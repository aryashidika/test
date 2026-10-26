// cwCbdGrid - grid baris CBD page Cost Breakdown (CBD), dikelompokkan per grup komponen (a/b/c/d, + subtotal) + bagian
// MISSING_IN_SPEC, dengan panel ringkasan menempel di atas grid, banner refresh (F8), dan di bawah grid tabel
// Cost recapitulation (baris biaya) + Harga jual (F8b).
// Hanya tampilan & input: Yield, Loss %, dan nilai rekap diedit di sel (revisi DRAFT); harga lewat tombol
// Isi harga (quotation) / Isi estimasi (R17: baris tanpa Material Code di Pullover / Preview) / Ajukan harga master (R8)
// (modal di luar widget). R11: Tanpa biaya
// (alasan diisi di sel, cost/pair 0 - mis. printing yang harganya sudah termasuk baris lain). Setiap aksi dikirim sebagai model.action + event
// onAction (CbdGridCtrl.onAction()); aturan final di DB. Usage, harga IDR/USD, cost/pair, dan rekap dihitung
// di DB (v_cbd_line, v_cbd_recap) - di sini hanya diformat.
// Antrean aksi (sama dengan cwBomGrid): aksi dikirim SATU PER SATU; berikutnya baru dikirim setelah CbdGridCtrl
//   membalas doneSeq >= seq (ack). Tanpa ack 5 detik -> kirim ulang (seq yang sudah selesai diabaikan). Nilai yang
//   sudah dikirim ditampilkan (optimistic) sampai antrean kosong. Sel disimpan saat change DAN blur.
const $ = id => document.getElementById(id);
let M = {};
let seq = 0;
let queue = [];             // aksi menunggu ack CbdGridCtrl (model.doneSeq); queue[0] = yang sedang dikirim
let retryTimer = null;
let optimistic = {};        // key input -> nilai yang sudah dikirim tapi belum kembali dari DB
let lastMsg = null;
let localMsg = null;
let ncOpen = null;           // R11: id baris yang form "Tanpa biaya"-nya terbuka
let ncText = '';

const COLS = [
  ['c-no', 'No'], ['c-comp', 'Component'], ['c-mat', 'Material'], ['c-thk', 'Dimension'], ['c-col', 'Color'],
  ['c-sup', 'Supplier'], ['c-uom', 'UoM'], ['c-rem', 'Remarks'], ['c-num', 'Yield'], ['c-num', 'Usage'],
  ['c-num', 'Loss %'], ['c-price', 'Price'], ['c-cur', 'Cur'], ['c-num', 'USD'], ['c-num', 'IDR'],
  ['c-num', 'Cost/pr (Rp)'], ['c-src', 'Source'],
];

// Panel atas (menempel): [field (null = hanya baca), label, kunci nilai, digit desimal, boleh minus, uang]
// F8b: biaya lain, Target FOB, Selling price & Margin pindah ke tabel di bawah grid.
const RECAP = [
  ['RATE', 'Exchange rate (Rp / 1 USD)', 'exchange_rate', 4, false, true],
  [null, 'Material cost', 'material_cost', 2],
  [null, 'Actual FOB', 'actual_fob', 2],
  [null, 'Target FOB', 'target_fob', 2],
  [null, 'Difference', 'variance', 2],
  [null, 'PO (Actual FOB × stage factor)', 'po_price', 2],          // R5: kosong bila stage tanpa faktor
];

// Jenis baris biaya (F8b) - urutan tampil
const COST_TYPES = [
  ['LABOUR', 'Direct Labour (LOP)'], ['AMORTIZATION', 'Amortization'], ['ADJUSTMENT', 'Adjustment'], ['OTHER', 'Other'],
];
const COST_NAME = { LABOUR: 'Direct Labour', AMORTIZATION: 'Amortization', ADJUSTMENT: 'Adjustment', OTHER: 'Other' };
let addForm = { type: '', name: '', amount: '', remarks: '' };
let lastCostOk = null;

function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined && text !== null) e.textContent = text;
  return e;
}

