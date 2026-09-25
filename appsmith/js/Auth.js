// JSObject "Auth" — salin ke SETIAP page kecuali Login.
// Yang diubah per page: `requiredPerm` dan isi `pageQueries()`.
// Setelan: fungsi onPageLoad -> Run on page load = ON.
// Semua query baca di page: Run on page load = OFF (dijalankan lewat pageQueries).
export default {
	// Izin untuk membuka page ini. '' = cukup sudah login (Beranda).
	requiredPerm: '',

	// Query baca yang dijalankan setelah login & izin valid.
	pageQueries() {
		return [];
	},

	me: null,       // { email, full_name, role, role_label, must_change_password, expires_at, permissions }
	perms: [],
	loaded: false,

	async load() {
		this.me = null;
		this.perms = [];
		if (appsmith.store.token) {
			await q_me.run();
			this.me = (q_me.data && q_me.data[0]) || null;
			this.perms = this.me ? String(this.me.permissions || '').split(',').filter(p => p) : [];
		}
		this.loaded = true;
		return this.me;
	},

	can(perm) {
		return this.perms.includes(perm);
	},

	async onPageLoad() {
		const hadToken = !!appsmith.store.token;
		try {
			await this.load();
		} catch (e) {
			showAlert('Gagal memuat profil: ' + Util.cleanError(e && e.message), 'error');
			return false;
		}
		if (!this.me) {
			await removeValue('token');
			if (hadToken) showAlert('Sesi login habis. Silakan login lagi.', 'warning');
			navigateTo('Login');
			return false;
		}
		if (this.me.must_change_password) {
			navigateTo('Login', { mode: 'ganti' });
			return false;
		}
		if (this.requiredPerm && !this.can(this.requiredPerm)) {
			showAlert(`Role ${this.me.role_label} tidak punya akses ke halaman ini.`, 'warning');
			navigateTo('Beranda');
			return false;
		}
		for (const q of this.pageQueries()) {
			try {
				await q.run();
			} catch (e) {
				showAlert(Util.cleanError(e && e.message), 'error');
			}
		}
		return true;
	},
}
