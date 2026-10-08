// cwVariantForm — form satu varian material di mdlVarian (page Material Detail). Hanya tampilan; simpan lewat
// MaterialDetailCtrl.saveVariant() -> fn_variant_save. R2b (keputusan user 8 Okt 2026): satu baris seperti ERP
// (Material Code, warna, thickness teks). Saat kode 10 karakter diketik, event onLookup -> fn_variant_code_hint:
// 3 tengah / 3 akhir yang sudah tercatat mengisi & mengunci thickness / warna; awalan beda = peringatan saja.
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let isEdit = false;
let lookupTimer = null;
let lastLookup = null;
const locked = { color: false, thickness: false };

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

const cleanCode = s => String(s || '').trim().replace(/\s+/g, ' ').toUpperCase();

// ---- isi otomatis dari bagian kode ----
function unlock(field) {
  if (locked[field]) {
    $(field).value = '';
    locked[field] = false;
  }
  $(field).disabled = false;
  $(`${field}Note`).hidden = true;
}

function setNote(field, text) {
  $(`${field}Note`).textContent = text;
  $(`${field}Note`).hidden = !text;
}

function applyHint(h) {
  const code = cleanCode($('code').value);
  if (!h || h.code !== code) return;
  const part = { thickness: code.substr(4, 3), color: code.substr(7, 3) };
  [['thickness', h.thickness_known, h.thickness, h.thickness_ref],
   ['color', h.color_known, h.color, h.color_ref]].forEach(([field, known, value, ref]) => {
    if (known) {
      $(field).value = value || '';
      $(field).disabled = true;
      $(field).classList.remove('invalid');
      locked[field] = true;
      const shown = value || (field === 'thickness' ? 'tanpa thickness' : '');
      setNote(field, `Kode ${part[field]} = ${shown} (sudah tercatat di ${ref}).`);
    } else {
      unlock(field);
      setNote(field, `Kode ${field === 'thickness' ? 'thickness' : 'warna'} ${part[field]} baru — isi sekali, berikutnya terisi otomatis.`);
    }
  });
  const others = h.other_prefixes || '';
  $('prefixWarn').textContent = others
    ? `Awalan ${code.substr(0, 4)} berbeda dari varian lain di material ini (${others}). Periksa kembali — tetap bisa disimpan.`
    : '';
  $('prefixWarn').hidden = !others;
}

function onCodeInput() {
  clearTimeout(lookupTimer);
  const code = cleanCode($('code').value);
  if (code.length !== 10) {
    unlock('thickness');
    unlock('color');
    $('prefixWarn').hidden = true;
    lastLookup = null;
    return;
  }
  lookupTimer = setTimeout(() => {
    if (code === lastLookup) return;
    lastLookup = code;
    appsmith.updateModel({ lookupCode: code });
    appsmith.triggerEvent('onLookup');
  }, 300);
}

// Isi ulang field hanya saat modal dibuka / setelah "Simpan & tambah lagi" (key berubah)
function fillForm(m) {
  const f = m.form || {};
  isEdit = m.mode === 'edit';
  $('title').textContent = isEdit ? 'Ubah Varian' : 'Tambah Varian';
  $('materialLabel').textContent = m.materialLabel || '';
  locked.color = false;
  locked.thickness = false;
  ['code', 'color', 'thickness'].forEach(id => {
    $(id).value = f[id] || '';
    $(id).disabled = false;
    $(id).classList.remove('invalid');
  });
  setNote('color', '');
  setNote('thickness', '');
  $('prefixWarn').hidden = true;
  fillSelect($('status'), m.statusOptions, f.status || 'ACTIVE');
  $('statusBox').hidden = !isEdit;
  $('btnAgain').hidden = isEdit;
  lastLookup = null;
  $('code').focus();
  if (isEdit) onCodeInput();
}

function setBusy(v) {
  busy = v;
  ['btnSave', 'btnAgain', 'btnCancel', 'btnX'].forEach(id => { $(id).disabled = v; });
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
  applyHint(m.hint);
}

function submit(again) {
  if (busy) return;
  const code = cleanCode($('code').value);
  const color = $('color').value.trim().replace(/\s+/g, ' ').toUpperCase();
  const thickness = $('thickness').value.trim().replace(/\s+/g, ' ').toUpperCase();
  ['code', 'color'].forEach(id => $(id).classList.remove('invalid'));
  if (!code || !color) {
    $(code ? 'color' : 'code').classList.add('invalid');
    $(code ? 'color' : 'code').focus();
    showMessage({ type: 'error', text: 'Material Code dan warna wajib diisi.' });
    return;
  }
  appsmith.updateModel({ code, color, thickness, status: $('status').value, again: !!again });
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', () => submit(false));
  $('btnAgain').addEventListener('click', () => submit(true));
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  $('code').addEventListener('input', onCodeInput);
  ['code', 'color', 'thickness'].forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit(!isEdit);
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