// ---------------------------------------------------------------- angka
function num(v) {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

// Format Indonesia (titik ribuan, koma desimal); max = digit desimal maksimal, min = minimal
function fmt(v, max, min) {
  const n = num(v);
  if (n === null) return '-';
  return n.toLocaleString('id-ID', { minimumFractionDigits: min || 0, maximumFractionDigits: max });
}

// Nilai sel -> teks input (tanpa pemisah ribuan, koma desimal)
function inputText(v, max) {
  const n = num(v);
  if (n === null) return '';
  return String(Number(n.toFixed(max))).replace('.', ',');
}

// Teks ketikan -> angka kanonik '1.25' ('' = kosong). Satu pemisah desimal (koma atau titik); tanpa pemisah ribuan.
// money: '47.500' ditolak karena ambigu (47500 atau 47,5). neg: boleh diawali '-'.
function parseInput(text, opt) {
  opt = opt || {};
  const t = String(text ?? '').trim().replace(/\s+/g, '');
  if (!t) return { value: '' };
  if (!opt.neg && t.startsWith('-')) return { error: 'The value cannot be negative.' };
  const re = opt.neg ? /^-?\d+([.,]\d+)?$/ : /^\d+([.,]\d+)?$/;
  if (!re.test(t)) return { error: `"${text}" is not a number. Use a comma or dot for decimals, no thousand separators.` };
  if (opt.money && /^-?\d{1,3}\.\d{3}$/.test(t)) {
    return { error: `"${text}" is ambiguous. Write it without thousand separators (e.g. 16250), with a comma for decimals (e.g. 16250,5).` };
  }
  return { value: t.replace(',', '.') };
}

// ---------------------------------------------------------------- aksi
function send(type, data) {
  localMsg = null;
  showMessage();
  seq = Math.max(Date.now(), seq + 1);         // naik terus, juga setelah widget dimuat ulang
  queue.push(Object.assign({ type, seq }, data));
  if (queue.length === 1) setTimeout(flush, 0);  // setelah pemanggil mencatat nilai optimistic
}

function flush() {
  clearTimeout(retryTimer);
  if (!queue.length) return;
  appsmith.updateModel({ action: queue[0] });
  appsmith.triggerEvent('onAction');
  retryTimer = setTimeout(flush, 5000);        // event hilang (model di-reset) -> kirim ulang
}

// Balasan CbdGridCtrl: model.doneSeq = seq aksi terakhir yang selesai (berhasil atau gagal) dan datanya sudah dimuat ulang
function onAck(m) {
  const done = Number((m || {}).doneSeq) || 0;
  const before = queue.length;
  while (queue.length && queue[0].seq <= done) queue.shift();
  if (queue.length === before) return;
  if (queue.length) {
    flush();
  } else {
    clearTimeout(retryTimer);
    optimistic = {};
  }
}

// Simpan sel (change + blur): nilai yang dipulihkan setelah render ulang tidak memicu change, jadi blur ikut menyimpan
function committer(i, key, run) {
  const go = () => {
    if (!i.isConnected) return;                // elemen sudah diganti render ulang
    const before = seq;
    run();
    if (seq !== before) {
      i.dataset.orig = i.value.trim();
      optimistic[key] = i.dataset.orig;
    }
  };
  i.addEventListener('change', go);
  i.addEventListener('blur', go);
}

function showMessage() {
  const m = localMsg || M.message;
  const box = $('msg');
  if (!m || !m.text) {
    box.hidden = true;
    box.textContent = '';
    return;
  }
  box.className = `msg ${m.type || 'info'}`;
  box.textContent = m.text;
  box.hidden = false;
}

function invalid(input, text) {
  input.classList.add('invalid');
  localMsg = { type: 'error', text };
  showMessage();
}

// Input angka yang disimpan saat berubah (Enter / Tab / klik di luar); Esc batal.
// o: { key, col, value, max, label, parse, check(n) -> pesan error | null, commit(value), need, needTitle }
function numInput(o) {
  const i = el('input', 'cell');
  i.type = 'text';
  i.inputMode = 'decimal';
  i.autocomplete = 'off';
  i.value = inputText(o.value, o.max);
  i.dataset.key = o.key;
  i.dataset.col = o.col;
  i.dataset.orig = i.value;
  i.setAttribute('aria-label', o.label);
  if (o.need) {
    i.classList.add('need');
    i.title = o.needTitle || '';
  }
  i.addEventListener('input', () => i.classList.remove('invalid'));
  committer(i, o.key, () => {
    if (i.value.trim() === i.dataset.orig) return;
    const p = parseInput(i.value, o.parse);
    if (p.error) return invalid(i, p.error);
    const err = o.check ? o.check(p.value === '' ? null : Number(p.value)) : null;
    if (err) return invalid(i, err);
    o.commit(p.value);
  });
  i.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
      i.value = i.dataset.orig;
      i.classList.remove('invalid');
      i.blur();
    } else if (e.key === 'Enter') {
      e.preventDefault();
      const all = Array.from(document.querySelectorAll(`input.cell[data-col="${o.col}"]`));
      const next = all[all.indexOf(i) + 1];
      if (next) {
        next.focus();
        next.select();
      } else {
        i.blur();
      }
    }
  });
  return i;
}

