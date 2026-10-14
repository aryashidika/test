// JSObject "Auth" - salin ke SETIAP page kecuali Login.
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
			showAlert('Could not load profile: ' + Util.cleanError(e && e.message), 'error');
			return false;
		}
		if (!this.me) {
			await removeValue('token');
			if (hadToken) showAlert('Session expired. Please log in again.', 'warning');
			navigateTo('Login');
			return false;
		}
		if (this.me.must_change_password) {
			navigateTo('Login', { mode: 'ganti' });
			return false;
		}
		if (this.requiredPerm && !this.can(this.requiredPerm)) {
			showAlert(`Role ${this.me.role_label} has no access to this page.`, 'warning');
			navigateTo('Home');
			return false;
		}
		for (const q of this.pageQueries()) {
			try {
				await q.run();
			} catch (e) {
				const msg = e && e.message;
				if (Util.isSessionError(msg)) {          // R12 (T64)
					await removeValue('token');
					showAlert('Session expired. Please log in again.', 'warning');
					navigateTo('Login');
					return false;
				}
				showAlert(Util.cleanError(msg), 'error');
			}
		}
		return true;
	},
}
