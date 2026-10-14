// cwCbdPriceForm - modal harga baris CBD (mdlCbdHarga, page Cost Breakdown (CBD)). Hanya tampilan.
// mode QUOTATION: harga quotation material proses (kosong = tidak dihargai terpisah), referensi opsional.
// mode PROPOSE  : (R8, ganti OVERRIDE yang dihapus F10b) ajukan harga MASTER untuk Material Code + supplier baris ini:
//   harga, currency & tanggal berlaku wajib, referensi opsional. model.direct (Manager Costing) = langsung berlaku.
// Simpan lewat CbdGridCtrl.savePrice() -> fn_cbd_set_quotation / fn_cbd_price_propose (aturan final di DB).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let mode = 'QUOTATION';
let direct = false;
let currency = '';

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

// "47.500" bisa berarti 47500 (titik ribuan) atau 47,5 - ditolak supaya tidak salah input
function isAmbiguous(s) {
  return /^\d{1,3}(\.\d{3})+$/.test(String(s || '').replace(/\s+/g, ''));
}

function parsePrice(s) {
  const t = String(s || '').replace(/\s+/g, '').replace(',', '.');
  return /^\d+(\.\d{1,4})?$/.test(t) ? t : null;
}

function fmt(n) {
  return Number(n).toLocaleString('id-ID', { minimumFractionDigits: 0, maximumFractionDigits: 4 });
}

function setCurrency(v) {
  currency = v === 'IDR' || v === 'USD' ? v : '';
  document.querySelectorAll('#currency button').forEach(b => b.classList.toggle('on', b.dataset.v === currency));
  if (currency) $('currency').classList.remove('invalid');
  updateHint();
}

function updateHint() {
  const raw = $('price').value.trim();
  const p = parsePrice(raw);
  $('priceHint').classList.toggle('warn', !!raw && (!p || isAmbiguous(raw)));
  $('priceHint').textContent = !raw
    ? (mode === 'QUOTATION' ? 'Empty = this line is not priced separately (cost 0).' : 'No thousand separators; use a comma or dot for decimals.')
    : isAmbiguous(raw) ? `"${raw}" is ambiguous. Write it without thousand separators (e.g. 47500), with a comma for decimals (e.g. 47,5).`
    : p ? `Read as: ${fmt(p)}${currency ? ' ' + currency : ''}`
    : 'Not a valid number (max 4 decimals).';
}

// Isi ulang hanya saat modal dibuka (key berubah) - busy/message tidak menghapus isian user
function fillForm(m) {
  mode = m.mode === 'PROPOSE' ? 'PROPOSE' : 'QUOTATION';
  direct = !!m.direct;
  $('title').textContent = m.title || (mode === 'QUOTATION' ? 'Quotation Price' : 'Propose Master Price');
  $('lineLabel').textContent = m.lineLabel || '';
  $('current').textContent = m.current || '';
  $('current').hidden = !m.current;
  const f = m.form || {};
  $('price').value = f.price || '';
  setCurrency('');                       // sengaja kosong: currency wajib dipilih
  $('text').value = f.text || '';
  $('priceReq').hidden = mode === 'QUOTATION';
  $('validBox').hidden = mode !== 'PROPOSE';
  $('validFrom').value = m.today || '';
  $('validFrom').classList.remove('invalid');
  $('textLabel').textContent = 'Reference';
  $('textReq').hidden = true;
  $('text').placeholder = mode === 'QUOTATION' ? 'quotation / offer no. (optional)' : 'supplier offer no. (optional)';
  $('textHint').textContent = mode === 'QUOTATION' ? ''
    : direct ? 'Active right away as the master price (you are Manager Costing) for all CBDs using this Material Code + supplier.'
      : 'Sent to Manager Costing as a master price proposal (not an override). After approval it applies to all CBDs '
        + 'using this Material Code + supplier; then click Refresh Prices from Master.';
  $('textHint').hidden = mode === 'QUOTATION';
  $('info').textContent = m.info || '';
  $('info').hidden = !m.info;
  ['price', 'text'].forEach(id => $(id).classList.remove('invalid'));
  $('currency').classList.remove('invalid');
  updateHint();
}

function setBusy(v) {
  busy = v;
  $('btnSave').disabled = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Saving…' : (mode === 'PROPOSE' && !direct ? 'Propose' : 'Save');
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
  else {
    $(id).classList.add('invalid');
    $(id).focus();
  }
  showMessage({ type: 'error', text });
}

function submit() {
  if (busy) return;
  ['price', 'text'].forEach(id => $(id).classList.remove('invalid'));
  const raw = $('price').value.trim();
  const text = $('text').value.trim();
  if (isAmbiguous(raw)) {
    return fail('price', `"${raw}" is ambiguous. Write it without thousand separators (e.g. 47500), with a comma for decimals (e.g. 47,5).`);
  }
  const price = raw ? parsePrice(raw) : '';
  if (raw && !price) return fail('price', 'Price must be a number (no thousand separators, max 4 decimals).');
  if (mode === 'PROPOSE' && !price) return fail('price', 'Price is required.');
  if (price && Number(price) <= 0) return fail('price', 'Price must be above 0.');
  if (price && !currency) return fail('currency', 'Select currency: IDR or USD.');
  const validFrom = $('validFrom').value;
  if (mode === 'PROPOSE' && !validFrom) return fail('validFrom', 'Start date is required.');
  appsmith.updateModel({ price: price || '', currency: price ? currency : '', text, valid_from: mode === 'PROPOSE' ? validFrom : '' });
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  document.querySelectorAll('#currency button').forEach(b => b.addEventListener('click', () => setCurrency(b.dataset.v)));
  $('price').addEventListener('input', () => {
    $('price').classList.remove('invalid');
    updateHint();
  });
  $('text').addEventListener('input', () => $('text').classList.remove('invalid'));
  $('validFrom').addEventListener('input', () => $('validFrom').classList.remove('invalid'));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
