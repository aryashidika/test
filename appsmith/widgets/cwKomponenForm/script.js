// cwKomponenForm — form Tambah/Usulkan/Ubah Komponen di mdlKomponen. Hanya tampilan; simpan lewat
// KomponenCtrl.save(). Aturan nomor dicek ringan di sini untuk umpan balik cepat; aturan final di DB
// (trg_component_check).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let groups = [];
let isEdit = false;
let lastSuggest = null;   // saran nomor untuk kelompok yang sedang dipilih

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

function currentGroup() {
  return groups.find(g => g.code === $('group').value) || null;
}

function suggestionOf(g) {
  return g && g.next_no !== null && g.next_no !== undefined ? Number(g.next_no) : null;
}

function updateHint() {
  const g = currentGroup();
  const hint = $('numberHint');
  const btn = $('btnSuggest');
  hint.classList.remove('warn');
  btn.hidden = true;
  if (!g) {
    hint.textContent = 'Pilih kelompok dulu.';
    return;
  }
  const range = `Rentang ${g.range_start}–${g.range_end}, kelipatan 10.`;
  if (isEdit) {
    hint.textContent = range;
    return;
  }
  const s = suggestionOf(g);
  if (s === null) {
    hint.textContent = `${range} Rentang kelompok ini sudah penuh.`;
    hint.classList.add('warn');
    return;
  }
  hint.textContent = `${range} Saran nomor berikutnya: ${s}.`;
  btn.hidden = $('number').value === String(s);
}

// Tambah: saat kelompok diganti, nomor ikut saran baru — kecuali user sudah mengetik nomor sendiri
function onGroupChange() {
  const next = suggestionOf(currentGroup());
  if (!isEdit) {
    const typed = $('number').value;
    if (typed === '' || typed === String(lastSuggest)) {
      $('number').value = next === null ? '' : String(next);
    }
  }
  lastSuggest = next;
  $('group').classList.remove('invalid');
  updateHint();
}

// Isi ulang field hanya saat modal dibuka (key berubah) — busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  isEdit = m.mode === 'edit';
  groups = m.groups || [];
  $('title').textContent = isEdit ? 'Ubah Komponen' : (m.canManage ? 'Tambah Komponen' : 'Usulkan Komponen');
  fillSelect($('group'), groups.map(g => ({
    value: g.code,
    label: `${g.code} — ${g.name} (${g.range_start}–${g.range_end})`,
  })), f.group_code, '— Pilih kelompok —');
  lastSuggest = suggestionOf(currentGroup());
  $('number').value = f.number === null || f.number === undefined ? '' : String(f.number);
  $('name').value = f.name || '';
  fillSelect($('status'), m.statusOptions, f.status || 'APPROVED');
  $('statusBox').hidden = !isEdit;
  $('proposeInfo').hidden = isEdit || !!m.canManage;
  $('btnSave').dataset.label = !isEdit && !m.canManage ? 'Usulkan' : 'Simpan';
  ['group', 'number', 'name'].forEach(id => $(id).classList.remove('invalid'));
  updateHint();
  (isEdit ? $('name') : ($('group').value ? $('name') : $('group'))).focus();
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

function validate(g, numText, name) {
  if (!g) return ['group', 'Kelompok wajib dipilih.'];
  if (!/^\d+$/.test(numText)) return ['number', 'Nomor wajib diisi dengan angka bulat.'];
  const n = Number(numText);
  if (n % 10 !== 0) return ['number', 'Nomor komponen harus kelipatan 10.'];
  if (n < g.range_start || n > g.range_end) {
    return ['number', `Nomor harus berada di rentang ${g.range_start}–${g.range_end} untuk kelompok ${g.name}.`];
  }
  if (!name) return ['name', 'Nama komponen wajib diisi.'];
  return null;
}

function submit() {
  if (busy) return;
  const g = currentGroup();
  const numText = $('number').value.trim();
  const name = $('name').value.trim().replace(/\s+/g, ' ');
  ['group', 'number', 'name'].forEach(id => $(id).classList.remove('invalid'));
  const err = validate(g, numText, name);
  if (err) {
    $(err[0]).classList.add('invalid');
    $(err[0]).focus();
    showMessage({ type: 'error', text: err[1] });
    return;
  }
  appsmith.updateModel({
    group_code: g.code,
    number: Number(numText),
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
  $('group').addEventListener('change', onGroupChange);
  $('number').addEventListener('input', updateHint);
  $('btnSuggest').addEventListener('click', () => {
    if (lastSuggest !== null) $('number').value = String(lastSuggest);
    $('number').classList.remove('invalid');
    updateHint();
  });
  ['number', 'name'].forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
