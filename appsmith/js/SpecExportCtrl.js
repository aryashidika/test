// JSObject "SpecExportCtrl" - page Specsheet: Export Excel revisi yang sedang dibuka. Layout mengikuti contoh user
// "SS_SPECS_FH26_FOOTBALL_ACC ILLUZION IV ELITE FG_PROD.pdf" (SPECIFICATION SHEET OF MATERIAL & COMPONENT), tanpa
// kotak validasi (Dibuat / Diketahui / Divalidasi), tanpa gambar/logo, tanpa highlight. File ditulis JSObject
// XlsxWriter (tanpa library). Data = query yang sudah dimuat page ini (q_spec_model, q_revisions, q_rev_articles,
// q_bom_grid, q_change_log), jadi isi file sama dengan layar dan Brand hanya bisa mengekspor revisi terbit.
// R16: sel warna tanpa Material Code (sel kuning di layar) diberi latar kuning + tulisan "(no code)" di Excel, supaya jelas kode
// mana yang harus diminta ke tim material. Hanya satu sheet, tanpa tombol terpisah.
export default {
	busy: false,
	step: '',      // langkah export yang sedang berjalan (untuk pesan error)

	// PURPOSE dicentang otomatis dari stage (R15: 5 stage sesuai sistem, 2 kolom x 3 baris)
	PURPOSES: ['PULL', 'PREV', 'SMS', 'GTM', 'PROD'],

	canExport() {
		return !!SpecCtrl.revision() && !this.busy;
	},

	fileName(...parts) {
		return parts.filter(p => p).join('_').replace(/[\\/:*?"<>|\s]+/g, '-') + '.xlsx';
	},

	// Garis tipis - objek baru setiap kali (gaya jangan disimpan sebagai variabel JSObject)
	thin() {
		const s = () => ({ style: 'thin', color: { argb: 'FF000000' } });
		return { top: s(), left: s(), bottom: s(), right: s() };
	},

	underline() {
		return { bottom: { style: 'thin', color: { argb: 'FF000000' } } };
	},

	// Tulis file (JSObject XlsxWriter, tanpa ExcelJS - T43) lalu unduh. this.step = langkah yang sedang berjalan.
	async save(wb, name) {
		this.step = 'writing the file';
		const b64 = wb.toBase64();
		this.step = 'downloading';
		const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
		await download(`data:${mime};base64,${b64}`, name, mime);
	},

	// ---- tombol Export Excel ----
	async exportExcel() {
		const m = SpecCtrl.model();
		const s = SpecCtrl.season();
		const r = SpecCtrl.revision();
		if (!m || !s || !r) return showAlert('Open a specsheet revision first.', 'warning');
		this.busy = true;
		this.step = 'building the content';
		try {
			const wb = this.build(m, s, r);
			await this.save(wb, this.fileName('Specsheet', m.name, s.season, `${Util.stageLabel(r.stage)}-r${r.revision_no}`, r.status === 'DRAFT' ? 'DRAFT' : ''));
			showAlert('Specsheet Excel file downloaded.', 'success');
		} catch (e) {
			showAlert(`Export failed while ${this.step}: ` + Util.cleanError((e && e.message) || String(e)), 'error');
		} finally {
			this.busy = false;
		}
	},

	// Kolom: A NO · B COMPONENT NAME · C MATERIAL DESCRIPTION · D SOURCE OF MATERIAL · satu kolom warna per article
	// aktif · UNIT OF MSRMNT · THICKNESS (F10c) · PROCESS. Baris 1–11 = header (diulang tiap halaman cetak), data mulai baris 12.
	build(m, s, r) {
		const articles = BomCtrl.activeArticles();
		const lines = BomCtrl.gridLines();     // baris revisi yang dibuka saja (R12, T62)
		const log = r.status === 'PUBLISHED' ? SpecCtrl.logFor(r.id) : null;
		const K = Math.max(articles.length, 1);
		const A0 = 5;                 // kolom article pertama (E)
		const UOM = A0 + K;
		const THK = UOM + 1;
		const PROC = THK + 1;
		const N = PROC;
		const v = x => (x === null || x === undefined || x === '' ? '-' : String(x));

		const wb = XlsxWriter.workbook();
		wb.creator = (Auth.me && Auth.me.full_name) || '';
		wb.created = new Date();
		const ws = wb.addWorksheet('Specsheet', {
			pageSetup: { orientation: 'landscape', paperSize: 9, fitToPage: true, fitToWidth: 1, fitToHeight: 0 },
		});
		[6, 24, 46, 20].concat(articles.length ? articles.map(() => 22) : [22], [11, 11, 20])
			.forEach((w, i) => { ws.getColumn(i + 1).width = w; });
		const cell = (row, col, value, style) => {
			const c = ws.getRow(row).getCell(col);
			c.value = value;
			if (style) Object.keys(style).forEach(k => { c[k] = style[k]; });
			return c;
		};
		const merge = (r1, c1, r2, c2) => { if (r1 !== r2 || c1 !== c2) ws.mergeCells(r1, c1, r2, c2); };
		const box = (r1, c1, r2, c2) => {
			for (let i = r1; i <= r2; i++) for (let c = c1; c <= c2; c++) ws.getRow(i).getCell(c).border = this.thin();
		};
		const small = { font: { size: 9 } };

		// ---- baris 1: judul ----
		cell(1, 1, 'SPECIFICATION SHEET OF MATERIAL & COMPONENT', {
			font: { bold: true, size: 12, color: { argb: 'FFFFFFFF' } },
			fill: { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF000000' } },
			alignment: { horizontal: 'center', vertical: 'middle' },
		});
		merge(1, 1, 1, N);
		ws.getRow(1).height = 20;

		// ---- baris 2–4: factory, revision, season, purpose ----
		const revDate = r.published_at || r.created_at || null;
		cell(2, 1, 'FACTORY', small);
		cell(2, 2, `:  ${v(m.factory)}`, { font: { size: 9 }, border: this.underline() });
		cell(3, 1, 'REVISION', small);
		cell(3, 2, `:  ${revDate ? moment(revDate).utcOffset(7).format('DD/MM/YYYY') : 'not published'}`,
			{ font: { size: 11, color: { argb: 'FF1D4ED8' } }, border: this.underline() });
		cell(2, 3, s.season, { font: { size: 22, color: { argb: 'FF374151' } }, alignment: { horizontal: 'center', vertical: 'middle' } });
		merge(2, 3, 4, 3);
		cell(2, 4, 'PURPOSE :', { font: { size: 9 }, alignment: { horizontal: 'right' } });
		const mid = A0 + Math.ceil((N - A0 + 1) / 2);
		this.PURPOSES.forEach((st, i) => {
			const c1 = i < 3 ? A0 : mid;
			const c2 = i < 3 ? mid - 1 : N;
			cell(2 + (i % 3), c1, `${st === r.stage ? '☑' : '☐'}  ${Util.stageLabel(st)}`,
				{ font: { size: 10, bold: st === r.stage } });
			merge(2 + (i % 3), c1, 2 + (i % 3), c2);
		});

		// ---- baris 5–8: info model (kiri), info revisi (kanan, pengganti kotak validasi) ----
		cell(5, 1, 'MODEL NAME  :', small);
		merge(5, 1, 5, 2);
		cell(6, 1, m.name || '-', { font: { size: 14 }, alignment: { vertical: 'middle' } });
		merge(6, 1, 6, 2);
		cell(7, 1, `CATEGORY  :  ${v(m.category)}`, small);
		merge(7, 1, 7, 2);
		cell(8, 1, `OUTSOLE MOULD  :  ${v(m.outsole_mold)}`, small);
		merge(8, 1, 8, 2);
		[['LAST No.', m.last_no], ['CONSTRUCTION', m.construction], ['SIZE RANGE', m.size_range], ['SAMPLE SIZE', m.sample_size]]
			.forEach(([k, val], i) => {
				cell(5 + i, 3, `${k}  :  ${v(val)}`, { font: { size: 9 }, border: this.underline() });
			});
		cell(5, A0, `GENDER  :  ${v(m.gender)}`, small);
		cell(6, A0, `STAGE ${Util.stageLabel(r.stage).toUpperCase()} · REVISION ${r.revision_no} · ${r.status}`
			+ (r.status === 'PUBLISHED' ? (r.published_by ? ` · published by ${r.published_by}` : '') : ' · NOT PUBLISHED'),
		{ font: { bold: true, size: 10, color: { argb: r.status === 'PUBLISHED' ? 'FF16A34A' : 'FFDC2626' } } });
		if (log) cell(7, A0, `Change (${log.category}): ${log.reason}`, { font: { size: 9, italic: true, color: { argb: 'FF6B7280' } }, alignment: { wrapText: true, vertical: 'top' } });
		[5, 6].forEach(i => merge(i, A0, i, N));
		merge(7, A0, 8, N);
		// garis luar blok header saja (bukan kisi penuh) + garis bawah isian
		for (let i = 2; i <= 8; i++) {
			for (let c = 1; c <= N; c++) {
				const b = {};
				if (i === 2) b.top = { style: 'thin', color: { argb: 'FF000000' } };
				if (i === 4 || i === 8) b.bottom = { style: 'thin', color: { argb: 'FF000000' } };
				if (c === 1) b.left = { style: 'thin', color: { argb: 'FF000000' } };
				if (c === N) b.right = { style: 'thin', color: { argb: 'FF000000' } };
				if (c === A0 && i >= 5) b.left = { style: 'thin', color: { argb: 'FF000000' } };
				const keep = ws.getRow(i).getCell(c);
				const under = (i >= 5 && c === 3) || ((i === 2 || i === 3) && c === 2);
				if (under) b.bottom = { style: 'thin', color: { argb: 'FF000000' } };
				keep.border = b;
			}
		}

		// ---- baris 9–11: header tabel ----
		const hd = { font: { bold: true, size: 10 }, alignment: { horizontal: 'center', vertical: 'middle', wrapText: true } };
		[['NO.', 1], ['COMPONENT NAME', 2], ['MATERIAL DESCRIPTION', 3], ['SOURCE OF MATERIAL', 4], ['UNIT OF MSRMNT', UOM], ['DIMENSION', THK], ['PROCESS', PROC]]
			.forEach(([t, c]) => { cell(9, c, t, hd); merge(9, c, 11, c); });
		cell(9, A0, 'ARTICLE NO.', hd);
		merge(9, A0, 9, A0 + K - 1);
		if (articles.length) {
			articles.forEach((a, i) => {
				cell(10, A0 + i, a.code, Object.assign({}, hd, { font: { bold: true, size: 11 } }));
				cell(11, A0 + i, a.colorway || '-', hd);
			});
		} else {
			cell(10, A0, 'No active articles', hd);
			merge(10, A0, 11, A0);
		}
		box(9, 1, 11, N);
		ws.getRow(11).height = 30;

		// ---- data ----
		let yellow = 0;      // R16: sel warna tanpa Material Code
		let row = 12;
		let parentRow = null;
		const closeParent = () => {
			if (parentRow !== null && row - 1 > parentRow) {
				merge(parentRow, 1, row - 1, 1);
				merge(parentRow, 2, row - 1, 2);
			}
		};
		const top = h => ({ vertical: 'middle', horizontal: h, wrapText: true });
		lines.forEach(l => {
			if (!l.is_sub) { closeParent(); parentRow = row; }
			const mat = l.material_name || '';
			cell(row, 1, l.is_sub ? '' : (l.display_no || ''), { alignment: top('center') });
			cell(row, 2, l.is_sub ? '' : (l.display_name || '') + (l.is_local ? ' (local)' : ''), { alignment: top() });
			cell(row, 3, l.is_sub && l.display_name && l.display_name !== l.material_name ? `${l.display_name} · ${mat}` : mat, { alignment: top() });
			cell(row, 4, l.supplier_name || '', { alignment: top('center') });
			const cells = typeof l.cells === 'string' ? JSON.parse(l.cells || '{}') : (l.cells || {});
			const codes = typeof l.cell_codes === 'string' ? JSON.parse(l.cell_codes || '{}') : (l.cell_codes || {});
			// R4: warna + Material Code varian di bawahnya
			articles.forEach((a, i) => {
				const color = cells[a.id] || '';
				const noCode = !!color && !codes[a.id];
				if (noCode) yellow++;
				cell(row, A0 + i, color && codes[a.id] ? `${color}\n${codes[a.id]}` : (noCode ? `${color}\n(no code)` : color),
					noCode ? { alignment: top('center'), fill: { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFEF08A' } } }
					  : { alignment: top('center') });
			});
			cell(row, UOM, l.uom || '', { alignment: top('center') });
			cell(row, THK, l.thickness || '', { alignment: top('center') });
			cell(row, PROC, l.process || '', { alignment: top() });
			if (!l.is_sub) ws.getRow(row).getCell(1).alignment = top('center');
			box(row, 1, row, N);
			row++;
		});
		closeParent();
		if (yellow && !log) {
			cell(7, A0, `YELLOW = no Material Code yet (${yellow} cell(s)). Ask the Material team for these codes.`,
				{ font: { size: 9, bold: true, color: { argb: 'FF92400E' } }, alignment: { wrapText: true, vertical: 'top' } });
		}
		if (!lines.length) {
			cell(row, 1, 'No BOM lines yet.', { font: { italic: true } });
			merge(row, 1, row, N);
			box(row, 1, row, N);
		}

		ws.views = [{ state: 'frozen', xSplit: 0, ySplit: 11 }];
		ws.printTitleRows = '1:11';
		ws.footer = `${m.name} ${s.season} ${Util.revLabel(r)} · Page &P / &N`;
		return wb;
	},
}
