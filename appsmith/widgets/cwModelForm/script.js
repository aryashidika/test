// cwModelForm — form Tambah / Ubah Model di mdlModel. Hanya tampilan; simpan lewat
// ModelCtrl.save() (Model List) atau ModelDetailCtrl.saveModel() (Model Detail).
// Aturan final (kode unik tidak peka huruf besar/kecil) di DB (trg_model_check).
const $ = id => document.getElementById(id);
const FIELDS = ['code', 'category', 'name', 'factory', 'outsole_mold', 'last_no', 'construction', 'size_range', 'sample_size'];
let lastKey = null;
let busy = false;

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

// Isi ulang field hanya saat modal dibuka (key berubah) — busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  $('title').textContent = m.mode === 'edit' ? 'Ubah Model' : 'Tambah Model';
  FIELDS.forEach(id => {
    $(id).value = f[id] || '';
    $(id).classList.remove('invalid');
  });
  (m.mode === 'edit' ? $('name') : $('code')).focus();
}

function setBusy(v) {
  busy = v;
  $('btnSave').disabled = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Menyimpan…' : 'Simpan';
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

function clean(id) {
  return $(id).value.trim().replace(/\s+/g, ' ');
}

function submit() {
  if (busy) return;
  const data = {};
  FIELDS.forEach(id => {
    data[id] = clean(id);
    $(id).classList.remove('invalid');
  });
  const missing = [['code', 'Kode model'], ['name', 'Nama model']].find(([id]) => !data[id]);
  if (missing) {
    $(missing[0]).classList.add('invalid');
    $(missing[0]).focus();
    showMessage({ type: 'error', text: `${missing[1]} wajib diisi.` });
    return;
  }
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
  FIELDS.forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