// Input teks yang disimpan saat berubah (Enter / Tab / klik di luar); Esc batal.
// o: { key, value, label, placeholder, required, commit(value) }
function textInput(o) {
  const i = el('input', 'cell txt');
  i.type = 'text';
  i.autocomplete = 'off';
  i.maxLength = 200;
  i.value = o.value || '';
  i.placeholder = o.placeholder || '';
  i.dataset.key = o.key;
  i.dataset.kind = 'text';
  i.dataset.orig = i.value;
  i.setAttribute('aria-label', o.label);
  i.addEventListener('input', () => i.classList.remove('invalid'));
  committer(i, o.key, () => {
    const v = i.value.trim();
    if (v === i.dataset.orig.trim()) return;
    if (o.required && !v) return invalid(i, `${o.label} is required.`);
    o.commit(v);
  });
  i.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
      i.value = i.dataset.orig;
      i.classList.remove('invalid');
      i.blur();
    } else if (e.key === 'Enter') {
      e.preventDefault();
      i.blur();
    }
  });
  return i;
}

function lineInput(line, field, value, max) {
  const yieldCol = field === 'yield';
  return numInput({
    key: `${field}:${line.id}`, col: field, value, max,
    label: `${yieldCol ? 'Yield' : 'Loss %'} ${line.display_no || ''} ${line.display_name || ''}`,
    need: yieldCol && num(line.price_original) !== null && num(value) === null && !line.no_charge,
    needTitle: 'Priced line without yield. Required before publishing',
    check: n => yieldCol ? (n !== null && n <= 0 ? 'Yield must be above 0.' : null)
      : (n !== null && n >= 100 ? 'Loss % must be from 0 to below 100.' : null),
    commit: v => send(yieldCol ? 'setYield' : 'setLoss', { line_id: line.id, value: v }),
  });
}

function linkBtn(text, title, onClick, danger) {
  const b = el('button', 'lnk' + (danger ? ' danger' : ''), text);
  b.type = 'button';
  if (title) b.title = title;
  b.disabled = !!M.busy;
  b.addEventListener('click', onClick);
  return b;
}

// ---------------------------------------------------------------- sel
function td(cls, child) {
  const c = el('td', cls);
  if (child !== undefined && child !== null) {
    if (typeof child === 'string') c.appendChild(el('span', 'ro', child));
    else c.appendChild(child);
  }
  return c;
}

function roText(v) {
  return el('span', 'ro' + (v ? '' : ' none'), v || '-');
}

// Kenapa harga kosong (price_gap dari v_cbd_price_check, hanya revisi DRAFT)
function gapText(line) {
  switch (line.price_gap) {
    case 'QUOTATION': return ['quotation material, not filled in (cost 0)', ''];
    case 'NO_SUPPLIER': return ['no supplier selected in the specsheet', ''];
    case 'NO_CODE': return ['no Material Code yet. Enter an estimate', 'warn'];
    case 'AVAILABLE': return ['master price available. Click Refresh Prices', 'warn'];
    case 'PENDING': return ['master price waiting for Manager Costing approval', 'warn'];
    case 'NO_PRICE': return ['no master price for this Material Code + supplier', 'warn'];
    default: return [line.price_method === 'QUOTATION' ? 'not priced separately' : 'no price', ''];
  }
}

