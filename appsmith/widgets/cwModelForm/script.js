// cwModelForm — form Tambah / Ubah Model di mdlModel. Hanya tampilan; simpan lewat
// ModelCtrl.save() (Model List) atau ModelDetailCtrl.saveModel() (Model Detail) -> fn_model_save.
// R4: kode model dihapus (nama = identitas, unik per pabrik). Kategori/Gender/Construction/Last/Outsole mould =
// dropdown dari Master Pilihan; ukuran = grid ala kalender (klik awal + akhir = rentang, klik lagi = buang),
// sample size dipilih dari ukuran terpilih.
const $ = id => document.getElementById(id);
const SELECTS = [['category_id', 'KATEGORI'], ['gender_id', 'GENDER'], ['construction_id', 'CONSTRUCTION'],
  ['last_id', 'LAST'], ['outsole_mold_id', 'OUTSOLE_MOLD']];
let lastKey = null;
let busy = false;
let sizeList = [];          // ukuran yang bisa dipilih (angka)
let picked = new Set();     // ukuran terpilih
let anchor = null;          // ukuran awal rentang yang menunggu klik kedua

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

function fillSelect(sel, options, selected, placeholder) {
  sel.innerHTML = '';
  const ph = document.createElement('option');
  ph.value = '';
  ph.textContent = placeholder;
  sel.appendChild(ph);
  (options || []).forEach(o => {
    const opt = document.createElement('option');
    opt.value = o.value;
    opt.textContent = o.label;
    sel.appendChild(opt);
  });
  sel.value = selected || '';
}

// [37, 38, 39, 40, 42] -> "37–40, 42"
function sizeLabel(list) {
  const v = [...list].sort((a, b) => a - b);
  const parts = [];
  let s = null;
  let e = null;
  v.forEach(n => {
    if (s !== null && n === e + 1) {
      e = n;
      return;
    }
    if (s !== null) parts.push(s === e ? `${s}` : `${s}–${e}`);
    s = n;
    e = n;
  });
  if (s !== null) parts.push(s === e ? `${s}` : `${s}–${e}`);
  return parts.join(', ');
}

function renderSizes() {
  const box = $('sizes');
  box.innerHTML = '';
  sizeList.forEach(n => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'size' + (picked.has(n) ? ' on' : '') + (anchor === n ? ' anchor' : '');
    b.textContent = n;
    b.disabled = busy;
    b.addEventListener('click', () => clickSize(n));
    box.appendChild(b);
  });
  $('sizeSum').textContent = picked.size ? `${sizeLabel(picked)} (${picked.size} ukuran)` : 'Belum dipilih';
  const sample = $('sample_size').value;
  fillSelect($('sample_size'), [...picked].sort((a, b) => a - b).map(n => ({ value: String(n), label: String(n) })),
    picked.has(Number(sample)) ? sample : '', picked.size ? '— pilih —' : '— pilih ukuran dulu —');
}

function clickSize(n) {
  if (anchor !== null && anchor !== n) {
    const lo = Math.min(anchor, n);
    const hi = Math.max(anchor, n);
    sizeList.filter(x => x >= lo && x <= hi).forEach(x => picked.add(x));
    anchor = null;
  } else if (anchor === n) {
    anchor = null;                 // klik ukuran yang sama lagi = hanya ukuran itu
  } else if (picked.has(n)) {
    picked.delete(n);
  } else {
    picked.add(n);
    anchor = n;
  }
  renderSizes();
}

// Isi ulang field hanya saat modal dibuka (key berubah) — busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  const opts = m.options || {};
  $('title').textContent = m.mode === 'edit' ? 'Ubah Model' : 'Tambah Model';
  $('name').value = f.name || '';
  $('name').classList.remove('invalid');
  SELECTS.forEach(([id, kind]) => {
    fillSelect($(id), opts[kind], f[id], id === 'category_id' ? '— pilih kategori —' : '— kosong —');
    $(id).classList.remove('invalid');
  });
  picked = new Set((f.sizes || []).map(Number).filter(n => n > 0));
  sizeList = [...new Set((m.sizes || []).map(Number).concat([...picked]))].filter(n => n > 0).sort((a, b) => a - b);
  anchor = null;
  renderSizes();
  $('sample_size').value = f.sample_size && picked.has(Number(f.sample_size)) ? String(f.sample_size) : '';
  $('name').focus();
}

function setBusy(v) {
  busy = v;
  $('btnSave').disabled = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Menyimpan…' : 'Simpan';
  document.querySelectorAll('#sizes .size').forEach(b => { b.disabled = v; });
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

function submit() {
  if (busy) return;
  const name = $('name').value.trim().replace(/\s+/g, ' ');
  $('name').classList.remove('invalid');
  $('category_id').classList.remove('invalid');
  if (!name) {
    $('name').classList.add('invalid');
    $('name').focus();
    showMessage({ type: 'error', text: 'Nama model wajib diisi.' });
    return;
  }
  if (!$('category_id').value) {
    $('category_id').classList.add('invalid');
    $('category_id').focus();
    showMessage({ type: 'error', text: 'Kategori wajib dipilih.' });
    return;
  }
  const data = { name, sizes: [...picked].sort((a, b) => a - b), sample_size: $('sample_size').value ? Number($('sample_size').value) : null };
  SELECTS.forEach(([id]) => { data[id] = $(id).value; });
  appsmith.updateModel(data);
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  $('btnSizeClear').addEventListener('click', () => {
    picked = new Set();
    anchor = null;
    renderSizes();
  });
  $('name').addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  });
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
