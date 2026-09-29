// cwSeasonForm — form Season Baru di mdlSeason (page Model Detail). Hanya tampilan; simpan lewat
// ModelDetailCtrl.saveSeason(). Season = SS/FH + 2 digit tahun (SS26, FH26). Aturan final di DB
// (trg_specsheet_check: format & season yang sama untuk model ini ditolak).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let half = '';
let existing = [];

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

function season() {
  const y = $('year').value.trim();
  return half && /^\d{2}$/.test(y) ? half + y : '';
}

function updatePreview() {
  const s = season();
  const box = $('preview');
  if (!s) {
    box.textContent = 'Pilih musim dan isi 2 digit tahun.';
  } else if (existing.includes(s)) {
    box.textContent = `${s} sudah ada untuk model ini.`;
  } else {
    box.textContent = `${s} · ${half === 'SS' ? 'Spring/Summer' : 'Fall/Holiday'} 20${s.slice(2)}`;
  }
}

function setHalf(v) {
  half = v === 'FH' ? 'FH' : (v === 'SS' ? 'SS' : '');
  document.querySelectorAll('#half button').forEach(b => b.classList.toggle('on', b.dataset.v === half));
  $('half').classList.remove('invalid');
  updatePreview();
}

// Isi ulang hanya saat modal dibuka (key berubah). Awal: musim & tahun berjalan (Jan–Jun = SS).
function fillForm(m) {
  existing = (m.existing || []).map(s => String(s).toUpperCase());
  const now = new Date();
  setHalf(now.getMonth() < 6 ? 'SS' : 'FH');
  $('year').value = String(now.getFullYear()).slice(2);
  $('year').classList.remove('invalid');
  $('existing').textContent = existing.length ? `Season yang sudah ada: ${existing.join(', ')}` : 'Belum ada season untuk model ini.';
  updatePreview();
  $('year').focus();
  $('year').select();
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
  if (!half) {
    $('half').classList.add('invalid');
    showMessage({ type: 'error', text: 'Pilih musim SS atau FH.' });
    return;
  }
  const s = season();
  if (!s) {
    $('year').classList.add('invalid');
    $('year').focus();
    showMessage({ type: 'error', text: 'Tahun harus 2 digit angka, mis. 26.' });
    return;
  }
  if (existing.includes(s)) {
    $('year').classList.add('invalid');
    showMessage({ type: 'error', text: `Season ${s} sudah ada untuk model ini.` });
    return;
  }
  $('year').classList.remove('invalid');
  appsmith.updateModel({ season: s });
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  document.querySelectorAll('#half button').forEach(b => b.addEventListener('click', () => setHalf(b.dataset.v)));
  $('year').addEventListener('input', () => {
    $('year').value = $('year').value.replace(/\D/g, '').slice(0, 2);
    $('year').classList.remove('invalid');
    updatePreview();
  });
  $('year').addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  });
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
