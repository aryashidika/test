// cwUserForm — form Tambah/Ubah User di mdlUser. Hanya tampilan; simpan lewat AdminCtrl.save().
const $ = id => document.getElementById(id);
const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
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
function fillRoles(options, selected) {
  const sel = $('role');
  sel.innerHTML = '';
  const ph = document.createElement('option');
  ph.value = '';
  ph.textContent = '— Pilih role —';
  sel.appendChild(ph);
  (options || []).forEach(o => {
    const opt = document.createElement('option');
    opt.value = o.value;
    opt.textContent = o.label;
    sel.appendChild(opt);
  });
  sel.value = selected || '';
}

// Isi ulang field hanya saat modal dibuka (key berubah) — busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  const isEdit = m.mode === 'edit';
  const isSelf = isEdit && m.selfEmail && f.email === m.selfEmail;
  $('title').textContent = isEdit ? 'Ubah User' : 'Tambah User';
  $('email').value = f.email || '';
  $('email').disabled = isEdit;
  $('email').classList.remove('invalid');
  $('emailNote').hidden = !isEdit;
  $('fullName').value = f.full_name || '';
  fillRoles(m.roleOptions, f.role);
  $('role').disabled = !!isSelf;
  $('active').checked = f.is_active !== false;
  $('active').disabled = !!isSelf;
  $('selfNote').hidden = !isSelf;
  $('addInfo').hidden = isEdit;
  (isEdit ? $('fullName') : $('email')).focus();
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
  const email = $('email').value.trim().toLowerCase();
  const full_name = $('fullName').value.trim();
  const role = $('role').value;
  let error = '';
  if (!EMAIL_RE.test(email)) error = 'Format email tidak valid.';else if (!full_name) error = 'Nama lengkap wajib diisi.';else if (!role) error = 'Role wajib dipilih.';
  $('email').classList.toggle('invalid', !EMAIL_RE.test(email));
  if (error) {
    showMessage({
      type: 'error',
      text: error
    });
    return;
  }
  appsmith.updateModel({
    email,
    full_name,
    role,
    is_active: $('active').checked
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
  ['email', 'fullName'].forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
