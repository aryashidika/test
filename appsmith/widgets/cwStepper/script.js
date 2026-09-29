// cwStepper — stepper stage PULL → SMS → GTM → PROD berisi chip revisi (r0, r1, …). Hanya tampilan.
// Klik chip -> model.selectedId + event onSelect (SpecCtrl.selectRevision()).
// Chip DRAFT kuning bergaris putus; chip terpilih terisi. Brand hanya menerima revisi PUBLISHED dari query.
const $ = id => document.getElementById(id);
const STAGES = ['PULL', 'SMS', 'GTM', 'PROD'];

function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}

function render(model) {
  const m = model || {};
  const revs = m.revisions || [];
  const selected = m.selectedId || '';
  const current = (revs.find(r => r.id === selected) || {}).stage;
  const list = $('steps');
  list.innerHTML = '';
  $('empty').hidden = true;
  if (!revs.length && m.emptyText) {
    $('empty').textContent = m.emptyText;
    $('empty').hidden = false;
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
    name.textContent = stage;
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
      b.className = 'chip' + (r.status === 'DRAFT' ? ' draft' : '') + (r.id === selected ? ' active' : '');
      b.textContent = `r${r.revision_no}`;
      b.title = `${r.stage} r${r.revision_no} · ${r.status === 'DRAFT' ? 'DRAFT (belum terbit)' : 'PUBLISHED'}`;
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
