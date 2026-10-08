export default {
	// R2: material INDUK + tab Varian (Material Code + warna + thickness teks ERP, satu per satu — R2b) + tab Supplier.
	// Bagian harga (cntHarga) disembunyikan sampai R3 (harga per varian × supplier); fungsinya dibiarkan.
	// ---- state form (Default model widget) ----
	matKey: 0, matBusy: false, matMsg: null,
	linkKey: 0, linkBusy: false, linkMsg: null, linkIsNew: true, linkForm: {},
	varKey: 0, varBusy: false, varMsg: null, varIsNew: true, varForm: {}, varHint: null, varLookupSeq: 0,
	priceKey: 0, priceBusy: false, priceMsg: null, priceForm: {},
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

	selectedLink() {
		const row = tblLinks.selectedRow;
		return row && row.id ? row : null;
	},

	prices() {
		return this.canViewPrice() ? (q_prices.data || []) : [];
	},

	// Tabel harga: supplier yang dipilih di tblLinks. Tanpa "Tampilkan riwayat": sembunyikan RIWAYAT
	// dan usulan DITOLAK yang lebih lama dari 30 hari.
	pricesForSelected() {
		const link = this.selectedLink();
		if (!link) return [];
		const history = swHargaRiwayat.isSwitchedOn === true;
		const recent = p => p.decided_at && moment().diff(moment(p.decided_at), 'days') <= 30;
		return this.prices().filter(p => p.link_id === link.id && (history || p.state === 'BERLAKU'
			|| p.state === 'AKAN BERLAKU' || p.state === 'MENUNGGU APPROVAL' || (p.state === 'DITOLAK' && recent(p))));
	},

	// Warna kolom Keterangan di tblPrices
	stateColor(state) {
		return {
			BERLAKU: '#16a34a', 'AKAN BERLAKU': '#d97706', 'MENUNGGU APPROVAL': '#d97706', DITOLAK: '#dc2626',
		}[state] || '#6b7280';
	},

	stateText(row) {
		if (row.state === 'DITOLAK') return `DITOLAK: ${row.reject_reason || '-'}`;
		if (row.state === 'MENUNGGU APPROVAL') return 'MENUNGGU APPROVAL';
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
		return this.canManagePrice() && !!m && m.price_method === 'CATALOG'
			&& this.links().some(l => l.status !== 'INACTIVE');
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
		const link = this.selectedLink();
		if (!link) return 'Pilih supplier di tabel atas untuk melihat harganya.';
		const pending = this.prices().filter(p => p.status === 'PROPOSED').length;
		return `Harga untuk ${link.supplier_name}. Harga tanpa warna berlaku untuk semua warna; harga dengan warna hanya untuk warna itu.`
			+ (pending ? ` · ${pending} usulan harga material ini menunggu approval Manager Costing.` : '');
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

	// ---- harga (disembunyikan sampai R3) ----
	openAddPrice(color) {
		const link = this.selectedLink();
		this.priceForm = {
			link_id: link && link.status !== 'INACTIVE' ? link.id : '',
			color: color || '',
		};
		this.priceBusy = false;
		this.priceMsg = null;
		this.priceKey = this.priceKey + 1;
		showModal('mdlHarga');
	},

	priceFormModel() {
		const prices = this.prices();
		const colors = {};
		prices.forEach(p => { if (p.color) colors[String(p.color).toLowerCase()] = p.color; });
		return {
			key: this.priceKey,
			materialLabel: this.materialLabel(),
			links: this.links().filter(l => l.status !== 'INACTIVE').map(l => ({ value: l.id, label: l.supplier_name })),
			form: this.priceForm,
			colorSuggestions: Object.values(colors).sort((a, b) => a.localeCompare(b)),
			openPrices: prices.filter(p => p.status === 'APPROVED' && !p.valid_to).map(p => ({
				link_id: p.link_id, color: p.color, price: p.price, currency: p.currency, valid_from: p.valid_from,
			})),
			pendingPrices: prices.filter(p => p.status === 'PROPOSED').map(p => ({
				link_id: p.link_id, color: p.color, price: p.price, currency: p.currency,
			})),
			needsApproval: true,
			today: moment().utcOffset(7).format('YYYY-MM-DD'),
			busy: this.priceBusy,
			message: this.priceMsg,
		};
	},

	async savePrice() {
		const f = cwPriceForm.model || {};
		const params = {
			link_id: f.link_id, color: f.color, price: f.price, currency: f.currency,
			valid_from: f.valid_from, reference: f.reference,
		};
		if (!params.link_id || !params.price || !params.currency || !params.valid_from) {
			this.priceMsg = { type: 'error', text: 'Lengkapi supplier, harga, currency, dan tanggal berlaku.' };
			return;
		}
		const ok = await this.runForm(a_price_add, params,
			v => { this.priceMsg = v; }, v => { this.priceBusy = v; }, 'mdlHarga');
		if (!ok) return;
		closeModal('mdlHarga');
		showAlert('Usulan harga terkirim, menunggu approval Manager Costing.', 'success');
		await this.refresh([q_prices, q_material]);
	},

	// Query a_price_end memakai "Request confirmation before running" = ON
	endPrice(row) {
		return Util.run(a_price_end, { id: row.id }, 'Harga diakhiri per hari ini.', [q_prices, q_material]);
	},

	approvePrice(row) {
		return Util.run(a_price_approve, { id: row.id },
			'Harga di-approve dan berlaku sesuai tanggalnya.', [q_prices, q_material]);
	},

	// Query a_price_cancel memakai "Request confirmation before running" = ON
	cancelPrice(row) {
		return Util.run(a_price_cancel, { id: row.id }, 'Usulan harga dibatalkan.', [q_prices, q_material]);
	},

	// Ambil baris asli dari q_prices: baris dari tabel berisi nilai tampilan ("2,49"), bukan angka -> NaN.
	openReject(row) {
		this.rejectRow = this.prices().find(p => p.id === row.id) || row;
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
			summary: `${this.materialLabel()}\nSupplier: ${r.supplier_name || '-'} · Warna: ${r.color || 'Semua warna'}\n`
				+ `Harga: ${this.fmtPrice(r.price)} ${r.currency || ''} · Berlaku mulai ${Util.fmtDate(r.valid_from)} · Diusulkan ${r.created_by || '-'}`,
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
		const ok = await this.runForm(a_price_reject, { id: this.rejectRow.id, reason },
			v => { this.rejectMsg = v; }, v => { this.rejectBusy = v; }, 'mdlTolakHarga');
		if (!ok) return;
		closeModal('mdlTolakHarga');
		showAlert('Usulan harga ditolak.', 'success');
		await this.refresh([q_prices, q_material]);
	},
}
