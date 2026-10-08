// cwMaterialForm — form Tambah / Ubah Material INDUK di mdlMaterial (Master Material & Material Detail).
// Hanya tampilan; simpan lewat MaterialCtrl.save() / MaterialDetailCtrl.saveMaterial().
// R2: tanpa Material Code & thickness (pindah ke varian), tanpa usulan; metode harga hanya tim CBD
// (canPriceMethod); daftar nama mirip saat mengetik (event onSearch). Aturan final di DB.
const $ = id => document.getElementById(id);
const IDENTITY = ['category', 'name', 'uom'];
const METHOD_HINT = {
  CATALOG: 'Harga diambil dari master harga per varian × supplier (diajukan tim CBD).',
  QUOTATION: 'Material proses (printing, molding, dst.): tidak ada harga master, harga diisi per CBD.',
};
let lastKey = null;
let busy = false;
let isEdit = false;
let method = 'CATALOG';
let canPriceMethod = false;
let similarTimer = null;
let lastQuery = null;

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

// ---- nama mirip ----
const norm = s => String(s || '').trim().replace(/\s+/g, ' ').toLowerCase();

function renderSimilar(m) {
  const list = m.similar || [];
  const show = list.length > 0 && norm(m.similarFor) === norm($('name').value);
  $('similar').hidden = !show;
  const ul = $('similarList');
  ul.innerHTML = '';
  if (!show) return;
  list.forEach(x => {
    const li = document.createElement('li');
    li.textContent = x.label;
    if (x.info) {
      const meta = document.createElement('span');
      meta.className = 'meta';
      meta.textContent = ` · ${x.info}`;
      li.appendChild(meta);
    }
    ul.appendChild(li);
  });
}

function querySimilar() {
  clearTimeout(similarTimer);
  similarTimer = setTimeout(() => {
    const q = $('name').value.trim().replace(/\s+/g, ' ');
    if (q === lastQuery) return;
    lastQuery = q;
    appsmith.updateModel({ similarQuery: q });
    appsmith.triggerEvent('onSearch');
  }, 350);
}

// Isi ulang field hanya saat modal dibuka (key berubah) — busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  isEdit = m.mode === 'edit';
  canPriceMethod = !!m.canPriceMethod;
  $('title').textContent = isEdit ? 'Ubah Material' : 'Tambah Material';
  $('name').value = f.name || '';
  $('category').value = f.category || '';
  $('uom').value = f.uom || '';
  fillDatalist($('dlCategory'), m.categories);
  fillDatalist($('dlUom'), m.uoms);
  setMethod(f.price_method);
  fillSelect($('status'), m.statusOptions, f.status || 'ACTIVE');

  const canIdentity = m.canIdentity !== false;
  IDENTITY.forEach(id => {
    $(id).disabled = !canIdentity;
    $(id).classList.remove('invalid');
  });
  document.querySelectorAll('#method button').forEach(b => { b.disabled = !canPriceMethod; });
  $('statusBox').hidden = !(isEdit && m.canStatus);
  const notes = [];
  if (!canIdentity) notes.push('Data material diubah tim specsheet (Vendor Spec).');
  if (!canPriceMethod) notes.push('Metode harga ditentukan tim CBD (default Catalog).');
  $('lockNote').textContent = notes.join(' ');
  $('lockNote').hidden = notes.length === 0;
  $('addInfo').hidden = isEdit;
  lastQuery = isEdit ? $('name').value.trim() : null;
  (canIdentity ? (isEdit ? $('name') : $('category')) : $('btnCancel')).focus();
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
  renderSimilar(m);
}

function clean(id) {
  return $(id).value.trim().replace(/\s+/g, ' ');
}

function submit() {
  if (busy) return;
  const data = {
    name: clean('name'),
    category: clean('category'),
    uom: clean('uom').toUpperCase(),
    price_method: method,
    status: $('status').value,
  };
  IDENTITY.forEach(id => $(id).classList.remove('invalid'));
  const required = [['category', 'Kategori'], ['name', 'Nama material'], ['uom', 'Mea (UoM)']];
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
  $('name').addEventListener('input', querySimilar);
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
