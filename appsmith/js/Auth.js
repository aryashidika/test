// JSObject "Auth" — salin ke SETIAP page. Yang diubah per page hanya `requiredPerm`.
// Setelan: fungsi onPageLoad -> Run on page load = ON.
export default {
	// Izin untuk membuka page ini. '' khusus Beranda (semua user boleh buka).
	requiredPerm: '',

	me: null,       // { email, full_name, role, role_label, is_active, permissions }
	perms: [],
	loaded: false,

	async load() {
		await q_me.run();
		const row = (q_me.data && q_me.data[0]) || null;
		this.me = row && row.is_active ? row : null;
		this.perms = this.me ? String(this.me.permissions || '').split(',').filter(p => p) : [];
		this.loaded = true;
		return this.me;
	},

	can(perm) {
		return this.perms.includes(perm);
	},

	async onPageLoad() {
		try {
			await this.load();
		} catch (e) {
			showAlert('Gagal memuat profil: ' + Util.cleanError(e && e.message), 'error');
			return false;
		}
		if (!this.requiredPerm) return true;
		if (!this.me) {
			showAlert('Akun Anda belum terdaftar atau nonaktif. Hubungi System Admin.', 'error');
			navigateTo('Beranda');
			return false;
		}
		if (!this.can(this.requiredPerm)) {
			showAlert(`Role ${this.me.role_label} tidak punya akses ke halaman ini.`, 'warning');
			navigateTo('Beranda');
			return false;
		}
		return true;
	},
}
