# Perubahan Custom Widget R1 (diterapkan ke sumber dari export, bukan ditulis ulang)

USER_HTML = [
    ('''  <label for="role">Role <span class="req">*</span></label>
  <select id="role"></select>
''', '''  <label for="role">Role <span class="req">*</span></label>
  <select id="role"></select>

  <div id="factoryRow" hidden>
    <label for="factory">Pabrik <span class="req">*</span></label>
    <select id="factory"></select>
    <div class="field-note">Vendor Spec, Vendor CBD, dan Manager Costing hanya melihat data pabriknya.</div>
  </div>
'''),
]

USER_JS = [
    ('''// Isi ulang field hanya saat modal dibuka''', '''function fillFactories(options, selected) {
  const sel = $('factory');
  sel.innerHTML = '';
  const ph = document.createElement('option');
  ph.value = ''; ph.textContent = '— Pilih pabrik —';
  sel.appendChild(ph);
  (options || []).forEach((o) => {
    const opt = document.createElement('option');
    opt.value = o.value; opt.textContent = o.label;
    sel.appendChild(opt);
  });
  sel.value = selected || '';
}

let factoryRoles = [];
function needsFactory() {
  return factoryRoles.includes($('role').value);
}
function toggleFactory() {
  $('factoryRow').hidden = !needsFactory();
}

// Isi ulang field hanya saat modal dibuka'''),
    ('''  fillRoles(m.roleOptions, f.role);
  $('role').disabled = !!isSelf;''', '''  fillRoles(m.roleOptions, f.role);
  $('role').disabled = !!isSelf;
  factoryRoles = m.factoryRoles || [];
  fillFactories(m.factoryOptions, f.factory_id);
  toggleFactory();'''),
    ('''  else if (!role) error = 'Role wajib dipilih.';''', '''  else if (!role) error = 'Role wajib dipilih.';
  else if (needsFactory() && !$('factory').value) error = 'Pilih pabrik untuk role ini.';'''),
    ('''  appsmith.updateModel({ email, full_name, role, is_active: $('active').checked });''',
     '''  const factory_id = needsFactory() ? $('factory').value : '';
  appsmith.updateModel({ email, full_name, role, is_active: $('active').checked, factory_id });'''),
    ('''  $('btnX').addEventListener('click', cancel);''', '''  $('btnX').addEventListener('click', cancel);
  $('role').addEventListener('change', toggleFactory);'''),
]

USER_MODEL = ('''  roleOptions: AdminCtrl.roleOptions,''', '''  roleOptions: AdminCtrl.roleOptions,
  factoryRoles: AdminCtrl.factoryRoles,
  factoryOptions: AdminCtrl.factoryOptions(),''')

FACTORY_HTML = '''<div class="wrap">
  <div class="head">
    <h2 id="title">Tambah Pabrik</h2>
    <button type="button" class="x" id="btnX" aria-label="Tutup">✕</button>
  </div>

  <div id="msg" class="msg" role="alert" hidden></div>

  <label for="name">Nama pabrik <span class="req">*</span></label>
  <input id="name" type="text" maxlength="100" autocomplete="off" placeholder="mis. PT PRESTASI">

  <label for="status">Status <span class="req">*</span></label>
  <select id="status">
    <option value="ACTIVE">ACTIVE</option>
    <option value="INACTIVE">INACTIVE</option>
  </select>
  <div class="field-note">Pabrik tidak bisa dinonaktifkan selama masih punya user aktif.</div>

  <div class="actions">
    <button type="button" class="btn-secondary" id="btnCancel">Batal</button>
    <button type="button" class="btn-primary" id="btnSave">Simpan</button>
  </div>
</div>
'''

FACTORY_JS = '''// cwFactoryForm — form Tambah/Ubah Pabrik di mdlPabrik. Hanya tampilan; simpan lewat AdminCtrl.saveFactory().
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
  const name = $('name').value.trim().replace(/\\s+/g, ' ');
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
'''

FACTORY_MODEL = '''{{ {
  key: AdminCtrl.factoryKey,
  form: AdminCtrl.factoryForm,
  busy: AdminCtrl.factoryBusy,
  message: AdminCtrl.factoryMessage
} }}'''
