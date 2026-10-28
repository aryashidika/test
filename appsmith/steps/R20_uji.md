# R20: penulisan material seragam + Material Code ketat + Use

Isi R20 (diskusi 27 Okt 2026):
1. **Nama material yang hanya beda spasi / tanda baca = material yang sama** (`PU-LEATHER` = `PU LEATHER` = `P.U LEATHER`, per UoM).
   Di grid langsung dipakai nama master tanpa bertanya. Saran "Did you mean" hanya untuk nama yang **angkanya sama**
   (`FOAM 50 KG` tidak disarankan untuk `FOAM 60 KG`).
2. **Material Code 10 karakter ketat dua arah, tanpa centang konfirmasi** (centang R9 dihapus):
   - kode -> arti: 4 awal = 1 material, 3 tengah = 1 dimension, 3 akhir = 1 warna
   - arti -> kode: 1 material = 1 awalan, 1 dimension = 1 kode tengah (dimension kosong: per material sejak bagian 3, dulu per UoM),
     1 warna di satu material = 1 kode akhir
   - Pelanggaran tampil **merah di form sebelum Save**, dan Save ditolak.
3. **Material Code hanya diketik di Register** (revisi Anda setelah hasil cek): kolom Material dan sel warna tidak membaca kode lagi.
   Kode yang diketik di sel = teks warna biasa (kuning); di kolom Material ditolak dengan pesan. Warna yang sudah terdaftar untuk
   material + dimension baris tetap **langsung dapat kode** dan tidak kuning, seperti sebelumnya. Tidak ada Pick code.
4. **Use di modal Register**: kode dari purchasing ternyata sudah terdaftar untuk material / dimension / warna lain -> tombol
   **Use KODE in the specsheet**. Sel itu memakai varian tersebut, sel kuning yang sama (material + dimension + warna) di **semua
   draft** ikut pindah, material salah ketik yang tidak dipakai lagi otomatis **INACTIVE**. Revisi terbit tidak berubah.
5. **Perbaikan data** dari hasil cek Anda: 11 material proses berkode dummy -> material **Process**; `98 D` digabung ke `98 A`,
   `BSW-0032` ke `BSW-032` (bagian 1b).
6. **Bagian 2 (28 Okt 2026, bagian 8): warna seragam** (`black / white` = `BLACK/WHITE` = `BLACK-WHITE`) dan **Dimension seperti
   dropdown** (specsheet + form varian). Sudah menjalankan bagian 0 sampai 1b? Cukup jalankan **bagian 8**.
7. **Bagian 3 (28 Okt 2026, bagian 9): kode Dimension kosong per material** (tidak lagi per UoM) dan **Dimension wajib + default**
   (`(None)` paling atas, default = dimension dengan varian terbanyak). Sudah menjalankan bagian 8? Cukup jalankan **bagian 9**.

> Build dibuat dari `exports/build_r19.json` (export R19 dari Anda belum ada). Kalau Anda sempat mengubah app setelah import
> R19, kirim export-nya dulu supaya build dibuat ulang dari situ.

> **Catatan benang:** di ERP nama benang memuat nomor shade (`BONDED THREAD(210D/3P)=B 4848`), padahal satu awalan kode (`502A`)
> dipakai semua shade. Di app daftarkan **satu material tanpa nomor shade** (`BONDED THREAD(210D/3P)`), warna di kolom warna.
> Kalau dua shade ERP punya nama warna sama (PALE KHAKI `P88` / `P9F`), hanya satu yang bisa didaftarkan (sesuai keputusan).

Beri tanda di kolom **OK?** (v / x). Kalau ada yang beda, kirim tangkapan layar dan teks pesannya.

## 0. Pasang

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 0.1 | DB Tools → `z_run_sql` (prepared statements OFF) → tempel **seluruh SQL di bagian 0a** → Run | `R20: material kembar (beda spasi/tanda baca) N kelompok, varian menyimpang M` (catat N dan M) | |
| 0.2 | Jalankan lagi SQL yang sama | Aman: hasil sama | |
| 0.3 | DB Tools → jalankan `sql/R_selftest.sql` (sudah diperbarui untuk R20) | **`SELFTEST LOLOS`** | |
| 0.4 | Import `exports/build_r20.json` (timpa app), lalu Deploy | Nama app `Product Management R20` | |
| 0.5 | Page **Login** → `LoginCtrl.onPageLoad` masih **Run on page load ON**; page **Home** → **Auth** → `onPageLoad` ON | ON | |
| 0.6 | Page **Specsheet** → query `a_bom_use_variant` ada, **Run behaviour Manual** (dipakai tombol Use di modal Register) | Ada, Manual | |

Langkah 0.1 dan 0.4 sebaiknya berurutan tanpa jeda: setelah SQL dan sebelum import, isian otomatis Material Code di form
varian app lama tidak jalan (hanya bantuan, data aman).

### 0a. SQL R20 (salin semua)

