-- ============================================================================
-- R16 - Pembakuan penulisan thickness (15 Okt 2026, PLAN.md R16). Jalankan SETELAH R15_english.sql, lewat z_run_sql
-- di app "DB Tools" (Use prepared statements = OFF). Aman diulang. Satu transaksi. Tanpa reset data.
--
-- Mengapa: kunci pencocokan thickness = fn_normalize (huruf kecil, spasi dirapatkan) sehingga "1.2 MM" dan "1.2MM"
-- selama ini dianggap DUA thickness (varian dobel lolos). Sekarang fn_clean_thickness membuat satu bentuk baku (gaya berspasi,
-- sama dengan standar tim material):
--   - huruf besar, spasi ganda dirapikan, koma desimal jadi titik (1,2 -> 1.2)
--   - angka + satuan satu spasi: "1.2MM" -> "1.2 MM", `44 "` -> `44"`
--   - "X" antar ukuran berspasi: "1.2MMX44"" -> `1.2 MM X 44"`; tanpa spasi di sekitar "-": "1.4 - 1.6 MM" -> "1.4-1.6 MM"
--   - (20 Okt 2026) angka setara satu bentuk: "2.0" = "2", "1.50" = "1.5", ".5" = "0.5"; kutip pintar (” ″) dan "INCH" / "IN"
--     setelah angka jadi tanda kutip: `44”` = `44 INCH` = `44"`; rentang "1.4MM-1.6MM" = "1.4-1.6 MM"
--   - kosong, "." atau "-" = tanpa thickness (NULL), seperti sebelumnya
--   Sel kuning di draft yang setelah dibakukan cocok dengan varian disambungkan ulang.
--   Konfirmasi arti kode: dibandingkan dengan arti yang paling banyak dipakai bagian kode itu (seri: paling awal), sama dengan form.
-- Master Options: Order sekarang POSISI di daftar (1..n, tanpa kembar, kosong = paling akhir), lihat blok di bawah.
-- Nama material, kategori, warna, dan kode sudah huruf besar sejak F10b / R2b / R9, tidak diubah di sini.
--
-- Data lama: thickness di material_variant, bom_line, cbd_line dibakukan. Varian yang akan menabrak varian lain
-- (material + warna sama, thickness jadi sama) TIDAK diubah dan dilaporkan lewat NOTICE; selesaikan manual
-- (nonaktifkan / hapus salah satu), lalu jalankan file ini lagi.
-- ============================================================================
BEGIN;

