// cwFactoryForm — form Tambah/Ubah Pabrik di mdlPabrik. Hanya tampilan; simpan lewat AdminCtrl.saveFactory().
const $ = (id) => document.getElementById(id);
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
  if (!m || !m.text) { box.hidden = true; box.textContent = ''; return; }
  box.className = `msg ${m.type || 'info'}`;
  box.textContent = m.text;
  box.hidden = false;
}

function fillForm(m) {
  const f = m.form || {};
  $('title').textContent = f.id ? 'Ubah Pabrik' : 'Tambah Pabrik';
  $('name').value = f.name || '';
  $('name').classList.remove('invalid');
  $('status').value = f.status || 'ACTIVE';
  $('name').focus();
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

function submit() {
  if (busy) return;
  const name = $('name').value.trim().replace(/\s+/g, ' ');
  $('name').classList.toggle('invalid', !name);
  if (!name) { showMessage({ type: 'error', text: 'Nama pabrik wajib diisi.' }); return; }
  appsmith.updateModel({ name, status: $('status').value });
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  $('name').addEventListener('keydown', (e) => { if (e.key === 'Enter') submit(); });
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
