// cwSupplierForm — form Tambah/Ubah Supplier di mdlSupplier. Hanya tampilan; simpan lewat SupplierCtrl.save().
// R2: tanpa usulan/approval (status ACTIVE/INACTIVE), daftar nama mirip saat mengetik (event onSearch).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
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
  sel.value = selected || (options && options[0] ? options[0].value : '');
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
  const isEdit = m.mode === 'edit';
  $('title').textContent = isEdit ? 'Ubah Supplier' : 'Tambah Supplier';
  $('name').value = f.name || '';
  $('name').classList.remove('invalid');
  fillSelect($('status'), m.statusOptions, f.status || 'ACTIVE');
  $('statusBox').hidden = !isEdit;
  $('addInfo').hidden = isEdit;
  $('editNote').hidden = !isEdit;
  lastQuery = isEdit ? $('name').value.trim() : null;
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
  renderSimilar(m);
}

function submit() {
  if (busy) return;
  const name = $('name').value.trim().replace(/\s+/g, ' ');
  $('name').classList.toggle('invalid', !name);
  if (!name) {
    showMessage({ type: 'error', text: 'Nama supplier wajib diisi.' });
    return;
  }
  appsmith.updateModel({
    name,
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
  $('name').addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  });
  $('name').addEventListener('input', querySimilar);
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
