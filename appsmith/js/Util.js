// JSObject "Util" — salin ke SETIAP page (termasuk Login), isinya sama persis.
// Kalau diubah (mis. errorMessages bertambah), tempel ulang di semua page.
export default {
	// Pesan ramah untuk constraint DB. Ditambah setiap fase.
	errorMessages: {
		app_user_pkey: 'Email sudah terdaftar.',
	},

	// 45000 -> "45.000", fmtNum(1.5, 2) -> "1,50"
	fmtNum(v, dec = 0) {
		if (v === null || v === undefined || v === '') return '-';
		return Number(v).toLocaleString('id-ID', { minimumFractionDigits: dec, maximumFractionDigits: dec });
	},

	// Rupiah tanpa desimal: 45000 -> "Rp 45.000"
	fmtRp(v, dec = 0) {
		const s = this.fmtNum(v, dec);
		return s === '-' ? s : `Rp ${s}`;
	},

	fmtDate(v) {
		return v ? moment(v).format('DD MMM YYYY') : '-';
	},

	fmtDateTime(v) {
		return v ? moment(v).format('DD MMM YYYY HH:mm') : '-';
	},

	// jsonb bisa datang sebagai objek atau teks
	prettyJson(v) {
		if (v === null || v === undefined || v === '') return '-';
		let obj = v;
		if (typeof v === 'string') {
			try { obj = JSON.parse(v); } catch (e) { return v; }
		}
		return JSON.stringify(obj, null, 2);
	},

	// Ambil pesan inti dari error Postgres (RAISE EXCEPTION / constraint)
	cleanError(msg) {
		const text = String(msg || 'Terjadi kesalahan.');
		const m = text.match(/constraint "([^"]+)"/);
		if (m && this.errorMessages[m[1]]) return this.errorMessages[m[1]];
		return text
			.replace(/^[\s\S]*?ERROR:\s*/, '')
			.replace(/^SESI_HABIS:\s*/, '')
			.replace(/\s*(Where|Detail|Hint|CONTEXT|Position):[\s\S]*$/, '')
			.trim();
	},

	isSessionError(msg) {
		return /SESI_HABIS/.test(String(msg || ''));
	},

	// Jalankan query aksi, tampilkan pesan, refresh query baca.
	// Mengembalikan true kalau berhasil, false kalau gagal (tidak melempar error).
	// Contoh: if (!await Util.run(a_x, { id: 1 }, 'Tersimpan', [q_list])) return;
	async run(query, params = {}, successMsg = '', refresh = []) {
		try {
			await query.run(params);
		} catch (e) {
			const msg = e && e.message;
			if (this.isSessionError(msg)) {
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return false;
			}
			showAlert(this.cleanError(msg), 'error');
			return false;
		}
		if (successMsg) showAlert(successMsg, 'success');
		for (const q of refresh) {
			try { await q.run(); } catch (e) { /* refresh gagal tidak membatalkan aksi */ }
		}
		return true;
	},

	statusColor(status) {
		return {
			APPROVED: '#16a34a', PUBLISHED: '#16a34a', ACTIVE: '#16a34a', IN_SYNC: '#16a34a',
			PROPOSED: '#d97706', DRAFT: '#d97706',
			NEEDS_REVISION: '#dc2626', MISSING_IN_SPEC: '#dc2626',
			INACTIVE: '#6b7280', DROPPED: '#6b7280',
		}[status] || '#6b7280';
	},
}
