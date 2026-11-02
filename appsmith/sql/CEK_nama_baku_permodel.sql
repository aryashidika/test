-- ============================================================================
-- CEK nama baku material per model (Size Label, Hang Tag, Sticker Inner Box) - 29 Okt 2026
-- Hanya membaca. Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF).
-- Aturan sama dengan R_impor_material_permodel.sql:
--   jenis di depan: SIZE LABEL (HEATSEAL / SZ / LABL dirapikan), HANGTAG, STICKER INNER BOX
--   LS / LIGHTSPEED -> LIGHT SPEED, ACCESSORIES -> ACC, NATIVE -> NATIV, GALACTCA -> GALACTICA, MORP -> MORPH,
--   WMN -> WOMEN, JUNIOR -> JR, JR ditaruh di belakang FG / IN / TF.
-- Hanya material yang namanya BERUBAH yang tampil. Material umum (STANDARD ... SPECS) tidak ikut.
-- Kolom:
--   bentrok        = sudah ada material lain dengan nama baku itu (UoM sama) -> tidak bisa diganti, perlu digabung
--   spec_terbit    = jumlah revisi specsheet PUBLISHED yang memakai material ini (nama baru ikut tampil di sana)
-- ============================================================================

WITH f AS (SELECT id FROM factory WHERE name ILIKE '%UNIMITRA%'),
m AS (
  SELECT m.*,
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
         regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
         regexp_replace(regexp_replace(
           upper(btrim(regexp_replace(m.name, '\s+', ' ', 'g'))),
           '^HEAT ?SEAL SIZE LABEL ', 'SIZE LABEL '),
           '^(SZ|SIZE) LABE?L ', 'SIZE LABEL '),
           '^HANG TAG ', 'HANGTAG '),
           '\mLSREBORN\M', 'LS REBORN', 'g'),
           '\mLIGHTSPEED\M', 'LS', 'g'),
           '\mLIGHT SPEED\M', 'LS', 'g'),
           '\mLS\M', 'LIGHT SPEED', 'g'),
           '\mACCESSORIES\M', 'ACC', 'g'),
           '\mNATIVE\M', 'NATIV', 'g'),
           '\mGALACTCA\M', 'GALACTICA', 'g'),
           '\mMORP\M', 'MORPH', 'g'),
           '\mWMN\M', 'WOMEN', 'g'),
           '\mJUNIOR\M', 'JR', 'g'),
           ' JR (FG|IN|TF)$', ' \1 JR') AS nama_baku
    FROM material m
   WHERE m.factory_id = (SELECT id FROM f)
     AND upper(m.name) ~ '^(HEAT ?SEAL SIZE LABEL|SIZE LABEL|SIZE LABL|SZ LABE?L|HANGTAG|HANG TAG|STICKER INNER BOX) '
)
SELECT m.name AS nama_sekarang,
       m.nama_baku,
       m.uom,
       m.category AS kategori,
       m.status,
       (SELECT string_agg(v.code, ', ' ORDER BY v.code) FROM material_variant v WHERE v.material_id = m.id) AS kode,
       (SELECT o.name FROM material o
         WHERE o.factory_id = m.factory_id AND o.id <> m.id AND o.uom = m.uom
           AND fn_tight_key(o.name) = fn_tight_key(m.nama_baku) LIMIT 1) AS bentrok,
       (SELECT count(DISTINCT r.id) FROM bom_line l JOIN specsheet_revision r ON r.id = l.revision_id
         WHERE l.material_id = m.id AND r.status = 'DRAFT') AS spec_draft,
       (SELECT count(DISTINCT r.id) FROM bom_line l JOIN specsheet_revision r ON r.id = l.revision_id
         WHERE l.material_id = m.id AND r.status = 'PUBLISHED') AS spec_terbit
  FROM m
 WHERE m.nama_baku <> upper(btrim(regexp_replace(m.name, '\s+', ' ', 'g')))
 ORDER BY m.nama_baku;

-- Material umum dengan salah ketik (tidak ikut diganti otomatis, hanya info):
-- SELECT name, uom, status FROM material WHERE name ILIKE '%STICKER INER BOX%';
