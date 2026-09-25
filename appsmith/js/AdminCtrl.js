// JSObject "AdminCtrl" — page Admin. Form user: Custom Widget cwUserForm, password sementara: cwTempPassword.
export default {
	isNew: true,
	form: { email: '', full_name: '', role: 'VENDOR_SPEC', is_active: true },
	formKey: 0,        // naik setiap modal dibuka -> cwUserForm mengisi ulang field
	busy: false,
	message: null,     // { type, text } ditampilkan di dalam cwUserForm

	// Password sementara terakhir (ditampilkan sekali di mdlPasswordSementara)
	tempPassword: '',
	tempFor: '',

	roleOptions: [
		{ label: 'Master Admin', value: 'MASTER_ADMIN' },
		{ label: 'Vendor - Specsheet', value: 'VENDOR_SPEC' },
		{ label: 'Vendor - CBD', value: 'VENDOR_CBD' },
		{ label: 'Brand Viewer', value: 'BRAND_VIEWER' },
		{ label: 'System Admin', value: 'SYSTEM_ADMIN' },
	],

	openForm(isNew, form) {
		this.isNew = isNew;
		this.form = form;
		this.busy = false;
		this.message = null;
		this.formKey = this.formKey + 1;
		showModal('mdlUser');
	},

	openAdd() {
		this.openForm(true, { email: '', full_name: '', role: 'VENDOR_SPEC', is_active: true });
	},

	openEdit(row) {
		this.openForm(false, { email: row.email, full_name: row.full_name, role: row.role, is_active: row.is_active });
	},

	async save() {
		// Baca model dulu — model di-reset saat state (Default model) berubah
		const m = cwUserForm.model || {};
		const data = {
			email: String(m.email || '').trim().toLowerCase(),
			full_name: String(m.full_name || '').trim(),
			role: m.role,
			is_active: m.is_active !== false,
			is_new: this.isNew,
		};
		if (!data.email || !data.full_name || !data.role) {
			this.message = { type: 'error', text: 'Lengkapi email, nama, dan role.' };
			return;
		}
		this.message = null;
		this.busy = true;
		try {
			await a_user_save.run(data);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlUser');
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.busy = false;
		}
		closeModal('mdlUser');
		showAlert('User disimpan.', 'success');
		for (const q of [q_users, q_audit, q_audit_entities]) {
			try { await q.run(); } catch (e) { /* abaikan */ }
		}
		const pass = a_user_save.data && a_user_save.data[0] && a_user_save.data[0].temp_password;
		if (pass) this.showTempPassword(data.email, pass);
	},

	// Query a_user_reset_password memakai "Request confirmation before running" = ON
	async resetPassword(row) {
		const ok = await Util.run(a_user_reset_password, { email: row.email }, 'Password direset.', [q_users, q_audit]);
		if (!ok) return;
		const pass = a_user_reset_password.data && a_user_reset_password.data[0]
			&& a_user_reset_password.data[0].temp_password;
		if (pass) this.showTempPassword(row.email, pass);
	},

	showTempPassword(email, pass) {
		this.tempFor = email;
		this.tempPassword = pass;
		showModal('mdlPasswordSementara');
	},

	closeTempPassword() {
		this.tempPassword = '';
		this.tempFor = '';
		closeModal('mdlPasswordSementara');
	},

	userStatus(row) {
		if (!row.is_active) return 'Nonaktif';
		if (row.locked_until && moment(row.locked_until).isAfter(moment())) return 'Terkunci';
		if (row.must_change_password) return 'Belum ganti password';
		return 'Aktif';
	},
}
