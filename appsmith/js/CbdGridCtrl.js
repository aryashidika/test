export default {
	busyCount: 0,
	doneSeq: 0,      // seq aksi grid terakhir yang selesai -> ack ke cwCbdGrid (antrean aksi)
	running: false,
	message: null,   // { type, text } ditampilkan di atas grid

	priceKey: 0, priceBusy: false, priceMsg: null,
	priceLineId: '', priceMode: '',
	priceHint: null, // R17: estimasi terakhir material + thickness + supplier yang sama (q_cbd_estimate_hint)
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
				tone: 'danger', action: 'refreshSpec', actionLabel: 'Refresh from Specsheet',
				text: `The ${Util.stageLabel(r.stage)} specsheet now has ${a.draft_spec_label} published. This draft still uses ${r.spec_label}. `
					+ 'Refresh before publishing (Yield, Loss % & entered prices are kept; removed lines become MISSING_IN_SPEC).',
			});
			return out;
		}
		const lines = this.lines().filter(l => l.status === 'ACTIVE');
		const stale = lines.filter(l => l.master_stale).length;
		if (stale) {
			out.push({
				tone: 'warn', action: 'refreshPrices', actionLabel: 'Refresh Prices from Master',
				text: `Master prices for ${stale} lines are new or changed since this CBD was created. `
					+ 'Update them before publishing.',
			});
		}
		const pending = lines.filter(l => l.pending).length;
		if (pending) {
			out.push({
				tone: 'danger',
				text: `${pending} lines have price proposals waiting for Manager Costing. The CBD cannot be published yet. `
					+ 'After approval, click Refresh Prices from Master.',
			});
		}
		// R11 (T56, keputusan user 13 Okt 2026): peringatan saja, untuk baris ber-Yield yang belum berharga (kemungkinan
		// lupa). Baris tanpa harga & tanpa Yield dianggap memang tanpa biaya - tidak diperingatkan.
		// R17: mulai SMS memblokir (sama dengan fn_stage_code_required di DB); Pullover / Preview tetap peringatan
		const unpriced = lines.filter(l => l.price_original == null && l.yield_value != null && !l.no_charge);
		if (unpriced.length) {
			const required = ['SMS', 'GTM', 'PROD'].includes(r.stage);
			const gaps = unpriced.filter(l => l.price_gap === 'NO_PRICE').length;
			const noSup = unpriced.filter(l => l.price_gap === 'NO_SUPPLIER').length;
			const noCode = unpriced.filter(l => l.price_gap === 'NO_CODE').length;
			const parts = [required
				? `${unpriced.length} lines have a Yield but no price. From SMS the CBD cannot be published until they have a price (or are marked No charge).`
				: `${unpriced.length} lines have a Yield but no price. They can still publish with cost 0. Fill in the price if it was missed.`];
			if (gaps) parts.push(`${gaps} of them have no master price for their Material Code + supplier (Propose master price in the Price column).`);
			if (noCode && !required) parts.push(`${noCode} have no Material Code yet: click Enter estimate in the Price column.`);
			if (noSup) parts.push(`${noSup} have no supplier in the specsheet.`);
			out.push({ tone: required ? 'danger' : 'warn', text: parts.join(' ') });
		}
		const rc = this.recap();
		if (rc && rc.usd_no_rate_count) {
			out.push({ tone: 'warn', text: `${rc.usd_no_rate_count} USD-priced lines are not counted. Fill in the Exchange rate in the recap.` });
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
			emptyText: CbdCtrl.navBusy ? 'Loading…' : (r ? 'No lines. This article does not use any BOM line.' : ''),
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
				showAlert('Session expired. Please log in again.', 'warning');
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
		const a = (cwCbdGrid.model || {}).action;   // baca dulu - model di-reset saat Default model berubah
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
			case 'editPrice':       // mode QUOTATION / ESTIMATE (R17)
				await this.openPrice(a.line_id, a.mode);
				break;
			case 'proposePrice':    // R8: harga master untuk varian × supplier baris ini
				await this.openPrice(a.line_id, 'PROPOSE');
				break;
			case 'setNoCharge':     // R11: tanpa biaya (alasan wajib) / batalkan
				if (await this.exec(a_cbd_no_charge, { line_id: a.line_id, on: a.on ? 'true' : 'false', reason: a.reason || '' })) {
					showAlert(a.on ? 'Line marked as no charge (cost 0).' : 'No-charge mark removed.', 'success');
				}
				break;
			case 'refreshPrices':
				if (await this.exec(a_cbd_refresh_prices, { revision_id: r.id })) {
					const n = a_cbd_refresh_prices.data && a_cbd_refresh_prices.data[0] && a_cbd_refresh_prices.data[0].n;
					showAlert(`Prices of ${n || ''} line(s) updated from master.`, 'success');
				}
				break;
			case 'refreshSpec':     // a_cbd_refresh_spec: Request confirmation = ON
				if (await this.exec(a_cbd_refresh_spec, { revision_id: r.id })) {
					showAlert(`CBD refreshed from the latest published ${Util.stageLabel(r.stage)} specsheet.`, 'success');
					await CbdCtrl.refresh(r.id);   // acuan & baris berubah (R13: stage tetap)
				}
				break;
		}
	},

	// ---- harga (modal mdlCbdHarga) ----
	priceLine() {
		return this.lines().find(l => l.id === this.priceLineId) || null;
	},

	// R17: ESTIMATE & PROPOSE memuat estimasi terakhir dulu (saran / isian awal); gagal dimuat = tanpa saran
	async openPrice(lineId, mode) {
		this.priceLineId = lineId || '';
		this.priceMode = mode === 'PROPOSE' || mode === 'ESTIMATE' ? mode : 'QUOTATION';
		this.priceHint = null;
		if (this.priceMode !== 'QUOTATION' && lineId) {
			try {
				await q_cbd_estimate_hint.run({ line_id: lineId });
				this.priceHint = (q_cbd_estimate_hint.data && q_cbd_estimate_hint.data[0]) || null;
			} catch (e) {
				this.priceHint = null;
			}
		}
		this.priceBusy = false;
		this.priceMsg = null;
		this.priceKey = this.priceKey + 1;
		showModal('mdlCbdHarga');
	},

	priceFormModel() {
		const l = this.priceLine();
		const mode = this.priceMode;
		const q = mode === 'QUOTATION';
		const est = mode === 'ESTIMATE';
		const h = this.priceHint && this.priceHint.price != null ? this.priceHint : null;
		const hintLabel = h ? `${h.source_label || ''}${h.entered_on ? ', ' + h.entered_on : ''}` : '';
		const direct = Auth.can('approve_price');
		const fmt = (v, cur) => `${Util.fmtNum(v, cur === 'USD' ? 4 : 2)} ${cur || ''}`.trim();
		let current = '';
		let info = '';
		if (l) {
			if (l.price_original != null) {
				const src = { MASTER: 'master price', OVERRIDE: 'override', QUOTATION: 'quotation', ESTIMATE: 'estimate' }[l.price_source] || '';
				current = `Price in this CBD: ${fmt(l.price_original, l.currency)}${src ? ' (' + src + ')' : ''}`;
			} else {
				current = 'Price in this CBD: empty';
			}
			if (est) {
				info = 'No Material Code yet. Estimates are allowed in Pullover and Preview only; from SMS the master price is required.';
			} else if (!q) {
				info = l.master_price != null ? `Current master price: ${fmt(l.master_price, l.master_currency)}.`
					: 'No active master price for this Material Code + supplier.';
				if (h) info += ` Price filled in from the estimate ${fmt(h.price, h.currency)} (${hintLabel}). Check it before saving.`;
			}
		}
		const own = l && l.price_original != null && l.price_source === (q ? 'QUOTATION' : est ? 'ESTIMATE' : 'OVERRIDE');
		const prefill = !q && !est && h;     // R17: isian awal Propose master price = estimasi terakhir
		return {
			key: this.priceKey,
			mode: this.priceMode,
			direct,
			today: moment().utcOffset(7).format('YYYY-MM-DD'),
			title: q ? 'Quotation Price' : est ? 'Estimate Price' : (direct ? 'New Master Price' : 'Propose Master Price'),
			lineLabel: l ? [l.display_no, l.display_name, [l.material_code, l.material_name].filter(x => x).join(' '), l.color, l.supplier_name]
				.filter(x => x).join(' · ') : '',
			current,
			form: {
				price: own ? String(Number(l.price_original)) : prefill ? String(Number(h.price)) : '',
				currency: own && est ? l.currency : prefill ? h.currency : '',
				text: l && (q || est) ? (l.price_reference || '') : '',   // referensi master = no. penawaran supplier (tidak dari estimasi)
			},
			suggestion: est && h ? { price: Number(h.price), currency: h.currency, label: hintLabel, reference: h.reference || '' } : null,
			info,
			busy: this.priceBusy,
			message: this.priceMsg,
		};
	},

	async savePrice() {
		const f = cwCbdPriceForm.model || {};   // baca dulu
		const l = this.priceLine();
		if (!l) return;
		const q = this.priceMode !== 'PROPOSE';      // QUOTATION / ESTIMATE (R17) lewat satu fungsi DB; override dihapus F10b
		const est = this.priceMode === 'ESTIMATE';
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
				showAlert('Session expired. Please log in again.', 'warning');
				navigateTo('Login');
				return;
			}
			this.priceMsg = { type: 'error', text: Util.cleanError(msg) };
			return;
		} finally {
			this.priceBusy = false;
		}
		closeModal('mdlCbdHarga');
		showAlert(est ? (f.price ? 'Estimate saved.' : 'Estimate cleared.')
			: q ? (f.price ? 'Quotation price saved.' : 'Quotation price cleared.')
			: Auth.can('approve_price') ? 'Master price saved and active now. Vendor CBD needs to click Refresh Prices from Master.'
				: 'Master price proposal sent to Manager Costing. After approval, click Refresh Prices from Master.', 'success');
		this.message = null;
		await this.reload();
	},
}