```sql
-- ============================================================================
-- R20 (27 Okt 2026, PLAN.md R20): penulisan material seragam + kode ERP ketat. Jalankan SETELAH R19, lewat z_run_sql di
-- app "DB Tools" (Use prepared statements = OFF). Aman diulang. Satu transaksi. Data tidak diubah.
--   1. Nama material yang hanya beda spasi / tanda baca = material yang sama (PU-LEATHER = PU LEATHER), per UoM.
--   2. Material Code 10 karakter ketat dua arah (tanpa centang konfirmasi):
--        kode -> arti : 4 awal = 1 material, 3 tengah = 1 dimension, 3 akhir = 1 warna
--        arti -> kode : 1 material = 1 awalan, 1 dimension = 1 kode tengah (dimension kosong: per UoM),
--                       1 warna di satu material = 1 kode akhir
--      Arti = yang paling banyak dipakai (seri: tercatat paling awal). Data lama yang menyimpang dicek dengan query di R20_uji.md.
--   3. "Use" (modal Register, kode yang diketik sudah dipakai varian lain) -> sel memakai varian itu. Sel kuning yang sama
--      (material + dimension + warna) di semua draft ikut pindah; material lama tanpa varian yang tidak dipakai lagi -> INACTIVE.
--   4. Material Code hanya diketik di Register: sel specsheet menyimpan kode sebagai teks warna biasa.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'material' AND column_name = 'is_process') THEN
    RAISE EXCEPTION 'R19 belum terpasang. Jalankan sql/R19_catatan_uji.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- 1. nama material: abaikan spasi & tanda baca
-- Kunci rapat: huruf kecil + angka saja ("P.U-LEATHER 1,5" -> "puleather15")
CREATE OR REPLACE FUNCTION fn_tight_key(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]', '', 'g')
$$;

-- fn_material_check: R2 + nama rapat (R20). Dicek hanya saat tambah / nama / UoM berubah, supaya data lama yang kembar
-- (lihat query cek R20) tidak menghalangi ubah status / kategori.
CREATE OR REPLACE FUNCTION public.fn_material_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_other record;
BEGIN
  NEW.name     := btrim(regexp_replace(coalesce(NEW.name, ''), '\s+', ' ', 'g'));
  NEW.category := btrim(regexp_replace(coalesce(NEW.category, ''), '\s+', ' ', 'g'));
  NEW.uom      := upper(btrim(coalesce(NEW.uom, '')));
  IF NEW.factory_id IS NULL THEN RAISE EXCEPTION 'Material factory is required.'; END IF;
  IF NEW.name = ''          THEN RAISE EXCEPTION 'Material name is required.'; END IF;
  IF NEW.category = ''      THEN RAISE EXCEPTION 'Material category is required.'; END IF;
  IF NEW.uom = ''           THEN RAISE EXCEPTION 'UoM is required.'; END IF;
  IF TG_OP = 'UPDATE' AND NEW.factory_id IS DISTINCT FROM OLD.factory_id THEN
    RAISE EXCEPTION 'The material factory cannot be changed.';
  END IF;
  SELECT name, uom INTO v_other FROM material
   WHERE factory_id = NEW.factory_id AND name_key = fn_normalize(NEW.name) AND uom = NEW.uom AND id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material "%" (%) already exists in this factory. Add the variant to that material.', v_other.name, v_other.uom;
  END IF;
  -- R20: hanya beda spasi / tanda baca (PU-LEATHER = PU LEATHER) = material yang sama
  IF TG_OP = 'INSERT' OR NEW.name IS DISTINCT FROM OLD.name OR NEW.uom IS DISTINCT FROM OLD.uom THEN
    SELECT name, uom INTO v_other FROM material
     WHERE factory_id = NEW.factory_id AND uom = NEW.uom AND id <> NEW.id
       AND fn_tight_key(name) = fn_tight_key(NEW.name) AND fn_tight_key(NEW.name) <> ''
     ORDER BY status = 'ACTIVE' DESC, name LIMIT 1;
    IF FOUND THEN
      RAISE EXCEPTION 'Material "%" (%) already exists in this factory (only spaces or punctuation differ). Use that material.',
        v_other.name, v_other.uom;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ---------------------------------------------------------------- 2. Material Code ketat
-- Masalah kode 10 karakter terhadap varian lain di pabrik ini (kosong = boleh). Dipakai trigger varian (menolak),
-- fn_variant_code_hint (form menampilkan sebelum simpan) dan query cek data R20.
CREATE OR REPLACE FUNCTION fn_variant_code_problems(p_factory uuid, p_material_id uuid, p_code text, p_color text,
                                                    p_thickness text, p_exclude uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_code  text := upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g')));
  v_color text := upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g')));
  v_thick text := fn_clean_thickness(p_thickness);
  v_tkey  text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey  text := fn_normalize(upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))));
  v_mat   material%ROWTYPE;
  v_out   text[] := '{}';
  r       record;
BEGIN
  IF length(v_code) <> 10 THEN
    RETURN v_out;
  END IF;
  SELECT * INTO v_mat FROM material WHERE id = p_material_id;
  -- kode -> arti: 4 awal = satu material
  SELECT x.material_id, x.code INTO r
    FROM (SELECT v.material_id, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND left(v.code, 4) = left(v_code, 4)
           GROUP BY v.material_id) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.material_id <> p_material_id THEN
    v_out := v_out || format('Prefix %s belongs to material %s (code %s). Register this variant in that material.',
                             left(v_code, 4), (SELECT name FROM material WHERE id = r.material_id), r.code);
  END IF;
  -- kode -> arti: 3 tengah = satu dimension
  SELECT x.tkey, x.thickness, x.code INTO r
    FROM (SELECT v.thickness_key AS tkey, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                 (array_agg(v.thickness ORDER BY v.created_at, v.code))[1] AS thickness
            FROM material_variant v
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND substr(v.code, 5, 3) = substr(v_code, 5, 3)
           GROUP BY v.thickness_key) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.tkey <> v_tkey THEN
    v_out := v_out || format('Dimension code %s means %s (code %s), not %s.',
                             substr(v_code, 5, 3), fn_thickness_label(r.thickness), r.code, fn_thickness_label(v_thick));
  END IF;
  -- kode -> arti: 3 akhir = satu warna
  SELECT x.ckey, x.color, x.code INTO r
    FROM (SELECT v.color_key AS ckey, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                 (array_agg(v.color ORDER BY v.created_at, v.code))[1] AS color
            FROM material_variant v
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND substr(v.code, 8, 3) = substr(v_code, 8, 3)
           GROUP BY v.color_key) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND v_ckey <> '' AND r.ckey <> v_ckey THEN
    v_out := v_out || format('Color code %s means %s (code %s), not %s.', substr(v_code, 8, 3), r.color, r.code, v_color);
  END IF;
  -- arti -> kode: satu material = satu awalan
  SELECT x.part, x.code INTO r
    FROM (SELECT left(v.code, 4) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.part <> left(v_code, 4) THEN
    v_out := v_out || format('Material %s uses prefix %s (code %s), not %s.', v_mat.name, r.part, r.code, left(v_code, 4));
  END IF;
  -- arti -> kode: satu dimension = satu kode tengah (dimension kosong: per UoM, mis. PRS = 800, KG = K00)
  SELECT x.part, x.code INTO r
    FROM (SELECT substr(v.code, 5, 3) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v JOIN material m ON m.id = v.material_id
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND v.thickness_key = v_tkey AND (v_tkey <> '' OR m.uom = v_mat.uom)
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.part <> substr(v_code, 5, 3) THEN
    v_out := v_out || CASE WHEN v_tkey = ''
      THEN format('No dimension (%s) uses dimension code %s (code %s), not %s.', v_mat.uom, r.part, r.code, substr(v_code, 5, 3))
      ELSE format('Dimension %s uses dimension code %s (code %s), not %s.', v_thick, r.part, r.code, substr(v_code, 5, 3)) END;
  END IF;
  -- arti -> kode: satu warna di material ini = satu kode akhir
  SELECT x.part, x.code INTO r
    FROM (SELECT substr(v.code, 8, 3) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND v.color_key = v_ckey
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND v_ckey <> '' AND r.part <> substr(v_code, 8, 3) THEN
    v_out := v_out || format('Color %s in material %s uses color code %s (code %s), not %s.',
                             v_color, v_mat.name, r.part, r.code, substr(v_code, 8, 3));
  END IF;
  RETURN v_out;
END;
$function$;

-- fn_material_variant_check: R18 + tingkat KONFIRMASI diganti aturan ketat (R20). Hanya dicek saat varian baru atau kode /
-- warna / dimension berubah (ubah status saja tidak dicek ulang, supaya data lama yang menyimpang tetap bisa di-INACTIVE).
CREATE OR REPLACE FUNCTION public.fn_material_variant_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory  uuid;
  v_other    record;
  v_tkey     text;
  v_ckey     text;
  v_problems text[];
BEGIN
  NEW.code      := upper(btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g')));
  NEW.color     := upper(btrim(regexp_replace(coalesce(NEW.color, ''), '\s+', ' ', 'g')));
  NEW.thickness := fn_clean_thickness(NEW.thickness);
  v_tkey := fn_normalize(coalesce(NEW.thickness, ''));
  v_ckey := fn_normalize(NEW.color);
  IF NEW.code = '' THEN
    RAISE EXCEPTION 'Material Code is required.';
  END IF;
  IF NEW.color = '' THEN
    RAISE EXCEPTION 'Color is required.';
  END IF;
  -- R20: pindah material hanya lewat skrip perbaikan data (gabung material kembar, app.variant_merge = on di transaksi itu)
  IF TG_OP = 'UPDATE' AND NEW.material_id IS DISTINCT FROM OLD.material_id
     AND coalesce(current_setting('app.variant_merge', true), '') <> 'on' THEN
    RAISE EXCEPTION 'A variant cannot be moved to another material.';
  END IF;
  SELECT factory_id INTO v_factory FROM material WHERE id = NEW.material_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Parent material not found.';
  END IF;
  IF TG_OP = 'UPDATE' AND v_factory IS DISTINCT FROM OLD.factory_id THEN
    RAISE EXCEPTION 'A variant cannot be moved to another factory.';
  END IF;
  NEW.factory_id := v_factory;

  -- TOLAK: kode unik per pabrik
  SELECT v.code, m.name, v.color, v.thickness INTO v_other
    FROM material_variant v JOIN material m ON m.id = v.material_id
   WHERE v.factory_id = NEW.factory_id AND v.code = NEW.code AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material Code % is already used: % · % · %.',
      NEW.code, v_other.name, v_other.color, fn_thickness_label(v_other.thickness);
  END IF;

  -- TOLAK: satu kode per material + dimension + warna
  SELECT v.code INTO v_other
    FROM material_variant v
   WHERE v.material_id = NEW.material_id AND v.thickness_key = v_tkey AND v.color_key = v_ckey AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Variant % · % already exists in this material (code %). One color + dimension has one Material Code.',
      NEW.color, fn_thickness_label(NEW.thickness), v_other.code;
  END IF;

  -- R20 TOLAK: setiap bagian kode 10 karakter punya satu arti, dan sebaliknya
  IF length(NEW.code) = 10
     AND (TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code OR NEW.color IS DISTINCT FROM OLD.color
          OR NEW.thickness IS DISTINCT FROM OLD.thickness) THEN
    v_problems := fn_variant_code_problems(NEW.factory_id, NEW.material_id, NEW.code, NEW.color, NEW.thickness, NEW.id);
    IF cardinality(v_problems) > 0 THEN
      RAISE EXCEPTION 'Material Code % cannot be saved: %', NEW.code, array_to_string(v_problems, ' ');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- fn_variant_save: R10 tanpa konfirmasi (R20). p_confirm tetap ada supaya query lama tidak rusak, tapi tidak dipakai.
CREATE OR REPLACE FUNCTION public.fn_variant_save(p_token text, p_id uuid, p_material_id uuid, p_code text, p_color text, p_thickness text, p_status text, p_confirm boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_mat   material%ROWTYPE;
  v_old   material_variant%ROWTYPE;
  v_id    uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Variant status is required (ACTIVE / INACTIVE).';
  END IF;
  IF p_id IS NULL THEN
    SELECT * INTO v_mat FROM material WHERE id = p_material_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Material not found.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_mat.factory_id);
    IF v_mat.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Material % is INACTIVE. Activate it before adding variants.', v_mat.name;
    END IF;
    INSERT INTO material_variant (material_id, factory_id, code, color, thickness, status, updated_by)
    VALUES (p_material_id, v_mat.factory_id, p_code, p_color, p_thickness, p_status, v_email)
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM material_variant WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Variant not found.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  IF (upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g'))) IS DISTINCT FROM v_old.code
      OR upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))) IS DISTINCT FROM v_old.color
      OR fn_clean_thickness(p_thickness) IS DISTINCT FROM v_old.thickness)
     AND fn_variant_used_published(p_id) THEN
    RAISE EXCEPTION 'Variant % is used in published documents. Its Material Code, color, and dimension cannot be changed. Set it INACTIVE and register a new variant.', v_old.code;
  END IF;
  UPDATE material_variant
     SET code = p_code, color = p_color, thickness = p_thickness, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$function$;

-- fn_variant_code_hint: R16 + warna / dimension form, kode yang sudah dipakai (tombol Use) dan masalah aturan ketat (R20)
DROP FUNCTION IF EXISTS fn_variant_code_hint(text, uuid, text, uuid);
CREATE OR REPLACE FUNCTION public.fn_variant_code_hint(p_token text, p_material_id uuid, p_code text, p_exclude uuid,
                                                       p_color text DEFAULT NULL, p_thickness text DEFAULT NULL)
 RETURNS TABLE(code text, thickness_known boolean, thickness text, thickness_ref text, color_known boolean, color text,
               color_ref text, other_prefixes text, used_id uuid, used_label text, used_active boolean, problems text[])
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  v_email   text := fn_auth(p_token, 'view_master');
  v_factory uuid;
  v_code    text := upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g')));
  v_t       record;
  v_c       record;
  v_u       record;
BEGIN
  SELECT factory_id INTO v_factory FROM material WHERE id = p_material_id;
  IF NOT FOUND OR NOT fn_can_see_factory(v_email, v_factory) OR length(v_code) <> 10 THEN
    RETURN;
  END IF;
  -- R16 (review): arti = yang paling banyak memakai bagian kode itu (seri: tercatat paling awal), sama dengan trigger varian
  SELECT x.code, x.thickness INTO v_t
    FROM (SELECT count(*) AS n, min(mv.created_at) AS first_at,
                 (array_agg(mv.code ORDER BY mv.created_at, mv.code))[1] AS code,
                 (array_agg(mv.thickness ORDER BY mv.created_at, mv.code))[1] AS thickness
            FROM material_variant mv
           WHERE mv.factory_id = v_factory AND length(mv.code) = 10 AND mv.id IS DISTINCT FROM p_exclude
             AND substr(mv.code, 5, 3) = substr(v_code, 5, 3)
           GROUP BY mv.thickness_key) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  SELECT x.code, x.color INTO v_c
    FROM (SELECT count(*) AS n, min(mv.created_at) AS first_at,
                 (array_agg(mv.code ORDER BY mv.created_at, mv.code))[1] AS code,
                 (array_agg(mv.color ORDER BY mv.created_at, mv.code))[1] AS color
            FROM material_variant mv
           WHERE mv.factory_id = v_factory AND length(mv.code) = 10 AND mv.id IS DISTINCT FROM p_exclude
             AND substr(mv.code, 8, 3) = substr(v_code, 8, 3)
           GROUP BY mv.color_key) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  -- R20: kode utuh sudah dipakai varian lain
  SELECT mv.id, m.name || ' · ' || fn_thickness_label(mv.thickness) || ' · ' || mv.color AS label,
         mv.status = 'ACTIVE' AND m.status = 'ACTIVE' AND NOT m.is_process AS active INTO v_u
    FROM material_variant mv JOIN material m ON m.id = mv.material_id
   WHERE mv.factory_id = v_factory AND mv.code = v_code AND mv.id IS DISTINCT FROM p_exclude;
  RETURN QUERY SELECT
    v_code,
    v_t.code IS NOT NULL, v_t.thickness, v_t.code,
    v_c.code IS NOT NULL, v_c.color, v_c.code,
    (SELECT string_agg(DISTINCT left(mv.code, 4), ', ') FROM material_variant mv
      WHERE mv.material_id = p_material_id AND mv.id IS DISTINCT FROM p_exclude
        AND length(mv.code) = 10 AND left(mv.code, 4) <> left(v_code, 4)),
    v_u.id, v_u.label, coalesce(v_u.active, false),
    CASE WHEN v_u.id IS NOT NULL THEN '{}'::text[]
         ELSE fn_variant_code_problems(v_factory, p_material_id, v_code, p_color, p_thickness, p_exclude) END;
END;
$function$;

-- fn_variant_code_suggest: R9 + dimension kosong dicari per UoM material (R20: 800 = PRS, K00 = KG, ...)
CREATE OR REPLACE FUNCTION public.fn_variant_code_suggest(p_token text, p_material_id uuid, p_color text, p_thickness text)
 RETURNS TABLE(prefixes text, thickness_codes text, color_codes text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_email   text := fn_auth(p_token, 'view_master');
  v_factory uuid;
  v_uom     text;
  v_tkey    text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey    text := fn_normalize(upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))));
BEGIN
  SELECT factory_id, uom INTO v_factory, v_uom FROM material WHERE id = p_material_id;
  IF NOT FOUND OR NOT fn_can_see_factory(v_email, v_factory) THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT left(v.code, 4) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
        WHERE v.material_id = p_material_id AND length(v.code) = 10 GROUP BY 1) x),
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT substr(v.code, 5, 3) AS part, count(*) AS n, min(v.created_at) AS first_at
         FROM material_variant v JOIN material m ON m.id = v.material_id
        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v.thickness_key = v_tkey
          AND (v_tkey <> '' OR m.uom = v_uom) GROUP BY 1) x),
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT substr(v.code, 8, 3) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v_ckey <> '' AND v.color_key = v_ckey
          AND (v.material_id = p_material_id OR NOT EXISTS (
                 SELECT 1 FROM material_variant w WHERE w.material_id = p_material_id AND w.color_key = v_ckey
                    AND length(w.code) = 10))
        GROUP BY 1) x);
END;
$function$;

-- fn_bom_cell_set: R18 tanpa membaca Material Code (R20, keputusan user 27 Okt 2026: kode hanya diketik di Register; kode yang
-- diketik di sel = teks warna biasa). Warna yang terdaftar tetap tersambung ke variannya oleh trigger sel.
CREATE OR REPLACE FUNCTION public.fn_bom_cell_set(p_token text, p_line_id uuid, p_article_id uuid, p_color text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid := fn_line_factory(p_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_line    bom_line%ROWTYPE;
  v_color   text := nullif(upper(btrim(regexp_replace(coalesce(p_color, ''), '\s+', ' ', 'g'))), '');
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  IF NOT EXISTS (SELECT 1 FROM revision_article
                  WHERE revision_id = v_line.revision_id AND article_id = p_article_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'This article is not active in this revision.';
  END IF;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  VALUES (v_line.id, p_article_id, v_color, v_email)
  ON CONFLICT (bom_line_id, article_id) DO UPDATE SET color = EXCLUDED.color, updated_by = EXCLUDED.updated_by;
  RETURN v_line.id;
END;
$function$;

-- ---------------------------------------------------------------- 3. Use: pakai varian yang sudah ada
-- Sel artikel p_arts di baris p_line_id dipindah ke varian p_variant_id. Baris lain di draft dipanggil oleh fn_bom_use_variant.
--   material + dimension sama      -> warna sel diganti warna varian
--   sel lain di baris belum berkode -> seluruh baris diganti material (seperti Ganti material: Undo replace tersedia)
--   sel lain sudah berkode          -> sel ini pindah ke baris komponen yang sama dengan material + dimension varian
--                                      (yang sudah ada, atau baris baru)
CREATE OR REPLACE FUNCTION fn_bom_take_cells(p_token text, p_email text, p_line_id uuid, p_arts uuid[], p_variant_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_line bom_line%ROWTYPE;
  v_var  material_variant%ROWTYPE;
  v_mat  material%ROWTYPE;
  v_to   uuid;
  v_new  uuid;
  v_busy text;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  SELECT * INTO v_var FROM material_variant WHERE id = p_variant_id;
  SELECT * INTO v_mat FROM material WHERE id = v_var.material_id;
  IF v_line.material_id = v_var.material_id AND fn_normalize(coalesce(v_line.thickness, '')) = v_var.thickness_key THEN
    UPDATE bom_cell SET color = v_var.color, updated_by = p_email
     WHERE bom_line_id = v_line.id AND article_id = ANY (p_arts);
    RETURN v_line.id;
  END IF;
  -- baris komponen yang sama yang sudah memakai material + dimension varian
  SELECT l.id INTO v_to FROM bom_line l
   WHERE l.revision_id = v_line.revision_id AND l.is_active AND l.id <> v_line.id
     AND l.material_id = v_var.material_id AND fn_normalize(coalesce(l.thickness, '')) = v_var.thickness_key
     AND l.parent_line_key IS NOT DISTINCT FROM v_line.parent_line_key
     AND CASE WHEN v_line.parent_line_key IS NULL
              THEN l.component_id IS NOT DISTINCT FROM v_line.component_id
                   AND l.local_component_no IS NOT DISTINCT FROM v_line.local_component_no
              ELSE l.sub_name IS NOT DISTINCT FROM v_line.sub_name END
   ORDER BY l.sort_order LIMIT 1;
  IF v_to IS NULL AND NOT EXISTS (
       SELECT 1 FROM bom_cell bc WHERE bc.bom_line_id = v_line.id AND bc.is_used AND bc.variant_id IS NOT NULL
          AND NOT (bc.article_id = ANY (p_arts))) THEN
    -- seluruh baris pindah (sel kuning lain ikut, tetap kuning sampai kodenya ada)
    v_new := fn_bom_replace_material(p_token, v_line.id, v_var.material_id, v_var.thickness);
    UPDATE bom_cell SET color = v_var.color, updated_by = p_email
     WHERE bom_line_id = v_new AND article_id = ANY (p_arts);
    RETURN v_new;
  END IF;
  IF v_to IS NOT NULL THEN
    SELECT string_agg(coalesce(a.code, a.colorway), ', ') INTO v_busy
      FROM bom_cell bc JOIN article a ON a.id = bc.article_id
     WHERE bc.bom_line_id = v_to AND bc.is_used AND bc.article_id = ANY (p_arts)
       AND fn_normalize(bc.color) <> v_var.color_key;
    IF v_busy IS NOT NULL THEN
      RAISE EXCEPTION 'The line % · % of this component already has another color for %. Fix that line first.',
        v_mat.name, fn_thickness_label(v_var.thickness), v_busy;
    END IF;
  ELSE
    IF v_line.parent_line_key IS NULL AND v_line.component_id IS NULL THEN
      RAISE EXCEPTION 'Local component % has other articles with Material Codes of another material. Add a line for % · % yourself, then type the code there.',
        v_line.local_component_no, v_mat.name, fn_thickness_label(v_var.thickness);
    END IF;
    PERFORM fn_bom_check_material(v_var.material_id, v_mat.factory_id);
    PERFORM fn_bom_check_supplier(v_var.material_id, v_line.supplier_id);
    INSERT INTO bom_line (revision_id, line_key, component_id, local_component_no, local_component_name, parent_line_key,
                          sub_seq, sub_name, material_id, thickness, supplier_id, process, sort_order, updated_by)
    VALUES (v_line.revision_id, gen_random_uuid(), v_line.component_id, v_line.local_component_no,
            v_line.local_component_name, v_line.parent_line_key,
            CASE WHEN v_line.parent_line_key IS NOT NULL THEN
              (SELECT coalesce(max(sub_seq), 0) + 1 FROM bom_line
                WHERE revision_id = v_line.revision_id AND is_active AND parent_line_key = v_line.parent_line_key) END,
            v_line.sub_name, v_var.material_id, v_var.thickness, v_line.supplier_id, v_line.process, v_line.sort_order, p_email)
    RETURNING id INTO v_to;
    PERFORM fn_bom_create_cells(v_to, p_email);
  END IF;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  SELECT v_to, x, v_var.color, p_email FROM unnest(p_arts) AS x
  ON CONFLICT (bom_line_id, article_id) DO UPDATE SET color = EXCLUDED.color, updated_by = EXCLUDED.updated_by;
  UPDATE bom_cell SET color = NULL, updated_by = p_email
   WHERE bom_line_id = v_line.id AND article_id = ANY (p_arts);
  RETURN v_to;
END;
$function$;

-- Tombol Use (modal Register): sel artikel p_article_id di baris p_line_id memakai varian p_variant_id.
-- Sel kuning: semua sel kuning lain dengan material + dimension + warna yang sama di draft pabrik ini ikut pindah.
-- Baris lain yang bentrok (article sudah berwarna lain di baris tujuan, komponen lokal) dilewati: tetap kuning (skipped).
-- Hasil: { code, label, cells, lines, revisions (draft lain), skipped (sel dilewati), inactivated (nama material lama yang di-INACTIVE) }
CREATE OR REPLACE FUNCTION fn_bom_use_variant(p_token text, p_line_id uuid, p_article_id uuid, p_variant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid := fn_line_factory(p_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_line    bom_line%ROWTYPE;
  v_cell    bom_cell%ROWTYPE;
  v_var     material_variant%ROWTYPE;
  v_mat     material%ROWTYPE;
  v_src     material%ROWTYPE;
  v_tkey    text;
  v_ckey    text;
  v_cells   integer := 0;
  v_lines   integer := 0;
  v_revs    integer := 0;
  v_skip    integer := 0;
  v_off     text;
  v_revids  uuid[] := '{}';
  r         record;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  IF NOT EXISTS (SELECT 1 FROM revision_article
                  WHERE revision_id = v_line.revision_id AND article_id = p_article_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'This article is not active in this revision.';
  END IF;
  SELECT * INTO v_var FROM material_variant WHERE id = p_variant_id;
  IF NOT FOUND OR v_var.factory_id IS DISTINCT FROM v_factory THEN
    RAISE EXCEPTION 'Variant not found in this factory.';
  END IF;
  SELECT * INTO v_mat FROM material WHERE id = v_var.material_id;
  IF v_var.status <> 'ACTIVE' OR v_mat.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Material Code % is INACTIVE.', v_var.code;
  END IF;
  SELECT * INTO v_src FROM material WHERE id = v_line.material_id;
  v_tkey := fn_normalize(coalesce(v_line.thickness, ''));
  SELECT * INTO v_cell FROM bom_cell WHERE bom_line_id = v_line.id AND article_id = p_article_id;
  IF FOUND AND v_cell.is_used AND v_cell.variant_id IS NULL AND NOT v_src.is_process THEN
    v_ckey := fn_normalize(v_cell.color);
  END IF;

  IF v_ckey IS NULL THEN
    -- sel kosong / sudah berkode: hanya sel ini
    PERFORM fn_bom_take_cells(p_token, v_email, v_line.id, ARRAY[p_article_id], v_var.id);
    v_cells := 1;
    v_lines := 1;
  ELSE
    FOR r IN
      SELECT l.id, l.revision_id, array_agg(bc.article_id) AS arts
        FROM bom_line l
        JOIN specsheet_revision sr ON sr.id = l.revision_id AND sr.status = 'DRAFT'
        JOIN bom_cell bc ON bc.bom_line_id = l.id AND bc.variant_id IS NULL AND bc.is_used AND fn_normalize(bc.color) = v_ckey
        JOIN revision_article ra ON ra.revision_id = l.revision_id AND ra.article_id = bc.article_id AND ra.status = 'ACTIVE'
       WHERE l.is_active AND l.material_id = v_line.material_id AND fn_normalize(coalesce(l.thickness, '')) = v_tkey
       GROUP BY l.id, l.revision_id
       ORDER BY l.id = v_line.id DESC, l.revision_id, l.id
    LOOP
      IF r.id = v_line.id THEN
        PERFORM fn_bom_take_cells(p_token, v_email, r.id, r.arts, v_var.id);   -- baris yang diklik: gagal = pesan ke user
      ELSE
        BEGIN
          PERFORM fn_revision_draft(r.revision_id);
          PERFORM fn_bom_take_cells(p_token, v_email, r.id, r.arts, v_var.id);
        EXCEPTION WHEN others THEN
          v_skip := v_skip + cardinality(r.arts);                             -- bentrok di baris lain: dibiarkan kuning
          CONTINUE;
        END;
      END IF;
      v_cells := v_cells + cardinality(r.arts);
      v_lines := v_lines + 1;
      IF r.revision_id <> v_line.revision_id AND NOT (r.revision_id = ANY (v_revids)) THEN
        v_revids := v_revids || r.revision_id;
      END IF;
    END LOOP;
    v_revs := cardinality(v_revids);
  END IF;

  -- material lama tanpa varian yang sudah tidak dipakai di draft mana pun -> INACTIVE
  IF v_src.id <> v_var.material_id AND v_src.status = 'ACTIVE' AND NOT v_src.is_process
     AND NOT EXISTS (SELECT 1 FROM material_variant WHERE material_id = v_src.id)
     AND NOT EXISTS (SELECT 1 FROM bom_line l JOIN specsheet_revision sr ON sr.id = l.revision_id AND sr.status = 'DRAFT'
                      WHERE l.material_id = v_src.id AND l.is_active)
     AND NOT EXISTS (SELECT 1 FROM cbd_line cl JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id AND cr.status = 'DRAFT'
                      WHERE cl.material_id = v_src.id) THEN
    UPDATE material SET status = 'INACTIVE', updated_by = v_email WHERE id = v_src.id;
    v_off := v_src.name;
  END IF;

  RETURN jsonb_build_object('code', v_var.code,
                            'label', v_mat.name || ' · ' || fn_thickness_label(v_var.thickness) || ' · ' || v_var.color,
                            'cells', v_cells, 'lines', v_lines, 'revisions', v_revs, 'skipped', v_skip, 'inactivated', v_off);
END;
$function$;

-- fn_bom_delete_line: R4 + Undo replace mengaktifkan lagi material lama tanpa varian yang di-INACTIVE oleh Use (R20)
CREATE OR REPLACE FUNCTION public.fn_bom_delete_line(p_token text, p_line_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth_in(p_token, 'edit_specsheet', fn_line_factory(p_line_id));
  v_line  bom_line%ROWTYPE;
  v_old   bom_line%ROWTYPE;
  v_subs  integer;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  SELECT * INTO v_old FROM bom_line WHERE id = fn_bom_undo_target(v_line.id);
  IF FOUND THEN
    UPDATE bom_line SET parent_line_key = v_old.line_key, updated_by = v_email
     WHERE revision_id = v_line.revision_id AND parent_line_key = v_line.line_key;
    DELETE FROM bom_line WHERE id = v_line.id;
    UPDATE bom_line SET is_active = true, updated_by = v_email WHERE id = v_old.id;
    -- R20: Use bisa membuat material lama (tanpa varian) INACTIVE; Undo replace kembali ke material itu -> aktif lagi
    UPDATE material SET status = 'ACTIVE', updated_by = v_email
     WHERE id = v_old.material_id AND status = 'INACTIVE'
       AND NOT EXISTS (SELECT 1 FROM material_variant WHERE material_id = v_old.material_id);
    UPDATE bom_cell SET color = color WHERE bom_line_id = v_old.id;     -- sambungkan ulang Material Code (trigger)
    PERFORM fn_bom_create_cells(v_old.id, v_email);                     -- article yang ditambah setelah penggantian
    RETURN 0;
  END IF;
  DELETE FROM bom_line WHERE revision_id = v_line.revision_id AND parent_line_key = v_line.line_key;
  GET DIAGNOSTICS v_subs = ROW_COUNT;
  DELETE FROM bom_line WHERE id = v_line.id;
  RETURN v_subs + 1;
END;
$function$;

SELECT 'R20: material kembar (beda spasi/tanda baca) ' ||
       (SELECT count(*) FROM (SELECT 1 FROM material GROUP BY factory_id, uom, fn_tight_key(name) HAVING count(*) > 1) x) ||
       ' kelompok, varian menyimpang ' ||
       (SELECT count(*) FROM material_variant v
         WHERE cardinality(fn_variant_code_problems(v.factory_id, v.material_id, v.code, v.color, v.thickness, v.id)) > 0) AS cek_r20;

COMMIT;
```

