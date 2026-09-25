// cwHeader — header app: nama app, judul page, user + role, tombol Beranda / Ganti Password / Keluar.
// Hanya tampilan. Model masuk: { pageTitle, name, role, showHome }. Event: onHome, onChangePassword, onLogout.

const $ = id => document.getElementById(id);
function applyTheme(theme) {
  const t = theme || {};
  const root = document.documentElement.style;
  if (t.primaryColor) root.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) root.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') {
    root.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
  }
}
function initials(name) {
  const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '?';
  const first = parts[0][0] || '';
  const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
  return (first + last).toUpperCase();
}
function render(model) {
  const m = model || {};
  if (m.appName) $('appName').textContent = m.appName;
  $('pageTitle').textContent = m.pageTitle || '';
  $('btnHome').hidden = !m.showHome;
  const hasUser = !!m.name;
  $('userBox').hidden = !hasUser;
  if (hasUser) {
    $('userName').textContent = m.name;
    $('userName').title = m.email || m.name;
    $('userRole').textContent = m.role || '';
    $('avatar').textContent = initials(m.name);
  }
}
appsmith.onReady(() => {
  $('btnHome').addEventListener('click', () => appsmith.triggerEvent('onHome'));
  $('btnPassword').addEventListener('click', () => appsmith.triggerEvent('onChangePassword'));
  $('btnLogout').addEventListener('click', () => appsmith.triggerEvent('onLogout'));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(model => render(model));
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
