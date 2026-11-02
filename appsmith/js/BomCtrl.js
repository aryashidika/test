// JSObject "BomCtrl" - page Specsheet: grid BOM (Custom Widget cwBomGrid) dan article di revisi.
// cwBomGrid mengirim satu event onAction dengan model.action = { type, ... }; onAction() menjalankan query
// yang sesuai lalu memuat ulang grid. Semua aturan dicek di DB (fn_bom_*, fn_rev_article_set, trg_lock_published).
// Query baca dijalankan dengan params lewat load() / reload().
// R4: kolom Material = induk × thickness; sel warna tanpa Material Code = kuning -> Daftarkan (cwVariantForm di
// mdlVarianBaru) · + Supplier baru (cwSupplierForm di mdlSupplierBaru).
// R16: "+ New material" (mdlMaterialBaru / cwMaterialForm, induk baru tanpa kode, cari nama mirip dulu). Thickness baru = baris
// baru, sel kuning. Sel kuning juga kuning di Export Excel (SpecExportCtrl) supaya kode yang harus diminta jelas.
// R12 (T62): grid hanya menampilkan baris revisi yang dibuka; pemuatan yang tersalip dimuat ulang (fetch()).
// R20: "Use KODE in the specsheet" di modal Register (kode sudah dipakai varian lain) = a_bom_use_variant (fn_bom_use_variant):
// sel memakai varian itu, sel kuning yang sama di semua draft ikut pindah. Material Code hanya diketik di Register.
// R20 bagian 5: tombol ✎ di sel Material (action editMaterial) = Edit Material (nama, kategori, UoM, Process, status) di modal
// yang sama (mdlMaterialBaru, mode edit, q_material_edit + a_material_update); berlaku untuk master, jadi semua draft ikut.
export default {
	okKey: 0,        // naik setelah tambah baris / subkomponen berhasil -> cwBomGrid mengosongkan form
	busyCount: 0,
	loadGen: 0,      // R12: nomor pemuatan grid terakhir yang dimulai
	doneGen: 0,      // R12: nomor pemuatan grid terbaru yang sudah selesai
	doneSeq: 0,      // seq aksi grid terakhir yang selesai -> ack ke cwBomGrid (antrean aksi)
	running: false,
	message: null,   // { type, text } ditampilkan di atas grid
	// R4: modal Daftarkan varian (sel kuning) & + Supplier baru
	varKey: 0, varBusy: false, varMsg: null, varCtx: null, varHint: null, varLookupSeq: 0, varSuggest: null, varSuggestSeq: 0,
	supKey: 0, supBusy: false, supMsg: null, similar: [], similarFor: '', similarSeq: 0,
	matKey: 0, matBusy: false, matMsg: null, matForm: { name: '', category: '', uom: '' },
	matSimilar: [], matSimilarFor: '', matSimilarSeq: 0,
	matAdded: { key: 0, name: '' },   // R16: material baru tersimpan -> cwBomGrid melanjutkan baris yang menunggu
	matEdit: null,   // R20 bagian 5: baris q_material_edit saat modal dalam mode edit (null = + New material)
	statusOptions: [
		{ label: 'ACTIVE', value: 'ACTIVE' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	// ---- data ----
	articles() {
		return q_rev_articles.data || [];
	},

	activeArticles() {
		return this.articles().filter(a => a.rev_status === 'ACTIVE');
	},

	// Article season yang belum aktif di revisi (belum masuk atau di-drop) -> msArticleTambah
	addableOptions() {
		return this.articles().filter(a => a.rev_status !== 'ACTIVE').map(a => ({
			label: `${a.code} · ${a.colorway}${a.rev_status === 'DROPPED' ? ' (dropped)' : ''}`, value: a.id,
		}));
	},

	options() {
		const r = (q_bom_options.data && q_bom_options.data[0]) || {};
		const arr = v => (typeof v === 'string' ? JSON.parse(v || '[]') : (v || []));
		return {
			components: arr(r.components), materials: arr(r.materials), variants: arr(r.variants),
			suppliers: arr(r.suppliers), links: arr(r.links),
			categories: arr(r.categories), uoms: arr(r.uoms),   // R16: saran isian modal + New material
			usedDims: arr(r.used_dims),   // R20 bagian 7: dimension di baris specsheet aktif yang belum punya varian ACTIVE
		};
	},

	// R20 bagian 4: kode sel grid yang belum ada di q_bom_options (varian tersusun otomatis). Kode yang tetap tidak ada setelah
	// dimuat ulang (mis. varian INACTIVE yang masih terpasang) diingat, supaya tidak memuat ulang terus.
	codesChecked: [],
	hasNewCodes() {
		const known = new Set(this.options().variants.map(v => v.code).concat(this.codesChecked));
		const fresh = [];
		(q_bom_grid.data || []).forEach(l => {
			const c = typeof l.cell_codes === 'string' ? JSON.parse(l.cell_codes || '{}') : (l.cell_codes || {});
			Object.values(c).forEach(code => { if (code && !known.has(code) && !fresh.includes(code)) fresh.push(code); });
		});
		this.codesChecked = this.codesChecked.concat(fresh);
		return fresh.length > 0;
	},

	articleNote() {
		const r = SpecCtrl.revision();
		if (!r) return '';
		const label = a => (a.no_code ? `${a.code} ${a.colorway}` : a.code);   // R19: article tanpa nomor dikenali dari colorway
		const dropped = this.articles().filter(a => a.rev_status === 'DROPPED').map(label);
		const notIn = this.articles().filter(a => !a.rev_status).map(label);
		const parts = [`${this.activeArticles().length} active article(s)`];
		if (dropped.length) parts.push(`dropped: ${dropped.join(', ')}`);
		if (notIn.length && SpecCtrl.canEdit()) parts.push(`not in revision: ${notIn.join(', ')}`);
		return parts.join(' · ');
	},

	// ---- muat ----
	async load() {
		const what = ['articles'];
		if (SpecCtrl.editable()) what.push('options', 'colors');
		try {
			await this.fetch(what);
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
	},

	async reload(what) {
		try { await this.fetch(what); } catch (e) { /* abaikan */ }
	},

	// Grid + query tambahan (what: 'articles' | 'options' | 'colors') untuk revisi yang dibuka. R12 (T62): data query =
	// hasil yang SELESAI terakhir. Bila selama memuat revisi berganti, atau pemuatan yang lebih baru sudah selesai
	// duluan (respons ini menimpa data yang lebih baru), muat ulang untuk revisi yang dibuka sekarang.
	async fetch(what) {
		for (let i = 0; i < 3; i++) {
			const g = this.loadGen + 1;
			this.loadGen = g;
			const r = SpecCtrl.revision();
			const s = SpecCtrl.season();
			const rid = r ? r.id : '';
			const jobs = [q_bom_grid.run({ revision_id: rid })];
			if (what.includes('articles')) jobs.push(q_rev_articles.run({ revision_id: rid, specsheet_id: SpecCtrl.seasonId || '' }));
			if (what.includes('options')) jobs.push(q_bom_options.run());
			if (what.includes('colors')) jobs.push(q_season_colors.run({ season: s ? s.season : '' }));
			await Promise.all(jobs);
			// R20 bagian 4: sel mendapat kode tersusun otomatis (varian baru di DB) -> daftar varian / dimension grid ikut dimuat ulang
			if (!what.includes('options') && this.hasNewCodes()) await q_bom_options.run();
			const cur = SpecCtrl.revision();
			const stale = g < this.doneGen || (cur ? cur.id : '') !== rid;
			this.doneGen = Math.max(this.doneGen, g);
			if (!stale) return;
		}
	},

	// Baris grid milik revisi yang dibuka saja (R12, T62)
	gridLines() {
		const r = SpecCtrl.revision();
		return r ? (q_bom_grid.data || []).filter(l => l.revision_id === r.id) : [];
	},

	// Default model cwBomGrid
	gridModel() {
		const o = this.options();
		return {
			editable: SpecCtrl.editable() && !SpecCtrl.navBusy,
			articles: this.activeArticles().map(a => ({ id: a.id, code: a.code, colorway: a.colorway, no_code: !!a.no_code })),
			lines: this.gridLines(),
			components: o.components,
			materials: o.materials,
			variants: o.variants,
			usedDims: o.usedDims,
			suppliers: o.suppliers,
			links: o.links,
			colors: (q_season_colors.data || []).map(c => c.color),
			busy: this.busyCount > 0,
			message: this.message,
			okKey: this.okKey,
			doneSeq: this.doneSeq,
			canRegister: Auth.can('manage_master'),
			canAddSupplier: Auth.can('manage_master'),
			canAddMaterial: Auth.can('manage_master'),   // R16: tombol + New material
			matAdded: this.matAdded,
			dict: this.dictRes,                        // R22: hasil pencarian kamus ERP terakhir { seq, kind, q, items }
			emptyText: SpecCtrl.navBusy ? 'Loading…' : (SpecCtrl.revision() ? 'No BOM lines yet.' : ''),
		};
	},

	// R22: saran dari kamus ERP (material / Dimension / warna yang belum ada di app). Dicari ke server saat mengetik, maksimal 8
	// baris; hasil tambahan saja, gagal = diam. Event sendiri (onSearch) supaya tidak mengganggu antrean simpan (onAction).
	dictRes: null,
	async onSearch() {
		const s = (cwBomGrid.model || {}).search;   // baca dulu - model di-reset saat Default model berubah
		if (!s || !s.q) return;
		try {
			const rows = await q_dict_search.run({ kind: s.kind, q: s.q });
			this.dictRes = { seq: s.seq, kind: s.kind, q: s.q, items: (rows || []).map(r => ({ label: r.label, code: r.code })) };
		} catch (e) { /* saran kamus hanya tambahan */ }
	},

	// ---- aksi dari grid (event onAction) ----
	// Satu aksi sekali jalan. Setelah selesai (berhasil / gagal) + data dimuat ulang -> doneSeq = seq aksi (ack);
	// cwBomGrid baru mengirim aksi berikutnya setelah ack. Kiriman ulang dengan seq yang sudah selesai diabaikan.
	async onAction() {
		const a = (cwBomGrid.model || {}).action;   // baca dulu - model di-reset saat Default model berubah
		if (!a || !a.type) return;
		const s = Number(a.seq) || 0;
		if (s && s <= this.doneSeq) return;
		if (this.running) return;                   // cwBomGrid mengirim ulang bila belum di-ack
		const ack = () => { this.doneSeq = Math.max(this.doneSeq, s); };
		if (a.type === 'registerVariant') { ack(); return this.openRegister(a); }
		if (a.type === 'newSupplier') { ack(); return this.openNewSupplier(); }
		if (a.type === 'newMaterial') { ack(); return this.openNewMaterial(a); }
		if (a.type === 'editMaterial') { ack(); return this.openEditMaterial(a); }
		const r = SpecCtrl.revision();
		const actions = !r ? {} : {
			addLine: [a_bom_add_line, {
				revision_id: r.id, component_id: a.component_id, local_no: a.local_no, local_name: a.local_name,
				material_id: a.material_id, thickness: a.thickness || '', supplier_id: a.supplier_id, process: a.process,
				fill_color: a.fill_color || '',
			}, ['options', 'colors']],
			addSub: [a_bom_add_sub, {
				parent_id: a.parent_id, sub_name: a.sub_name, material_id: a.material_id, thickness: a.thickness || '',
				supplier_id: a.supplier_id, process: a.process,
			}, ['options']],
			replaceMaterial: [a_bom_replace_material, {
				line_id: a.line_id, material_id: a.material_id, thickness: a.thickness || '',
			}, ['options']],
			setSupplier: [a_bom_set_supplier, { line_id: a.line_id, supplier_id: a.supplier_id }, ['options']],
			setProcess: [a_bom_set_process, { line_id: a.line_id, process: a.process }, []],
			setCell: [a_cell_save, { line_id: a.line_id, article_id: a.article_id, color: a.color }, ['colors']],
			dropArticle: [a_rev_article_set, { revision_id: r.id, article_id: a.article_id, status: 'DROPPED' }, ['articles']],
			deleteLine: [a_bom_delete_line, { line_id: a.line_id }, ['colors']],
			// R19: ganti komponen baris ini (+ subkomponennya) ke komponen master lain
			changeComponent: [a_bom_change_component, { line_id: a.line_id, component_id: a.component_id }, []],
		};
		const def = actions[a.type];
		if (!def) { ack(); return; }
		this.running = true;
		this.busyCount = this.busyCount + 1;
		try {
			let failed = false;
			try {
				await def[0].run(def[1]);
			} catch (e) {
				const msg = e && e.message;
				if (Util.isSessionError(msg)) {
					await removeValue('token');
					showAlert('Session expired. Please log in again.', 'warning');
					navigateTo('Login');
					return;
				}
				this.message = { type: 'error', text: Util.cleanError(msg) };
				failed = true;
			}
			if (!failed) {
				this.message = null;
				if (a.type === 'addLine' || a.type === 'addSub') this.okKey = this.okKey + 1;
			}
			await this.reload(failed ? [] : def[2]);   // gagal -> kembalikan grid ke isi DB
		} finally {
			this.busyCount = Math.max(0, this.busyCount - 1);
			this.running = false;
			ack();
		}
	},

	// R20: ringkasan hasil fn_bom_use_variant
	useText(rows) {
		let j = rows && rows[0] ? rows[0].result : null;
		if (typeof j === 'string') {
			try { j = JSON.parse(j); } catch (e) { j = null; }
		}
		if (!j) return 'Variant used.';
		const n = Number(j.cells) || 0;
		return (j.registered ? `New variant ${j.code} registered. ` : '')   // R20 bagian 4: kode purchasing belum terdaftar
			+ `${j.code} (${j.label}) used in ${n} cell${n === 1 ? '' : 's'}.`
			+ (Number(j.revisions) ? ` ${j.revisions} other draft${Number(j.revisions) === 1 ? '' : 's'} updated too.` : '')
			+ (Number(j.skipped) ? ` ${j.skipped} yellow cell${Number(j.skipped) === 1 ? '' : 's'} in other drafts stayed yellow (that line already has another color there).` : '')
			+ (j.inactivated ? ` Material ${j.inactivated} is no longer used in drafts and is now INACTIVE.` : '');
	},

	// ---- Daftarkan varian dari sel kuning (mdlVarianBaru / cwVariantForm) ----
	openRegister(a) {
		this.varCtx = {
			material_id: a.material_id, material_name: a.material_name, uom: a.uom,
			thickness: a.thickness || '', color: a.color,
			line_id: a.line_id, article_id: a.article_id,   // R20: untuk tombol "Use this variant"
		};
		this.varHint = null;
		this.varSuggest = null;
		this.varBusy = false;
		this.varMsg = null;
		this.varKey = this.varKey + 1;
		showModal('mdlVarianBaru');
	},

	variantFormModel() {
		const c = this.varCtx || {};
		return {
			key: this.varKey,
			mode: 'add',
			materialLabel: c.material_name ? `${c.material_name} (${c.uom || '-'}) · ${c.thickness || 'no dimension'}` : '',
			form: { code: '', color: c.color, thickness: c.thickness, status: 'ACTIVE' },
			fixed: { color: c.color, thickness: c.thickness },
			statusOptions: this.statusOptions,
			hint: this.varHint,
			suggest: this.varSuggest,    // R9: usulan Material Code
			canUse: !!(c.line_id && c.article_id),   // R20: tombol "Use this variant"
			busy: this.varBusy,
			message: this.varMsg,
		};
	},

	// cwVariantForm onLookup: arti bagian kode yang sudah tercatat di pabrik ini + masalah aturan ketat (R20)
	async lookupVariantCode() {
		const m = cwVariantForm.model || {};
		if (m.lookupKind === 'suggest') return this.suggestVariantCode();
		if (m.lookupKind === 'use') return this.useFromRegister(m.useId, m.useCode);
		if (m.lookupKind === 'useCode') return this.useFromRegister(null, m.useCode);
		const code = String(m.lookupCode || '');
		const color = String(m.lookupColor || '');
		const thickness = String(m.lookupThickness || '');
		const c = this.varCtx || {};
		const seq = this.varLookupSeq + 1;
		this.varLookupSeq = seq;
		try {
			// R20 bagian 4: + kode purchasing belum terdaftar yang terbaca sebagai material / dimension / warna lain (tombol Use)
			const [rows, dec] = await Promise.all([
				q_code_hint.run({ material_id: c.material_id, code, exclude_id: '', color, thickness }),
				c.line_id ? q_code_decode.run({ material_id: c.material_id, code, color, thickness }).catch(() => []) : [],
			]);
			if (seq !== this.varLookupSeq) return;
			this.varHint = rows && rows[0]
				? Object.assign({ for: `${code}|${color}|${thickness}`, decode: (dec && dec[0]) || null }, rows[0]) : null;
		} catch (e) {
			/* hanya bantuan - aturan final di DB */
		}
	},

	// R20: modal Register -> kode sudah dipakai varian lain -> sel ini (dan sel kuning yang sama di semua draft) memakainya.
	// R20 bagian 4: variantId kosong = kode belum terdaftar yang terbaca (a_bom_use_code mendaftarkan varian itu dulu)
	async useFromRegister(variantId, code) {
		const c = this.varCtx || {};
		if ((!variantId && !code) || !c.line_id || !c.article_id) return;
		this.varMsg = null;
		this.varBusy = true;
		let res = null;
		try {
			res = variantId
				? await a_bom_use_variant.run({ line_id: c.line_id, article_id: c.article_id, variant_id: variantId })
				: await a_bom_use_code.run({ line_id: c.line_id, article_id: c.article_id, code });
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlVarianBaru');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.varMsg = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.varBusy = false;
		}
		closeModal('mdlVarianBaru');
		this.message = { type: 'success', text: this.useText(res) };
		showAlert(`${code} used.`, 'success');
		await this.reload(['options', 'colors']);
	},

	// R9 cwVariantForm onLookup (lookupKind 'suggest'): usulan Material Code dari warna + thickness
	async suggestVariantCode() {
		const m = cwVariantForm.model || {};
		const color = String(m.suggestColor || '');
		const thickness = String(m.suggestThickness || '');
		const seq = this.varSuggestSeq + 1;
		this.varSuggestSeq = seq;
		try {
			const c = this.varCtx || {};
			const rows = await q_code_suggest.run({ material_id: c.material_id, color, thickness });
			if (seq !== this.varSuggestSeq) return;
			this.varSuggest = Object.assign({ for: `${color}|${thickness}` }, (rows && rows[0]) || {});
		} catch (e) {
			/* hanya bantuan isi otomatis - kode tetap diketik/diperiksa user */
		}
	},

	async saveVariant() {
		const f = cwVariantForm.model || {};
		const c = this.varCtx || {};
		const code = String(f.code || '').trim();
		if (!code) {
			this.varMsg = { type: 'error', text: 'Material Code is required.' };
			return;
		}
		this.varMsg = null;
		this.varBusy = true;
		try {
			await a_variant_save.run({
				id: '', material_id: c.material_id, code, color: c.color, thickness: c.thickness, status: 'ACTIVE',
			});
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlVarianBaru');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.varMsg = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.varBusy = false;
		}
		closeModal('mdlVarianBaru');
		showAlert(`Variant ${code.toUpperCase()} registered. Cell ${c.color} linked automatically.`, 'success');
		await this.reload(['options']);
	},

	// ---- + Supplier baru (mdlSupplierBaru / cwSupplierForm) ----
	openNewSupplier() {
		this.similar = [];
		this.similarFor = '';
		this.supBusy = false;
		this.supMsg = null;
		this.supKey = this.supKey + 1;
		showModal('mdlSupplierBaru');
	},

	supplierFormModel() {
		return {
			key: this.supKey,
			mode: 'add',
			form: { id: null, name: '', status: 'ACTIVE' },
			statusOptions: this.statusOptions,
			similar: this.similar,
			similarFor: this.similarFor,
			busy: this.supBusy,
			message: this.supMsg,
		};
	},

	// cwSupplierForm onSearch: nama mirip ("cari dulu, baru buat")
	async searchSimilar() {
		const text = String((cwSupplierForm.model || {}).similarQuery || '').trim();
		const seq = this.similarSeq + 1;
		this.similarSeq = seq;
		if (text.length < 2) {
			this.similar = [];
			this.similarFor = text;
			return;
		}
		try {
			const rows = await q_similar.run({ kind: 'SUPPLIER', text, exclude_id: '' });
			if (seq !== this.similarSeq) return;
			this.similar = rows || [];
			this.similarFor = text;
		} catch (e) {
			/* daftar mirip hanya bantuan */
		}
	},

	async saveSupplier() {
		const name = String((cwSupplierForm.model || {}).name || '').trim();
		if (!name) {
			this.supMsg = { type: 'error', text: 'Supplier name is required.' };
			return;
		}
		this.supMsg = null;
		this.supBusy = true;
		try {
			await a_supplier_insert.run({ name });
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlSupplierBaru');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.supMsg = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.supBusy = false;
		}
		closeModal('mdlSupplierBaru');
		showAlert(`Supplier ${name.toUpperCase()} added. Type its name in the Supplier column.`, 'success');
		await this.reload(['options']);
	},

	// ---- + New material (mdlMaterialBaru / cwMaterialForm): induk baru (nama, kategori, UoM), tanpa kode ----
	openNewMaterial(a) {
		this.matEdit = null;
		this.matForm = { name: String((a && a.name) || ''), category: '', uom: '', is_process: false };
		this.matSimilar = [];
		this.matSimilarFor = '';
		this.matBusy = false;
		this.matMsg = null;
		this.matKey = this.matKey + 1;
		showModal('mdlMaterialBaru');
	},

	materialFormModel() {
		const o = this.options();
		const e = this.matEdit;
		if (e) {
			return {
				key: this.matKey,
				mode: 'edit',
				form: this.matForm,
				categories: o.categories,
				uoms: o.uoms,
				statusOptions: this.statusOptions,
				// R19: tanda Process terkunci setelah dipakai dokumen terbit; dipasang hanya bila belum punya varian (aturan di DB)
				processLocked: !!e.used_published || (!e.is_process && Number(e.variant_count) > 0),
				processNote: e.used_published ? 'Process cannot be changed: this material is used in a published specsheet / CBD.'
					: 'This material has variants (Material Codes), so it cannot be a Process material.',
				canIdentity: true,
				canPriceMethod: Auth.can('manage_price'),
				canStatus: true,
				similar: this.matSimilar,
				similarFor: this.matSimilarFor,
				busy: this.matBusy,
				message: this.matMsg,
			};
		}
		return {
			key: this.matKey,
			mode: 'add',
			form: this.matForm,
			categories: o.categories,
			uoms: o.uoms,
			statusOptions: this.statusOptions,
			canIdentity: true,
			canPriceMethod: false,
			canStatus: false,
			similar: this.matSimilar,
			similarFor: this.matSimilarFor,
			busy: this.matBusy,
			message: this.matMsg,
		};
	},

	// cwMaterialForm onSearch: nama mirip di pabrik user ("cari dulu, baru buat")
	async searchSimilarMaterial() {
		const text = String((cwMaterialForm.model || {}).similarQuery || '').trim();
		const seq = this.matSimilarSeq + 1;
		this.matSimilarSeq = seq;
		if (text.length < 2) {
			this.matSimilar = [];
			this.matSimilarFor = text;
			return;
		}
		try {
			const rows = await q_similar.run({ kind: 'MATERIAL', text, exclude_id: this.matEdit ? this.matEdit.id : '' });
			if (seq !== this.matSimilarSeq) return;
			// R16: DB hanya menemukan nama yang memuat teks (tanpa tanda baca); typo / urutan kata dicari di sini dari master pabrik
			const list = (rows || []).slice();
			const self = this.matEdit ? String(this.matEdit.name).toUpperCase() : null;
			this.nearMaterialNames(text).filter(n => n.toUpperCase() !== self).forEach(n => {
				if (!list.some(r => String(r.label).toUpperCase() === n.toUpperCase())) list.push({ ref_id: n, label: n, info: 'looks similar (typo?)' });
			});
			this.matSimilar = list;
			this.matSimilarFor = text;
		} catch (e) {
			/* daftar mirip hanya bantuan */
		}
	},

	// Nama material pabrik yang mirip teks. R20 (= cwBomGrid nearName): angka harus sama (FOAM 50 KG bukan FOAM 60 KG);
	// hanya beda spasi / tanda baca, kata sama urutan lain, typo 1 huruf di kata 5 huruf ke atas, atau nama memuat ketikan.
	nearMaterialNames(text) {
		const tight = x => String(x ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
		const nums = x => (String(x ?? '').replace(/,/g, '.').match(/\d+(?:\.\d+)?/g) || []).join(' ');
		const words = x => String(x ?? '').toLowerCase().replace(/\d+(?:[.,]\d+)?/g, ' ').replace(/[^a-z]+/g, ' ').trim().split(' ').filter(w => w);
		const q = tight(text);
		if (q.length < 3) return [];
		const dist = (a, b) => {
			let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
			for (let i = 1; i <= a.length; i++) {
				const cur = [i];
				for (let j = 1; j <= b.length; j++) {
					cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
				}
				prev = cur;
			}
			return prev[b.length];
		};
		const near = (a, b) => {
			if (nums(a) !== nums(b)) return 0;
			const ta = tight(a);
			const tb = tight(b);
			if (!ta || !tb) return 0;
			if (ta === tb) return 1;
			const wa = words(a);
			const wb = words(b);
			if (wa.length && wa.slice().sort().join(' ') === wb.slice().sort().join(' ')) return 2;
			if (wa.length && wa.length === wb.length
				&& wa.every((w, i) => w === wb[i] || (Math.min(w.length, wb[i].length) >= 5 && dist(w, wb[i]) === 1))) return 3;
			if (ta.length >= 4 && tb.includes(ta)) return 4;
			return 0;
		};
		const names = [...new Set((this.options().materials || []).map(x => x.name))];
		return names
			.map(n => ({ n, d: near(text, n) }))
			.filter(x => x.d > 0)
			.sort((a, b) => a.d - b.d || a.n.localeCompare(b.n))
			.slice(0, 5)
			.map(x => x.n);
	},

	// ---- R20 bagian 5: ✎ di sel Material -> Edit Material (master: berlaku di semua specsheet / CBD draft) ----
	async openEditMaterial(a) {
		let row;
		try {
			row = ((await q_material_edit.run({ id: a.material_id })) || [])[0];
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
			return;
		}
		if (!row) {
			showAlert('Material not found.', 'error');
			return;
		}
		this.matEdit = row;
		this.matForm = {
			name: row.name, category: row.category, uom: row.uom, price_method: row.price_method, status: row.status,
			is_process: !!row.is_process,
		};
		this.matSimilar = [];
		this.matSimilarFor = '';
		this.matBusy = false;
		const used = [];
		if (Number(row.draft_specs) > 0) used.push(`${row.draft_specs} draft specsheet${Number(row.draft_specs) > 1 ? 's' : ''}`);
		if (Number(row.draft_cbds) > 0) used.push(`${row.draft_cbds} draft CBD${Number(row.draft_cbds) > 1 ? 's' : ''}`);
		this.matMsg = { type: 'info', text: 'Changes apply to Master Material' + (used.length ? `, so also to ${used.join(' and ')} using it.` : '.') };
		this.matKey = this.matKey + 1;
		showModal('mdlMaterialBaru');
	},

	async saveEditedMaterial(m) {
		const e = this.matEdit;
		const data = {
			id: e.id,
			name: m.name,
			category: m.category,
			uom: m.uom,
			status: m.status || e.status,
			price_method: m.price_method || e.price_method,
			is_process: m.is_process === true,
		};
		this.matMsg = null;
		this.matBusy = true;
		try {
			await a_material_update.run(data);
		} catch (err) {
			const msg = err && err.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlMaterialBaru');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.matMsg = { type: 'error', text: Util.cleanError(msg) };   // mis. sudah terbit, nama + UoM sudah ada
			return;
		} finally {
			this.matBusy = false;
		}
		closeModal('mdlMaterialBaru');
		this.matEdit = null;
		showAlert('Material saved.', 'success');
		await this.reload(['options']);
	},

	async saveMaterial() {
		const m = cwMaterialForm.model || {};     // baca dulu - model di-reset saat Default model berubah
		if (this.matEdit) return this.saveEditedMaterial(m);
		const data = { name: m.name, category: m.category, uom: m.uom, is_process: m.is_process === true };   // R19: Process
		if (!data.name || !data.category || !data.uom) {
			this.matMsg = { type: 'error', text: 'Fill in category, name, and Mea.' };
			return;
		}
		this.matMsg = null;
		this.matBusy = true;
		try {
			await a_material_add.run(data);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlMaterialBaru');
				await removeValue('token');
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.matMsg = { type: 'error', text: Util.cleanError(msg) };   // mis. nama + UoM sudah ada
			return;
		} finally {
			this.matBusy = false;
		}
		closeModal('mdlMaterialBaru');
		const name = String(data.name).trim().replace(/\s+/g, ' ').toUpperCase();
		showAlert(`Material ${name} added.`, 'success');
		await this.reload(['options']);
		// R16: sesudah daftar material dimuat ulang -> cwBomGrid mengulang aksi baris yang menunggu (tambah / sub / ganti)
		this.matAdded = { key: this.matAdded.key + 1, name };
	},

	// Tombol "Masukkan ke Revisi": article terpilih di msArticleTambah jadi ACTIVE (baru masuk / aktif lagi)
	async addArticles() {
		const r = SpecCtrl.revision();
		const ids = msArticleTambah.selectedOptionValues || [];
		if (!r || !ids.length) {
			showAlert('Select an article first.', 'warning');
			return;
		}
		for (const id of ids) {
			if (!await Util.run(a_rev_article_set, { revision_id: r.id, article_id: id, status: 'ACTIVE' })) break;
		}
		resetWidget('msArticleTambah');
		showAlert('Article added to the revision.', 'success');
		await this.reload(['articles']);
	},
}
