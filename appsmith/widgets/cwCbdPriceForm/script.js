// cwCbdPriceForm — modal harga baris CBD (mdlCbdHarga, page Cost Breakdown (CBD)). Hanya tampilan.
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

// "47.500" bisa berarti 47500 (titik ribuan) atau 47,5 — ditolak supaya tidak salah input
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
    ? (mode === 'QUOTATION' ? 'Kosongkan = baris ini tidak dihargai terpisah (cost 0).' : 'Tanpa titik ribuan; desimal pakai koma atau titik.')
    : isAmbiguous(raw) ? `"${raw}" ambigu — tulis tanpa titik ribuan (mis. 47500), desimal pakai koma (mis. 47,5).`
    : p ? `Terbaca: ${fmt(p)}${currency ? ' ' + currency : ''}`
    : 'Bukan angka yang valid (maks. 4 desimal).';
}

// Isi ulang hanya saat modal dibuka (key berubah) — busy/message tidak menghapus isian user
function fillForm(m) {
  mode = m.mode === 'PROPOSE' ? 'PROPOSE' : 'QUOTATION';
  direct = !!m.direct;
  $('title').textContent = m.title || (mode === 'QUOTATION' ? 'Harga Quotation' : 'Ajukan Harga Master');
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
  $('textLabel').textContent = 'Referensi';
  $('textReq').hidden = true;
  $('text').placeholder = mode === 'QUOTATION' ? 'no. quotation / penawaran (opsional)' : 'no. penawaran supplier (opsional)';
  $('textHint').textContent = mode === 'QUOTATION' ? ''
    : direct ? 'Langsung berlaku sebagai harga master (Anda Manager Costing) untuk semua CBD yang memakai Material Code + supplier ini.'
      : 'Masuk ke Manager Costing sebagai usulan harga master (bukan override) — setelah disetujui berlaku untuk semua CBD '
        + 'yang memakai Material Code + supplier ini; lalu klik Refresh Harga dari Master.';
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
  $('btnSave').textContent = v ? 'Menyimpan…' : (mode === 'PROPOSE' && !direct ? 'Ajukan' : 'Simpan');
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
    return fail('price', `"${raw}" ambigu. Tulis tanpa titik ribuan (mis. 47500), desimal pakai koma (mis. 47,5).`);
  }
  const price = raw ? parsePrice(raw) : '';
  if (raw && !price) return fail('price', 'Harga harus angka (tanpa titik ribuan, maks. 4 desimal).');
  if (mode === 'PROPOSE' && !price) return fail('price', 'Harga wajib diisi.');
  if (price && Number(price) <= 0) return fail('price', 'Harga harus lebih besar dari 0.');
  if (price && !currency) return fail('currency', 'Pilih currency: IDR atau USD.');
  const validFrom = $('validFrom').value;
  if (mode === 'PROPOSE' && !validFrom) return fail('validFrom', 'Tanggal berlaku wajib diisi.');
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
