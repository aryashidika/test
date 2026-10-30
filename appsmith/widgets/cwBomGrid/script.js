// cwBomGrid - grid BOM page Specsheet: No, Komponen, Material, Supplier, UoM, Thickness, Remarks + satu kolom per article.
// F10b: sel warna & Remarks = kotak teks yang membungkus (terbaca semua); Remarks boleh beberapa baris (Shift+Enter);
//   saran warna = daftar sendiri (panah atas/bawah lalu Enter memilih saran - ketikan setengah jadi tidak tersimpan).
// R4: baris = material INDUK + thickness ("NAMA · THICKNESS"); sel = WARNA, varian (Material Code) dicari DB.
//   (R20: Material Code tidak lagi diketik di kolom Material / sel.) Sel berwarna tanpa varian =
//   SEL KUNING + tombol Daftarkan (action registerVariant). Tombol "+ Supplier baru" (action newSupplier).
// R16: thickness diketik apa adanya lalu dibakukan (= fn_clean_thickness, canonThickness); "NAMA · THICKNESS" dengan thickness
//   baru untuk induk yang ada = baris baru, selnya kuning sampai kodenya didaftarkan. Induk yang belum ada: tombol
//   "+ New material" (action newMaterial). Typo: pesan "Did you mean".
// R16 (20 Okt 2026, permintaan user): material yang tidak ketemu (Enter / + Add / ganti material di sel) -> tombol
//   "+ New material" langsung di sel Material baris itu. Setelah material disimpan di modal (model.matAdded berubah), aksi baris
//   itu diulang otomatis dengan nama yang disimpan: baris tambah / sub ditambahkan, atau material baris diganti.
// R19 (catatan uji user 26 Okt 2026): kolom Material = NAMA saja (atau Material Code: mengisi nama + dimension), DIMENSION diisi di
//   kolom Dimension (saran dimension terdaftar material itu, boleh baru). Ganti dimension baris = Ganti material (material sama).
//   Ketikan lama "NAMA · DIMENSION" / "NAMA . 1,5 mm" tetap dibaca lalu dipisah ke dua kolom. Ganti nama material di baris yang
//   dimension-nya tidak jelas (material punya beberapa dimension) -> dimension dipilih dulu (pendingDim), baru disimpan sekali.
//   Saran Material & Dimension = daftar sendiri yang membungkus (NAMA + UoM · dimension; nama sama beda UoM = "NAMA (UOM)").
//   Tombol "Change" di kolom Component (baris induk) = ganti komponen ke komponen master lain (action changeComponent).
//   Material Process (is_process): tanpa Material Code, sel tidak pernah kuning.
// R20 (27 Okt 2026): Material Code HANYA diketik di Register (modal; di sana ada tombol Use bila kode sudah dipakai). Kolom Material
//   dan sel warna tidak membaca kode lagi: kode yang diketik di sel = teks warna biasa (kuning). Warna yang sudah terdaftar untuk
//   material + dimension baris tetap langsung dapat kode (DB). Nama material yang hanya beda spasi / tanda baca langsung dipakai nama
//   master (PU-LEATHER = PU LEATHER). "Did you mean" hanya untuk nama yang angkanya sama (FOAM 50 KG bukan saran untuk FOAM 60 KG).
// R20 bagian 3 (28 Okt 2026): Dimension wajib terisi; tanpa dimension = "(None)" (paling atas di daftar Dimension). Material dipilih
//   (baris tambah / sub) atau diganti di baris -> Dimension otomatis: dimension baris yang juga ada di material itu tetap, selain itu
//   dimension material itu dengan varian terbanyak (sama banyak: paling dulu didaftarkan; belum ada varian = (None)). Kotak
//   dikosongkan = (None). Alur lama "pilih dimension dulu" (pendingDim) dihapus.
// R20 bagian 5 (28 Okt 2026, permintaan user): link "Edit material" di kolom Material (draft, role canAddMaterial) = action
//   editMaterial { material_id } -> BomCtrl membuka Edit Material (nama, kategori, UoM, Process, status di master).
// R20 bagian 6 (28 Okt 2026, catatan uji user: ganti Dimension baris A lalu cepat klik baris B -> B tersimpan sendiri, tidak bisa
//   mengetik, daftar tidak muncul): (1) selama render ulang tidak ada kotak yang menyimpan (blur karena kotak dibuang);
//   (2) Dimension di grid: memilih dari daftar langsung menyimpan; (3) fokus pindah ke baris pengganti (replaces_line_key) bila
//   id baris berganti karena Ganti material / Dimension; (4) daftar yang terbuka dibuka lagi setelah render, guliran grid
//   menggeser daftar (bukan menutup); (5) kotak yang sedang fokus dipakai lagi (tidak dibuat ulang): ketikan, kursor tetap.
// Hanya tampilan & input. Setiap perubahan dikirim sebagai model.action + event onAction (BomCtrl.onAction());
// BomCtrl menjalankan query lalu memuat ulang data. Aturan final di DB (fn_bom_*).
// Antrean aksi: aksi dikirim SATU PER SATU; berikutnya baru dikirim setelah BomCtrl membalas doneSeq >= seq aksi
//   (ack). Tanpa ack 5 detik -> kirim ulang (BomCtrl mengabaikan seq yang sudah selesai). Nilai yang sudah dikirim
//   ditampilkan (optimistic) sampai antrean kosong, supaya render ulang tidak memunculkan nilai lama.
// Teks yang diketik dicocokkan ke master di sini:
//   komponen "10 - Vamp" / "10" / nama unik -> master ACTIVE; selain itu komponen lokal (No. wajib)
//   material "NAMA · THICKNESS" / nama unik; supplier = nama (kosong = tanpa supplier)
const $ = id => document.getElementById(id);
const SEP = ' · ';
let M = {};                 // model terakhir
let seq = 0;
let queue = [];             // aksi menunggu ack BomCtrl (model.doneSeq); queue[0] = yang sedang dikirim
let retryTimer = null;
let optimistic = {};        // key input -> nilai yang sudah dikirim tapi belum kembali dari DB
let lastMsg = null;         // object message dari model (untuk mendeteksi pesan baru)
let localMsg = null;        // pesan validasi di widget
let lastNotFound = null;    // R16: material terakhir yang diketik dan tidak ketemu -> isian awal "+ New material"
let nfFor = null;           // R16: { key, name, thick } input Material yang tidak ketemu -> tombol "+ New material" di sel itu
let awaitNew = null;        // R16: { key, thick } menunggu material baru dari modal, lalu aksi baris itu diulang otomatis
let lastMatAdded = null;    // R16: model.matAdded.key terakhir
let curAdd = null;          // input baris tambah yang sedang tampil
let curSub = null;          // { parent, f } form subkomponen yang sedang tampil
let lastOkKey = null;
let subParent = null;       // id baris induk yang sedang dibuka form "+ Sub"
let addState = {};          // isian baris tambah (dipertahankan saat render ulang)
let subState = {};
let dropArmed = null;       // article yang tombol drop-nya menunggu klik kedua
let dropTimer = null;
let delArmed = null;        // baris yang tombol Hapus-nya menunggu klik kedua
let delTimer = null;
let compEdit = null;        // R19: line_id baris yang kolom Component-nya sedang diganti
let MATS = [];              // R19: material unik { material_id, name, uom, is_process, dims: [{ thickness, n, first }] }
const NONE = '(None)';      // R20 bagian 3: tanpa dimension (disimpan kosong)
let ALL_DIMS = [];          // R20: semua dimension terdaftar di pabrik [{ thickness, key, mats }] (saran "Other materials")
let MAT_BY_ID = {};
let MATS_SRC = null;
let USED_BY_ID = {};        // R20 bagian 7: material_id -> [{ thickness, lines }] dipakai di specsheet, belum ada varian ACTIVE
let USED_SRC = null;
let rendering = false;      // R20 bagian 6: render() sedang berjalan -> blur / focus dari render tidak menyimpan / membuka daftar

function applyTheme(t) {
  t = t || {};
  const r = document.documentElement.style;
  if (t.primaryColor) r.setProperty('--primary', t.primaryColor);
  if (t.borderRadius) r.setProperty('--radius', t.borderRadius);
  if (t.fontFamily && t.fontFamily !== 'System Default') r.setProperty('--font', `${t.fontFamily}, "Segoe UI", Arial, sans-serif`);
}

// = fn_normalize: huruf kecil, koma -> titik, spasi dirapatkan, trim
function norm(s) {
  return String(s ?? '').toLowerCase().replace(/,/g, '.').replace(/\s+/g, ' ').trim();
}

function tidy(s) {
  return String(s ?? '').replace(/\s+/g, ' ').trim();
}

