// cwPriceForm — form Tambah Harga di mdlHarga (page Material Detail). Hanya tampilan; simpan lewat
// MaterialDetailCtrl.savePrice() -> fn_price_add. Currency tidak punya nilai awal (wajib dipilih).
// Harga baru menutup harga yang masih berlaku untuk supplier + warna yang sama (dicek final di DB).
// needsApproval (Vendor CBD): harga jadi usulan PROPOSED; harga lama baru ditutup saat di-approve Manager Costing.
// Maks. satu usulan per supplier + warna: kalau sudah ada (pendingPrices), simpan diblokir.
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let currency = '';
let openPrices = [];
let pendingPrices = [];
let needsApproval = false;

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

// = fn_normalize di DB: huruf kecil, koma -> titik, spasi dirapatkan, trim
function normalize(s) {
  return String(s || '').toLowerCase().replace(/,/g, '.').replace(/\s+/g, ' ').trim();
}

// "45000" / "3,25" / "3.25" -> "3.25"; null kalau tidak valid
function parsePrice(s) {
  const t = String(s || '').replace(/\s+/g, '').replace(',', '.');
  return /^\d+(\.\d{1,4})?$/.test(t) ? t : null;
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

function findFor(list) {
  const key = normalize($('color').value);
  return list.find(p => p.link_id === $('link').value && normalize(p.color) === key) || null;
}

function currentOpen() {
  return findFor(openPrices);
}

function currentPending() {
  return findFor(pendingPrices);
}

function updateInfo() {
  const p = parsePrice($('price').value);
  $('priceHint').classList.toggle('warn', isAmbiguous($('price').value));
  $('priceHint').textContent = isAmbiguous($('price').value)
    ? 'Ambigu: jangan pakai titik ribuan.'
    : p ? `Terbaca: ${fmt(p)}${currency ? ' ' + currency : ''}`
      : 'Tanpa titik ribuan; desimal pakai koma atau titik.';
  const pending = currentPending();
  const warn = $('pendingWarn');
  warn.hidden = !pending;
  if (pending) {
    const what = pending.color ? `warna ${pending.color}` : 'semua warna';
    warn.textContent = `Sudah ada usulan ${fmt(pending.price)} ${pending.currency} untuk ${what} yang menunggu approval. `
      + 'Batalkan usulan itu dulu (tombol Batalkan di tabel harga) atau tunggu Manager Costing memprosesnya.';
  }
  const open = currentOpen();
  const parts = [];
  if (needsApproval) parts.push('Harga ini tersimpan sebagai usulan (PROPOSED) dan baru dipakai setelah di-approve Manager Costing.');
  if (open) {
    const what = open.color ? `warna ${open.color}` : 'semua warna';
    parts.push(`Harga berlaku untuk ${what}: ${fmt(open.price)} ${open.currency} sejak ${fmtDate(open.valid_from)}. `
      + (needsApproval ? 'Harga itu tetap berlaku sampai usulan di-approve, lalu ditutup per tanggal berlaku harga baru.'
        : 'Harga itu akan ditutup per tanggal berlaku harga baru dan masuk riwayat.'));
  }
  $('closeInfo').textContent = parts.join(' ');
  $('closeInfo').hidden = parts.length === 0;
}

// Isi ulang field hanya saat modal dibuka (key berubah) — busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  openPrices = m.openPrices || [];
  pendingPrices = m.pendingPrices || [];
  needsApproval = !!m.needsApproval;
  $('title').textContent = needsApproval ? 'Usulkan Harga' : 'Tambah Harga';
  $('btnSave').dataset.label = needsApproval ? 'Usulkan' : 'Simpan';
  $('materialLabel').textContent = m.materialLabel || '';
  fillSelect($('link'), m.links, f.link_id, '— Pilih supplier —');
  const dl = $('dlColor');
  dl.innerHTML = '';
  (m.colorSuggestions || []).forEach(c => {
    const opt = document.createElement('option');
    opt.value = c;
    dl.appendChild(opt);
  });
  $('color').value = f.color || '';
  $('price').value = '';
  setCurrency('');                       // sengaja kosong: currency wajib dipilih
  $('validFrom').value = m.today || '';
  $('reference').value = '';
  ['link', 'price', 'validFrom'].forEach(id => $(id).classList.remove('invalid'));
  $('currency').classList.remove('invalid');
  updateInfo();
  ($('link').value ? $('price') : $('link')).focus();
}

function setBusy(v) {
  busy = v;
  $('btnSave').disabled = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Menyimpan…' : ($('btnSave').dataset.label || 'Simpan');
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

// "47.500" bisa berarti 47500 (titik ribuan) atau 47,5 — ditolak supaya tidak salah input
function isAmbiguous(s) {
  return /^\d{1,3}(\.\d{3})+$/.test(String(s || '').replace(/\s+/g, ''));
}

function submit() {
  if (busy) return;
  ['link', 'price', 'validFrom'].forEach(id => $(id).classList.remove('invalid'));
  if (isAmbiguous($('price').value)) {
    return fail('price', `"${$('price').value.trim()}" ambigu. Tulis tanpa titik ribuan (mis. 47500), desimal pakai koma (mis. 47,5).`);
  }
  const price = parsePrice($('price').value);
  const validFrom = $('validFrom').value;
  if (!$('link').value) return fail('link', 'Pilih supplier.');
  if (!price || Number(price) <= 0) return fail('price', 'Harga wajib diisi dengan angka lebih dari 0 (maks. 4 desimal).');
  if (!currency) return fail('currency', 'Pilih currency: IDR atau USD.');
  if (!validFrom) return fail('validFrom', 'Tanggal berlaku mulai wajib diisi.');
  if (currentPending()) {
    return fail('color', 'Masih ada usulan harga untuk supplier + warna ini yang menunggu approval.');
  }
  const open = currentOpen();
  if (open && validFrom < String(open.valid_from).slice(0, 10)) {
    return fail('validFrom', `Tanggal berlaku tidak boleh lebih awal dari harga yang berlaku sekarang (${fmtDate(open.valid_from)}).`);
  }
  appsmith.updateModel({
    link_id: $('link').value,
    color: $('color').value.trim().replace(/\s+/g, ' '),
    price,
    currency,
    valid_from: validFrom,
    reference: $('reference').value.trim(),
  });
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  document.querySelectorAll('#currency button').forEach(b => b.addEventListener('click', () => {
    setCurrency(b.dataset.v);
    updateInfo();
  }));
  ['link', 'color', 'price'].forEach(id => $(id).addEventListener('input', updateInfo));
  $('link').addEventListener('change', updateInfo);
  ['color', 'price', 'reference'].forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
