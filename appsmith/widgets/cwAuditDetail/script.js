// cwAuditDetail: panel detail baris audit di page Admin (tab Audit Log, sebelah tblAudit). Hanya tampilan;
// isi & format dari AdminCtrl.auditModel(). Tombol kolom teknis hanya membuka/menutup daftar di widget ini.
const $ = id => document.getElementById(id);
let lastKey = null;
let showTech = false;

function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}

function valueEl(v, cls) {
  const s = document.createElement('span');
  s.className = `v ${v.empty ? 'empty' : cls}`;
  s.textContent = v.text;
  if (v.full) s.title = v.full;
  return s;
}

function rowEl(r, kind) {
  const d = document.createElement('div');
  d.className = 'row';
  const f = document.createElement('div');
  f.className = 'field';
  f.textContent = r.field;
  const vals = document.createElement('div');
  vals.className = 'vals';
  if (kind === 'diff') {
    vals.appendChild(valueEl(r.before, 'old'));
    const a = document.createElement('span');
    a.className = 'arrow';
    a.textContent = '→';
    vals.appendChild(a);
    vals.appendChild(valueEl(r.after, 'new'));
  } else {
    vals.appendChild(valueEl(kind === 'before' ? r.before : r.after, 'plain'));
  }
  d.appendChild(f);
  d.appendChild(vals);
  return d;
}

function fill(box, list, kind) {
  box.innerHTML = '';
  list.forEach(r => box.appendChild(rowEl(r, kind)));
}

function render(model) {
  const m = model || {};
  $('empty').hidden = !m.empty && !!m.action;
  $('detail').hidden = !$('empty').hidden;
  if ($('detail').hidden) return;
  if (m.key !== lastKey) {
    lastKey = m.key;
    showTech = false;
  }
  $('action').textContent = m.action;
  $('action').className = `badge ${m.action}`;
  $('entity').textContent = m.entity;
  $('time').textContent = m.time;
  $('user').textContent = m.user;
  $('entityId').textContent = m.entityId;
  $('title').textContent = m.title;

  const rows = m.rows || [];
  const main = rows.filter(r => !r.tech);
  const tech = rows.filter(r => r.tech);
  $('count').textContent = main.length ? `(${main.length})` : '';
  $('note').textContent = m.note || (!main.length && tech.length ? 'Only technical fields.' : '');
  $('note').hidden = !$('note').textContent;
  fill($('rows'), main, m.kind);
  fill($('techRows'), tech, m.kind);
  $('btnTech').hidden = !tech.length;
  $('btnTech').textContent = `${showTech ? 'Hide' : 'Show'} technical fields (${tech.length})`;
  $('techRows').hidden = !showTech || !tech.length;
}

appsmith.onReady(() => {
  $('btnTech').addEventListener('click', () => {
    showTech = !showTech;
    render(appsmith.model);
  });
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
