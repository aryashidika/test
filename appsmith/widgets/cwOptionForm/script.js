// cwOptionForm - form Tambah / Ubah pilihan model (page Master Pilihan, mdlPilihan). Hanya tampilan;
// simpan lewat OptionCtrl.save() -> fn_option_save. Jenis dipilih di page (bukan di form).
// UKURAN: angka bulat, urutan otomatis. Daftar nilai mirip saat mengetik (event onSearch).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let isEdit = false;
let kind = '';
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

// ---- nilai mirip ----
const norm = s => String(s || '').trim().replace(/\s+/g, ' ').toLowerCase();

function renderSimilar(m) {
  const list = m.similar || [];
  const show = list.length > 0 && norm(m.similarFor) === norm($('value').value);
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
    const q = $('value').value.trim().replace(/\s+/g, ' ');
    if (q === lastQuery) return;
    lastQuery = q;
    appsmith.updateModel({ similarQuery: q });
    appsmith.triggerEvent('onSearch');
  }, 350);
}

// Isi ulang field hanya saat modal dibuka (key berubah) - busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  isEdit = m.mode === 'edit';
  kind = m.kind || '';
  const isSize = kind === 'UKURAN';
  $('title').textContent = `${isEdit ? 'Edit' : 'Add'} ${m.kindLabel || 'Option'}`;
  $('kindLabel').textContent = m.kindLabel || kind;
  $('scopeNote').textContent = m.isFactoryKind
    ? `Applies to your factory only${m.factoryName ? ` (${m.factoryName})` : ''}.`
    : 'Shared by all factories.';
  $('value').type = isSize ? 'number' : 'text';      // tipe dulu: nilai teks ditolak input number
  $('value').value = f.value || '';
  $('value').placeholder = isSize ? 'e.g. 40 (whole number)' : '';
  $('value').classList.remove('invalid');
  $('sort').value = f.sort_order === null || f.sort_order === undefined ? '' : String(f.sort_order);
  $('sortBox').hidden = isSize;
  fillSelect($('status'), m.statusOptions, f.status || 'ACTIVE');
  $('statusBox').hidden = !isEdit;
  lastQuery = isEdit ? $('value').value.trim() : null;
  $('value').focus();
}

function setBusy(v) {
  busy = v;
  $('btnSave').disabled = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Saving…' : 'Save';
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
  const value = $('value').value.trim().replace(/\s+/g, ' ');
  const sort = $('sort').value.trim();
  $('value').classList.remove('invalid');
  if (!value) {
    $('value').classList.add('invalid');
    showMessage({ type: 'error', text: 'Value is required.' });
    return;
  }
  if (kind === 'UKURAN' && !/^\d{1,2}$/.test(value)) {
    $('value').classList.add('invalid');
    showMessage({ type: 'error', text: 'Size must be a whole number (e.g. 40), no half sizes.' });
    return;
  }
  if (sort && !/^\d+$/.test(sort)) {
    showMessage({ type: 'error', text: 'Order must be a whole number.' });
    return;
  }
  appsmith.updateModel({ value, sort_order: kind === 'UKURAN' ? '' : sort, status: $('status').value });
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  $('value').addEventListener('input', querySimilar);
  ['value', 'sort'].forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