function priceCell(line, editable) {
  const box = el('div');
  const p = num(line.price_original);
  const missing = line.status !== 'ACTIVE';
  if (line.no_charge) {                        // R11: biaya 0, harga (bila ada) tetap terlihat
    if (p !== null) box.appendChild(el('span', 'ro none', fmt(p, line.currency === 'USD' ? 4 : 2)));
    const b = el('span', 'badge nocharge', 'no charge');
    b.title = `Reason: ${line.no_charge_reason || '-'}`;
    box.appendChild(b);
    box.appendChild(el('span', 'hint', line.no_charge_reason || ''));
  } else if (p !== null) {
    box.appendChild(el('span', 'ro', fmt(p, line.currency === 'USD' ? 4 : 2)));
    const src = { MASTER: 'master', OVERRIDE: 'override', QUOTATION: 'quotation', ESTIMATE: 'estimate' }[line.price_source] || '';
    if (src) {
      const b = el('span', `badge ${src}`, src);
      if (line.price_source === 'MASTER' && line.master_price_valid_from) {
        b.title = `Master price for${line.master_price_color ? ' color ' + line.master_price_color : ' all colors'}, active since ${line.master_price_valid_from}`;
      }
      if (line.price_source === 'OVERRIDE' && line.price_override_reason) b.title = `Reason: ${line.price_override_reason}`;
      if (line.price_source === 'QUOTATION' && line.price_reference) b.title = `Reference: ${line.price_reference}`;
      if (line.price_source === 'ESTIMATE') b.title = `Estimate (no Material Code yet)${line.price_reference ? '. Reference: ' + line.price_reference : ''}`;
      box.appendChild(b);
    }
  } else if (missing) {
    box.appendChild(el('span', 'ro none', '-'));
  } else {
    const [t, tone] = gapText(line);
    box.appendChild(el('span', 'hint' + (tone ? ' ' + tone : ''), t));
  }
  if (!missing && !line.no_charge && line.master_stale) {
    box.appendChild(el('span', 'hint warn', line.price_source === 'QUOTATION'
      ? 'material is now catalog. Click Refresh Prices' : 'master price changed. Click Refresh Prices'));
  }
  const acts = el('div', 'acts');
  if (editable && !missing) {
    if (line.price_method === 'QUOTATION') {
      acts.appendChild(linkBtn(p !== null ? 'Edit price' : 'Enter price', 'Quotation price of the process material',
        () => send('editPrice', { line_id: line.id, mode: 'QUOTATION' })));
    }
    // R17: baris Catalog tanpa Material Code di Pullover / Preview (can_estimate dari v_cbd_price_check)
    if (line.can_estimate && !line.no_charge) {
      acts.appendChild(linkBtn(p !== null ? 'Edit estimate' : 'Enter estimate',
        'No Material Code yet: estimate price for Pullover / Preview. From SMS the master price is required',
        () => send('editPrice', { line_id: line.id, mode: 'ESTIMATE' })));
    }
    if (line.no_charge) {
      acts.appendChild(linkBtn('Undo no charge', 'This line is counted again with its price',
        () => send('setNoCharge', { line_id: line.id, on: false, reason: '' }), true));
    } else if (ncOpen !== line.id) {
      acts.appendChild(linkBtn('No charge', 'This line costs 0. Its price is included in another line / not charged',
        () => openNoCharge(line.id)));
    }
  }
  // R8: ajukan harga MASTER untuk Material Code + supplier baris ini (alur approval biasa; Manager Costing langsung berlaku)
  if (M.canProposePrice && !missing && !line.no_charge && line.price_method === 'CATALOG' && line.variant_id && line.supplier_id && !line.pending) {
    acts.appendChild(linkBtn(M.directPrice ? 'New master price' : 'Propose master price',
      `Master price ${line.material_code || ''} · ${line.supplier_name || ''}. Applies to all CBDs`,
      () => send('proposePrice', { line_id: line.id })));
  }
  if (acts.childNodes.length) box.appendChild(acts);
  if (editable && !missing && !line.no_charge && ncOpen === line.id) box.appendChild(noChargeForm(line));
  return box;
}

// R11: form alasan "Tanpa biaya" di dalam sel Harga (isian disimpan di ncText supaya tidak hilang saat render ulang)
function openNoCharge(id) {
  ncOpen = id;
  ncText = '';
  render(M);
  setTimeout(() => {
    const i = document.querySelector(`input.cell[data-key="nc:${id}"]`);
    if (i) i.focus();
  }, 0);
}

function closeNoCharge() {
  ncOpen = null;
  ncText = '';
  render(M);
}

function noChargeForm(line) {
  const f = el('div', 'ncform');
  const i = el('input', 'cell txt');
  i.type = 'text';
  i.maxLength = 200;
  i.autocomplete = 'off';
  i.placeholder = 'Reason, e.g. included in line 10 price';
  i.value = ncText;
  i.dataset.key = `nc:${line.id}`;
  i.dataset.kind = 'text';
  i.dataset.orig = '';
  i.setAttribute('aria-label', `No-charge reason ${line.display_no || ''} ${line.display_name || ''}`);
  const save = () => {
    const v = i.value.trim().replace(/\s+/g, ' ');
    if (!v) return invalid(i, 'Enter the no-charge reason (e.g. "price included in line 10").');
    ncOpen = null;
    ncText = '';
    send('setNoCharge', { line_id: line.id, on: true, reason: v });
    render(M);                                   // tutup form sekarang; grid dimuat ulang setelah DB menyimpan
  };
  i.addEventListener('input', () => { ncText = i.value; i.classList.remove('invalid'); });
  i.addEventListener('keydown', e => {
    if (e.key === 'Enter') { e.preventDefault(); save(); }
    else if (e.key === 'Escape') closeNoCharge();
  });
  const ok = el('button', 'bbtn sm', 'Save');
  ok.type = 'button';
  ok.disabled = !!M.busy;
  ok.addEventListener('click', save);
  const no = linkBtn('Cancel', 'Close without saving', closeNoCharge);
  no.disabled = false;
  f.appendChild(i);
  const b = el('div', 'ncbtns');
  b.appendChild(no);
  b.appendChild(ok);
  f.appendChild(b);
  return f;
}

function originText(line) {
  const t = { INPUT: 'input', COPIED: 'copy', CARRIED_FROM_REPLACED: 'replaced material' }[line.value_origin] || line.value_origin;
  const s = el('span', 'ro', t);
  if (line.value_source_ref) s.title = `From ${line.value_source_ref}`;
  return s;
}

