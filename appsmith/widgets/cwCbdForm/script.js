// cwCbdForm — modal Buat CBD di page Cost Breakdown (CBD) (mdlCbdBaru). Hanya tampilan; pilihan cara & sumber
// disusun CbdCtrl.createFormModel(), simpan lewat CbdCtrl.saveCreate() -> fn_cbd_create.
//   article belum punya CBD -> NEW (dari specsheet) / COPY (dari CBD terbit article lain model sama)
//   article sudah punya CBD terbit -> NEXT (revisi berikutnya)
// Aturan final di DB (satu draft per article, article ACTIVE di specsheet terbit, sumber model sama).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let mode = '';
let options = [];

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

function current() {
  return options.find(o => o.v === mode) || null;
}

function setMode(v) {
  mode = v;
  document.querySelectorAll('.opt').forEach(el => {
    const on = el.dataset.v === v;
    el.classList.toggle('on', on);
    el.setAttribute('aria-checked', on ? 'true' : 'false');
  });
  const o = current();
  $('sourceBox').hidden = !(o && o.needsSource);
}

function fillForm(m) {
  $('title').textContent = m.title || 'Buat CBD';
  options = m.options || [];
  const box = $('opts');
  box.innerHTML = '';
  options.forEach(o => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'opt';
    b.dataset.v = o.v;
    b.disabled = !!o.disabled;
    b.setAttribute('role', 'radio');
    b.innerHTML = '<span class="dot"></span><span class="txt"><strong></strong><span class="desc"></span></span>';
    b.querySelector('strong').textContent = o.title;
    b.querySelector('.desc').textContent = o.desc || '';
    b.addEventListener('click', () => setMode(o.v));
    box.appendChild(b);
  });
  const src = $('source');
  src.innerHTML = '<option value="">— pilih article —</option>';
  (m.sources || []).forEach(s => {
    const opt = document.createElement('option');
    opt.value = s.id;
    opt.textContent = s.label;
    src.appendChild(opt);
  });
  if ((m.sources || []).length === 1) src.value = m.sources[0].id;
  src.classList.remove('invalid');
  const first = options.find(o => !o.disabled);
  setMode(first ? first.v : '');
  const note = options.length ? (m.note || '') : (m.emptyText || '');
  $('note').textContent = note;
  $('note').hidden = !note;
  $('btnSave').hidden = options.length === 0;
}

function setBusy(v) {
  busy = v;
  $('btnSave').disabled = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Membuat…' : 'Buat';
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
  const o = current();
  if (!o) {
    showMessage({ type: 'error', text: 'Pilih cara membuat CBD.' });
    return;
  }
  if (o.needsSource && !$('source').value) {
    $('source').classList.add('invalid');
    $('source').focus();
    showMessage({ type: 'error', text: 'Pilih article sumber.' });
    return;
  }
  $('source').classList.remove('invalid');
  appsmith.updateModel({ mode, source_article_id: o.needsSource ? $('source').value : '' });
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  $('source').addEventListener('change', () => $('source').classList.remove('invalid'));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