// = fn_clean_thickness (R16, gaya berspasi tim material): huruf besar, kutip pintar / dua apostrof -> ", koma desimal -> titik,
// ".5" -> "0.5", nol belakang dibuang ("2.0" = "2"), INCH / IN setelah angka -> ", angka + satuan satu spasi ("1.2MM" -> "1.2 MM"),
// "X" antar ukuran berspasi ("44X69CM" -> "44 X 69 CM"), tanpa spasi di sekitar "-", spasi sebelum "(", rentang
// "1.4 MM-1.6 MM" -> "1.4-1.6 MM". Kosong / "." / "-" / (None) = tanpa thickness. Salinan sama di cwVariantForm.
function canonThickness(s) {
  let t = String(s ?? '').replace(/\s+/g, ' ').trim().toUpperCase();
  if (t === '' || t === '.' || t === '-' || t === 'NONE' || t === '(NONE)') return '';
  t = t.replace(/[“”„‟″〃＂]/g, '"')
    .replace(/['’‘′`´]{2}/g, '"')
    .replace(/(\d),(\d)/g, '$1.$2')
    .replace(/(^|[^0-9A-Z.])\.(\d)/g, (m, a, b) => `${a}0.${b}`)   // R21: bukan sesudah huruf (NO.1)
    .replace(/(\d)\.(\d*[1-9])0+(?![0-9])/g, '$1.$2')
    .replace(/(\d)\.0+(?![0-9])/g, '$1')
    .replace(/(\d)\s*(INCHES|INCH|IN)(?=$|\s*X|\s*\(|\s*-|[^A-Z0-9\s])/g, '$1"')
    .replace(/(\d)\s*(MM|CM|UM|ME)(?=$|[^A-Z]|X\d)/g, '$1 $2')
    .replace(/(\d|MM|CM|UM|")\s*X\s*(?=\d)/g, '$1 X ')
    .replace(/\s*-\s*/g, '-')
    .replace(/\s*\(\s*/g, ' (')
    .replace(/\s+\)/g, ')')
    .replace(/(\d)\s+"/g, '$1"')
    .replace(/(\d) (MM|CM|UM)-(\d+(?:\.\d+)?) \2(?=$|[^A-Z])/g, '$1-$3 $2')
    .replace(/\s+/g, ' ')
    .trim();
  return t;
}

const thickKey = t => norm(canonThickness(t));
const dimText = t => canonThickness(t) ? t : NONE;   // R20 bagian 3: yang tampil di kolom Dimension

// Jarak ketik (Levenshtein) untuk saran typo
function editDistance(a, b) {
  const m = a.length;
  const n = b.length;
  let prev = Array.from({ length: n + 1 }, (_, j) => j);
  for (let i = 1; i <= m; i++) {
    const cur = [i];
    for (let j = 1; j <= n; j++) {
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[n];
}

// R20: kunci rapat = huruf + angka saja (= fn_tight_key): "P.U-LEATHER" = "PU LEATHER"
const tightKey = s => String(s ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');

// R20 warna: = fn_clean_color (huruf besar, spasi dirapatkan, tanpa spasi di sekitar / - & + ,) dan fn_color_key (= tightKey):
// BLACK / WHITE = BLACK-WHITE = BLACK WHITE; urutan beda (WHITE/BLACK) tetap warna lain. Salinan sama di cwVariantForm.
const cleanColor = s => String(s ?? '').toUpperCase().replace(/\s+/g, ' ').replace(/\s*([/&+,-])\s*/g, '$1').trim();
const colorKey = tightKey;
// kata-kata warna tanpa urutan: WHITE/BLACK dan BLACK/WHITE sama di sini (hanya untuk saran "Did you mean")
const colorWords = s => String(s ?? '').toLowerCase().split(/[^a-z0-9]+/).filter(w => w).sort().join(' ');

// R20: nama mirip yang layak disarankan (0 = tidak mirip, makin kecil makin mirip). Angka harus sama (FOAM 50 KG bukan
// FOAM 60 KG); lalu: hanya beda spasi / tanda baca (1), kata sama urutan lain (2), typo 1 huruf di kata 5 huruf ke atas (3),
// nama yang memuat ketikan (4). Salinan sama di BomCtrl.nearMaterialNames.
function nearName(a, b) {
  const nums = x => (String(x ?? '').replace(/,/g, '.').match(/\d+(?:\.\d+)?/g) || []).join(' ');
  if (nums(a) !== nums(b)) return 0;
  const ta = tightKey(a);
  const tb = tightKey(b);
  if (!ta || !tb) return 0;
  if (ta === tb) return 1;
  const words = x => String(x ?? '').toLowerCase().replace(/\d+(?:[.,]\d+)?/g, ' ').replace(/[^a-z]+/g, ' ').trim().split(' ').filter(w => w);
  const wa = words(a);
  const wb = words(b);
  if (wa.length && wa.slice().sort().join(' ') === wb.slice().sort().join(' ')) return 2;
  if (wa.length && wa.length === wb.length
      && wa.every((w, i) => w === wb[i] || (Math.min(w.length, wb[i].length) >= 5 && editDistance(w, wb[i]) === 1))) return 3;
  if (ta.length >= 4 && tb.includes(ta)) return 4;
  return 0;
}

// Remarks: baris dipertahankan, spasi di dalam baris dirapatkan, baris kosong dibuang
function tidyLines(s) {
  return String(s ?? '').split(/\r?\n/).map(x => x.replace(/\s+/g, ' ').trim()).filter(x => x).join('\n');
}

// Tinggi kotak teks mengikuti isi
function autosize(t) {
  if (!t || t.tagName !== 'TEXTAREA') return;
  t.style.height = 'auto';
  t.style.height = `${t.scrollHeight + 2}px`;
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined && text !== null) e.textContent = text;
  return e;
}

// ---------------------------------------------------------------- master & saran
const compLabel = c => `${c.number} - ${c.name}`;
const matKey = (materialId, thickness) => `${materialId}|${thickKey(thickness)}`;

// R19: material unik dari kombinasi induk × dimension (M.materials), dihitung ulang hanya bila daftar berubah
function buildMats() {
  if (MATS_SRC === M.materials && USED_SRC === M.usedDims) return;
  MATS_SRC = M.materials;
  USED_SRC = M.usedDims;
  MAT_BY_ID = {};
  MATS = [];
  (M.materials || []).forEach(x => {
    let m = MAT_BY_ID[x.material_id];
    if (!m) {
      m = { material_id: x.material_id, name: x.name, uom: x.uom, is_process: !!x.is_process, dims: [] };
      MAT_BY_ID[x.material_id] = m;
      MATS.push(m);
    }
    m.dims.push({ thickness: x.thickness || '', n: Number(x.variant_count) || 0, first: Number(x.first_at) || 0 });
  });
  // R20 bagian 3: dimension dengan varian terbanyak dulu (sama banyak: paling dulu didaftarkan) = default
  MATS.forEach(m => m.dims.sort((a, b) => b.n - a.n || a.first - b.first || a.thickness.localeCompare(b.thickness)));
  // R20 bagian 7: dimension yang sudah dipakai di specsheet tapi belum terdaftar (tanpa yang sudah ada di m.dims)
  USED_BY_ID = {};
  (M.usedDims || []).forEach(u => {
    const m = MAT_BY_ID[u.material_id];
    if (!m || !u.thickness) return;
    const k = thickKey(u.thickness);
    const list = USED_BY_ID[u.material_id] || (USED_BY_ID[u.material_id] = []);
    if (m.dims.some(d => thickKey(d.thickness) === k) || list.some(x => thickKey(x.thickness) === k)) return;
    list.push({ thickness: u.thickness, lines: Number(u.lines) || 0 });
  });
  const dimMap = {};
  MATS.forEach(m => m.dims.map(d => d.thickness).concat((USED_BY_ID[m.material_id] || []).map(u => u.thickness))
    .forEach(t => {
      if (!t || m.is_process) return;
      const k = thickKey(t);
      if (!dimMap[k]) dimMap[k] = { thickness: t, key: k, mats: 0 };
      dimMap[k].mats += 1;
    }));
  ALL_DIMS = Object.values(dimMap).sort((a, b) => b.mats - a.mats || a.thickness.localeCompare(b.thickness));
  const count = {};
  MATS.forEach(m => { count[norm(m.name)] = (count[norm(m.name)] || 0) + 1; });
  MATS.forEach(m => { m.label = count[norm(m.name)] > 1 ? `${m.name} (${m.uom})` : m.name; });
}

// Nama yang tampil di kolom Material: "NAMA", atau "NAMA (UOM)" bila ada material lain bernama sama
function nameLabel(materialId, fallback) {
  const m = MAT_BY_ID[materialId];
  return m ? m.label : (fallback || '');
}

// Dimension terdaftar material ini (varian terbanyak dulu); '' = tanpa dimension
const dimsOf = materialId => ((MAT_BY_ID[materialId] || {}).dims || []).map(d => d.thickness);

// R20 bagian 3: dimension default material = varian terbanyak ('' = (None), juga untuk material tanpa varian)
const defaultDim = materialId => dimsOf(materialId)[0] || '';

// R20 bagian 3: dimension saat material diganti: dimension sekarang bila terdaftar juga di material itu, selain itu default
function dimFor(materialId, current) {
  const keep = dimsOf(materialId).find(t => thickKey(t) === thickKey(current));
  return keep !== undefined ? keep : defaultDim(materialId);
}

// Saran kolom Material: nama + UoM · dimension (membungkus, terbaca penuh)
function materialSuggest() {
  return MATS.map(m => {
    const dims = m.dims.map(d => d.thickness).filter(t => t);
    const info = m.is_process ? 'Process (no Material Code)'
      : dims.length ? `dimension: ${dims.join(' / ')}` : 'no dimension';
    return { value: m.label, detail: `${m.uom} · ${info}` };
  });
}

// Saran kolom Dimension: dimension material itu (jumlah warna terdaftar = varian), R20 bagian 7: dimension yang sudah dipakai
// material itu di specsheet tapi belum punya kode, lalu R20: dimension material lain (other: true, di bawah "Other materials";
// bagian 7: langsung tampil saat diklik) supaya dimension baru ditulis seperti yang sudah ada.
function dimensionSuggest(getMaterialId) {
  return () => {
    const m = MAT_BY_ID[getMaterialId()];
    const own = m ? m.dims.filter(d => d.thickness).map(d => ({
      value: d.thickness, detail: m.is_process ? 'Process' : d.n ? `${d.n} colors` : 'no variants yet',
    })) : [];
    if (m) {
      (USED_BY_ID[m.material_id] || []).forEach(u => own.push({
        value: u.thickness, detail: `used in specsheet · no code yet (${u.lines} line${u.lines === 1 ? '' : 's'})`,
      }));
    }
    // R20 bagian 3: (None) selalu paling atas
    const nd = m ? m.dims.find(d => !d.thickness) : null;
    own.unshift({ value: NONE, none: true, detail: nd && nd.n ? `no dimension · ${nd.n} colors` : 'no dimension' });
    if (m && m.is_process) return own;
    const seen = new Set(own.map(o => thickKey(o.value)));
    return own.concat(ALL_DIMS.filter(d => !seen.has(d.key)).map(d => ({
      value: d.thickness, other: true,
      detail: `new for this material · used by ${d.mats} material${d.mats === 1 ? '' : 's'}`,
    })));
  };
}

// Varian ACTIVE per induk + thickness (warna terdaftar baris itu)
function variantsOf(materialId, thickness) {
  return (M.variants || []).filter(v => v.material_id === materialId && thickKey(v.thickness) === thickKey(thickness));
}

function resolveComponent(text) {
  const key = norm(text);
  if (!key) return { error: 'Component is required.' };
  const comps = M.components || [];
  let c = comps.find(x => norm(compLabel(x)) === key);
  if (c) return { comp: c };
  if (/^\d+$/.test(key)) {
    c = comps.find(x => Number(x.number) === Number(key));
    return c ? { comp: c } : { error: `Component number ${key} is not in the master. For a new component, type its name and fill in No.` };
  }
  const byName = comps.filter(x => norm(x.name) === key);
  return byName.length === 1 ? { comp: byName[0] } : { local: tidy(text) };
}

// Material yang tidak ditemukan: nama mirip (typo) dari master pabrik, paling dekat dulu
function didYouMean(raw) {
  const q = norm(String(raw).split(/\s*·\s*/)[0]);
  if (q.length < 3) return [];
  // R20: hanya nama yang angkanya sama (nearName)
  const names = [...new Set((M.materials || []).map(x => x.name))];
  return names
    .map(n => ({ n, d: nearName(q, n) }))
    .filter(x => x.d > 0)
    .sort((x, y) => x.d - y.d || x.n.localeCompare(y.n))
    .slice(0, 3)
    .map(x => x.n);
}

// R16 (21 Okt 2026, permintaan user): titik tengah sulit diketik. Tanpa "·", teks dibaca sebagai NAMA MASTER + THICKNESS bila
// bagian depannya persis nama material yang ada (terpanjang dulu) dan sisanya mirip thickness:
//   dengan pemisah ". - | / , ; :"  -> sisanya cukup berisi angka   ("honeylon mesh . 1,5 mm", "honeylon mesh - 44 inch")
//   tanpa pemisah                   -> sisanya angka + satuan      ("honeylon mesh 1,5mm"; "HONEYLON MESH 2" tetap nama)
// Nama yang cocok persis (mis. "SM-300 (COOL MELT)") selalu menang. Hasil -> "NAMA · THICKNESS" (isian ditulis ulang).
function looksThick(text, explicit) {
  const t = canonThickness(text);
  if (!/\d/.test(t) || /\d\.\d+\.\d/.test(t)) return false;         // "1.2.5" bukan angka
  return explicit || /\d\s*(MM|CM|UM)\b|\d"/.test(t);
}

function altSplit(raw) {
  if (raw.includes('·')) return null;
  const nr = norm(raw);
  const names = [...new Set((M.materials || []).map(x => x.name))].sort((a, b) => norm(b).length - norm(a).length);
  if (names.some(n => norm(n) === nr)) return null;                   // nama persis
  for (const n of names) {
    const nn = norm(n);
    if (!nn || !nr.startsWith(nn)) continue;
    const rest = nr.slice(nn.length);
    if (!/^[\s.\-|\/,;:]/.test(rest)) continue;                         // nama lain yang lebih panjang ("honeylon meshx ...")
    const sep = /^\s*[.\-|\/,;:]+\s*/.exec(rest);
    const dotNumber = /^\.\d/.test(rest);                              // "NAMA.5mm" = 0.5, bukan pemisah
    const explicit = !!sep && !dotNumber;
    const body = (explicit ? rest.slice(sep[0].length) : rest).trim();
    if (body && looksThick(body, explicit)) return `${n}${SEP}${canonThickness(body)}`;
  }
  return null;
}

// Material baru (tidak ada di master) ditulis "NAMA . THICKNESS" / "NAMA - THICKNESS" (pemisah berspasi): pisahkan untuk modal
function splitNewName(raw) {
  const m = /^(.*\S)\s+[.\-|\/]\s+(\S.*)$/.exec(raw);
  return m && looksThick(m[2], true) ? { name: m[1], thickness: canonThickness(m[2]) } : null;
}

// R19: nama di kolom Material -> material unik. "NAMA (UOM)" memilih di antara nama yang sama beda UoM.
function resolveName(raw) {
  const key = norm(raw);
  const byLabel = MATS.filter(m => norm(m.label) === key);
  if (byLabel.length === 1) return { m: byLabel[0] };
  const byName = MATS.filter(m => norm(m.name) === key);
  if (byName.length === 1) return { m: byName[0] };
  if (byName.length > 1) {
    return { error: `Several materials are named "${raw}" (different UoM): ${byName.map(m => m.label).join(' / ')}. Pick one from the list.` };
  }
  // R20: hanya beda spasi / tanda baca = material itu (PU-LEATHER -> PU LEATHER), tanpa bertanya
  const t = tightKey(raw);
  const byTight = t ? MATS.filter(m => tightKey(m.name) === t || tightKey(m.label) === t) : [];
  if (byTight.length === 1) return { m: byTight[0] };
  if (byTight.length > 1) {
    return { error: `Several materials match "${raw}" (different UoM): ${byTight.map(m => `${m.name} (${m.uom})`).join(' / ')}. Pick one from the list.` };
  }
  return null;
}

// Material (kolom Material) + dimension (kolom Dimension) -> { mat: { material_id, name, label, uom, thickness, isNew, is_process },
//   split? } (split = ketikan lama "NAMA · DIMENSION": isi kedua kolom ditulis ulang). R20: Material Code tidak dibaca di sini.
//   Tidak ketemu -> { error, notFound: { name, thickness } } (tombol "+ New material"). R20 bagian 3: Dimension (None) = tanpa
//   dimension; Dimension belum diisi sama sekali = default material (varian terbanyak).
function resolveMaterial(text, dimText) {
  const raw = tidy(text);
  if (!raw) return { error: 'Material is required.' };
  // R20: Material Code bukan nama material (jangan sampai didaftarkan sebagai material baru)
  const code = (M.variants || []).find(v => norm(v.code) === norm(raw));
  if (code) return { error: `${code.code} is a Material Code (${code.material_name}). Type the material name here; Material Codes are entered with Register.` };
  // ketikan lama: "NAMA · DIMENSION" atau tanpa titik tengah ("NAMA . 1,5 mm", "NAMA 1,5mm")
  let nameText = raw;
  let dim = dimText;
  let split = false;
  if (!resolveName(raw)) {
    const alt = raw.includes('·') ? raw : altSplit(raw);
    if (alt) {
      const parts = alt.split(/\s*·\s*/);
      if (resolveName(parts[0])) {
        nameText = parts[0];
        dim = parts.slice(1).join(' ');
        split = true;
      }
    }
  }
  const r = resolveName(nameText);
  if (r && r.error) return { error: r.error };
  if (!r) {
    const parts = raw.split(/\s*·\s*/);
    const nw = parts.length > 1 ? null : splitNewName(raw);
    const nfName = nw ? nw.name : tidy(parts[0]);
    const nfThick = nw ? nw.thickness : (parts.length > 1 ? canonThickness(parts.slice(1).join(' ')) : canonThickness(dimText));
    lastNotFound = { name: nfName, thickness: nfThick };
    // pesan (termasuk "Did you mean", pemindaian seluruh master) baru dihitung saat dibaca: sync isian tidak menampilkannya
    return {
      notFound: { name: nfName, thickness: nfThick },
      get error() {
        const guess = didYouMean(nw ? nw.name : raw);
        const how = M.canAddMaterial
          ? 'Check the spelling, or click "+ New material" to add it.'
          : 'Check the spelling, or ask Vendor Specsheet to add it to Master Material.';
        return `Material "${raw}" is not in this factory's Master Material (or INACTIVE).`
          + (guess.length ? ` Did you mean: ${guess.join(' / ')}?` : '') + ` ${how}`;
      },
    };
  }
  const m = r.m;
  const d = canonThickness(dim);
  const dims = m.dims.map(x => x.thickness);
  const base = { material_id: m.material_id, name: m.name, label: m.label, uom: m.uom, is_process: m.is_process };
  if (d) {
    const hit = dims.find(t => thickKey(t) === norm(d));
    return { mat: Object.assign(base, { thickness: hit !== undefined ? hit : d, isNew: hit === undefined && !m.is_process }), split };
  }
  const none = !!tidy(dim);                    // "(None)" / "." diketik = tanpa dimension; kosong = default
  const t = none ? '' : defaultDim(m.material_id);
  return { mat: Object.assign(base, { thickness: t, isNew: !!t && !dims.includes(t) && !m.is_process }), split };
}

function resolveSupplier(text) {
  const raw = tidy(text);
  if (!raw) return { id: null };
  const s = (M.suppliers || []).find(x => norm(x.name) === norm(raw));
  return s ? { id: s.id } : { error: `Supplier "${raw}" is not in Master Supplier (or inactive).` };
}

function linksOf(materialId) {
  return (M.links || []).filter(l => l.material_id === materialId);
}

// Supplier utama, atau satu-satunya supplier aktif material ini
function defaultSupplier(materialId) {
  const active = linksOf(materialId).filter(l => l.status !== 'INACTIVE');
  const pref = active.find(l => l.is_preferred) || (active.length === 1 ? active[0] : null);
  if (!pref) return '';
  const s = (M.suppliers || []).find(x => x.id === pref.supplier_id);
  return s ? s.name : '';
}

// Datalist supplier per material: supplier terdaftar dulu (utama paling atas), link INACTIVE tidak ditawarkan
function supplierListId(materialId) {
  const id = `dlSup-${materialId || 'all'}`;
  if (document.getElementById(id)) return id;
  const links = materialId ? linksOf(materialId) : [];
  const byId = {};
  links.forEach(l => { byId[l.supplier_id] = l; });
  const linked = [];
  const others = [];
  (M.suppliers || []).forEach(s => {
    const l = byId[s.id];
    if (l && l.status === 'INACTIVE') return;
    (l ? linked : others).push({ s, l });
  });
  linked.sort((a, b) => (b.l.is_preferred ? 1 : 0) - (a.l.is_preferred ? 1 : 0) || a.s.name.localeCompare(b.s.name));
  const dl = el('datalist');
  dl.id = id;
  linked.concat(others).forEach(({ s, l }) => {
    const o = el('option');
    o.value = s.name;
    o.textContent = l ? (l.is_preferred ? 'main supplier of this material' : 'added to this material')
      : 'other supplier (will be linked)';
    dl.appendChild(o);
  });
  $('dlSuppliers').appendChild(dl);
  return id;
}

function fillDatalists() {
  const fill = (dl, items) => {
    dl.innerHTML = '';
    items.forEach(([v, t]) => {
      const o = el('option');
      o.value = v;
      if (t) o.textContent = t;
      dl.appendChild(o);
    });
  };
  fill($('dlComponents'), (M.components || []).map(c => [compLabel(c)]));
  fill($('dlColors'), (M.colors || []).map(c => [c]));
  $('dlSuppliers').innerHTML = '';
}

// ---------------------------------------------------------------- aksi
function send(type, data) {
  localMsg = null;
  showMessage();
  seq = Math.max(Date.now(), seq + 1);         // naik terus, juga setelah widget dimuat ulang
  queue.push(Object.assign({ type, seq }, data));
  if (queue.length === 1) setTimeout(flush, 0);  // setelah pemanggil mencatat nilai optimistic
}

function flush() {
  clearTimeout(retryTimer);
  if (!queue.length) return;
  appsmith.updateModel({ action: queue[0] });
  appsmith.triggerEvent('onAction');
  retryTimer = setTimeout(flush, 5000);        // event hilang (model di-reset) -> kirim ulang
}

// Balasan BomCtrl: model.doneSeq = seq aksi terakhir yang selesai (berhasil atau gagal) dan datanya sudah dimuat ulang
function onAck(m) {
  const done = Number((m || {}).doneSeq) || 0;
  const before = queue.length;
  while (queue.length && queue[0].seq <= done) queue.shift();
  if (queue.length === before) return;
  if (queue.length) {
    flush();
  } else {
    clearTimeout(retryTimer);
    optimistic = {};
  }
}

function fail(input, text) {
  if (input) input.classList.add('invalid');
  localMsg = { type: 'error', text };
  showMessage();
}

function showMessage() {
  const m = localMsg || M.message;
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

// Input sel yang disimpan saat berubah (change = Enter / Tab / klik di luar).
// opts.multiline: kotak teks yang membungkus · opts.keepLines: Shift/Alt+Enter = baris baru (Remarks)
// · opts.suggest: daftar saran sendiri (warna)
function cellInput(key, value, opts) {
  const multi = !!(opts.multiline || opts.keepLines);
  const i = el(multi ? 'textarea' : 'input', 'cell');
  if (multi) {
    i.rows = 1;
    i.spellcheck = false;
    i.addEventListener('input', () => autosize(i));
  } else {
    i.type = 'text';
  }
  i.autocomplete = 'off';
  i.value = value || '';
  const clean = opts.keepLines ? tidyLines : tidy;
  i.dataset.key = key;
  i.dataset.orig = i.value;
  if (opts.col) i.dataset.col = opts.col;
  if (opts.list) i.setAttribute('list', opts.list);
  if (opts.placeholder) i.placeholder = opts.placeholder;
  if (opts.title) i.title = opts.title;
  if (opts.label) i.setAttribute('aria-label', opts.label);
  i.addEventListener('input', () => i.classList.remove('invalid'));
  if (opts.onCommit) {
    // change + blur: nilai yang dipulihkan setelah render ulang tidak memicu change, jadi blur ikut menyimpan
    const commit = () => {
      if (rendering || !i.isConnected) return; // dibuang / dipindah render ulang: jangan simpan ketikan setengah jadi
      if (clean(i.value) === clean(i.dataset.orig)) return;
      const before = seq;
      opts.onCommit(i);
      if (seq !== before) optimistic[key] = i.value;
    };
    i.addEventListener('change', commit);
    i.addEventListener('blur', commit);
    i._commit = commit;
  }
  if (opts.dropdown) {                         // R20 Dimension: daftar penuh saat diklik, dibandingkan dalam bentuk baku
    i._sugFull = true;
    i._sugKey = thickKey;
    i._commitOnPick = !!(opts.onCommit && opts.col);   // R20 bagian 6: sel grid: pilih dari daftar = langsung simpan
    i.classList.add('dd');
    i.addEventListener('focus', () => { if (!rendering && i.value === NONE) i.select(); });   // R20 bagian 3
  }
  if (opts.suggest) attachSuggest(i, opts.suggest, opts.onPick);
  i.addEventListener('keydown', e => {
    if (e.defaultPrevented) return;            // sudah ditangani daftar saran
    if (e.key === 'Escape') {
      i.value = i.dataset.orig;
      i.classList.remove('invalid');
      autosize(i);
      i.blur();
    } else if (e.key === 'Enter' && opts.keepLines && (e.shiftKey || e.altKey)) {
      if (e.altKey) {                          // Alt+Enter seperti Excel
        e.preventDefault();
        const p = i.selectionStart;
        i.value = `${i.value.slice(0, p)}\n${i.value.slice(i.selectionEnd)}`;
        i.setSelectionRange(p + 1, p + 1);
        autosize(i);
      }                                        // Shift+Enter: baris baru bawaan kotak teks
    } else if (e.key === 'Enter' && multi && !opts.col) {
      e.preventDefault();                      // baris tambah/sub: Enter ditangani formRow
    } else if (e.key === 'Enter' && opts.col) {
      e.preventDefault();
      moveDown(i);
    }
  });
  return i;
}

// ---------------------------------------------------------------- daftar saran (warna)
let sugTarget = null;
let sugItems = [];
let sugIndex = -1;
let sugWasFull = false;     // R20 bagian 6: daftar terakhir dibuka penuh (klik) atau disaring (mengetik)

function hideSuggest() {
  sugTarget = null;
  sugItems = [];
  sugIndex = -1;
  $('suggest').hidden = true;
}

// R20 bagian 6: daftar mengikuti kotaknya (dipanggil juga saat grid digulir); kotak keluar dari area grid -> daftar ditutup
function placeSuggest() {
  const box = $('suggest');
  const input = sugTarget;
  if (box.hidden || !input) return;
  if (!input.isConnected) {
    hideSuggest();
    return;
  }
  const r = input.getBoundingClientRect();
  const s = $('scroll').getBoundingClientRect();
  if (input.closest('#scroll') && (r.bottom < s.top || r.top > s.bottom || r.right < s.left || r.left > s.right)) {
    hideSuggest();
    return;
  }
  box.style.left = `${Math.max(0, Math.min(r.left, window.innerWidth - 340))}px`;
  box.style.minWidth = `${Math.max(r.width, 220)}px`;
  const below = window.innerHeight - r.bottom;
  if (below < box.offsetHeight + 4 && r.top > box.offsetHeight) {
    box.style.top = `${r.top - box.offsetHeight - 2}px`;
  } else {
    box.style.top = `${r.bottom + 2}px`;
  }
}

// R19: item = teks (warna) atau { value, detail } (material / dimension: detail tampil kecil di bawah, teks membungkus)
const sugValue = c => (typeof c === 'string' ? c : c.value);

// R20: input._sugFull (Dimension) = klik / fokus menampilkan seluruh dimension material itu seperti dropdown (yang terisi
// ditandai, juga saat mengetik); saat mengetik daftar disaring dan dimension material lain (item.other) ikut di bawah judul
// "Other materials".
// input._sugKey = kunci pembanding (Dimension: bentuk baku, "1,2mm" cocok dengan "1.2 MM").
function showSuggest(input, source, focus) {
  const kf = input._sugKey || norm;
  const key = kf(input.value);
  const all = typeof source === 'function' ? source() : (source || []);
  const full = !!(focus && input._sugFull);
  let hits;
  const fk = c => (c.none ? 'none' : kf(sugValue(c)));   // R20 bagian 3: (None) dicari dengan "none"
  const showAll = full || (!key && input._sugFull);   // R20 bagian 7: Dimension = daftar penuh termasuk "Other materials"
  if (showAll) {
    hits = all;
  } else {
    const rank = c => (c.other ? 2 : 0) + (fk(c).startsWith(key) ? 0 : 1);
    hits = all.filter(c => (input._sugFull || kf(sugValue(c)) !== key) && (!key || fk(c).includes(key)));
    hits.sort((a, b) => rank(a) - rank(b));
  }
  sugItems = hits.slice(0, showAll ? 200 : 12);
  sugTarget = input;
  sugIndex = -1;
  sugWasFull = full;
  const box = $('suggest');
  box.innerHTML = '';
  if (!sugItems.length) {
    box.hidden = true;
    return;
  }
  sugItems.forEach((c, n) => {
    if (c.other && (n === 0 || !sugItems[n - 1].other)) box.appendChild(el('div', 'opt-head', 'Other materials'));
    const o = el('div', 'opt' + (input._sugFull && (key || c.none) && kf(sugValue(c)) === key ? ' cur' : '')
      + (c.none ? ' none' : ''), sugValue(c));
    if (typeof c !== 'string' && c.detail) o.appendChild(el('span', 'opt-detail', c.detail));
    o.addEventListener('mousedown', e => {     // mousedown: sebelum kotak teks kehilangan fokus
      e.preventDefault();
      pickSuggest(n);
    });
    box.appendChild(o);
  });
  box.hidden = false;
  placeSuggest();
}

function markSuggest() {
  Array.from($('suggest').querySelectorAll('.opt')).forEach((o, n) => o.classList.toggle('on', n === sugIndex));
}

function pickSuggest(n) {
  const input = sugTarget;
  if (!input || !sugItems[n]) return;
  input.value = sugValue(sugItems[n]);
  autosize(input);
  hideSuggest();
  input.classList.remove('invalid');
  if (input._onPick) input._onPick();          // R19: baris tambah / sub: isi UoM, dimension, supplier
  if (input._commitOnPick && input._commit) input._commit();   // R20 bagian 6: Dimension di grid langsung disimpan
}

function attachSuggest(input, source, onPick) {
  input._onPick = onPick || null;
  input._sugSrc = source;
  input.addEventListener('focus', () => { if (!rendering) showSuggest(input, source, true); });
  input.addEventListener('mousedown', () => {    // R20 Dimension: klik lagi pada kotak yang sudah fokus = buka / tutup daftar
    if (!input._sugFull || document.activeElement !== input) return;
    if ($('suggest').hidden || sugTarget !== input) showSuggest(input, source, true);
    else hideSuggest();
  });
  input.addEventListener('input', () => showSuggest(input, source));
  input.addEventListener('blur', () => { if (!rendering && sugTarget === input) hideSuggest(); });
  input.addEventListener('keydown', e => {
    if (sugTarget !== input || $('suggest').hidden) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const n = sugItems.length;
      sugIndex = e.key === 'ArrowDown' ? (sugIndex + 1) % n : (sugIndex - 1 + n) % n;
      markSuggest();
    } else if (e.key === 'Enter' && sugIndex >= 0) {
      if (!input.dataset.col) {                      // R19: baris tambah / sub: Enter memilih saran saja (belum menyimpan)
        e.preventDefault();
        e.sugPicked = true;
      }
      pickSuggest(sugIndex);                   // sel grid: Enter tetap lanjut, simpan & pindah ke baris berikutnya
    } else if (e.key === 'Escape') {
      e.preventDefault();
      hideSuggest();
    }
  });
}

// Enter di sel -> simpan (blur) lalu pindah ke sel yang sama di baris berikutnya
function moveDown(input) {
  const inputs = Array.from(document.querySelectorAll(`#tbody .cell[data-col="${input.dataset.col}"]`));
  const next = inputs[inputs.indexOf(input) + 1];
  if (next) {
    next.focus();
    next.select();
  } else {
    input.blur();
  }
}

// R16: material tidak ketemu -> pesan + tombol "+ New material" di sel input itu (hanya role yang boleh menambah material)
function materialMissing(key, input, r) {
  fail(input, r.error);
  if (!r.notFound || !M.canAddMaterial) return;
  nfFor = { key, name: r.notFound.name, thick: r.notFound.thickness };
  const cell = input.closest('td');
  if (!cell) return;
  const old = cell.querySelector('.newmat');
  if (old) old.remove();
  cell.appendChild(newMaterialBox(key));
}

function newMaterialBox(key) {
  const box = el('div', 'newmat');
  box.appendChild(el('span', 'hint', 'Not in Master Material.'));
  const b = el('button', 'link newmat-btn', '+ New material');
  b.type = 'button';
  b.disabled = !!M.busy;
  b.title = `Add "${nfFor ? nfFor.name : ''}" to Master Material. This line continues automatically after saving.`;
  b.addEventListener('mousedown', e => e.preventDefault());   // jangan blur input dulu (blur = simpan ulang)
  b.addEventListener('click', () => openNewFor(key));
  box.appendChild(b);
  return box;
}

function openNewFor(key) {
  if (!nfFor || nfFor.key !== key) return;
  awaitNew = { key, thick: nfFor.thick };
  lastNotFound = null;
  send('newMaterial', { name: nfFor.name });
}

// Isian Material diubah lagi -> tombol "+ New material" baris itu hilang
function clearMissing(key, input) {
  if (!nfFor || nfFor.key !== key) return;
  nfFor = null;
  const box = input.closest('td') && input.closest('td').querySelector('.newmat');
  if (box) box.remove();
}

// R16: material baru tersimpan di modal (BomCtrl.matAdded) -> ulangi aksi baris yang menunggu dengan nama yang disimpan
function resumeAfterNewMaterial() {
  const a = M.matAdded || {};
  if (a.key === lastMatAdded) return;
  lastMatAdded = a.key;
  const w = awaitNew;
  awaitNew = null;
  if (!w || !a.name) return;
  nfFor = null;
  // R19: nama ke kolom Material, dimension yang diketik ke kolom Dimension
  const fill = (f, state) => {
    f.mat.value = a.name;
    state.mat = a.name;
    if (w.thick && !tidy(f.thk.value)) {
      f.thk.value = w.thick;
      state.thk = w.thick;
    }
    f.mat.dispatchEvent(new Event('change'));   // UoM, dimension, supplier utama
  };
  if (w.key === 'add:mat' && curAdd) {
    fill(curAdd, addState);
    submitAdd(curAdd);
  } else if (w.key === 'sub:mat' && curSub) {
    fill(curSub.f, subState);
    submitSub(curSub.parent, curSub.f);
  } else if (w.key.startsWith('mat:')) {
    const line = (M.lines || []).find(l => `mat:${l.id}` === w.key);
    const i = document.querySelector(`#tbody [data-key="${CSS.escape(w.key)}"]`);
    if (line && i) {
      i.value = a.name;
      const before = seq;
      commitMaterial(line, i, w.thick);
      if (seq !== before) optimistic[w.key] = i.value;   // tampil sampai DB membalas (sama dengan cellInput)
    }
  }
}

// R19: nama material diganti di baris. Dimension: ketikan lama "NAMA · DIMENSION" -> dari situ; material sama -> tidak berubah;
// dimension baris ini terdaftar juga di material baru -> tetap; R20 bagian 3: selain itu default material baru (varian terbanyak).
function commitMaterial(line, input, newThick) {
  const key = `mat:${line.id}`;
  if (newThick !== undefined) {                // material baru dari modal: dimension yang diketik / dimension baris
    const r0 = resolveMaterial(input.value, newThick || line.thickness || '');
    if (r0.mat) {
      input.dataset.orig = input.value;
      return send('replaceMaterial', { line_id: line.id, material_id: r0.mat.material_id, thickness: r0.mat.thickness || '' });
    }
  }
  const r = resolveMaterial(input.value, '');
  const base = r.mat || null;
  if (!base) {
    if (r.notFound && !r.notFound.thickness) r.notFound.thickness = line.thickness || '';   // material baru: dimension baris ini
    return materialMissing(key, input, r);
  }
  const m = MAT_BY_ID[base.material_id];
  let thickness;
  if (r.mat && r.split) {
    thickness = r.mat.thickness || '';
  } else if (base.material_id === line.material_id) {   // nama sama: dimension diubah di kolom Dimension
    input.value = input.dataset.orig;
    return;
  } else {
    thickness = dimFor(base.material_id, line.thickness);
  }
  if (matKey(base.material_id, thickness) === matKey(line.material_id, line.thickness)) {
    input.value = input.dataset.orig;
    return;
  }
  input.value = m ? m.label : input.value;
  input.dataset.orig = input.value;
  send('replaceMaterial', { line_id: line.id, material_id: base.material_id, thickness });
}

// R19: dimension diketik di kolom Dimension baris = Ganti material (material sama, dimension lain).
// R20 bagian 3: kotak dikosongkan / (None) = tanpa dimension
function commitDimension(line, input) {
  const materialId = line.material_id;
  const d = canonThickness(input.value);
  if (thickKey(d) === thickKey(line.thickness)) {
    input.value = input.dataset.orig;
    return;
  }
  const m = MAT_BY_ID[materialId];
  const hit = m ? m.dims.map(x => x.thickness).find(t => thickKey(t) === thickKey(d)) : undefined;
  const thickness = hit !== undefined ? hit : d;
  input.value = dimText(thickness);
  input.dataset.orig = input.value;
  send('replaceMaterial', { line_id: line.id, material_id: materialId, thickness });
}

// R19: ganti komponen BARIS induk ini saja (+ subkomponennya; koreksi user 27 Okt 2026) ke komponen master lain
function commitComponent(line, input) {
  if (!input.isConnected || compEdit !== line.id) return;   // sudah dikirim (Enter) / dibatalkan
  const raw = tidy(input.value);
  if (!raw || raw === tidy(input.dataset.orig)) {
    compEdit = null;
    return render(M, true);
  }
  const c = resolveComponent(raw);
  if (c.error) return fail(input, c.error);
  if (!c.comp) return fail(input, `"${raw}" is not in the component master. Pick a master component from the list.`);
  if (c.comp.id === line.component_id) {
    compEdit = null;
    return render(M, true);
  }
  compEdit = null;
  send('changeComponent', { line_id: line.id, component_id: c.comp.id });
  render(M, true);
}

function commitSupplier(line, input) {
  const r = resolveSupplier(input.value);
  if (r.error) return fail(input, r.error);
  if ((r.id || null) === (line.supplier_id || null)) {
    input.value = input.dataset.orig;
    return;
  }
  input.dataset.orig = input.value;
  send('setSupplier', { line_id: line.id, supplier_id: r.id || '' });
}

function commitProcess(line, input) {
  input.dataset.orig = input.value;
  send('setProcess', { line_id: line.id, process: tidyLines(input.value) });
}

// R20: sel = teks warna saja (Material Code hanya lewat Register). Warna terdaftar -> DB menyambungkan kodenya.
function commitCell(line, article, input) {
  const color = cleanColor(input.value);        // R20: bentuk baku seperti DB (black / white -> BLACK/WHITE)
  input.dataset.orig = input.value;
  send('setCell', { line_id: line.id, article_id: article.id, color });
}

// Warna terdaftar untuk baris ini dulu, lalu warna se-season
function colorSource(line) {
  return () => {
    const own = variantsOf(line.material_id, line.thickness).map(v => v.color);
    const seen = new Set(own.map(colorKey));
    return own.concat((M.colors || []).filter(c => !seen.has(colorKey(c)) && seen.add(colorKey(c))));
  };
}

function armDrop(btn, art) {
  if (dropArmed === art.id) {
    clearTimeout(dropTimer);
    dropArmed = null;
    send('dropArticle', { article_id: art.id });
    return;
  }
  dropArmed = art.id;
  btn.classList.add('confirm');
  btn.textContent = 'Drop?';
  clearTimeout(dropTimer);
  dropTimer = setTimeout(() => {
    dropArmed = null;
    const b = document.querySelector(`#thead .drop[data-art="${art.id}"]`);
    if (b) {
      b.classList.remove('confirm');
      b.textContent = '✕';
    }
  }, 3000);
}

// Hapus baris: klik pertama -> "Yakin?" (3 detik), klik kedua -> kirim. Baris induk ikut menghapus subkomponennya.
function armDelete(btn, line, hasSubs) {
  if (delArmed === line.id) {
    clearTimeout(delTimer);
    delArmed = null;
    send('deleteLine', { line_id: line.id });
    return;
  }
  delArmed = line.id;
  btn.classList.add('confirm');
  btn.textContent = line.undo_replace ? 'Sure?' : hasSubs ? 'Delete + sub?' : 'Sure?';
  clearTimeout(delTimer);
  delTimer = setTimeout(() => {
    delArmed = null;
    const b = document.querySelector(`#tbody .link.danger[data-line="${line.id}"]`);
    if (b) {
      b.classList.remove('confirm');
      b.textContent = line.undo_replace ? 'Undo replace' : 'Delete';
    }
  }, 3000);
}

// ---------------------------------------------------------------- baris tambah & subkomponen
// Input yang dipakai baris tambah/sub: komponen/nama, No., material, supplier, remarks
function formInputs(prefix, state, isSub) {
  const f = {};
  const mk = (name, opts) => {
    const i = cellInput(`${prefix}:${name}`, state[name] || '', opts);
    i.addEventListener('input', () => { state[name] = i.value; });
    f[name] = i;
    return i;
  };
  if (isSub) {
    mk('name', { placeholder: 'Subcomponent name', label: 'Subcomponent name' });
  } else {
    mk('comp', { list: 'dlComponents', placeholder: 'Type a component…', label: 'Component' });
    mk('no', { placeholder: 'No.', label: 'Local component no.', title: 'Only for a new component that is not in the master' });
  }
  // R19: Material = nama, Dimension di kolom sendiri
  const curMat = () => { const r = resolveName(tidy(f.mat.value)); return r && r.m ? r.m.material_id : null; };
  mk('mat', { multiline: true, suggest: materialSuggest, onPick: () => syncMaterial(), placeholder: 'Material name…', label: 'Material' });
  f.mat.addEventListener('input', () => clearMissing(`${prefix}:mat`, f.mat));
  mk('thk', { multiline: true, dropdown: true, suggest: dimensionSuggest(curMat), onPick: () => syncDim(), placeholder: 'Dimension…',
    label: 'Dimension',
    title: 'Click to pick a dimension of this material, or type: dimensions of other materials are suggested too (a new dimension is allowed)' });
  mk('sup', { list: supplierListId(null), placeholder: 'Supplier…', label: 'Supplier' });
  mk('rem', { placeholder: 'Remarks', label: 'Remarks', keepLines: true, title: 'Shift+Enter / Alt+Enter = new line' });
  f.uom = el('span', 'ro none', '-');
  f.thkNote = el('span', 'hint');

  // R19: dimension baru / Process -> catatan kecil di bawah kolom Dimension
  const syncDim = () => {
    const r = resolveMaterial(f.mat.value, f.thk.value);
    const mat = r.mat || null;
    // dibakukan seperti DB ("1,4mm" -> "1.4 MM"); R20 bagian 3: kosong = default material, tanpa dimension tampil (None)
    if (mat && f.thk.value !== dimText(mat.thickness)) {
      f.thk.value = dimText(mat.thickness);
      state.thk = f.thk.value;
    }
    f.thkNote.textContent = mat && mat.is_process ? 'Process: no Material Code'
      : mat && mat.isNew ? 'new dimension (cells stay yellow until the codes are registered)' : '';
    autosize(f.thk);
  };
  f.thk.addEventListener('change', () => {
    if (!tidy(f.thk.value) && resolveName(tidy(f.mat.value))) {   // R20 bagian 3: dikosongkan = (None)
      f.thk.value = NONE;
      state.thk = NONE;
    }
    syncDim();
  });
  const syncMaterial = () => {
    const r = resolveMaterial(f.mat.value, f.thk.value);
    const named = resolveName(tidy(f.mat.value));
    const mat = r.mat || (named && named.m ? named.m : null);
    f.uom.textContent = mat ? mat.uom : '-';
    const setThk = v => { f.thk.value = v; state.thk = v; };
    if (r.mat && r.split) {    // "NAMA · DIMENSION" diketik -> nama ke Material, dimension ke Dimension
      f.mat.value = r.mat.label;
      state.mat = f.mat.value;
      setThk(r.mat.thickness || '');
    } else if (mat && state.matId && state.matId !== mat.material_id) {
      // R19 (revisi user 27 Okt 2026): material diganti ke material LAIN -> Dimension selalu mengikuti material baru.
      // R20 bagian 3: terdaftar juga di material baru = tetap, selain itu default material baru (varian terbanyak / (None))
      setThk(dimText(dimFor(mat.material_id, f.thk.value)));
    } else if (mat && !tidy(f.thk.value)) {    // material pertama dipilih: R20 bagian 3 = default (varian terbanyak / (None))
      setThk(dimText(defaultDim(mat.material_id)));
    }
    if (mat) state.matId = mat.material_id;
    if (named && named.m && f.mat.value !== named.m.label) {   // huruf besar / "(UOM)" seperti master
      f.mat.value = named.m.label;
      state.mat = f.mat.value;
    }
    autosize(f.mat);
    syncDim();
    f.sup.setAttribute('list', supplierListId(mat ? mat.material_id : null));
    if (mat && !tidy(f.sup.value)) {
      f.sup.value = defaultSupplier(mat.material_id);
      state.sup = f.sup.value;
    }
  };
  f.mat.addEventListener('change', syncMaterial);
  if (state.mat) syncMaterial();

  if (!isSub) {
    const syncLocal = () => {
      const r = resolveComponent(f.comp.value);
      f.no.disabled = !r.local;
      if (!r.local) {
        f.no.value = '';
        state.no = '';
      }
    };
    f.comp.addEventListener('input', syncLocal);
    f.comp.addEventListener('change', syncLocal);
    syncLocal();
  }
  return f;
}

function submitAdd(f) {
  Object.values(f).forEach(i => i.classList && i.classList.remove('invalid'));
  const c = resolveComponent(f.comp.value);
  if (c.error) return fail(f.comp, c.error);
  const data = { component_id: '', local_no: '', local_name: '' };
  if (c.comp) {
    data.component_id = c.comp.id;
  } else {
    const no = tidy(f.no.value);
    if (!/^\d+$/.test(no)) return fail(f.no, `"${c.local}" is not in the component master. Fill in No. (a number) for this local component.`);
    if (Number(no) % 10 === 0) return fail(f.no, 'A local component no. cannot be a multiple of 10.');
    data.local_no = no;
    data.local_name = c.local;
  }
  const m = resolveMaterial(f.mat.value, f.thk.value);
  if (m.error) return materialMissing('add:mat', f.mat, m);
  const s = resolveSupplier(f.sup.value);
  if (s.error) return fail(f.sup, s.error);
  send('addLine', Object.assign(data, {
    material_id: m.mat.material_id, thickness: m.mat.thickness || '', supplier_id: s.id || '',
    process: tidyLines(f.rem.value), fill_color: '',
  }));
}

function submitSub(parent, f) {
  Object.values(f).forEach(i => i.classList && i.classList.remove('invalid'));
  if (!tidy(f.name.value)) return fail(f.name, 'Subcomponent name is required.');
  const m = resolveMaterial(f.mat.value, f.thk.value);
  if (m.error) return materialMissing('sub:mat', f.mat, m);
  const s = resolveSupplier(f.sup.value);
  if (s.error) return fail(f.sup, s.error);
  send('addSub', {
    parent_id: parent.id, sub_name: tidy(f.name.value), material_id: m.mat.material_id,
    thickness: m.mat.thickness || '', supplier_id: s.id || '', process: tidyLines(f.rem.value),
  });
}

// ---------------------------------------------------------------- render
function parseObj(v) {
  if (typeof v !== 'string') return v || {};
  try { return JSON.parse(v || '{}'); } catch (e) { return {}; }
}

function td(cls, child) {
  const c = el('td', cls);
  if (child !== undefined) c.appendChild(typeof child === 'string' ? el('span', 'ro', child) : child);
  return c;
}

function supplierCell(line, editable) {
  const c = el('td', 'c-sup');
  if (editable) {
    c.appendChild(cellInput(`sup:${line.id}`, line.supplier_name, {
      col: 'sup', list: supplierListId(line.material_id), placeholder: 'Supplier…', label: 'Supplier',
      onCommit: i => commitSupplier(line, i),
    }));
  } else {
    c.appendChild(el('span', 'ro' + (line.supplier_name ? '' : ' none'), line.supplier_name || '-'));
  }
  if (line.supplier_id && (line.link_status === 'INACTIVE' || line.supplier_status === 'INACTIVE')) {
    const b = el('span', 'badge inactive', '⚠ inactive');
    b.title = line.supplier_status === 'INACTIVE'
      ? 'This supplier is inactive in Master Supplier. Choose another supplier before publishing.'
      : 'This supplier is inactive for this material. Choose another supplier before publishing.';
    c.appendChild(b);
  }
  return c;
}

function materialCell(line, editable) {
  const c = el('td', 'c-mat');
  const label = nameLabel(line.material_id, line.material_name);
  const title = [line.uom, line.material_code].filter(x => x).join(' · ');
  if (editable) {
    const mi = cellInput(`mat:${line.id}`, label, {
      col: 'mat', multiline: true, suggest: materialSuggest, label: 'Material',
      title: `${title}. Type another material name to Replace Material. The dimension is set in the Dimension column.`,
      onCommit: i => commitMaterial(line, i),
    });
    mi.addEventListener('input', () => clearMissing(`mat:${line.id}`, mi));
    c.appendChild(mi);
  } else {
    const s = el('span', 'ro', label);
    s.title = title;
    c.appendChild(s);
  }
  if (line.material_status === 'INACTIVE') c.appendChild(el('span', 'badge inactive', '⚠ material INACTIVE'));
  if (line.is_process) {
    const b = el('span', 'badge proc', 'process');
    b.title = 'Process material: no Material Code; its price is a quotation per CBD.';
    c.appendChild(b);
  }
  if (editable && M.canAddMaterial && nfFor && nfFor.key === `mat:${line.id}`) c.appendChild(newMaterialBox(nfFor.key));
  if (editable && M.canAddMaterial && line.material_id) {
    const b = el('button', 'link mat-edit', 'Edit material');
    b.type = 'button';
    b.disabled = !!M.busy;
    b.title = 'Edit this material in Master Material (name, category, UoM, Process, status). Applies to every draft that uses it.';
    b.addEventListener('mousedown', e => e.preventDefault());   // jangan blur input dulu (blur = simpan ulang)
    b.addEventListener('click', () => send('editMaterial', { material_id: line.material_id }));
    c.appendChild(b);
  }
  return c;
}

// R19: kolom Dimension bisa diedit (saran dimension terdaftar material baris). R20 bagian 3: tanpa dimension tampil (None)
function dimensionCell(line, editable) {
  const c = el('td', 'c-thk');
  if (!editable) {
    c.appendChild(el('span', 'ro' + (line.thickness ? '' : ' none'), dimText(line.thickness)));
    return c;
  }
  const di = cellInput(`thk:${line.id}`, dimText(line.thickness), {
    col: 'thk', multiline: true, dropdown: true, label: 'Dimension',
    suggest: dimensionSuggest(() => line.material_id),
    title: 'Click to pick or type the dimension; (None) = no dimension (dimensions of other materials are suggested while typing). Changing it = Replace Material (same material, new dimension).',
    onCommit: i => commitDimension(line, i),
  });
  c.appendChild(di);
  return c;
}

function lineRow(line, arts, editable, hasSubs) {
  const tr = el('tr', line.is_sub ? 'sub' : '');
  tr.appendChild(td('c-no', String(line.display_no ?? '')));
  const comp = el('td', 'c-comp');
  if (editable && !line.is_sub && compEdit === line.id) {
    const ci = cellInput(`comp:${line.id}`, '', {
      list: 'dlComponents', placeholder: 'Type a master component…', label: 'New component',
      title: 'Only this line (with its subcomponents) moves to the chosen master component. Esc = cancel',
    });
    ci.addEventListener('keydown', e => {
      if (e.key === 'Enter') {
        e.preventDefault();
        commitComponent(line, ci);
      } else if (e.key === 'Escape') {
        compEdit = null;
        render(M, true);
      }
    });
    ci.addEventListener('change', () => { if (!rendering) commitComponent(line, ci); });
    ci.addEventListener('blur', () => setTimeout(() => {           // klik di luar tanpa isian = batal
      if (compEdit === line.id && ci.isConnected && !tidy(ci.value) && document.activeElement !== ci) {
        compEdit = null;
        render(M, true);
      }
    }, 200));
    comp.appendChild(ci);
    comp.appendChild(el('span', 'hint', `Now: ${line.display_no ?? ''} ${line.display_name || ''}. Enter = change, Esc = cancel.`));
  } else {
    const name = el('span', 'ro name', line.display_name || '');
    if (line.is_local) name.appendChild(el('span', 'local', 'local'));
    comp.appendChild(name);
    if (editable && !line.is_sub) {
      const b = el('button', 'link comp-change', 'Change');
      b.type = 'button';
      b.title = 'Change the component of this line (its subcomponents move too; other lines of the same component stay)';
      b.addEventListener('click', () => {
        compEdit = line.id;
        render(M, true);
        const i = document.querySelector(`#tbody [data-key="${CSS.escape(`comp:${line.id}`)}"]`);
        if (i) i.focus();
      });
      comp.appendChild(b);
    }
  }
  tr.appendChild(comp);
  tr.appendChild(materialCell(line, editable));
  tr.appendChild(supplierCell(line, editable));
  tr.appendChild(td('c-uom', line.uom || '-'));
  tr.appendChild(dimensionCell(line, editable));
  const rem = el('td', 'c-rem');
  if (editable) {
    rem.appendChild(cellInput(`rem:${line.id}`, line.process, {
      col: 'rem', placeholder: '', label: 'Remarks', keepLines: true,
      title: 'Shift+Enter / Alt+Enter = new line · Enter = save', onCommit: i => commitProcess(line, i),
    }));
  } else {
    rem.appendChild(el('span', 'ro lines' + (line.process ? '' : ' none'), line.process || '-'));
  }
  tr.appendChild(rem);
  if (editable) {
    const act = el('td', 'c-act');
    if (!line.is_sub) {
      const b = el('button', 'link', '+ Sub');
      b.type = 'button';
      b.title = 'Add a subcomponent below this line';
      b.addEventListener('click', () => {
        subParent = subParent === line.id ? null : line.id;
        subState = {};
        render(M, true);
        const first = document.querySelector('tr.subform input');
        if (first) first.focus();
      });
      act.appendChild(b);
    }
    // R11 (T58): baris hasil Ganti material -> "Batal ganti" (baris ini dihapus, material sebelumnya aktif lagi)
    const undo = !!line.undo_replace;
    const del = el('button', 'link danger', delArmed === line.id ? (undo ? 'Sure?' : hasSubs ? 'Delete + sub?' : 'Sure?')
      : (undo ? 'Undo replace' : 'Delete'));
    if (delArmed === line.id) del.classList.add('confirm');
    del.type = 'button';
    del.dataset.line = line.id;
    del.title = undo ? `Undo material replace: back to ${line.undo_material || 'the previous material'}${hasSubs ? ' (subcomponents move too)' : ''} (click twice)`
      : hasSubs ? 'Delete this line and its subcomponents (click twice)' : 'Delete this line (click twice)';
    del.addEventListener('click', () => armDelete(del, line, hasSubs));
    act.appendChild(del);
    tr.appendChild(act);
  }
  const cells = parseObj(line.cells);
  const codes = parseObj(line.cell_codes);
  arts.forEach(a => {
    const v = cells[a.id] || '';
    const code = codes[a.id] || '';
    const yellow = !!v && !code && !line.is_process;   // R19: material Process memang tanpa kode
    const c = el('td', 'c-art' + (yellow ? ' yellow' : ''));
    if (editable) {
      c.appendChild(cellInput(`cell:${line.id}:${a.id}`, v, {
        col: `art:${a.id}`, multiline: true, suggest: colorSource(line), label: `Warna ${a.code}`,
        title: 'Type a color. Empty = not used in this article. Material Codes are entered with Register.',
        onCommit: i => commitCell(line, a, i),
      }));
    } else {
      c.appendChild(el('span', 'ro' + (v ? '' : ' none'), v || '-'));
    }
    if (code) {
      c.appendChild(el('span', 'vcode', code));
    } else if (yellow) {
      const note = el('span', 'vcode warn', 'no Material Code');
      note.title = 'This color is not registered as a variant of this material + dimension. The specsheet cannot be published.';
      c.appendChild(note);
      // R20: warna terdaftar dengan kata sama tapi urutan lain (WHITE/BLACK vs BLACK/WHITE) -> saran saja, tidak diganti otomatis
      const words = colorWords(v);
      const twin = words && variantsOf(line.material_id, line.thickness)
        .find(x => colorWords(x.color) === words && colorKey(x.color) !== colorKey(v));
      if (twin && editable) {
        const t = el('button', 'link twin', `Did you mean ${twin.color}?`);
        t.type = 'button';
        t.title = `${twin.color} is registered for this material + dimension (code ${twin.code}). Click to use it; ignore if the color order is really different.`;
        t.addEventListener('click', () => send('setCell', { line_id: line.id, article_id: a.id, color: twin.color }));
        c.appendChild(t);
      }
      if (editable && M.canRegister) {
        const b = el('button', 'link reg', 'Register');
        b.type = 'button';
        b.title = `Register variant ${line.material_name} · ${line.thickness || 'no dimension'} · ${v}`;
        b.addEventListener('click', () => send('registerVariant', {
          line_id: line.id, article_id: a.id, material_id: line.material_id, material_name: line.material_name, uom: line.uom,
          thickness: line.thickness || '', color: v,
        }));
        c.appendChild(b);
      }
    }
    tr.appendChild(c);
  });
  return tr;
}

function formRow(cls, f, first, button, cancel, arts) {
  const tr = el('tr', cls);
  tr.appendChild(td('c-no', first.no || el('span')));
  const comp = el('td', 'c-comp');
  comp.appendChild(first.comp);
  if (first.hint) comp.appendChild(el('span', 'hint', first.hint));
  tr.appendChild(comp);
  const mat = el('td', 'c-mat');
  mat.appendChild(f.mat);
  if (M.canAddMaterial && nfFor && nfFor.key === f.mat.dataset.key) mat.appendChild(newMaterialBox(nfFor.key));
  tr.appendChild(mat);
  const sup = el('td', 'c-sup');
  sup.appendChild(f.sup);
  tr.appendChild(sup);
  const uom = el('td', 'c-uom');
  uom.appendChild(f.uom);
  tr.appendChild(uom);
  const thk = el('td', 'c-thk');
  thk.appendChild(f.thk);
  thk.appendChild(f.thkNote);
  tr.appendChild(thk);
  const rem = el('td', 'c-rem');
  rem.appendChild(f.rem);
  tr.appendChild(rem);
  const act = el('td', 'c-act');
  act.appendChild(button);
  if (cancel) act.appendChild(cancel);
  tr.appendChild(act);
  arts.forEach(() => tr.appendChild(el('td', 'c-art')));
  [f.mat, f.thk, f.sup, f.rem, first.input, f.no].forEach(i => i && i.addEventListener('keydown', e => {
    if (e.sugPicked) return;                    // R19: Enter memilih saran Material / Dimension
    if (e.key === 'Enter' && !e.shiftKey && !e.altKey) {
      e.preventDefault();
      button.click();
    }
  }));
  return tr;
}

// R20 bagian 6: Ganti material / Dimension membuat baris baru (id baru, replaces_line_key = line_key lama).
// Peta id lama -> id baru supaya fokus, ketikan, dan daftar terbuka ikut pindah ke baris pengganti.
function replacedIds(oldLines, newLines) {
  const ids = new Set(newLines.map(l => l.id));
  const byKey = {};
  newLines.forEach(l => { if (l.replaces_line_key) byKey[l.replaces_line_key] = l.id; });
  const map = {};
  oldLines.forEach(l => { if (!ids.has(l.id) && byKey[l.line_key]) map[l.id] = byKey[l.line_key]; });
  return map;
}

const rekey = (k, map) => {
  if (!k) return k;
  const p = k.split(':');
  if (p.length > 1 && map[p[1]]) p[1] = map[p[1]];
  return p.join(':');
};

function render(model, keepState) {
  rendering = true;
  try {
    renderGrid(model, keepState);
  } finally {
    rendering = false;
  }
}

function renderGrid(model, keepState) {
  // simpan fokus, scroll, dan ketikan yang belum disimpan
  const active = document.activeElement;
  const inGrid = !!(active && active.closest && active.closest('#tbody') && active.dataset && active.dataset.key);
  let focusKey = inGrid ? active.dataset.key : null;
  const hasSel = focusKey && typeof active.selectionStart === 'number';
  const sel = hasSel ? [active.selectionStart, active.selectionEnd] : null;
  const sugOpen = !$('suggest').hidden && sugTarget && sugTarget === active ? { full: sugWasFull } : null;
  let dirty = {};
  document.querySelectorAll('#tbody .cell[data-key]').forEach(i => {
    if (i.value !== i.dataset.orig && !/^(add|sub):/.test(i.dataset.key)) dirty[i.dataset.key] = i.value;
  });
  hideSuggest();
  const scroll = $('scroll');
  const pos = [scroll.scrollLeft, scroll.scrollTop];
  const oldLines = M.lines || [];

  M = model || {};
  const idMap = replacedIds(oldLines, M.lines || []);
  if (Object.keys(idMap).length) {
    const d2 = {};
    Object.keys(dirty).forEach(k => { d2[rekey(k, idMap)] = dirty[k]; });
    dirty = d2;
    const o2 = {};
    Object.keys(optimistic).forEach(k => { o2[rekey(k, idMap)] = optimistic[k]; });
    optimistic = o2;
  }
  // R20 bagian 6: kotak yang sedang fokus dipakai lagi bila barisnya tetap (id sama = material & dimension sama)
  const keepEl = focusKey && !idMap[focusKey.split(':')[1]] && !/^(add|sub):/.test(focusKey) ? active : null;
  focusKey = rekey(focusKey, idMap);
  if (!keepState) {
    if (M.message !== lastMsg) {
      lastMsg = M.message;
      localMsg = null;
    }
    if (M.okKey !== lastOkKey) {
      if (lastOkKey !== null) {     // aksi tambah berhasil -> kosongkan form
        addState = {};
        subState = {};
        subParent = null;
        if (nfFor && /^(add|sub):/.test(nfFor.key)) nfFor = null;
      }
      lastOkKey = M.okKey;
    }
  }
  const editable = !!M.editable;
  const arts = M.articles || [];
  const lines = M.lines || [];
  buildMats();
  fillDatalists();
  if (compEdit && !lines.some(l => l.id === compEdit)) compEdit = null;

  // header
  const thead = $('thead');
  thead.innerHTML = '';
  const hr = el('tr');
  [['c-no', 'No'], ['c-comp', 'Component'], ['c-mat', 'Material'], ['c-sup', 'Supplier'], ['c-uom', 'UoM'], ['c-thk', 'Dimension'], ['c-rem', 'Remarks']]
    .forEach(([c, t]) => hr.appendChild(el('th', c, t)));
  if (editable) hr.appendChild(el('th', 'c-act', ''));
  arts.forEach(a => {
    const th = el('th', 'c-art');
    const box = el('div', 'art-head');
    const txt = el('span');
    txt.appendChild(el('span', 'art-code' + (a.no_code ? ' none' : ''), a.code));
    txt.appendChild(el('span', 'art-cw', a.colorway));
    box.appendChild(txt);
    if (editable) {
      const b = el('button', 'drop', dropArmed === a.id ? 'Drop?' : '✕');
      if (dropArmed === a.id) b.classList.add('confirm');
      b.type = 'button';
      b.dataset.art = a.id;
      b.title = `Drop article ${a.no_code ? a.colorway : a.code} from this revision (click twice)`;
      b.addEventListener('click', () => armDrop(b, a));
      box.appendChild(b);
    }
    th.appendChild(box);
    hr.appendChild(th);
  });
  thead.appendChild(hr);

  // isi
  const tbody = $('tbody');
  tbody.innerHTML = '';
  const cols = 7 + (editable ? 1 : 0) + arts.length;
  if (!lines.length && !editable) {
    const tr = el('tr');
    const c = el('td', 'empty', M.emptyText || 'No BOM lines yet.');
    c.colSpan = cols;
    tr.appendChild(c);
    tbody.appendChild(tr);
  }
  curAdd = null;
  curSub = null;
  const parents = new Set(lines.filter(l => l.is_sub).map(l => l.parent_line_key));
  lines.forEach(line => {
    tbody.appendChild(lineRow(line, arts, editable, !line.is_sub && parents.has(line.line_key)));
    if (editable && subParent === line.id) {
      const f = formInputs('sub', subState, true);
      curSub = { parent: line, f };
      const ok = el('button', 'btn', 'Add');
      ok.type = 'button';
      ok.disabled = !!M.busy;
      ok.addEventListener('click', () => submitSub(line, f));
      const cancel = el('button', 'link muted', 'Cancel');
      cancel.type = 'button';
      cancel.addEventListener('click', () => { subParent = null; subState = {}; render(M, true); });
      tbody.appendChild(formRow('subform', f, { comp: f.name, input: f.name }, ok, cancel, arts));
    }
  });
  if (editable) {
    const f = formInputs('add', addState, false);
    curAdd = f;
    const ok = el('button', 'btn', '+ Add');
    ok.type = 'button';
    ok.disabled = !!M.busy;
    ok.addEventListener('click', () => submitAdd(f));
    tbody.appendChild(formRow('add', f, {
      no: f.no, comp: f.comp, input: f.comp,
      hint: 'Not in the master → local component, fill in No. (not a multiple of 10).',
    }, ok, null, arts));
  }

  // pulihkan ketikan, fokus, scroll
  document.querySelectorAll('#tbody .cell[data-key]').forEach(i => {
    const k = i.dataset.key;
    if (optimistic[k] !== undefined) {
      i.value = optimistic[k];
      i.dataset.orig = optimistic[k];
    }
    if (dirty[k] !== undefined) i.value = dirty[k];
    autosize(i);
  });
  if (focusKey) {
    let i = document.querySelector(`#tbody [data-key="${CSS.escape(focusKey)}"]`);
    if (i && keepEl && i !== keepEl && i.tagName === keepEl.tagName) {
      // kotak lama (listener, ketikan, riwayat undo) menggantikan kotak baru; nilai DB terbaru = pembanding simpan
      if (keepEl.value === keepEl.dataset.orig) keepEl.value = i.value;
      keepEl.dataset.orig = i.dataset.orig;
      keepEl.classList.toggle('invalid', i.classList.contains('invalid'));
      i.replaceWith(keepEl);
      autosize(keepEl);
      i = keepEl;
    }
    if (i && !i.disabled) {
      i.focus({ preventScroll: true });
      if (sel) {
        try { i.setSelectionRange(Math.min(sel[0], i.value.length), Math.min(sel[1], i.value.length)); } catch (e) { /* abaikan */ }
      }
    }
  }
  scroll.scrollLeft = pos[0];
  scroll.scrollTop = pos[1];
  // R20 bagian 6: daftar yang sedang terbuka dibuka lagi pada kotak yang sama (penuh / disaring seperti sebelumnya)
  if (sugOpen && document.activeElement && document.activeElement._sugSrc) {
    const i = document.activeElement;
    showSuggest(i, i._sugSrc, sugOpen.full);
  }

  const n = lines.length;
  const yellow = lines.reduce((t, l) => t + (Number(l.yellow) || 0), 0);
  $('status').textContent = (M.busy || queue.length ? 'Saving… · ' : '')
    + `${n} lines · ${arts.length} article(s)` + (yellow ? ` · ${yellow} yellow cells` : '') + (editable ? '' : ' · read only');
  $('btnSupplier').hidden = !(editable && M.canAddSupplier);
  $('btnSupplier').disabled = !!M.busy;
  $('btnMaterial').hidden = !(editable && M.canAddMaterial);
  $('btnMaterial').disabled = !!M.busy;
  showMessage();
}

appsmith.onReady(() => {
  applyTheme(appsmith.theme);
  $('btnSupplier').addEventListener('click', () => send('newSupplier', {}));
  // "+ New material": nama dari ketikan terakhir yang tidak ketemu, atau isi kolom Material baris tambah
  $('btnMaterial').addEventListener('click', () => {
    const r = resolveMaterial(addState.mat || '', addState.thk || '');
    const nf = r.notFound || lastNotFound;
    lastNotFound = null;
    awaitNew = r.notFound ? { key: 'add:mat', thick: r.notFound.thickness } : null;   // baris tambah dilanjutkan setelah simpan
    send('newMaterial', { name: nf ? nf.name : tidy(String(addState.mat || '').split(/\s*·\s*/)[0]) });
  });
  $('scroll').addEventListener('scroll', placeSuggest);   // R20 bagian 6: daftar ikut bergeser, tidak ditutup
  $('suggest').addEventListener('mousedown', e => e.preventDefault());   // R20 bagian 7: scrollbar / judul daftar: kotak tetap fokus
  render(appsmith.model);
  lastMatAdded = (M.matAdded || {}).key;
  appsmith.onModelChange(m => {
    onAck(m);
    render(m);
    resumeAfterNewMaterial();
  });
  if (typeof appsmith.onThemeChange === 'function') appsmith.onThemeChange(applyTheme);
});
