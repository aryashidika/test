-- ============================================================================
-- R21 Appsmith: kamus kode ERP per pabrik (30 Okt 2026) - BAGIAN 1 dari 2: tabel, fungsi, trigger
-- Jalankan lewat z_run_sql di app "DB Tools" (Use prepared statements = OFF). Satu transaksi. Aman diulang.
-- Sesudah ini jalankan isi kamus: sql/R21_kamus_isi_1.sql ... R21_kamus_isi_6.sql (urutan bebas, aman diulang).
-- Sebelum isi kamus dimuat semua aturan tetap seperti R20 (kamus kosong = tidak dipakai).
--
-- Isi (PLAN §6 R21):
--   1. fn_clean_thickness: "NO.1" tidak jadi "NO0.1" (titik sesudah huruf bukan desimal)
--   2. tabel code_dict_material (awalan 4), code_dict_dimension (kode tengah 3), code_dict_color (kode akhir 3);
--      satu kode = satu arti (kunci factory_id + code), satu teks boleh beberapa kode (data ERP)
--   3. kamus dipakai untuk arah kode -> arti (fn_variant_code_problems, fn_variant_code_hint, fn_variant_code_decode);
--      arah arti -> kode tetap dari varian app (R20). Susun otomatis (fn_variant_compose) dan saran (fn_variant_code_suggest)
--      memakai kamus hanya bila varian app belum tahu, dan hanya teks yang punya TEPAT SATU kode di kamus
--   4. varian berkode 10 karakter disimpan -> bagian kode yang belum ada masuk kamus (source REGISTER, trigger trg_r21_dict_learn)
--   5. index kode varian per bagian (awalan, kode akhir) untuk cek kode dan halaman Code Dictionary
-- Kamus tidak masuk Audit Log (21.000 baris impor; tambahan REGISTER mengikuti varian yang sudah diaudit).
-- ============================================================================

-- ---------------------------------------------------------------- 1. fn_clean_thickness: NO.1 tetap NO.1
-- Sama dengan R20 bagian 3, satu perubahan: ".5" -> "0.5" hanya bila sebelum titik bukan angka / huruf
-- ("NO.1" dulu jadi "NO0.1"). Salinan JS sama di cwBomGrid / cwVariantForm (canonThickness).
CREATE OR REPLACE FUNCTION fn_clean_thickness(p text) RETURNS text
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
  t := regexp_replace(t, '(^|[^0-9A-Z.])\.(\d)', '\10.\2', 'g');      -- R21: bukan sesudah huruf (NO.1)
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

