// cwStepper: stepper stage Pullover → Preview → SMS → GTM → Production berisi chip revisi (r0, r1, …). Hanya tampilan.
// Klik chip -> model.selectedId + event onSelect (SpecCtrl / CbdCtrl .selectRevision()).
// Chip DRAFT kuning bergaris putus; chip terpilih terisi; chip needsRevision bergaris merah (CBD).
// Brand hanya menerima revisi PUBLISHED dari query.
// Opsional (page CBD): baris chip article di atas stepper (model.articles) -> model.selectedArticleId + event onArticle.
const $ = id => document.getElementById(id);
// R14: kode di DB tetap pendek; label sama dengan Util.stageLabel / fn_stage_label
const STAGES = ['PULL', 'PREV', 'SMS', 'GTM', 'PROD'];
const LABELS = { PULL: 'Pullover', PREV: 'Preview', PROD: 'Production' };
const stageLabel = s => LABELS[s] || s;

function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}

function renderArticles(m) {
  const box = $('arts');
  box.innerHTML = '';
  if (!Array.isArray(m.articles)) {
    box.hidden = true;
    return;
  }
  box.hidden = false;
  if (!m.articles.length) {
    const none = document.createElement('span');
    none.className = 'none';
    none.textContent = m.articleEmptyText || '';
    box.appendChild(none);
    return;
  }
  m.articles.forEach(a => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'art' + (a.id === m.selectedArticleId ? ' active' : '');
    b.title = a.colorway || '';
    b.setAttribute('aria-pressed', a.id === m.selectedArticleId ? 'true' : 'false');
    const code = document.createElement('strong');
    code.textContent = a.code;
    b.appendChild(code);
    if (a.badge) {
      const badge = document.createElement('span');
      badge.className = `badge ${a.tone || 'muted'}`;
      badge.textContent = a.badge;
      b.appendChild(badge);
    }
    b.addEventListener('click', () => {
      if (a.id === m.selectedArticleId) return;
      appsmith.updateModel({ selectedArticleId: a.id });
      appsmith.triggerEvent('onArticle');
    });
    box.appendChild(b);
  });
}

function render(model) {
  const m = model || {};
  renderArticles(m);
  const revs = m.revisions || [];
  const selected = m.selectedId || '';
  const current = (revs.find(r => r.id === selected) || {}).stage;
  const list = $('steps');
  list.innerHTML = '';
  $('empty').hidden = true;
  if (!revs.length && (m.emptyText || Array.isArray(m.articles))) {
    $('empty').textContent = m.emptyText || '';
    $('empty').hidden = !m.emptyText;
    list.hidden = true;
    return;
  }
  list.hidden = false;
  STAGES.forEach(stage => {
    const inStage = revs.filter(r => r.stage === stage).sort((a, b) => a.revision_no - b.revision_no);
    const li = document.createElement('li');
    li.className = 'step' + (inStage.length ? ' has-revs' : '') + (stage === current ? ' current' : '');
    const name = document.createElement('span');
    name.className = 'stage';
    name.textContent = stageLabel(stage);
    const chips = document.createElement('div');
    chips.className = 'chips';
    if (!inStage.length) {
      const none = document.createElement('span');
      none.className = 'none';
      none.textContent = '–';
      chips.appendChild(none);
    }
    inStage.forEach(r => {
      const b = document.createElement('button');
      b.type = 'button';
      b.className = 'chip' + (r.status === 'DRAFT' ? ' draft' : '') + (r.needsRevision ? ' needs' : '')
        + (r.id === selected ? ' active' : '');
      b.textContent = `r${r.revision_no}`;
      b.title = `${stageLabel(r.stage)} r${r.revision_no} · ${r.status === 'DRAFT' ? 'DRAFT (belum terbit)' : 'PUBLISHED'}`
        + (r.needsRevision ? ' · perlu revisi' : '');
      b.setAttribute('aria-pressed', r.id === selected ? 'true' : 'false');
      b.addEventListener('click', () => {
        if (r.id === selected) return;
        appsmith.updateModel({ selectedId: r.id });
        appsmith.triggerEvent('onSelect');
      });
      chips.appendChild(b);
    });
    li.appendChild(name);
    li.appendChild(chips);
    list.appendChild(li);
  });
}

appsmith.onReady(() => {
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
