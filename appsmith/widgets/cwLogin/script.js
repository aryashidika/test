// cwLogin - form Masuk & Ganti Password. Kontrak model/event: lihat README.md.
// Widget ini hanya tampilan: validasi ringan di sini, semua keputusan di LoginCtrl + DB.

const $ = (id) => document.getElementById(id);
const PASSWORD_FIELDS = ['password', 'oldPass', 'newPass', 'newPass2'];

let currentView = null;
let busy = false;
let filledEmail = '';   // email dari model yang terakhir diisikan (email tersimpan bisa datang setelah render pertama)

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
  $('btnLogin').textContent = busy ? 'Processing…' : 'Log in';
  $('btnChange').textContent = busy ? 'Saving…' : 'Save';
  // Selesai diproses (berhasil atau gagal): password tidak dibiarkan di layar
  if (wasBusy && !busy) clearPasswords();
}

function fillEmail(email) {
  if (email && !$('email').value) {
    $('email').value = email;
    filledEmail = email;
  }
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
      fillEmail(m.email);
      ($('email').value ? $('password') : $('email')).focus();
    } else {
      $('oldPass').focus();
    }
  } else if (view === 'login' && m.email && m.email !== filledEmail && !$('email').value) {
    fillEmail(m.email);
    if (document.activeElement === $('email')) $('password').focus();
  }

  $('btnCancel').textContent = m.forced ? 'Log out' : 'Cancel';
  $('changeHint').textContent = m.forced
    ? 'You logged in with a temporary password. Create a new password (at least 8 characters) to continue.'
    : 'At least 8 characters.';

  showMessage(m.message);
  setBusy(!!m.busy);
}

function submitLogin() {
  if (busy) return;
  const email = $('email').value.trim().toLowerCase();
  const password = $('password').value;
  if (!email || !password) {
    showMessage({ type: 'error', text: 'Enter email and password.' });
    return;
  }
  appsmith.updateModel({ email, password, remember: $('remember').checked });
  appsmith.triggerEvent('onLogin');
}

function submitChange() {
  if (busy) return;
  const oldPass = $('oldPass').value;
  const newPass = $('newPass').value;
  const newPass2 = $('newPass2').value;
  let error = '';
  if (!oldPass || !newPass) error = 'Enter the old and new password.';
  else if (newPass.length < 8) error = 'New password must be at least 8 characters.';
  else if (newPass !== newPass2) error = 'New password confirmation does not match.';
  else if (newPass === oldPass) error = 'New password must differ from the old one.';
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
      btn.textContent = show ? 'Hide' : 'Show';
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
