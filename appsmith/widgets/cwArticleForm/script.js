// cwArticleForm - form Tambah / Ubah Article di mdlArticle (page Model Detail). Hanya tampilan; simpan lewat
// ModelDetailCtrl.saveArticle(). Kode dikunci kalau article sudah dipakai (codeLocked).
// R19: nomor artikel boleh kosong (diisi belakangan, juga setelah article dipakai); wajib untuk terbit Production.
// R19 (27 Okt 2026): nomor boleh dikoreksi sampai article ada di Production terbit (codeLocked dari q_articles.code_locked).
// Aturan final di DB (trg_article_check: kode unik per season, kode terpakai terkunci; tanpa batas jumlah sejak R8).
const $ = id => document.getElementById(id);
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
  if (!m || !m.text) {
    box.hidden = true;
    box.textContent = '';
    return;
  }
  box.className = `msg ${m.type || 'info'}`;
  box.textContent = m.text;
  box.hidden = false;
}

// Isi ulang field hanya saat modal dibuka (key berubah) - busy/message tidak menghapus ketikan user
function fillForm(m) {
  const f = m.form || {};
  const isEdit = m.mode === 'edit';
  $('title').textContent = isEdit ? 'Edit Article' : 'Add Article';
  $('code').value = f.code || '';
  $('colorway').value = f.colorway || '';
  $('code').disabled = !!m.codeLocked;
  $('codeNote').hidden = !m.codeLocked;
  $('codeHint').hidden = !!m.codeLocked;
  ['code', 'colorway'].forEach(id => $(id).classList.remove('invalid'));
  $('seasonInfo').textContent = isEdit
    ? `Season ${m.season || '-'}`
    : `Season ${m.season || '-'} · article no. ${(m.count || 0) + 1}`;
  (isEdit ? $('colorway') : $('code')).focus();
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
}

function clean(id) {
  return $(id).value.trim().replace(/\s+/g, ' ');
}

function submit() {
  if (busy) return;
  const data = { code: clean('code'), colorway: clean('colorway') };
  ['code', 'colorway'].forEach(id => $(id).classList.remove('invalid'));
  const missing = [['colorway', 'Colorway']].find(([id]) => !data[id]);
  if (missing) {
    $(missing[0]).classList.add('invalid');
    $(missing[0]).focus();
    showMessage({ type: 'error', text: `${missing[1]} is required.` });
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
  ['code', 'colorway'].forEach(id => $(id).addEventListener('keydown', e => {
    if (e.key === 'Enter') submit();
  }));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
