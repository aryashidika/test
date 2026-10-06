// cwWorklist — daftar "Tugas Saya" di Beranda (ringkasan + bagian berisi tugas yang bisa diklik). Hanya tampilan.
// Model masuk: { loaded, loading, title, subtitle, columns, stats: [{ key, value, label, tone }],
//   sections: [{ key, title, note, empty, hideWhenEmpty, items: [{ title, meta, flags: [{ text, tone, hint }], target, params }] }] }
// Event keluar: onOpen (setelah appsmith.updateModel({ target, params })), onRefresh.

const $ = id => document.getElementById(id);
const LIMIT = 6;          // item per bagian sebelum "Tampilkan semua"
const expanded = {};      // key bagian -> sudah "Tampilkan semua"
const TONES = ['info', 'warn', 'danger', 'ok'];

function esc(text) {
  const div = document.createElement('div');
  div.textContent = text == null ? '' : String(text);
  return div.innerHTML;
}
function applyTheme(theme) {
  const t = theme || {};
  const root = document.documentElement.style;
  if (t.primaryColor) root.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) root.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') {
    root.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
  }
}
function toneClass(tone) {
  return TONES.includes(tone) ? ` tone-${tone}` : '';
}
function open(item) {
  appsmith.updateModel({
    target: item.target,
    params: item.params || {}
  });
  appsmith.triggerEvent('onOpen');
}
function goTo(key) {
  const el = document.getElementById('sec-' + key);
  if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

function statEl(stat) {
  const value = Number(stat.value) || 0;
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'stat' + (value > 0 ? toneClass(stat.tone) : '');
  btn.innerHTML = `<span class="value">${esc(value.toLocaleString('id-ID'))}</span><span class="label">${esc(stat.label)}</span>`;
  btn.addEventListener('click', () => goTo(stat.key));
  return btn;
}

function taskEl(item) {
  const clickable = !!item.target;
  const el = document.createElement(clickable ? 'button' : 'div');
  if (clickable) el.type = 'button';
  el.className = 'task';
  const flags = (Array.isArray(item.flags) ? item.flags : []).map(f =>
    `<span class="flag${toneClass(f.tone)}"${f.hint ? ` title="${esc(f.hint)}"` : ''}>${esc(f.text)}</span>`
  ).join('');
  el.innerHTML = `
    <span class="task-main">
      <span class="task-title">${esc(item.title)}</span>
      ${item.meta ? `<span class="task-meta">${esc(item.meta)}</span>` : ''}
    </span>
    ${flags ? `<span class="task-flags">${flags}</span>` : ''}
    ${clickable ? '<span class="chev" aria-hidden="true">→</span>' : ''}`;
  if (clickable) el.addEventListener('click', () => open(item));
  return el;
}

function sectionEl(section, rerender) {
  const items = Array.isArray(section.items) ? section.items : [];
  const card = document.createElement('section');
  card.className = 'card';
  card.id = 'sec-' + section.key;
  card.innerHTML = `<h3>${esc(section.title)}${items.length ? ` <span class="count">${items.length}</span>` : ''}</h3>`
    + (section.note ? `<p class="note">${esc(section.note)}</p>` : '');
  if (!items.length) {
    card.insertAdjacentHTML('beforeend', `<p class="none">${esc(section.empty || 'Tidak ada.')}</p>`);
    return card;
  }
  const list = document.createElement('div');
  list.className = 'list';
  const shown = expanded[section.key] ? items : items.slice(0, LIMIT);
  shown.forEach(item => list.appendChild(taskEl(item)));
  card.appendChild(list);
  if (items.length > LIMIT) {
    const more = document.createElement('button');
    more.type = 'button';
    more.className = 'more';
    more.textContent = expanded[section.key] ? 'Tampilkan lebih sedikit' : `Tampilkan semua (${items.length})`;
    more.addEventListener('click', () => {
      expanded[section.key] = !expanded[section.key];
      rerender();
    });
    card.appendChild(more);
  }
  return card;
}

let current = {};
function render(model) {
  current = model || {};
  const m = current;
  const scroller = document.scrollingElement || document.documentElement;
  const keepTop = scroller.scrollTop;

  $('title').textContent = m.title || 'Tugas Saya';
  $('subtitle').textContent = m.subtitle || '';
  $('subtitle').hidden = !m.subtitle;
  $('refresh').disabled = !!m.loading;
  $('refresh').textContent = m.loading ? 'Memuat…' : '↻ Muat ulang';

  const loaded = !!m.loaded;
  const stats = Array.isArray(m.stats) ? m.stats : [];
  const sections = (Array.isArray(m.sections) ? m.sections : [])
    .filter(s => !(s.hideWhenEmpty && !(Array.isArray(s.items) && s.items.length)));

  $('loading').hidden = loaded;
  $('stats').hidden = !loaded || stats.length === 0;
  $('sections').hidden = !loaded || sections.length === 0;
  $('none').hidden = !loaded || sections.length > 0;

  const statsBox = $('stats');
  statsBox.innerHTML = '';
  stats.forEach(s => statsBox.appendChild(statEl(s)));

  const box = $('sections');
  box.className = 'sections' + (Number(m.columns) === 2 ? ' cols-2' : '');
  box.innerHTML = '';
  sections.forEach(s => box.appendChild(sectionEl(s, () => render(current))));

  scroller.scrollTop = keepTop;
}

appsmith.onReady(() => {
  applyTheme(appsmith.theme);
  $('refresh').addEventListener('click', () => appsmith.triggerEvent('onRefresh'));
  render(appsmith.model);
  appsmith.onModelChange(model => render(model));
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
