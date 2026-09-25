// cwMenu — kartu menu Beranda. Hanya tampilan.
// Model masuk: { loaded, title, subtitle, items: [{ key, title, desc, target, icon, badge }] }
// Event keluar: onOpen (setelah appsmith.updateModel({ target, key })).

const $ = id => document.getElementById(id);
const ICONS = {
  database: '<path d="M4 6c0-1.7 3.6-3 8-3s8 1.3 8 3-3.6 3-8 3-8-1.3-8-3z"/><path d="M4 6v6c0 1.7 3.6 3 8 3s8-1.3 8-3V6"/><path d="M4 12v6c0 1.7 3.6 3 8 3s8-1.3 8-3v-6"/>',
  layers: '<path d="M12 3 2 8l10 5 10-5-10-5z"/><path d="m2 16 10 5 10-5"/><path d="m2 12 10 5 10-5"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6"/><path d="M16 4.5a3.5 3.5 0 0 1 0 7"/><path d="M18 14.2c2 .7 3.5 2.8 3.5 5.8"/>',
  list: '<path d="M9 6h11M9 12h11M9 18h11"/><path d="m3.5 6 1 1 2-2M3.5 12l1 1 2-2M3.5 18l1 1 2-2"/>',
  file: '<path d="M14 3H6a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8z"/><path d="M14 3v5h5"/>'
};
function svg(name) {
  const body = ICONS[name] || ICONS.file;
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"
    stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
}
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
function open(item) {
  appsmith.updateModel({
    target: item.target,
    key: item.key
  });
  appsmith.triggerEvent('onOpen');
}
function render(model) {
  const m = model || {};
  $('title').textContent = m.title || 'Menu';
  $('subtitle').textContent = m.subtitle || '';
  $('subtitle').hidden = !m.subtitle;
  const items = Array.isArray(m.items) ? m.items : [];
  $('loading').hidden = !!m.loaded;
  $('empty').hidden = !m.loaded || items.length > 0;
  $('grid').hidden = !m.loaded || items.length === 0;
  const grid = $('grid');
  grid.innerHTML = '';
  items.forEach(item => {
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'card';
    card.innerHTML = `
      ${item.badge ? `<span class="badge">${esc(item.badge)}</span>` : ''}
      <div class="icon">${svg(item.icon)}</div>
      <h3>${esc(item.title)}</h3>
      <p class="desc">${esc(item.desc)}</p>
      <span class="open">Buka <span aria-hidden="true">→</span></span>`;
    card.addEventListener('click', () => open(item));
    grid.appendChild(card);
  });
}
appsmith.onReady(() => {
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(model => render(model));
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
