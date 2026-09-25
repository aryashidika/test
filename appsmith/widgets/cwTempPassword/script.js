// cwTempPassword — tampilkan password sementara sekali. Hanya tampilan; salin & tutup lewat event.
const $ = id => document.getElementById(id);
let copiedTimer = null;
let lastPassword = null;
function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}
function resetCopied() {
  clearTimeout(copiedTimer);
  $('btnCopy').textContent = 'Salin';
  $('btnCopy').classList.remove('copied');
}
function render(model) {
  const m = model || {};
  $('email').textContent = m.email || '-';
  $('password').textContent = m.password || '-';
  $('btnCopy').disabled = !m.password;
  if (m.password !== lastPassword) {
    // password baru -> status "Disalin" dihapus
    lastPassword = m.password;
    resetCopied();
  }
}
appsmith.onReady(() => {
  $('btnCopy').addEventListener('click', () => {
    appsmith.triggerEvent('onCopy');
    $('btnCopy').textContent = 'Disalin ✓';
    $('btnCopy').classList.add('copied');
    clearTimeout(copiedTimer);
    copiedTimer = setTimeout(resetCopied, 2000);
  });
  $('btnClose').addEventListener('click', () => appsmith.triggerEvent('onClose'));
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
