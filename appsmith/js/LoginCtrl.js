// JSObject "LoginCtrl" — page Login (home page). Page ini TIDAK memakai Auth.
// Setelan: fungsi onPageLoad -> Run on page load = ON.
// URL: ?mode=keluar -> logout, ?mode=ganti -> buka modal ganti password.
export default {
	async onPageLoad() {
		const mode = appsmith.URL.queryParams.mode;
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
			await this.openChangePassword();
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
		if (!inpLoginEmail.text || !inpLoginPassword.text) {
			showAlert('Isi email dan password.', 'warning');
			return;
		}
		try {
			await a_login.run({ email: inpLoginEmail.text, password: inpLoginPassword.text });
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
			return;
		}
		const r = a_login.data && a_login.data[0];
		if (!r || !r.ok) {
			showAlert((r && r.message) || 'Login gagal.', 'error');
			return;
		}
		await storeValue('token', r.token, true);
		resetWidget('inpLoginPassword');
		if (r.must_change_password) {
			showAlert('Silakan ganti password sementara Anda.', 'info');
			await this.loadMe();
			await this.openChangePassword();
			return;
		}
		navigateTo('Beranda');
	},

	async openChangePassword() {
		await resetWidget('mdlGantiPassword', true);
		showModal('mdlGantiPassword');
	},

	async changePassword() {
		const lama = inpPassLama.text;
		const baru = inpPassBaru.text;
		if (!lama || !baru) {
			showAlert('Isi password lama dan password baru.', 'warning');
			return;
		}
		if (baru.length < 8) {
			showAlert('Password baru minimal 8 karakter.', 'warning');
			return;
		}
		if (baru !== inpPassUlang.text) {
			showAlert('Konfirmasi password tidak sama.', 'warning');
			return;
		}
		const ok = await Util.run(a_change_password, { oldPass: lama, newPass: baru }, 'Password berhasil diganti.');
		if (!ok) return;
		closeModal('mdlGantiPassword');
		navigateTo('Beranda');
	},

	// Batal ganti password: kalau memang wajib ganti, keluar dari aplikasi.
	async cancelChangePassword() {
		closeModal('mdlGantiPassword');
		const me = q_me.data && q_me.data[0];
		if (!me || me.must_change_password) {
			await this.logout();
		} else {
			navigateTo('Beranda');
		}
	},

	async logout() {
		if (appsmith.store.token) {
			try { await a_logout.run(); } catch (e) { /* sesi mungkin sudah habis */ }
		}
		await removeValue('token');
		showAlert('Anda sudah keluar.', 'info');
	},
}