function lineRow(line, editable) {
  const missing = line.status !== 'ACTIVE';
  const tr = el('tr', (line.is_sub ? 'sub' : '') + (missing ? ' missing' : ''));
  tr.appendChild(td('c-no', line.display_no || '-'));
  const comp = el('span', 'ro');
  comp.appendChild(el('span', 'name', line.display_name || '-'));
  if (line.is_local) comp.appendChild(el('span', 'local', 'local'));
  tr.appendChild(td('c-comp', comp));
  const mat = el('span', 'ro');
  mat.appendChild(document.createTextNode(line.material_name || '-'));
  if (line.material_code || line.price_method !== 'CATALOG') mat.appendChild(el('span', 'code', line.material_code || ''));
  else mat.appendChild(el('span', 'code nocode', 'no Material Code'));     // R17: hanya mungkin di Pullover / Preview
  tr.appendChild(td('c-mat', mat));
  tr.appendChild(td('c-thk', roText(line.thickness)));
  tr.appendChild(td('c-col', roText(line.color)));
  tr.appendChild(td('c-sup', roText(line.supplier_name)));
  tr.appendChild(td('c-uom', roText(line.uom)));
  tr.appendChild(td('c-rem', roText(line.remarks)));
  const canEdit = editable && !missing;
  tr.appendChild(td('c-num', canEdit ? lineInput(line, 'yield', line.yield_value, 6) : fmt(line.yield_value, 6)));
  tr.appendChild(td('c-num', fmt(line.usage_value, 4)));
  tr.appendChild(td('c-num', canEdit ? lineInput(line, 'loss', line.loss_pct, 2) : fmt(line.loss_pct, 2, 2)));
  tr.appendChild(td('c-price', priceCell(line, editable)));
  tr.appendChild(td('c-cur', roText(line.currency)));
  tr.appendChild(td('c-num', fmt(line.price_usd, 4, 2)));
  tr.appendChild(td('c-num', fmt(line.price_idr, 2)));
  tr.appendChild(td('c-num', fmt(line.cost_per_pair, 2, 2)));
  tr.appendChild(td('c-src', originText(line)));
  return tr;
}

function groupRow(label, missing) {
  const tr = el('tr', 'group' + (missing ? ' missing' : ''));
  const c = el('td');
  c.colSpan = COLS.length;
  c.appendChild(el('span', 'glabel', label));
  tr.appendChild(c);
  return tr;
}

// Subtotal cost/pair per grup (dihitung DB: v_cbd_recap.group_costs)
function subtotalRow(code, name) {
  const tr = el('tr', 'subtotal');
  const c = el('td');
  c.colSpan = COLS.length - 2;
  c.appendChild(el('span', 'glabel', `Subtotal ${String(code || '').toUpperCase()} · ${name || ''}`));
  tr.appendChild(c);
  const costs = (M.recap && M.recap.group_costs) || {};
  tr.appendChild(td('c-num', fmt(costs[code] ?? 0, 2, 2)));
  tr.appendChild(td('c-src', ''));
  return tr;
}

// ---------------------------------------------------------------- banner & rekap
function renderBanners() {
  const box = $('banners');
  box.innerHTML = '';
  (M.banners || []).forEach(b => {
    const d = el('div', `banner ${b.tone || 'info'}`);
    d.appendChild(el('span', 'btext', b.text));
    if (b.action && b.actionLabel) {
      const btn = el('button', 'bbtn', b.actionLabel);
      btn.type = 'button';
      btn.disabled = !!M.busy;
      btn.addEventListener('click', () => send(b.action, {}));
      d.appendChild(btn);
    }
    box.appendChild(d);
  });
  box.hidden = !(M.banners || []).length;
}

// Input nilai rekap (cbd_revision) -> aksi setHeader
function headerInput(field, label, value, max, neg, money) {
  return numInput({
    key: `hdr:${field}`, col: `hdr:${field}`, value, max, label,
    parse: { neg, money },
    need: field === 'RATE' && num(value) === null,
    needTitle: 'Exchange rate is required before publishing',
    check: n => field === 'RATE' ? (n !== null && n <= 0 ? 'Exchange rate must be above 0 (leave empty if not known yet).' : null)
      : field === 'MARGIN' ? (n !== null && n >= 100 ? 'Margin must be below 100%.' : null)
      : (n !== null && n <= 0) ? 'Must be above 0 (leave empty if not known yet).'
      : null,
    commit: v => send('setHeader', { field, value: v }),
  });
}

function varianceView(r) {
  const v = el('span', 'rvv', fmt(r.variance, 2));
  if (r.variance_label) v.appendChild(el('span', `vl ${r.variance_label.toLowerCase()}`, r.variance_label));
  return v;
}

