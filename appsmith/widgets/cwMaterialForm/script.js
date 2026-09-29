// cwMaterialForm — form Tambah / Usulkan / Ubah Material di mdlMaterial. Hanya tampilan; simpan lewat
// MaterialCtrl.save(). Hak ubah per field ditentukan model (canIdentity, canPriceMethod, canStatus);
// aturan final di DB (fn_material_add / fn_material_update / trg_material_check).
const $ = id => document.getElementById(id);
const IDENTITY = ['code', 'category', 'name', 'thickness', 'uom'];
const METHOD_HINT = {
  CATALOG: 'Harga diambil dari master harga per supplier (diisi tim CBD di Material Detail).',
  QUOTATION: 'Material proses (printing, molding, dst.): tidak ada harga master, harga diisi per CBD.',
};
let lastKey = null;
let busy = false;
let isEdit = false;
let nextCode = '';
let method = 'CATALOG';
let canPriceMethod = true;

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

function fillSelect(sel, options, selected) {
  sel.innerHTML = '';
  (options || []).forEach(o => {
    const opt = document.createElement('option');
    opt.value = o.value;
    opt.textContent = o.label;
    sel.appendChild(opt);
  });
  sel.value = selected || '';
}

function fillDatalist(dl, values) {
  dl.innerHTML = '';
  (values || []).forEach(v => {
    const opt = document.createElement('option');
    opt.value = v;
    dl.appendChild(opt);
  });
}

function setMethod(v) {
  method = v === 'QUOTATION' ? 'QUOTATION' : 'CATALOG';
  document.querySelectorAll('#method button').forEach(b => b.classList.toggle('on', b.dataset.v === method));
  $('methodHint').textContent = METHOD_HINT[method];
}

function updateSuggest() {
  $('btnSuggest').hidden = isEdit || !nextCode || $('code').value.trim().toUpperCase() === nextCode;
  $('btnSuggest').textContent = `Pakai saran ${nextCode}`;
}

// Isi ulang field hanya saat modal dibuka (key berubah) — busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  isEdit = m.mode === 'edit';
  nextCode = m.nextCode || '';
  canPriceMethod = m.canPriceMethod !== false;
  $('title').textContent = isEdit ? 'Ubah Material' : (m.canManage ? 'Tambah Material' : 'Usulkan Material');
  $('code').value = f.material_code || (isEdit ? '' : nextCode);
  $('name').value = f.name || '';
  $('category').value = f.category || '';
  $('thickness').value = f.thickness || '';
  $('uom').value = f.uom || '';
  fillDatalist($('dlCategory'), m.categories);
  fillDatalist($('dlUom'), m.uoms);
  setMethod(f.price_method);
  fillSelect($('status'), m.statusOptions, f.status || 'APPROVED');

  const canIdentity = m.canIdentity !== false;
  IDENTITY.forEach(id => {
    $(id).disabled = !canIdentity;
    $(id).classList.remove('invalid');
  });
  document.querySelectorAll('#method button').forEach(b => { b.disabled = !canPriceMethod; });
  $('statusBox').hidden = !(isEdit && m.canStatus);
  const notes = [];
  if (!canIdentity) notes.push('Data material hanya bisa diubah Master Admin.');
  if (!canPriceMethod) notes.push('Metode harga ditentukan tim CBD.');
  $('lockNote').textContent = notes.join(' ');
  $('lockNote').hidden = notes.length === 0;
  $('proposeInfo').hidden = isEdit || !!m.canManage;
  $('btnSave').dataset.label = !isEdit && !m.canManage ? 'Usulkan' : 'Simpan';
  updateSuggest();
  (canIdentity ? (isEdit ? $('name') : $('category')) : $('btnCancel')).focus();
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

function clean(id) {
  return $(id).value.trim().replace(/\s+/g, ' ');
}

function submit() {
  if (busy) return;
  const data = {
    material_code: clean('code').toUpperCase(),
    name: clean('name'),
    category: clean('category'),
    thickness: clean('thickness'),
    uom: clean('uom').toUpperCase(),
    price_method: method,
    status: $('status').value,
  };
  IDENTITY.forEach(id => $(id).classList.remove('invalid'));
  const required = [['code', 'Material Code'], ['category', 'Kategori'], ['name', 'Nama material'], ['uom', 'UoM']];
  const missing = required.find(([id]) => !clean(id));
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
  $('code').addEventListener('input', updateSuggest);
  $('btnSuggest').addEventListener('click', () => {
    $('code').value = nextCode;
    $('code').classList.remove('invalid');
    updateSuggest();
  });
  document.querySelectorAll('#method button').forEach(b => b.addEventListener('click', () => {
    if (canPriceMethod) setMethod(b.dataset.v);
  }));
  IDENTITY.forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
