// cwReasonForm - form alasan umum (mis. Tolak usulan harga). Hanya tampilan; teks judul, ringkasan,
// label, dan tombol dari model. Simpan lewat JSObject pemilik (event onSave).
const $ = id => document.getElementById(id);
let lastKey = null;
let busy = false;
let confirmLabel = 'Save';
let minLength = 3;

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

// Isi ulang hanya saat modal dibuka (key berubah) - busy/message tidak menghapus ketikan user
function fillForm(m) {
  $('title').textContent = m.title || 'Reason';
  $('summary').textContent = m.summary || '';
  $('summary').hidden = !m.summary;
  $('label').textContent = m.label || 'Reason';
  $('reason').placeholder = m.placeholder || '';
  $('reason').value = m.reason || '';
  $('reason').classList.remove('invalid');
  $('hint').textContent = m.hint || '';
  $('hint').hidden = !m.hint;
  confirmLabel = m.confirmLabel || 'Save';
  minLength = Number.isInteger(m.minLength) ? m.minLength : 3;
  $('btnSave').className = m.danger ? 'btn-primary btn-danger' : 'btn-primary';
  $('reason').focus();
}

function setBusy(v) {
  busy = v;
  $('btnSave').disabled = v;
  $('btnCancel').disabled = v;
  $('btnX').disabled = v;
  $('btnSave').textContent = v ? 'Saving…' : confirmLabel;
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
  const reason = $('reason').value.trim();
  if (reason.length < minLength) {
    $('reason').classList.add('invalid');
    $('reason').focus();
    showMessage({ type: 'error', text: `${$('label').textContent} is required (min. ${minLength} characters).` });
    return;
  }
  appsmith.updateModel({ reason });
  appsmith.triggerEvent('onSave');
}

function cancel() {
  if (!busy) appsmith.triggerEvent('onCancel');
}

appsmith.onReady(() => {
  $('btnSave').addEventListener('click', submit);
  $('btnCancel').addEventListener('click', cancel);
  $('btnX').addEventListener('click', cancel);
  $('reason').addEventListener('input', () => $('reason').classList.remove('invalid'));
  $('reason').addEventListener('keydown', e => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) submit();
  });
  applyTheme(appsmith.theme);
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
