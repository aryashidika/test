// cwImageGallery — galeri gambar change log di modal Riwayat (Specsheet & CBD, F10b). Hanya tampilan.
// Model masuk: { title, emptyText, loading, images: [{ id, name, mime, size, data (base64) }] }
// Event keluar: onDownload (setelah appsmith.updateModel({ downloadId })).
const $ = id => document.getElementById(id);
let M = {};
let current = -1;

function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}

function images() {
  return Array.isArray(M.images) ? M.images.filter(i => i && i.data) : [];
}

function src(img) {
  return `data:${img.mime || 'image/png'};base64,${img.data}`;
}

function openViewer(n) {
  const list = images();
  if (!list[n]) return;
  current = n;
  $('vimg').src = src(list[n]);
  $('vimg').alt = list[n].name || '';
  $('vname').textContent = `${list[n].name || 'gambar'} (${n + 1} / ${list.length})`;
  $('vprev').disabled = n === 0;
  $('vnext').disabled = n === list.length - 1;
  $('viewer').hidden = false;
}

function closeViewer() {
  current = -1;
  $('viewer').hidden = true;
  $('vimg').removeAttribute('src');
}

function render(model) {
  M = model || {};
  const list = images();
  $('title').textContent = M.title || 'Gambar';
  $('count').textContent = list.length ? `${list.length} gambar` : '';
  $('empty').textContent = M.loading ? 'Memuat gambar…' : (M.emptyText || 'Tidak ada gambar.');
  $('empty').hidden = !M.loading && list.length > 0;
  const grid = $('grid');
  grid.innerHTML = '';
  grid.hidden = !!M.loading || list.length === 0;
  list.forEach((img, n) => {
    const b = document.createElement('button');
    b.type = 'button';
    b.className = 'tile';
    b.title = 'Klik untuk memperbesar';
    const pic = document.createElement('img');
    pic.src = src(img);
    pic.alt = img.name || '';
    const name = document.createElement('span');
    name.className = 'name';
    name.textContent = img.name || 'gambar';
    b.appendChild(pic);
    b.appendChild(name);
    b.addEventListener('click', () => openViewer(n));
    grid.appendChild(b);
  });
  if (current >= 0 && !list[current]) closeViewer();
}

appsmith.onReady(() => {
  applyTheme(appsmith.theme);
  $('vclose').addEventListener('click', closeViewer);
  $('vprev').addEventListener('click', () => openViewer(current - 1));
  $('vnext').addEventListener('click', () => openViewer(current + 1));
  $('vdl').addEventListener('click', () => {
    const img = images()[current];
    if (!img) return;
    appsmith.updateModel({ downloadId: img.id });
    appsmith.triggerEvent('onDownload');
  });
  document.addEventListener('keydown', e => {
    if ($('viewer').hidden) return;
    if (e.key === 'Escape') closeViewer();
    else if (e.key === 'ArrowLeft' && current > 0) openViewer(current - 1);
    else if (e.key === 'ArrowRight' && current < images().length - 1) openViewer(current + 1);
  });
  render(appsmith.model);
  appsmith.onModelChange(render);
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
