-- Impor specsheet dari Excel lama (Migrasi Specsheet SS28). Satu transaksi.
-- v_simpan = false: semua dijalankan lalu DIBATALKAN, pesan "UJI SAJA" menampilkan jumlahnya.
-- v_simpan = true : disimpan. Pengaman: model yang sudah ada tidak ditimpa, semua nama master harus ditemukan.
DO $$
DECLARE
  v_simpan  boolean := false;   -- false = uji saja (dibatalkan), true = simpan
  d         jsonb := $j${"user":"Migrasi data","season":"SS28","stage":"PREV","options":[{"kind":"KATEGORI","value":"FOOTBALL"},
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
{"name":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099 JR","category":"OUTSOLE","uom":"PRS","is_process":false}],"models":[{"file":"ACC LS  SPYDER   FG SS 28.xlsx","name":"ACC LS SPYDER FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023","outsole_mold":"PRM-105","sizes":[37,38,39,40,41,42,43,44],"sample":41,"articles":[{"colorway":"ANTIQUE GOLD / ANTIQUE WHITE / GOLD","code":null},
{"colorway":"BRONZE / WHEAT / SABLE","code":null},
{"colorway":"BLACK / COOL GREY / SILVER","code":null}],"lines":[{"x":16,"m":"HULEX NAPA ANTI (STICKY SURFACE)","u":"YD","d":"0.3 MM X 51\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Metallic Pale olive green 15-0522 TPG","Metallic Bronze 4264 C","Black"],"k":"MAIN","c":"VAMP"},
{"x":17,"m":"PRINTING SCREEN","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Super Glossy Antique White 11-0105 TPG","Super Glossy Wheat 13-1016 TPG","Super Glossy Cool Grey 11 C"],"k":"SUB","a":0,"s":"DECORATION PRINTING GRAPHIC BLOCK + PRINTING GRAPHIC DALAM LOGO FLASH SESUAI ART WORK ( SEE DRAWING )"},
{"x":18,"m":"PRINTING SCREEN","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Matte Black","Matte White","Matte Charcoal Grey 18-0601 TPG"],"k":"SUB","a":0,"s":"DECORATION PRINTING GRAPHIC LINE SESUAI ART WORK ( SEE DRAWING )"},
{"x":19,"m":"PRINTING SCREEN","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Super Glossy Metallic Pale Gold 15-0927 TPG","Super Glossy Sable 19-1320 TPG","Super Glossy Metallic Silver 14-5002 TPG"],"k":"SUB","a":0,"s":"DECORATION PRINTING OUT LINE LOGO FLASH + \" S \" + WORDING \" SPYDER \" + WORDING \" ULTRA GRIP \" + \" THERMASKIN \" SESUAI ART WORK ( SEE DRAWING )"},
{"x":20,"m":"MESH TN 378B (WIGHT 28 GR ) .54\"","u":"ME","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"SUB","a":0,"s":"MESH TN 378 B ( WEIGHT 28 GSM )"},
{"x":21,"m":"T-160 (HASI-022 GRAMASI 160GSM)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"SUB","a":0,"s":"HASI 022T 160"},
{"x":22,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":0,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":23,"m":"HULEX NAPA ANTI (STICKY SURFACE)","u":"YD","d":"0.3 MM X 51\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Metallic Pale olive green 15-0522 TPG","Metallic Bronze 4264 C","Black"],"k":"MAIN","c":"TONGUE"},
{"x":24,"m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Metallic Pale olive green 15-0522 TPG","Metallic Bronze 4264 C","Black"],"k":"SUB","a":7,"s":"0,7 MM MERRY KD KL 054 / BACKING KNITWEAR"},
{"x":25,"m":"T-160 (HASI-022 GRAMASI 160GSM)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"SUB","a":7,"s":"HASI 022T 160"},
{"x":26,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":7,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":27,"m":"PUNCH HOLE","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["None","None","None"],"k":"SUB","a":7,"s":"DECORATION POUNCH HOLE SESUAI ART WORK ( SEE DRAWING )"},
{"x":28,"m":"T-160 (HASI-022 GRAMASI 160GSM)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"MAIN","c":"TOE BOX"},
{"x":29,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":12,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":30,"m":"POLYPAG 2 (HASI 028)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF IN"},
{"x":31,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":14,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":32,"m":"POLYPAG 2 (HASI 028)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF OUT"},
{"x":33,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":16,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":34,"m":"1.2 MM NON WOVEN NW 260","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL IND","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF IN"},
{"x":35,"m":"1.2 MM NON WOVEN NW 260","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL IND","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF OUT"},
{"x":36,"m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing White","Metallic Bronze 4264 C / Backing White","Black / Backing Black"],"k":"MAIN","c":"COLLAR LINING"},
{"x":37,"m":"6 MM FOAM 50 KG +5 SHL","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":38,"m":"SHOELACE SPUN TUBULAR (NSL0208)","u":"PRS","d":"5 MM X 115 CM","p":"SUN-TEX INDONESIA, PT","r":"37 - 40 : 110CM / 41 - 45 : 115 CM","w":["Base : Antique White 11-0105 TPG / Asken : Metallic Pale Gold 15-0927 TPG","Base : Wheat 13-1016 TPG / Asken : Sable 19-1320 TPG","Base : Black / Asken : Metallic Silver 14-5002 TPG"],"k":"MAIN","c":"SHOE LACE"},
{"x":39,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL DIAMETER 2.0 X 5 MM","w":["NONE","NONE","NONE"],"k":"MAIN","c":"PUNCH HOLE"},
{"x":40,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":41,"m":"MERRY MESH","u":"ME","d":"44\"","p":"MULTI KARYA USAHA, PT","w":["Antique White 11-0105 TPG","Wheat 13-1016 TPG","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":42,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":43,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO \"LIGHTSPEED \" 60MMX 4 MM","w":["Metallic Pale Gold 15-0927 TPG / Backing Layer White","Sable 19-1320 TPG / Backing Layer White","Metallic Silver 14-5002 TPG / Backing Layer White"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":44,"m":"CM 02","u":"EA","p":"JING XING INDONESIA, PT","w":["White","White","White"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":45,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"MAIN","c":"SEWING THREAD"},
{"x":46,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","Black"],"k":"SUB","c":"SEWING THREAD","a":29,"s":"SEWING THREAD"},
{"x":47,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":48,"m":"OUTSOLE TPU INJECTION BASE 98 A STUD 90 A PRM-105","u":"PRS","p":"JING XING INDONESIA, PT","r":"BASE TPU HARDNESS 98 A / STUD TIP TPU HARDNESS 90 A","w":["Clear","Clear","Clear"],"k":"MAIN","c":"OUTSOLE"},
{"x":51,"m":"SPRAY OUTSOLE","u":"PRS","p":"INDOKU HESA MAJU JAYA, PT","w":["Base : Metallic Pale olive green 15-0522 TPG / Gradation Graphic : Antique White 11-0105 TPG","Base : Metallic Bronze 4264 C / Gradation Graphic : Wheat 13-1016 TPG","Base : Black / Gradation Graphic : Cool Grey 11 C"],"k":"SUB","a":32,"s":"SPRAY OUTSOLE"},
{"x":52,"m":"HANGTAG ACC LS SPYDER FG","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":53,"m":"SIZE LABEL ACC LS SPYDER FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":54,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":55,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":56,"m":"INNER BOX SPECS","u":"SET","d":"A3 (300 X 200 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":57,"m":"INNER BOX SPECS","u":"SET","d":"A6 (310 X 215 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":38,"s":"A6 ( 310 X 215 X 110 MM ) SIZE 41 - 44"},
{"x":58,"m":"INNER BOX SPECS","u":"SET","d":"A7 (320 X 220 X 125 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":38,"s":"A7 ( 320 X 220 X 125 MM ) SIZE 45 - 45"},
{"x":59,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":60,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":41,"s":"CARTON BOX"},
{"x":61,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":41,"s":"CARTON BOX"},
{"x":62,"m":"STICKER INNER BOX ACC LS SPYDER FG","u":"PCS","d":"10 CM X 6 CM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":66,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["Neon Volt / Black","Neon Volt / Black","Neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":67,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":68,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]},
{"file":"ACC LS  SPYDER  IN SS 28.xlsx","name":"ACC LS SPYDER IN","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-014","outsole_mold":"PRM-106","sizes":[37,38,39,40,41,42,43,44],"sample":41,"articles":[{"colorway":"ANTIQUE GOLD / ANTIQUE WHITE / GOLD","code":null},
{"colorway":"BRONZE / WHEAT / SABLE","code":null},
{"colorway":"BLACK / COOL GREY / SILVER","code":null}],"lines":[{"x":16,"m":"HULEX NAPA ANTI (STICKY SURFACE)","u":"YD","d":"0.3 MM X 51\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Metallic Pale olive green 15-0522 TPG","Metallic Bronze 4264 C","Black"],"k":"MAIN","c":"VAMP"},
{"x":17,"m":"PRINTING SCREEN","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Super Glossy Antique White 11-0105 TPG","Super Glossy Wheat 13-1016 TPG","Super Glossy Cool Grey 11 C"],"k":"SUB","a":0,"s":"DECORATION PRINTING GRAPHIC BLOCK + PRINTING GRAPHIC DALAM LOGO FLASH SESUAI ART WORK ( SEE DRAWING )"},
{"x":18,"m":"PRINTING SCREEN","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Matte Black","Matte White","Matte Charcoal Grey 18-0601 TPG"],"k":"SUB","a":0,"s":"DECORATION PRINTING GRAPHIC LINE SESUAI ART WORK ( SEE DRAWING )"},
{"x":19,"m":"PRINTING SCREEN","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Super Glossy Metallic Pale Gold 15-0927 TPG","Super Glossy Sable 19-1320 TPG","Super Glossy Metallic Silver 14-5002 TPG"],"k":"SUB","a":0,"s":"DECORATION PRINTING OUT LINE LOGO FLASH + \" S \" + WORDING \" SPYDER \" + WORDING \" ULTRA GRIP \" + \" THERMASKIN \" SESUAI ART WORK ( SEE DRAWING )"},
{"x":20,"m":"MESH TN 378B (WIGHT 28 GR ) .54\"","u":"ME","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"SUB","a":0,"s":"MESH TN 378 B ( WEIGHT 28 GSM )"},
{"x":21,"m":"T-160 (HASI-022 GRAMASI 160GSM)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"SUB","a":0,"s":"HASI 022T 160"},
{"x":22,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":0,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":23,"m":"HULEX NAPA ANTI (STICKY SURFACE)","u":"YD","d":"0.3 MM X 51\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Metallic Pale olive green 15-0522 TPG","Metallic Bronze 4264 C","Black"],"k":"MAIN","c":"TONGUE"},
{"x":24,"m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["Metallic Pale olive green 15-0522 TPG","Metallic Bronze 4264 C","Black"],"k":"SUB","a":7,"s":"0,7 MM MERRY KD KL 054 / BACKING KNITWEAR"},
{"x":25,"m":"T-160 (HASI-022 GRAMASI 160GSM)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"SUB","a":7,"s":"HASI 022T 160"},
{"x":26,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":7,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":27,"m":"PUNCH HOLE","u":"PRS","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["None","None","None"],"k":"SUB","a":7,"s":"DECORATION POUNCH HOLE SESUAI ART WORK ( SEE DRAWING )"},
{"x":28,"m":"T-160 (HASI-022 GRAMASI 160GSM)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"MAIN","c":"TOE BOX"},
{"x":29,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":12,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":30,"m":"POLYPAG 2 (HASI 028)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF IN"},
{"x":31,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":14,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":32,"m":"POLYPAG 2 (HASI 028)","u":"ME","d":"44\"","p":"FUJIAN HEHE INTERNATIONAL TRAD","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF OUT"},
{"x":33,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":16,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":34,"m":"1.2 MM NON WOVEN NW 260","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL IND","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF IN"},
{"x":35,"m":"1.2 MM NON WOVEN NW 260","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL IND","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF OUT"},
{"x":36,"m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing White","Metallic Bronze 4264 C / Backing White","Black / Backing Black"],"k":"MAIN","c":"COLLAR LINING"},
{"x":37,"m":"6 MM FOAM 50 KG +5 SHL","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":38,"m":"SHOELACE SPUN TUBULAR (NSL0208)","u":"PRS","d":"5 MM X 115 CM","p":"SUN-TEX INDONESIA, PT","r":"37 - 40 : 110CM / 41 - 45 : 115 CM","w":["Base : Antique White 11-0105 TPG / Asken : Metallic Pale Gold 15-0927 TPG","Base : Wheat 13-1016 TPG / Asken : Sable 19-1320 TPG","Base : Black / Asken : Metallic Silver 14-5002 TPG"],"k":"MAIN","c":"SHOE LACE"},
{"x":39,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL DIAMETER 2.0 X 5 MM","w":["NONE","NONE","NONE"],"k":"MAIN","c":"PUNCH HOLE"},
{"x":40,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":41,"m":"MERRY MESH","u":"ME","d":"44\"","p":"MULTI KARYA USAHA, PT","w":["Antique White 11-0105 TPG","Wheat 13-1016 TPG","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":42,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":43,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO \"LIGHTSPEED \" 60MMX 4 MM","w":["Metallic Pale Gold 15-0927 TPG / Backing Layer White","Sable 19-1320 TPG / Backing Layer White","Metallic Silver 14-5002 TPG / Backing Layer White"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":44,"m":"CM 02","u":"EA","p":"JING XING INDONESIA, PT","w":["White","White","White"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":45,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"MAIN","c":"SEWING THREAD"},
{"x":46,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","Black"],"k":"SUB","c":"SEWING THREAD","a":29,"s":"SEWING THREAD"},
{"x":47,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":48,"m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-106","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"BASE FRONT & HEEL / CENTER MID / LOGO","w":["Pale olive green 15-0522 TPG Mixtuer Antique White 11-0105 TPG","Bronze 4264 C Mixtuer Sable 19-1320 TPG","Black Mixtuer Cool Grey 11 C"],"k":"MAIN","c":"OUTSOLE"},
{"x":52,"m":"INJECTION PHYLON HARDNESS 60\u00b12 ASKER C PRM-106","u":"PRS","p":"DWI MITRA MANDIRI,PT","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"MAIN","c":"MIDSOLE"},
{"x":53,"m":"HANGTAG ACC LS SPYDER IN","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":54,"m":"SIZE LABEL ACC LS SPYDER IN","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":55,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":56,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":57,"m":"INNER BOX SPECS","u":"SET","d":"A3 (300 X 200 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":58,"m":"INNER BOX SPECS","u":"SET","d":"A6 (310 X 215 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":38,"s":"A6 ( 310 X 215 X 110 MM ) SIZE 41 - 44"},
{"x":59,"m":"INNER BOX SPECS","u":"SET","d":"A7 (320 X 220 X 125 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":38,"s":"A7 ( 320 X 220 X 125 MM ) SIZE 45 - 45"},
{"x":60,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":61,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":41,"s":"CARTON BOX"},
{"x":62,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":41,"s":"CARTON BOX"},
{"x":63,"m":"STICKER INNER BOX ACC LS SPYDER IN","u":"PCS","d":"10 CM X 6 CM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":67,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["Neon Volt / Black","Neon Volt / Black","Neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":68,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":69,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]},
{"file":"ACC LS  SPYDER CORE FG SS 28.xlsx","name":"ACC LIGHTSPEED SPYDER CORE FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023 MID","outsole_mold":"PRM-112","sizes":[37,38,39,40,41,42,43,44],"sample":41,"articles":[{"colorway":"ANTIQUE GOLD / ANTIQUE WHITE / GOLD","code":null},
{"colorway":"BRONZE / WHEAT / SABLE","code":null},
{"colorway":"BLACK / COOL GREY / SILVER","code":null}],"lines":[{"x":17,"m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing Grey","Metallic Bronze 4264 C / Backing Grey","Black / Backing Black"],"k":"MAIN","c":"VAMP"},
{"x":18,"m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Super Glossy Antique White 11-0105 TPG","Super Glossy Wheat 13-1016 TPG","Super Glossy Cool Grey 11 C"],"k":"SUB","a":0,"s":"DECORATION PRINTING GRAPHIC BLOCK + PRINTING GRAPHIC DALAM LOGO FLASH SESUAI ART WORK ( SEE DRAWING )"},
{"x":19,"m":"NEGATIVE FILM","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Base Material","Base Material","Base Material"],"k":"SUB","a":0,"s":"DECORATION NEGATIVE FILM GRAPHIC LINE SESUAI ART WORK ( SEE DRAWING )"},
{"x":20,"m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Super Glossy Metallic Pale Gold 15-0927 TPG","Super Glossy Sable 19-1320 TPG","Super Glossy Metallic Silver 14-5002 TPG"],"k":"SUB","a":0,"s":"DECORATION PRINTING OUT LINE LOGO FLASH + \" S \" + WORDING OUT LINE \" SPYDER \" SESUAI ART WORK ( SEE DRAWING )"},
{"x":21,"m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing Grey","Metallic Bronze 4264 C / Backing Grey","Black / Backing Black"],"k":"MAIN","c":"TONGUE"},
{"x":22,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","w":["NONE","NONE","NONE"],"k":"SUB","a":4,"s":"DECORATION POUNCH HOLE SESUAI ART WORK ( SEE DRAWING )"},
{"x":23,"m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing White","Metallic Bronze 4264 C / Backing White","Black / Backing Black"],"k":"MAIN","c":"COLLAR LINING"},
{"x":24,"m":"COCOTEX","u":"ME","d":"2 MM X 44\"","p":"SU INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"VAMP LINING"},
{"x":25,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["None","None","None"],"k":"SUB","a":7,"s":"SINGLE STICKER"},
{"x":26,"m":"FOAM 50KG 6 MM X 44\"","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":27,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF IN"},
{"x":28,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["None","None","None"],"k":"SUB","a":10,"s":"SINGLE STIKER"},
{"x":29,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF OUT"},
{"x":30,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["None","None","None"],"k":"SUB","a":12,"s":"SINGLE STIKER"},
{"x":31,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"TOE BOX"},
{"x":32,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF IN"},
{"x":33,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF OUT"},
{"x":34,"m":"SHOELACE SPUN TUBULAR (NSL0208)","u":"PRS","d":"5 MM X 115 CM","p":"SUN-TEX INDONESIA, PT","r":"37 - 40 : 110CM / 41 - 45 : 115 CM","w":["Base : Antique White 11-0105 TPG / Asken : Metallic Pale Gold 15-0927 TPG","Base : Wheat 13-1016 TPG / Asken : Sable 19-1320 TPG","Base : Black / Asken : Metallic Silver 14-5002 TPG"],"k":"MAIN","c":"SHOE LACE"},
{"x":35,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL DIAMETER 2,0 X 5 MM","w":["NONE","NONE","NONE"],"k":"MAIN","c":"PUNCH HOLE"},
{"x":36,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":37,"m":"MERRY MESH","u":"ME","d":"44\"","p":"MULTI KARYA USAHA, PT","w":["Antique White 11-0105 TPG","Wheat 13-1016 TPG","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":38,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":39,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO \"LIGHTSPEED \" 60MM X 4MM","w":["Metallic Pale Gold 15-0927 TPG / Backing Layer White","Sable 19-1320 TPG / Backing Layer White","Metallic Silver 14-5002 TPG / Backing Layer White"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":40,"m":"CM 02","u":"EA","p":"JING XING INDONESIA, PT","w":["White","White","White"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":41,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"MAIN","c":"SEWING THREAD"},
{"x":42,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","Black"],"k":"SUB","c":"SEWING THREAD","a":24,"s":"SEWING THREAD"},
{"x":43,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":44,"m":"OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112","u":"PRS","p":"TOPRO INDONESIA,PT","r":"BASE / STUD / LOGO","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"MAIN","c":"OUTSOLE"},
{"x":48,"m":"HANGTAG ACC LIGHTSPEED SPYDER CORE FG","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":49,"m":"SIZE LABEL ACC LIGHTSPEED SPYDER CORE FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":50,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","Natural","Natural"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":51,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","Natural","Natural"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":52,"m":"INNER BOX SPECS","u":"SET","d":"A3 (300 X 200 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":53,"m":"INNER BOX SPECS","u":"SET","d":"A6 (310 X 215 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":32,"s":"A6 ( 310 X 215 X 110 MM ) SIZE 41 - 44"},
{"x":54,"m":"INNER BOX SPECS","u":"SET","d":"A7 (320 X 220 X 125 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":32,"s":"A7 ( 320 X 220 X 125 MM ) SIZE 45 - 45"},
{"x":55,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":56,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":35,"s":"CARTON BOX"},
{"x":57,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":35,"s":"CARTON BOX"},
{"x":58,"m":"STICKER INNER BOX ACC LIGHTSPEED SPYDER CORE FG","u":"PCS","d":"10 CM X 6 CM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":62,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["Neon Volt / Black","Neon Volt / Black","Neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":63,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":64,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]},
{"file":"ACC LS  SPYDER CORE IN  SS 28.xlsx","name":"ACC LIGHTSPEED SPYDER CORE IN","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023 MID","outsole_mold":"PRM-099","sizes":[37,38,39,40,41,42,43,44,45,46],"sample":41,"articles":[{"colorway":"ANTIQUE GOLD / ANTIQUE WHITE / GOLD","code":null},
{"colorway":"BRONZE / WHEAT / SABLE","code":null},
{"colorway":"BLACK / COOL GREY / SILVER","code":null}],"lines":[{"x":17,"m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing Grey","Metallic Bronze 4264 C / Backing Grey","Black / Backing Black"],"k":"MAIN","c":"VAMP"},
{"x":18,"m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Super Glossy Antique White 11-0105 TPG","Super Glossy Wheat 13-1016 TPG","Super Glossy Cool Grey 11 C"],"k":"SUB","a":0,"s":"DECORATION PRINTING GRAPHIC BLOCK + PRINTING GRAPHIC DALAM LOGO FLASH SESUAI ART WORK ( SEE DRAWING )"},
{"x":19,"m":"NEGATIVE FILM","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Base Material","Base Material","Base Material"],"k":"SUB","a":0,"s":"DECORATION NEGATIVE FILM GRAPHIC LINE SESUAI ART WORK ( SEE DRAWING )"},
{"x":20,"m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Super Glossy Metallic Pale Gold 15-0927 TPG","Super Glossy Sable 19-1320 TPG","Super Glossy Metallic Silver 14-5002 TPG"],"k":"SUB","a":0,"s":"DECORATION PRINTING OUT LINE LOGO FLASH + \" S \" + WORDING OUT LINE \" SPYDER \" SESUAI ART WORK ( SEE DRAWING )"},
{"x":21,"m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing Grey","Metallic Bronze 4264 C / Backing Grey","Black / Backing Black"],"k":"MAIN","c":"TONGUE"},
{"x":22,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","w":["NONE","NONE","NONE"],"k":"SUB","a":4,"s":"DECORATION POUNCH HOLE SESUAI ART WORK ( SEE DRAWING )"},
{"x":23,"m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing White","Metallic Bronze 4264 C / Backing White","Black / Backing Black"],"k":"MAIN","c":"COLLAR LINING"},
{"x":24,"m":"COCOTEX","u":"ME","d":"2 MM X 44\"","p":"SU INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"VAMP LINING"},
{"x":25,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["None","None","None"],"k":"SUB","a":7,"s":"SINGLE STICKER"},
{"x":26,"m":"FOAM 50KG 6 MM X 44\"","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":27,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF IN"},
{"x":28,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["None","None","None"],"k":"SUB","a":10,"s":"SINGLE STIKER"},
{"x":29,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF OUT"},
{"x":30,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["None","None","None"],"k":"SUB","a":12,"s":"SINGLE STIKER"},
{"x":31,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"TOE BOX"},
{"x":32,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF IN"},
{"x":33,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF OUT"},
{"x":34,"m":"SHOELACE SPUN TUBULAR (NSL0208)","u":"PRS","d":"5 MM X 115 CM","p":"SUN-TEX INDONESIA, PT","r":"37 - 40 : 110CM / 41 - 45 : 115 CM","w":["Base : Antique White 11-0105 TPG / Asken : Metallic Pale Gold 15-0927 TPG","Base : Wheat 13-1016 TPG / Asken : Sable 19-1320 TPG","Base : Black / Asken : Metallic Silver 14-5002 TPG"],"k":"MAIN","c":"SHOE LACE"},
{"x":35,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL DIAMETER 2,0 X 5 MM","w":["NONE","NONE","NONE"],"k":"MAIN","c":"PUNCH HOLE"},
{"x":36,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":37,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","White"],"k":"SUB","a":19,"s":"2.0 MM EVA HARDNESS 40 - 45 ASKER C"},
{"x":38,"m":"MERRY MESH","u":"ME","d":"44\"","p":"MULTI KARYA USAHA, PT","w":["Antique White 11-0105 TPG","Wheat 13-1016 TPG","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":39,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":40,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO \"LIGHTSPEED \" 60MM X 4MM","w":["Metallic Pale Gold 15-0927 TPG / Backing Layer White","Sable 19-1320 TPG / Backing Layer White","Metallic Silver 14-5002 TPG / Backing Layer White"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":41,"m":"CM 02","u":"EA","p":"JING XING INDONESIA, PT","w":["White","White","White"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":42,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"MAIN","c":"SEWING THREAD"},
{"x":43,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","Black"],"k":"SUB","c":"SEWING THREAD","a":25,"s":"SEWING THREAD"},
{"x":44,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":45,"m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"BASE SIDE WALL + IN SIDE BASE / LOGO","w":["Pale olive green 15-0522 TPG / Antique White 11-0105 TPG","Bronze 4264 C / Wheat 13-1016 TPG","Black / Cool Grey 11 C"],"k":"MAIN","c":"OUTSOLE"},
{"x":48,"m":"HANGTAG ACC LIGHTSPEED SPYDER CORE IN","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":49,"m":"SIZE LABEL ACC LIGHTSPEED SPYDER CORE IN","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":50,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","Natural","Natural"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":51,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","Natural","Natural"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":52,"m":"INNER BOX SPECS","u":"SET","d":"A3 (300 X 200 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":53,"m":"INNER BOX SPECS","u":"SET","d":"A6 (310 X 215 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":33,"s":"A6 ( 310 X 215 X 110 MM ) SIZE 41 - 44"},
{"x":54,"m":"INNER BOX SPECS","u":"SET","d":"A7 (320 X 220 X 125 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":33,"s":"A7 ( 320 X 220 X 125 MM ) SIZE 45 - 45"},
{"x":55,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":56,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":36,"s":"CARTON BOX"},
{"x":57,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":36,"s":"CARTON BOX"},
{"x":58,"m":"STICKER INNER BOX ACC LIGHTSPEED SPYDER CORE IN","u":"PCS","d":"10 CM X 6 CM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":62,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["Neon Volt / Black","Neon Volt / Black","Neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":63,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":64,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]},
{"file":"ACC LS  SPYDER FG JR  SS 28.xls","name":"ACC LS SPYDER FG JR","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"JR","last":"PRL-024 JR","outsole_mold":"PRM-091 JR","sizes":[32,33,34,35,36],"sample":34,"articles":[{"colorway":"ANTIQUE GOLD / ANTIQUE WHITE / GOLD","code":null},
{"colorway":"BRONZE / WHEAT / SABLE","code":null},
{"colorway":"BLACK / COOL GREY / SILVER","code":null}],"lines":[{"x":15,"m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing Grey","Metallic Bronze 4264 C / Backing Grey","Black / Backing Black"],"k":"MAIN","c":"UPPER"},
{"x":16,"m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Super Glossy Antique White 11-0105 TPG","Super Glossy Wheat 13-1016 TPG","Super Glossy Cool Grey 11 C"],"k":"SUB","a":0,"s":"DECORATION PRINTING GRAPHIC BLOCK + PRINTING GRAPHIC DALAM LOGO FLASH SESUAI ART WORK ( SEE DRAWING )"},
{"x":17,"m":"NEGATIVE FILM","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Base Material","Base Material","Base Material"],"k":"SUB","a":0,"s":"DECORATION NEGATIVE FILM GRAPHIC LINE SESUAI ART WORK ( SEE DRAWING )"},
{"x":18,"m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Super Glossy Metallic Pale Gold 15-0927 TPG","Super Glossy Sable 19-1320 TPG","Super Glossy Metallic Silver 14-5002 TPG"],"k":"SUB","a":0,"s":"DECORATION PRINTING OUT LINE LOGO FLASH + \" S \" + WORDING OUT LINE \" SPYDER \" SESUAI ART WORK ( SEE DRAWING )"},
{"x":19,"m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing Grey","Metallic Bronze 4264 C / Backing Grey","Black / Backing Black"],"k":"MAIN","c":"TONGUE"},
{"x":20,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","w":["NONE","NONE","NONE"],"k":"SUB","a":4,"s":"DECORATION POUNCH HOLE SESUAI ART WORK ( SEE DRAWING )"},
{"x":21,"m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing White","Metallic Bronze 4264 C / Backing White","Black / Backing Black"],"k":"MAIN","c":"COLLAR LINING"},
{"x":22,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","r":"LAMINATING","w":["White","White","Black"],"k":"MAIN","c":"VAMP LINING"},
{"x":23,"m":"2 MM FOAM 50 KG","u":"ME","d":"2 MM X 44\"","p":"SERIM INDONESIA,PT","w":["None","None","None"],"k":"SUB","a":7,"s":"2.0 MM FOAM 50 KG"},
{"x":24,"m":"FOAM 50KG 6 MM X 44\"","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","r":"COATING","w":["White","White","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":25,"m":"EVA HARDNESS 40 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"TOE BOX"},
{"x":26,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["None","None","None"],"k":"MAIN","c":"EYESTAY REINF IN"},
{"x":27,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"SUB","a":11,"s":"SINGLE STIKER"},
{"x":28,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["None","None","None"],"k":"MAIN","c":"EYESTAY REINF OUT"},
{"x":29,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"SUB","a":13,"s":"SINGLE STIKER"},
{"x":30,"m":"EVA HARDNESS 40 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF IN"},
{"x":31,"m":"EVA HARDNESS 40 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF OUT"},
{"x":32,"m":"SHOELACE SPUN TUBULAR (NSL0208)","u":"PRS","d":"5 MM X 110 CM","p":"SUN-TEX INDONESIA, PT","r":"32 - 33 : 105CM /34 - 36 : 110 CM","w":["Base : Antique White 11-0105 TPG / Asken : Metallic Pale Gold 15-0927 TPG","Base : Wheat 13-1016 TPG / Asken : Sable 19-1320 TPG","Base : Black / Asken : Metallic Silver 14-5002 TPG"],"k":"MAIN","c":"SHOE LACE"},
{"x":33,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":34,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","r":"LAMINATING","w":["Antique White 11-0105 TPG","Wheat 13-1016 TPG","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":35,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":36,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO \"LIGHTSPEED \" 50MM X 3.3MM","w":["Metallic Pale Gold 15-0927 TPG / Backing Layer White","Sable 19-1320 TPG / Backing Layer White","Metallic Silver 14-5002 TPG / Backing Layer White"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":37,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"MAIN","c":"SEWING THREAD"},
{"x":38,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","Black"],"k":"SUB","c":"SEWING THREAD","a":22,"s":"SEWING THREAD"},
{"x":39,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","r":"BLACK / NEON VOLT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":40,"m":"TR COUNTER K-10 JR POTONG KAKI","u":"PRS","p":"TOPRO INDONESIA,PT","r":"BROWN/BLACK","w":["Black","Black","Black"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":41,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL 2.0 X 5 MM (6X2)","w":[null,null,null],"k":"MAIN","c":"PUNCH HOLE"},
{"x":42,"m":"OUTSOLE TPU INJECTION BASE 90-92 A STUD 90-92 A PRM-091 JR","u":"PRS","p":"WINFAITH,PT","r":"BASE / STUD","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"MAIN","c":"OUTSOLE"},
{"x":45,"m":"HANGTAG ACC LS SPYDER FG JR","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":46,"m":"SIZE LABEL ACC LS SPYDER FG JR","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":47,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":48,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":49,"m":"INNER BOX SPECS","u":"SET","d":"A1A (275 X 170 X 100 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":51,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":52,"m":"STICKER INNER BOX ACC LS SPYDER FG JR","u":"PCS","d":"7.8 CM X 5 CM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":56,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["Neon Volt / Black","Neon Volt / Black","Neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":57,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":58,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]},
{"file":"ACC LS  SPYDER IN JR  SS 28.xls","name":"ACC LS SPYDER IN JR","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"JR","last":"PRL-014 JR","outsole_mold":"PRM-099 JR","sizes":[32,33,34,35,36],"sample":34,"articles":[{"colorway":"ANTIQUE GOLD / ANTIQUE WHITE / GOLD","code":null},
{"colorway":"BRONZE / WHEAT / SABLE","code":null},
{"colorway":"BLACK / COOL GREY / SILVER","code":null}],"lines":[{"x":16,"m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing Grey","Metallic Bronze 4264 C / Backing Grey","Black / Backing Black"],"k":"MAIN","c":"UPPER"},
{"x":17,"m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Super Glossy Antique White 11-0105 TPG","Super Glossy Wheat 13-1016 TPG","Super Glossy Cool Grey 11 C"],"k":"SUB","a":0,"s":"DECORATION PRINTING GRAPHIC BLOCK + PRINTING GRAPHIC DALAM LOGO FLASH SESUAI ART WORK ( SEE DRAWING )"},
{"x":18,"m":"NEGATIVE FILM","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Base Material","Base Material","Base Material"],"k":"SUB","a":0,"s":"DECORATION NEGATIVE FILM GRAPHIC LINE SESUAI ART WORK ( SEE DRAWING )"},
{"x":19,"m":"PRINTING SCREEN","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Super Glossy Metallic Pale Gold 15-0927 TPG","Super Glossy Sable 19-1320 TPG","Super Glossy Metallic Silver 14-5002 TPG"],"k":"SUB","a":0,"s":"DECORATION PRINTING OUT LINE LOGO FLASH + \" S \" + WORDING OUT LINE \" SPYDER \" SESUAI ART WORK ( SEE DRAWING )"},
{"x":20,"m":"PU SYNTHETIC KD AR-100 M BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing Grey","Metallic Bronze 4264 C / Backing Grey","Black / Backing Black"],"k":"MAIN","c":"TONGUE"},
{"x":21,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","w":["NONE","NONE","NONE"],"k":"SUB","a":4,"s":"DECORATION POUNCH HOLE SESUAI ART WORK ( SEE DRAWING )"},
{"x":22,"m":"MERRY KD KL R-054 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Metallic Pale olive green 15-0522 TPG / Backing White","Metallic Bronze 4264 C / Backing White","Black / Backing Black"],"k":"MAIN","c":"COLLAR LINING"},
{"x":23,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","w":["White","White","Black"],"k":"MAIN","c":"VAMP LINING"},
{"x":24,"m":"2 MM FOAM 50 KG","u":"ME","d":"2 MM X 44\"","p":"SERIM INDONESIA,PT","w":["None","None","None"],"k":"SUB","a":7,"s":"2.0 MM FOAM 50 KG"},
{"x":25,"m":"FOAM 50KG 6 MM X 44\"","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":26,"m":"EVA HARDNESS 40 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"TOE BOX"},
{"x":27,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["None","None","None"],"k":"MAIN","c":"EYESTAY REINF IN"},
{"x":28,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"SUB","a":11,"s":"SINGLE STIKER"},
{"x":29,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["None","None","None"],"k":"MAIN","c":"EYESTAY REINF OUT"},
{"x":30,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"SUB","a":13,"s":"SINGLE STIKER"},
{"x":31,"m":"EVA HARDNESS 40 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF IN"},
{"x":32,"m":"EVA HARDNESS 40 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF OUT"},
{"x":33,"m":"SHOELACE SPUN TUBULAR (NSL0208)","u":"PRS","d":"5 MM X 110 CM","p":"SUN-TEX INDONESIA, PT","w":["Base : Antique White 11-0105 TPG / Asken : Metallic Pale Gold 15-0927 TPG","Base : Wheat 13-1016 TPG / Asken : Sable 19-1320 TPG","Base : Black / Asken : Metallic Silver 14-5002 TPG"],"k":"MAIN","c":"SHOE LACE"},
{"x":34,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":35,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","w":["Antique White 11-0105 TPG","Wheat 13-1016 TPG","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":36,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":37,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO \"LIGHTSPEED \" 50MM X 3.3MM","w":["Metallic Pale Gold 15-0927 TPG / Backing Layer White","Sable 19-1320 TPG / Backing Layer White","Metallic Silver 14-5002 TPG / Backing Layer White"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":38,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Pale olive green 15-0522 TPG","Bronze 4264 C","Black"],"k":"MAIN","c":"SEWING THREAD"},
{"x":39,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","Black"],"k":"SUB","c":"SEWING THREAD","a":22,"s":"SEWING THREAD"},
{"x":40,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":41,"m":"TR COUNTER K-10 JR POTONG KAKI","u":"PRS","p":"TOPRO INDONESIA,PT","w":["Black","Black","Black"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":42,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL 2.0 X 5 MM (6X2)","w":[null,null,null],"k":"MAIN","c":"PUNCH HOLE"},
{"x":43,"m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099 JR","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"BASE SIDE WALL + IN SIDE BASE / LOGO","w":["Pale olive green 15-0522 TPG / Antique White 11-0105 TPG","Bronze 4264 C / Wheat 13-1016 TPG","Black / Cool Grey 11 C"],"k":"MAIN","c":"OUTSOLE"},
{"x":46,"m":"HANGTAG ACC LS SPYDER IN JR","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Red / White","Red / White","Red / White"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":47,"m":"SIZE LABEL ACC LS SPYDER IN JR","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":48,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","Natural","Natural"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":49,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","Natural","Natural"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":50,"m":"INNER BOX SPECS","u":"SET","d":"A1A (275 X 170 X 100 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":52,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":53,"m":"STICKER INNER BOX ACC LS SPYDER IN JR","u":"PCS","d":"7.8 CM X 5 CM","p":"EMRAN GHANIM ASAHI,PT","w":["Red / White","Red / White","Red / White"],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":57,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["Neon Volt / Black","Neon Volt / Black","Neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":58,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":59,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]}]}$j$::jsonb;
  v_factory uuid;
  v_n       integer;
  o jsonb; m jsonb; a jsonb; l jsonb; c jsonb;
  i integer; k integer;
  v_opt     jsonb;
  v_kind    text; v_field text; v_id uuid;
  v_model   uuid; v_sheet uuid; v_rev uuid; v_line uuid; v_key uuid;
  v_mat     uuid; v_sup uuid; v_comp uuid;
  v_arts    uuid[]; v_keys uuid[]; v_sorts integer[]; v_sort integer; v_parent integer;
  v_links0  integer;
  n_opt integer := 0; n_mat integer := 0; n_model integer := 0; n_line integer := 0; n_sub integer := 0;
  n_cell integer := 0; n_link integer; n_yellow integer; v_info text := '';
  n_dict integer := 0; n_auto integer; v_var0 integer; n_comp integer := 0;
BEGIN
  PERFORM set_config('app.user', d->>'user', true);
  SELECT count(*), (array_agg(id))[1] INTO v_n, v_factory FROM factory
   WHERE status = 'ACTIVE' AND upper(name) LIKE '%UNIMITRA%';
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'Harus tepat 1 pabrik aktif bernama UNIMITRA, ditemukan %. Dibatalkan.', v_n;
  END IF;
  SELECT count(*) INTO v_links0 FROM material_supplier;

  -- 1. Master Options yang belum ada (dilewati bila sudah ada)
  FOR o IN SELECT * FROM jsonb_array_elements(d->'options') LOOP
    INSERT INTO model_option (kind, factory_id, value, status)
    SELECT o->>'kind', CASE WHEN fn_option_is_factory_kind(o->>'kind') THEN v_factory END, o->>'value', 'ACTIVE'
     WHERE NOT EXISTS (SELECT 1 FROM model_option x
                        WHERE x.kind = o->>'kind' AND x.value_key = fn_normalize(o->>'value')
                          AND x.factory_id IS NOT DISTINCT FROM
                              (CASE WHEN fn_option_is_factory_kind(o->>'kind') THEN v_factory END));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    n_opt := n_opt + v_n;
  END LOOP;

  -- 1b. Komponen baru (dilewati bila namanya sudah ada). Nomor = kelipatan 10 sesudah nomor terbesar di kelompoknya.
  FOR o IN SELECT * FROM jsonb_array_elements(coalesce(d->'components', '[]'::jsonb)) LOOP
    INSERT INTO component (number, name, group_code, status, updated_by)
    SELECT (SELECT coalesce(max(number), 0) + 10 FROM component WHERE group_code = o->>'group'),
           o->>'name', o->>'group', 'ACTIVE', d->>'user'
     WHERE NOT EXISTS (SELECT 1 FROM component x WHERE upper(x.name) = upper(o->>'name'));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    n_comp := n_comp + v_n;
  END LOOP;

  -- 2. Material yang belum ada (dilewati bila namanya sudah ada). Material Process = harga Quotation, tanpa Material Code.
  FOR o IN SELECT * FROM jsonb_array_elements(d->'materials') LOOP
    INSERT INTO material (factory_id, name, category, uom, price_method, is_process, status)
    SELECT v_factory, o->>'name', o->>'category', o->>'uom',
           CASE WHEN (o->>'is_process')::boolean THEN 'QUOTATION' ELSE 'CATALOG' END, (o->>'is_process')::boolean, 'ACTIVE'
     WHERE NOT EXISTS (SELECT 1 FROM material x WHERE x.factory_id = v_factory
                          AND x.name_key = fn_normalize(o->>'name'));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    n_mat := n_mat + v_n;
    -- R22: material baru (bukan Process) disambung ke awalan kamus ERP, seperti + New material di app:
    -- nama sama dengan nama kamus, atau kode awalan yang ditulis di data ("dict"). Awalan yang sudah dipakai material lain dilewati.
    IF v_n > 0 AND NOT (o->>'is_process')::boolean THEN
      UPDATE code_dict_material x SET material_id = (SELECT id FROM material WHERE factory_id = v_factory
                                                       AND name_key = fn_normalize(o->>'name'))
       WHERE x.factory_id = v_factory AND x.material_id IS NULL
         AND (x.name_key = fn_tight_key(o->>'name') OR x.code = o->>'dict');
      GET DIAGNOSTICS v_n = ROW_COUNT;
      n_dict := n_dict + v_n;
    END IF;
  END LOOP;
  SELECT count(*) INTO v_var0 FROM material_variant;

  -- 3. Per model: model, season, article, revisi DRAFT, baris BOM, sel warna
  FOR m IN SELECT * FROM jsonb_array_elements(d->'models') LOOP
    IF EXISTS (SELECT 1 FROM product_model WHERE factory_id = v_factory AND name_key = fn_normalize(m->>'name')) THEN
      RAISE EXCEPTION 'Model % sudah ada di sistem. Dibatalkan, tidak ada yang tersimpan.', m->>'name';
    END IF;
    v_opt := '{}'::jsonb;
    FOR v_kind, v_field IN SELECT * FROM (VALUES ('KATEGORI', 'category'), ('CONSTRUCTION', 'construction'),
                                                 ('GENDER', 'gender'), ('LAST', 'last'),
                                                 ('OUTSOLE_MOLD', 'outsole_mold')) t LOOP
      SELECT id INTO v_id FROM model_option
       WHERE kind = v_kind AND value_key = fn_normalize(m->>v_field) AND status = 'ACTIVE'
         AND factory_id IS NOT DISTINCT FROM (CASE WHEN fn_option_is_factory_kind(v_kind) THEN v_factory END);
      IF v_id IS NULL THEN
        RAISE EXCEPTION 'Master Options % "%" tidak ditemukan (model %). Dibatalkan.', v_kind, m->>v_field, m->>'name';
      END IF;
      v_opt := v_opt || jsonb_build_object(v_field, v_id);
    END LOOP;
    INSERT INTO product_model (factory_id, name, category_id, construction_id, gender_id, last_id, outsole_mold_id,
                               sizes, sample_size)
    VALUES (v_factory, m->>'name', (v_opt->>'category')::uuid, (v_opt->>'construction')::uuid,
            (v_opt->>'gender')::uuid, (v_opt->>'last')::uuid, (v_opt->>'outsole_mold')::uuid,
            ARRAY(SELECT x::integer FROM jsonb_array_elements_text(m->'sizes') x), (m->>'sample')::integer)
    RETURNING id INTO v_model;
    n_model := n_model + 1;

    INSERT INTO specsheet (model_id, season) VALUES (v_model, d->>'season') RETURNING id INTO v_sheet;
    v_arts := ARRAY[]::uuid[];
    FOR a IN SELECT * FROM jsonb_array_elements(m->'articles') LOOP
      INSERT INTO article (specsheet_id, code, colorway) VALUES (v_sheet, a->>'code', a->>'colorway')
      RETURNING id INTO v_id;
      v_arts := v_arts || v_id;
    END LOOP;
    INSERT INTO specsheet_revision (specsheet_id, stage, revision_no, status)
    VALUES (v_sheet, d->>'stage', 0, 'DRAFT') RETURNING id INTO v_rev;
    INSERT INTO revision_article (revision_id, article_id) SELECT v_rev, unnest(v_arts);

    v_keys := ARRAY[]::uuid[];
    v_sorts := ARRAY[]::integer[];
    v_sort := 0;
    i := 0;
    FOR l IN SELECT * FROM jsonb_array_elements(m->'lines') LOOP
      i := i + 1;
      SELECT id INTO v_mat FROM material
       WHERE factory_id = v_factory AND name_key = fn_normalize(l->>'m') AND uom = upper(l->>'u');
      IF v_mat IS NULL THEN
        RAISE EXCEPTION 'Material "%" (%) tidak ditemukan (model %, baris Excel %). Dibatalkan.',
          l->>'m', l->>'u', m->>'name', l->>'x';
      END IF;
      SELECT id INTO v_sup FROM supplier WHERE name_key = fn_normalize(l->>'p');
      IF v_sup IS NULL THEN
        RAISE EXCEPTION 'Supplier "%" tidak ditemukan (model %, baris Excel %). Dibatalkan.',
          l->>'p', m->>'name', l->>'x';
      END IF;
      PERFORM fn_bom_check_material(v_mat, v_factory);
      PERFORM fn_bom_check_supplier(v_mat, v_sup);             -- link material-supplier dibuat bila belum ada
      IF l->>'k' = 'MAIN' THEN
        SELECT id INTO v_comp FROM component WHERE upper(name) = upper(l->>'c') AND status = 'ACTIVE';
        IF v_comp IS NULL THEN
          RAISE EXCEPTION 'Komponen "%" tidak ditemukan atau INACTIVE (model %). Dibatalkan.', l->>'c', m->>'name';
        END IF;
        v_sort := v_sort + 1;
        INSERT INTO bom_line (revision_id, line_key, component_id, material_id, thickness, supplier_id, process, sort_order)
        VALUES (v_rev, gen_random_uuid(), v_comp, v_mat, fn_clean_thickness(l->>'d'), v_sup,
                nullif(btrim(coalesce(l->>'r', '')), ''), v_sort)
        RETURNING id, line_key INTO v_line, v_key;
        v_keys := v_keys || v_key;
        v_sorts := v_sorts || v_sort;
        n_line := n_line + 1;
      ELSE
        v_parent := (l->>'a')::integer + 1;
        INSERT INTO bom_line (revision_id, line_key, parent_line_key, sub_seq, sub_name, material_id, thickness,
                              supplier_id, process, sort_order)
        VALUES (v_rev, gen_random_uuid(), v_keys[v_parent],
                coalesce((SELECT max(sub_seq) FROM bom_line WHERE revision_id = v_rev AND parent_line_key = v_keys[v_parent]), 0) + 1,
                l->>'s', v_mat, fn_clean_thickness(l->>'d'), v_sup,
                nullif(btrim(coalesce(l->>'r', '')), ''), v_sorts[v_parent])
        RETURNING id, line_key INTO v_line, v_key;
        v_keys := v_keys || v_key;             -- posisi tetap sejajar dengan urutan baris data
        v_sorts := v_sorts || v_sorts[v_parent];
        n_sub := n_sub + 1;
      END IF;
      k := 0;
      FOR c IN SELECT * FROM jsonb_array_elements(l->'w') LOOP
        k := k + 1;
        INSERT INTO bom_cell (bom_line_id, article_id, color)
        VALUES (v_line, v_arts[k], nullif(fn_clean_color(c #>> '{}'), ''));
        n_cell := n_cell + 1;
      END LOOP;
    END LOOP;
    v_info := v_info || format(' %s: %s article, %s baris, %s sub.', m->>'name', cardinality(v_arts), v_sort,
                               i - v_sort);
  END LOOP;

  SELECT count(*) - v_links0 INTO n_link FROM material_supplier;
  SELECT count(*) - v_var0 INTO n_auto FROM material_variant;   -- R22: kode 10 digit terbentuk otomatis dari kamus
  SELECT count(*) INTO n_yellow
    FROM bom_cell bc JOIN bom_line bl ON bl.id = bc.bom_line_id JOIN material mt ON mt.id = bl.material_id
    JOIN specsheet_revision r ON r.id = bl.revision_id
   WHERE r.created_at = now() AND bc.is_used AND bc.variant_id IS NULL AND NOT mt.is_process;

  IF NOT v_simpan THEN
    RAISE EXCEPTION 'UJI SAJA, tidak ada yang tersimpan. Master Options baru %, komponen baru %, material baru %, link supplier baru %, awalan kamus tersambung %, model %, baris utama %, sub-baris %, sel %, kode terbentuk otomatis %, sel tanpa kode (kuning) %.%',
      n_opt, n_comp, n_mat, n_link, n_dict, n_model, n_line, n_sub, n_cell, n_auto, n_yellow, v_info;
  END IF;
  RAISE NOTICE 'TERSIMPAN. Master Options baru %, komponen baru %, material baru %, link supplier baru %, awalan kamus tersambung %, model %, baris %, sub %, sel %, kode otomatis %.%',
    n_opt, n_comp, n_mat, n_link, n_dict, n_model, n_line, n_sub, n_cell, n_auto, v_info;
END;
$$;