// Panel atas (menempel): Exchange rate + ringkasan hanya baca
function renderRecap() {
  const box = $('recap');
  box.innerHTML = '';
  const r = M.recap;
  box.hidden = !r;
  if (!r) return;
  RECAP.forEach(([field, label, k, max, neg, money]) => {
    const f = el('div', 'rf' + (k === 'actual_fob' ? ' strong' : ''));
    f.appendChild(el('label', null, label));
    if (field && M.editable) {
      f.appendChild(headerInput(field, label, r[k], max, neg, money));
    } else {
      const v = el('div', 'rv');
      if (k === 'variance') v.appendChild(varianceView(r));
      else v.textContent = fmt(r[k], max);
      f.appendChild(v);
    }
    box.appendChild(f);
  });
}

// ---------------------------------------------------------------- tabel bawah (F8b)
function cell(tag, cls, child) {
  const c = el(tag, cls);
  if (child === undefined || child === null) return c;
  if (typeof child === 'string') c.textContent = child;
  else c.appendChild(child);
  return c;
}

function labelRow(label, valueNode, note) {
  const tr = el('tr');
  tr.appendChild(cell('td', '', ''));
  const l = cell('td', 'lbl', label);
  l.colSpan = 2;
  tr.appendChild(l);
  tr.appendChild(cell('td', 'n', valueNode));
  tr.appendChild(cell('td', 'muted', note || ''));
  tr.appendChild(cell('td', '', ''));
  return tr;
}

// Cost recapitulation: a. Material cost (otomatis) + baris biaya + Actual FOB, Target FOB, Selisih
function costTable(r, editable) {
  const wrap = el('section', 'sect');
  wrap.appendChild(el('h3', null, 'Cost recapitulation'));
  const t = el('table', 'mini cost');
  const hr = el('tr');
  ['No', 'Type', 'Description', 'Value (Rp)', 'Remarks', ''].forEach((h, i) => hr.appendChild(cell('th', i === 3 ? 'n' : '', h)));
  t.appendChild(cell('thead', null, hr));
  const tb = el('tbody');
  const letter = i => String.fromCharCode(97 + i) + '.';
  const mat = el('tr', 'auto');
  [letter(0), 'Material', 'Material cost', fmt(r.material_cost, 2, 2), 'automatic from the grid', ''].forEach((v, i) => {
    mat.appendChild(cell('td', i === 3 ? 'n' : (i === 4 ? 'muted' : ''), v));
  });
  tb.appendChild(mat);
  const typeLabel = Object.fromEntries(COST_TYPES);
  (M.costItems || []).forEach((it, idx) => {
    const tr = el('tr');
    tr.appendChild(cell('td', '', letter(idx + 1)));
    tr.appendChild(cell('td', '', typeLabel[it.item_type] || it.item_type));
    tr.appendChild(cell('td', '', editable
      ? textInput({ key: `cost:${it.id}:NAME`, value: it.name, label: 'Description', required: true,
          commit: v => send('setCost', { item_id: it.id, field: 'NAME', value: v }) })
      : it.name));
    tr.appendChild(cell('td', 'n', editable
      ? numInput({ key: `cost:${it.id}:AMOUNT`, col: 'cost-amount', value: it.amount, max: 2, label: `Value ${it.name}`,
          parse: { neg: it.item_type === 'ADJUSTMENT', money: true },
          commit: v => send('setCost', { item_id: it.id, field: 'AMOUNT', value: v }) })
      : fmt(it.amount, 2, 2)));
    tr.appendChild(cell('td', '', editable
      ? textInput({ key: `cost:${it.id}:REMARKS`, value: it.remarks, label: 'Remarks', placeholder: 'e.g. LOP 2026',
          commit: v => send('setCost', { item_id: it.id, field: 'REMARKS', value: v }) })
      : (it.remarks || '')));
    const act = el('td', 'act');
    if (editable && !it.is_default) act.appendChild(linkBtn('Delete', 'Delete this cost line', () => send('deleteCost', { item_id: it.id }), true));
    if (it.is_default) act.title = 'Default line. Always present (enter 0 if not used)';
    tr.appendChild(act);
    tb.appendChild(tr);
  });
  if (editable) tb.appendChild(addCostRow());
  const fob = labelRow('ACTUAL FOB', fmt(r.actual_fob, 2, 2), 'material cost + all cost lines');
  fob.className = 'total';
  tb.appendChild(fob);
  if (num(r.po_factor) !== null) {                     // R5: PO SMS = Actual FOB x faktor stage
    const po = labelRow(`PO ${r.stage || ''} (× ${fmt(r.po_factor, 4, 2)})`, fmt(r.po_price, 2, 2),
      r.status === 'PUBLISHED' ? 'factor frozen at publish' : 'current stage factor');
    po.className = 'total';
    tb.appendChild(po);
  }
  tb.appendChild(labelRow('Target FOB', editable ? headerInput('TARGET_FOB', 'Target FOB', r.target_fob, 2, false, true) : fmt(r.target_fob, 2, 2)));
  tb.appendChild(labelRow('Difference (Actual − Target)', varianceView(r)));
  t.appendChild(tb);
  wrap.appendChild(t);
  return wrap;
}