## 1. Cek data yang sudah ada (DB Tools, hanya membaca)

Jalankan ketiga query ini satu per satu, lalu **kirim hasilnya ke saya** (tangkapan layar / salin tabel). Data **belum** diubah;
query perbaikan saya buat setelah melihat hasilnya.

| # | Query | Isinya |
|---|---|---|
| 1.1 | C1 | Material kembar: nama hanya beda spasi / tanda baca, UoM sama, plus jumlah varian & apakah dipakai dokumen terbit |
| 1.2 | C2 | Varian yang melanggar aturan kode ketat + alasannya + apakah dipakai dokumen terbit |
| 1.3 | C3 | Material Code yang bukan 10 karakter (tidak dicek aturan ketat) |

```sql
-- C1. Material kembar: nama hanya beda spasi / tanda baca, UoM sama
SELECT f.name AS factory, m.uom,
       string_agg(m.name || '  [' || m.status || ', ' ||
                  (SELECT count(*) FROM material_variant v WHERE v.material_id = m.id) || ' variant, ' ||
                  CASE WHEN fn_material_used_published(m.id) THEN 'used in published docs' ELSE 'not in published docs' END || ']',
                  '  |  ' ORDER BY m.name) AS materials
  FROM material m JOIN factory f ON f.id = m.factory_id
 GROUP BY f.name, m.factory_id, m.uom, fn_tight_key(m.name)
HAVING count(*) > 1
 ORDER BY 1, 3;

-- C2. Varian yang melanggar aturan kode ketat (dibandingkan dengan varian lain di pabrik yang sama)
SELECT f.name AS factory, m.name AS material, v.code, v.color, coalesce(v.thickness, '') AS dimension, m.uom, v.status,
       fn_variant_used_published(v.id) AS used_published,
       array_to_string(p.problems, ' ') AS problems
  FROM material_variant v
  JOIN material m ON m.id = v.material_id
  JOIN factory f ON f.id = v.factory_id
 CROSS JOIN LATERAL (SELECT fn_variant_code_problems(v.factory_id, v.material_id, v.code, v.color, v.thickness, v.id) AS problems) p
 WHERE cardinality(p.problems) > 0
 ORDER BY 1, 2, 3;

-- C3. Material Code yang bukan 10 karakter (tidak dicek aturan ketat)
SELECT f.name AS factory, m.name AS material, v.code, length(v.code) AS length, v.color, coalesce(v.thickness, '') AS dimension, v.status
  FROM material_variant v JOIN material m ON m.id = v.material_id JOIN factory f ON f.id = v.factory_id
 WHERE length(v.code) <> 10
 ORDER BY 1, 2, 3;
```

> **Hasil Anda 27 Okt 2026:** C1 = 0, C2 = 13 baris: 11 material proses dengan kode dummy (`PR01K00000` ... `PR10K00000`,
> `0000000000`) dan 2 varian yang awalannya milik material bernama lain (`938L` 98 D vs 98 A, `5005` BSW-0032 vs BSW-032).
> Perbaikannya di bagian 1b.

Data lama yang menyimpang **tidak menghalangi** pekerjaan lain: ubah status saja, pakai di specsheet, dan harga tetap jalan.
Aturan ketat hanya dicek saat varian baru atau saat kode / warna / dimension diubah.

## 1b. Perbaikan data (DB Tools, setelah 0.1)

Keputusan Anda: 11 material proses -> material **Process** (kode dummy + harganya dihapus; sel draft tetap `NO COLOUR`, tidak kuning;
harga lewat quotation di CBD). `OUTSOLE TPU INJECTION HARDNESS 98 D PRM-091` digabung ke **`... 98 A PRM-091`** (di ERP 7 kode
`938L` bernama 98A, hanya 1 bernama 98D) dan `POLY WEBBING TAPE (BSW-0032)` ke **`POLY WEBBING TAPE (BSW-032)`**: varian, supplier,
harga, dan baris specsheet / CBD **draft** pindah; material lama jadi INACTIVE.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 1b.1 | Jalankan query **P1** dan **P2** (hanya membaca) | P1: 11 material, `used_published` = f, `cbd_lines` = 0, `prices` kosong / berakhir. P2: 4 baris, `used_published` = f. **Kalau ada yang beda, kirim hasilnya ke saya dulu** | |
| 1b.2 | Jalankan skrip **perbaikan** | Pesan `A. 11 material dijadikan Process`, `B. ... digabung ke ...` (2x), lalu `Perbaikan R20: varian menyimpang tersisa 0, ...` | |
| 1b.3 | Jalankan lagi skrip perbaikan | Aman: `A. 0 material ...`, `B. ... sudah digabung, dilewati` | |
| 1b.4 | Jalankan lagi **C2** | 0 baris | |
| 1b.5 | Master Material → `PRINTING` | Price method `Process (quotation)`, tanpa varian. `... 98 D ...` dan `(BSW-0032)` INACTIVE; varian dan supplier-nya ada di `98 A` / `BSW-032` | |
| 1b.6 | Specsheet draft yang memakai material itu | Baris proses tidak kuning; baris 98 D / BSW-0032 sekarang bernama 98 A / BSW-032 dengan kode yang sama | |

Skrip berhenti tanpa mengubah apa pun (pesan `Stop: ...`) bila material sudah dipakai dokumen terbit, kode dummy dipakai di CBD,
masih ada harga berlaku / menunggu, atau varian yang sama sudah ada di material tujuan. Kirim pesannya ke saya bila terjadi.

```sql
-- P1. Material proses berkode dummy yang akan dijadikan material Process
SELECT m.name AS material, m.uom, m.status, m.is_process,
       fn_material_used_published(m.id) AS used_published,
       string_agg(v.code || ' ' || v.color, ', ' ORDER BY v.code) AS variants,
       (SELECT count(*) FROM bom_cell bc JOIN material_variant x ON x.id = bc.variant_id WHERE x.material_id = m.id) AS spec_cells,
       (SELECT count(*) FROM cbd_line cl JOIN material_variant x ON x.id = cl.variant_id WHERE x.material_id = m.id) AS cbd_lines,
       (SELECT string_agg(fn_price_state(mp.status, mp.valid_from, mp.valid_to), ', ')
          FROM material_price mp JOIN material_variant x ON x.id = mp.variant_id WHERE x.material_id = m.id) AS prices
  FROM material m LEFT JOIN material_variant v ON v.material_id = m.id
 WHERE m.name IN ('HF WELDING', 'LAMINATING', 'PRINTING', 'PRINTING BLOCK', 'PRINTING LOGO', 'PRINTING SCREEN', 'PUFF PRINTING',
                  'PUNCH HOLE', 'SINGLE STICKER', 'TRANSFER PAPER', 'WORDING')
 GROUP BY m.id
 ORDER BY m.name;

-- P2. Material yang digabung (98 D -> 98 A, BSW-0032 -> BSW-032)
SELECT CASE WHEN m.name LIKE '%98 D%' OR m.name LIKE '%BSW-0032%' THEN 'dari (jadi INACTIVE)' ELSE 'ke' END AS role,
       m.name AS material, m.uom, m.status,
       fn_material_used_published(m.id) AS used_published,
       (SELECT string_agg(v.code || ' ' || v.color || ' ' || coalesce(v.thickness, ''), ', ' ORDER BY v.code)
          FROM material_variant v WHERE v.material_id = m.id) AS variants,
       (SELECT string_agg(s.name, ', ') FROM material_supplier ms JOIN supplier s ON s.id = ms.supplier_id
         WHERE ms.material_id = m.id) AS suppliers,
       (SELECT count(*) FROM bom_line l JOIN specsheet_revision r ON r.id = l.revision_id
         WHERE l.material_id = m.id AND l.is_active AND r.status = 'DRAFT') AS draft_spec_lines,
       (SELECT count(*) FROM cbd_line cl JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id
         WHERE cl.material_id = m.id AND cr.status = 'DRAFT') AS draft_cbd_lines
  FROM material m
 WHERE m.name IN ('OUTSOLE TPU INJECTION HARDNESS 98 D PRM-091', 'OUTSOLE TPU INJECTION HARDNESS 98 A PRM-091',
                  'POLY WEBBING TAPE (BSW-0032)', 'POLY WEBBING TAPE (BSW-032)')
 ORDER BY m.name, role;
```

