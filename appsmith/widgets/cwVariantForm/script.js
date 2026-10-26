// cwVariantForm - form satu varian material: mdlVarian (Material Detail, MaterialDetailCtrl) & mdlVarianBaru (Specsheet,
// BomCtrl, dari Daftarkan di sel kuning). Hanya tampilan; simpan lewat saveVariant() -> fn_variant_save.
// R2b: satu baris seperti ERP (Material Code 10 karakter = 4 awalan material · 3 thickness · 3 warna, warna, thickness).
// R9 (keputusan user 12 Okt 2026) - "kamus kode" per pabrik, tiga tingkat:
//   TOLAK      : kode dobel · material + thickness + warna dobel - pesan dari DB.
//   KONFIRMASI : bagian kode sudah berarti lain (W01 = WHITE, diisi CREAM) - kotak merah + centang "Sudah saya cek,
//                kode ini benar sesuai ERP"; tanpa centang tidak bisa simpan (DB juga menolak tanpa p_confirm).
//   INFO       : warna / thickness sudah memakai kode lain, awalan beda dari varian lain material ini, kode bukan
//                10 karakter - kotak kuning, tetap bisa simpan.
// Isi otomatis dua arah (event onLookup):
//   - kode diketik (10 karakter) -> lookupKind 'code' -> model.hint (fn_variant_code_hint): warna / thickness yang
//     masih kosong diisi dari arti kodenya (tetap bisa diedit).
//   - warna + thickness diketahui (sel specsheet = model.fixed, atau diketik di form tambah) -> lookupKind 'suggest' ->
//     model.suggest (fn_variant_code_suggest): Material Code diisi USULAN (kode paling sering dipakai); bagian yang
//     belum diketahui dibiarkan kosong. Kode yang sudah diubah user tidak ditimpa lagi.
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let isEdit = false;
let fixed = null;                          // { color, thickness } dari specsheet (terkunci)
let hint = null;                           // arti bagian kode yang sedang diketik (model.hint)
let lookupTimer = null;
let lastLookup = null;
const autoField = { color: false, thickness: false };   // diisi dari arti kode (boleh ditimpa lagi)
let autoCode = null;                       // kode yang diisi usulan (null = diketik user)
let sug = null;                            // { key, p: [awalan], t: [kode thickness], c: [kode warna] }
let sugKey = '';                           // 'WARNA|THICKNESS' yang terakhir diminta
let sugTimer = null;
let sugSig = '';
let serverConflict = '';                   // pesan "Perlu konfirmasi" dari DB (bila form belum tahu)
let lastConflict = '';
let lastMsgText = '';

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
const tidyText = s => String(s || '').trim().replace(/\s+/g, ' ').toUpperCase();
// = fn_clean_thickness (R16, gaya berspasi tim material): huruf besar, kutip pintar / dua apostrof -> ", koma desimal -> titik,
// ".5" -> "0.5", nol belakang dibuang ("2.0" = "2"), INCH / IN setelah angka -> ", angka + satuan satu spasi ("1.2MM" -> "1.2 MM"),
// "X" antar ukuran berspasi ("44X69CM" -> "44 X 69 CM"), tanpa spasi di sekitar "-", spasi sebelum "(", rentang
// "1.4 MM-1.6 MM" -> "1.4-1.6 MM". Kosong / "." / "-" = tanpa thickness. Salinan sama di cwBomGrid.
function canonThickness(s) {
  let t = String(s ?? '').replace(/\s+/g, ' ').trim().toUpperCase();
  if (t === '' || t === '.' || t === '-') return '';
  t = t.replace(/[“”„‟″〃＂]/g, '"')
    .replace(/['’‘′`´]{2}/g, '"')
    .replace(/(\d),(\d)/g, '$1.$2')
    .replace(/(^|[^0-9.])\.(\d)/g, (m, a, b) => `${a}0.${b}`)
    .replace(/(\d)\.(\d*[1-9])0+(?![0-9])/g, '$1.$2')
    .replace(/(\d)\.0+(?![0-9])/g, '$1')
    .replace(/(\d)\s*(INCHES|INCH|IN)(?=$|\s*X|\s*\(|\s*-|[^A-Z0-9\s])/g, '$1"')
    .replace(/(\d)\s*(MM|CM|UM|ME)(?=$|[^A-Z]|X\d)/g, '$1 $2')
    .replace(/(\d|MM|CM|UM|")\s*X\s*(?=\d)/g, '$1 X ')
    .replace(/\s*-\s*/g, '-')
    .replace(/\s*\(\s*/g, ' (')
    .replace(/\s+\)/g, ')')
    .replace(/(\d)\s+"/g, '$1"')
    .replace(/(\d) (MM|CM|UM)-(\d+(?:\.\d+)?) \2(?=$|[^A-Z])/g, '$1-$3 $2')
    .replace(/\s+/g, ' ')
    .trim();
  return t;
}
const cleanThick = canonThickness;   // R16: thickness dibandingkan dalam bentuk baku ("44 \"" = '44"')
const thickLabel = s => cleanThick(s) || 'no dimension';
const parts = s => String(s || '').split(',').filter(x => x);
const el = (tag, cls, text) => Object.assign(document.createElement(tag), { className: cls || '', textContent: text || '' });

function setNote(field, text) {
  $(`${field}Note`).textContent = text;
  $(`${field}Note`).hidden = !text;
}

function fixedNote(field) {
  return field === 'color' ? 'From the specsheet cell.' : 'From the specsheet line.';
}

// ---- arah 1: kode -> warna / thickness ----
function clearAutoFields() {
  ['color', 'thickness'].forEach(field => {
    if (fixed) {
      setNote(field, fixedNote(field));
      return;
    }
    if (autoField[field]) {
      $(field).value = '';
      autoField[field] = false;
    }
    setNote(field, '');
  });
}

function applyHint(h) {
  const code = cleanCode($('code').value);
  if (!h || h.code !== code) return;
  hint = h;
  const part = { thickness: code.substr(4, 3), color: code.substr(7, 3) };
  [['thickness', h.thickness_known, h.thickness, h.thickness_ref],
   ['color', h.color_known, h.color, h.color_ref]].forEach(([field, known, value, ref]) => {
    const shown = field === 'thickness' ? thickLabel(value) : (value || '');
    if (fixed) {
      setNote(field, known ? `${fixedNote(field)} Code ${part[field]} is recorded as ${shown} (${ref}).` : fixedNote(field));
      return;
    }
    if (known) {
      if (!tidyText($(field).value) || autoField[field]) {
        $(field).value = value || '';
        autoField[field] = true;
        $(field).classList.remove('invalid');
      }
      setNote(field, `Code ${part[field]} = ${shown} (recorded in ${ref}).`);
    } else {
      setNote(field, `${field === 'thickness' ? 'Dimension' : 'Color'} code ${part[field]} is new. It fills in automatically next time.`);
    }
  });
  updateChecks();
}

function onCodeInput() {
  clearTimeout(lookupTimer);
  const code = cleanCode($('code').value);
  if (code !== autoCode) autoCode = null;  // diketik user: usulan tidak menimpa lagi
  serverConflict = '';
  if (code.length !== 10) {
    hint = null;
    lastLookup = null;
    clearAutoFields();
    updateChecks();
    return;
  }
  updateChecks();
  lookupTimer = setTimeout(() => {
    if (code === lastLookup) return;
    lastLookup = code;
    appsmith.updateModel({ lookupKind: 'code', lookupCode: code });
    appsmith.triggerEvent('onLookup');
  }, 300);
}

// ---- arah 2: warna + thickness -> usulan kode ----
function requestSuggest(now) {
  if (isEdit) return;
  const color = tidyText($('color').value);
  const thickness = cleanThick($('thickness').value);
  clearTimeout(sugTimer);
  if (!color) {
    sug = null;
    sugKey = '';
    renderSuggest();
    updateChecks();
    return;
  }
  const key = `${color}|${thickness}`;
  sugTimer = setTimeout(() => {
    if (key === sugKey) return;
    sugKey = key;
    appsmith.updateModel({ lookupKind: 'suggest', suggestColor: color, suggestThickness: thickness });
    appsmith.triggerEvent('onLookup');
  }, now ? 0 : 400);
}

function applySuggest(s) {
  if (!s || isEdit || s.for !== sugKey) return;
  const sig = JSON.stringify(s);
  if (sig === sugSig) return;              // model yang sama dikirim ulang Appsmith
  sugSig = sig;
  sug = { key: s.for, p: parts(s.prefixes), t: parts(s.thickness_codes), c: parts(s.color_codes) };
  const cur = cleanCode($('code').value);
  if (!cur || cur === autoCode) {
    // kode paling sering dipakai; berhenti di bagian pertama yang belum diketahui (posisi kode tetap)
    const code = sug.p[0] ? sug.p[0] + (sug.t[0] ? sug.t[0] + (sug.c[0] || '') : '') : '';
    $('code').value = code;
    autoCode = code;
    hint = null;
    lastLookup = code;                     // usulan sendiri tidak perlu dicari artinya
    $('code').classList.remove('invalid');
    if (fixed) {
      const n = code.length;
      $('code').focus();
      try { $('code').setSelectionRange(n, n); } catch (e) { /* abaikan */ }
    }
  }
  renderSuggest();
  updateChecks();
}

function renderSuggest() {
  const box = $('sugBox');
  box.innerHTML = '';
  if (!sug || isEdit) {
    box.hidden = true;
    return;
  }
  box.appendChild(el('div', '', 'Suggested from recorded codes. Check against ERP before saving:'));
  [['p', 'Material prefix', 'no other variants in this material yet. Type 4 characters'],
   ['t', 'Dimension', 'never used yet. Type 3 characters'],
   ['c', 'Color', 'new color. Type the last 3 characters']].forEach(([k, label, none]) => {
    const row = el('div', 'sug-row');
    row.appendChild(el('span', 'sug-label', `${label}:`));
    const list = sug[k];
    if (!list.length) {
      row.appendChild(el('span', 'sug-none', none));
    } else {
      row.appendChild(el('span', 'sug-code', list[0]));
      if (list.length > 1) row.appendChild(el('span', 'sug-other', `(other codes: ${list.slice(1).join(', ')})`));
    }
    box.appendChild(row);
  });
  box.hidden = false;
}

// ---- tiga tingkat: konfirmasi (merah) & info (kuning) ----
function conflicts() {
  const code = cleanCode($('code').value);
  const out = [];
  if (hint && hint.code === code && code.length === 10) {
    const color = tidyText($('color').value);
    const thick = cleanThick($('thickness').value);
    if (hint.thickness_known && cleanThick(hint.thickness) !== thick) {
      out.push(`Dimension code ${code.substr(4, 3)} is already recorded as ${thickLabel(hint.thickness)} (code ${hint.thickness_ref}), not ${thickLabel(thick)}.`);
    }
    if (hint.color_known && color && tidyText(hint.color) !== color) {
      out.push(`Color code ${code.substr(7, 3)} is already recorded as ${hint.color} (code ${hint.color_ref}), not ${color}.`);
    }
  }
  if (!out.length && serverConflict) out.push(serverConflict);
  return out;
}

function infos() {
  const code = cleanCode($('code').value);
  const out = [];
  if (code && code.length !== 10 && code !== autoCode) out.push(`ERP Material Codes are usually 10 characters (now ${code.length}).`);
  if (hint && hint.code === code && hint.other_prefixes) {
    out.push(`Prefix ${code.substr(0, 4)} differs from other variants of this material (${hint.other_prefixes}).`);
  }
  const key = `${tidyText($('color').value)}|${cleanThick($('thickness').value)}`;
  if (sug && sug.key === key && code.length === 10) {
    if (sug.t.length && !sug.t.includes(code.substr(4, 3))) {
      out.push(`Dimension ${thickLabel($('thickness').value)} usually has code ${sug.t.join(' / ')}. Make sure ${code.substr(4, 3)} matches ERP.`);
    }
    if (sug.c.length && !sug.c.includes(code.substr(7, 3))) {
      out.push(`Color ${tidyText($('color').value)} usually has code ${sug.c.join(' / ')}. Make sure ${code.substr(7, 3)} matches ERP.`);
    }
    if (sug.p.length && !sug.p.includes(code.substr(0, 4)) && !(hint && hint.code === code)) {
      out.push(`Prefix ${code.substr(0, 4)} differs from other variants of this material (${sug.p.join(', ')}).`);
    }
  }
  return out;
}

function updateChecks() {
  const c = conflicts();
  const text = c.join(' ');
  if (text !== lastConflict) {             // isi konflik berubah -> konfirmasi harus diulang
    lastConflict = text;
    $('confChk').checked = false;
  }
  $('confText').textContent = text ? `${text} Check the Material Code in ERP.` : '';
  $('confBox').hidden = !text;
  const i = infos();
  $('infoBox').innerHTML = '';
  i.forEach(t => $('infoBox').appendChild(el('div', '', t)));
  $('infoBox').hidden = !i.length;
}

// ---- form ----
// Isi ulang field hanya saat modal dibuka / setelah "Simpan & tambah lagi" (key berubah)
function fillForm(m) {
  const f = m.form || {};
  isEdit = m.mode === 'edit';
  fixed = m.fixed || null;
  hint = null;
  sug = null;
  sugKey = '';
  sugSig = '';
  autoCode = null;
  serverConflict = '';
  lastConflict = '';
  autoField.color = false;
  autoField.thickness = false;
  $('title').textContent = isEdit ? 'Edit Variant' : 'Add Variant';
  $('materialLabel').textContent = m.materialLabel || '';
  ['code', 'color', 'thickness'].forEach(id => {
    $(id).value = f[id] || '';
    $(id).disabled = !!fixed && id !== 'code';
    $(id).classList.remove('invalid');
  });
  setNote('color', fixed ? fixedNote('color') : '');
  setNote('thickness', fixed ? fixedNote('thickness') : '');
  $('confChk').checked = false;
  fillSelect($('status'), m.statusOptions, f.status || 'ACTIVE');
  $('statusBox').hidden = !isEdit;
  $('btnAgain').hidden = isEdit || !!fixed;
  lastLookup = null;
  $('code').focus();
  if (isEdit) onCodeInput();
  renderSuggest();
  updateChecks();
  if (!isEdit && fixed) requestSuggest(true);          // sel kuning specsheet: warna & thickness sudah diketahui
}

function setBusy(v) {
  busy = v;
  ['btnSave', 'btnAgain', 'btnCancel', 'btnX', 'confChk'].forEach(id => { $(id).disabled = v; });
  $('btnSave').textContent = v ? 'Saving…' : 'Save';
}

function render(model) {
  const m = model || {};
  if (m.key !== lastKey) {
    lastKey = m.key;
    fillForm(m);
  }
  // DB menolak dengan "Confirmation needed" (form belum sempat tahu): tampilkan di kotak konfirmasi.
  // R16 (review): sejak R15 pesan DB berbahasa Inggris; pola lama "Perlu konfirmasi" tidak pernah cocok lagi.
  const t = (m.message && m.message.text) || '';
  if (t !== lastMsgText) {                 // pesan baru saja (model dikirim ulang tidak memasang lagi)
    lastMsgText = t;
    if (/^Confirmation needed:/.test(t)) {
      const x = t.replace(/^Confirmation needed:\s*/, '').replace(/\s*Check the Material Code;.*$/, '');
      serverConflict = x.charAt(0).toUpperCase() + x.slice(1);
    }
  }
  if (/^Confirmation needed:/.test(t)) {
    showMessage(null);
  } else {
    showMessage(m.message);
  }
  setBusy(!!m.busy);
  applyHint(m.hint);
  applySuggest(m.suggest);
  updateChecks();
}

function submit(again) {
  if (busy) return;
  const code = cleanCode($('code').value);
  const color = tidyText($('color').value);
  const thickness = tidyText($('thickness').value);
  ['code', 'color'].forEach(id => $(id).classList.remove('invalid'));
  if (!code || !color) {
    $(code ? 'color' : 'code').classList.add('invalid');
    $(code ? 'color' : 'code').focus();
    showMessage({ type: 'error', text: 'Material Code and color are required.' });
    return;
  }
  const needConfirm = conflicts().length > 0;
  if (needConfirm && !$('confChk').checked) {
    $('code').classList.add('invalid');
    showMessage({ type: 'error', text: 'The Material Code conflicts with recorded codes. Check the code, or tick the confirmation if it matches ERP.' });
    return;
  }
  appsmith.updateModel({ code, color, thickness, status: $('status').value, again: !!again, confirm: needConfirm });
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
  ['color', 'thickness'].forEach(id => $(id).addEventListener('input', () => {
    autoField[id] = false;                 // diketik user
    serverConflict = '';
    $(id).classList.remove('invalid');
    updateChecks();
    requestSuggest(false);
  }));
  $('confChk').addEventListener('change', () => $('code').classList.remove('invalid'));
  ['code', 'color', 'thickness'].forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit(!isEdit);
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
