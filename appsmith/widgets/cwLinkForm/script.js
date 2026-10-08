// cwLinkForm — form Tambah / Ubah supplier material di mdlLink (page Material Detail). Hanya tampilan;
// simpan lewat MaterialDetailCtrl.saveLink() -> fn_link_save. Hak ubah per field dari model
// (canLink: supplier utama, canStatus: status); aturan final di DB. R2: tanpa kode supplier & approval.
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let isEdit = false;

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

// Isi ulang field hanya saat modal dibuka (key berubah) — busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  isEdit = m.mode === 'edit';
  const canLink = m.canLink !== false;
  const canStatus = !!m.canStatus;
  $('title').textContent = isEdit ? 'Ubah Supplier Material' : 'Tambah Supplier Material';
  $('materialLabel').textContent = m.materialLabel || '';

  $('supplier').hidden = isEdit;
  $('supplierHint').hidden = isEdit;
  $('supplierName').hidden = !isEdit;
  $('supplierName').textContent = f.supplier_name || '';
  const options = m.supplierOptions || [];
  fillSelect($('supplier'), options, f.supplier_id, options.length ? '— Pilih supplier —' : '— Semua supplier sudah terdaftar —');
  $('supplier').classList.remove('invalid');

  $('preferred').checked = !!f.is_preferred;
  $('preferred').disabled = !canLink;

  fillSelect($('status'), m.statusOptions, f.status || 'ACTIVE');
  $('statusBox').hidden = !(isEdit && canStatus);

  $('lockNote').textContent = isEdit && !canLink ? 'Supplier utama diatur tim specsheet.' : '';
  $('lockNote').hidden = !(isEdit && !canLink);
  $('proposeInfo').hidden = isEdit;
  (isEdit ? $('status') : $('supplier')).focus();
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
  const supplierId = $('supplier').value;
  if (!isEdit && !supplierId) {
    $('supplier').classList.add('invalid');
    $('supplier').focus();
    showMessage({ type: 'error', text: 'Pilih supplier.' });
    return;
  }
  appsmith.updateModel({
    supplier_id: supplierId,
    is_preferred: $('preferred').checked,
    status: $('status').value,
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
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