```sql
-- Perbaikan data R20 (keputusan user 27 Okt 2026). Satu transaksi: ada yang tidak sesuai = semua dibatalkan dengan pesan.
--   A. 11 material proses berkode dummy -> material Process (varian dummy + harga lamanya dihapus, sel draft tetap, tidak kuning)
--   B. gabung: 98 D -> 98 A, BSW-0032 -> BSW-032 (varian, supplier, harga, baris draft pindah; material lama INACTIVE)
BEGIN;

DO $$
DECLARE
  v_names text[] := ARRAY['HF WELDING', 'LAMINATING', 'PRINTING', 'PRINTING BLOCK', 'PRINTING LOGO', 'PRINTING SCREEN',
                          'PUFF PRINTING', 'PUNCH HOLE', 'SINGLE STICKER', 'TRANSFER PAPER', 'WORDING'];
  v_pairs text[][] := ARRAY[['OUTSOLE TPU INJECTION HARDNESS 98 D PRM-091', 'OUTSOLE TPU INJECTION HARDNESS 98 A PRM-091'],
                            ['POLY WEBBING TAPE (BSW-0032)', 'POLY WEBBING TAPE (BSW-032)']];
  m   material%ROWTYPE;
  t   material%ROWTYPE;
  k   record;
  v_x text;
  v_n integer := 0;
  i   integer;
BEGIN
  -- ===== A. material Process =====
  FOR m IN SELECT * FROM material WHERE name = ANY (v_names) AND NOT is_process ORDER BY name LOOP
    IF fn_material_used_published(m.id) THEN
      RAISE EXCEPTION 'Stop: % sudah dipakai dokumen terbit. Kirim pesan ini ke Claude.', m.name;
    END IF;
    SELECT string_agg(DISTINCT cr.status, ', ') INTO v_x
      FROM cbd_line cl JOIN material_variant x ON x.id = cl.variant_id JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id
     WHERE x.material_id = m.id;
    IF v_x IS NOT NULL THEN
      RAISE EXCEPTION 'Stop: kode % dipakai di CBD (%). Kirim pesan ini ke Claude.', m.name, v_x;
    END IF;
    SELECT string_agg(DISTINCT fn_price_state(mp.status, mp.valid_from, mp.valid_to), ', ') INTO v_x
      FROM material_price mp JOIN material_variant x ON x.id = mp.variant_id
     WHERE x.material_id = m.id AND fn_price_state(mp.status, mp.valid_from, mp.valid_to) IN ('PENDING APPROVAL', 'ACTIVE', 'UPCOMING');
    IF v_x IS NOT NULL THEN
      RAISE EXCEPTION 'Stop: % masih punya harga (%). Kirim pesan ini ke Claude.', m.name, v_x;
    END IF;
    -- sel draft: lepas sambungan ke varian dummy (warna NO COLOUR tetap; material Process tidak kuning)
    UPDATE material_variant SET status = 'INACTIVE', updated_by = 'R20 perbaikan data' WHERE material_id = m.id;
    UPDATE bom_cell bc SET color = bc.color, updated_by = 'R20 perbaikan data'
      FROM material_variant x WHERE x.id = bc.variant_id AND x.material_id = m.id;
    DELETE FROM material_price mp USING material_variant x WHERE x.id = mp.variant_id AND x.material_id = m.id;
    DELETE FROM material_variant WHERE material_id = m.id;
    UPDATE material SET is_process = true, price_method = 'QUOTATION', updated_by = 'R20 perbaikan data' WHERE id = m.id;
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'A. % material dijadikan Process', v_n;

  -- ===== B. gabung material =====
  PERFORM set_config('app.variant_merge', 'on', true);
  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    SELECT * INTO m FROM material WHERE name = v_pairs[i][1];
    IF NOT FOUND THEN
      RAISE NOTICE 'B. % tidak ada (mungkin sudah digabung), dilewati', v_pairs[i][1];
      CONTINUE;
    END IF;
    SELECT * INTO t FROM material WHERE name = v_pairs[i][2] AND factory_id = m.factory_id AND uom = m.uom;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Stop: material tujuan % (UoM %) tidak ada di pabrik yang sama. Kirim pesan ini ke Claude.', v_pairs[i][2], m.uom;
    END IF;
    IF m.status = 'INACTIVE' AND NOT EXISTS (SELECT 1 FROM material_variant WHERE material_id = m.id) THEN
      RAISE NOTICE 'B. % sudah digabung, dilewati', m.name;
      CONTINUE;
    END IF;
    IF fn_material_used_published(m.id) THEN
      RAISE EXCEPTION 'Stop: % sudah dipakai dokumen terbit. Kirim pesan ini ke Claude.', m.name;
    END IF;
    IF EXISTS (SELECT 1 FROM cbd_line cl JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id
                WHERE cl.material_id = m.id AND cr.status <> 'DRAFT') THEN
      RAISE EXCEPTION 'Stop: % dipakai di CBD terbit. Kirim pesan ini ke Claude.', m.name;
    END IF;
    SELECT string_agg(v.code, ', ') INTO v_x FROM material_variant v JOIN material_variant w
        ON w.material_id = t.id AND w.thickness_key = v.thickness_key AND w.color_key = v.color_key
     WHERE v.material_id = m.id;
    IF v_x IS NOT NULL THEN
      RAISE EXCEPTION 'Stop: varian % sudah ada di % (dimension + warna sama). Kirim pesan ini ke Claude.', v_x, t.name;
    END IF;
    -- supplier: link material tujuan dibuat bila belum ada, harga varian ikut link tujuan
    FOR k IN SELECT * FROM material_supplier WHERE material_id = m.id LOOP
      INSERT INTO material_supplier (material_id, supplier_id, is_preferred, status, updated_by)
      SELECT t.id, k.supplier_id,
             k.is_preferred AND NOT EXISTS (SELECT 1 FROM material_supplier WHERE material_id = t.id AND is_preferred),
             k.status, 'R20 perbaikan data'
       WHERE NOT EXISTS (SELECT 1 FROM material_supplier WHERE material_id = t.id AND supplier_id = k.supplier_id);
      UPDATE material_price SET material_supplier_id = (SELECT id FROM material_supplier WHERE material_id = t.id AND supplier_id = k.supplier_id),
                                updated_by = 'R20 perbaikan data'
       WHERE material_supplier_id = k.id;
    END LOOP;
    UPDATE material_variant SET material_id = t.id, updated_by = 'R20 perbaikan data' WHERE material_id = m.id;
    UPDATE bom_line l SET material_id = t.id, updated_by = 'R20 perbaikan data'
      FROM specsheet_revision r WHERE r.id = l.revision_id AND r.status = 'DRAFT' AND l.material_id = m.id;
    UPDATE cbd_line cl SET material_id = t.id, updated_by = 'R20 perbaikan data'
      FROM cbd_revision cr WHERE cr.id = cl.cbd_revision_id AND cr.status = 'DRAFT' AND cl.material_id = m.id;
    UPDATE material SET status = 'INACTIVE', updated_by = 'R20 perbaikan data' WHERE id = m.id;
    RAISE NOTICE 'B. % digabung ke %', m.name, t.name;
  END LOOP;
  PERFORM set_config('app.variant_merge', 'off', true);
END;
$$;

-- hasil: harus 0 baris pelanggaran untuk material di atas
SELECT 'Perbaikan R20: varian menyimpang tersisa ' ||
       (SELECT count(*) FROM material_variant v
         WHERE cardinality(fn_variant_code_problems(v.factory_id, v.material_id, v.code, v.color, v.thickness, v.id)) > 0) ||
       ', material Process ' || (SELECT count(*) FROM material WHERE is_process) AS hasil;

COMMIT;
```

## 2. Nama material seragam (Vendor Spec)

Siapkan di Master Material: `UJI R20 KULIT` (kategori bebas, UoM `ME`), `UJI R20 SPONGE 50 KG` (UoM `ME`).

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 2.1 | Master Material → + Material `uji-r20  kulit.` UoM `ME` | Ditolak: `Material "UJI R20 KULIT" (ME) already exists in this factory (only spaces or punctuation differ). Use that material.` | |
| 2.2 | Sama tapi UoM `PRS` | Tersimpan (UoM beda = material beda) | |
| 2.3 | Edit `UJI R20 SPONGE 50 KG` → ganti nama `UJI R20 KULIT` dengan titik di akhir (`UJI R20 KULIT.`), UoM `ME` | Ditolak, pesan sama seperti 2.1 | |
| 2.4 | Specsheet draft → baris tambah, Material ketik `uji r20 kulit` + titik / strip (`UJI-R20 KULIT`) | Langsung dikenali sebagai `UJI R20 KULIT` (tidak ada `+ New material`). Kalau 2.2 dibuat, muncul pesan pilih salah satu (`UJI R20 KULIT (ME) / ... (PRS)`) | |
| 2.5 | Material ketik `UJI R20 SPONGE 60 KG` → + Add | `... is not in this factory's Master Material ...` **tanpa** `Did you mean` | |
| 2.6 | Material ketik `UJI R20 SPONG 50 KG` → + Add | `Did you mean: UJI R20 SPONGE 50 KG?` | |
| 2.7 | Klik `+ New material` → ketik nama `UJI R20 SPONGE 70 KG` | Daftar nama mirip **tidak** menampilkan `UJI R20 SPONGE 50 KG` (angka beda) | |

## 3. Material Code ketat (Material Detail, Vendor Spec)

Kode uji memakai awalan `U20A` / `U20B` dan kode `Z9x` supaya tidak bentrok dengan kode asli.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 3.1 | `UJI R20 KULIT` → + Variant `U20A99XZ91`, warna `UJI MERAH`, dimension `9,9mm` | Tersimpan (`9.9 MM`) | |
| 3.2 | + Variant `U20A99XZ92`, `UJI BIRU`, `9.9 MM` | Tersimpan | |
| 3.3 | Buat material `UJI R20 JARING` (ME) → + Variant `U20B88XZ91`, `UJI MERAH`, `8.8 MM` | Tersimpan (warna sama boleh di material lain dengan kode akhir sama) | |
| 3.4 | Form varian **tidak** punya centang `I checked it. This code matches ERP` lagi | Tidak ada centang | |
| 3.5 | `UJI R20 JARING` → ketik `U20A88XZ93`, `UJI HIJAU`, `8.8 MM` | Kotak merah sebelum Save: `This Material Code cannot be saved: Prefix U20A belongs to material UJI R20 KULIT ...`; Save → `This Material Code breaks the code rules (red box) ...` | |
| 3.6 | Ganti ke `U20C88XZ93` | Merah: `Material UJI R20 JARING uses prefix U20B ...` | |
| 3.7 | Ganti ke `U20B99XZ93` | Merah: `Dimension code 99X means 9.9 MM ..., not 8.8 MM.` | |
| 3.8 | Ganti ke `U20B87XZ93` | Merah: `Dimension 8.8 MM uses dimension code 88X ...` | |
| 3.9 | Ganti ke `U20B88XZ91` (warna tetap `UJI HIJAU`) | Merah: `Color code Z91 means UJI MERAH ...` | |
| 3.10 | Kode `U20B77XZ94`, warna `UJI MERAH`, dimension `7.7 MM` | Merah: `Color UJI MERAH in material UJI R20 JARING uses color code Z91 ...` | |
| 3.11 | Kotak merah berubah saat **warna / dimension** diubah (tanpa mengubah kode) | Kotak merah ikut berubah / hilang | |
| 3.12 | Kode `U20B88XZ93`, `UJI HIJAU`, `8.8 MM` → Save | Tersimpan | |
| 3.13 | Ketik kode yang sudah ada `U20A99XZ91` di form Material Detail | Merah: `Material Code U20A99XZ91 is already used: UJI R20 KULIT · 9.9 MM · UJI MERAH.` (tanpa tombol Use di halaman ini) | |
| 3.14 | Material baru `UJI R20 KARET` UoM `KG` → + Variant, warna `UJI MERAH`, dimension **kosong**: lihat usulan kode | Bagian **Dimension** di kotak usulan menunjukkan kode tengah dimension kosong untuk KG yang sudah tercatat (mis. `K00`), atau `never used yet` | |
| 3.15 | Simpan dengan kode `U20D` + kode tengah dari 3.14 (atau `K0X` bila belum ada) + `Z91` | Tersimpan | |
| 3.16 | + Variant `U20D800Z92`, `UJI BIRU`, dimension kosong | Merah: `No dimension (KG) uses dimension code ... , not 800.` | |
| 3.17 | (Bila C2 di bagian 1 ada isinya) buka salah satu varian itu → **Edit** → ubah **Status** saja → Save | Tersimpan tanpa kotak merah | |

## 4. Material Code hanya di Register (Specsheet, Vendor Spec)

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 4.1 | Baris tambah: ketik Material Code (mis. `U20A99XZ91`) di kolom **Material** → + Add | Ditolak: `U20A99XZ91 is a Material Code (UJI R20 KULIT). Type the material name here; Material Codes are entered with Register.` (tanpa + New material) | |
| 4.2 | Placeholder kolom Material | `Material name…` | |
| 4.3 | Baris `UJI R20 KULIT` · `9.9 mm`: ketik warna `uji merah` di sel → klik di luar (tanpa Enter) | Tersimpan `UJI MERAH`, langsung ada kode `U20A99XZ91`, **tidak kuning** | |
| 4.4 | Sel lain baris itu: ketik `u20a99xz92` → klik di luar | Tersimpan sebagai teks `U20A99XZ92`, **kuning** + tombol Register (tidak jadi `UJI BIRU`) | |
| 4.5 | Sel kuning | Hanya tombol **Register** (tidak ada Pick code / Use) | |
| 4.6 | Login Vendor CBD / Brand → specsheet draft | Read only, tanpa tombol Register | |

## 5. Use di modal Register (kode dari purchasing ternyata sudah terdaftar)