// Baris "+ Tambah" biaya (isian disimpan di addForm supaya tidak hilang saat render ulang)
function addCostRow() {
  const tr = el('tr', 'add');
  tr.appendChild(cell('td', '', '+'));
  const sel = el('select', 'cell sel');
  sel.setAttribute('aria-label', 'New cost type');
  const o0 = el('option', null, 'Type');
  o0.value = '';
  sel.appendChild(o0);
  COST_TYPES.forEach(([v, l]) => {
    const o = el('option', null, l);
    o.value = v;
    sel.appendChild(o);
  });
  sel.value = addForm.type;
  const mk = (cls, ph, val, label) => {
    const i = el('input', cls);
    i.type = 'text';
    i.maxLength = 200;
    i.placeholder = ph;
    i.value = val;
    i.setAttribute('aria-label', label);
    return i;
  };
  const name = mk('cell txt', addForm.type ? COST_NAME[addForm.type] : 'Description', addForm.name, 'New cost description');
  const amt = mk('cell', '0', addForm.amount, 'New cost value');
  amt.inputMode = 'decimal';
  const rem = mk('cell txt', 'Remarks (optional)', addForm.remarks, 'New cost remarks');
  sel.addEventListener('change', () => {
    addForm.type = sel.value;
    sel.classList.remove('invalid');
    name.placeholder = sel.value ? COST_NAME[sel.value] : 'Description';
  });
  name.addEventListener('input', () => { addForm.name = name.value; });
  amt.addEventListener('input', () => { addForm.amount = amt.value; amt.classList.remove('invalid'); });
  rem.addEventListener('input', () => { addForm.remarks = rem.value; });
  tr.appendChild(cell('td', '', sel));
  tr.appendChild(cell('td', '', name));
  tr.appendChild(cell('td', 'n', amt));
  tr.appendChild(cell('td', '', rem));
  const act = el('td', 'act');
  const b = el('button', 'bbtn', 'Add');
  b.type = 'button';
  b.disabled = !!M.busy;
  b.addEventListener('click', () => {
    if (!addForm.type) return invalid(sel, 'Select a cost type.');
    const p = parseInput(addForm.amount, { neg: addForm.type === 'ADJUSTMENT', money: true });
    if (p.error) return invalid(amt, p.error);
    send('addCost', {
      item_type: addForm.type, name: addForm.name.trim() || COST_NAME[addForm.type],
      amount: p.value, remarks: addForm.remarks.trim(),
    });
  });
  act.appendChild(b);
  tr.appendChild(act);
  return tr;
}

// R5: simulasi harga jual Brand (simulate_margin) - Selling price ⇄ Margin % dari Actual FOB.
// Dihitung di layar saja, TIDAK disimpan (tanpa tombol simpan, tidak ikut export).
let sim = { key: null, price: '', margin: '' };

function simRead(text, neg) {
  const p = parseInput(text, { neg, money: true });
  return p.error || p.value === '' ? null : Number(p.value);
}

function sellTable(r) {
  const wrap = el('section', 'sect');
  wrap.appendChild(el('h3', null, 'Selling price simulation'));
  const fob = num(r.actual_fob);
  if (sim.key !== r.cbd_revision_id) sim = { key: r.cbd_revision_id, price: '', margin: '' };
  const t = el('table', 'mini sell');
  const tb = el('tbody');
  const mk = (label, value, aria) => {
    const i = el('input', 'cell');
    i.type = 'text';
    i.inputMode = 'decimal';
    i.value = value;
    i.setAttribute('aria-label', aria);
    const tr = el('tr');
    tr.appendChild(cell('td', 'lbl', label));
    tr.appendChild(cell('td', 'n', i));
    tb.appendChild(tr);
    return i;
  };
  const price = mk('Selling price (Rp)', sim.price, 'Selling price simulation');
  const margin = mk('Margin %', sim.margin, 'Margin simulation');
  price.addEventListener('input', () => {
    sim.price = price.value;
    const v = simRead(price.value, false);
    sim.margin = v && fob !== null && v > 0 ? ((v - fob) / v * 100).toFixed(2).replace('.', ',') : '';
    margin.value = sim.margin;
  });
  margin.addEventListener('input', () => {
    sim.margin = margin.value;
    const m = simRead(margin.value, true);
    // tanpa pemisah ribuan: "255.784" akan ditolak sebagai angka ambigu saat Selling price diubah lagi
    sim.price = m !== null && m < 100 && fob !== null ? String(Math.round(fob / (1 - m / 100))) : '';
    price.value = sim.price;
  });
  t.appendChild(tb);
  wrap.appendChild(t);
  wrap.appendChild(el('p', 'muted', `From Actual FOB ${fmt(r.actual_fob, 2, 2)}. Simulation only. Not saved and not exported.`));
  return wrap;
}

