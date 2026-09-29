// JSObject "MaterialCtrl" — page Master Material. Form tambah: Custom Widget cwMaterialForm di modal mdlMaterial.
// Tambah: Master Admin -> APPROVED, vendor (propose_master) -> PROPOSED (ditentukan fn_material_add).
// Approve: hanya Master Admin. Ubah data material ada di page Material Detail.
export default {
	form: { material_code: '', name: '', category: '', thickness: '', uom: '', price_method: 'CATALOG', status: 'APPROVED' },
	formKey: 0,        // naik setiap modal dibuka -> cwMaterialForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwMaterialForm

	statusOptions: [
		{ label: 'APPROVED', value: 'APPROVED' },
		{ label: 'PROPOSED', value: 'PROPOSED' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	canManage() {
		return Auth.can('manage_master');
	},

	canAdd() {
		return Auth.can('manage_master') || Auth.can('propose_master');
	},

	canViewPrice() {
		return Auth.can('view_price');
	},

	// q_material_meta: next_code, categories & uoms (teks dipisah "|")
	meta() {
		const r = (q_material_meta.data && q_material_meta.data[0]) || {};
		const split = s => String(s || '').split('|').filter(x => x);
		return { nextCode: r.next_code || '', categories: split(r.categories), uoms: split(r.uoms) };
	},

	categoryOptions() {
		return this.meta().categories.map(c => ({ label: c, value: c }));
	},

	// Ringkasan kolom "Supplier" di tabel
	supplierSummary(row) {
		if (!row.supplier_count) return 'Belum ada supplier';
		const parts = [`${row.supplier_count} supplier`];
		if (row.preferred_supplier) parts.push(`utama: ${row.preferred_supplier}`);
		if (row.proposed_links) parts.push(`${row.proposed_links} usulan`);
		if (this.canViewPrice()) {
			parts.push(row.price_method === 'QUOTATION' ? 'harga per CBD' : `${row.priced_links}/${row.supplier_count} berharga`);
			if (row.pending_prices) parts.push(`${row.pending_prices} harga menunggu approval`);
		}
		return parts.join(' · ');
	},

	openAdd() {
		this.form = { material_code: '', name: '', category: '', thickness: '', uom: '', price_method: 'CATALOG', status: 'APPROVED' };
		this.busy = false;
		this.message = null;
		this.formKey = this.formKey + 1;
		showModal('mdlMaterial');
	},

	async save() {
		// Baca model dulu — model di-reset saat state (Default model) berubah
		const m = cwMaterialForm.model || {};
		const data = {
			code: m.material_code, name: m.name, category: m.category,
			thickness: m.thickness, uom: m.uom, price_method: m.price_method,
		};
		if (!data.code || !data.name || !data.category || !data.uom) {
			this.message = { type: 'error', text: 'Lengkapi Material Code, kategori, nama, dan UoM.' };
			return;
		}
		this.message = null;
		this.busy = true;
		try {
			await a_material_add.run(data);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlMaterial');
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };   // mis. duplikat nama/thickness/UoM
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlMaterial');
		showAlert(this.canManage() ? 'Material ditambahkan.'
			: 'Usulan material terkirim (PROPOSED), menunggu persetujuan Master Admin.', 'success');
		for (const q of [q_materials, q_material_meta]) {
			try { await q.run(); } catch (e) { /* abaikan */ }
		}
	},

	approve(row) {
		return Util.run(a_material_set_status, { id: row.id, status: 'APPROVED' },
			`Material ${row.material_code} disetujui.`, [q_materials]);
	},

	open(row) {
		navigateTo('Material Detail', { id: row.id });
	},
}
