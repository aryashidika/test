export default {
	// R2: supplier dipakai bersama semua pabrik, tanpa usulan/approval (ACTIVE / INACTIVE).
	isNew: true,
	form: { id: null, name: '', status: 'ACTIVE' },
	formKey: 0,        // naik setiap modal dibuka -> cwSupplierForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwSupplierForm
	similar: [],       // nama mirip (fn_similar_names) untuk teks similarFor
	similarFor: '',
	similarSeq: 0,

	statusOptions: [
		{ label: 'ACTIVE', value: 'ACTIVE' },
		{ label: 'INACTIVE', value: 'INACTIVE' },
	],

	canManage() {
		return Auth.can('manage_master');
	},

	canAdd() {
		return this.canManage();
	},

	openForm(isNew, form) {
		this.isNew = isNew;
		this.form = form;
		this.busy = false;
		this.message = null;
		this.similar = [];
		this.similarFor = '';
		this.formKey = this.formKey + 1;
		showModal('mdlSupplier');
	},

	openAdd() {
		this.openForm(true, { id: null, name: '', status: 'ACTIVE' });
	},

	openEdit(row) {
		this.openForm(false, {
			id: row.id, name: row.name, status: row.status,
		});
	},

	// cwSupplierForm onSearch: daftar nama mirip ("cari dulu, baru buat")
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
			const rows = await q_similar.run({ kind: 'SUPPLIER', text, exclude_id: this.form.id || '' });
			if (seq !== this.similarSeq) return;
			this.similar = rows || [];
			this.similarFor = text;
		} catch (e) {
			/* daftar mirip hanya bantuan - abaikan */
		}
	},

	async save() {
		// Baca model dulu - model di-reset saat state (Default model) berubah
		const m = cwSupplierForm.model || {};
		const data = {
			id: this.form.id,
			name: String(m.name || '').trim(),
			status: this.isNew ? 'ACTIVE' : m.status,
		};
		if (!data.name) {
			this.message = { type: 'error', text: 'Supplier name is required.' };
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
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };   // mis. "Supplier "X" sudah ada."
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlSupplier');
		showAlert(this.isNew ? 'Supplier added.' : 'Supplier saved.', 'success');
		try { await q_suppliers.run(); } catch (e) { /* abaikan */ }
	},
}
