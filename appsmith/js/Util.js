// JSObject "Util" - salin ke SETIAP page (termasuk Login), isinya sama persis.
// Kalau diubah (mis. errorMessages bertambah), tempel ulang di semua page.
export default {
	// Pesan ramah untuk constraint DB. Ditambah setiap fase.
	errorMessages: {
		app_user_pkey: 'Email is already registered.',
	},

	// 45000 -> "45.000", fmtNum(1.5, 2) -> "1,50"
	fmtNum(v, dec = 0) {
		if (v === null || v === undefined || v === '') return '-';
		return Number(v).toLocaleString('id-ID', { minimumFractionDigits: dec, maximumFractionDigits: dec });
	},

	// R12 (T67): jam selalu WIB, tidak ikut zona waktu PC. Kolom date ('YYYY-MM-DD') tidak digeser.
	fmtDate(v) {
		if (!v) return '-';
		const s = String(v);
		return (/^\d{4}-\d{2}-\d{2}$/.test(s) ? moment(s, 'YYYY-MM-DD') : moment(v).utcOffset(7)).format('DD MMM YYYY');
	},

	fmtDateTime(v) {
		return v ? moment(v).utcOffset(7).format('DD MMM YYYY HH:mm') : '-';
	},

	// Ambil pesan inti dari error Postgres (RAISE EXCEPTION / constraint)
	cleanError(msg) {
		const text = String(msg || 'Something went wrong.');
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
				showAlert('Session expired. Please log in again.', 'warning');
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

	// R12 (T64): jalankan query baca dari tombol Cari / filter. Sesi habis -> ke Login; error lain -> pesan rapi.
	// Contoh di event onClick tombol Cari: Util.load(<query daftar>)
	async load(...queries) {
		for (const q of queries) {
			try {
				await q.run();
			} catch (e) {
				const msg = e && e.message;
				if (this.isSessionError(msg)) {
					await removeValue('token');
					showAlert('Session expired. Please log in again.', 'warning');
					navigateTo('Login');
					return false;
				}
				showAlert(this.cleanError(msg), 'error');
				return false;
			}
		}
		return true;
	},

	// R14: label stage (kode di DB tetap pendek: PULL, PREV, SMS, GTM, PROD). Sama dengan fn_stage_label di DB.
	stageLabel(stage) {
		return { PULL: 'Pullover', PREV: 'Preview', PROD: 'Production' }[stage] || stage || '';
	},

	// 'Pullover r0' dari baris revisi { stage, revision_no }
	revLabel(r) {
		return r ? `${this.stageLabel(r.stage)} r${r.revision_no}` : '';
	},

	statusColor(status) {
		return {
			APPROVED: '#16a34a', PUBLISHED: '#16a34a', ACTIVE: '#16a34a', IN_SYNC: '#16a34a',
			PROPOSED: '#d97706', DRAFT: '#d97706',
			NEEDS_REVISION: '#dc2626', MISSING_IN_SPEC: '#dc2626',
			INACTIVE: '#6b7280', DROPPED: '#6b7280',
		}[status] || '#6b7280';
	},

	// R19 (keputusan user 26 Okt 2026): filter di-reset setiap page dibuka (dari Home / menu, setelah login, F5), KECUALI saat
	// kembali dari halaman detail. appsmith.store.keepFilters = page yang filternya dipertahankan (tidak persisten: F5 = kosong).
	// Auth.onPageLoad tiap page memanggil resetFilters(Auth.pageName, Auth.filterWidgets()); Home mengosongkan daftar.
	async resetFilters(page, widgets) {
		if (page === 'Home') {
			await storeValue('keepFilters', [], false);
			return;
		}
		if ((appsmith.store.keepFilters || []).includes(page)) return;
		for (const w of widgets || []) {
			try { await resetWidget(w, true); } catch (e) { /* widget tidak ada: abaikan */ }
		}
	},

	// Pindah dari page berfilter ke halaman detail / turunan: filter page asal dipertahankan saat kembali; page tujuan dibuka
	// segar (mis. Model Detail model lain tidak membawa filter model sebelumnya)
	async goDetail(fromPage, target, params) {
		const keep = (appsmith.store.keepFilters || []).filter(p => p !== target && p !== fromPage);
		await storeValue('keepFilters', keep.concat([fromPage]), false);
		navigateTo(target, params || {});
	},
}
