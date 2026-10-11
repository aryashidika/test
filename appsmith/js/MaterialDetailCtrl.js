export default {
	// R2: material INDUK + tab Varian (Material Code + warna + thickness teks ERP, satu per satu — R2b) + tab Supplier.
	// R3: tab Harga = harga per varian × supplier (q_prices dari v_material_price, termasuk baris BELUM ADA HARGA).
	//     Vendor CBD mengajukan (banyak varian sekaligus) / menyalin harga; Manager Costing setujui / tolak / akhiri.
	// ---- state form (Default model widget) ----
	matKey: 0, matBusy: false, matMsg: null,
	linkKey: 0, linkBusy: false, linkMsg: null, linkIsNew: true, linkForm: {},
	varKey: 0, varBusy: false, varMsg: null, varIsNew: true, varForm: {}, varHint: null, varLookupSeq: 0,
	priceKey: 0, priceBusy: false, priceMsg: null, priceMode: 'propose', pricePreset: {},
	rejectKey: 0, rejectBusy: false, rejectMsg: null, rejectRow: null,

	statusOptions: [
		{ label: 'ACTIVE', value: 'ACTIVE' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	// ---- data ----
	material() {
		return (q_material.data && q_material.data[0]) || null;
	},

	materialLabel() {
		const m = this.material();
		return m ? `${m.name} (${m.uom})` : '';
	},

	meta() {
		const r = (q_material_meta.data && q_material_meta.data[0]) || {};
		const split = s => String(s || '').split('|').filter(x => x);
		return { categories: split(r.categories), uoms: split(r.uoms) };
	},

	links() {
		return q_links.data || [];
	},

	variants() {
		return q_variants.data || [];
	},

	prices() {
		return this.canViewPrice() ? (q_prices.data || []) : [];
	},

	// Tabel harga. Tanpa "Tampilkan riwayat": sembunyikan RIWAYAT dan usulan DITOLAK yang lebih lama dari 30 hari.
	pricesShown() {
		const history = swHargaRiwayat.isSwitchedOn === true;
		const recent = p => p.decided_at && moment().diff(moment(p.decided_at), 'days') <= 30;
		return this.prices().filter(p => history || (p.state !== 'RIWAYAT' && (p.state !== 'DITOLAK' || recent(p))));
	},

	// Warna kolom Keterangan di tblPrices
	stateColor(state) {
		return {
			BERLAKU: '#16a34a', 'AKAN BERLAKU': '#d97706', 'MENUNGGU APPROVAL': '#d97706', DITOLAK: '#dc2626',
			'BELUM ADA HARGA': '#dc2626',
		}[state] || '#6b7280';
	},

	stateText(row) {
		if (row.state === 'DITOLAK') return `DITOLAK: ${row.reject_reason || '-'}`;
		return row.state;
	},

	// ---- izin (tampilan saja) ----
	canViewPrice() { return Auth.can('view_price'); },
	canManagePrice() { return Auth.can('manage_price'); },
	canManageMaster() { return Auth.can('manage_master'); },
	canApprovePrice() { return Auth.can('approve_price'); },
	canLink() { return this.canManageMaster(); },
	canEditMaterial() { return this.canManageMaster() || this.canManagePrice(); },
	canAddPrice() {
		const m = this.material();
		return this.canManagePrice() && !!m && m.status === 'ACTIVE' && m.price_method === 'CATALOG'
			&& this.activeLinks().length > 0 && this.activeVariants().length > 0;
	},

	// ---- teks info (Text widget merender HTML) ----
	esc(v) {
		return String(v ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
	},

	infoText() {
		const m = this.material();
		if (!m) return q_material.isLoading ? 'Memuat…' : 'Material tidak ditemukan. Buka dari Master Material.';
		const e = v => this.esc(v);
		const method = m.price_method === 'QUOTATION' ? 'Quotation (harga per CBD)' : 'Catalog (harga master)';
		return `<b style="font-size:16px">${e(m.name)}</b> <span style="color:#6b7280">· ${e(m.factory_name)}</span><br>`
			+ `Kategori: ${e(m.category)} · Mea: ${e(m.uom)} · ${e(m.variant_count)} varian<br>`
			+ `Status: <b style="color:${Util.statusColor(m.status)}">${e(m.status)}</b>`
			+ (this.canViewPrice() ? ` · Metode harga: ${method}` : '');
	},

	priceNote() {
		const m = this.material();
		if (!m || !this.canViewPrice()) return '';
		if (m.price_method === 'QUOTATION') return 'Material Quotation: tidak ada harga master — harga diisi per CBD.';
		const all = this.prices();
		const n = state => all.filter(p => p.state === state).length;
		const parts = [`Harga per varian × supplier. ${n('BERLAKU')} berlaku`];
		if (n('MENUNGGU APPROVAL')) parts.push(`${n('MENUNGGU APPROVAL')} menunggu persetujuan Manager Costing`);
		if (n('BELUM ADA HARGA')) parts.push(`${n('BELUM ADA HARGA')} pasangan belum ada harga`);
		return parts.join(' · ') + '.';
	},

	fmtPrice(v) {
		if (v === null || v === undefined || v === '') return '-';
		return Number(v).toLocaleString('id-ID', { minimumFractionDigits: 0, maximumFractionDigits: 4 });
	},

	// ---- helper simpan dari form Custom Widget ----
	async runForm(query, params, setMsg, setBusy, modal) {
		setMsg(null);
		setBusy(true);
		try {
			await query.run(params);
			return true;
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal(modal);
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return false;
			}
			setMsg({ type: 'error', text: Util.cleanError(msg) });
			return false;
		} finally {
			setBusy(false);
		}
	},

	async refresh(queries) {
		for (const q of queries) {
			try { await q.run(); } catch (e) { /* abaikan */ }
		}
	},

	// ---- material ----
	openEditMaterial() {
		this.matBusy = false;
		this.matMsg = null;
		this.matKey = this.matKey + 1;
		showModal('mdlMaterial');
	},

	materialFormModel() {
		const m = this.material() || {};
		const meta = this.meta();
		return {
			key: this.matKey,
			mode: 'edit',
			form: {
				name: m.name, category: m.category, uom: m.uom, price_method: m.price_method, status: m.status,
			},
			categories: meta.categories, uoms: meta.uoms,
			statusOptions: this.statusOptions,
			canIdentity: this.canManageMaster(),
			canStatus: this.canManageMaster(),
			canPriceMethod: this.canManagePrice(),
			similar: [],
			busy: this.matBusy,
			message: this.matMsg,
		};
	},

	async saveMaterial() {
		const f = cwMaterialForm.model || {};
		const params = {
			id: appsmith.URL.queryParams.id, name: f.name, category: f.category,
			uom: f.uom, status: f.status, price_method: f.price_method,
		};
		const ok = await this.runForm(a_material_update, params,
			v => { this.matMsg = v; }, v => { this.matBusy = v; }, 'mdlMaterial');
		if (!ok) return;
		closeModal('mdlMaterial');
		showAlert('Material disimpan.', 'success');
		await this.refresh([q_material, q_material_meta]);
	},

	// ---- varian (R2b: satu baris seperti ERP) ----
	openAddVariant() {
		this.varIsNew = true;
		this.varForm = {};
		this.varHint = null;
		this.varBusy = false;
		this.varMsg = null;
		this.varKey = this.varKey + 1;
		showModal('mdlVarian');
	},

	// Ambil baris asli dari q_variants: baris tabel berisi nilai tampilan.
	openEditVariant(row) {
		const v = this.variants().find(x => x.id === row.id) || row;
		this.varIsNew = false;
		this.varForm = { id: v.id, code: v.code, color: v.color, thickness: v.thickness, status: v.status };
		this.varHint = null;
		this.varBusy = false;
		this.varMsg = null;
		this.varKey = this.varKey + 1;
		showModal('mdlVarian');
	},

	variantFormModel() {
		return {
			key: this.varKey,
			mode: this.varIsNew ? 'add' : 'edit',
			materialLabel: this.materialLabel(),
			form: this.varForm,
			statusOptions: this.statusOptions,
			hint: this.varHint,
			busy: this.varBusy,
			message: this.varMsg,
		};
	},

	// cwVariantForm onLookup: arti 3 tengah (thickness) / 3 akhir (warna) kode yang sudah tercatat di pabrik ini
	async lookupVariantCode() {
		const code = String((cwVariantForm.model || {}).lookupCode || '');
		const seq = this.varLookupSeq + 1;
		this.varLookupSeq = seq;
		try {
			const rows = await q_code_hint.run({
				material_id: appsmith.URL.queryParams.id, code, exclude_id: this.varIsNew ? '' : this.varForm.id,
			});
			if (seq !== this.varLookupSeq) return;
			this.varHint = (rows && rows[0]) || null;
		} catch (e) {
			/* hanya bantuan isi otomatis — aturan final tetap di DB */
		}
	},

	async saveVariant() {
		const f = cwVariantForm.model || {};
		const isNew = this.varIsNew;
		const params = {
			id: isNew ? '' : this.varForm.id, material_id: appsmith.URL.queryParams.id,
			code: f.code, color: f.color, thickness: f.thickness, status: isNew ? 'ACTIVE' : f.status,
		};
		const ok = await this.runForm(a_variant_save, params,
			v => { this.varMsg = v; }, v => { this.varBusy = v; }, 'mdlVarian');
		if (!ok) return;
		await this.refresh([q_variants, q_material]);
		if (isNew && f.again) {
			// "Simpan & tambah lagi": modal tetap terbuka, form dikosongkan
			this.varForm = {};
			this.varHint = null;
			this.varMsg = { type: 'info', text: `Varian ${f.code} tersimpan. Isi varian berikutnya.` };
			this.varKey = this.varKey + 1;
			return;
		}
		closeModal('mdlVarian');
		showAlert(isNew ? `Varian ${f.code} ditambahkan.` : 'Varian disimpan.', 'success');
	},

	// ---- supplier material ----
	// Daftar supplier dimuat ulang setiap modal dibuka (supplier bisa baru ditambah di jendela lain).
	async openAddLink() {
		try { await q_link_supplier_options.run(); } catch (e) { /* daftar lama tetap dipakai */ }
		this.linkIsNew = true;
		this.linkForm = { supplier_id: '', is_preferred: this.links().length === 0, status: 'ACTIVE' };
		this.linkBusy = false;
		this.linkMsg = null;
		this.linkKey = this.linkKey + 1;
		showModal('mdlLink');
	},

	openEditLink(row) {
		this.linkIsNew = false;
		this.linkForm = {
			id: row.id, supplier_id: row.supplier_id, supplier_name: row.supplier_name,
			is_preferred: row.is_preferred, status: row.status,
		};
		this.linkBusy = false;
		this.linkMsg = null;
		this.linkKey = this.linkKey + 1;
		showModal('mdlLink');
	},

	linkFormModel() {
		return {
			key: this.linkKey,
			mode: this.linkIsNew ? 'add' : 'edit',
			form: this.linkForm,
			materialLabel: this.materialLabel(),
			supplierOptions: (q_link_supplier_options.data || []).map(s => ({ label: s.name, value: s.id })),
			statusOptions: this.statusOptions,
			canLink: this.canLink(),
			canStatus: this.canManageMaster(),
			busy: this.linkBusy,
			message: this.linkMsg,
		};
	},

	async saveLink() {
		const f = cwLinkForm.model || {};
		const params = {
			link_id: this.linkIsNew ? null : this.linkForm.id,
			material_id: appsmith.URL.queryParams.id,
			supplier_id: this.linkIsNew ? f.supplier_id : this.linkForm.supplier_id,
			is_preferred: !!f.is_preferred,
			status: this.linkIsNew ? 'ACTIVE' : f.status,
		};
		const ok = await this.runForm(a_link_save, params,
			v => { this.linkMsg = v; }, v => { this.linkBusy = v; }, 'mdlLink');
		if (!ok) return;
		closeModal('mdlLink');
		showAlert(this.linkIsNew ? 'Supplier material ditambahkan.' : 'Supplier material disimpan.', 'success');
		await this.refresh([q_links, q_link_supplier_options, q_material]);
	},

	// ---- harga (R3: varian × supplier, diajukan Vendor CBD, disetujui Manager Costing) ----
	activeLinks() {
		return this.links().filter(l => l.status === 'ACTIVE' && l.supplier_status === 'ACTIVE');
	},

	activeVariants() {
		return this.variants().filter(v => v.status === 'ACTIVE');
	},

	// Tombol Ajukan di baris tabel: varian + supplier masih aktif
	canProposeRow(row) {
		return this.canAddPrice() && !!row && row.state !== 'MENUNGGU APPROVAL' && row.state !== 'RIWAYAT'
			&& this.activeLinks().some(l => l.id === row.link_id) && this.activeVariants().some(v => v.id === row.variant_id);
	},

	canEndRow(row) {
		return this.canApprovePrice() && !!row && (row.state === 'BERLAKU' || row.state === 'AKAN BERLAKU') && !row.valid_to;
	},

	canDecideRow(row) {
		return this.canApprovePrice() && !!row && row.state === 'MENUNGGU APPROVAL';
	},

	canCancelRow(row) {
		return this.canManagePrice() && !!row && row.state === 'MENUNGGU APPROVAL';
	},

	// Salin harga: ada varian dengan harga berlaku + minimal satu varian aktif lain
	canCopyPrice() {
		return this.canAddPrice() && this.activeVariants().length >= 2 && this.prices().some(p => p.state === 'BERLAKU');
	},

	openProposePrice(row) {
		const link = row && this.activeLinks().find(l => l.id === row.link_id);
		this.priceMode = 'propose';
		this.pricePreset = {
			link_id: link ? link.id : (this.activeLinks().length === 1 ? this.activeLinks()[0].id : ''),
			variant_ids: row && row.variant_id ? [row.variant_id] : [],
		};
		this.priceBusy = false;
		this.priceMsg = null;
		this.priceKey = this.priceKey + 1;
		showModal('mdlHarga');
	},

	openCopyPrice() {
		this.priceMode = 'copy';
		this.pricePreset = {};
		this.priceBusy = false;
		this.priceMsg = null;
		this.priceKey = this.priceKey + 1;
		showModal('mdlHarga');
	},

	priceFormModel() {
		return {
			key: this.priceKey,
			mode: this.priceMode,
			materialLabel: this.materialLabel(),
			links: this.activeLinks().map(l => ({ value: l.id, label: l.supplier_name })),
			variants: this.activeVariants().map(v => ({
				id: v.id, code: v.code, color: v.color, thickness_label: v.thickness_label,
			})),
			prices: this.prices().filter(p => ['BERLAKU', 'AKAN BERLAKU', 'MENUNGGU APPROVAL'].includes(p.state)).map(p => ({
				link_id: p.link_id, variant_id: p.variant_id, supplier_name: p.supplier_name,
				price: p.price, currency: p.currency, valid_from: p.valid_from, state: p.state,
			})),
			preset: this.pricePreset,
			today: moment().utcOffset(7).format('YYYY-MM-DD'),
			busy: this.priceBusy,
			message: this.priceMsg,
		};
	},

	async savePrice() {
		const f = cwPriceForm.model || {};
		const ids = Array.isArray(f.variant_ids) ? f.variant_ids : [];
		const copy = f.mode === 'copy';
		if (!ids.length || !f.valid_from || (copy ? !f.source_id : (!f.link_id || !f.price || !f.currency))) {
			this.priceMsg = { type: 'error', text: 'Lengkapi isian yang wajib.' };
			return;
		}
		const query = copy ? a_price_copy : a_price_propose;
		const params = copy
			? { source_id: f.source_id, variant_ids: JSON.stringify(ids), valid_from: f.valid_from, reference: f.reference }
			: {
				link_id: f.link_id, variant_ids: JSON.stringify(ids), price: f.price, currency: f.currency,
				valid_from: f.valid_from, reference: f.reference,
			};
		const ok = await this.runForm(query, params,
			v => { this.priceMsg = v; }, v => { this.priceBusy = v; }, 'mdlHarga');
		if (!ok) return;
		const result = (query.data && query.data[0]) || {};
		closeModal('mdlHarga');
		if (copy) {
			showAlert(`${result.created || 0} harga diajukan, menunggu persetujuan Manager Costing.`
				+ (result.skipped ? ` Dilewati: ${result.skipped}` : ''), result.skipped ? 'warning' : 'success');
		} else {
			showAlert(`${ids.length} harga diajukan, menunggu persetujuan Manager Costing.`, 'success');
		}
		await this.refresh([q_prices, q_material]);
	},

	// Query a_price_end memakai "Request confirmation before running" = ON
	endPrice(row) {
		return Util.run(a_price_end, { id: row.id }, 'Harga diakhiri per hari ini.', [q_prices, q_material]);
	},

	approvePrice(row) {
		return Util.run(a_price_decide, { ids: JSON.stringify([row.id]), decision: 'APPROVE', reason: '' },
			'Harga disetujui dan berlaku sesuai tanggalnya.', [q_prices, q_material]);
	},

	// Query a_price_cancel memakai "Request confirmation before running" = ON
	cancelPrice(row) {
		return Util.run(a_price_cancel, { id: row.id }, 'Usulan harga dibatalkan.', [q_prices, q_material]);
	},

	// Ambil baris asli dari q_prices: baris dari tabel berisi nilai tampilan ("2,49"), bukan angka -> NaN.
	openReject(row) {
		this.rejectRow = this.prices().find(p => p.row_key === row.row_key) || row;
		this.rejectBusy = false;
		this.rejectMsg = null;
		this.rejectKey = this.rejectKey + 1;
		showModal('mdlTolakHarga');
	},

	rejectFormModel() {
		const r = this.rejectRow || {};
		return {
			key: this.rejectKey,
			title: 'Tolak Usulan Harga',
			summary: `${this.materialLabel()}\nVarian: ${r.code || '-'} · ${r.color || '-'} · ${r.thickness_label || '-'} · Supplier: ${r.supplier_name || '-'}\n`
				+ `Harga: ${this.fmtPrice(r.price)} ${r.currency || ''} · Berlaku mulai ${Util.fmtDate(r.valid_from)} · Diajukan ${r.created_by || '-'}`,
			label: 'Alasan penolakan',
			placeholder: 'mis. Harga tidak sesuai quotation terbaru',
			hint: 'Alasan terlihat oleh tim CBD di tabel harga.',
			confirmLabel: 'Tolak',
			danger: true,
			busy: this.rejectBusy,
			message: this.rejectMsg,
		};
	},

	async saveReject() {
		const reason = String((cwReasonForm.model || {}).reason || '').trim();
		if (!this.rejectRow || !reason) {
			this.rejectMsg = { type: 'error', text: 'Alasan penolakan wajib diisi.' };
			return;
		}
		const ok = await this.runForm(a_price_decide, { ids: JSON.stringify([this.rejectRow.id]), decision: 'REJECT', reason },
			v => { this.rejectMsg = v; }, v => { this.rejectBusy = v; }, 'mdlTolakHarga');
		if (!ok) return;
		closeModal('mdlTolakHarga');
		showAlert('Usulan harga ditolak.', 'success');
		await this.refresh([q_prices, q_material]);
	},
}
