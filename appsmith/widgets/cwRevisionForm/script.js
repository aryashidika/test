// cwRevisionForm — modal Buat Revisi di page Specsheet (mdlRevisi). Hanya tampilan; simpan lewat
// SpecCtrl.saveRevision() -> fn_revision_create. Pilihan cara mengikuti keadaan season:
//   belum ada revisi  -> EMPTY (kosong) / COPY (copy season lain model yang sama) /
//                        COPY_MODEL (R7: copy dari model lain, pabrik + kategori sama; ringkasan jumlah baris), + stage awal
//   ada revisi terbit -> NEXT_REVISION (stage sama, nomor + 1) / NEXT_STAGE (stage berikutnya r0)
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
      { v: 'EMPTY', title: 'Mulai kosong', desc: 'BOM kosong; semua article season ini langsung dimuat.' },
      {
        v: 'COPY', title: 'Copy dari season lain (model sama)',
        desc: sources.length ? 'Ambil struktur BOM specsheet season lain supaya tidak mulai dari 0.'
          : 'Belum ada season lain model ini yang punya revisi terbit.',
        disabled: !sources.length,
      },
      {
        v: 'COPY_MODEL', title: 'Copy dari model lain (pabrik & kategori sama)',
        desc: (m.modelSources || []).length
          ? 'Untuk model turunan (mis. beda outsole). Baris BOM model sumber di-copy; warna kosong; model sumber jadi model induk.'
          : 'Belum ada model lain dengan kategori sama yang punya specsheet terbit.',
        disabled: !(m.modelSources || []).length,
      },
    ];
  }
  if (m.latestLabel) {
    return [
      {
        v: 'NEXT_REVISION', title: `Revisi berikutnya: ${m.nextRevisionLabel || ''}`,
        desc: `Salin ${m.latestLabel} (baris BOM, article, warna), nomor revisi + 1.`,
      },
      {
        v: 'NEXT_STAGE', title: m.nextStageLabel ? `Stage berikutnya: ${m.nextStageLabel}` : 'Stage berikutnya',
        desc: m.nextStageLabel ? `Salin ${m.latestLabel} ke stage berikutnya.` : 'Sudah di stage terakhir (PROD).',
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
  fillSources();
}

// Isi pilihan sumber sesuai mode: season lain model ini (COPY) atau specsheet model lain (COPY_MODEL)
function fillSources() {
  const cross = mode === 'COPY_MODEL';
  const list = cross ? (M.modelSources || []) : (M.copySources || []);
  const src = $('source');
  src.innerHTML = `<option value="">${cross ? '— pilih model & season —' : '— pilih season —'}</option>`;
  list.forEach(s => {
    const opt = document.createElement('option');
    opt.value = s.id;
    opt.textContent = cross ? s.label : `${s.season} — ${s.label} terbit`;
    src.appendChild(opt);
  });
  if (list.length === 1) src.value = list[0].id;
  src.classList.remove('invalid');
  $('sourceLabel').innerHTML = `${cross ? 'Model & season sumber' : 'Season sumber'} <span class="req">*</span>`;
  $('sourceHint').textContent = cross
    ? 'Baris BOM revisi terbit terakhir model sumber di-copy (material, thickness, supplier). Article season ini dimuat dengan warna kosong.'
    : 'Baris BOM revisi terbit terakhir season sumber di-copy. Article season ini dimuat dengan warna kosong.';
  showSummary();
}

function showSummary() {
  const s = mode === 'COPY_MODEL' ? (M.modelSources || []).find(x => x.id === $('source').value) : null;
  $('sourceSum').textContent = s ? s.summary : '';
  $('sourceSum').hidden = !s;
}

function fillForm(m) {
  M = m;
  $('title').textContent = `Buat Revisi — ${m.season || ''}`;
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
  $('stage').value = 'PULL';
  const first = options.find(o => !o.disabled);
  setMode(first ? first.v : '');
  $('note').hidden = options.length > 0;
  $('note').textContent = options.length ? '' : 'Terbitkan atau hapus draft yang ada dulu sebelum membuat revisi baru.';
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
  if (!mode) {
    showMessage({ type: 'error', text: 'Pilih cara membuat revisi.' });
    return;
  }
  const copy = mode === 'COPY' || mode === 'COPY_MODEL';
  if (copy && !$('source').value) {
    $('source').classList.add('invalid');
    $('source').focus();
    showMessage({ type: 'error', text: mode === 'COPY' ? 'Pilih season sumber.' : 'Pilih model & season sumber.' });
    return;
  }
  $('source').classList.remove('invalid');
  const first = mode === 'EMPTY' || copy;
  appsmith.updateModel({
    mode,
    stage: first ? $('stage').value : '',
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
