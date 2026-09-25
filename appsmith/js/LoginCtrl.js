// JSObject "LoginCtrl" — page Login (home page). Page ini TIDAK memakai Auth.
// Tampilan: Custom Widget cwLogin (lihat widgets/cwLogin/README.md).
// Setelan: fungsi onPageLoad -> Run on page load = ON.
// URL: ?mode=keluar -> logout, ?mode=ganti -> tampilan ganti password.
export default {
	// State yang dikirim ke cwLogin lewat Default model
	view: 'login',      // 'login' | 'change'
	busy: false,
	forced: false,      // wajib ganti password (password sementara)
	message: null,      // { type, text }
	lastEmail: '',

	setMessage(type, text) {
		this.message = text ? { type, text } : null;
	},

	openChange(forced) {
		this.forced = !!forced;
		this.view = 'change';
		this.setMessage(null);
	},

	async onPageLoad() {
		const mode = appsmith.URL.queryParams.mode;
		this.view = 'login';
		this.busy = false;
		this.forced = false;
		this.setMessage(null);
		if (mode === 'keluar') {
			await this.logout();
			return;
		}
		if (!appsmith.store.token) return;
		const me = await this.loadMe();
		if (!me) {
			await removeValue('token');
			return;
		}
		if (me.must_change_password || mode === 'ganti') {
			this.openChange(me.must_change_password);
			return;
		}
		navigateTo('Beranda');
	},

	async loadMe() {
		try {
			await q_me.run();
		} catch (e) {
			return null;
		}
		return (q_me.data && q_me.data[0]) || null;
	},

	async login() {
		// Baca dulu dari model sebelum state berubah (model di-reset saat Default model berubah)
		const email = (cwLogin.model.email || '').trim().toLowerCase();
		const password = cwLogin.model.password || '';
		if (!email || !password) {
			this.setMessage('error', 'Isi email dan password.');
			return;
		}
		this.lastEmail = email;
		this.setMessage(null);
		this.busy = true;
		try {
			await a_login.run({ email, password });
		} catch (e) {
			this.setMessage('error', Util.cleanError(e && e.message));
			return;
		} finally {
			this.busy = false;
		}
		const r = a_login.data && a_login.data[0];
		if (!r || !r.ok) {
			this.setMessage('error', (r && r.message) || 'Login gagal.');
			return;
		}
		await storeValue('token', r.token, true);
		if (r.must_change_password) {
			await this.loadMe();
			this.openChange(true);
			return;
		}
		navigateTo('Beranda');
	},

	async changePassword() {
		const oldPass = cwLogin.model.oldPass || '';
		const newPass = cwLogin.model.newPass || '';
		if (!oldPass || !newPass) {
			this.setMessage('error', 'Isi password lama dan password baru.');
			return;
		}
		this.setMessage(null);
		this.busy = true;
		try {
			await a_change_password.run({ oldPass, newPass });
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				await removeValue('token');
				this.view = 'login';
				this.forced = false;
				this.setMessage('error', 'Sesi login habis. Silakan login lagi.');
			} else {
				this.setMessage('error', Util.cleanError(msg));
			}
			return;
		} finally {
			this.busy = false;
		}
		showAlert('Password berhasil diganti.', 'success');
		navigateTo('Beranda');
	},

	// Batal: kalau wajib ganti password -> keluar; kalau tidak -> kembali ke Beranda
	async cancelChange() {
		if (this.forced) {
			await this.logout();
			return;
		}
		navigateTo('Beranda');
	},

	async logout() {
		if (appsmith.store.token) {
			try { await a_logout.run(); } catch (e) { /* sesi mungkin sudah habis */ }
		}
		await removeValue('token');
		this.view = 'login';
		this.forced = false;
		this.setMessage('info', 'Anda sudah keluar.');
	},
}
