// JSObject "CbdGridCtrl" — page Cost Breakdown (CBD): grid baris CBD (Custom Widget cwCbdGrid).
// cwCbdGrid mengirim satu event onAction dengan model.action = { type, ... }; onAction() menjalankan query
// lalu memuat ulang grid. Semua aturan dicek di DB (fn_cbd_line_set, trg_lock_published).
// F7: Yield & Loss %. F8 menambah harga (quotation / override), rekap, refresh.
export default {
	busyCount: 0,
	message: null,   // { type, text } ditampilkan di atas grid

	lines() {
		return q_cbd_lines.data || [];
	},

	async load() {
		const r = CbdCtrl.revision();
		this.message = null;
		try {
			await q_cbd_lines.run({ revision_id: r ? r.id : '' });
		} catch (e) {
			showAlert(Util.cleanError(e && e.message), 'error');
		}
	},

	async reload() {
		const r = CbdCtrl.revision();
		try { await q_cbd_lines.run({ revision_id: r ? r.id : '' }); } catch (e) { /* abaikan */ }
	},

	// Default model cwCbdGrid
	gridModel() {
		const r = CbdCtrl.revision();
		return {
			editable: CbdCtrl.editable(),
			lines: this.lines(),
			exchangeRate: r ? r.exchange_rate : null,
			busy: this.busyCount > 0,
			message: this.message,
			emptyText: r ? 'Tidak ada baris — article ini tidak memakai baris BOM mana pun.' : '',
		};
	},

	// ---- aksi dari grid (event onAction) ----
	async onAction() {
		const a = (cwCbdGrid.model || {}).action;   // baca dulu — model di-reset saat Default model berubah
		if (!a || !a.type) return;
		const fields = { setYield: 'YIELD', setLoss: 'LOSS' };
		if (!fields[a.type]) return;
		this.busyCount = this.busyCount + 1;
		try {
			await a_cbd_line_set.run({ line_id: a.line_id, field: fields[a.type], value: a.value ?? '' });
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };
			await this.reload();          // kembalikan grid ke isi DB
			return;
		} finally {
			this.busyCount = Math.max(0, this.busyCount - 1);
		}
		this.message = null;
		await this.reload();
	},
}