Siapkan material salah ketik `UJI R20 KULT` (UoM `ME`, tanpa varian). Dua model uji, misalnya `UJI R20 MODEL A` (2 article) dan
`UJI R20 MODEL B` (1 article).

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 5.1 | Model A → specsheet **Preview**: Material `UJI R20 KULT`, Dimension `9.9 mm`; article 1 warna `UJI MRH`, article 2 warna `UJI BIRU` → Publish | Terbit dengan sel kuning (peringatan) | |
| 5.2 | Model B → specsheet Preview **draft**: baris `UJI R20 KULT` · `9.9 mm`, warna `UJI MRH` | Sel kuning | |
| 5.3 | Model A → Next stage **SMS** (draft) | Sel `UJI MRH` dan `UJI BIRU` kuning | |
| 5.4 | Sel `UJI MRH` → **Register** → ketik `U20A99XZ91` | Kotak merah `Material Code U20A99XZ91 is already used: UJI R20 KULIT · 9.9 MM · UJI MERAH.` + tombol **Use U20A99XZ91 in the specsheet**; Save ditolak | |
| 5.5 | Klik tombol Use | Modal tertutup. Pesan hijau: `U20A99XZ91 (UJI R20 KULIT · 9.9 MM · UJI MERAH) used in 2 cells. 1 other draft updated too. Material UJI R20 KULT is no longer used in drafts and is now INACTIVE.` | |
| 5.6 | Baris itu sekarang | Material `UJI R20 KULIT`, article 1 `UJI MERAH` + kode, article 2 `UJI BIRU` **otomatis** dapat kode `U20A99XZ92`. Tombol **Undo replace** ada | |
| 5.7 | Model B draft | Sel jadi `UJI MERAH` + `U20A99XZ91` | |
| 5.8 | Model A revisi **Preview** yang sudah terbit | Masih `UJI R20 KULT` / `UJI MRH` (tidak berubah) | |
| 5.9 | Master Material → `UJI R20 KULT` | **INACTIVE** | |
| 5.10 | Model A SMS → **Undo replace** di baris itu | Kembali ke `UJI R20 KULT`; Master Material `UJI R20 KULT` **ACTIVE** lagi | |
| 5.11 | Baris `UJI R20 KULIT` dengan article 1 sudah berkode, article 2 warna `HIJAU UJI` (kuning) → Register di article 2 → kode `U20B88XZ93` → Use | Article 2 pindah ke **baris baru** komponen yang sama `UJI R20 JARING` · `8.8 MM` (`UJI HIJAU` + kode); baris lama: article 1 tetap, article 2 kosong | |
| 5.12 | Register sel kuning dengan kode baru yang benar (mis. `U20A99XZ95`) | Tersimpan seperti biasa, sel tersambung otomatis | |
| 5.13 | (opsional) Draft model lain sudah punya baris komponen yang sama dengan material + dimension kode tapi warna lain untuk article itu, lalu Use | Draft ini tetap pindah; pesan menambah `... stayed yellow (that line already has another color there).` | |

## 6. Cek cepat yang tidak berubah

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 6.1 | SMS dengan semua kode lengkap → Publish | Terbit | |
| 6.2 | Material Detail → edit varian yang dipakai dokumen terbit → ganti kode | Ditolak seperti sebelumnya (`used in published documents`) | |
| 6.3 | Material Process (`PRINTING`) di specsheet SMS / CBD | Tidak kuning; CBD baris Process = quotation | |

## 7. Bersih-bersih data uji (opsional)

Data uji bisa dibiarkan INACTIVE, atau hapus model / material `UJI R20 ...` lewat aplikasi seperti uji sebelumnya.

## 8. Bagian 2 (BARU, 28 Okt 2026): warna seragam + Dimension seperti dropdown

Sudah menjalankan R20 bagian 0 sampai 1b di DB Anda? **Cukup jalankan bagian 8 ini** (SQL 0a tidak perlu diulang).
Install baru: jalankan bagian 0 dulu, lalu bagian 8.

Isi bagian 2:
1. **Warna ditulis baku**: huruf besar, spasi dirapatkan, tanpa spasi di sekitar `/ - & + ,`
   (`black / white` jadi `BLACK/WHITE`). Berlaku di sel specsheet, form varian, dan data lama (warna varian + sel draft).
2. **Warna yang hanya beda spasi / tanda baca = warna yang sama**: `BLACK/WHITE` = `BLACK-WHITE` = `BLACK WHITE`.
   Varian kembar seperti itu ditolak; sel yang diketik `Black-White` langsung tersambung ke kode `BLACK/WHITE` dan
   ditulis seperti varian terdaftar.
3. **Urutan beda tetap warna lain**: `WHITE/BLACK` tidak sama dengan `BLACK/WHITE`. Sel kuning yang katanya sama tapi urutannya
   beda dengan warna terdaftar mendapat tombol **Did you mean BLACK/WHITE?** (tidak diganti otomatis).
   Singkatan (`BLK`) tidak diubah ke `BLACK`.
4. **Kolom Dimension di specsheet seperti dropdown**: ada tanda panah; diklik = semua dimension material itu (yang terisi
   dicentang). Saat mengetik, dimension **material lain** ikut muncul di bawah judul **Other materials** supaya dimension baru
   ditulis seperti yang sudah ada. Dimension baru tetap boleh diketik.
5. **Form varian di Material Detail**: kolom Dimension punya daftar pilihan (dimension material ini dulu, lalu material lain di
   pabrik ini). Di modal Register specsheet Dimension tetap terkunci dari baris.
6. Revisi yang **sudah terbit tidak diubah** (tulisan warna lama tetap).

### 8a. Pasang

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 8.1 | DB Tools → jalankan **query W1** (di bawah, hanya membaca) | Tidak ada baris **KEMBAR**. Kalau ada, **kirim hasilnya ke saya** dan jangan lanjut ke 8.2. Baris **KODE BEDA** hanya info (kirim juga) | |
| 8.2 | DB Tools → `z_run_sql` (prepared statements OFF) → tempel **seluruh SQL 0b** (di bawah) → Run | `R20 warna: varian kembar 0, sel kuning draft A -> B, warna varian belum baku 0` (catat A dan B; B boleh lebih kecil karena sel yang hanya beda tanda baca tersambung) | |
| 8.3 | Jalankan lagi SQL 0b | Aman: `... sel kuning draft B -> B ...` | |
| 8.4 | DB Tools → jalankan `sql/R_selftest.sql` (sudah diperbarui) | **`SELFTEST LOLOS`** | |
| 8.5 | Import `exports/build_r20.json` (timpa app), lalu Deploy | Nama app `Product Management R20` | |
| 8.6 | Page **Material Detail** → query `q_dimensions` ada, **Run behaviour Manual** | Ada, Manual | |
| 8.7 | Page **Login** / **Home** → `onPageLoad` tetap ON (seperti 0.5) | ON | |

Kalau 8.2 berhenti dengan `R20 warna: N kelompok varian kembar ...`: tidak ada yang diubah. Kirim hasil W1, saya buatkan
query perbaikannya.

### 8b. Uji (Vendor Spec)

Pakai material uji sendiri, mis. `UJI R20B KULIT` (ME) di Master Material.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 8.8 | Material Detail `UJI R20B KULIT` → + Variant: kode `U2BK160B0W`, warna `black / white`, Dimension `1.6mm` → Save | Tersimpan sebagai `BLACK/WHITE` · `1.6 MM` | |
| 8.9 | + Variant lagi: kode `U2BK160BXW`, warna `Black-White`, Dimension `1.6 MM` | **Ditolak**: `Variant BLACK-WHITE · 1.6 MM already exists in this material (code U2BK160B0W)...` | |
| 8.10 | Sama, warna `BLACK WHITE` | Ditolak juga | |
| 8.11 | + Variant: kode `U2BK160W0B`, warna `WHITE/BLACK`, Dimension `1.6 MM` | **Boleh** (urutan beda = warna lain) | |
| 8.12 | + Variant: klik kolom **Dimension** | Daftar: `1.6 MM` (this material) di atas, lalu dimension material lain (`other material`); ketik bebas tetap bisa. Batal | |
| 8.13 | Specsheet draft → tambah baris `UJI R20B KULIT` · `1.6 MM` → sel article 1 ketik `Black - White` | Sel jadi `BLACK/WHITE`, **tidak kuning**, kode `U2BK160B0W` | |
| 8.14 | Sel article 2 ketik `red / gold` | Tersimpan `RED/GOLD`, kuning (belum terdaftar) | |
| 8.15 | Sel article 2 ketik `white black` | Tersambung ke `WHITE/BLACK` (kunci sama) dan ditulis `WHITE/BLACK`, tidak kuning | |
| 8.16 | Material Detail → + Variant: kode `U2BK160N0R`, warna `NAVY/RED`, Dimension `1.6 MM`. Kembali ke specsheet, sel article 3 ketik `red / navy` | Kuning (`RED/NAVY`) + tombol **Did you mean NAVY/RED?**; klik → sel jadi `NAVY/RED` dengan kode `U2BK160N0R` | |
| 8.17 | Klik sel **Dimension** baris `UJI R20B KULIT` | Ada tanda panah; daftar dimension material itu, `1.6 MM` dicentang. Klik lagi di kotak = daftar tertutup | |
| 8.18 | Di sel Dimension yang sama ketik `0,8` (atau angka dimension material lain) | Di bawah judul **Other materials**: dimension material lain dengan `new for this material · used by N materials`. Esc = batal | |
| 8.19 | Baris tambah: pilih material yang punya beberapa dimension → klik kolom Dimension | Daftar penuh dimension material itu | |
| 8.20 | Sel kuning → **Register** | Modal Register: warna & Dimension terkunci dari sel/baris (tanpa daftar) | |
| 8.21 | Buka revisi yang **sudah terbit** yang punya warna dengan spasi (mis. `SNOW WHITE PEARLIZED / WHITE`) | Tulisan lama tetap (tidak diubah) | |
| 8.22 | Export Excel specsheet draft dari 8.13 | Warna tertulis `BLACK/WHITE` | |

Bersih-bersih: varian dan material `UJI R20B ...` bisa di-INACTIVE atau dihapus lewat aplikasi.

### W1. Cek warna (hanya membaca)

```sql
-- W1. Warna varian yang hanya beda spasi / tanda baca (hanya membaca; bisa dijalankan sebelum atau sesudah SQL 0b)
--   KEMBAR    = material + dimension sama -> SQL 0b berhenti sampai ini dibereskan
--   KODE BEDA = material sama, warna dianggap sama tapi 3 huruf akhir kode beda -> hanya info (merah saat varian diedit)
WITH v AS (
  SELECT v.id, v.factory_id, v.material_id, v.thickness_key, v.code, v.color, v.thickness, v.status,
         regexp_replace(lower(v.color), '[^a-z0-9]', '', 'g') AS k,
         EXISTS (SELECT 1 FROM bom_cell b JOIN bom_line l ON l.id = b.bom_line_id
                   JOIN specsheet_revision r ON r.id = l.revision_id AND r.status <> 'DRAFT'
                  WHERE b.variant_id = v.id) AS terbit
    FROM material_variant v),
g AS (
  SELECT 'KEMBAR' AS jenis, material_id, thickness_key, k, array_agg(id) AS ids FROM v
   GROUP BY material_id, thickness_key, k HAVING count(*) > 1
  UNION ALL
  SELECT 'KODE BEDA', material_id, NULL, k, array_agg(id) FROM v
   WHERE length(code) = 10
   GROUP BY material_id, k HAVING count(DISTINCT substr(code, 8, 3)) > 1)
SELECT g.jenis, f.name AS factory, m.name AS material, m.uom,
       string_agg(v.code || ' · ' || v.color || ' · ' || coalesce(nullif(v.thickness, ''), 'no dimension') || ' · ' || v.status
                  || CASE WHEN v.terbit THEN ' · TERBIT' ELSE '' END, E'\n' ORDER BY v.code) AS variants
  FROM g JOIN v ON v.id = ANY (g.ids)
  JOIN material m ON m.id = g.material_id JOIN factory f ON f.id = m.factory_id
 GROUP BY g.jenis, f.name, m.name, m.uom, g.thickness_key, g.k
 ORDER BY g.jenis DESC, f.name, m.name;
```

### 0b. SQL R20 bagian 2: warna (salin semua)

