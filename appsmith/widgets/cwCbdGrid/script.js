// cwCbdGrid — grid baris CBD page Cost Breakdown (CBD), dikelompokkan per grup komponen (a/b/c/d) + bagian
// MISSING_IN_SPEC. Hanya tampilan & input: Yield dan Loss % diedit di sel (revisi DRAFT). Setiap perubahan
// dikirim sebagai model.action + event onAction (CbdGridCtrl.onAction()); aturan final di DB (fn_cbd_line_set).
// Usage, harga IDR/USD, cost/pair dihitung di DB (v_cbd_line) — di sini hanya diformat.
const $ = id => document.getElementById(id);
let M = {};
let seq = 0;
let lastMsg = null;
let localMsg = null;

const COLS = [
  ['c-no', 'No'], ['c-comp', 'Komponen'], ['c-mat', 'Material'], ['c-thk', 'Thickness'], ['c-col', 'Color'],
  ['c-sup', 'Supplier'], ['c-uom', 'UoM'], ['c-rem', 'Remarks'], ['c-num', 'Yield'], ['c-num', 'Usage'],
  ['c-num', 'Loss %'], ['c-price', 'Harga'], ['c-cur', 'Cur'], ['c-num', 'USD'], ['c-num', 'IDR'],
  ['c-num', 'Cost/pr (Rp)'], ['c-src', 'Asal'],
];

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
function parseInput(text) {
  const t = String(text ?? '').trim().replace(/\s+/g, '');
  if (!t) return { value: '' };
  if (!/^\d+([.,]\d+)?$/.test(t)) return { error: `"${text}" bukan angka. Pakai koma atau titik untuk desimal, tanpa pemisah ribuan.` };
  return { value: t.replace(',', '.') };
}

