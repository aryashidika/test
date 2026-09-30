// JSObject "CbdGridCtrl" — page Cost Breakdown (CBD): grid baris CBD + rekap + harga (Custom Widget cwCbdGrid,
// modal mdlCbdHarga berisi cwCbdPriceForm). cwCbdGrid mengirim satu event onAction dengan model.action = { type, ... };
// onAction() menjalankan query lalu memuat ulang grid & rekap. Semua aturan dicek di DB (fn_cbd_*, trg_lock_published).
// F7: Yield & Loss %. F8: rekap (rate, amortisasi, adjustment, target FOB, selling price ⇄ margin), harga quotation /
// override / hapus override, Refresh Harga dari Master, Refresh dari Specsheet.
export default {
	busyCount: 0,
	message: null,   // { type, text } ditampilkan di atas grid

	priceKey: 0, priceBusy: false, priceMsg: null,
	priceLineId: '', priceMode: '',

	lines() {
		return q_cbd_lines.data || [];
	},

	recap() {
		return (q_cbd_recap.data && q_cbd_recap.data[0]) || null;
	},

	async load() {
		this.message = null;
		await this.reload(true);
	},

	// Muat ulang baris + rekap revisi yang dibuka. showError: tampilkan error query sebagai toast.
	async reload(showError) {
		const r = CbdCtrl.revision();
		const p = { revision_id: r ? r.id : '' };
		try {
			await Promise.all([q_cbd_lines.run(p), q_cbd_recap.run(p)]);
		} catch (e) {
			if (showError) showAlert(Util.cleanError(e && e.message), 'error');
		}
	},

	// Banner di atas grid (hanya draft yang bisa diubah)
	banners() {
		const r = CbdCtrl.revision();
		const a = CbdCtrl.article();
		if (!r || r.status !== 'DRAFT' || !a || !CbdCtrl.canEdit()) return [];
		const out = [];
		if (a.draft_stale) {
			out.push({
				tone: 'danger', action: 'refreshSpec', actionLabel: 'Refresh dari Specsheet',
				text: `Specsheet sudah terbit ${a.spec_pub_label} — baris draft ini masih dari ${r.spec_label}. `
					+ 'Refresh dulu sebelum terbit (Yield, Loss % & harga input dibawa; baris yang hilang jadi MISSING_IN_SPEC).',
			});
			return out;
		}
		const lines = this.lines().filter(l => l.status === 'ACTIVE');
		const stale = lines.filter(l => l.master_stale).length;
		if (stale) {
			out.push({
				tone: 'warn', action: 'refreshPrices', actionLabel: 'Refresh Harga dari Master',
				text: `Harga master untuk ${stale} baris baru tersedia atau berubah sejak CBD ini dibuat. `
					+ 'Samakan dulu sebelum terbit (override tidak ikut berubah).',
			});
		}
		const gaps = lines.filter(l => ['NO_PRICE', 'NO_COLOR_PRICE', 'PENDING'].includes(l.price_gap)).length;
		const noSup = lines.filter(l => l.price_gap === 'NO_SUPPLIER').length;
		const parts = [];
		if (gaps) parts.push(`${gaps} baris belum punya harga master (isi di Master Material, lalu Refresh Harga) — boleh terbit dengan cost 0.`);
		if (noSup) parts.push(`${noSup} baris belum punya supplier di specsheet.`);
		if (parts.length) out.push({ tone: 'info', text: parts.join(' ') });
		const rc = this.recap();
		if (rc && rc.usd_no_rate_count) {
			out.push({ tone: 'warn', text: `${rc.usd_no_rate_count} baris berharga USD belum terhitung — isi Exchange rate di rekap.` });
		}
		return out;
	},

	// Default model cwCbdGrid
	gridModel() {
		const r = CbdCtrl.revision();
		return {
			editable: CbdCtrl.editable(),
			lines: this.lines(),
			recap: r ? this.recap() : null,
			banners: this.banners(),
			busy: this.busyCount > 0,
			message: this.message,
			emptyText: r ? 'Tidak ada baris — article ini tidak memakai baris BOM mana pun.' : '',
		};
	},

	// Jalankan query aksi, lalu muat ulang. Mengembalikan true bila berhasil.
	async exec(query, params) {
		this.busyCount = this.busyCount + 1;
		try {
			await query.run(params);
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return false;
			}
			this.message = { type: 'error', text: Util.cleanError(msg) };
			await this.reload();          // kembalikan grid ke isi DB
			return false;
		} finally {
			this.busyCount = Math.max(0, this.busyCount - 1);
		}
		this.message = null;
		await this.reload();
		return true;
	},

	// ---- aksi dari grid (event onAction) ----
	async onAction() {
		const a = (cwCbdGrid.model || {}).action;   // baca dulu — model di-reset saat Default model berubah
		if (!a || !a.type) return;
		const r = CbdCtrl.revision();
		if (!r) return;
		switch (a.type) {
			case 'setYield':
			case 'setLoss':
				await this.exec(a_cbd_line_set, { line_id: a.line_id, field: a.type === 'setYield' ? 'YIELD' : 'LOSS', value: a.value ?? '' });
				break;
			case 'setHeader':
				await this.exec(a_cbd_header_set, { revision_id: r.id, field: a.field, value: a.value ?? '' });
				break;
			case 'editPrice':
				this.openPrice(a.line_id, a.mode);
				break;
			case 'clearOverride':   // a_cbd_clear_override: Request confirmation = ON
				if (await this.exec(a_cbd_clear_override, { line_id: a.line_id })) showAlert('Override dihapus — kembali ke harga master.', 'success');
				break;
			case 'refreshPrices':
				if (await this.exec(a_cbd_refresh_prices, { revision_id: r.id })) {
					const n = a_cbd_refresh_prices.data && a_cbd_refresh_prices.data[0] && a_cbd_refresh_prices.data[0].n;
					showAlert(`Harga ${n || ''} baris disamakan dengan master.`, 'success');
				}
				break;
			case 'refreshSpec':     // a_cbd_refresh_spec: Request confirmation = ON
				if (await this.exec(a_cbd_refresh_spec, { revision_id: r.id })) {
					showAlert('CBD di-refresh dari specsheet terbit terakhir.', 'success');
					await CbdCtrl.refresh(r.id);   // stage / nomor revisi bisa berubah
				}
				break;
		}
	},

	// ---- harga (modal mdlCbdHarga) ----
	priceLine() {
		return this.lines().find(l => l.id === this.priceLineId) || null;
	},

	openPrice(lineId, mode) {
		this.priceLineId = lineId || '';
		this.priceMode = mode === 'QUOTATION' ? 'QUOTATION' : 'OVERRIDE';
		this.priceBusy = false;
		this.priceMsg = null;
		this.priceKey = this.priceKey + 1;
		showModal('mdlCbdHarga');
	},

	priceFormModel() {
		const l = this.priceLine();
		const q = this.priceMode === 'QUOTATION';
		const fmt = (v, cur) => `${Util.fmtNum(v, cur === 'USD' ? 4 : 2)} ${cur || ''}`.trim();
		let current = '';
		let info = '';
		if (l) {
			if (l.price_original != null) {
				const src = { MASTER: 'harga master', OVERRIDE: 'override', QUOTATION: 'quotation' }[l.price_source] || '';
				current = `Harga sekarang: ${fmt(l.price_original, l.currency)}${src ? ' (' + src + ')' : ''}`;
			} else {
				current = 'Harga sekarang: kosong';
			}
			if (!q && l.master_price != null && l.price_source !== 'MASTER') info = `Harga master berlaku: ${fmt(l.master_price, l.master_currency)}.`;
			if (!q && l.price_gap === 'PENDING') info = 'Ada usulan harga master yang menunggu approval Master Admin — setelah di-approve, klik Refresh Harga (override tidak perlu).';
		}
		return {
			key: this.priceKey,
			mode: this.priceMode,
			title: q ? 'Harga Quotation' : 'Override Harga',
			lineLabel: l ? [l.display_no, l.display_name, `${l.material_code} ${l.material_name}`, l.color, l.supplier_name]
				.filter(x => x).join(' · ') : '',
			current,
			form: {
				price: l && l.price_source === (q ? 'QUOTATION' : 'OVERRIDE') && l.price_original != null ? String(Number(l.price_original)) : '',
				text: l ? (q ? (l.price_reference || '') : (l.price_source === 'OVERRIDE' ? l.price_override_reason || '' : '')) : '',
			},
			info,
			busy: this.priceBusy,
			message: this.priceMsg,
		};
	},

	async savePrice() {
		const f = cwCbdPriceForm.model || {};   // baca dulu
		const l = this.priceLine();
		if (!l) return;
		const q = this.priceMode === 'QUOTATION';
		this.priceMsg = null;
		this.priceBusy = true;
		try {
			if (q) {
				await a_cbd_set_quotation.run({ line_id: l.id, price: f.price || '', currency: f.currency || '', reference: f.text || '' });
			} else {
				await a_cbd_override_price.run({ line_id: l.id, price: f.price || '', currency: f.currency || '', reason: f.text || '' });
			}
		} catch (e) {
			const msg = e && e.message;
			if (Util.isSessionError(msg)) {
				closeModal('mdlCbdHarga');
				await removeValue('token');
				showAlert('Sesi login habis. Silakan login lagi.', 'warning');
				navigateTo('Login');
				return;
			}
			this.priceMsg = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.priceBusy = false;
		}
		closeModal('mdlCbdHarga');
		showAlert(q ? (f.price ? 'Harga quotation disimpan.' : 'Harga quotation dikosongkan.') : 'Override harga disimpan.', 'success');
		this.message = null;
		await this.reload();
	},
}