```sql
-- ============================================================================
-- R20 bagian 2 (27 Okt 2026): penulisan WARNA seragam. Jalankan SETELAH SQL 0a (R20), lewat z_run_sql di app "DB Tools"
-- (Use prepared statements = OFF). Aman diulang. Satu transaksi.
--   1. Bentuk baku warna (fn_clean_color): huruf besar, spasi dirapatkan, tanpa spasi di sekitar / - & + ,
--      ("black / white" -> "BLACK/WHITE").
--   2. Warna yang hanya beda spasi / tanda baca = warna yang sama (fn_color_key = fn_tight_key): BLACK/WHITE = BLACK-WHITE =
--      BLACK WHITE. Urutan beda (WHITE/BLACK) tetap warna lain. Singkatan (BLK) tidak diubah.
--   3. Sel specsheet yang tersambung ke varian memakai tulisan warna varian itu.
--   4. Data: warna varian dirapikan, sel draft dirapikan + disambung ulang. Revisi terbit tidak diubah.
--   Bila ada varian kembar (material + dimension sama, warna hanya beda tanda baca) SQL ini berhenti tanpa mengubah apa pun:
--   jalankan query W1 (bagian 1c) dan kirim hasilnya.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION fn_clean_color(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT btrim(regexp_replace(regexp_replace(upper(coalesce(p, '')), '\s+', ' ', 'g'), '\s*([/&+,-])\s*', '\1', 'g'))
$$;

CREATE OR REPLACE FUNCTION fn_color_key(p text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT fn_tight_key(p)
$$;

DO $$
DECLARE
  v_dup integer;
BEGIN
  SELECT count(*) INTO v_dup
    FROM (SELECT 1 FROM material_variant GROUP BY material_id, thickness_key, fn_color_key(color) HAVING count(*) > 1) x;
  IF v_dup > 0 THEN
    RAISE EXCEPTION 'R20 warna: % kelompok varian kembar (warna hanya beda spasi / tanda baca). Tidak ada yang diubah. Jalankan query W1 (bagian 1c) dan kirim hasilnya.', v_dup;
  END IF;
  IF (SELECT generation_expression FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'material_variant' AND column_name = 'color_key') NOT LIKE '%fn_color_key%' THEN
    ALTER TABLE material_variant DROP CONSTRAINT uq_variant_identity;
    ALTER TABLE material_variant DROP COLUMN color_key;
    ALTER TABLE material_variant ADD COLUMN color_key text GENERATED ALWAYS AS (fn_color_key(color)) STORED;
    ALTER TABLE material_variant ADD CONSTRAINT uq_variant_identity UNIQUE (material_id, thickness_key, color_key);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_bom_cell_set(p_token text, p_line_id uuid, p_article_id uuid, p_color text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid := fn_line_factory(p_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_line    bom_line%ROWTYPE;
  v_color   text := nullif(fn_clean_color(p_color), '');
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  IF NOT EXISTS (SELECT 1 FROM revision_article
                  WHERE revision_id = v_line.revision_id AND article_id = p_article_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'This article is not active in this revision.';
  END IF;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  VALUES (v_line.id, p_article_id, v_color, v_email)
  ON CONFLICT (bom_line_id, article_id) DO UPDATE SET color = EXCLUDED.color, updated_by = EXCLUDED.updated_by;
  RETURN v_line.id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_cell_variant()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_line record;
BEGIN
  NEW.color := nullif(fn_clean_color(NEW.color), '');
  IF NEW.color IS NULL THEN
    NEW.variant_id := NULL;
    RETURN NEW;
  END IF;
  SELECT material_id, thickness INTO v_line FROM bom_line WHERE id = NEW.bom_line_id;
  NEW.variant_id := fn_bom_variant_for(v_line.material_id, v_line.thickness, NEW.color);
  IF NEW.variant_id IS NOT NULL THEN        -- R20: tulisan warna mengikuti varian terdaftar (BLACK-WHITE -> BLACK/WHITE)
    SELECT color INTO NEW.color FROM material_variant WHERE id = NEW.variant_id;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_variant_for(p_material_id uuid, p_thickness text, p_color text)
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  SELECT v.id FROM material_variant v
   WHERE v.material_id = p_material_id
     AND v.thickness_key = fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''))
     AND v.color_key = fn_color_key(p_color)
     AND v.status = 'ACTIVE'
   LIMIT 1
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_take_cells(p_token text, p_email text, p_line_id uuid, p_arts uuid[], p_variant_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_line bom_line%ROWTYPE;
  v_var  material_variant%ROWTYPE;
  v_mat  material%ROWTYPE;
  v_to   uuid;
  v_new  uuid;
  v_busy text;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  SELECT * INTO v_var FROM material_variant WHERE id = p_variant_id;
  SELECT * INTO v_mat FROM material WHERE id = v_var.material_id;
  IF v_line.material_id = v_var.material_id AND fn_normalize(coalesce(v_line.thickness, '')) = v_var.thickness_key THEN
    UPDATE bom_cell SET color = v_var.color, updated_by = p_email
     WHERE bom_line_id = v_line.id AND article_id = ANY (p_arts);
    RETURN v_line.id;
  END IF;
  -- baris komponen yang sama yang sudah memakai material + dimension varian
  SELECT l.id INTO v_to FROM bom_line l
   WHERE l.revision_id = v_line.revision_id AND l.is_active AND l.id <> v_line.id
     AND l.material_id = v_var.material_id AND fn_normalize(coalesce(l.thickness, '')) = v_var.thickness_key
     AND l.parent_line_key IS NOT DISTINCT FROM v_line.parent_line_key
     AND CASE WHEN v_line.parent_line_key IS NULL
              THEN l.component_id IS NOT DISTINCT FROM v_line.component_id
                   AND l.local_component_no IS NOT DISTINCT FROM v_line.local_component_no
              ELSE l.sub_name IS NOT DISTINCT FROM v_line.sub_name END
   ORDER BY l.sort_order LIMIT 1;
  IF v_to IS NULL AND NOT EXISTS (
       SELECT 1 FROM bom_cell bc WHERE bc.bom_line_id = v_line.id AND bc.is_used AND bc.variant_id IS NOT NULL
          AND NOT (bc.article_id = ANY (p_arts))) THEN
    -- seluruh baris pindah (sel kuning lain ikut, tetap kuning sampai kodenya ada)
    v_new := fn_bom_replace_material(p_token, v_line.id, v_var.material_id, v_var.thickness);
    UPDATE bom_cell SET color = v_var.color, updated_by = p_email
     WHERE bom_line_id = v_new AND article_id = ANY (p_arts);
    RETURN v_new;
  END IF;
  IF v_to IS NOT NULL THEN
    SELECT string_agg(coalesce(a.code, a.colorway), ', ') INTO v_busy
      FROM bom_cell bc JOIN article a ON a.id = bc.article_id
     WHERE bc.bom_line_id = v_to AND bc.is_used AND bc.article_id = ANY (p_arts)
       AND fn_color_key(bc.color) <> v_var.color_key;
    IF v_busy IS NOT NULL THEN
      RAISE EXCEPTION 'The line % · % of this component already has another color for %. Fix that line first.',
        v_mat.name, fn_thickness_label(v_var.thickness), v_busy;
    END IF;
  ELSE
    IF v_line.parent_line_key IS NULL AND v_line.component_id IS NULL THEN
      RAISE EXCEPTION 'Local component % has other articles with Material Codes of another material. Add a line for % · % yourself, then type the code there.',
        v_line.local_component_no, v_mat.name, fn_thickness_label(v_var.thickness);
    END IF;
    PERFORM fn_bom_check_material(v_var.material_id, v_mat.factory_id);
    PERFORM fn_bom_check_supplier(v_var.material_id, v_line.supplier_id);
    INSERT INTO bom_line (revision_id, line_key, component_id, local_component_no, local_component_name, parent_line_key,
                          sub_seq, sub_name, material_id, thickness, supplier_id, process, sort_order, updated_by)
    VALUES (v_line.revision_id, gen_random_uuid(), v_line.component_id, v_line.local_component_no,
            v_line.local_component_name, v_line.parent_line_key,
            CASE WHEN v_line.parent_line_key IS NOT NULL THEN
              (SELECT coalesce(max(sub_seq), 0) + 1 FROM bom_line
                WHERE revision_id = v_line.revision_id AND is_active AND parent_line_key = v_line.parent_line_key) END,
            v_line.sub_name, v_var.material_id, v_var.thickness, v_line.supplier_id, v_line.process, v_line.sort_order, p_email)
    RETURNING id INTO v_to;
    PERFORM fn_bom_create_cells(v_to, p_email);
  END IF;
  INSERT INTO bom_cell (bom_line_id, article_id, color, updated_by)
  SELECT v_to, x, v_var.color, p_email FROM unnest(p_arts) AS x
  ON CONFLICT (bom_line_id, article_id) DO UPDATE SET color = EXCLUDED.color, updated_by = EXCLUDED.updated_by;
  UPDATE bom_cell SET color = NULL, updated_by = p_email
   WHERE bom_line_id = v_line.id AND article_id = ANY (p_arts);
  RETURN v_to;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_bom_use_variant(p_token text, p_line_id uuid, p_article_id uuid, p_variant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid := fn_line_factory(p_line_id);
  v_email   text := fn_auth_in(p_token, 'edit_specsheet', v_factory);
  v_line    bom_line%ROWTYPE;
  v_cell    bom_cell%ROWTYPE;
  v_var     material_variant%ROWTYPE;
  v_mat     material%ROWTYPE;
  v_src     material%ROWTYPE;
  v_tkey    text;
  v_ckey    text;
  v_cells   integer := 0;
  v_lines   integer := 0;
  v_revs    integer := 0;
  v_skip    integer := 0;
  v_off     text;
  v_revids  uuid[] := '{}';
  r         record;
BEGIN
  SELECT * INTO v_line FROM bom_line WHERE id = p_line_id;
  IF NOT FOUND OR NOT v_line.is_active THEN
    RAISE EXCEPTION 'Line not found or no longer active. Please reload the page.';
  END IF;
  PERFORM fn_revision_draft(v_line.revision_id);
  IF NOT EXISTS (SELECT 1 FROM revision_article
                  WHERE revision_id = v_line.revision_id AND article_id = p_article_id AND status = 'ACTIVE') THEN
    RAISE EXCEPTION 'This article is not active in this revision.';
  END IF;
  SELECT * INTO v_var FROM material_variant WHERE id = p_variant_id;
  IF NOT FOUND OR v_var.factory_id IS DISTINCT FROM v_factory THEN
    RAISE EXCEPTION 'Variant not found in this factory.';
  END IF;
  SELECT * INTO v_mat FROM material WHERE id = v_var.material_id;
  IF v_var.status <> 'ACTIVE' OR v_mat.status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'Material Code % is INACTIVE.', v_var.code;
  END IF;
  SELECT * INTO v_src FROM material WHERE id = v_line.material_id;
  v_tkey := fn_normalize(coalesce(v_line.thickness, ''));
  SELECT * INTO v_cell FROM bom_cell WHERE bom_line_id = v_line.id AND article_id = p_article_id;
  IF FOUND AND v_cell.is_used AND v_cell.variant_id IS NULL AND NOT v_src.is_process THEN
    v_ckey := fn_color_key(v_cell.color);
  END IF;

  IF v_ckey IS NULL THEN
    -- sel kosong / sudah berkode: hanya sel ini
    PERFORM fn_bom_take_cells(p_token, v_email, v_line.id, ARRAY[p_article_id], v_var.id);
    v_cells := 1;
    v_lines := 1;
  ELSE
    FOR r IN
      SELECT l.id, l.revision_id, array_agg(bc.article_id) AS arts
        FROM bom_line l
        JOIN specsheet_revision sr ON sr.id = l.revision_id AND sr.status = 'DRAFT'
        JOIN bom_cell bc ON bc.bom_line_id = l.id AND bc.variant_id IS NULL AND bc.is_used AND fn_color_key(bc.color) = v_ckey
        JOIN revision_article ra ON ra.revision_id = l.revision_id AND ra.article_id = bc.article_id AND ra.status = 'ACTIVE'
       WHERE l.is_active AND l.material_id = v_line.material_id AND fn_normalize(coalesce(l.thickness, '')) = v_tkey
       GROUP BY l.id, l.revision_id
       ORDER BY l.id = v_line.id DESC, l.revision_id, l.id
    LOOP
      IF r.id = v_line.id THEN
        PERFORM fn_bom_take_cells(p_token, v_email, r.id, r.arts, v_var.id);   -- baris yang diklik: gagal = pesan ke user
      ELSE
        BEGIN
          PERFORM fn_revision_draft(r.revision_id);
          PERFORM fn_bom_take_cells(p_token, v_email, r.id, r.arts, v_var.id);
        EXCEPTION WHEN others THEN
          v_skip := v_skip + cardinality(r.arts);                             -- bentrok di baris lain: dibiarkan kuning
          CONTINUE;
        END;
      END IF;
      v_cells := v_cells + cardinality(r.arts);
      v_lines := v_lines + 1;
      IF r.revision_id <> v_line.revision_id AND NOT (r.revision_id = ANY (v_revids)) THEN
        v_revids := v_revids || r.revision_id;
      END IF;
    END LOOP;
    v_revs := cardinality(v_revids);
  END IF;

  -- material lama tanpa varian yang sudah tidak dipakai di draft mana pun -> INACTIVE
  IF v_src.id <> v_var.material_id AND v_src.status = 'ACTIVE' AND NOT v_src.is_process
     AND NOT EXISTS (SELECT 1 FROM material_variant WHERE material_id = v_src.id)
     AND NOT EXISTS (SELECT 1 FROM bom_line l JOIN specsheet_revision sr ON sr.id = l.revision_id AND sr.status = 'DRAFT'
                      WHERE l.material_id = v_src.id AND l.is_active)
     AND NOT EXISTS (SELECT 1 FROM cbd_line cl JOIN cbd_revision cr ON cr.id = cl.cbd_revision_id AND cr.status = 'DRAFT'
                      WHERE cl.material_id = v_src.id) THEN
    UPDATE material SET status = 'INACTIVE', updated_by = v_email WHERE id = v_src.id;
    v_off := v_src.name;
  END IF;

  RETURN jsonb_build_object('code', v_var.code,
                            'label', v_mat.name || ' · ' || fn_thickness_label(v_var.thickness) || ' · ' || v_var.color,
                            'cells', v_cells, 'lines', v_lines, 'revisions', v_revs, 'skipped', v_skip, 'inactivated', v_off);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_cbd_estimate_hint(p_token text, p_line_id uuid)
 RETURNS TABLE(price numeric, currency text, reference text, source_label text, entered_on text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_line cbd_line%ROWTYPE;
BEGIN
  PERFORM fn_auth_in(p_token, 'view_cbd', fn_cbd_line_factory(p_line_id));
  SELECT * INTO v_line FROM cbd_line WHERE id = p_line_id;
  IF NOT FOUND OR v_line.supplier_id IS NULL THEN
    RETURN;
  END IF;
  RETURN QUERY
  SELECT x.price_original, x.currency, x.price_reference,
         pm.name || ' · ' || a.code || ' · ' || fn_rev_label(cr.stage, cr.revision_no)
           || CASE WHEN cr.status = 'DRAFT' THEN ' (draft)' ELSE '' END,
         to_char(x.updated_at AT TIME ZONE 'Asia/Jakarta', 'DD Mon YYYY')
    FROM cbd_line x
    JOIN cbd_revision cr ON cr.id = x.cbd_revision_id
    JOIN article a ON a.id = cr.article_id
    JOIN specsheet sh ON sh.id = a.specsheet_id
    JOIN product_model pm ON pm.id = sh.model_id
   WHERE x.price_source = 'ESTIMATE' AND x.id <> v_line.id AND x.status = 'ACTIVE'
     AND x.material_id = v_line.material_id AND x.supplier_id = v_line.supplier_id
     AND fn_normalize(coalesce(x.thickness, '')) = fn_normalize(coalesce(v_line.thickness, ''))
   ORDER BY (fn_color_key(x.color) = fn_color_key(v_line.color)) DESC, x.updated_at DESC
   LIMIT 1;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_material_variant_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory  uuid;
  v_other    record;
  v_tkey     text;
  v_ckey     text;
  v_problems text[];
BEGIN
  NEW.code      := upper(btrim(regexp_replace(coalesce(NEW.code, ''), '\s+', ' ', 'g')));
  NEW.color     := fn_clean_color(NEW.color);
  NEW.thickness := fn_clean_thickness(NEW.thickness);
  v_tkey := fn_normalize(coalesce(NEW.thickness, ''));
  v_ckey := fn_color_key(NEW.color);
  IF NEW.code = '' THEN
    RAISE EXCEPTION 'Material Code is required.';
  END IF;
  IF NEW.color = '' THEN
    RAISE EXCEPTION 'Color is required.';
  END IF;
  -- R20: pindah material hanya lewat skrip perbaikan data (gabung material kembar, app.variant_merge = on di transaksi itu)
  IF TG_OP = 'UPDATE' AND NEW.material_id IS DISTINCT FROM OLD.material_id
     AND coalesce(current_setting('app.variant_merge', true), '') <> 'on' THEN
    RAISE EXCEPTION 'A variant cannot be moved to another material.';
  END IF;
  SELECT factory_id INTO v_factory FROM material WHERE id = NEW.material_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Parent material not found.';
  END IF;
  IF TG_OP = 'UPDATE' AND v_factory IS DISTINCT FROM OLD.factory_id THEN
    RAISE EXCEPTION 'A variant cannot be moved to another factory.';
  END IF;
  NEW.factory_id := v_factory;

  -- TOLAK: kode unik per pabrik
  SELECT v.code, m.name, v.color, v.thickness INTO v_other
    FROM material_variant v JOIN material m ON m.id = v.material_id
   WHERE v.factory_id = NEW.factory_id AND v.code = NEW.code AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Material Code % is already used: % · % · %.',
      NEW.code, v_other.name, v_other.color, fn_thickness_label(v_other.thickness);
  END IF;

  -- TOLAK: satu kode per material + dimension + warna
  SELECT v.code INTO v_other
    FROM material_variant v
   WHERE v.material_id = NEW.material_id AND v.thickness_key = v_tkey AND v.color_key = v_ckey AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Variant % · % already exists in this material (code %). One color + dimension has one Material Code.',
      NEW.color, fn_thickness_label(NEW.thickness), v_other.code;
  END IF;

  -- R20 TOLAK: setiap bagian kode 10 karakter punya satu arti, dan sebaliknya
  IF length(NEW.code) = 10
     AND (TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code OR v_ckey IS DISTINCT FROM OLD.color_key
          OR NEW.thickness IS DISTINCT FROM OLD.thickness) THEN
    v_problems := fn_variant_code_problems(NEW.factory_id, NEW.material_id, NEW.code, NEW.color, NEW.thickness, NEW.id);
    IF cardinality(v_problems) > 0 THEN
      RAISE EXCEPTION 'Material Code % cannot be saved: %', NEW.code, array_to_string(v_problems, ' ');
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_variant_code_problems(p_factory uuid, p_material_id uuid, p_code text, p_color text, p_thickness text, p_exclude uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_code  text := upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g')));
  v_color text := fn_clean_color(p_color);
  v_thick text := fn_clean_thickness(p_thickness);
  v_tkey  text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey  text := fn_color_key(p_color);
  v_mat   material%ROWTYPE;
  v_out   text[] := '{}';
  r       record;
BEGIN
  IF length(v_code) <> 10 THEN
    RETURN v_out;
  END IF;
  SELECT * INTO v_mat FROM material WHERE id = p_material_id;
  -- kode -> arti: 4 awal = satu material
  SELECT x.material_id, x.code INTO r
    FROM (SELECT v.material_id, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND left(v.code, 4) = left(v_code, 4)
           GROUP BY v.material_id) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.material_id <> p_material_id THEN
    v_out := v_out || format('Prefix %s belongs to material %s (code %s). Register this variant in that material.',
                             left(v_code, 4), (SELECT name FROM material WHERE id = r.material_id), r.code);
  END IF;
  -- kode -> arti: 3 tengah = satu dimension
  SELECT x.tkey, x.thickness, x.code INTO r
    FROM (SELECT v.thickness_key AS tkey, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                 (array_agg(v.thickness ORDER BY v.created_at, v.code))[1] AS thickness
            FROM material_variant v
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND substr(v.code, 5, 3) = substr(v_code, 5, 3)
           GROUP BY v.thickness_key) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.tkey <> v_tkey THEN
    v_out := v_out || format('Dimension code %s means %s (code %s), not %s.',
                             substr(v_code, 5, 3), fn_thickness_label(r.thickness), r.code, fn_thickness_label(v_thick));
  END IF;
  -- kode -> arti: 3 akhir = satu warna
  SELECT x.ckey, x.color, x.code INTO r
    FROM (SELECT v.color_key AS ckey, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                 (array_agg(v.color ORDER BY v.created_at, v.code))[1] AS color
            FROM material_variant v
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND substr(v.code, 8, 3) = substr(v_code, 8, 3)
           GROUP BY v.color_key) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND v_ckey <> '' AND r.ckey <> v_ckey THEN
    v_out := v_out || format('Color code %s means %s (code %s), not %s.', substr(v_code, 8, 3), r.color, r.code, v_color);
  END IF;
  -- arti -> kode: satu material = satu awalan
  SELECT x.part, x.code INTO r
    FROM (SELECT left(v.code, 4) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.part <> left(v_code, 4) THEN
    v_out := v_out || format('Material %s uses prefix %s (code %s), not %s.', v_mat.name, r.part, r.code, left(v_code, 4));
  END IF;
  -- arti -> kode: satu dimension = satu kode tengah (dimension kosong: per UoM, mis. PRS = 800, KG = K00)
  SELECT x.part, x.code INTO r
    FROM (SELECT substr(v.code, 5, 3) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v JOIN material m ON m.id = v.material_id
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND v.thickness_key = v_tkey AND (v_tkey <> '' OR m.uom = v_mat.uom)
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.part <> substr(v_code, 5, 3) THEN
    v_out := v_out || CASE WHEN v_tkey = ''
      THEN format('No dimension (%s) uses dimension code %s (code %s), not %s.', v_mat.uom, r.part, r.code, substr(v_code, 5, 3))
      ELSE format('Dimension %s uses dimension code %s (code %s), not %s.', v_thick, r.part, r.code, substr(v_code, 5, 3)) END;
  END IF;
  -- arti -> kode: satu warna di material ini = satu kode akhir
  SELECT x.part, x.code INTO r
    FROM (SELECT substr(v.code, 8, 3) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND v.color_key = v_ckey
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND v_ckey <> '' AND r.part <> substr(v_code, 8, 3) THEN
    v_out := v_out || format('Color %s in material %s uses color code %s (code %s), not %s.',
                             v_color, v_mat.name, r.part, r.code, substr(v_code, 8, 3));
  END IF;
  RETURN v_out;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_variant_code_suggest(p_token text, p_material_id uuid, p_color text, p_thickness text)
 RETURNS TABLE(prefixes text, thickness_codes text, color_codes text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_email   text := fn_auth(p_token, 'view_master');
  v_factory uuid;
  v_uom     text;
  v_tkey    text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey    text := fn_color_key(p_color);
BEGIN
  SELECT factory_id, uom INTO v_factory, v_uom FROM material WHERE id = p_material_id;
  IF NOT FOUND OR NOT fn_can_see_factory(v_email, v_factory) THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT left(v.code, 4) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
        WHERE v.material_id = p_material_id AND length(v.code) = 10 GROUP BY 1) x),
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT substr(v.code, 5, 3) AS part, count(*) AS n, min(v.created_at) AS first_at
         FROM material_variant v JOIN material m ON m.id = v.material_id
        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v.thickness_key = v_tkey
          AND (v_tkey <> '' OR m.uom = v_uom) GROUP BY 1) x),
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT substr(v.code, 8, 3) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v_ckey <> '' AND v.color_key = v_ckey
          AND (v.material_id = p_material_id OR NOT EXISTS (
                 SELECT 1 FROM material_variant w WHERE w.material_id = p_material_id AND w.color_key = v_ckey
                    AND length(w.code) = 10))
        GROUP BY 1) x);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_variant_save(p_token text, p_id uuid, p_material_id uuid, p_code text, p_color text, p_thickness text, p_status text, p_confirm boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email text := fn_auth(p_token, 'manage_master');
  v_mat   material%ROWTYPE;
  v_old   material_variant%ROWTYPE;
  v_id    uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Variant status is required (ACTIVE / INACTIVE).';
  END IF;
  IF p_id IS NULL THEN
    SELECT * INTO v_mat FROM material WHERE id = p_material_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'Material not found.';
    END IF;
    PERFORM fn_assert_factory(v_email, v_mat.factory_id);
    IF v_mat.status = 'INACTIVE' THEN
      RAISE EXCEPTION 'Material % is INACTIVE. Activate it before adding variants.', v_mat.name;
    END IF;
    INSERT INTO material_variant (material_id, factory_id, code, color, thickness, status, updated_by)
    VALUES (p_material_id, v_mat.factory_id, p_code, p_color, p_thickness, p_status, v_email)
    RETURNING id INTO v_id;
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM material_variant WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Variant not found.';
  END IF;
  PERFORM fn_assert_factory(v_email, v_old.factory_id);
  IF (upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g'))) IS DISTINCT FROM v_old.code
      OR fn_color_key(p_color) IS DISTINCT FROM v_old.color_key
      OR fn_clean_thickness(p_thickness) IS DISTINCT FROM v_old.thickness)
     AND fn_variant_used_published(p_id) THEN
    RAISE EXCEPTION 'Variant % is used in published documents. Its Material Code, color, and dimension cannot be changed. Set it INACTIVE and register a new variant.', v_old.code;
  END IF;
  UPDATE material_variant
     SET code = p_code, color = p_color, thickness = p_thickness, status = p_status, updated_by = v_email
   WHERE id = p_id;
  RETURN p_id;
END;
$function$;

-- Data: warna varian dalam bentuk baku (kunci warna tidak berubah, jadi aturan kode tidak dicek ulang)
CREATE TEMP TABLE r20w_before ON COMMIT DROP AS
SELECT count(*) FILTER (WHERE bc.variant_id IS NULL) AS yellow
  FROM bom_cell bc JOIN bom_line l ON l.id = bc.bom_line_id
  JOIN specsheet_revision r ON r.id = l.revision_id AND r.status = 'DRAFT'
 WHERE bc.color IS NOT NULL AND bc.is_used;

UPDATE material_variant SET color = fn_clean_color(color), updated_by = 'R20 warna baku'
 WHERE color <> fn_clean_color(color);

-- Sel draft: rapikan + sambung ulang (trigger), tulisan ikut varian. Revisi terbit tidak disentuh.
UPDATE bom_cell bc SET color = bc.color, updated_by = 'R20 warna baku'
  FROM bom_line l
  JOIN specsheet_revision r ON r.id = l.revision_id AND r.status = 'DRAFT'
 WHERE bc.bom_line_id = l.id AND bc.color IS NOT NULL
   AND (bc.color <> fn_clean_color(bc.color) OR bc.variant_id IS NULL
        OR bc.color <> (SELECT v.color FROM material_variant v WHERE v.id = bc.variant_id));

SELECT 'R20 warna: varian kembar 0, sel kuning draft ' || b.yellow || ' -> ' ||
       (SELECT count(*) FROM bom_cell bc JOIN bom_line l ON l.id = bc.bom_line_id
          JOIN specsheet_revision r ON r.id = l.revision_id AND r.status = 'DRAFT'
         WHERE bc.color IS NOT NULL AND bc.is_used AND bc.variant_id IS NULL) ||
       ', warna varian belum baku ' || (SELECT count(*) FROM material_variant WHERE color <> fn_clean_color(color)) AS cek_r20_warna
  FROM r20w_before b;

COMMIT;
```

