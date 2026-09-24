// JS Object "Util" — salin ke SETIAP page, isinya sama persis di semua page.
export default {
	// Angka format Indonesia: 45000 -> "45.000", fmtNum(1.5, 2) -> "1,50"
	fmtNum(v, dec = 0) {
		if (v === null || v === undefined || v === '') return '-';
		return Number(v).toLocaleString('id-ID', { minimumFractionDigits: dec, maximumFractionDigits: dec });
	},

	// IDR tanpa desimal, USD 4 desimal (sama seperti mockup)
	fmtMoney(v, currency = 'IDR') {
		if (v === null || v === undefined || v === '') return '-';
		return `${currency} ${this.fmtNum(v, currency === 'USD' ? 4 : 0)}`;
	},

	fmtDate(v) {
		return v ? moment(v).format('DD MMM YYYY') : '-';
	},

	fmtDateTime(v) {
		return v ? moment(v).format('DD MMM YYYY HH:mm') : '-';
	},

	// Pesan error Postgres dari RAISE EXCEPTION di fn_* tanpa awalan "ERROR:" / konteks PL/pgSQL
	cleanError(msg) {
		return String(msg || 'Terjadi kesalahan.')
			.replace(/^.*?ERROR:\s*/s, '')
			.replace(/\s*(Where|Detail|Hint|CONTEXT):.*$/s, '')
			.trim();
	},

	// Jalankan query aksi (a_*), tampilkan pesan sukses/gagal, lalu refresh query baca.
	// Contoh: Util.run(a_supplier_create, { name: inpNama.text }, 'Supplier dibuat', [q_suppliers])
	async run(query, params = {}, successMsg = '', refresh = []) {
		try {
			const res = await query.run(params);
			if (successMsg) showAlert(successMsg, 'success');
			for (const q of refresh) await q.run();
			return res;
		} catch (e) {
			showAlert(this.cleanError(e && e.message), 'error');
			throw e;
		}
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
