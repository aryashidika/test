// cwRevisionForm - modal Buat Revisi di page Specsheet (mdlRevisi). Hanya tampilan; simpan lewat
// SpecCtrl.saveRevision() -> fn_revision_create. Pilihan cara mengikuti keadaan season:
//   belum ada revisi  -> EMPTY (kosong) / COPY (copy season lain model yang sama) /
//                        COPY_MODEL (R7: copy dari model lain, pabrik + kategori sama; ringkasan jumlah baris), + stage awal
//   ada revisi terbit -> NEXT_REVISION (stage sama, nomor + 1) / NEXT_STAGE (stage lebih tinggi r0; R14: boleh
//                        melompat, pilihan nextStages, default stage berikutnya)
// R14: pilihan stage dari model (kode + label): stages (revisi awal), nextStages (NEXT_STAGE).
// COPY_MODEL dikirim apa adanya; SpecCtrl.saveRevision() memanggil fn_revision_create mode COPY.
// Aturan final di DB (satu draft per season, sumber harus terbit; lintas model: pabrik & kategori sama).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let mode = '';
let options = [];
let M = {};

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

function buildOptions(m) {
  const sources = m.copySources || [];
  if (!m.hasRevisions) {
    return [
      { v: 'EMPTY', title: 'Start empty', desc: 'Empty BOM; all articles of this season are loaded.' },
      {
        v: 'COPY', title: 'Copy from another season (same model)',
        desc: sources.length ? 'Reuse the BOM of another season so you do not start from zero.'
          : 'No other season of this model has a published revision.',
        disabled: !sources.length,
      },
      {
        v: 'COPY_MODEL', title: 'Copy from another model (same factory & category)',
        desc: (m.modelSources || []).length
          ? 'For derived models (e.g. a different outsole). BOM lines of the source model are copied; colors are empty; the source model becomes the parent model.'
          : 'No other model with the same category has a published specsheet.',
        disabled: !(m.modelSources || []).length,
      },
    ];
  }
  if (m.latestLabel) {
    return [
      {
        v: 'NEXT_REVISION', title: `Next revision: ${m.nextRevisionLabel || ''}`,
        desc: `Copy ${m.latestLabel} (BOM lines, articles, colors), revision number + 1.`,
      },
      {
        v: 'NEXT_STAGE', title: m.nextStageLabel ? `Next stage: ${m.nextStageLabel}` : 'Next stage',
        desc: m.nextStageLabel ? `Copy ${m.latestLabel} to the selected stage.` : 'Already at the last stage (Production).',
        disabled: !m.nextStageLabel,
      },
    ];
  }
  return [];
}

function setMode(v) {
  mode = v;
  document.querySelectorAll('.opt').forEach(el => {
    const on = el.dataset.v === v;
    el.classList.toggle('on', on);
    el.setAttribute('aria-checked', on ? 'true' : 'false');
  });
  $('firstBox').hidden = !(v === 'EMPTY' || v === 'COPY' || v === 'COPY_MODEL');
  $('sourceBox').hidden = v !== 'COPY' && v !== 'COPY_MODEL';
  $('nextBox').hidden = v !== 'NEXT_STAGE';
  fillSources();
}

// Isi pilihan sumber sesuai mode: season lain model ini (COPY) atau specsheet model lain (COPY_MODEL)
function fillSources() {
  const cross = mode === 'COPY_MODEL';
  const list = cross ? (M.modelSources || []) : (M.copySources || []);
  const src = $('source');
  src.innerHTML = `<option value="">${cross ? 'Select model & season' : 'Select season'}</option>`;
  list.forEach(s => {
    const opt = document.createElement('option');
    opt.value = s.id;
    opt.textContent = cross ? s.label : `${s.season} · ${s.label} published`;
    src.appendChild(opt);
  });
  if (list.length === 1) src.value = list[0].id;
  src.classList.remove('invalid');
  $('sourceLabel').innerHTML = `${cross ? 'Source model & season' : 'Source season'} <span class="req">*</span>`;
  $('sourceHint').textContent = cross
    ? 'BOM lines of the latest published revision of the source model are copied (material, dimension, supplier). This season\'s articles are loaded with empty colors.'
    : 'BOM lines of the latest published revision of the source season are copied. This season\'s articles are loaded with empty colors.';
  showSummary();
}

function showSummary() {
  const s = mode === 'COPY_MODEL' ? (M.modelSources || []).find(x => x.id === $('source').value) : null;
  $('sourceSum').textContent = s ? s.summary : '';
  $('sourceSum').hidden = !s;
}

function fillForm(m) {
  M = m;
  $('title').textContent = `Create Revision: ${m.season || ''}`;
  options = buildOptions(m);
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
    b.querySelector('.desc').textContent = o.desc;
    b.addEventListener('click', () => setMode(o.v));
    box.appendChild(b);
  });
  fillSelect($('stage'), m.stages || [{ v: 'PULL', label: 'Pullover' }]);
  fillSelect($('nextStage'), m.nextStages || []);
  const first = options.find(o => !o.disabled);
  setMode(first ? first.v : '');
  $('note').hidden = options.length > 0;
  $('note').textContent = options.length ? '' : 'Publish or delete the current draft before creating a new revision.';
  $('btnSave').hidden = options.length === 0;
}

function fillSelect(sel, list) {
  sel.innerHTML = '';
  list.forEach(s => {
    const opt = document.createElement('option');
    opt.value = s.v;
    opt.textContent = s.label;
    sel.appendChild(opt);
  });
  if (list.length) sel.value = list[0].v;
}

function setBusy(v) {
  busy = v;
  $('btnSave').disabled = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Creating…' : 'Create';
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
  if (!mode) {
    showMessage({ type: 'error', text: 'Choose how to create the revision.' });
    return;
  }
  const copy = mode === 'COPY' || mode === 'COPY_MODEL';
  if (copy && !$('source').value) {
    $('source').classList.add('invalid');
    $('source').focus();
    showMessage({ type: 'error', text: mode === 'COPY' ? 'Select a source season.' : 'Select a source model & season.' });
    return;
  }
  $('source').classList.remove('invalid');
  const first = mode === 'EMPTY' || copy;
  appsmith.updateModel({
    mode,
    stage: first ? $('stage').value : mode === 'NEXT_STAGE' ? $('nextStage').value : '',
    source_specsheet_id: copy ? $('source').value : '',
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
  $('source').addEventListener('change', () => {
    $('source').classList.remove('invalid');
    showSummary();
  });
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