function renderBelow() {
  const box = $('below');
  box.innerHTML = '';
  const r = M.recap;
  box.hidden = !r;
  if (!r) return;
  if (M.costOkKey !== lastCostOk) {          // tambah biaya berhasil -> kosongkan form
    if (lastCostOk !== null) addForm = { type: '', name: '', amount: '', remarks: '' };
    lastCostOk = M.costOkKey;
  }
  box.appendChild(costTable(r, !!M.editable));
  if (M.canSimulate) box.appendChild(sellTable(r));
}

// ---------------------------------------------------------------- render
function render(model) {
  // simpan fokus, scroll, dan ketikan yang belum disimpan
  const active = document.activeElement;
  const focusKey = active && active.dataset ? active.dataset.key : null;
  const dirty = {};
  document.querySelectorAll('input.cell[data-key]').forEach(i => {
    if (i.value !== i.dataset.orig) dirty[i.dataset.key] = i.value;
  });
  const scroll = $('scroll');
  const pos = [scroll.scrollLeft, scroll.scrollTop];

  M = model || {};
  if (M.message !== lastMsg) {
    lastMsg = M.message;
    localMsg = null;
  }
  const editable = !!M.editable;
  const lines = M.lines || [];

  renderBanners();
  renderRecap();
  renderBelow();

  const thead = $('thead');
  thead.innerHTML = '';
  const hr = el('tr');
  COLS.forEach(([c, t]) => {
    const th = el('th', c, t);
    if (t === 'Yield') th.title = 'Pairs from one material unit. Usage = 1 / Yield.';
    if (t === 'USD' || t === 'IDR') th.title = 'Converted with this revision\'s exchange rate (in the recap).';
    hr.appendChild(th);
  });
  thead.appendChild(hr);

  const tbody = $('tbody');
  tbody.innerHTML = '';
  if (!lines.length) {
    const tr = el('tr');
    const c = el('td', 'empty', M.emptyText || 'No CBD lines yet.');
    c.colSpan = COLS.length;
    tr.appendChild(c);
    tbody.appendChild(tr);
  }
  const active_ = lines.filter(l => l.status === 'ACTIVE');
  const missing = lines.filter(l => l.status !== 'ACTIVE');
  let group = null;
  let groupName = '';
  active_.forEach(l => {
    if (l.group_code !== group) {
      if (group !== null) tbody.appendChild(subtotalRow(group, groupName));
      group = l.group_code;
      groupName = l.group_name;
      tbody.appendChild(groupRow(`${String(l.group_code || '').toUpperCase()} · ${l.group_name || ''}`));
    }
    tbody.appendChild(lineRow(l, editable));
  });
  if (group !== null) tbody.appendChild(subtotalRow(group, groupName));
  if (missing.length) {
    tbody.appendChild(groupRow(`Missing from specsheet (MISSING_IN_SPEC): ${missing.length} lines, not counted`, true));
    missing.forEach(l => tbody.appendChild(lineRow(l, false)));
  }

  // pulihkan ketikan, fokus, scroll
  document.querySelectorAll('input.cell[data-key]').forEach(i => {
    const o = optimistic[i.dataset.key];
    if (o !== undefined) {
      i.value = o;
      i.dataset.orig = o;
    }
    const d = dirty[i.dataset.key];
    if (d === undefined) return;
    // ketikan yang sudah tersimpan (nilai DB sama) tidak dipulihkan
    if (i.dataset.kind === 'text') {
      if (d.trim() !== i.dataset.orig.trim()) i.value = d;
    } else if (parseInput(d, { neg: true }).value !== parseInput(i.dataset.orig, { neg: true }).value) {
      i.value = d;
    }
  });
  if (focusKey) {
    const i = document.querySelector(`input.cell[data-key="${CSS.escape(focusKey)}"]`);
    if (i) i.focus();
  }
  scroll.scrollLeft = pos[0];
  scroll.scrollTop = pos[1];

  const noPrice = active_.filter(l => num(l.price_original) === null && num(l.yield_value) !== null && !l.no_charge).length;
  const noYield = active_.filter(l => num(l.price_original) !== null && num(l.yield_value) === null && !l.no_charge).length;
  const noCharge = active_.filter(l => l.no_charge).length;
  const parts = [`${active_.length} line(s)`];
  if (noYield) parts.push(`${noYield} priced without yield`);
  if (noPrice) parts.push(`${noPrice} without price`);
  if (noCharge) parts.push(`${noCharge} no charge`);
  if (!editable) parts.push('read only');
  $('status').textContent = (M.busy || queue.length ? 'Saving… · ' : '') + parts.join(' · ');
  showMessage();
}

appsmith.onReady(() => {
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(m => {
    onAck(m);
    render(m);
  });
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