DO $$
BEGIN
  IF to_regprocedure('fn_cbd_stage_options(text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'R15 belum terpasang. Jalankan sql/R15_english.sql dulu.';
  END IF;
END;
$$;

-- ---------------------------------------------------------------- bentuk baku thickness
-- Gaya berspasi, sama dengan standar tim material (file MATERIAL_CODE_KLASIFIKASI_v8): `1.8 MM X 36"`, `2 MM (95 X 152 CM)`.
-- Urutan: rapikan spasi + huruf besar -> kutip pintar (” ″ “) dan dua apostrof jadi tanda kutip -> koma desimal -> angka:
-- ".5" jadi "0.5", nol di belakang koma dibuang ("2.0" = "2", "1.50" = "1.5"; keputusan user 20 Okt 2026) -> "INCH" / "IN" setelah
-- angka jadi tanda kutip -> satuan (MM / CM / UM / ME) diberi satu spasi dari angkanya -> "X" antar ukuran diberi spasi di kedua
-- sisi -> tanpa spasi di sekitar "-" -> spasi sebelum "(" dan tidak ada spasi dalam kurung -> tanda kutip menempel pada angka ->
-- rentang dengan satuan di kedua sisi ("1.4 MM-1.6 MM") jadi "1.4-1.6 MM". Hasilnya idempoten (dibakukan dua kali = sama).
-- Kata biasa ("MAX 5", "SIZE 37-39", "LEBAR=140 CM") hanya dirapikan spasinya; "SZ" tidak diubah jadi "SIZE" (itu isi).
-- Sama persis dengan canonThickness di cwBomGrid dan cwVariantForm (ubah ketiganya bersamaan).
CREATE OR REPLACE FUNCTION fn_clean_thickness(p text) RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
DECLARE
  t text := upper(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')));
BEGIN
  IF t IN ('', '.', '-') THEN
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
$$;

-- ---------------------------------------------------------------- konfirmasi arti kode (review 20 Okt 2026)
-- Arti bagian thickness (5-7) / warna (8-10) Material Code = yang paling banyak memakainya (seri: paling awal). Satu pengecualian yang sudah
-- dikonfirmasi (mis. 404 = 58") tidak lagi membuat varian normal (404 = 44") diminta konfirmasi.
CREATE OR REPLACE FUNCTION public.fn_material_variant_check()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_factory uuid;
  v_other   record;
  v_tkey    text;
  v_ckey    text;
  v_confirm boolean := coalesce(current_setting('app.variant_confirm', true), '') = 'on';
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
  IF TG_OP = 'UPDATE' AND NEW.material_id IS DISTINCT FROM OLD.material_id THEN
    RAISE EXCEPTION 'A variant cannot be moved to another material.';
  END IF;
  SELECT factory_id INTO v_factory FROM material WHERE id = NEW.material_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Parent material not found.';
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

  -- TOLAK: satu kode per material + thickness + warna
  SELECT v.code INTO v_other
    FROM material_variant v
   WHERE v.material_id = NEW.material_id AND v.thickness_key = v_tkey AND v.color_key = v_ckey AND v.id <> NEW.id;
  IF FOUND THEN
    RAISE EXCEPTION 'Variant % · % already exists in this material (code %). If ERP really has another code, make the color name differ as in ERP (e.g. WHITE C).',
      NEW.color, fn_thickness_label(NEW.thickness), v_other.code;
  END IF;

  -- KONFIRMASI: bagian kode ERP (10 karakter) yang sudah punya arti lain di pabrik ini.
  -- Hanya dicek saat varian baru atau kode / warna / thickness berubah (ubah status saja tidak ditanya lagi).
  IF length(NEW.code) = 10 AND NOT v_confirm
     AND (TG_OP = 'INSERT' OR NEW.code IS DISTINCT FROM OLD.code OR NEW.color IS DISTINCT FROM OLD.color
          OR NEW.thickness IS DISTINCT FROM OLD.thickness) THEN
    -- R16 (review): arti bagian kode = thickness yang PALING BANYAK memakainya (seri: yang tercatat paling awal), sama dengan
    -- fn_variant_code_hint / form. Dulu dicari varian pertama yang BERBEDA, sehingga setelah satu pengecualian dikonfirmasi
    -- (404 = 58") semua varian normal (404 = 44") ikut diminta konfirmasi.
    SELECT x.code, x.thickness, x.tkey INTO v_other
      FROM (SELECT v.thickness_key AS tkey, count(*) AS n, min(v.created_at) AS first_at,
                   (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                   (array_agg(v.thickness ORDER BY v.created_at, v.code))[1] AS thickness
              FROM material_variant v
             WHERE v.factory_id = NEW.factory_id AND length(v.code) = 10 AND v.id <> NEW.id
               AND substr(v.code, 5, 3) = substr(NEW.code, 5, 3)
             GROUP BY v.thickness_key) x
     ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
    IF FOUND AND v_other.tkey <> v_tkey THEN
      RAISE EXCEPTION 'Confirmation needed: thickness code % is recorded as "%" (code %), not "%". Check the Material Code; if it matches ERP, tick the confirmation and save.',
        substr(NEW.code, 5, 3), fn_thickness_label(v_other.thickness), v_other.code, fn_thickness_label(NEW.thickness);
    END IF;
    SELECT x.code, x.color, x.ckey INTO v_other
      FROM (SELECT v.color_key AS ckey, count(*) AS n, min(v.created_at) AS first_at,
                   (array_agg(v.code ORDER BY v.created_at, v.code))[1] AS code,
                   (array_agg(v.color ORDER BY v.created_at, v.code))[1] AS color
              FROM material_variant v
             WHERE v.factory_id = NEW.factory_id AND length(v.code) = 10 AND v.id <> NEW.id
               AND substr(v.code, 8, 3) = substr(NEW.code, 8, 3)
             GROUP BY v.color_key) x
     ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
    IF FOUND AND v_other.ckey <> v_ckey THEN
      RAISE EXCEPTION 'Confirmation needed: color code % is recorded as "%" (code %), not "%". Check the Material Code; if it matches ERP, tick the confirmation and save.',
        substr(NEW.code, 8, 3), v_other.color, v_other.code, NEW.color;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_variant_code_hint(p_token text, p_material_id uuid, p_code text, p_exclude uuid)
 RETURNS TABLE(code text, thickness_known boolean, thickness text, thickness_ref text, color_known boolean, color text, color_ref text, other_prefixes text)
 LANGUAGE plpgsql
AS $function$
#variable_conflict use_column
DECLARE
  v_email   text := fn_auth(p_token, 'view_master');
  v_factory uuid;
  v_code    text := upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', ' ', 'g')));
  v_t       record;
  v_c       record;
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
  RETURN QUERY SELECT
    v_code,
    v_t.code IS NOT NULL, v_t.thickness, v_t.code,
    v_c.code IS NOT NULL, v_c.color, v_c.code,
    (SELECT string_agg(DISTINCT left(mv.code, 4), ', ') FROM material_variant mv
      WHERE mv.material_id = p_material_id AND mv.id IS DISTINCT FROM p_exclude
        AND length(mv.code) = 10 AND left(mv.code, 4) <> left(v_code, 4));
END;
$function$;

-- ---------------------------------------------------------------- data lama
DO $$
DECLARE
  v_var   integer;
  v_skip  integer;
  v_bom   integer;
  v_cbd   integer;
  v_rel   integer;
  r       record;
BEGIN
  -- varian yang akan bertabrakan setelah dibakukan: grup (material, warna, kunci thickness baru) berisi > 1 baris
  CREATE TEMP TABLE r16_skip ON COMMIT DROP AS
  SELECT v.id
    FROM material_variant v
   WHERE (v.material_id, v.color_key, fn_normalize(coalesce(fn_clean_thickness(v.thickness), ''))) IN (
           SELECT material_id, color_key, fn_normalize(coalesce(fn_clean_thickness(thickness), ''))
             FROM material_variant
            GROUP BY 1, 2, 3
           HAVING count(*) > 1 AND bool_or(thickness IS DISTINCT FROM fn_clean_thickness(thickness)));

  SELECT count(*) INTO v_skip FROM r16_skip;
  FOR r IN SELECT m.name, v.code, v.color, v.thickness
             FROM material_variant v JOIN material m ON m.id = v.material_id
            WHERE v.id IN (SELECT id FROM r16_skip) ORDER BY m.name, v.color, v.code LOOP
    RAISE NOTICE 'R16 dilewati (bentrok setelah dibakukan): % | % | % | kode %', r.name, r.color, r.thickness, r.code;
  END LOOP;

  -- kunci penguncian dokumen terbit dimatikan sebentar: ini hanya penulisan ulang teks thickness (kuncinya sama)
  ALTER TABLE bom_line DISABLE TRIGGER trg_lock_published;
  ALTER TABLE cbd_line DISABLE TRIGGER trg_lock_published;
  PERFORM set_config('app.variant_confirm', 'on', true);   -- arti kode thickness dicek ulang oleh trigger varian

  UPDATE material_variant v
     SET thickness = fn_clean_thickness(v.thickness)
   WHERE v.thickness IS DISTINCT FROM fn_clean_thickness(v.thickness)
     AND v.id NOT IN (SELECT id FROM r16_skip);
  GET DIAGNOSTICS v_var = ROW_COUNT;

  UPDATE bom_line SET thickness = fn_clean_thickness(thickness)
   WHERE thickness IS DISTINCT FROM fn_clean_thickness(thickness);
  GET DIAGNOSTICS v_bom = ROW_COUNT;

  UPDATE cbd_line SET thickness = fn_clean_thickness(thickness)
   WHERE thickness IS DISTINCT FROM fn_clean_thickness(thickness);
  GET DIAGNOSTICS v_cbd = ROW_COUNT;

  PERFORM set_config('app.variant_confirm', 'off', true);
  ALTER TABLE bom_line ENABLE TRIGGER trg_lock_published;
  ALTER TABLE cbd_line ENABLE TRIGGER trg_lock_published;

  -- sel kuning di draft yang kini cocok dengan varian (mis. baris "2.0 MM" dan varian "2 MM") disambungkan ulang
  -- (trg_bom_cell_variant mencari varian lagi); dokumen terbit tidak disentuh
  UPDATE bom_cell bc
     SET color = bc.color
    FROM bom_line l
    JOIN specsheet_revision sr ON sr.id = l.revision_id AND sr.status = 'DRAFT'
   WHERE bc.bom_line_id = l.id AND bc.color IS NOT NULL AND bc.variant_id IS NULL
     AND fn_bom_variant_for(l.material_id, l.thickness, bc.color) IS NOT NULL;
  GET DIAGNOSTICS v_rel = ROW_COUNT;
  RAISE NOTICE 'R16: varian dibakukan % (dilewati %), baris BOM %, baris CBD %, sel kuning tersambung %',
    v_var, v_skip, v_bom, v_cbd, v_rel;
END;
$$;

-- ---------------------------------------------------------------- Urutan master option (Order = posisi, tanpa angka kembar)
-- Sebelumnya Order boleh kosong (tampil paling bawah) dan boleh kembar (dua "10"). Sekarang Order = POSISI di daftar per jenis (dan
-- per pabrik untuk Last / Outsole Mold): selalu 1..n tanpa lubang dan tanpa kembar.
--   - Order kosong saat menambah = paling akhir; saat mengubah = posisi tidak berubah.
--   - Order yang sudah dipakai: baris ini mengambil posisi itu dan baris lain bergeser ke bawah (10 sudah ada, ketik 10 = menyisip di 10).
--   - Order lebih besar dari jumlah baris = paling akhir. Size (UKURAN) tidak berubah: Order selalu = angka ukurannya.
--   - (20 Okt 2026) pindah ke bawah: baris ini berada TEPAT di posisi yang diketik (A,B,C,D: A ke 3 = B,C,A,D), bukan satu di atasnya.
--     Posisi lama dibaca dari baris itu sendiri, jadi fn_option_save tidak mengubah sort_order sebelum memanggil fungsi ini.
CREATE OR REPLACE FUNCTION fn_option_renumber(p_kind text, p_factory uuid, p_moved uuid, p_wanted integer) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_down boolean;
BEGIN
  IF p_kind = 'UKURAN' THEN
    RETURN;
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('option-order:' || p_kind || ':' || coalesce(p_factory::text, 'shared')));
  -- pindah ke bawah = angka baru lebih besar dari posisi sekarang: bila seri, baris ini sesudah baris yang sudah di sana
  SELECT p_wanted IS NOT NULL AND sort_order IS NOT NULL AND p_wanted > sort_order INTO v_down
    FROM model_option WHERE id = p_moved;
  UPDATE model_option o
     SET sort_order = r.rn
    FROM (SELECT id,
                 row_number() OVER (ORDER BY
                   CASE WHEN id = p_moved AND p_wanted IS NOT NULL THEN p_wanted ELSE coalesce(sort_order, 2147483647) END,
                   CASE WHEN id = p_moved THEN CASE WHEN coalesce(v_down, false) THEN 1 ELSE -1 END ELSE 0 END,
                   value_key) AS rn
            FROM model_option
           WHERE kind = p_kind AND factory_id IS NOT DISTINCT FROM p_factory) r
   WHERE o.id = r.id AND o.sort_order IS DISTINCT FROM r.rn;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_option_save(p_token text, p_id uuid, p_kind text, p_value text, p_sort_order integer, p_status text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_email   text := fn_auth(p_token, 'manage_master');
  v_factory uuid := fn_user_factory(v_email);
  v_old     model_option%ROWTYPE;
  v_used    text;
  v_id      uuid;
BEGIN
  IF coalesce(p_status, '') NOT IN ('ACTIVE', 'INACTIVE') THEN
    RAISE EXCEPTION 'Option status is required (ACTIVE / INACTIVE).';
  END IF;
  IF p_id IS NULL THEN
    IF p_kind IS NULL OR p_kind NOT IN ('KATEGORI', 'CONSTRUCTION', 'GENDER', 'UKURAN', 'LAST', 'OUTSOLE_MOLD') THEN
      RAISE EXCEPTION 'Select an option type.';
    END IF;
    IF fn_option_is_factory_kind(p_kind) AND v_factory IS NULL THEN
      RAISE EXCEPTION '% is set per factory, but your account has no factory.', fn_option_kind_label(p_kind);
    END IF;
    INSERT INTO model_option (kind, factory_id, value, sort_order, status, updated_by)
    VALUES (p_kind, CASE WHEN fn_option_is_factory_kind(p_kind) THEN v_factory END, p_value, p_sort_order, p_status, v_email)
    RETURNING id INTO v_id;
    PERFORM fn_option_renumber(p_kind, CASE WHEN fn_option_is_factory_kind(p_kind) THEN v_factory END, v_id, p_sort_order);
    RETURN v_id;
  END IF;
  SELECT * INTO v_old FROM model_option WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Option not found.';
  END IF;
  IF v_old.factory_id IS NOT NULL THEN
    PERFORM fn_assert_factory(v_email, v_old.factory_id);
  END IF;
  IF fn_normalize(p_value) IS DISTINCT FROM v_old.value_key THEN
    IF v_old.kind = 'UKURAN' THEN
      SELECT string_agg(pm.name, ', ' ORDER BY pm.name) INTO v_used
        FROM product_model pm WHERE v_old.value ~ '^[0-9]+$' AND v_old.value::integer = ANY (pm.sizes);
    ELSE
      SELECT string_agg(DISTINCT pm.name, ', ') INTO v_used
        FROM product_model pm
       WHERE p_id IN (pm.category_id, pm.construction_id, pm.gender_id, pm.last_id, pm.outsole_mold_id)
         AND EXISTS (SELECT 1 FROM specsheet sh JOIN specsheet_revision r ON r.specsheet_id = sh.id
                      WHERE sh.model_id = pm.id AND r.status = 'PUBLISHED');
    END IF;
    IF v_used IS NOT NULL THEN
      RAISE EXCEPTION '% "%" is used by model %, so its value cannot be changed. Set it INACTIVE and add a new value.',
        fn_option_kind_label(v_old.kind), v_old.value, left(v_used, 200);
    END IF;
  END IF;
  -- sort_order tidak diubah di sini: fn_option_renumber membaca posisi lama untuk tahu arah pindah
  UPDATE model_option SET value = p_value, status = p_status, updated_by = v_email
   WHERE id = p_id;
  PERFORM fn_option_renumber(v_old.kind, v_old.factory_id, p_id, p_sort_order);
  RETURN p_id;
END;
$function$;

-- data lama: nomori ulang tiap jenis (dan pabrik) berurutan 1..n, mempertahankan urutan sekarang (Order kosong di bawah, seri
-- diurutkan menurut nama)
DO $$
DECLARE
  r record;
  v_n integer := 0;
BEGIN
  FOR r IN SELECT DISTINCT kind, factory_id FROM model_option WHERE kind <> 'UKURAN' LOOP
    PERFORM fn_option_renumber(r.kind, r.factory_id, NULL, NULL);
    v_n := v_n + 1;
  END LOOP;
  RAISE NOTICE 'R16: urutan master option dinomori ulang untuk % kelompok', v_n;
END;
$$;

SELECT 'R16 terpasang' AS hasil
UNION ALL SELECT 'thickness baku: ' || fn_clean_thickness('1,2mm') || ' | ' || fn_clean_thickness('1.0MMX44"') || ' | ' || fn_clean_thickness('1,4mm - 1,60mm x 44 inch')
UNION ALL SELECT 'varian belum baku: ' || count(*)::text FROM material_variant
  WHERE thickness IS DISTINCT FROM fn_clean_thickness(thickness)
UNION ALL SELECT 'Order option kembar / kosong: ' || count(*)::text FROM (SELECT 1 FROM model_option WHERE kind <> 'UKURAN'
  GROUP BY kind, factory_id, sort_order HAVING count(*) > 1 OR sort_order IS NULL) z
UNION ALL SELECT 'trigger kunci aktif: ' || (SELECT count(*)::text FROM pg_trigger
  WHERE tgname = 'trg_lock_published' AND tgenabled = 'O' AND tgrelid IN ('bom_line'::regclass, 'cbd_line'::regclass));

COMMIT;