## 9. Bagian 3 (BARU, 28 Okt 2026): Dimension kosong per material + Dimension default

Sudah menjalankan R20 bagian 0 sampai 8 di DB Anda? **Cukup jalankan bagian 9 ini** (SQL 0a dan 0b tidak perlu diulang).
Install baru: bagian 0, lalu bagian 8, lalu bagian 9.

Isi bagian 3:
1. **Kode tengah untuk Dimension kosong ditentukan per material, bukan per UoM** (UoM bisa salah isi). Dalam satu material, varian
   tanpa Dimension wajib memakai satu kode tengah yang sama. Material lain boleh memakai kode kosong lain (`800`, `K00`, `C00` atau kode
   baru). Kode kosong tetap **tidak boleh** dipakai untuk Dimension berisi, dan sebaliknya (aturan kode -> arti tidak berubah).
2. **Usulan kode** di form varian: material yang belum punya varian tanpa Dimension mendapat usulan kode kosong yang sudah dikenal
   (UoM sama di depan), **hanya saran**: tulisan `(no dimension in other materials ... Use the ERP code)`.
3. **Dimension wajib terisi.** Tanpa Dimension = **`(None)`**, selalu **paling atas** di daftar Dimension (grid specsheet + form varian).
   Kotak Dimension dikosongkan = kembali ke `(None)`. Di database dan Excel tetap kosong (tidak tertulis "(None)").
4. **Dimension default**: setelah Material dipilih (baris tambah / subkomponen specsheet, + Variant di Material Detail), Dimension langsung
   terisi **dimension material itu dengan varian terbanyak** (sama banyak: yang paling dulu didaftarkan). Material belum punya varian =
   `(None)`. Ganti material di baris yang sudah ada: Dimension baris tetap bila terdaftar juga di material baru, selain itu default material
   baru (dulu: harus memilih dimension dulu). Default tetap bisa diganti.
5. **Save & add another** di form varian: Dimension yang baru disimpan tetap terisi untuk varian berikutnya.

### 9a. Pasang

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 9.1 | DB Tools → jalankan **query W2** (di bawah, hanya membaca) | Kirim hasilnya ke saya (info). Baris **SATU MATERIAL DUA KODE** / **BENTROK** tidak menghentikan SQL 0c, tapi varian itu akan merah saat kode / Dimension-nya diedit | |
| 9.2 | DB Tools → `z_run_sql` (prepared statements OFF) → tempel **seluruh SQL 0c** (di bawah) → Run | `R20 bagian 3: material dengan >1 kode Dimension kosong N, kode Dimension kosong dikenal 800, C00, K00` (catat) | |
| 9.3 | Jalankan lagi SQL 0c | Aman: hasil sama | |
| 9.4 | DB Tools → jalankan `sql/R_selftest.sql` (sudah diperbarui) | **`SELFTEST LOLOS`** | |
| 9.5 | Import `exports/build_r20.json` (timpa app), lalu Deploy | Nama app `Product Management R20` | |
| 9.6 | Page **Login** / **Home** → `onPageLoad` tetap ON (seperti 0.5); page **Material Detail** → `q_dimensions` **Manual** | ON / Manual | |

Langkah 9.2 dan 9.5 sebaiknya berurutan tanpa jeda: setelah SQL dan sebelum import, usulan kode di form varian app lama kosong (hanya
bantuan, data aman).

### 9b. Uji (Vendor Spec)

Pakai material uji sendiri: `UJI R20C LEM` (UoM `KG`), `UJI R20C SPON` (UoM `PRS`, sengaja "salah"), `UJI R20C MESH` (UoM `ME`).
Kode uji memakai Dimension yang jarang (`7.7 MM` = `770`, `8.8 MM` = `880`). Kalau di DB Anda dimension itu sudah punya kode lain,
form menolak dengan pesan `Dimension ... uses dimension code ...`: pakai kode tengah dari pesan itu.

| # | Langkah | Hasil | OK? |
|---|---|---|---|
| 9.7 | Material Detail `UJI R20C LEM` (belum ada varian) → **+ Variant** | Dimension terisi **`(None)`**. Klik kolom Dimension: `(None)` paling atas | |
| 9.8 | Warna `RED` | Usulan kode: Dimension `K00` + keterangan `(no dimension in other materials, same UoM first ...)` | |
| 9.9 | Kode `UR3LK00RED` → Save | Tersimpan, Dimension kosong (di tabel varian kosong / tanpa dimension) | |
| 9.10 | Material Detail `UJI R20C SPON` (UoM PRS) → + Variant: kode `UR3SK00RED`, warna `RED`, Dimension `(None)` → Save | **Boleh** (dulu ditolak: `No dimension (PRS) uses dimension code 800`) | |
| 9.11 | `UJI R20C SPON` → + Variant: kode `UR3S800BLK`, warna `BLACK`, Dimension `(None)` | **Merah, Save ditolak**: `Material UJI R20C SPON without dimension uses dimension code K00 ...` | |
| 9.12 | Sama, kode `UR3SK00BLK` → Save | Boleh | |
| 9.13 | `UJI R20C MESH` → + Variant: kode `UR3MK00RED`, warna `RED`, Dimension `7.7 MM` | **Merah**: `Dimension code K00 means no dimension ...` (kode kosong tidak boleh untuk dimension berisi) | |
| 9.14 | `UJI R20C MESH`: daftarkan `UR3M770RED` (RED, `7.7 MM`), `UR3M770BLK` (BLACK, `7.7 MM`), `UR3M880RED` (RED, `8.8 MM`). Pakai **Save & add another** | Setelah varian pertama, Dimension tetap `7.7 MM` untuk varian berikutnya | |
| 9.15 | Tutup, buka lagi **+ Variant** di `UJI R20C MESH` | Dimension terisi **`7.7 MM`** (2 varian, terbanyak). Daftar: `(None)`, `7.7 MM · 2 colors`, `8.8 MM · 1 color`, lalu material lain | |
| 9.16 | Kosongkan kotak Dimension, klik kolom lain | Kembali `(None)` | |
| 9.17 | Specsheet draft → baris tambah: Material `UJI R20C MESH` | Dimension langsung **`7.7 MM`** | |
| 9.18 | Di baris tambah yang sama ganti Material ke `UJI R20C LEM` | Dimension jadi **`(None)`** | |
| 9.19 | Ganti lagi ke `UJI R20C MESH`, Dimension pilih `8.8 MM`, simpan baris (Enter) | Baris tersimpan `UJI R20C MESH` · `8.8 MM` | |
| 9.20 | Klik sel Dimension baris itu | `(None)` paling atas, lalu `7.7 MM`, `8.8 MM` (dicentang) | |
| 9.21 | Pilih `(None)` | Baris jadi tanpa dimension (Replace Material, sel warna menyesuaikan, kuning bila belum ada varian) | |
| 9.22 | Ganti Material baris itu ke `UJI R20C LEM` | Langsung tersimpan, Dimension `(None)`. **Tidak** ada pesan "Now pick the dimension ..." lagi | |
| 9.23 | Tambah baris `UJI R20C LEM`, lalu ganti Material-nya ke `UJI R20C MESH` | Dimension jadi `7.7 MM` (LEM tanpa dimension; `(None)` tidak terdaftar di MESH -> default MESH) | |
| 9.24 | Sel kuning baris tanpa dimension → **Register** | Modal: Dimension `(None)`, terkunci | |
| 9.25 | Export Excel specsheet draft | Kolom Dimension baris tanpa dimension **kosong** (bukan "(None)") | |

