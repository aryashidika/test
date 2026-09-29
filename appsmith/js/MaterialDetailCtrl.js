// JSObject "MaterialDetailCtrl" — page Material Detail (?id=<material id>).
// Form: cwMaterialForm (mdlMaterial), cwLinkForm (mdlLink), cwPriceForm (mdlHarga).
// Izin: ubah data/status material = manage_master · metode harga & harga = manage_price ·
// supplier material (tambah, kode, utama) = manage_material_supplier · status supplier material = manage_master.
// Semua dicek lagi di DB.
export default {
	// ---- state form (Default model widget) ----
	matKey: 0, matBusy: false, matMsg: null,
	linkKey: 0, linkBusy: false, linkMsg: null, linkIsNew: true, linkForm: {},
	priceKey: 0, priceBusy: false, priceMsg: null, priceForm: {},

	statusOptions: [
		{ label: 'APPROVED', value: 'APPROVED' },
		{ label: 'PROPOSED', value: 'PROPOSED' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	// ---- data ----
	material() {
		return (q_material.data && q_material.data[0]) || null;
	},

	materialLabel() {
		const m = this.material();
		return m ? `${m.material_code} — ${m.name}${m.thickness ? ' ' + m.thickness : ''} (${m.uom})` : '';
	},

	meta() {
		const r = (q_material_meta.data && q_material_meta.data[0]) || {};
		const split = s => String(s || '').split('|').filter(x => x);
		return { nextCode: r.next_code || '', categories: split(r.categories), uoms: split(r.uoms) };
	},

	links() {
		return q_links.data || [];
	},

	selectedLink() {
		const row = tblLinks.selectedRow;
		return row && row.id ? row : null;
	},

	prices() {
		return this.canViewPrice() ? (q_prices.data || []) : [];
	},

	// Tabel harga: supplier yang dipilih di tblLinks; riwayat hanya kalau switch swHargaRiwayat ON
	pricesForSelected() {
		const link = this.selectedLink();
		if (!link) return [];
		const history = swHargaRiwayat.isSwitchedOn === true;
		return this.prices().filter(p => p.link_id === link.id && (history || p.state !== 'RIWAYAT'));
	},

	// ---- izin (tampilan saja) ----
	canViewPrice() { return Auth.can('view_price'); },
	canManagePrice() { return Auth.can('manage_price'); },
	canManageMaster() { return Auth.can('manage_master'); },
	canLink() { return Auth.can('manage_material_supplier'); },
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
		return `<b style="font-size:16px">${e(m.material_code)} — ${e(m.name)}</b><br>`
			+ `Kategori: ${e(m.category)} · Thickness: ${e(m.thickness || '-')} · UoM: ${e(m.uom)}<br>`
			+ `Status: <b style="color:${Util.statusColor(m.status)}">${e(m.status)}</b>`
			+ (this.canViewPrice() ? ` · Metode harga: ${method}` : '');
	},

	priceNote() {
		const m = this.material();
		if (!m || !this.canViewPrice()) return '';
		if (m.price_method === 'QUOTATION') return 'Material Quotation: tidak ada harga master — harga diisi per CBD.';
		const link = this.selectedLink();
		if (!link) return 'Pilih supplier di tabel atas untuk melihat harganya.';
		return `Harga untuk ${link.supplier_name}. Harga tanpa warna berlaku untuk semua warna; harga dengan warna hanya untuk warna itu.`;
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
				material_code: m.material_code, name: m.name, category: m.category, thickness: m.thickness,
				uom: m.uom, price_method: m.price_method, status: m.status,
			},
			nextCode: meta.nextCode, categories: meta.categories, uoms: meta.uoms,
			statusOptions: this.statusOptions,
			canManage: this.canManageMaster(),
			canIdentity: this.canManageMaster(),
			canStatus: this.canManageMaster(),
			canPriceMethod: this.canManagePrice(),
			busy: this.matBusy,
			message: this.matMsg,
		};
	},

	async saveMaterial() {
		const f = cwMaterialForm.model || {};
		const params = {
			id: appsmith.URL.queryParams.id, code: f.material_code, name: f.name, category: f.category,
			thickness: f.thickness, uom: f.uom, status: f.status, price_method: f.price_method,
		};
		const ok = await this.runForm(a_material_update, params,
			v => { this.matMsg = v; }, v => { this.matBusy = v; }, 'mdlMaterial');
		if (!ok) return;
		closeModal('mdlMaterial');
		showAlert('Material disimpan.', 'success');
		await this.refresh([q_material, q_material_meta]);
	},

	// ---- supplier material ----
	openAddLink() {
		this.linkIsNew = true;
		this.linkForm = { supplier_id: '', supplier_material_code: '', is_preferred: this.links().length === 0, status: 'PROPOSED' };
		this.linkBusy = false;
		this.linkMsg = null;
		this.linkKey = this.linkKey + 1;
		showModal('mdlLink');
	},

	openEditLink(row) {
		this.linkIsNew = false;
		this.linkForm = {
			id: row.id, supplier_id: row.supplier_id, supplier_name: row.supplier_name,
			supplier_material_code: row.supplier_material_code, is_preferred: row.is_preferred, status: row.status,
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
			code: f.supplier_material_code,
			is_preferred: !!f.is_preferred,
			status: this.linkIsNew ? null : f.status,
		};
		const ok = await this.runForm(a_link_save, params,
			v => { this.linkMsg = v; }, v => { this.linkBusy = v; }, 'mdlLink');
		if (!ok) return;
		closeModal('mdlLink');
		showAlert(this.linkIsNew ? 'Supplier material ditambahkan.' : 'Supplier material disimpan.', 'success');
		await this.refresh([q_links, q_link_supplier_options, q_material]);
	},

	approveLink(row) {
		return Util.run(a_link_set_status, { id: row.id, status: 'APPROVED' },
			`Supplier ${row.supplier_name} disetujui.`, [q_links, q_material]);
	},

	// ---- harga ----
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
			links: this.links().filter(l => l.status !== 'INACTIVE').map(l => ({
				value: l.id,
				label: l.supplier_name + (l.supplier_material_code ? ` (${l.supplier_material_code})` : ''),
			})),
			form: this.priceForm,
			colorSuggestions: Object.values(colors).sort((a, b) => a.localeCompare(b)),
			openPrices: prices.filter(p => !p.valid_to).map(p => ({
				link_id: p.link_id, color: p.color, price: p.price, currency: p.currency, valid_from: p.valid_from,
			})),
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
		showAlert('Harga disimpan.', 'success');
		await this.refresh([q_prices, q_material]);
	},

	// Query a_price_end memakai "Request confirmation before running" = ON
	endPrice(row) {
		return Util.run(a_price_end, { id: row.id }, 'Harga diakhiri per hari ini.', [q_prices, q_material]);
	},
}
