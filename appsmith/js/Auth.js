// JS Object "Auth" — salin ke SETIAP page (Appsmith CE tidak punya JS global).
// Yang diubah per page hanya `requiredPerm`.
// Setelan: fungsi onPageLoad -> "Run on page load" = ON.
export default {
	// Izin untuk membuka page ini. Kosongkan ('') khusus di page Beranda.
	// Contoh: Master_* -> 'view_master', CBD_* -> 'view_cbd', Audit_Log -> 'view_audit'
	requiredPerm: '',

	me: null,     // { email, full_name, role, role_label, is_active, permissions }
	perms: [],

	async load() {
		await q_me.run();
		const row = (q_me.data && q_me.data[0]) || null;
		this.me = row && row.is_active ? row : null;
		this.perms = this.me ? String(this.me.permissions || '').split(',').filter(p => p) : [];
		return this.me;
	},

	can(perm) {
		return this.perms.includes(perm);
	},

	async onPageLoad() {
		const me = await this.load();
		if (!this.requiredPerm) return true;   // Beranda: tampilkan pesan, jangan redirect
		if (!me) {
			showAlert('Akun Anda belum terdaftar di aplikasi. Hubungi System Admin.', 'error');
			navigateTo('Beranda');
			return false;
		}
		if (!this.can(this.requiredPerm)) {
			showAlert(`Role ${me.role_label} tidak punya akses ke halaman ini.`, 'warning');
			navigateTo('Beranda');
			return false;
		}
		return true;
	},
}
