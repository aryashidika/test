-- CEK sebelum impor (hanya SELECT). Baris bermasalah tampil paling atas.
-- pabrik_unimitra harus 1. status: ada = sudah di database; baru = dibuat oleh impor; TIDAK ADA / SUDAH ADA / INACTIVE / UOM BEDA = impor akan ditolak.
-- kamus ERP (R22): baru = awalan disambung ke material baru; DIPAKAI MATERIAL LAIN / TIDAK ADA = awalan tidak disambung, kirim hasilnya.
WITH d AS (SELECT $j${"user":"Migrasi data","season":"SS28","stage":"PREV","options":[{"kind":"KATEGORI","value":"FOOTBALL"},
{"kind":"CONSTRUCTION","value":"STROBLE + TOE LASTING"},
{"kind":"GENDER","value":"MEN"},
{"kind":"LAST","value":"PRL-023 MID"},
{"kind":"OUTSOLE_MOLD","value":"PRM-112"},
{"kind":"KATEGORI","value":"FUTSAL"},
{"kind":"LAST","value":"PRL-014"},
{"kind":"OUTSOLE_MOLD","value":"PRM-099"},
{"kind":"LAST","value":"PRL-015"},
{"kind":"OUTSOLE_MOLD","value":"PRM-101"},
{"kind":"OUTSOLE_MOLD","value":"PRM-102"},
{"kind":"OUTSOLE_MOLD","value":"PRM-074"},
{"kind":"OUTSOLE_MOLD","value":"PRM-105"},
{"kind":"OUTSOLE_MOLD","value":"PRM-106"},
{"kind":"OUTSOLE_MOLD","value":"PRM-106 TF"}],"materials":[{"name":"SIZE LABEL LIGHT SPEED NEW REBORN FG","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG LIGHT SPEED NEW REBORN FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX LIGHT SPEED NEW REBORN FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL GALACTICA HYDRA ENERGA FG","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG GALACTICA HYDRA ENERGA FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX GALACTICA HYDRA ENERGA FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL GALACTICA HYDRA ENERGA IN","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG GALACTICA HYDRA ENERGA IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX GALACTICA HYDRA ENERGA IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL ESSORER 2 FG","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ESSORER 2 FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ESSORER 2 FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL ESSORER 2 IN","category":"LABEL","uom":"PRS","is_process":false},
{"name":"HANGTAG ESSORER 2 IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"STICKER INNER BOX ESSORER 2 IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"MERRY KD KL-R534 BACKING KNITWEAR","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"PRINTING 3D","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"FLAT LACE TIP 15 MM BYL G 235","category":"LACE","uom":"PRS","is_process":false},
{"name":"FLAT LACE TIP 15 MM BYL G 211","category":"LACE","uom":"PRS","is_process":false},
{"name":"TPU INJECTION PBM 01","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"OUTSOLE TPU INJECTION BASE SOLE PLATE SOLID TPU STUD TIPS SOLID TPU 90 A PRM-074","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"OUTSOLE TPU INJECTION BASE 98 D STUD 98 A PRM-101","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-106 TF","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"PRESS WELDING","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"PUNCH HOLE","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"DECO SINGLE STITCH ROW","category":"PROCESS","uom":"ME","is_process":false},
{"name":"MERISKIN KD DE-7 BACKING KNITWEAR","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"COCOTEX","category":"FABRIC","uom":"ME","is_process":false},
{"name":"SINGLE STICKER","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"FOAM 50KG 6 MM X 44\"","category":"FOAM","uom":"ME","is_process":false},
{"name":"EVA HARDNESS 40-45 ASKER C","category":"FOAM","uom":"ME","is_process":false},
{"name":"SUPERLIGHT SL 560","category":"FABRIC","uom":"ME","is_process":false},
{"name":"POLY FLAT TUBULAR (BSL-0040)","category":"LACE","uom":"PRS","is_process":false},
{"name":"TR COUNTER SC-02 (HARDNESS 99)","category":"COUNTER","uom":"PRS","is_process":false},
{"name":"HY SOCK 16N","category":"FABRIC","uom":"ME","is_process":false},
{"name":"MERRY MESH GRAMASI 100","category":"MESH","uom":"ME","is_process":false},
{"name":"EVA HARDNESS 45-50","category":"FOAM","uom":"ME","is_process":false},
{"name":"TRANSFER PAPER","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"BONDED THREAD(210D/3P)","category":"THREAD","uom":"CON","is_process":false},
{"name":"BONDED THREAD(N280D/3P)","category":"THREAD","uom":"CON","is_process":false},
{"name":"OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"TISSUE PAPER","category":"PACKAGING","uom":"RIM","is_process":false},
{"name":"INNER BOX SPECS","category":"PACKAGING","uom":"SET","is_process":false},
{"name":"STANDARD CARTON BOX NEW","category":"PACKAGING","uom":"EA","is_process":false},
{"name":"STANDARD ISOLATAPE SPECS","category":"PACKAGING","uom":"ME","is_process":false},
{"name":"STRING PIN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SILICAGEL","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"HULEX DIVE KD KL-R070 BACKING MICRO FIBER","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"PRINTING SCREEN","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"PERFORATED","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"COATING FA7300/50 MICRON","category":"PROCESS","uom":"ME","is_process":true},
{"name":"CANVAS 6 OZ","category":"FABRIC","uom":"ME","is_process":false},
{"name":"1.2 MM NON WOVEN NW 260","category":"FABRIC","uom":"ME","is_process":false},
{"name":"POLYPAG 2 (HASI 028)","category":"FABRIC","uom":"ME","is_process":false},
{"name":"FLATLACE TIP 15 MM BYL E 005","category":"LACE","uom":"PRS","is_process":false},
{"name":"CM 02","category":"COUNTER","uom":"EA","is_process":false},
{"name":"INJECTION PHYLON HARDNESS 50-55 ASKER C PRM-102","category":"MIDSOLE","uom":"PRS","is_process":false},
{"name":"ELASTIC KNIT","category":"KNIT","uom":"PRS","is_process":false},
{"name":"HULEX DIVE TECHNO BACKING MICRO FIBER","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"EVA HARDNESS 50-55 ASKER C","category":"FOAM","uom":"SHT","is_process":false},
{"name":"LAMINATING","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"CAMELEON KD UM-13 BACKING MICRO FIBER","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"HF WELDING","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"FLAT LACE TIP 15 MM BYL G 253","category":"LACE","uom":"PRS","is_process":false},
{"name":"OUTSOLE TPU INJECTION BASE 98 A TPU 95 A PRM-105","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"HANGTAG LIGHT SPEED REBORN META XR FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL LIGHT SPEED REBORN META XR FG","category":"LABEL","uom":"PRS","is_process":false},
{"name":"STICKER INNER BOX LIGHT SPEED REBORN META XR FG","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-106","category":"OUTSOLE","uom":"PRS","is_process":false},
{"name":"INJECTION PHYLON HARDNESS 60\u00b12 ASKER C PRM-106","category":"MIDSOLE","uom":"PRS","is_process":false},
{"name":"HANGTAG LIGHT SPEED REBORN META XR IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL LIGHT SPEED REBORN META XR IN","category":"LABEL","uom":"PRS","is_process":false},
{"name":"STICKER INNER BOX LIGHT SPEED REBORN META XR IN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"HANGTAG LIGHT SPEED REBORN META XR TF","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SIZE LABEL LIGHT SPEED REBORN META XR TF","category":"LABEL","uom":"PRS","is_process":false},
{"name":"STICKER INNER BOX LIGHT SPEED REBORN META XR TF","category":"PACKAGING","uom":"PCS","is_process":false}],"models":[{"file":"ESSORER  II FG  SS 28.xls","name":"ESSORER 2 FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023 MID","outsole_mold":"PRM-112","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"MAIN","c":"UPPER","m":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"SUB","m":"PRESS WELDING","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT"},
{"k":"MAIN","c":"TONGUE","m":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"SUB","m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"HEEL CAP","m":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"SUB","m":"DECO SINGLE STITCH ROW","u":"ME","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"COLLAR LINING","m":"MERISKIN KD DE-7 BACKING KNITWEAR","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"MAIN","c":"VAMP LINING","m":"COCOTEX","u":"ME","p":"SU INDONESIA,PT"},
{"k":"SUB","m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"COLLAR FOAM","m":"FOAM 50KG 6 MM X 44\"","u":"ME","p":"SERIM INDONESIA,PT"},
{"k":"MAIN","c":"TOE BOX","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"COLLAR REINF IN / OUT","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"HEEL CAP REINF","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"EYESTAY REINF","m":"SUPERLIGHT SL 560","u":"ME","p":"HAN YOUNG INDONESIA,PT"},
{"k":"MAIN","c":"PUNCH HOLE","m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"SHOE LACE","m":"POLY FLAT TUBULAR (BSL-0040)","u":"PRS","p":"SUN-TEX INDONESIA, PT"},
{"k":"MAIN","c":"HEEL COUNTER","m":"TR COUNTER SC-02 (HARDNESS 99)","u":"PRS","p":"TOPRO INDONESIA,PT"},
{"k":"MAIN","c":"INSOLE","m":"HY SOCK 16N","u":"ME","p":"HAN YOUNG INDONESIA,PT"},
{"k":"MAIN","c":"SOCKLINER COVER","m":"MERRY MESH GRAMASI 100","u":"ME","p":"BUKIT HIJAU SENTOSA,PD"},
{"k":"MAIN","c":"SOCKLINER DIE CUT","m":"EVA HARDNESS 45-50","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"SOCKLINER LOGO","m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"SEWING THREAD","m":"BONDED THREAD(210D/3P)","u":"CON","p":"IDAMAN ERA MANDIRI, PT"},
{"k":"SUB","m":"BONDED THREAD(210D/3P)","u":"CON","p":"IDAMAN ERA MANDIRI, PT"},
{"k":"MAIN","c":"STROBEL THREAD","m":"BONDED THREAD(N280D/3P)","u":"CON","p":"IDAMAN ERA MANDIRI, PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112","u":"PRS","p":"TOPRO INDONESIA,PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG ESSORER 2 FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL ESSORER 2 FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"TISSUE PAPER","m":"TISSUE PAPER","u":"RIM","p":"ROYAL QUICK INDO,CV"},
{"k":"MAIN","c":"WRAPPING PAPER","m":"TISSUE PAPER","u":"RIM","p":"ROYAL QUICK INDO,CV"},
{"k":"MAIN","c":"INNER BOX","m":"INNER BOX SPECS","u":"SET","p":"KARYA INDAH MULTIGUNA,PT"},
{"k":"SUB","m":"INNER BOX SPECS","u":"SET","p":"KARYA INDAH MULTIGUNA,PT"},
{"k":"MAIN","c":"CARTON BOX","m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT"},
{"k":"SUB","m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX ESSORER 2 FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"ISOLATAPE","m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT"},
{"k":"MAIN","c":"STRING PIN","m":"STRING PIN","u":"PCS","p":"DARMA SUKSES MANDIRI,CV"},
{"k":"MAIN","c":"SILICA GEL","m":"SILICAGEL","u":"PCS","p":"IMCO SILICA"}]},
{"file":"ESSORER II IN SS 28.xls","name":"ESSORER 2 IN","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-014","outsole_mold":"PRM-099","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"SUB","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG ESSORER 2 IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL ESSORER 2 IN","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX ESSORER 2 IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"GALACTICA HYDRA ENERGA FG SS 28.xlsx","name":"GALACTICA HYDRA ENERGA FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-015","outsole_mold":"PRM-101","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"MAIN","c":"UPPER","m":"HULEX DIVE KD KL-R070 BACKING MICRO FIBER","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"SUB","m":"PRINTING 3D","u":"PRS","p":"MULTI KARYA USAHA, PT"},
{"k":"SUB","m":"PRINTING SCREEN","u":"PRS","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"TONGUE","m":"HULEX DIVE KD KL-R070 BACKING MICRO FIBER","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"SUB","m":"PERFORATED","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"COLLAR LINING","m":"MERRY KD KL-R534 BACKING KNITWEAR","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"MAIN","c":"VAMP LINING","m":"MERRY MESH GRAMASI 100","u":"ME","p":"BUKIT HIJAU SENTOSA,PD"},
{"k":"SUB","m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT"},
{"k":"MAIN","c":"TOE BOX","m":"CANVAS 6 OZ","u":"ME","p":"HWASUNG INTERNATIONAL IND"},
{"k":"MAIN","c":"COLLAR REINF IN / OUT","m":"1.2 MM NON WOVEN NW 260","u":"ME","p":"HWASUNG INTERNATIONAL,PT"},
{"k":"MAIN","c":"EYESTAY REINF IN","m":"POLYPAG 2 (HASI 028)","u":"ME","p":"HWASUNG INTERNATIONAL,PT"},
{"k":"MAIN","c":"SHOE LACE","m":"FLATLACE TIP 15 MM BYL E 005","u":"PRS","p":"BOO YOUNG INDONESIA,PT"},
{"k":"MAIN","c":"HEEL COUNTER","m":"CM 02","u":"EA","p":"JING XING INDONESIA, PT"},
{"k":"SUB","m":"PERFORATED","u":"PRS","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE TPU INJECTION BASE 98 D STUD 98 A PRM-101","u":"PRS","p":"SINAR MASANDA INDUSTRI,PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG GALACTICA HYDRA ENERGA FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL GALACTICA HYDRA ENERGA FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX GALACTICA HYDRA ENERGA FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"GALACTICA HYDRA ENERGA IN SS 28.xlsx","name":"GALACTICA HYDRA ENERGA IN","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-014","outsole_mold":"PRM-102","sizes":[37,38,39,40,41,42,43,44,45,46],"sample":41,"lines":[{"k":"MAIN","c":"MIDSOLE","m":"INJECTION PHYLON HARDNESS 50-55 ASKER C PRM-102","u":"PRS","p":"KUMKANG TECH INDONESIA,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL GALACTICA HYDRA ENERGA IN","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG GALACTICA HYDRA ENERGA IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX GALACTICA HYDRA ENERGA IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"LIGHT SPEED NEW REBORN FG SS 28.xls","name":"LIGHT SPEED NEW REBORN FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023 MID","outsole_mold":"PRM-074","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"MAIN","c":"TONGUE","m":"ELASTIC KNIT","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"MAIN","c":"UPPER","m":"HULEX DIVE TECHNO BACKING MICRO FIBER","u":"ME","p":"HWASUNG INTERNATIONAL,PT"},
{"k":"MAIN","c":"TOE BOX","m":"EVA HARDNESS 50-55 ASKER C","u":"SHT","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"COLLAR REINF IN","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"COLLAR REINF OUT","m":"EVA HARDNESS 40-45 ASKER C","u":"ME","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"EYESTAY REINF","m":"POLYPAG 2 (HASI 028)","u":"ME","p":"FUJIAN HEHE INTERNATIONAL TRAD"},
{"k":"MAIN","c":"SHOE LACE","m":"FLAT LACE TIP 15 MM BYL G 235","u":"PRS","p":"BOO YOUNG INDONESIA,PT"},
{"k":"SUB","m":"LAMINATING","u":"PRS","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE TPU INJECTION BASE SOLE PLATE SOLID TPU STUD TIPS SOLID TPU 90 A PRM-074","u":"PRS","p":"GUNFESAS TECHNOLOGY,PT"},
{"k":"MAIN","c":"SANK INSOLE FORE FOOT","m":"TPU INJECTION PBM 01","u":"PRS","p":"WINFAITH,PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG LIGHT SPEED NEW REBORN FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL LIGHT SPEED NEW REBORN FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX LIGHT SPEED NEW REBORN FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"LIGHT SPEED REBORN META XR  FG SS 28.xls","name":"LIGHT SPEED REBORN META XR FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023 MID","outsole_mold":"PRM-105","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"MAIN","c":"UPPER","m":"CAMELEON KD UM-13 BACKING MICRO FIBER","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"SUB","m":"HF WELDING","u":"PRS","p":"MULTI KARYA USAHA, PT"},
{"k":"MAIN","c":"TONGUE","m":"CAMELEON KD UM-13 BACKING MICRO FIBER","u":"ME","p":"KINDO MAKMUR JAYA,PT"},
{"k":"MAIN","c":"SHOE LACE","m":"FLAT LACE TIP 15 MM BYL G 253","u":"PRS","p":"BOO YOUNG INDONESIA,PT"},
{"k":"MAIN","c":"SHOE LACE","m":"FLAT LACE TIP 15 MM BYL G 211","u":"PRS","p":"BOO YOUNG INDONESIA,PT"},
{"k":"MAIN","c":"HEEL COUNTER","m":"CM 02","u":"EA","p":"WINFAITH,PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE TPU INJECTION BASE 98 A TPU 95 A PRM-105","u":"PRS","p":"JING XING INDONESIA, PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG LIGHT SPEED REBORN META XR FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL LIGHT SPEED REBORN META XR FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX LIGHT SPEED REBORN META XR FG","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"LIGHT SPEED REBORN META XR  IN SS 28.xls","name":"LIGHT SPEED REBORN META XR IN","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-014","outsole_mold":"PRM-106","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-106","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"MIDSOLE","m":"INJECTION PHYLON HARDNESS 60\u00b12 ASKER C PRM-106","u":"PRS","p":"EVALIA JAYA ABADI, PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG LIGHT SPEED REBORN META XR IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL LIGHT SPEED REBORN META XR IN","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX LIGHT SPEED REBORN META XR IN","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]},
{"file":"LIGHT SPEED REBORN META XR  TF SS 28.xls","name":"LIGHT SPEED REBORN META XR TF","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-014","outsole_mold":"PRM-106 TF","sizes":[37,38,39,40,41,42,43,44],"sample":41,"lines":[{"k":"SUB","m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT"},
{"k":"SUB","m":"HF WELDING","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT"},
{"k":"MAIN","c":"OUTSOLE","m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-106 TF","u":"PRS","p":"UNIMITRA KHARISMA, PT"},
{"k":"MAIN","c":"HANG TAG PRICE","m":"HANGTAG LIGHT SPEED REBORN META XR TF","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"SIZE LABEL","m":"SIZE LABEL LIGHT SPEED REBORN META XR TF","u":"PRS","p":"EMRAN GHANIM ASAHI,PT"},
{"k":"MAIN","c":"STICKER INNER BOX","m":"STICKER INNER BOX LIGHT SPEED REBORN META XR TF","u":"PCS","p":"EMRAN GHANIM ASAHI,PT"}]}]}$j$::jsonb AS j),
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
