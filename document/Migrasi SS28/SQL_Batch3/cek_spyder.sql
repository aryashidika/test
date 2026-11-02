-- CEK sebelum impor (hanya SELECT). Baris bermasalah tampil paling atas.
-- pabrik_unimitra harus 1. status: ada = sudah di database; baru = dibuat oleh impor; TIDAK ADA / SUDAH ADA / INACTIVE / UOM BEDA = impor akan ditolak.
-- kamus ERP (R22): baru = awalan disambung ke material baru; DIPAKAI MATERIAL LAIN / TIDAK ADA = awalan tidak disambung, kirim hasilnya.
WITH d AS (SELECT $j${"user":"Migrasi data","season":"SS28","stage":"PREV","options":[{"kind":"KATEGORI","value":"FOOTBALL"},
{"kind":"CONSTRUCTION","value":"STROBLE + TOE LASTING"},
{"kind":"GENDER","value":"MEN"},
{"kind":"LAST","value":"PRL-023"},
{"kind":"OUTSOLE_MOLD","value":"PRM-105"},
{"kind":"KATEGORI","value":"FUTSAL"},
{"kind":"LAST","value":"PRL-014"},
{"kind":"OUTSOLE_MOLD","value":"PRM-106"},
{"kind":"LAST","value":"PRL-023 MID"},
{"kind":"OUTSOLE_MOLD","value":"PRM-112"},
{"kind":"OUTSOLE_MOLD","value":"PRM-099"},
{"kind":"GENDER","value":"JR"},
{"kind":"LAST","value":"PRL-024 JR"},
{"kind":"OUTSOLE_MOLD","value":"PRM-091 JR"},
{"kind":"LAST","value":"PRL-014 JR"},
{"kind":"OUTSOLE_MOLD","value":"PRM-099 JR"}],"materials":[{"name":"SIZE LABEL ACC LS SPYDER FG","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ACC LS SPYDER FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ACC LS SPYDER FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL ACC LS SPYDER IN","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ACC LS SPYDER IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ACC LS SPYDER IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL ACC LIGHTSPEED SPYDER CORE FG","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ACC LIGHTSPEED SPYDER CORE FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ACC LIGHTSPEED SPYDER CORE FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL ACC LIGHTSPEED SPYDER CORE IN","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ACC LIGHTSPEED SPYDER CORE IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ACC LIGHTSPEED SPYDER CORE IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL ACC LS SPYDER FG JR","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ACC LS SPYDER FG JR","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ACC LS SPYDER FG JR","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL ACC LS SPYDER IN JR","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ACC LS SPYDER IN JR","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ACC LS SPYDER IN JR","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL ALPHA FORCE PRO FG","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ALPHA FORCE PRO FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ALPHA FORCE PRO FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL ALPHA FORCE PRO IN","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ALPHA FORCE PRO IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ALPHA FORCE PRO IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"OUTSOLE TPU INJECTION BASE 98 A STUD 90 A PRM-105","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-106","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-109","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"OUTSOLE TPU INJECTION BASE 90-92 A STUD 90-92 A PRM-091 JR","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"OUTSOLE TPU INJECTION BASE FRONT 95 A BASE HEEL 64 D STUD TIP 90 A PRM-110","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"INJECTION PHYLON HARDNESS 60\u00b12 ASKER C PRM-106","category":"MIDSOLE","uom":"PRS","is_process":false},
{"name":"INJECTION PHYLON HARDNESS 50-55 ASKER C PRM-109","category":"MIDSOLE","uom":"PRS","is_process":false},
{"name":"HULEX NAPPA GRIP EFFECT","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"SINGLE MESH JZ 9036","category":"FABRIC","uom":"ME","is_process":false},
{"name":"POLY FLAT TUBULAR BYL C028","category":"LACE","uom":"PRS","is_process":false},
{"name":"NEGATIVE FILM","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"6 MM FOAM 50 KG +5 SHL","category":"FOAM","uom":"ME","is_process":false},
{"name":"HULEX NAPA ANTI (STICKY SURFACE)","category":"SYNTHETIC LEATHER","uom":"YD","is_process":false},
{"name":"PRINTING SCREEN","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"MESH TN 378B (WIGHT 28 GR ) .54\"","category":"MESH","uom":"ME","is_process":false},
{"name":"T-160 (HASI-022 GRAMASI 160GSM)","category":"FABRIC","uom":"ME","is_process":false},
{"name":"COATING FA7300/50 MICRON","category":"PROCESS","uom":"ME","is_process":true},
{"name":"MERRY KD KL R-054 BACKING KNITWEAR","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"PUNCH HOLE","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"POLYPAG 2 (HASI 028)","category":"FABRIC","uom":"ME","is_process":false},
{"name":"1.2 MM NON WOVEN NW 260","category":"FABRIC","uom":"ME","is_process":false},
{"name":"SHOELACE SPUN TUBULAR (NSL0208)","category":"LACE","uom":"PRS","is_process":false},
{"name":"HY SOCK 16N","category":"FABRIC","uom":"ME","is_process":false},
{"name":"MERRY MESH","category":"FABRIC","uom":"ME","is_process":false},
{"name":"EVA HARDNESS 45-50","category":"FOAM","uom":"ME","is_process":false},
{"name":"TRANSFER PAPER","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"CM 02","category":"COUNTER","uom":"EA","is_process":false},
{"name":"BONDED THREAD(210D/3P)","category":"THREAD","uom":"CON","is_process":false},
{"name":"BONDED THREAD(N280D/3P)","category":"THREAD","uom":"CON","is_process":false},
{"name":"SPRAY OUTSOLE","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"TISSUE PAPER","category":"PACKAGING","uom":"RIM","is_process":false},
{"name":"INNER BOX SPECS","category":"PACKAGING","uom":"SET","is_process":false},
{"name":"STANDARD CARTON BOX NEW","category":"PACKAGING","uom":"EA","is_process":false},
{"name":"STANDARD ISOLATAPE SPECS","category":"PACKAGING","uom":"ME","is_process":false},
{"name":"STRING PIN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SILICAGEL","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"COCOTEX","category":"FABRIC","uom":"ME","is_process":false},
{"name":"SINGLE STICKER","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"FOAM 50KG 6 MM X 44\"","category":"FOAM","uom":"ME","is_process":false},
{"name":"SUPERLIGHT SL 560","category":"FABRIC","uom":"ME","is_process":false},
{"name":"EVA HARDNESS 40-45 ASKER C","category":"FOAM","uom":"ME","is_process":false},
{"name":"OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"MERRY MESH GRAMASI 100","category":"MESH","uom":"ME","is_process":false},
{"name":"2 MM FOAM 50 KG","category":"FOAM","uom":"ME","is_process":false},
{"name":"EVA HARDNESS 40 ASKER C","category":"FOAM","uom":"ME","is_process":false},
{"name":"TR COUNTER K-10 JR POTONG KAKI","category":"COUNTER","uom":"PRS","is_process":false},
{"name":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099 JR","category":"OUTSOLE","uom":"PRS","is_process":false}],"models":[{"file":"ACC LS  SPYDER   FG SS 28.xlsx","name":"ACC LS SPYDER FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023","outsole_mold":"PRM-105","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"MAIN","c":"VAMP","m":"HULEX NAPA ANTI (STICKY SURFACE)","u":"YD","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"SUB","m":"PRINTING SCREEN","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"SUB","m":"MESH TN 378B (WIGHT 28 GR ) .54\"","u":"ME","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"SUB","m":"T-160 (HASI-022 GRAMASI 160GSM)","u":"ME","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"SUB","m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT"},
{"k":"MAIN","c":"TONGUE","m":"HULEX NAPA ANTI (STICKY SURFACE)","u":"YD","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"SUB","m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"SUB","m":"PUNCH HOLE","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"MAIN","c":"TOE BOX","m":"T-160 (HASI-022 GRAMASI 160GSM)","u":"ME","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"MAIN","c":"EYESTAY REINF IN","m":"POLYPAG 2 (HASI 028)","u":"ME","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"MAIN","c":"EYESTAY REINF OUT","m":"POLYPAG 2 (HASI 028)","u":"ME","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"MAIN","c":"COLLAR REINF IN","m":"1.2 MM NON WOVEN NW 260","u":"ME","p":"HWASUNG INTERNATIONAL IND"},
{"k":"MAIN","c":"COLLAR REINF OUT","m":"1.2 MM NON WOVEN NW 260","u":"ME","p":"HWASUNG INTERNATIONAL IND"},
{"k":"MAIN","c":"COLLAR LINING","m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"MAIN","c":"COLLAR FOAM","m":"6 MM FOAM 50 KG +5 SHL","u":"ME","p":"SERIM INDONESIA,PT"},
{"k":"MAIN","c":"SHOE LACE","m":"SHOELACE SPUN TUBULAR (NSL0208)","u":"PRS","p":"SUN-TEX INDONESIA, PT"},
{"k":"MAIN","c":"PUNCH HOLE","m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"INSOLE","m":"HY SOCK 16N","u":"ME","p":"HAN YOUNG INDONESIA,PT"},
{"k":"MAIN","c":"SOCKLINER COVER","m":"MERRY MESH","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"SOCKLINER DIE CUT","m":"EVA HARDNESS 45-50","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"SOCKLINER LOGO","m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"HEEL COUNTER","m":"CM 02","u":"EA","p":"JING XING INDONESIA, PT"},
{"k":"MAIN","c":"SEWING THREAD","m":"BONDED THREAD(210D/3P)","u":"CON","p":"IDAMAN ERA MANDIRI, PT"},
{"k":"SUB","m":"BONDED THREAD(210D/3P)","u":"CON","p":"IDAMAN ERA MANDIRI, PT"},
{"k":"MAIN","c":"STROBEL THREAD","m":"BONDED THREAD(N280D/3P)","u":"CON","p":"IDAMAN ERA MANDIRI, PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE TPU INJECTION BASE 98 A STUD 90 A PRM-105","u":"PRS","p":"JING XING INDONESIA, PT"},
{"k":"SUB","m":"SPRAY OUTSOLE","u":"PRS","p":"INDOKU HESA MAJU JAYA, PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG ACC LS SPYDER FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL ACC LS SPYDER FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"TISSUE PAPER","m":"TISSUE PAPER","u":"RIM","p":"ROYAL QUICK INDO,CV"},
{"k":"MAIN","c":"WRAPPING PAPER","m":"TISSUE PAPER","u":"RIM","p":"ROYAL QUICK INDO,CV"},
{"k":"MAIN","c":"INNER BOX","m":"INNER BOX SPECS","u":"SET","p":"KARYA INDAH MULTIGUNA,PT"},
{"k":"SUB","m":"INNER BOX SPECS","u":"SET","p":"KARYA INDAH MULTIGUNA,PT"},
{"k":"MAIN","c":"CARTON BOX","m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT"},
{"k":"SUB","m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX ACC LS SPYDER FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"ISOLATAPE","m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT"},
{"k":"MAIN","c":"STRING PIN","m":"STRING PIN","u":"PCS","p":"DARMA SUKSES MANDIRI,CV"},
{"k":"MAIN","c":"SILICA GEL","m":"SILICAGEL","u":"PCS","p":"IMCO SILICA"}]},
{"file":"ACC LS  SPYDER  IN SS 28.xlsx","name":"ACC LS SPYDER IN","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-014","outsole_mold":"PRM-106","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-106","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"MIDSOLE","m":"INJECTION PHYLON HARDNESS 60\u00b12 ASKER C PRM-106","u":"PRS","p":"DWI MITRA MANDIRI,PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG ACC LS SPYDER IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL ACC LS SPYDER IN","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX ACC LS SPYDER IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"ACC LS  SPYDER CORE FG SS 28.xlsx","name":"ACC LIGHTSPEED SPYDER CORE FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023 MID","outsole_mold":"PRM-112","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"MAIN","c":"VAMP","m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"SUB","m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT"},
{"k":"SUB","m":"NEGATIVE FILM","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT"},
{"k":"MAIN","c":"TONGUE","m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"SUB","m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"VAMP LINING","m":"COCOTEX","u":"ME","p":"SU INDONESIA,PT"},
{"k":"SUB","m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"COLLAR FOAM","m":"FOAM 50KG 6 MM X 44\"","u":"ME","p":"SERIM INDONESIA,PT"},
{"k":"MAIN","c":"EYESTAY REINF IN","m":"SUPERLIGHT SL 560","u":"ME","p":"HAN YOUNG INDONESIA,PT"},
{"k":"MAIN","c":"EYESTAY REINF OUT","m":"SUPERLIGHT SL 560","u":"ME","p":"HAN YOUNG INDONESIA,PT"},
{"k":"MAIN","c":"TOE BOX","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"COLLAR REINF IN","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"COLLAR REINF OUT","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112","u":"PRS","p":"TOPRO INDONESIA,PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG ACC LIGHTSPEED SPYDER CORE FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL ACC LIGHTSPEED SPYDER CORE FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX ACC LIGHTSPEED SPYDER CORE FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"ACC LS  SPYDER CORE IN  SS 28.xlsx","name":"ACC LIGHTSPEED SPYDER CORE IN","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023 MID","outsole_mold":"PRM-099","sizes":[37,38,39,40,41,42,43,44,45,46],"sample":41,"lines":[{"k":"SUB","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG ACC LIGHTSPEED SPYDER CORE IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL ACC LIGHTSPEED SPYDER CORE IN","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX ACC LIGHTSPEED SPYDER CORE IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"ACC LS  SPYDER FG JR  SS 28.xls","name":"ACC LS SPYDER FG JR","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"JR","last":"PRL-024 JR","outsole_mold":"PRM-091 JR","sizes":[32,33,34,35,36],"sample":34,"lines":[{"k":"MAIN","c":"UPPER","m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"MAIN","c":"VAMP LINING","m":"MERRY MESH GRAMASI 100","u":"ME","p":"BUKIT HIJAU SENTOSA,PD"},
{"k":"SUB","m":"2 MM FOAM 50 KG","u":"ME","p":"SERIM INDONESIA,PT"},
{"k":"MAIN","c":"TOE BOX","m":"EVA HARDNESS 40 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"COLLAR REINF IN","m":"EVA HARDNESS 40 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"COLLAR REINF OUT","m":"EVA HARDNESS 40 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"SOCKLINER COVER","m":"MERRY MESH GRAMASI 100","u":"ME","p":"BUKIT HIJAU SENTOSA,PD"},
{"k":"MAIN","c":"HEEL COUNTER","m":"TR COUNTER K-10 JR POTONG KAKI","u":"PRS","p":"TOPRO INDONESIA,PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE TPU INJECTION BASE 90-92 A STUD 90-92 A PRM-091 JR","u":"PRS","p":"WINFAITH,PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG ACC LS SPYDER FG JR","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL ACC LS SPYDER FG JR","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX ACC LS SPYDER FG JR","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"ACC LS  SPYDER IN JR  SS 28.xls","name":"ACC LS SPYDER IN JR","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"JR","last":"PRL-014 JR","outsole_mold":"PRM-099 JR","sizes":[32,33,34,35,36],"sample":34,"lines":[{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099 JR","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG ACC LS SPYDER IN JR","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL ACC LS SPYDER IN JR","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX ACC LS SPYDER IN JR","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]}]}$j$::jsonb AS j),
f AS (SELECT id FROM factory WHERE status = 'ACTIVE' AND upper(name) LIKE '%UNIMITRA%'),
mdl AS (SELECT x FROM d, jsonb_array_elements(j->'models') x),
ln AS (SELECT m.x->>'name' AS model, l FROM mdl m, jsonb_array_elements(m.x->'lines') l),
newmat AS (SELECT fn_normalize(x->>'name') AS k, upper(x->>'uom') AS uom FROM d, jsonb_array_elements(j->'materials') x),
newcomp AS (SELECT upper(x->>'name') AS k FROM d, jsonb_array_elements(coalesce(j->'components', '[]'::jsonb)) x),
newopt AS (SELECT x->>'kind' AS kind, fn_normalize(x->>'value') AS k FROM d, jsonb_array_elements(j->'options') x),
need AS (
  SELECT DISTINCT 'model' AS jenis, x->>'name' AS nama, NULL::text AS info FROM mdl
  UNION SELECT DISTINCT 'material', l->>'m', l->>'u' FROM ln
  UNION SELECT DISTINCT 'supplier', l->>'p', NULL FROM ln
  UNION SELECT DISTINCT 'komponen', l->>'c', NULL FROM ln WHERE l->>'k' = 'MAIN'
  UNION SELECT DISTINCT 'link supplier', l->>'m' || ' + ' || (l->>'p'), l->>'u' FROM ln
  UNION SELECT DISTINCT 'kamus ERP', x->>'name', x->>'dict' FROM d, jsonb_array_elements(j->'materials') x WHERE x ? 'dict'
  UNION SELECT DISTINCT 'option ' || t.kind, x->>t.field, NULL
          FROM mdl, (VALUES ('KATEGORI', 'category'), ('CONSTRUCTION', 'construction'), ('GENDER', 'gender'),
                            ('LAST', 'last'), ('OUTSOLE_MOLD', 'outsole_mold')) t(kind, field)
),
st AS (
  SELECT n.*,
    CASE n.jenis
      WHEN 'model' THEN CASE WHEN EXISTS (SELECT 1 FROM product_model p WHERE p.name_key = fn_normalize(n.nama)
                                                AND p.factory_id IN (SELECT id FROM f))
                             THEN 'SUDAH ADA' ELSE 'baru' END
      WHEN 'material' THEN CASE
             WHEN EXISTS (SELECT 1 FROM material x WHERE x.name_key = fn_normalize(n.nama) AND x.uom = upper(n.info)
                             AND x.factory_id IN (SELECT id FROM f) AND x.status = 'ACTIVE') THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM material x WHERE x.name_key = fn_normalize(n.nama) AND x.uom = upper(n.info)
                             AND x.factory_id IN (SELECT id FROM f)) THEN 'INACTIVE'
             WHEN EXISTS (SELECT 1 FROM material x WHERE x.name_key = fn_normalize(n.nama)
                             AND x.factory_id IN (SELECT id FROM f)) THEN 'UOM BEDA'
             WHEN EXISTS (SELECT 1 FROM newmat x WHERE x.k = fn_normalize(n.nama) AND x.uom = upper(n.info)) THEN 'baru'
             ELSE 'TIDAK ADA' END
      WHEN 'supplier' THEN CASE
             WHEN EXISTS (SELECT 1 FROM supplier s WHERE s.name_key = fn_normalize(n.nama) AND s.status = 'ACTIVE') THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM supplier s WHERE s.name_key = fn_normalize(n.nama)) THEN 'INACTIVE'
             ELSE 'TIDAK ADA' END
      WHEN 'komponen' THEN CASE
             WHEN EXISTS (SELECT 1 FROM component c WHERE upper(c.name) = upper(n.nama) AND c.status = 'ACTIVE') THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM newcomp c WHERE c.k = upper(n.nama)) THEN 'baru'
             ELSE 'TIDAK ADA' END
      WHEN 'link supplier' THEN CASE
             WHEN EXISTS (SELECT 1 FROM material_supplier ms JOIN material x ON x.id = ms.material_id
                            JOIN supplier s ON s.id = ms.supplier_id
                           WHERE x.name_key || ' + ' || s.name_key = fn_normalize(n.nama) AND x.uom = upper(n.info)
                             AND x.factory_id IN (SELECT id FROM f) AND ms.status = 'INACTIVE') THEN 'INACTIVE'
             WHEN EXISTS (SELECT 1 FROM material_supplier ms JOIN material x ON x.id = ms.material_id
                            JOIN supplier s ON s.id = ms.supplier_id
                           WHERE x.name_key || ' + ' || s.name_key = fn_normalize(n.nama) AND x.uom = upper(n.info)
                             AND x.factory_id IN (SELECT id FROM f)) THEN 'ada'
             ELSE 'baru' END
      WHEN 'kamus ERP' THEN CASE    -- R22: awalan kamus yang akan disambung ke material baru (kolom uom = kode awalan)
             WHEN NOT EXISTS (SELECT 1 FROM code_dict_material k WHERE k.code = n.info AND k.factory_id IN (SELECT id FROM f))
               THEN 'TIDAK ADA'
             WHEN EXISTS (SELECT 1 FROM code_dict_material k JOIN material x ON x.id = k.material_id
                           WHERE k.code = n.info AND k.factory_id IN (SELECT id FROM f) AND x.name_key = fn_normalize(n.nama))
               THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM code_dict_material k WHERE k.code = n.info AND k.factory_id IN (SELECT id FROM f)
                             AND k.material_id IS NOT NULL) THEN 'DIPAKAI MATERIAL LAIN'
             ELSE 'baru' END
      ELSE CASE
             WHEN EXISTS (SELECT 1 FROM model_option o WHERE o.kind = substr(n.jenis, 8)
                             AND o.value_key = fn_normalize(n.nama) AND o.status = 'ACTIVE'
                             AND (o.factory_id IS NULL OR o.factory_id IN (SELECT id FROM f))) THEN 'ada'
             WHEN EXISTS (SELECT 1 FROM model_option o WHERE o.kind = substr(n.jenis, 8)
                             AND o.value_key = fn_normalize(n.nama)
                             AND (o.factory_id IS NULL OR o.factory_id IN (SELECT id FROM f))) THEN 'INACTIVE'
             WHEN EXISTS (SELECT 1 FROM newopt o WHERE o.kind = substr(n.jenis, 8) AND o.k = fn_normalize(n.nama)) THEN 'baru'
             ELSE 'TIDAK ADA' END
    END AS status
  FROM need n
)
SELECT status, jenis, nama, info AS uom,
       (SELECT count(*) FROM f) AS pabrik_unimitra
  FROM st
 ORDER BY CASE WHEN status IN ('TIDAK ADA', 'SUDAH ADA', 'INACTIVE', 'UOM BEDA', 'DIPAKAI MATERIAL LAIN') THEN 0 WHEN status = 'baru' THEN 1 ELSE 2 END,
          jenis, nama;
