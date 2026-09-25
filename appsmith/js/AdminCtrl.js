// JSObject "AdminCtrl" — page Admin
export default {
	isNew: true,
	form: { email: '', full_name: '', role: 'VENDOR_SPEC', is_active: true },

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

	async openAdd() {
		this.isNew = true;
		this.form = { email: '', full_name: '', role: 'VENDOR_SPEC', is_active: true };
		await resetWidget('mdlUser', true);
		showModal('mdlUser');
	},

	async openEdit(row) {
		this.isNew = false;
		this.form = { email: row.email, full_name: row.full_name, role: row.role, is_active: row.is_active };
		await resetWidget('mdlUser', true);
		showModal('mdlUser');
	},

	async save() {
		if (!inpUserEmail.text || !inpUserNama.text || !selUserRole.selectedOptionValue) {
			showAlert('Lengkapi email, nama, dan role.', 'warning');
			return;
		}
		const email = inpUserEmail.text.trim().toLowerCase();
		const ok = await Util.run(
			a_user_save,
			{
				email,
				full_name: inpUserNama.text,
				role: selUserRole.selectedOptionValue,
				is_active: swUserAktif.isSwitchedOn,
				is_new: this.isNew,
			},
			'User disimpan.',
			[q_users, q_audit, q_audit_entities],
		);
		if (!ok) return;
		closeModal('mdlUser');
		const pass = a_user_save.data && a_user_save.data[0] && a_user_save.data[0].temp_password;
		if (pass) this.showTempPassword(email, pass);
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
