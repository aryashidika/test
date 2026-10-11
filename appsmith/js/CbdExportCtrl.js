// JSObject "CbdExportCtrl" — page Cost Breakdown (CBD): Export Excel revisi CBD yang sedang dibuka. Layout mengikuti
// contoh user "FH26_CBD PRODUCTION_ACC ILLUZION IV ELITE FG PRM 097.xlsx": header (kurs 1 $ = …), tabel material per
// grup + subtotal, baris MISSING_IN_SPEC (tidak dihitung), Cost recapitulation, Target FOB, baris PO (R5, ganti blok Harga jual), change log.
// Sel hitungan berisi RUMUS Excel (Usage = 1/Yield, IDR = USD × kurs, Cost/pr, SUM, selisih) beserta hasilnya dari DB,
// jadi file tetap hidup bila diubah di Excel dan langsung tampil benar. File ditulis JSObject XlsxWriter (tanpa library).
// Data = query yang sudah dimuat page ini (Brand hanya revisi terbit). Tidak ada query baru (q_cbd_model + 3 kolom).
export default {
	busy: false,
	step: '',      // langkah export yang sedang berjalan (untuk pesan error)

	NAVY: 'FF122A52',
	GROUP_FILL: 'FFDCE4F3',
	MISSING_FILL: 'FFFCEFD8',
	RP: '_-"Rp"* #,##0.00_-;\\-"Rp"* #,##0.00_-;_-"Rp"* "-"??_-;_-@_-',
	USD: '_-[$$-409]* #,##0.0000_ ;_-[$$-409]* \\-#,##0.0000\\ ;_-[$$-409]* "-"??_ ;_-@_ ',
	COST_LABEL: { LABOUR: 'Direct Labour', AMORTIZATION: 'Amortisasi', ADJUSTMENT: 'Adjustment', OTHER: 'Lainnya' },

	canExport() {
		return !!CbdCtrl.revision() && !this.busy;
	},

	n(v) {
		if (v === null || v === undefined || v === '') return null;
		const x = Number(v);
		return Number.isFinite(x) ? x : null;
	},

	fileName(...parts) {
		return parts.filter(p => p).join('_').replace(/[\\/:*?"<>|\s]+/g, '-') + '.xlsx';
	},

	box(row, from, to) {
		for (let c = from; c <= to; c++) {
			row.getCell(c).border = this.thin();
		}
	},

	fill(row, from, to, argb) {
		for (let c = from; c <= to; c++) row.getCell(c).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb } };
	},

	// Rumus + hasil (hasil dari DB supaya tampil tanpa dihitung ulang)
	f(formula, result) {
		return result === null || result === undefined ? { formula } : { formula, result };
	},

	// Garis tipis — objek baru setiap kali (gaya jangan disimpan sebagai variabel JSObject)
	thin() {
		const s = () => ({ style: 'thin', color: { argb: 'FFC9CFDB' } });
		return { top: s(), left: s(), bottom: s(), right: s() };
	},

	// Tulis file (JSObject XlsxWriter, tanpa ExcelJS — T43) lalu unduh. this.step = langkah yang sedang berjalan.
	async save(wb, name) {
		this.step = 'menulis file';
		const b64 = wb.toBase64();
		this.step = 'mengunduh';
		const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
		await download(`data:${mime};base64,${b64}`, name, mime);
	},

	// ---- tombol Export Excel ----
	async exportExcel() {
		const m = CbdCtrl.model();
		const s = CbdCtrl.season();
		const a = CbdCtrl.article();
		const r = CbdCtrl.revision();
		if (!m || !s || !a || !r) return showAlert('Buka revisi CBD dulu.', 'warning');
		this.busy = true;
		this.step = 'menyusun isi';
		try {
			const wb = this.build(m, s, a, r);
			await this.save(wb, this.fileName('CBD', m.name, s.season, a.code, `${r.stage}-r${r.revision_no}`, r.status === 'DRAFT' ? 'DRAFT' : ''));
			showAlert('File Excel CBD diunduh.', 'success');
		} catch (e) {
			showAlert(`Export gagal saat ${this.step}: ` + Util.cleanError((e && e.message) || String(e)), 'error');
		} finally {
			this.busy = false;
		}
	},

	// Kolom: A No · B Component Name · C Material description · D Thickness · E Unit · F Color · G Yield · H Usage ·
	// I Loss % · J Unit price USD · K Unit price IDR · L Cost/pr (Rp) · M Supplier · N Remarks · O Asal harga / nilai
	build(m, s, a, r) {
		const N = 15;
		const lines = CbdGridCtrl.lines();
		const rc = CbdGridCtrl.recap() || {};
		const items = CbdGridCtrl.costItems();
		const log = r.status === 'PUBLISHED' ? CbdCtrl.logFor(r.id) : null;
		const rate = this.n(r.exchange_rate);

		const wb = XlsxWriter.workbook();
		wb.creator = (Auth.me && Auth.me.full_name) || '';
		wb.created = new Date();
		const ws = wb.addWorksheet(`${a.code} ${r.stage} r${r.revision_no}`.slice(0, 31), {
			pageSetup: { orientation: 'landscape', paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0 },
		});
		[6, 24, 34, 11, 9, 18, 10, 10, 8, 13, 15, 17, 18, 20, 16].forEach((w, i) => { ws.getColumn(i + 1).width = w; });

		// ---- header (baris 1–8) ----
		ws.getCell('A1').value = 'Cost Breakdown Sheet';
		ws.getCell('A1').font = { bold: true, size: 16, color: { argb: this.NAVY } };
		ws.getCell('A2').value = 'Confidential Information';
		ws.getCell('A2').font = { italic: true, color: { argb: 'FF6B7280' } };
		ws.getCell('K2').value = 'Tanggal';
		ws.getCell('L2').value = new Date(r.status === 'PUBLISHED' && r.published_at ? r.published_at : Date.now());
		ws.getCell('L2').numFmt = 'dd-mmm-yyyy';
		ws.getCell('K3').value = '1 $ =';
		ws.getCell('K3').alignment = { horizontal: 'right' };
		ws.getCell('L3').value = rate;
		ws.getCell('L3').numFmt = this.RP;
		ws.getCell('L3').font = { bold: true, size: 14 };
		const v = x => x || '-';
		const info = [
			['Model Name', `${m.name} (${v(m.factory_name)}); Mold: ${v(m.outsole_mold)}; Last: ${v(m.last_no)}; Size Range: ${v(m.size_range)}`],
			['Article #', `${a.code}`],
			['Construction', v(m.construction)],
			['Color', v(a.colorway)],
			['Season / Revisi', `${s.season} · ${r.stage} r${r.revision_no} · ${r.status}`
				+ (r.status === 'PUBLISHED' ? ` · terbit oleh ${r.published_by || '-'}` : ' · BELUM TERBIT')
				+ ` · acuan specsheet ${r.spec_label || '-'}`],
		];
		info.forEach(([k, val], i) => {
			ws.getCell(`B${4 + i}`).value = k;
			ws.getCell(`B${4 + i}`).font = { bold: true };
			ws.getCell(`C${4 + i}`).value = val;
		});
		ws.getCell('C8').font = { bold: true, color: { argb: r.status === 'PUBLISHED' ? 'FF16A34A' : 'FFDC2626' } };

		// ---- header tabel (baris 10–11) ----
		const h1 = ws.getRow(10);
		const h2 = ws.getRow(11);
		['No', 'Component Name', 'Material description', 'Thickness', 'Unit', 'Color', 'Yield', 'Usage', 'Loss %',
			'Unit Price', '', 'Cost/pr (Rp)', 'Supplier', 'Remarks', 'Asal'].forEach((t, i) => { h1.getCell(i + 1).value = t; });
		h2.getCell(10).value = 'USD';
		h2.getCell(11).value = 'IDR';
		ws.mergeCells('J10:K10');
		[1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 13, 14, 15].forEach(c => ws.mergeCells(10, c, 11, c));
		[h1, h2].forEach(row => {
			this.fill(row, 1, N, this.NAVY);
			this.box(row, 1, N);
			for (let c = 1; c <= N; c++) {
				row.getCell(c).font = { bold: true, color: { argb: 'FFFFFFFF' } };
				row.getCell(c).alignment = { horizontal: 'center', vertical: 'middle', wrapText: true };
			}
		});

		// ---- baris material ----
		const writeLine = (l, counted) => {
			const row = ws.addRow([]);
			const i = row.number;
			const y = this.n(l.yield_value);
			const p = this.n(l.price_original);
			row.getCell(1).value = l.is_sub ? '' : (l.display_no || '');
			row.getCell(2).value = (l.is_sub ? '↳ ' : '') + (l.display_name || '') + (l.is_local ? ' (lokal)' : '');
			row.getCell(3).value = `${l.material_name || ''}${l.material_code ? ' [' + l.material_code + ']' : ''}`;
			row.getCell(4).value = l.thickness || '';
			row.getCell(5).value = l.uom || '';
			row.getCell(6).value = l.color || '';
			row.getCell(7).value = y;
			row.getCell(8).value = y ? this.f(`1/G${i}`, this.n(l.usage_value)) : null;
			row.getCell(9).value = this.n(l.loss_pct) ?? 0;
			if (p !== null && l.currency === 'USD') {
				row.getCell(10).value = p;
				row.getCell(11).value = this.f(`J${i}*$L$3`, this.n(l.price_idr));
			} else if (p !== null) {
				row.getCell(11).value = p;
			}
			if (counted && y && p !== null && (l.currency === 'IDR' || rate)) {
				row.getCell(12).value = this.f(`H${i}*(1+I${i}/100)*K${i}`, this.n(l.cost_per_pair));
			}
			row.getCell(13).value = l.supplier_name || '';
			row.getCell(14).value = l.remarks || '';
			const src = { MASTER: 'harga master', OVERRIDE: 'override', QUOTATION: 'quotation' }[l.price_source] || 'tanpa harga';
			const org = { INPUT: '', COPIED: ' · copy', CARRIED_FROM_REPLACED: ' · ganti material' }[l.value_origin] || '';
			row.getCell(15).value = src + org + (l.price_source === 'OVERRIDE' && l.price_override_reason ? `: ${l.price_override_reason}` : '');
			row.getCell(7).numFmt = '#,##0.00####';
			row.getCell(8).numFmt = '0.000000';
			row.getCell(9).numFmt = '0.00';
			row.getCell(10).numFmt = this.USD;
			row.getCell(11).numFmt = this.RP;
			row.getCell(12).numFmt = this.RP;
			this.box(row, 1, N);
			for (let c = 1; c <= N; c++) row.getCell(c).alignment = { vertical: 'top', wrapText: c <= 6 || c >= 13 };
			if (!counted) for (let c = 1; c <= N; c++) row.getCell(c).font = { color: { argb: 'FF9CA3AF' } };
			return i;
		};

		const groupHeader = (label, argb) => {
			const row = ws.addRow([label]);
			ws.mergeCells(row.number, 1, row.number, N);
			row.getCell(1).font = { bold: true, color: { argb: this.NAVY } };
			this.fill(row, 1, N, argb);
		};

		const active = lines.filter(l => l.status === 'ACTIVE');
		const missing = lines.filter(l => l.status !== 'ACTIVE');
		const groups = [];
		active.forEach(l => {
			let g = groups[groups.length - 1];
			if (!g || g.code !== l.group_code) groups.push(g = { code: l.group_code, name: l.group_name, lines: [] });
			g.lines.push(l);
		});
		const subtotalCells = [];
		const gc = rc.group_costs || {};
		groups.forEach(g => {
			groupHeader(`${String(g.code || '').toLowerCase()}. ${g.name || ''}`, this.GROUP_FILL);
			const rows = g.lines.map(l => writeLine(l, true));
			const st = ws.addRow([]);
			st.getCell(2).value = `Subtotal ${String(g.code || '').toUpperCase()} · ${g.name || ''}`;
			st.getCell(12).value = this.f(`SUM(L${rows[0]}:L${rows[rows.length - 1]})`, this.n(gc[g.code]) ?? 0);
			st.getCell(12).numFmt = this.RP;
			st.font = { bold: true };
			this.box(st, 1, N);
			subtotalCells.push(`L${st.number}`);
			ws.addRow([]);
		});
		if (!groups.length) ws.addRow(['Belum ada baris CBD.']);
		if (missing.length) {
			groupHeader(`Hilang dari specsheet (MISSING_IN_SPEC) — ${missing.length} baris, tidak dihitung`, this.MISSING_FILL);
			missing.forEach(l => writeLine(l, false));
			ws.addRow([]);
		}

		// ---- Cost recapitulation (kolom G–L, keterangan di M) ----
		ws.addRow([]);
		const title = ws.addRow([]);
		title.getCell(7).value = 'Cost recapitulation';
		title.getCell(7).font = { bold: true, size: 12, color: { argb: this.NAVY } };
		const recapRow = (label, value, note, bold) => {
			const row = ws.addRow([]);
			row.getCell(7).value = label;
			row.getCell(12).value = value;
			row.getCell(12).numFmt = this.RP;
			if (note) row.getCell(13).value = note;
			if (bold) row.font = { bold: true };
			ws.mergeCells(row.number, 7, row.number, 11);
			this.box(row, 7, 13);
			return row.number;
		};
		const letter = i => String.fromCharCode(97 + i) + '.';
		const first = recapRow(`${letter(0)} Material Cost`,
			this.f(subtotalCells.length ? `SUM(${subtotalCells.join(',')})` : '0', this.n(rc.material_cost) ?? 0), '', true);
		let last = first;
		items.forEach((it, i) => {
			last = recapRow(`${letter(i + 1)} ${it.name || this.COST_LABEL[it.item_type]}`, this.n(it.amount) ?? 0, it.remarks || '');
		});
		const fobRow = recapRow('ACTUAL FOB', this.f(`SUM(L${first}:L${last})`, this.n(rc.actual_fob)), 'material cost + semua biaya', true);
		ws.getRow(fobRow).getCell(12).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: this.GROUP_FILL } };

		ws.addRow([]);
		const tRow = ws.addRow([]);
		tRow.getCell(11).value = 'TARGET FOB';
		tRow.getCell(12).value = this.n(rc.target_fob);
		tRow.getCell(12).numFmt = this.RP;
		const t = tRow.number;
		const vRow = ws.addRow([]);
		if (tRow.getCell(12).value !== null) {
			vRow.getCell(11).value = this.f(`IF(L${fobRow}>L${t},"OVER",IF(L${fobRow}<L${t},"UNDER","SESUAI"))`, rc.variance_label || null);
			vRow.getCell(12).value = this.f(`L${fobRow}-L${t}`, this.n(rc.variance));
			vRow.getCell(12).numFmt = this.RP;
			vRow.getCell(11).font = { bold: true, color: { argb: rc.variance_label === 'OVER' ? 'FFDC2626' : 'FF16A34A' } };
		}
		[tRow, vRow].forEach(row => { row.getCell(11).alignment = { horizontal: 'right' }; });

		// ---- R5: PO (mis. SMS = Actual FOB x 1,25). Selling price & margin tidak ada di CBD. ----
		const factor = this.n(rc.po_factor);
		if (factor) {
			const pRow = recapRow(`PO ${r.stage} (Actual FOB × ${String(factor).replace('.', ',')})`,
				this.f(`ROUND(L${fobRow}*${factor},2)`, this.n(rc.po_price)), 'harga PO ke brand', true);
			ws.getRow(pRow).getCell(12).fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: this.GROUP_FILL } };
		}

		// ---- change log revisi ini ----
		if (log) {
			ws.addRow([]);
			const c = ws.addRow(['', 'Change log']);
			c.getCell(2).font = { bold: true };
			const ch = ws.addRow(['', 'Tanggal', 'Kategori', 'Oleh', '', 'Alasan']);
			ch.font = { bold: true };
			ws.addRow(['', moment(log.created_at).format('DD-MM-YYYY HH:mm'), log.category, log.created_by, '', log.reason]);
		}

		ws.views = [{ state: 'frozen', xSplit: 3, ySplit: 11 }];
		return wb;
	},
}