Bersih-bersih: varian dan material `UJI R20C ...` bisa di-INACTIVE atau dihapus lewat aplikasi.

### W2. Cek kode Dimension kosong (hanya membaca)

```sql
-- W2. Kode tengah untuk Dimension kosong (hanya membaca)
--   SATU MATERIAL DUA KODE = satu material punya >1 kode tengah untuk Dimension kosong -> ditolak saat varian itu diedit
--   BENTROK               = kode tengah dipakai untuk Dimension kosong DAN Dimension berisi -> sudah ditolak sejak R20
--   SEBARAN               = info: kode tengah Dimension kosong per UoM (berapa material / varian)
WITH v AS (
  SELECT v.factory_id, v.material_id, m.name, m.uom, v.code, v.thickness_key, substr(v.code, 5, 3) AS mid, v.status
    FROM material_variant v JOIN material m ON m.id = v.material_id
   WHERE length(v.code) = 10)
SELECT 'SATU MATERIAL DUA KODE' AS jenis, f.name AS factory, v.name AS material, v.uom,
       string_agg(DISTINCT v.mid, ', ') AS kode_tengah, string_agg(v.code || ' · ' || v.status, E'\n' ORDER BY v.code) AS detail
  FROM v JOIN factory f ON f.id = v.factory_id
 WHERE v.thickness_key = ''
 GROUP BY f.name, v.material_id, v.name, v.uom HAVING count(DISTINCT v.mid) > 1
UNION ALL
SELECT 'BENTROK', f.name, NULL, NULL, v.mid,
       string_agg(v.code || ' · ' || coalesce(nullif(v.thickness_key, ''), 'no dimension') || ' · ' || v.name, E'\n' ORDER BY v.code)
  FROM v JOIN factory f ON f.id = v.factory_id
 GROUP BY f.name, v.factory_id, v.mid
HAVING bool_or(v.thickness_key = '') AND bool_or(v.thickness_key <> '')
UNION ALL
SELECT 'SEBARAN', f.name, NULL, v.uom, v.mid,
       count(DISTINCT v.material_id) || ' material, ' || count(*) || ' varian'
  FROM v JOIN factory f ON f.id = v.factory_id
 WHERE v.thickness_key = ''
 GROUP BY f.name, v.uom, v.mid
 ORDER BY 1 DESC, 2, 3, 4, 5;
```

### 0c. SQL R20 bagian 3: Dimension kosong per material (salin semua)

```sql
-- ============================================================================
-- R20 bagian 3 (28 Okt 2026): Dimension kosong + Dimension default. Jalankan SETELAH SQL 0a dan 0b (R20), lewat z_run_sql di
-- app "DB Tools" (Use prepared statements = OFF). Aman diulang. Satu transaksi. Data tidak diubah.
--   1. Material Code, Dimension kosong: kode tengah wajib sama DALAM SATU MATERIAL (dulu: sama per UoM di seluruh pabrik).
--      Material lain boleh memakai kode kosong lain (800 / K00 / C00 / kode baru). Kode kosong tetap tidak boleh dipakai untuk
--      dimension berisi, dan sebaliknya (aturan kode -> arti tidak berubah).
--   2. Usulan kode (fn_variant_code_suggest): material belum punya varian kosong -> kode kosong yang dikenal, UoM sama di depan,
--      hanya saran (kolom baru thickness_free).
--   3. "(None)" / "NONE" yang diketik di Dimension = tanpa dimension (fn_clean_thickness), sama seperti grid dan form varian.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM material_variant WHERE upper(btrim(thickness)) IN ('NONE', '(NONE)'))
     OR EXISTS (SELECT 1 FROM bom_line WHERE upper(btrim(thickness)) IN ('NONE', '(NONE)')) THEN
    RAISE EXCEPTION 'R20 bagian 3: ada Dimension bertulisan NONE di data. Tidak ada yang diubah. Kirim pesan ini ke Claude.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_clean_thickness(p text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE PARALLEL SAFE
AS $function$
DECLARE
  t text := upper(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')));
BEGIN
  IF t IN ('', '.', '-', 'NONE', '(NONE)') THEN       -- R20 bagian 3: (None) di daftar Dimension = tanpa dimension
    RETURN NULL;
  END IF;
  -- kutip miring ditulis sebagai kode \uXXXX (file ini hanya ASCII di bagian kode): karakter aslinya bisa berubah
  -- jadi kutip biasa saat isi file ditempel ke DB Tools (terjadi di uji user 20 Okt 2026)
  t := regexp_replace(t, '[\u201C\u201D\u201E\u201F\u2033\u3003\uFF02]', '"', 'g');
  t := regexp_replace(t, '[''\u2019\u2018\u2032`\u00B4]{2}', '"', 'g');
  t := regexp_replace(t, '(\d),(\d)', '\1.\2', 'g');
  t := regexp_replace(t, '(^|[^0-9.])\.(\d)', '\10.\2', 'g');
  t := regexp_replace(t, '(\d)\.(\d*[1-9])0+(?![0-9])', '\1.\2', 'g');
  t := regexp_replace(t, '(\d)\.0+(?![0-9])', '\1', 'g');
  t := regexp_replace(t, '(\d)\s*(INCHES|INCH|IN)(?=$|\s*X|\s*\(|\s*-|[^A-Z0-9\s])', '\1"', 'g');
  t := regexp_replace(t, '(\d)\s*(MM|CM|UM|ME)(?=$|[^A-Z]|X\d)', '\1 \2', 'g');
  t := regexp_replace(t, '(\d|MM|CM|UM|")\s*X\s*(?=\d)', '\1 X ', 'g');
  t := regexp_replace(t, '\s*-\s*', '-', 'g');
  t := regexp_replace(t, '\s*\(\s*', ' (', 'g');
  t := regexp_replace(t, '\s+\)', ')', 'g');
  t := regexp_replace(t, '(\d)\s+"', '\1"', 'g');
  t := regexp_replace(t, '(\d) (MM|CM|UM)-(\d+(?:\.\d+)?) \2(?=$|[^A-Z])', '\1-\3 \2', 'g');
  RETURN nullif(btrim(regexp_replace(t, '\s+', ' ', 'g')), '');
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_variant_code_problems(p_factory uuid, p_material_id uuid, p_code text, p_color text, p_thickness text, p_exclude uuid)
 RETURNS text[]
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_code  text := upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g')));
  v_color text := fn_clean_color(p_color);
  v_thick text := fn_clean_thickness(p_thickness);
  v_tkey  text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey  text := fn_color_key(p_color);
  v_mat   material%ROWTYPE;
  v_out   text[] := '{}';
  r       record;
BEGIN
  IF length(v_code) <> 10 THEN
    RETURN v_out;
  END IF;
  SELECT * INTO v_mat FROM material WHERE id = p_material_id;
  -- kode -> arti: 4 awal = satu material
  SELECT x.material_id, x.code INTO r
    FROM (SELECT v.material_id, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND left(v.code, 4) = left(v_code, 4)
           GROUP BY v.material_id) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.material_id <> p_material_id THEN
    v_out := v_out || format('Prefix %s belongs to material %s (code %s). Register this variant in that material.',
                             left(v_code, 4), (SELECT name FROM material WHERE id = r.material_id), r.code);
  END IF;
  -- kode -> arti: 3 tengah = satu dimension
  SELECT x.tkey, x.thickness, x.code INTO r
    FROM (SELECT v.thickness_key AS tkey, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                 (array_agg(v.thickness ORDER BY v.created_at, v.code))[1] AS thickness
            FROM material_variant v
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND substr(v.code, 5, 3) = substr(v_code, 5, 3)
           GROUP BY v.thickness_key) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.tkey <> v_tkey THEN
    v_out := v_out || format('Dimension code %s means %s (code %s), not %s.',
                             substr(v_code, 5, 3), fn_thickness_label(r.thickness), r.code, fn_thickness_label(v_thick));
  END IF;
  -- kode -> arti: 3 akhir = satu warna
  SELECT x.ckey, x.color, x.code INTO r
    FROM (SELECT v.color_key AS ckey, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                 (array_agg(v.color ORDER BY v.created_at, v.code))[1] AS color
            FROM material_variant v
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND substr(v.code, 8, 3) = substr(v_code, 8, 3)
           GROUP BY v.color_key) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND v_ckey <> '' AND r.ckey <> v_ckey THEN
    v_out := v_out || format('Color code %s means %s (code %s), not %s.', substr(v_code, 8, 3), r.color, r.code, v_color);
  END IF;
  -- arti -> kode: satu material = satu awalan
  SELECT x.part, x.code INTO r
    FROM (SELECT left(v.code, 4) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.part <> left(v_code, 4) THEN
    v_out := v_out || format('Material %s uses prefix %s (code %s), not %s.', v_mat.name, r.part, r.code, left(v_code, 4));
  END IF;
  -- arti -> kode: satu dimension = satu kode tengah. R20 bagian 3: dimension kosong = satu kode tengah PER MATERIAL
  -- (UoM tidak dipakai lagi: UoM bisa salah isi). Material lain boleh memakai kode kosong lain (800 / K00 / C00 ...).
  SELECT x.part, x.code INTO r
    FROM (SELECT substr(v.code, 5, 3) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v JOIN material m ON m.id = v.material_id
           WHERE v.factory_id = p_factory AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND v.thickness_key = v_tkey AND (v_tkey <> '' OR v.material_id = p_material_id)
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND r.part <> substr(v_code, 5, 3) THEN
    v_out := v_out || CASE WHEN v_tkey = ''
      THEN format('Material %s without dimension uses dimension code %s (code %s), not %s.', v_mat.name, r.part, r.code,
                  substr(v_code, 5, 3))
      ELSE format('Dimension %s uses dimension code %s (code %s), not %s.', v_thick, r.part, r.code, substr(v_code, 5, 3)) END;
  END IF;
  -- arti -> kode: satu warna di material ini = satu kode akhir
  SELECT x.part, x.code INTO r
    FROM (SELECT substr(v.code, 8, 3) AS part, count(*) AS n, min(v.created_at) AS first_at,
                 (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code
            FROM material_variant v
           WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.id IS DISTINCT FROM p_exclude
             AND v.color_key = v_ckey
           GROUP BY 1) x
   ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  IF FOUND AND v_ckey <> '' AND r.part <> substr(v_code, 8, 3) THEN
    v_out := v_out || format('Color %s in material %s uses color code %s (code %s), not %s.',
                             v_color, v_mat.name, r.part, r.code, substr(v_code, 8, 3));
  END IF;
  RETURN v_out;
END;
$function$;

DROP FUNCTION IF EXISTS fn_variant_code_suggest(text, uuid, text, text);
CREATE OR REPLACE FUNCTION public.fn_variant_code_suggest(p_token text, p_material_id uuid, p_color text, p_thickness text)
 RETURNS TABLE(prefixes text, thickness_codes text, color_codes text, thickness_free boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
-- R20 bagian 3: dimension kosong -> kode tengah material ini (wajib sama). Belum ada di material ini -> thickness_free = true:
-- kode kosong yang sudah dikenal di pabrik, UoM sama di depan (hanya saran, boleh yang lain / kode baru).
DECLARE
  v_email   text := fn_auth(p_token, 'view_master');
  v_factory uuid;
  v_uom     text;
  v_tkey    text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey    text := fn_color_key(p_color);
  v_own     boolean;
BEGIN
  SELECT factory_id, uom INTO v_factory, v_uom FROM material WHERE id = p_material_id;
  IF NOT FOUND OR NOT fn_can_see_factory(v_email, v_factory) THEN
    RETURN;
  END IF;
  v_own := v_tkey <> '' OR EXISTS (SELECT 1 FROM material_variant v WHERE v.material_id = p_material_id AND length(v.code) = 10
                                                                    AND v.thickness_key = '');
  RETURN QUERY SELECT
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT left(v.code, 4) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
        WHERE v.material_id = p_material_id AND length(v.code) = 10 GROUP BY 1) x),
    (SELECT string_agg(x.part, ',' ORDER BY (NOT v_own AND x.same_uom) DESC, x.n DESC, x.first_at) FROM (
       SELECT substr(v.code, 5, 3) AS part, count(*) AS n, min(v.created_at) AS first_at, bool_or(m.uom = v_uom) AS same_uom
         FROM material_variant v JOIN material m ON m.id = v.material_id
        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v.thickness_key = v_tkey
          AND (NOT v_own OR v_tkey <> '' OR v.material_id = p_material_id) GROUP BY 1) x),
    (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
       SELECT substr(v.code, 8, 3) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
        WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v_ckey <> '' AND v.color_key = v_ckey
          AND (v.material_id = p_material_id OR NOT EXISTS (
                 SELECT 1 FROM material_variant w WHERE w.material_id = p_material_id AND w.color_key = v_ckey
                    AND length(w.code) = 10))
        GROUP BY 1) x),
    NOT v_own;
END;
$function$;

SELECT 'R20 bagian 3: material dengan >1 kode Dimension kosong ' ||
       (SELECT count(*) FROM (SELECT material_id FROM material_variant WHERE length(code) = 10 AND thickness_key = ''
                               GROUP BY material_id HAVING count(DISTINCT substr(code, 5, 3)) > 1) x) ||
       ', kode Dimension kosong dikenal ' ||
       coalesce((SELECT string_agg(DISTINCT substr(code, 5, 3), ', ') FROM material_variant
                  WHERE length(code) = 10 AND thickness_key = ''), '-') AS cek_r20_dimension;

COMMIT;
```
