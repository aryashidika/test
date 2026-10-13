// cwCbdForm — modal Buat CBD di page Cost Breakdown (CBD) (mdlCbdBaru). Hanya tampilan; pilihan cara & sumber
// disusun CbdCtrl.createFormModel(), simpan lewat CbdCtrl.saveCreate() -> fn_cbd_create.
//   article belum punya CBD -> NEW (dari specsheet) / COPY (dari CBD terbit article lain model sama)
//   article sudah punya CBD terbit -> NEXT (revisi berikutnya)
// R13: stage dipilih (stages dari fn_cbd_stage_options); {spec} / {next} di judul, keterangan & catatan diganti
// dengan specsheet acuan / nomor revisi CBD stage terpilih.
// Aturan final di DB (satu draft per article, article ACTIVE di specsheet terbit, sumber model sama).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let mode = '';
let options = [];
let stages = [];
let stage = '';
let noteTpl = '';

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

function curStage() {
  return stages.find(s => s.v === stage) || null;
}

function fill(t) {
  const s = curStage();
  return String(t || '').replace(/\{spec\}/g, s ? s.spec : '').replace(/\{next\}/g, s ? s.next : '');
}

function renderTexts() {
  document.querySelectorAll('.opt').forEach(el => {
    const o = options.find(x => x.v === el.dataset.v);
    if (!o) return;
    el.querySelector('strong').textContent = fill(o.title);
    el.querySelector('.desc').textContent = fill(o.desc);
  });
  if (options.length) {
    const note = fill(noteTpl);
    $('note').textContent = note;
    $('note').hidden = !note;
  }
}

function setStage(v) {
  stage = v;
  document.querySelectorAll('#stages button').forEach(el => {
    const on = el.dataset.v === v;
    el.classList.toggle('on', on);
    el.setAttribute('aria-checked', on ? 'true' : 'false');
  });
  const off = stages.filter(s => s.disabled && s.note).map(s => `${s.label || s.v}: ${s.note}`);
  $('stageHint').textContent = off.join(' · ');
  $('stageHint').hidden = !off.length;
  renderTexts();
}

function fillStages(list) {
  stages = list || [];
  const box = $('stages');
  box.innerHTML = '';
  stages.forEach(s => {
    const b = document.createElement('button');
    b.type = 'button';
    b.dataset.v = s.v;
    b.disabled = !!s.disabled;
    b.setAttribute('role', 'radio');
    b.textContent = s.label || s.v;
    b.title = s.disabled ? (s.note || '') : `${s.next} · acuan specsheet ${s.spec}`;
    b.addEventListener('click', () => setStage(s.v));
    box.appendChild(b);
  });
  $('stageBox').hidden = !stages.length || !options.length;
  const def = stages.find(s => s.isDefault && !s.disabled) || stages.find(s => !s.disabled);
  setStage(def ? def.v : '');
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
    b.querySelector('strong').textContent = fill(o.title);
    b.querySelector('.desc').textContent = fill(o.desc);
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
  noteTpl = m.note || '';
  const note = options.length ? '' : (m.emptyText || '');
  $('note').textContent = note;
  $('note').hidden = !note;
  $('btnSave').hidden = options.length === 0;
  fillStages(m.stages);
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
  if (stages.length && !curStage()) {
    showMessage({ type: 'error', text: 'Pilih stage CBD.' });
    return;
  }
  $('source').classList.remove('invalid');
  appsmith.updateModel({ mode, source_article_id: o.needsSource ? $('source').value : '', stage });
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
