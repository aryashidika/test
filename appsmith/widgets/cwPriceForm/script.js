// cwPriceForm - form harga di mdlHarga (page Material Detail, R3). Hanya tampilan; simpan lewat
// MaterialDetailCtrl.savePrice() -> fn_price_propose / fn_price_copy (aturan final di DB).
// mode 'propose': satu supplier + centang banyak varian + satu harga -> satu pengajuan (PROPOSED).
// mode 'copy'   : harga BERLAKU varian sumber (semua supplier di daftar) disalin ke varian yang dicentang (PROPOSED).
// R8: model.direct (Manager Costing) -> harga langsung berlaku (DB: trg_price_self_approve), teks & tombol menyesuaikan.
// Currency tidak punya nilai awal (wajib dipilih). Varian yang masih punya usulan menunggu untuk supplier
// terpilih tidak bisa dicentang (mode propose); di mode copy pasangan itu dilewati DB dan dilaporkan.
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let mode = 'propose';
let direct = false;
let currency = '';
let variants = [];
let prices = [];
let links = [];
let checked = new Set();

function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}

function showMessage(m) {
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

// "45000" / "3,25" / "3.25" -> "3.25"; null kalau tidak valid
function parsePrice(s) {
  const t = String(s || '').replace(/\s+/g, '').replace(',', '.');
  return /^\d+(\.\d{1,4})?$/.test(t) ? t : null;
}

// "47.500" bisa berarti 47500 (titik ribuan) atau 47,5 - ditolak supaya tidak salah input
function isAmbiguous(s) {
  return /^\d{1,3}(\.\d{3})+$/.test(String(s || '').replace(/\s+/g, ''));
}

function fmt(n) {
  return Number(n).toLocaleString('id-ID', { minimumFractionDigits: 0, maximumFractionDigits: 4 });
}

function fmtDate(iso) {
  const [y, m, d] = String(iso || '').slice(0, 10).split('-');
  return d ? `${d}-${m}-${y}` : '-';
}

function fillSelect(sel, options, selected, placeholder) {
  sel.innerHTML = '';
  if (placeholder) {
    const ph = document.createElement('option');
    ph.value = '';
    ph.textContent = placeholder;
    sel.appendChild(ph);
  }
  (options || []).forEach(o => {
    const opt = document.createElement('option');
    opt.value = o.value;
    opt.textContent = o.label;
    sel.appendChild(opt);
  });
  sel.value = selected || '';
}

function setCurrency(v) {
  currency = v === 'IDR' || v === 'USD' ? v : '';
  document.querySelectorAll('#currency button').forEach(b => b.classList.toggle('on', b.dataset.v === currency));
  if (currency) $('currency').classList.remove('invalid');
}

function variantLabel(v) {
  return [v.code, v.color, v.thickness_label].filter(x => x).join(' · ');
}

const linkIds = () => new Set(links.map(l => l.value));
const priceText = p => `${fmt(p.price)} ${p.currency}`;

// harga varian untuk satu supplier material: { open (BERLAKU/AKAN BERLAKU terbaru), pending }
function pricesFor(variantId, linkId) {
  const rows = prices.filter(p => p.variant_id === variantId && p.link_id === linkId);
  const open = rows.filter(p => p.state === 'ACTIVE' || p.state === 'UPCOMING')
    .sort((a, b) => String(b.valid_from).localeCompare(String(a.valid_from)))[0] || null;
  const pending = rows.find(p => p.state === 'PENDING APPROVAL') || null;
  return { open, pending };
}

// harga BERLAKU varian sumber per supplier (hanya supplier di daftar = ACTIVE)
function sourcePrices() {
  const id = $('source').value;
  const ok = linkIds();
  return prices.filter(p => p.variant_id === id && p.state === 'ACTIVE' && ok.has(p.link_id));
}

// Status satu baris varian: { text, tone, disabled }
function rowStatus(v) {
  if (mode === 'propose') {
    const link = $('link').value;
    if (!link) return { text: '', tone: '', disabled: false };
    const { open, pending } = pricesFor(v.id, link);
    if (pending) return { text: `Pending: ${priceText(pending)}`, tone: 'warn', disabled: true };
    if (open) {
      const when = open.state === 'UPCOMING' ? 'from' : 'since';
      return { text: `Active: ${priceText(open)} ${when} ${fmtDate(open.valid_from)}`, tone: 'ok', disabled: false };
    }
    return { text: 'No price yet', tone: 'muted', disabled: false };
  }
  const src = sourcePrices();
  if (!$('source').value || !src.length) return { text: '', tone: '', disabled: false };
  const waiting = src.filter(s => pricesFor(v.id, s.link_id).pending).length;
  if (waiting) return { text: `${waiting} supplier(s) still pending (skipped)`, tone: 'warn', disabled: false };
  const has = src.filter(s => pricesFor(v.id, s.link_id).open).length;
  return has ? { text: `Has a price (${has} supplier(s))`, tone: 'ok', disabled: false }
    : { text: 'No price yet', tone: 'muted', disabled: false };
}

function visibleVariants() {
  const q = $('filter').value.trim().toLowerCase();
  const src = mode === 'copy' ? $('source').value : null;
  return variants.filter(v => v.id !== src && (!q || variantLabel(v).toLowerCase().includes(q)));
}

function renderList() {
  const list = $('list');
  list.innerHTML = '';
  const shown = visibleVariants();
  // varian yang tidak bisa dicentang lagi / tidak tampil sebagai tujuan dibuang dari pilihan
  variants.forEach(v => {
    if (checked.has(v.id) && (rowStatus(v).disabled || (mode === 'copy' && v.id === $('source').value))) checked.delete(v.id);
  });
  if (!shown.length) {
    const empty = document.createElement('div');
    empty.className = 'empty';
    empty.textContent = variants.length ? 'No matching variants.' : 'No ACTIVE variants yet.';
    list.appendChild(empty);
  }
  shown.forEach(v => {
    const st = rowStatus(v);
    const row = document.createElement('label');
    row.className = 'vrow' + (st.disabled ? ' disabled' : '') + (checked.has(v.id) ? ' on' : '');
    const cb = document.createElement('input');
    cb.type = 'checkbox';
    cb.checked = checked.has(v.id);
    cb.disabled = st.disabled || busy;
    cb.addEventListener('change', () => {
      if (cb.checked) checked.add(v.id);
      else checked.delete(v.id);
      row.classList.toggle('on', cb.checked);
      updateInfo();
    });
    const name = document.createElement('span');
    name.className = 'vname';
    const code = document.createElement('b');
    code.textContent = v.code;
    name.appendChild(code);
    name.appendChild(document.createTextNode(' · ' + [v.color, v.thickness_label].filter(x => x).join(' · ')));
    const status = document.createElement('span');
    status.className = `vstat ${st.tone}`;
    status.textContent = st.text;
    row.append(cb, name, status);
    list.appendChild(row);
  });
  updateInfo();
}

function renderSource() {
  const box = $('sourcePrices');
  const src = sourcePrices();
  box.innerHTML = '';
  if (!$('source').value) {
    box.textContent = 'Only variants with an active (approved) price can be a source.';
    return;
  }
  src.forEach(p => {
    const line = document.createElement('div');
    line.textContent = `${p.supplier_name}: ${priceText(p)} since ${fmtDate(p.valid_from)}`;
    box.appendChild(line);
  });
}

function updateInfo() {
  const n = checked.size;
  $('count').textContent = n ? `${n} selected` : '';
  if (mode === 'propose') {
    const p = parsePrice($('price').value);
    const amb = isAmbiguous($('price').value);
    $('priceHint').classList.toggle('warn', amb);
    $('priceHint').textContent = amb ? 'Ambiguous: do not use thousand separators.'
      : p ? `Read as: ${fmt(p)}${currency ? ' ' + currency : ''}` : 'No thousand separators; use a comma or dot for decimals.';
    $('info').textContent = direct
      ? 'Active right away as the master price for all ticked variants (you are Manager Costing, no approval needed). '
        + 'The current price ends on the new price start date.'
      : 'Saved as a proposal (PROPOSED) for all ticked variants. It is used after '
        + 'Manager Costing approves it. The current price stays in use until then, and ends '
        + 'on the new price start date.';
  } else {
    const src = sourcePrices();
    let total = 0;
    let skip = 0;
    variants.filter(v => checked.has(v.id)).forEach(v => src.forEach(s => {
      if (pricesFor(v.id, s.link_id).pending) skip += 1;
      else total += 1;
    }));
    $('info').textContent = src.length
      ? (direct
        ? `Will save ${total} price(s) (${src.length} supplier(s) × ${n} variant(s)), active right away.`
        : `Will propose ${total} price(s) (${src.length} supplier(s) × ${n} variant(s)) as proposals (PROPOSED), `
          + 'waiting for Manager Costing approval.')
        + (skip ? ` ${skip} pair(s) skipped because a proposal is still pending.` : '')
      : 'Select a source variant with an active price.';
  }
  $('btnSave').disabled = busy || n === 0;
}

function setMode(m) {
  mode = m === 'copy' ? 'copy' : 'propose';
  $('title').textContent = mode === 'copy' ? 'Copy Price from Another Variant' : (direct ? 'Add Price' : 'Propose Price');
  $('btnSave').dataset.label = mode === 'copy' ? (direct ? 'Save copy' : 'Propose copy') : (direct ? 'Save' : 'Propose');
  $('proposeTop').hidden = mode === 'copy';
  $('priceRow').hidden = mode === 'copy';
  $('copyTop').hidden = mode !== 'copy';
  $('listLabel').innerHTML = (mode === 'copy' ? 'To variants' : 'Variants') + ' <span class="req">*</span>';
}

// Isi ulang field hanya saat modal dibuka (key berubah) - busy/message tidak menghapus ketikan user
function fillForm(m) {
  const preset = m.preset || {};
  variants = m.variants || [];
  prices = m.prices || [];
  links = m.links || [];
  direct = !!m.direct;
  setMode(m.mode);
  $('materialLabel').textContent = m.materialLabel || '';
  fillSelect($('link'), links, preset.link_id, 'Select supplier');
  const ok = linkIds();
  const sources = variants.filter(v => prices.some(p => p.variant_id === v.id && p.state === 'ACTIVE' && ok.has(p.link_id)))
    .map(v => ({ value: v.id, label: variantLabel(v) }));
  fillSelect($('source'), sources, preset.source_id, sources.length ? 'Select source variant' : 'No priced variants yet');
  checked = new Set(preset.variant_ids || []);
  $('filter').value = '';
  $('price').value = '';
  setCurrency('');                       // sengaja kosong: currency wajib dipilih
  $('validFrom').value = m.today || '';
  $('reference').value = '';
  ['link', 'source', 'price', 'validFrom'].forEach(id => $(id).classList.remove('invalid'));
  $('currency').classList.remove('invalid');
  renderSource();
  renderList();
  if (mode === 'copy') $('source').focus();
  else ($('link').value ? $('price') : $('link')).focus();
}

function setBusy(v) {
  busy = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Saving…' : ($('btnSave').dataset.label || 'Propose');
  document.querySelectorAll('#list input').forEach(cb => {
    cb.disabled = v || cb.closest('.vrow').classList.contains('disabled');
  });
  updateInfo();
}

function render(model) {
  const m = model || {};
  if (m.key !== lastKey) {
    lastKey = m.key;
    fillForm(m);
  }
  showMessage(m.message);
  setBusy(!!m.busy);
}

function fail(id, text) {
  if (id === 'currency') $('currency').classList.add('invalid');
  else if (id) {
    $(id).classList.add('invalid');
    $(id).focus();
  }
  showMessage({ type: 'error', text });
}

function submit() {
  if (busy) return;
  ['link', 'source', 'price', 'validFrom'].forEach(id => $(id).classList.remove('invalid'));
  const validFrom = $('validFrom').value;
  const ids = variants.filter(v => checked.has(v.id)).map(v => v.id);
  const reference = $('reference').value.trim();
  if (mode === 'copy') {
    if (!$('source').value) return fail('source', 'Select a source variant.');
    if (!ids.length) return fail(null, 'Tick at least one target variant.');
    if (!validFrom) return fail('validFrom', 'Start date is required.');
    appsmith.updateModel({ mode, source_id: $('source').value, variant_ids: ids, valid_from: validFrom, reference });
    appsmith.triggerEvent('onSave');
    return;
  }
  if (!$('link').value) return fail('link', 'Select a supplier.');
  if (!ids.length) return fail(null, 'Tick at least one variant.');
  if (isAmbiguous($('price').value)) {
    return fail('price', `"${$('price').value.trim()}" is ambiguous. Write it without thousand separators (e.g. 47500), with a comma for decimals (e.g. 47,5).`);
  }
  const price = parsePrice($('price').value);
  if (!price || Number(price) <= 0) return fail('price', 'Price must be a number above 0 (max 4 decimals).');
  if (!currency) return fail('currency', 'Select currency: IDR or USD.');
  if (!validFrom) return fail('validFrom', 'Start date is required.');
  const early = variants.filter(v => checked.has(v.id)).map(v => ({ v, open: pricesFor(v.id, $('link').value).open }))
    .filter(x => x.open && validFrom < String(x.open.valid_from).slice(0, 10));
  if (early.length) {
    return fail('validFrom', 'The start date cannot be earlier than an existing price: '
      + early.map(x => `${x.v.code} (${fmtDate(x.open.valid_from)})`).join(', ') + '.');
  }
  appsmith.updateModel({ mode, link_id: $('link').value, variant_ids: ids, price, currency, valid_from: validFrom, reference });
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

function selectAll(on) {
  visibleVariants().forEach(v => {
    if (on && !rowStatus(v).disabled) checked.add(v.id);
    if (!on) checked.delete(v.id);
  });
  renderList();
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  $('btnAll').addEventListener('click', () => selectAll(true));
  $('btnNone').addEventListener('click', () => selectAll(false));
  document.querySelectorAll('#currency button').forEach(b => b.addEventListener('click', () => {
    setCurrency(b.dataset.v);
    updateInfo();
  }));
  $('link').addEventListener('change', renderList);
  $('source').addEventListener('change', () => {
    renderSource();
    renderList();
  });
  $('filter').addEventListener('input', renderList);
  $('price').addEventListener('input', updateInfo);
  ['price', 'reference'].forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
