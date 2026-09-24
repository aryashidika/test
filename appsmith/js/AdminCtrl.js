// JSObject "AdminCtrl" — page Admin
export default {
	isNew: true,
	form: { email: '', full_name: '', role: 'VENDOR_SPEC', is_active: true },

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
		const ok = await Util.run(
			a_user_save,
			{
				email: inpUserEmail.text,
				full_name: inpUserNama.text,
				role: selUserRole.selectedOptionValue,
				is_active: swUserAktif.isSwitchedOn,
				is_new: this.isNew,
			},
			'User disimpan.',
			[q_users, q_audit, q_audit_entities],
		);
		if (ok) closeModal('mdlUser');
	},
}
