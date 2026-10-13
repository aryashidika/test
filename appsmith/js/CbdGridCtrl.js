export default {
	busyCount: 0,
	doneSeq: 0,      // seq aksi grid terakhir yang selesai -> ack ke cwCbdGrid (antrean aksi)
	running: false,
	message: null,   // { type, text } ditampilkan di atas grid

	priceKey: 0, priceBusy: false, priceMsg: null,
	priceLineId: '', priceMode: '',
	costOkKey: 0,    // naik setelah tambah biaya berhasil -> cwCbdGrid mengosongkan form tambah
	loadGen: 0,      // R12: nomor pemuatan grid terakhir yang dimulai
	doneGen: 0,      // R12: nomor pemuatan grid terbaru yang sudah selesai

	// R12 (T62): hanya data milik revisi yang dibuka
	revId() {
		const r = CbdCtrl.revision();
		return r ? r.id : '';
	},

	lines() {
		const id = this.revId();
		return id ? (q_cbd_lines.data || []).filter(l => l.cbd_revision_id === id) : [];
	},

	recap() {
		const id = this.revId();
		const rc = (q_cbd_recap.data && q_cbd_recap.data[0]) || null;
		return id && rc && rc.cbd_revision_id === id ? rc : null;
	},

	costItems() {
		const id = this.revId();
		return id ? (q_cbd_cost_items.data || []).filter(c => c.cbd_revision_id === id) : [];
	},

	async load() {
		this.message = null;
		await this.reload(true);
	},

	// Muat ulang baris + rekap revisi yang dibuka. showError: tampilkan error query sebagai toast.
	// R12 (T62): data query = hasil yang SELESAI terakhir. Bila selama memuat revisi berganti, atau pemuatan yang lebih
	// baru sudah selesai duluan (respons ini menimpa data yang lebih baru), muat ulang untuk revisi yang dibuka sekarang.
	async reload(showError) {
		try {
			for (let i = 0; i < 3; i++) {
				const g = this.loadGen + 1;
				this.loadGen = g;
				const p = { revision_id: this.revId() };
				await Promise.all([q_cbd_lines.run(p), q_cbd_recap.run(p), q_cbd_cost_items.run(p)]);
				const stale = g < this.doneGen || this.revId() !== p.revision_id;
				this.doneGen = Math.max(this.doneGen, g);
				if (!stale) return;
			}
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
				text: `Specsheet ${r.stage} sudah terbit ${a.draft_spec_label} — baris draft ini masih dari ${r.spec_label}. `
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
					+ 'Samakan dulu sebelum terbit.',
			});
		}
		const pending = lines.filter(l => l.pending).length;
		if (pending) {
			out.push({
				tone: 'danger',
				text: `${pending} baris punya usulan harga yang menunggu persetujuan Manager Costing — CBD belum bisa terbit. `
					+ 'Setelah disetujui, klik Refresh Harga dari Master.',
			});
		}
		// R11 (T56, keputusan user 13 Okt 2026): peringatan saja, untuk baris ber-Yield yang belum berharga (kemungkinan
		// lupa). Baris tanpa harga & tanpa Yield dianggap memang tanpa biaya — tidak diperingatkan.
		const unpriced = lines.filter(l => l.price_original == null && l.yield_value != null && !l.no_charge);
		if (unpriced.length) {
			const gaps = unpriced.filter(l => l.price_gap === 'NO_PRICE').length;
			const noSup = unpriced.filter(l => l.price_gap === 'NO_SUPPLIER').length;
			const parts = [`${unpriced.length} baris sudah ada Yield tapi belum berharga — tetap bisa terbit dengan cost 0. Isi harganya bila terlupa.`];
			if (gaps) parts.push(`${gaps} di antaranya belum punya harga master untuk Material Code + supplier-nya (ajukan di Material Detail).`);
			if (noSup) parts.push(`${noSup} belum punya supplier di specsheet.`);
			out.push({ tone: 'warn', text: parts.join(' ') });
		}
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
			editable: CbdCtrl.editable() && !CbdCtrl.navBusy,
			lines: this.lines(),
			recap: r ? this.recap() : null,
			costItems: r ? this.costItems() : [],
			costOkKey: this.costOkKey,
			doneSeq: this.doneSeq,
			canProposePrice: Auth.can('manage_price') && !!r && r.status === 'DRAFT',   // R8: ajukan harga master
			directPrice: Auth.can('approve_price'),                                        // Manager Costing: langsung berlaku
			canSimulate: Auth.can('simulate_margin'),
			banners: this.banners(),
			busy: this.busyCount > 0,
			message: this.message,
			emptyText: CbdCtrl.navBusy ? 'Memuat…' : (r ? 'Tidak ada baris — article ini tidak memakai baris BOM mana pun.' : ''),
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
	// Satu aksi sekali jalan. Setelah selesai (berhasil / gagal) + data dimuat ulang -> doneSeq = seq aksi (ack);
	// cwCbdGrid baru mengirim aksi berikutnya setelah ack. Kiriman ulang dengan seq yang sudah selesai diabaikan.
	async onAction() {
		const a = (cwCbdGrid.model || {}).action;   // baca dulu — model di-reset saat Default model berubah
		if (!a || !a.type) return;
		const s = Number(a.seq) || 0;
		if (s && s <= this.doneSeq) return;
		if (this.running) return;                   // cwCbdGrid mengirim ulang bila belum di-ack
		this.running = true;
		try {
			await this.runAction(a);
		} finally {
			this.running = false;
			this.doneSeq = Math.max(this.doneSeq, s);
		}
	},

	async runAction(a) {
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
			case 'addCost':
				if (await this.exec(a_cbd_cost_add, {
					revision_id: r.id, item_type: a.item_type, name: a.name || '', amount: a.amount ?? '', remarks: a.remarks || '',
				})) this.costOkKey = this.costOkKey + 1;
				break;
			case 'setCost':
				await this.exec(a_cbd_cost_set, { item_id: a.item_id, field: a.field, value: a.value ?? '' });
				break;
			case 'deleteCost':      // a_cbd_cost_delete: Request confirmation = ON
				await this.exec(a_cbd_cost_delete, { item_id: a.item_id });
				break;
			case 'editPrice':
				this.openPrice(a.line_id, a.mode);
				break;
			case 'proposePrice':    // R8: harga master untuk varian × supplier baris ini
				this.openPrice(a.line_id, 'PROPOSE');
				break;
			case 'setNoCharge':     // R11: tanpa biaya (alasan wajib) / batalkan
				if (await this.exec(a_cbd_no_charge, { line_id: a.line_id, on: a.on ? 'true' : 'false', reason: a.reason || '' })) {
					showAlert(a.on ? 'Baris ditandai tanpa biaya (cost 0).' : 'Tanda tanpa biaya dibatalkan.', 'success');
				}
				break;
			case 'refreshPrices':
				if (await this.exec(a_cbd_refresh_prices, { revision_id: r.id })) {
					const n = a_cbd_refresh_prices.data && a_cbd_refresh_prices.data[0] && a_cbd_refresh_prices.data[0].n;
					showAlert(`Harga ${n || ''} baris disamakan dengan master.`, 'success');
				}
				break;
			case 'refreshSpec':     // a_cbd_refresh_spec: Request confirmation = ON
				if (await this.exec(a_cbd_refresh_spec, { revision_id: r.id })) {
					showAlert(`CBD di-refresh dari specsheet ${r.stage} terbit terakhir.`, 'success');
					await CbdCtrl.refresh(r.id);   // acuan & baris berubah (R13: stage tetap)
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
		this.priceMode = mode === 'PROPOSE' ? 'PROPOSE' : 'QUOTATION';
		this.priceBusy = false;
		this.priceMsg = null;
		this.priceKey = this.priceKey + 1;
		showModal('mdlCbdHarga');
	},

	priceFormModel() {
		const l = this.priceLine();
		const q = this.priceMode === 'QUOTATION';
		const direct = Auth.can('approve_price');
		const fmt = (v, cur) => `${Util.fmtNum(v, cur === 'USD' ? 4 : 2)} ${cur || ''}`.trim();
		let current = '';
		let info = '';
		if (l) {
			if (l.price_original != null) {
				const src = { MASTER: 'harga master', OVERRIDE: 'override', QUOTATION: 'quotation' }[l.price_source] || '';
				current = `Harga di CBD ini: ${fmt(l.price_original, l.currency)}${src ? ' (' + src + ')' : ''}`;
			} else {
				current = 'Harga di CBD ini: kosong';
			}
			if (!q) {
				info = l.master_price != null ? `Harga master berlaku sekarang: ${fmt(l.master_price, l.master_currency)}.`
					: 'Belum ada harga master berlaku untuk Material Code + supplier ini.';
			}
		}
		return {
			key: this.priceKey,
			mode: this.priceMode,
			direct,
			today: moment().utcOffset(7).format('YYYY-MM-DD'),
			title: q ? 'Harga Quotation' : (direct ? 'Harga Master Baru' : 'Ajukan Harga Master'),
			lineLabel: l ? [l.display_no, l.display_name, `${l.material_code} ${l.material_name}`, l.color, l.supplier_name]
				.filter(x => x).join(' · ') : '',
			current,
			form: {
				price: l && l.price_source === (q ? 'QUOTATION' : 'OVERRIDE') && l.price_original != null ? String(Number(l.price_original)) : '',
				text: l && q ? (l.price_reference || '') : '',
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
		const q = this.priceMode === 'QUOTATION';     // selain itu PROPOSE (R8); override dihapus F10b
		this.priceMsg = null;
		this.priceBusy = true;
		try {
			if (q) {
				await a_cbd_set_quotation.run({ line_id: l.id, price: f.price || '', currency: f.currency || '', reference: f.text || '' });
			} else {
				await a_cbd_price_propose.run({
					line_id: l.id, price: f.price || '', currency: f.currency || '', valid_from: f.valid_from || '', reference: f.text || '',
				});
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
		showAlert(q ? (f.price ? 'Harga quotation disimpan.' : 'Harga quotation dikosongkan.')
			: Auth.can('approve_price') ? 'Harga master disimpan dan langsung berlaku. Vendor CBD perlu klik Refresh Harga dari Master.'
				: 'Usulan harga master dikirim ke Manager Costing. Setelah disetujui, klik Refresh Harga dari Master.', 'success');
		this.message = null;
		await this.reload();
	},
}
