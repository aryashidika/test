// JSObject "SupplierCtrl" — page Master Supplier. Form: Custom Widget cwSupplierForm di modal mdlSupplier.
// Supplier tidak punya currency — currency dipilih per harga (F3/CBD).
// Tambah: Master Admin (langsung APPROVED) atau Vendor (propose_master -> PROPOSED, F10b). Ubah & status hanya
// Master Admin (manage_master). Semua dicek lagi di DB (fn_auth / fn_auth_any).
export default {
	isNew: true,
	form: { id: null, name: '', status: 'APPROVED' },
	formKey: 0,        // naik setiap modal dibuka -> cwSupplierForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwSupplierForm

	statusOptions: [
		{ label: 'APPROVED', value: 'APPROVED' },
		{ label: 'PROPOSED', value: 'PROPOSED' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	canManage() {
		return Auth.can('manage_master');
	},

	canAdd() {
		return this.canManage() || Auth.can('propose_master');
	},

	openForm(isNew, form) {
		this.isNew = isNew;
		this.form = form;
		this.busy = false;
		this.message = null;
		this.formKey = this.formKey + 1;
		showModal('mdlSupplier');
	},

	openAdd() {
		this.openForm(true, { id: null, name: '', status: this.canManage() ? 'APPROVED' : 'PROPOSED' });
	},

	openEdit(row) {
		this.openForm(false, {
			id: row.id, name: row.name, status: row.status,
		});
	},

	async save() {
		// Baca model dulu — model di-reset saat state (Default model) berubah
		const m = cwSupplierForm.model || {};
		const data = {
			id: this.form.id,
			name: String(m.name || '').trim(),
			status: this.isNew ? null : m.status,      // supplier baru: status ditentukan DB (APPROVED / PROPOSED)
		};
		if (!data.name) {
			this.message = { type: 'error', text: 'Nama supplier wajib diisi.' };
			return;
		}
		this.message = null;
		this.busy = true;
		try {
			await (this.isNew ? a_supplier_insert : a_supplier_update).run(data);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlSupplier');
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };   // mis. "Supplier "X" sudah ada."
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlSupplier');
		showAlert(!this.isNew ? 'Supplier disimpan.'
			: (this.canManage() ? 'Supplier ditambahkan.' : 'Usulan supplier terkirim, menunggu persetujuan Master Admin.'), 'success');
		try { await q_suppliers.run(); } catch (e) { /* abaikan */ }
	},
}