// ---------------------------------------------------------------- aksi
function send(type, data) {
  localMsg = null;
  showMessage();
  seq += 1;
  appsmith.updateModel({ action: Object.assign({ type, seq }, data) });
  appsmith.triggerEvent('onAction');
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

function commit(line, field, input) {
  const p = parseInput(input.value);
  if (p.error) {
    input.classList.add('invalid');
    localMsg = { type: 'error', text: p.error };
    showMessage();
    return;
  }
  const n = p.value === '' ? null : Number(p.value);
  if (field === 'yield' && n !== null && n <= 0) {
    input.classList.add('invalid');
    localMsg = { type: 'error', text: 'Yield harus lebih besar dari 0.' };
    showMessage();
    return;
  }
  if (field === 'loss' && n !== null && n >= 100) {
    input.classList.add('invalid');
    localMsg = { type: 'error', text: 'Loss % harus 0 sampai kurang dari 100.' };
    showMessage();
    return;
  }
  send(field === 'yield' ? 'setYield' : 'setLoss', { line_id: line.id, value: p.value });
}

// Input angka yang disimpan saat berubah (Enter / Tab / klik di luar); Enter pindah ke baris berikutnya, Esc batal
function numInput(line, field, value, max) {
  const i = el('input', 'cell');
  i.type = 'text';
  i.inputMode = 'decimal';
  i.autocomplete = 'off';
  i.value = inputText(value, max);
  i.dataset.key = `${field}:${line.id}`;
  i.dataset.col = field;
  i.dataset.orig = i.value;
  i.setAttribute('aria-label', `${field === 'yield' ? 'Yield' : 'Loss %'} ${line.display_no || ''} ${line.display_name || ''}`);
  if (field === 'yield' && num(line.price_original) !== null && num(value) === null) {
    i.classList.add('need');
    i.title = 'Baris berharga tanpa yield — wajib diisi sebelum terbit';
  }
  i.addEventListener('input', () => i.classList.remove('invalid'));
  i.addEventListener('change', () => {
    if (i.value.trim() === i.dataset.orig) return;
    commit(line, field, i);
  });
  i.addEventListener('keydown', e => {
    if (e.key === 'Escape') {
      i.value = i.dataset.orig;
      i.classList.remove('invalid');
      i.blur();
    } else if (e.key === 'Enter') {
      e.preventDefault();
      const all = Array.from(document.querySelectorAll(`#tbody input.cell[data-col="${field}"]`));
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
  const s = el('span', 'ro' + (v ? '' : ' none'), v || '-');
  return s;
}

function priceCell(line) {
  const box = el('div');
  const p = num(line.price_original);
  if (p !== null) {
    box.appendChild(el('span', 'ro', fmt(p, line.currency === 'USD' ? 4 : 2)));
    const src = { MASTER: 'master', OVERRIDE: 'override', QUOTATION: 'quotation' }[line.price_source] || '';
    if (src) {
      const b = el('span', `badge ${src}`, src);
      if (line.price_source === 'MASTER' && line.master_price_valid_from) {
        b.title = `Harga master${line.master_price_color ? ' warna ' + line.master_price_color : ' semua warna'} berlaku ${line.master_price_valid_from}`;
      }
      if (line.price_source === 'OVERRIDE' && line.price_override_reason) b.title = `Alasan: ${line.price_override_reason}`;
      box.appendChild(b);
    }
    return box;
  }
  if (line.status !== 'ACTIVE') {
    box.appendChild(el('span', 'ro none', '-'));
    return box;
  }
  // kenapa harga kosong
  let why = 'belum ada harga master';
  if (line.price_method === 'QUOTATION') why = 'material quotation (harga diisi di CBD — F8)';
  else if (!line.supplier_id) why = 'baris tanpa supplier di specsheet';
  box.appendChild(el('span', 'hint warn', why));
  return box;
}

function originText(line) {
  const t = { INPUT: 'input', COPIED: 'copy', CARRIED_FROM_REPLACED: 'ganti material' }[line.value_origin] || line.value_origin;
  const s = el('span', 'ro', t);
  if (line.value_source_ref) s.title = `Dari ${line.value_source_ref}`;
  return s;
}

function lineRow(line, editable) {
  const missing = line.status !== 'ACTIVE';
  const tr = el('tr', (line.is_sub ? 'sub' : '') + (missing ? ' missing' : ''));
  tr.appendChild(td('c-no', line.display_no || '-'));
  const comp = el('span', 'ro');
  comp.appendChild(el('span', 'name', line.display_name || '-'));
  if (line.is_local) comp.appendChild(el('span', 'local', 'lokal'));
  tr.appendChild(td('c-comp', comp));
  const mat = el('span', 'ro');
  mat.appendChild(document.createTextNode(line.material_name || '-'));
  mat.appendChild(el('span', 'code', line.material_code || ''));
  tr.appendChild(td('c-mat', mat));
  tr.appendChild(td('c-thk', roText(line.thickness)));
  tr.appendChild(td('c-col', roText(line.color)));
  tr.appendChild(td('c-sup', roText(line.supplier_name)));
  tr.appendChild(td('c-uom', roText(line.uom)));
  tr.appendChild(td('c-rem', roText(line.remarks)));
  const canEdit = editable && !missing;
  tr.appendChild(td('c-num', canEdit ? numInput(line, 'yield', line.yield_value, 6) : fmt(line.yield_value, 6)));
  tr.appendChild(td('c-num', fmt(line.usage_value, 4)));
  tr.appendChild(td('c-num', canEdit ? numInput(line, 'loss', line.loss_pct, 2) : fmt(line.loss_pct, 2, 2)));
  tr.appendChild(td('c-price', priceCell(line)));
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

// ---------------------------------------------------------------- render
function render(model) {
  // simpan fokus, scroll, dan ketikan yang belum disimpan
  const active = document.activeElement;
  const focusKey = active && active.dataset ? active.dataset.key : null;
  const dirty = {};
  document.querySelectorAll('#tbody input.cell[data-key]').forEach(i => {
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

  const thead = $('thead');
  thead.innerHTML = '';
  const hr = el('tr');
  COLS.forEach(([c, t]) => {
    const th = el('th', c, t);
    if (t === 'Yield') th.title = 'Jumlah pasang dari satu unit material. Usage = 1 / Yield.';
    if (t === 'USD' || t === 'IDR') th.title = 'Konversi memakai exchange rate revisi ini (diisi di rekap — F8).';
    hr.appendChild(th);
  });
  thead.appendChild(hr);

  const tbody = $('tbody');
  tbody.innerHTML = '';
  if (!lines.length) {
    const tr = el('tr');
    const c = el('td', 'empty', M.emptyText || 'Belum ada baris CBD.');
    c.colSpan = COLS.length;
    tr.appendChild(c);
    tbody.appendChild(tr);
  }
  const active_ = lines.filter(l => l.status === 'ACTIVE');
  const missing = lines.filter(l => l.status !== 'ACTIVE');
  let group = null;
  active_.forEach(l => {
    if (l.group_code !== group) {
      group = l.group_code;
      tbody.appendChild(groupRow(`${String(l.group_code || '').toUpperCase()} · ${l.group_name || ''}`));
    }
    tbody.appendChild(lineRow(l, editable));
  });
  if (missing.length) {
    tbody.appendChild(groupRow(`Hilang dari specsheet (MISSING_IN_SPEC) — ${missing.length} baris, tidak dihitung`, true));
    missing.forEach(l => tbody.appendChild(lineRow(l, false)));
  }

  // pulihkan ketikan, fokus, scroll
  document.querySelectorAll('#tbody input.cell[data-key]').forEach(i => {
    const d = dirty[i.dataset.key];
    // ketikan yang sudah tersimpan (nilai DB sama) tidak dipulihkan
    if (d !== undefined && parseInput(d).value !== parseInput(i.dataset.orig).value) i.value = d;
  });
  if (focusKey) {
    const i = document.querySelector(`#tbody input[data-key="${CSS.escape(focusKey)}"]`);
    if (i) i.focus();
  }
  scroll.scrollLeft = pos[0];
  scroll.scrollTop = pos[1];

  const noPrice = active_.filter(l => num(l.price_original) === null).length;
  const noYield = active_.filter(l => num(l.price_original) !== null && num(l.yield_value) === null).length;
  const parts = [`${active_.length} baris`];
  if (noYield) parts.push(`${noYield} berharga tanpa yield`);
  if (noPrice) parts.push(`${noPrice} tanpa harga`);
  if (num(M.exchangeRate) !== null) parts.push(`rate ${fmt(M.exchangeRate, 4)}`);
  else parts.push('rate belum diisi');
  if (!editable) parts.push('hanya baca');
  $('status').textContent = (M.busy ? 'Menyimpan… · ' : '') + parts.join(' · ');
  showMessage();
}

appsmith.onReady(() => {
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(m => render(m));
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