-- ---------------------------------------------------------------- 2. tabel kamus
CREATE TABLE IF NOT EXISTS code_dict_material (
  factory_id  uuid NOT NULL REFERENCES factory(id),
  code        text NOT NULL CHECK (code = upper(code) AND length(code) = 4),
  name        text NOT NULL,                                   -- nama di ERP (ADF) / nama material saat didaftarkan
  name_key    text GENERATED ALWAYS AS (fn_tight_key(name)) STORED,
  material_id uuid REFERENCES material(id) ON DELETE SET NULL,  -- material app pemilik awalan (A3: awalan varian DB)
  source      text NOT NULL CHECK (source IN ('ERP', 'REGISTER')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text,
  PRIMARY KEY (factory_id, code)
);
CREATE INDEX IF NOT EXISTS idx_code_dict_material_mat ON code_dict_material (material_id);

CREATE TABLE IF NOT EXISTS code_dict_dimension (
  factory_id    uuid NOT NULL REFERENCES factory(id),
  code          text NOT NULL CHECK (code = upper(code) AND length(code) = 3),
  thickness     text NOT NULL DEFAULT '',                      -- '' = tanpa dimension, (None)
  thickness_key text GENERATED ALWAYS AS (fn_normalize(thickness)) STORED,   -- = material_variant.thickness_key
  search_key    text GENERATED ALWAYS AS (fn_tight_key(thickness)) STORED,
  source        text NOT NULL CHECK (source IN ('ERP', 'REGISTER')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text,
  PRIMARY KEY (factory_id, code)
);
CREATE INDEX IF NOT EXISTS idx_code_dict_dimension_key ON code_dict_dimension (factory_id, thickness_key);

CREATE TABLE IF NOT EXISTS code_dict_color (
  factory_id uuid NOT NULL REFERENCES factory(id),
  code       text NOT NULL CHECK (code = upper(code) AND length(code) = 3),
  color      text NOT NULL CHECK (color <> ''),
  color_key  text GENERATED ALWAYS AS (fn_color_key(color)) STORED,           -- = material_variant.color_key
  source     text NOT NULL CHECK (source IN ('ERP', 'REGISTER')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by text,
  PRIMARY KEY (factory_id, code)
);
CREATE INDEX IF NOT EXISTS idx_code_dict_color_key ON code_dict_color (factory_id, color_key);

-- bagian kode varian: awalan & kode akhir (kode tengah sudah di idx_variant_code_parts)
CREATE INDEX IF NOT EXISTS idx_variant_code_prefix ON material_variant (factory_id, left(code, 4));
CREATE INDEX IF NOT EXISTS idx_variant_code_last ON material_variant (factory_id, substr(code, 8, 3));

-- Pabrik tujuan impor isi kamus: UNIMITRA, atau satu-satunya pabrik bila hanya ada satu
CREATE OR REPLACE FUNCTION fn_r21_import_factory() RETURNS uuid
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_id uuid;
BEGIN
  SELECT id INTO v_id FROM factory WHERE name ILIKE '%UNIMITRA%';
  IF v_id IS NULL AND (SELECT count(*) FROM factory) = 1 THEN
    SELECT id INTO v_id FROM factory;
  END IF;
  IF v_id IS NULL THEN
    RAISE EXCEPTION 'R21: factory UNIMITRA not found. Nothing was imported.';
  END IF;
  RETURN v_id;
END;
$function$;

-- ---------------------------------------------------------------- 3a. aturan kode ketat: arti bagian kode dari kamus dulu
-- R20 + R21: kode -> arti = kamus (pasti) bila bagian itu ada di kamus, selain itu mayoritas varian (R20).
-- Arti -> kode tidak berubah (varian app saja: kamus ERP punya teks yang sah dengan beberapa kode).
CREATE OR REPLACE FUNCTION fn_variant_code_problems(p_factory uuid, p_material_id uuid, p_code text, p_color text,
                                                    p_thickness text, p_exclude uuid)
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
  -- kode -> arti: 4 awal = satu material (kamus: awalan yang sudah tersambung ke material app)
  SELECT d.material_id, m.name INTO r
    FROM code_dict_material d JOIN material m ON m.id = d.material_id
   WHERE d.factory_id = p_factory AND d.code = left(v_code, 4);
  IF FOUND THEN
    IF r.material_id <> p_material_id THEN
      v_out := v_out || format('Prefix %s belongs to material %s (ERP dictionary). Register this variant in that material.',
                               left(v_code, 4), r.name);
    END IF;
  ELSE
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
  END IF;
  -- kode -> arti: 3 tengah = satu dimension
  SELECT d.thickness_key AS tkey, d.thickness INTO r
    FROM code_dict_dimension d WHERE d.factory_id = p_factory AND d.code = substr(v_code, 5, 3);
  IF FOUND THEN
    IF r.tkey <> v_tkey THEN
      v_out := v_out || format('Dimension code %s means %s (ERP dictionary), not %s.',
                               substr(v_code, 5, 3), fn_thickness_label(r.thickness), fn_thickness_label(v_thick));
    END IF;
  ELSE
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
  END IF;
  -- kode -> arti: 3 akhir = satu warna
  SELECT d.color_key AS ckey, d.color INTO r
    FROM code_dict_color d WHERE d.factory_id = p_factory AND d.code = substr(v_code, 8, 3);
  IF FOUND THEN
    IF v_ckey <> '' AND r.ckey <> v_ckey THEN
      v_out := v_out || format('Color code %s means %s (ERP dictionary), not %s.', substr(v_code, 8, 3), r.color, v_color);
    END IF;
  ELSE
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

-- ---------------------------------------------------------------- 3b. hint kode di modal Register / + Variant
-- R21: arti kode tengah / akhir dari kamus dulu; ref = 'ERP dictionary' (form: "Code W01 = WHITE (recorded in ERP dictionary).")
CREATE OR REPLACE FUNCTION fn_variant_code_hint(p_token text, p_material_id uuid, p_code text, p_exclude uuid,
                                                p_color text DEFAULT NULL::text, p_thickness text DEFAULT NULL::text)
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
  SELECT 'ERP dictionary'::text AS code, d.thickness INTO v_t
    FROM code_dict_dimension d WHERE d.factory_id = v_factory AND d.code = substr(v_code, 5, 3);
  IF NOT FOUND THEN
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
  END IF;
  SELECT 'ERP dictionary'::text AS code, d.color INTO v_c
    FROM code_dict_color d WHERE d.factory_id = v_factory AND d.code = substr(v_code, 8, 3);
  IF NOT FOUND THEN
    SELECT x.code, x.color INTO v_c
      FROM (SELECT count(*) AS n, min(mv.created_at) AS first_at,
                   (array_agg(mv.code ORDER BY mv.created_at, mv.code))[1] AS code,
                   (array_agg(mv.color ORDER BY mv.created_at, mv.code))[1] AS color
              FROM material_variant mv
             WHERE mv.factory_id = v_factory AND length(mv.code) = 10 AND mv.id IS DISTINCT FROM p_exclude
               AND substr(mv.code, 8, 3) = substr(v_code, 8, 3)
             GROUP BY mv.color_key) x
     ORDER BY x.n DESC, x.first_at, x.code LIMIT 1;
  END IF;
  -- R20: kode utuh sudah dipakai varian lain
  SELECT mv.id, m.name || ' ' || chr(183) || ' ' || fn_thickness_label(mv.thickness) || ' ' || chr(183) || ' ' || mv.color AS label,
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

-- ---------------------------------------------------------------- 3c. baca kode purchasing yang belum terdaftar (Use)
-- R21: awalan -> material dari kamus (tersambung) dulu; arti kode tengah / akhir dari kamus dulu
CREATE OR REPLACE FUNCTION fn_variant_code_decode(p_token text, p_material_id uuid, p_code text, p_color text, p_thickness text)
 RETURNS TABLE(material_id uuid, label text, thickness text, color text, problems text[])
 LANGUAGE plpgsql
 STABLE
AS $function$
#variable_conflict use_column
DECLARE
  v_email   text := fn_auth(p_token, 'view_master');
  v_factory uuid;
  v_code    text := upper(btrim(regexp_replace(coalesce(p_code, ''), '\s+', '', 'g')));
  v_mat     material%ROWTYPE;
  v_thick   text;
  v_color   text;
  v_known   boolean;
  v_other   text;
BEGIN
  SELECT m.factory_id INTO v_factory FROM material m WHERE m.id = p_material_id;
  IF NOT FOUND OR NOT fn_can_see_factory(v_email, v_factory) OR length(v_code) <> 10
     OR EXISTS (SELECT 1 FROM material_variant v WHERE v.factory_id = v_factory AND v.code = v_code) THEN
    RETURN;
  END IF;
  -- awalan milik material lain = material itu; awalan baru = material baris ini (aturan kode tetap memeriksa awalannya)
  SELECT m.* INTO v_mat FROM material m
   WHERE m.id = coalesce((SELECT d.material_id FROM code_dict_material d
                           WHERE d.factory_id = v_factory AND d.code = left(v_code, 4)),
                         (SELECT v.material_id FROM material_variant v
                           WHERE v.factory_id = v_factory AND length(v.code) = 10 AND left(v.code, 4) = left(v_code, 4)
                           GROUP BY v.material_id ORDER BY count(*) DESC, min(v.created_at), v.material_id LIMIT 1),
                         p_material_id);
  IF NOT FOUND OR v_mat.status <> 'ACTIVE' OR v_mat.is_process THEN
    RETURN;
  END IF;
  SELECT d.thickness, true INTO v_thick, v_known
    FROM code_dict_dimension d WHERE d.factory_id = v_factory AND d.code = substr(v_code, 5, 3);
  IF v_known IS NULL THEN
    SELECT (array_agg(v.thickness ORDER BY v.created_at, v.code))[1], true INTO v_thick, v_known
      FROM material_variant v
     WHERE v.factory_id = v_factory AND length(v.code) = 10 AND substr(v.code, 5, 3) = substr(v_code, 5, 3)
     GROUP BY v.thickness_key ORDER BY count(*) DESC, min(v.created_at) LIMIT 1;
  END IF;
  IF v_known IS NULL THEN
    v_thick := fn_clean_thickness(p_thickness);           -- kode dimension baru: dimension baris
  END IF;
  v_thick := nullif(v_thick, '');
  v_known := NULL;
  SELECT d.color, true INTO v_color, v_known
    FROM code_dict_color d WHERE d.factory_id = v_factory AND d.code = substr(v_code, 8, 3);
  IF v_known IS NULL THEN
    SELECT (array_agg(v.color ORDER BY v.created_at, v.code))[1], true INTO v_color, v_known
      FROM material_variant v
     WHERE v.factory_id = v_factory AND length(v.code) = 10 AND substr(v.code, 8, 3) = substr(v_code, 8, 3)
     GROUP BY v.color_key ORDER BY count(*) DESC, min(v.created_at) LIMIT 1;
  END IF;
  IF v_known IS NULL THEN
    v_color := nullif(fn_clean_color(p_color), '');        -- kode warna baru: warna sel
  END IF;
  IF v_color IS NULL THEN
    RETURN;
  END IF;
  IF v_mat.id = p_material_id AND fn_normalize(coalesce(v_thick, '')) = fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''))
     AND fn_color_key(v_color) = fn_color_key(p_color) THEN
    RETURN;                                                -- = baris + sel ini: cukup Save
  END IF;
  SELECT v.code INTO v_other FROM material_variant v
   WHERE v.material_id = v_mat.id AND v.thickness_key = fn_normalize(coalesce(v_thick, '')) AND v.color_key = fn_color_key(v_color);
  RETURN QUERY SELECT v_mat.id, v_mat.name || ' ' || chr(183) || ' ' || fn_thickness_label(v_thick) || ' ' || chr(183) || ' ' || v_color, coalesce(v_thick, ''), v_color,
    CASE WHEN v_other IS NOT NULL
      THEN ARRAY[format(replace('%s * %s * %s is already registered with code %s.', '*', chr(183)), v_mat.name, fn_thickness_label(v_thick), v_color, v_other)]
      ELSE fn_variant_code_problems(v_factory, v_mat.id, v_code, v_color, v_thick, NULL) END;
END;
$function$;

-- ---------------------------------------------------------------- 3d. susun kode otomatis (R20 bagian 4)
-- R21: bagian yang belum dikenal varian app boleh dari kamus, hanya bila teks itu punya TEPAT SATU kode di kamus
-- (kamus ERP: 76 Dimension dan 549 warna punya beberapa kode -> tetap Register). Awalan: varian material ini, lalu
-- awalan kamus yang tersambung ke material ini. Dimension kosong: tetap kode kosong material ini (R20 bagian 3).
CREATE OR REPLACE FUNCTION fn_variant_compose(p_material_id uuid, p_thickness text, p_color text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_factory uuid;
  v_tkey    text := fn_normalize(coalesce(fn_clean_thickness(p_thickness), ''));
  v_ckey    text := fn_color_key(p_color);
  v_pre     text;
  v_mid     text;
  v_last    text;
BEGIN
  SELECT factory_id INTO v_factory FROM material WHERE id = p_material_id AND NOT is_process;
  IF NOT FOUND OR v_ckey = '' THEN
    RETURN NULL;
  END IF;
  SELECT left(v.code, 4) INTO v_pre FROM material_variant v
   WHERE v.material_id = p_material_id AND length(v.code) = 10
   GROUP BY 1 ORDER BY count(*) DESC, min(v.created_at), 1 LIMIT 1;
  IF v_pre IS NULL THEN
    SELECT min(d.code) INTO v_pre FROM code_dict_material d
     WHERE d.factory_id = v_factory AND d.material_id = p_material_id HAVING count(*) = 1;
  END IF;
  SELECT substr(v.code, 5, 3) INTO v_mid FROM material_variant v
   WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v.thickness_key = v_tkey
     AND (v_tkey <> '' OR v.material_id = p_material_id)
   GROUP BY 1 ORDER BY count(*) DESC, min(v.created_at), 1 LIMIT 1;
  IF v_mid IS NULL AND v_tkey <> '' THEN    -- dimension belum dipakai varian app: kode kamus bila hanya SATU
    SELECT min(d.code) INTO v_mid FROM code_dict_dimension d
     WHERE d.factory_id = v_factory AND d.thickness_key = v_tkey HAVING count(*) = 1;
  END IF;
  SELECT substr(v.code, 8, 3) INTO v_last FROM material_variant v
   WHERE v.material_id = p_material_id AND length(v.code) = 10 AND v.color_key = v_ckey
   GROUP BY 1 ORDER BY count(*) DESC, min(v.created_at), 1 LIMIT 1;
  IF v_last IS NULL THEN                   -- warna belum ada di material ini: kode warna material lain bila di pabrik hanya SATU
    SELECT CASE WHEN count(DISTINCT substr(v.code, 8, 3)) = 1 THEN min(substr(v.code, 8, 3)) END INTO v_last
      FROM material_variant v WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v.color_key = v_ckey;
  END IF;
  IF v_last IS NULL AND NOT EXISTS (SELECT 1 FROM material_variant v WHERE v.factory_id = v_factory AND length(v.code) = 10
                                       AND v.color_key = v_ckey) THEN
    SELECT min(d.code) INTO v_last FROM code_dict_color d    -- warna belum dipakai varian app: kode kamus bila hanya SATU
     WHERE d.factory_id = v_factory AND d.color_key = v_ckey HAVING count(*) = 1;
  END IF;
  IF v_pre IS NULL OR v_mid IS NULL OR v_last IS NULL THEN
    RETURN NULL;
  END IF;
  RETURN v_pre || v_mid || v_last;
END;
$function$;

-- Sel kuning DRAFT -> varian tersusun (R20 bagian 4). R21: material tanpa varian berkode ikut dicoba bila awalannya
-- tersambung di kamus (mis. 4 material ERP tanpa varian yang namanya sama dengan ADF).
CREATE OR REPLACE FUNCTION fn_variant_autofill(p_materials uuid[], p_factories uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  r      record;
  v_code text;
  v_n    integer := 0;
BEGIN
  IF current_setting('app.r20_autofill', true) = 'on' THEN
    RETURN 0;
  END IF;
  PERFORM set_config('app.r20_autofill', 'on', true);
  FOR r IN
    SELECT DISTINCT ON (l.material_id, fn_normalize(coalesce(l.thickness, '')), fn_color_key(bc.color))
           l.material_id, m.factory_id, l.thickness, bc.color, coalesce(bc.updated_by, 'R20 auto code') AS who
      FROM bom_cell bc
      JOIN bom_line l ON l.id = bc.bom_line_id AND l.is_active
      JOIN specsheet_revision rv ON rv.id = l.revision_id AND rv.status = 'DRAFT'
      JOIN material m ON m.id = l.material_id AND m.status = 'ACTIVE' AND NOT m.is_process
     WHERE bc.is_used AND bc.variant_id IS NULL AND bc.color IS NOT NULL
       AND (p_materials IS NULL OR l.material_id = ANY (p_materials))
       AND (p_factories IS NULL OR m.factory_id = ANY (p_factories))
       AND (EXISTS (SELECT 1 FROM material_variant w WHERE w.material_id = l.material_id AND length(w.code) = 10)
            OR EXISTS (SELECT 1 FROM code_dict_material d WHERE d.material_id = l.material_id))
     ORDER BY l.material_id, fn_normalize(coalesce(l.thickness, '')), fn_color_key(bc.color), bc.updated_at DESC
  LOOP
    -- varian material + dimension + warna ini sudah ada (mis. INACTIVE): jangan dibuat lagi
    CONTINUE WHEN EXISTS (SELECT 1 FROM material_variant v
                           WHERE v.material_id = r.material_id
                             AND v.thickness_key = fn_normalize(coalesce(fn_clean_thickness(r.thickness), ''))
                             AND v.color_key = fn_color_key(r.color));
    v_code := fn_variant_compose(r.material_id, r.thickness, r.color);
    CONTINUE WHEN v_code IS NULL;
    CONTINUE WHEN EXISTS (SELECT 1 FROM material_variant v WHERE v.factory_id = r.factory_id AND v.code = v_code);
    CONTINUE WHEN cardinality(fn_variant_code_problems(r.factory_id, r.material_id, v_code, r.color, r.thickness, NULL)) > 0;
    BEGIN
      INSERT INTO material_variant (material_id, factory_id, code, color, thickness, status, created_by, updated_by)
      VALUES (r.material_id, r.factory_id, v_code, r.color, r.thickness, 'ACTIVE', r.who, r.who);
      v_n := v_n + 1;
    EXCEPTION WHEN others THEN
      NULL;                                -- aturan DB menolak: sel tetap kuning (Register / Use)
    END;
  END LOOP;
  PERFORM set_config('app.r20_autofill', 'off', true);
  RETURN v_n;
END;
$function$;

-- ---------------------------------------------------------------- 3e. saran kode (modal Register / + Variant)
-- R20 bagian 3: dimension kosong -> kode tengah material ini (wajib sama). Belum ada di material ini -> thickness_free = true:
-- kode kosong yang sudah dikenal di pabrik, UoM sama di depan (hanya saran, boleh yang lain / kode baru).
-- R21: sesudah saran dari varian app, kode kamus untuk teks yang sama (urutan kode). Kamus hanya menambah bila varian app
-- belum punya bagian itu untuk material ini (dimension berisi: belum ada di pabrik; warna: belum ada di material ini).
CREATE OR REPLACE FUNCTION fn_variant_code_suggest(p_token text, p_material_id uuid, p_color text, p_thickness text)
 RETURNS TABLE(prefixes text, thickness_codes text, color_codes text, thickness_free boolean)
 LANGUAGE plpgsql
 STABLE
AS $function$
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
    coalesce(
      (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
         SELECT left(v.code, 4) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
          WHERE v.material_id = p_material_id AND length(v.code) = 10 GROUP BY 1) x),
      (SELECT string_agg(d.code, ',' ORDER BY d.code) FROM code_dict_material d
        WHERE d.factory_id = v_factory AND d.material_id = p_material_id)),
    coalesce(
      (SELECT string_agg(x.part, ',' ORDER BY (NOT v_own AND x.same_uom) DESC, x.n DESC, x.first_at) FROM (
         SELECT substr(v.code, 5, 3) AS part, count(*) AS n, min(v.created_at) AS first_at, bool_or(m.uom = v_uom) AS same_uom
           FROM material_variant v JOIN material m ON m.id = v.material_id
          WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v.thickness_key = v_tkey
            AND (NOT v_own OR v_tkey <> '' OR v.material_id = p_material_id) GROUP BY 1) x),
      (SELECT string_agg(d.code, ',' ORDER BY d.code) FROM code_dict_dimension d
        WHERE d.factory_id = v_factory AND v_tkey <> '' AND d.thickness_key = v_tkey)),
    coalesce(
      (SELECT string_agg(x.part, ',' ORDER BY x.n DESC, x.first_at) FROM (
         SELECT substr(v.code, 8, 3) AS part, count(*) AS n, min(v.created_at) AS first_at FROM material_variant v
          WHERE v.factory_id = v_factory AND length(v.code) = 10 AND v_ckey <> '' AND v.color_key = v_ckey
            AND (v.material_id = p_material_id OR NOT EXISTS (
                   SELECT 1 FROM material_variant w WHERE w.material_id = p_material_id AND w.color_key = v_ckey
                      AND length(w.code) = 10))
          GROUP BY 1) x),
      (SELECT string_agg(d.code, ',' ORDER BY d.code) FROM code_dict_color d
        WHERE d.factory_id = v_factory AND v_ckey <> '' AND d.color_key = v_ckey)),
    NOT v_own;
END;
$function$;

-- ---------------------------------------------------------------- 4. varian berkode -> bagian kode baru masuk kamus (U3)
-- Bagian yang sudah ada di kamus tidak diubah (arti kamus menang; trigger varian sudah menolak arti yang beda).
-- Awalan kamus yang belum tersambung ke material app -> tersambung ke material varian ini. Varian dipindah ke material
-- lain (skrip gabung material kembar, app.variant_merge) -> sambungan awalan ikut pindah.
CREATE OR REPLACE FUNCTION fn_code_dict_learn() RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_by text := coalesce(NEW.updated_by, current_setting('app.user', true));
BEGIN
  IF length(NEW.code) <> 10 THEN
    RETURN NULL;
  END IF;
  INSERT INTO code_dict_material (factory_id, code, name, material_id, source, created_by)
  SELECT NEW.factory_id, left(NEW.code, 4), m.name, m.id, 'REGISTER', v_by FROM material m WHERE m.id = NEW.material_id
  ON CONFLICT (factory_id, code) DO UPDATE SET material_id = EXCLUDED.material_id
   WHERE code_dict_material.material_id IS NULL
      OR (TG_OP = 'UPDATE' AND code_dict_material.material_id = OLD.material_id AND OLD.material_id <> NEW.material_id);
  INSERT INTO code_dict_dimension (factory_id, code, thickness, source, created_by)
  VALUES (NEW.factory_id, substr(NEW.code, 5, 3), coalesce(NEW.thickness, ''), 'REGISTER', v_by)
  ON CONFLICT (factory_id, code) DO NOTHING;
  INSERT INTO code_dict_color (factory_id, code, color, source, created_by)
  VALUES (NEW.factory_id, substr(NEW.code, 8, 3), NEW.color, 'REGISTER', v_by)
  ON CONFLICT (factory_id, code) DO NOTHING;
  RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_r21_dict_learn ON material_variant;
CREATE TRIGGER trg_r21_dict_learn AFTER INSERT OR UPDATE OF code, color, thickness, material_id ON material_variant
  FOR EACH ROW EXECUTE FUNCTION fn_code_dict_learn();
