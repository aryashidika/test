// cwLogin — form Masuk & Ganti Password. Kontrak model/event: lihat README.md.
// Widget ini hanya tampilan: validasi ringan di sini, semua keputusan di LoginCtrl + DB.

const $ = (id) => document.getElementById(id);
const PASSWORD_FIELDS = ['password', 'oldPass', 'newPass', 'newPass2'];

let currentView = null;
let busy = false;

function applyTheme(theme) {
  const t = theme || {};
  const root = document.documentElement.style;
  if (t.primaryColor) root.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) root.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') {
    root.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
  }
}

function showMessage(message) {
  const box = $('msg');
  if (!message || !message.text) {
    box.hidden = true;
    box.textContent = '';
    return;
  }
  box.className = `msg ${message.type || 'info'}`;
  box.textContent = message.text;
  box.hidden = false;
}

function clearPasswords() {
  PASSWORD_FIELDS.forEach((id) => { $(id).value = ''; });
}

function setBusy(value) {
  const wasBusy = busy;
  busy = value;
  $('btnLogin').disabled = busy;
  $('btnChange').disabled = busy;
  $('btnCancel').disabled = busy;
  $('btnLogin').textContent = busy ? 'Memproses…' : 'Masuk';
  $('btnChange').textContent = busy ? 'Menyimpan…' : 'Simpan';
  // Selesai diproses (berhasil atau gagal): password tidak dibiarkan di layar
  if (wasBusy && !busy) clearPasswords();
}

function render(model) {
  const m = model || {};
  const view = m.view === 'change' ? 'change' : 'login';

  if (m.appName) $('appName').textContent = m.appName;

  if (view !== currentView) {
    currentView = view;
    $('viewLogin').hidden = view !== 'login';
    $('viewChange').hidden = view !== 'change';
    clearPasswords();
    if (view === 'login') {
      if (m.email && !$('email').value) $('email').value = m.email;
      ($('email').value ? $('password') : $('email')).focus();
    } else {
      $('oldPass').focus();
    }
  }

  $('btnCancel').textContent = m.forced ? 'Keluar' : 'Batal';
  $('changeHint').textContent = m.forced
    ? 'Anda masuk dengan password sementara. Buat password baru (minimal 8 karakter) sebelum melanjutkan.'
    : 'Minimal 8 karakter.';

  showMessage(m.message);
  setBusy(!!m.busy);
}

function submitLogin() {
  if (busy) return;
  const email = $('email').value.trim().toLowerCase();
  const password = $('password').value;
  if (!email || !password) {
    showMessage({ type: 'error', text: 'Isi email dan password.' });
    return;
  }
  appsmith.updateModel({ email, password });
  appsmith.triggerEvent('onLogin');
}

function submitChange() {
  if (busy) return;
  const oldPass = $('oldPass').value;
  const newPass = $('newPass').value;
  const newPass2 = $('newPass2').value;
  let error = '';
  if (!oldPass || !newPass) error = 'Isi password lama dan password baru.';
  else if (newPass.length < 8) error = 'Password baru minimal 8 karakter.';
  else if (newPass !== newPass2) error = 'Konfirmasi password baru tidak sama.';
  else if (newPass === oldPass) error = 'Password baru harus berbeda dari password lama.';
  if (error) {
    showMessage({ type: 'error', text: error });
    return;
  }
  appsmith.updateModel({ oldPass, newPass });
  appsmith.triggerEvent('onChangePassword');
}

function onEnter(ids, handler) {
  ids.forEach((id) => {
    $(id).addEventListener('keydown', (e) => {
      if (e.key === 'Enter') handler();
    });
  });
}

function bindEvents() {
  $('btnLogin').addEventListener('click', submitLogin);
  $('btnChange').addEventListener('click', submitChange);
  $('btnCancel').addEventListener('click', () => {
    if (!busy) appsmith.triggerEvent('onCancelChange');
  });
  onEnter(['email', 'password'], submitLogin);
  onEnter(['oldPass', 'newPass', 'newPass2'], submitChange);

  document.querySelectorAll('.pw-toggle').forEach((btn) => {
    btn.addEventListener('click', () => {
      const input = $(btn.dataset.for);
      const show = input.type === 'password';
      input.type = show ? 'text' : 'password';
      btn.textContent = show ? 'Sembunyikan' : 'Lihat';
    });
  });
}

appsmith.onReady(() => {
  bindEvents();
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange((model) => render(model));
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
