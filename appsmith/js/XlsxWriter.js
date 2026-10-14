// JSObject "XlsxWriter" - penulis file .xlsx TANPA library (pengganti ExcelJS, T43: ExcelJS di worker Appsmith memicu
// "Maximum call stack size exceeded"). Tempel di page Specsheet DAN page Cost Breakdown (CBD) dengan nama sama.
// API = bagian kecil ExcelJS yang dipakai SpecExportCtrl / CbdExportCtrl:
//   const wb = XlsxWriter.workbook(); const ws = wb.addWorksheet(name, { pageSetup });
//   ws.addRow([...]) / ws.getRow(n) / ws.getCell('A1') / ws.getColumn(c).width / ws.mergeCells('J10:K10' | r1,c1,r2,c2)
//   ws.views = [{ state: 'frozen', xSplit, ySplit }]; ws.printTitleRows = '1:11'; ws.footer = 'Page &P / &N'
//   row.number / row.height / row.font / row.getCell(c)
//   cell.value (teks, angka, Date, { formula, result }) / font / fill / border / alignment / numFmt
//   wb.toBase64() -> isi file .xlsx (zip tanpa kompresi) dalam base64.
// Semua loop biasa: tanpa rekursi, spread, apply, btoa, TextEncoder (aman untuk stack worker Appsmith yang kecil).
export default {
	workbook() {
		const MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
		const REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
		const PKG = 'http://schemas.openxmlformats.org/package/2006/relationships';
		const HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

		const esc = s => String(s)
			.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
			.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
		const colName = c => {
			let s = '';
			while (c > 0) {
				const m = (c - 1) % 26;
				s = String.fromCharCode(65 + m) + s;
				c = Math.floor((c - 1) / 26);
			}
			return s;
		};
		const parseRef = ref => {
			const m = /^([A-Z]+)(\d+)$/.exec(String(ref).trim().toUpperCase());
			if (!m) throw new Error('Invalid cell address: ' + ref);
			let c = 0;
			for (let i = 0; i < m[1].length; i++) c = c * 26 + m[1].charCodeAt(i) - 64;
			return [Number(m[2]), c];
		};
		const isDate = v => Object.prototype.toString.call(v) === '[object Date]' && !isNaN(v.getTime());
		const serial = d => (d.getTime() - d.getTimezoneOffset() * 60000) / 86400000 + 25569;

		// ---------- worksheet ----------
		const sheets = [];
		const makeSheet = (name, opts) => {
			const rows = {};
			const cols = {};
			const merges = [];
			let last = 0;
			const getRow = n => {
				if (!rows[n]) {
					const cells = {};
					rows[n] = {
						number: n, height: null, font: null, cells,
						getCell(c) {
							if (!cells[c]) cells[c] = { value: null };
							return cells[c];
						},
					};
					if (n > last) last = n;
				}
				return rows[n];
			};
			return {
				name, pageSetup: opts.pageSetup || null, views: [], rows, cols, merges,
				printTitleRows: null,   // mis. '1:11' = baris 1–11 diulang di tiap halaman cetak
				footer: null,           // teks footer tengah; &P = halaman, &N = jumlah halaman
				getRow,
				getColumn(c) {
					if (!cols[c]) cols[c] = { width: null };
					return cols[c];
				},
				getCell(ref) {
					const rc = parseRef(ref);
					return getRow(rc[0]).getCell(rc[1]);
				},
				addRow(values) {
					const row = getRow(last + 1);
					(values || []).forEach((v, i) => { row.getCell(i + 1).value = v; });
					return row;
				},
				mergeCells(a, b, c, d) {
					if (typeof a === 'string') {
						const p = a.split(':');
						const s = parseRef(p[0]);
						const e = parseRef(p[1]);
						merges.push([s[0], s[1], e[0], e[1]]);
					} else {
						merges.push([a, b, c, d]);
					}
				},
			};
		};

		// ---------- styles ----------
		const registry = () => {
			const list = [];
			const idx = {};
			return {
				list,
				add(key, xml) {
					if (!(key in idx)) { idx[key] = list.length; list.push(xml); }
					return idx[key];
				},
			};
		};
		const fonts = registry();
		const fills = registry();
		const borders = registry();
		const xfs = registry();
		const fmts = registry();
		fonts.add('', '<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>');
		fills.add('', '<fill><patternFill patternType="none"/></fill>');
		fills.add('gray125', '<fill><patternFill patternType="gray125"/></fill>');
		borders.add('', '<border><left/><right/><top/><bottom/><diagonal/></border>');
		xfs.add('', '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>');

		const argb = c => (c && c.argb ? `<color rgb="${esc(c.argb)}"/>` : '');
		const fontId = f => {
			if (!f) return 0;
			const key = [f.bold ? 1 : 0, f.italic ? 1 : 0, f.underline ? 1 : 0, f.size || 11, (f.color && f.color.argb) || ''].join('|');
			return fonts.add(key, '<font>' + (f.bold ? '<b/>' : '') + (f.italic ? '<i/>' : '') + (f.underline ? '<u/>' : '')
				+ `<sz val="${f.size || 11}"/>` + argb(f.color) + '<name val="Calibri"/><family val="2"/></font>');
		};
		const fillId = f => {
			const c = f && f.type === 'pattern' && f.pattern === 'solid' && f.fgColor && f.fgColor.argb;
			if (!c) return 0;
			return fills.add(c, `<fill><patternFill patternType="solid"><fgColor rgb="${esc(c)}"/><bgColor indexed="64"/></patternFill></fill>`);
		};
		const borderId = b => {
			if (!b) return 0;
			const side = (tag, s) => (s && s.style ? `<${tag} style="${esc(s.style)}">${argb(s.color)}</${tag}>` : `<${tag}/>`);
			const xml = '<border>' + side('left', b.left) + side('right', b.right) + side('top', b.top) + side('bottom', b.bottom) + '<diagonal/></border>';
			return borders.add(xml, xml);
		};
		const fmtId = f => (f ? 164 + fmts.add(f, f) : 0);
		const alignXml = a => {
			if (!a) return '';
			const v = a.vertical === 'middle' ? 'center' : a.vertical;
			const attrs = (a.horizontal ? ` horizontal="${esc(a.horizontal)}"` : '') + (v ? ` vertical="${esc(v)}"` : '') + (a.wrapText ? ' wrapText="1"' : '');
			return attrs ? `<alignment${attrs}/>` : '';
		};
		const styleId = (cell, rowFont) => {
			const nf = fmtId(cell.numFmt || (isDate(cell.value) ? 'dd-mm-yyyy' : null));
			const fo = fontId(cell.font || rowFont);
			const fi = fillId(cell.fill);
			const bo = borderId(cell.border);
			const al = alignXml(cell.alignment);
			if (!nf && !fo && !fi && !bo && !al) return 0;
			const xml = `<xf numFmtId="${nf}" fontId="${fo}" fillId="${fi}" borderId="${bo}" xfId="0"`
				+ (nf ? ' applyNumberFormat="1"' : '') + (fo ? ' applyFont="1"' : '') + (fi ? ' applyFill="1"' : '')
				+ (bo ? ' applyBorder="1"' : '') + (al ? ` applyAlignment="1">${al}</xf>` : '/>');
			return xfs.add(xml, xml);
		};

		// ---------- sheet XML ----------
		const cellXml = (ref, cell, rowFont) => {
			const s = styleId(cell, rowFont);
			const sa = s ? ` s="${s}"` : '';
			let v = cell.value;
			if (v === null || v === undefined || v === '') return s ? `<c r="${ref}"${sa}/>` : '';
			if (isDate(v)) v = serial(v);
			if (typeof v === 'number') return Number.isFinite(v) ? `<c r="${ref}"${sa}><v>${v}</v></c>` : (s ? `<c r="${ref}"${sa}/>` : '');
			if (typeof v === 'boolean') return `<c r="${ref}"${sa} t="b"><v>${v ? 1 : 0}</v></c>`;
			if (typeof v === 'object' && v.formula !== undefined) {
				const f = `<f>${esc(String(v.formula).replace(/^=/, ''))}</f>`;
				const r = v.result;
				if (typeof r === 'number' && Number.isFinite(r)) return `<c r="${ref}"${sa}>${f}<v>${r}</v></c>`;
				if (typeof r === 'string') return `<c r="${ref}"${sa} t="str">${f}<v>${esc(r)}</v></c>`;
				return `<c r="${ref}"${sa}>${f}</c>`;
			}
			return `<c r="${ref}"${sa} t="inlineStr"><is><t xml:space="preserve">${esc(v)}</t></is></c>`;
		};
		const sheetXml = ws => {
			const out = [HEAD, `<worksheet xmlns="${MAIN}" xmlns:r="${REL}">`];
			if (ws.pageSetup && ws.pageSetup.fitToPage) out.push('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>');
			const fr = (ws.views || []).find(x => x && x.state === 'frozen');
			if (fr && (fr.xSplit || fr.ySplit)) {
				const xs = fr.xSplit || 0;
				const ys = fr.ySplit || 0;
				const pane = xs && ys ? 'bottomRight' : (ys ? 'bottomLeft' : 'topRight');
				out.push('<sheetViews><sheetView workbookViewId="0"><pane' + (xs ? ` xSplit="${xs}"` : '') + (ys ? ` ySplit="${ys}"` : '')
					+ ` topLeftCell="${colName(xs + 1)}${ys + 1}" activePane="${pane}" state="frozen"/><selection pane="${pane}"/></sheetView></sheetViews>`);
			} else {
				out.push('<sheetViews><sheetView workbookViewId="0"/></sheetViews>');
			}
			out.push('<sheetFormatPr defaultRowHeight="15"/>');
			const cn = Object.keys(ws.cols).map(Number).filter(c => ws.cols[c].width).sort((a, b) => a - b);
			if (cn.length) {
				out.push('<cols>');
				cn.forEach(c => out.push(`<col min="${c}" max="${c}" width="${ws.cols[c].width}" customWidth="1"/>`));
				out.push('</cols>');
			}
			out.push('<sheetData>');
			Object.keys(ws.rows).map(Number).sort((a, b) => a - b).forEach(n => {
				const row = ws.rows[n];
				const cells = Object.keys(row.cells).map(Number).sort((a, b) => a - b)
					.map(c => cellXml(colName(c) + n, row.cells[c], row.font)).join('');
				if (cells || row.height) {
					out.push(`<row r="${n}"` + (row.height ? ` ht="${row.height}" customHeight="1"` : '') + `>${cells}</row>`);
				}
			});
			out.push('</sheetData>');
			if (ws.merges.length) {
				out.push(`<mergeCells count="${ws.merges.length}">`);
				ws.merges.forEach(m => out.push(`<mergeCell ref="${colName(m[1])}${m[0]}:${colName(m[3])}${m[2]}"/>`));
				out.push('</mergeCells>');
			}
			out.push('<pageMargins left="0.4" right="0.4" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>');
			const ps = ws.pageSetup;
			if (ps) {
				out.push('<pageSetup' + (ps.paperSize ? ` paperSize="${ps.paperSize}"` : '') + (ps.orientation ? ` orientation="${esc(ps.orientation)}"` : '')
					+ (ps.fitToPage ? ` fitToWidth="${ps.fitToWidth ?? 1}" fitToHeight="${ps.fitToHeight ?? 0}"` : '') + '/>');
			}
			if (ws.footer) out.push(`<headerFooter><oddFooter>&amp;C${esc(ws.footer)}</oddFooter></headerFooter>`);
			out.push('</worksheet>');
			return out.join('');
		};

		// ---------- package ----------
		const files = wb => {
			const names = {};
			const list = sheets.map((ws, i) => {
				let nm = String(ws.name || `Sheet${i + 1}`).replace(/[\\/?*[\]:]/g, ' ').slice(0, 31).trim() || `Sheet${i + 1}`;
				while (names[nm.toLowerCase()]) nm = (nm.slice(0, 28) + ' ' + (i + 1)).slice(0, 31);
				names[nm.toLowerCase()] = true;
				return { name: nm, xml: sheetXml(ws), titles: ws.printTitleRows };
			});
			const defined = list.map((s, i) => {
				const m = /^(\d+):(\d+)$/.exec(String(s.titles || ''));
				return m ? `<definedName name="_xlnm.Print_Titles" localSheetId="${i}">'${esc(s.name.replace(/'/g, "''"))}'!$${m[1]}:$${m[2]}</definedName>` : '';
			}).join('');
			const fmtXml = fmts.list.length
				? `<numFmts count="${fmts.list.length}">` + fmts.list.map((f, i) => `<numFmt numFmtId="${164 + i}" formatCode="${esc(f)}"/>`).join('') + '</numFmts>'
				: '';
			const styles = HEAD + `<styleSheet xmlns="${MAIN}">` + fmtXml
				+ `<fonts count="${fonts.list.length}">${fonts.list.join('')}</fonts>`
				+ `<fills count="${fills.list.length}">${fills.list.join('')}</fills>`
				+ `<borders count="${borders.list.length}">${borders.list.join('')}</borders>`
				+ '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
				+ `<cellXfs count="${xfs.list.length}">${xfs.list.join('')}</cellXfs>`
				+ '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';
			const created = isDate(wb.created) ? wb.created : new Date();
			const iso = created.toISOString().replace(/\.\d+Z$/, 'Z');
			return [
				['[Content_Types].xml', HEAD + '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
					+ '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
					+ '<Default Extension="xml" ContentType="application/xml"/>'
					+ '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
					+ list.map((s, i) => `<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join('')
					+ '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
					+ '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
					+ '</Types>'],
				['_rels/.rels', HEAD + `<Relationships xmlns="${PKG}">`
					+ `<Relationship Id="rId1" Type="${REL}/officeDocument" Target="xl/workbook.xml"/>`
					+ `<Relationship Id="rId2" Type="${PKG}/metadata/core-properties" Target="docProps/core.xml"/>`
					+ '</Relationships>'],
				['docProps/core.xml', HEAD + '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"'
					+ ' xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/"'
					+ ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
					+ `<dc:creator>${esc(wb.creator || '')}</dc:creator>`
					+ `<dcterms:created xsi:type="dcterms:W3CDTF">${iso}</dcterms:created>`
					+ `<dcterms:modified xsi:type="dcterms:W3CDTF">${iso}</dcterms:modified></cp:coreProperties>`],
				['xl/workbook.xml', HEAD + `<workbook xmlns="${MAIN}" xmlns:r="${REL}"><bookViews><workbookView/></bookViews><sheets>`
					+ list.map((s, i) => `<sheet name="${esc(s.name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>`).join('')
					+ '</sheets>' + (defined ? `<definedNames>${defined}</definedNames>` : '')
					+ '<calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>'],
				['xl/_rels/workbook.xml.rels', HEAD + `<Relationships xmlns="${PKG}">`
					+ list.map((s, i) => `<Relationship Id="rId${i + 1}" Type="${REL}/worksheet" Target="worksheets/sheet${i + 1}.xml"/>`).join('')
					+ `<Relationship Id="rId${list.length + 1}" Type="${REL}/styles" Target="styles.xml"/></Relationships>`],
				['xl/styles.xml', styles],
			].concat(list.map((s, i) => [`xl/worksheets/sheet${i + 1}.xml`, s.xml]));
		};

		// ---------- zip (STORE, tanpa kompresi) ----------
		const utf8 = s => {
			const out = [];
			for (let i = 0; i < s.length; i++) {
				let c = s.charCodeAt(i);
				if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
					const d = s.charCodeAt(i + 1);
					if (d >= 0xDC00 && d <= 0xDFFF) { c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00); i++; }
				}
				if (c >= 0xD800 && c <= 0xDFFF) c = 0xFFFD;
				if (c < 0x80) out.push(c);
				else if (c < 0x800) out.push(0xC0 | (c >> 6), 0x80 | (c & 63));
				else if (c < 0x10000) out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
				else out.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
			}
			return out;
		};
		const CRC = [];
		for (let n = 0; n < 256; n++) {
			let c = n;
			for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
			CRC.push(c >>> 0);
		}
		const crc32 = bytes => {
			let c = 0xFFFFFFFF;
			for (let i = 0; i < bytes.length; i++) c = CRC[(c ^ bytes[i]) & 0xFF] ^ (c >>> 8);
			return (c ^ 0xFFFFFFFF) >>> 0;
		};
		const zip = (entries, when) => {
			const out = [];
			const central = [];
			const u16 = (arr, v) => { arr.push(v & 0xFF, (v >>> 8) & 0xFF); };
			const u32 = (arr, v) => { arr.push(v & 0xFF, (v >>> 8) & 0xFF, (v >>> 16) & 0xFF, (v >>> 24) & 0xFF); };
			const copy = (arr, src) => { for (let i = 0; i < src.length; i++) arr.push(src[i]); };
			const time = (when.getHours() << 11) | (when.getMinutes() << 5) | (when.getSeconds() >> 1);
			const date = ((Math.max(when.getFullYear(), 1980) - 1980) << 9) | ((when.getMonth() + 1) << 5) | when.getDate();
			entries.forEach(e => {
				const name = utf8(e[0]);
				const data = utf8(e[1]);
				const crc = crc32(data);
				const offset = out.length;
				u32(out, 0x04034B50); u16(out, 20); u16(out, 0x0800); u16(out, 0); u16(out, time); u16(out, date);
				u32(out, crc); u32(out, data.length); u32(out, data.length); u16(out, name.length); u16(out, 0);
				copy(out, name);
				copy(out, data);
				u32(central, 0x02014B50); u16(central, 20); u16(central, 20); u16(central, 0x0800); u16(central, 0);
				u16(central, time); u16(central, date); u32(central, crc); u32(central, data.length); u32(central, data.length);
				u16(central, name.length); u16(central, 0); u16(central, 0); u16(central, 0); u16(central, 0); u32(central, 0);
				u32(central, offset);
				copy(central, name);
			});
			const cdOffset = out.length;
			copy(out, central);
			u32(out, 0x06054B50); u16(out, 0); u16(out, 0); u16(out, entries.length); u16(out, entries.length);
			u32(out, central.length); u32(out, cdOffset); u16(out, 0);
			return out;
		};
		const base64 = bytes => {
			const t = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
			const out = [];
			for (let i = 0; i < bytes.length; i += 3) {
				const x = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0);
				out.push(t[(x >> 18) & 63] + t[(x >> 12) & 63]
					+ (i + 1 < bytes.length ? t[(x >> 6) & 63] : '=') + (i + 2 < bytes.length ? t[x & 63] : '='));
			}
			return out.join('');
		};

		const wb = {
			creator: '',
			created: new Date(),
			addWorksheet(name, opts) {
				const ws = makeSheet(name, opts || {});
				sheets.push(ws);
				return ws;
			},
			toBase64() {
				return base64(zip(files(wb), isDate(wb.created) ? wb.created : new Date()));
			},
		};
		return wb;
	},
}
