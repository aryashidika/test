-- Impor specsheet dari Excel lama (Migrasi Specsheet SS28). Satu transaksi.
-- v_simpan = false: semua dijalankan lalu DIBATALKAN, pesan "UJI SAJA" menampilkan jumlahnya.
-- v_simpan = true : disimpan. Pengaman: model yang sudah ada tidak ditimpa, semua nama master harus ditemukan.
DO $$
DECLARE
  v_simpan  boolean := false;   -- false = uji saja (dibatalkan), true = simpan
  d         jsonb := $j${"user":"Migrasi data","season":"SS28","stage":"PREV","options":[{"kind":"KATEGORI","value":"FOOTBALL"},
{"kind":"CONSTRUCTION","value":"STROBLE + TOE LASTING"},
{"kind":"GENDER","value":"MEN"},
{"kind":"LAST","value":"PRL-023 MID"},
{"kind":"OUTSOLE_MOLD","value":"PRM-112"},
{"kind":"KATEGORI","value":"FUTSAL"},
{"kind":"LAST","value":"PRL-014"},
{"kind":"OUTSOLE_MOLD","value":"PRM-099"}],"materials":[{"name":"SIZE LABEL LIGHT SPEED NEW REBORN FG","category":"LABEL","uom":"PRS","is_process":false},
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
{"name":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099","category":"OUTSOLE","uom":"PRS","is_process":false}],"models":[{"file":"ESSORER  II FG  SS 28.xls","name":"ESSORER 2 FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-023 MID","outsole_mold":"PRM-112","sizes":[37,38,39,40,41,42,43,44],"sample":41,"articles":[{"colorway":"CHERRY BLOSSOM / BLUE DE FRANCE","code":null},
{"colorway":"ILLUSION BLUE / SILVER","code":null},
{"colorway":"CRYSTAL TEAL / ISLAND PARADISE","code":null}],"lines":[{"x":16,"m":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Cherry Blossom 13-3207 TPG / Backing White","Illusion Blue 13-4103 TPG / Backing White","Crystal Teal 19-4536 TPG / Backing Grey"],"k":"MAIN","c":"UPPER"},
{"x":17,"m":"PRESS WELDING","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Base : Clear / Metallic Blue De France 2727 C GLOSS + PEARL GOLD","Bas : Clear / Metallic Silver 877 C Gloss + PEARL Silver","Base : Clear / Metallic Island Paradise 14-4620 TPG GLOSS + PEARL GOLD"],"k":"SUB","a":0,"s":"DECORATION PRESH WELDING FLASH TO AREA LATERAL (SEE DRAWING)"},
{"x":18,"m":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Cherry Blossom 13-3207 TPG / Backing White","Illusion Blue 13-4103 TPG / Backing White","Crystal Teal 19-4536 TPG / Backing Grey"],"k":"MAIN","c":"TONGUE"},
{"x":19,"m":"PUNCH HOLE","u":"PRS","p":"KINDO MAKMUR JAYA,PT","w":["None","None","None"],"k":"SUB","a":2,"s":"DECORATION POUNCH HOLE OVAL ( SEE DRAWING )"},
{"x":20,"m":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Cherry Blossom 13-3207 TPG / Backing White","Illusion Blue 13-4103 TPG / Backing White","Crystal Teal 19-4536 TPG / Backing Grey"],"k":"MAIN","c":"HEEL CAP"},
{"x":21,"m":"DECO SINGLE STITCH ROW","u":"ME","p":"UNIMITRA KHARISMA, PT","w":["Cherry Blossom 13-3207 TPG","Illusion Blue 13-4103 TPG","Crystal Teal 19-4536 TPG"],"k":"SUB","a":4,"s":"DECORATION SINGLE STITCHING ROW TEMBUS LINING SESUAI ART WORK ( SEE DRAWING )"},
{"x":22,"m":"MERISKIN KD DE-7 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Blue De France 2727 C / Backing White","Metallic Silver 877 C / Backing White","Island Paradise 14-4620 TPG / Backing White"],"k":"MAIN","c":"COLLAR LINING"},
{"x":23,"m":"COCOTEX","u":"ME","d":"2 MM X 44\"","p":"SU INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"VAMP LINING"},
{"x":24,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["None","None","None"],"k":"SUB","a":7,"s":"SINGLE STICKER"},
{"x":25,"m":"FOAM 50KG 6 MM X 44\"","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","r":"COATING","w":["White","White","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":26,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"TOE BOX"},
{"x":27,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF IN / OUT"},
{"x":28,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"HEEL CAP REINF"},
{"x":29,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF"},
{"x":30,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["none","none","none"],"k":"SUB","a":13,"s":"SINGLE STICKER"},
{"x":31,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL DIAMETER 2.0 X 5MM","w":["none","none","none"],"k":"MAIN","c":"PUNCH HOLE"},
{"x":32,"m":"POLY FLAT TUBULAR (BSL-0040)","u":"PRS","d":"6 MM X 115 CM","p":"SUN-TEX INDONESIA, PT","r":"37-40 :110CM/41-45:115CM","w":["Cherry Blossom 13-3207 TPG","Illusion Blue 13-4103 TPG","Crystal Teal 19-4536 TPG"],"k":"MAIN","c":"SHOE LACE"},
{"x":33,"m":"TR COUNTER SC-02 (HARDNESS 99)","u":"PRS","p":"TOPRO INDONESIA,PT","w":["Black","Black","Black"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":34,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":35,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","r":"LAMINATING","w":["Black","Black","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":36,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["Black","Black","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":37,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO \" SPECS + VICTORY BOW \" ( 45MM X 30MM )","w":["Blue De France 2727 C / Backing Layer White","Metallic Silver 877 C / Backing Layer White","Island Paradise 14-4620 TPG / Backing Layer White"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":38,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Cherry Blossom 13-3207 TPG","Illusion Blue 13-4103 TPG","Crystal Teal 19-4536 TPG"],"k":"MAIN","c":"SEWING THREAD"},
{"x":39,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Blue De France 2727 C","Metallic Silver 877 C","Island Paradise 14-4620 TPG"],"k":"SUB","c":"SEWING THREAD","a":22,"s":"SEWING THREAD"},
{"x":40,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":41,"m":"OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112","u":"PRS","p":"TOPRO INDONESIA,PT","r":"BASE / STUD / LOGO","w":["Cherry Blossom 13-3207 TPG","Illusion Blue 13-4103 TPG","Crystal Teal 19-4536 TPG"],"k":"MAIN","c":"OUTSOLE"},
{"x":45,"m":"HANGTAG ESSORER 2 FG","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Red/Black","Red/Black","Red/Black"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":46,"m":"SIZE LABEL ESSORER 2 FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":47,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","Natural","Natural"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":48,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","Natural","Natural"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":49,"m":"INNER BOX SPECS","u":"SET","d":"A3 (300 X 200 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":50,"m":"INNER BOX SPECS","u":"SET","d":"A6 (310 X 215 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":30,"s":"A6 ( 310 X 215 X 110 MM ) SIZE 41 - 44"},
{"x":51,"m":"INNER BOX SPECS","u":"SET","d":"A7 (320 X 220 X 125 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":30,"s":"A7 ( 330 X 220 X 125 MM ) SIZE 45 - 45"},
{"x":52,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":53,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":33,"s":"CARTON BOX"},
{"x":54,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":33,"s":"CARTON BOX"},
{"x":55,"m":"STICKER INNER BOX ESSORER 2 FG","u":"PCS","d":"10 CM X 6 CM","p":"EMRAN GHANIM ASAHI,PT","w":[null,null,null],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":59,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["Neon Volt / Black","Neon Volt / Black","Neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":60,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":61,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]},
{"file":"ESSORER II IN SS 28.xls","name":"ESSORER 2 IN","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-014","outsole_mold":"PRM-099","sizes":[37,38,39,40,41,42,43,44],"sample":41,"articles":[{"colorway":"CHERRY BLOSSOM / BLUE DE FRANCE","code":null},
{"colorway":"ILLUSION BLUE / SILVER","code":null},
{"colorway":"CRYSTAL TEAL / ISLAND PARADISE","code":null}],"lines":[{"x":16,"m":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Cherry Blossom 13-3207 TPG / Backing White","Illusion Blue 13-4103 TPG / Backing White","Crystal Teal 19-4536 TPG / Backing Grey"],"k":"MAIN","c":"UPPER"},
{"x":17,"m":"PRESS WELDING","u":"PRS","p":"MASTERINA GRAFIKA ESPRINTA,PT","w":["Base : Clear / Metallic Blue De France 2727 C GLOSS + PEARL GOLD","Bas : Clear / Metallic Silver 877 C Gloss + PEARL Silver","Base : Clear / Metallic Island Paradise 14-4620 TPG GLOSS + PEARL GOLD"],"k":"SUB","a":0,"s":"DECORATION PRESH WELDING FLASH TO AREA LATERAL (SEE DRAWING)"},
{"x":18,"m":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Cherry Blossom 13-3207 TPG / Backing White","Illusion Blue 13-4103 TPG / Backing White","Crystal Teal 19-4536 TPG / Backing Grey"],"k":"MAIN","c":"TONGUE"},
{"x":19,"m":"PUNCH HOLE","u":"PRS","p":"KINDO MAKMUR JAYA,PT","w":["None","None","None"],"k":"SUB","a":2,"s":"DECORATION POUNCH HOLE OVAL ( SEE DRAWING )"},
{"x":20,"m":"PU SYNTHETIC KD MANILA BACKING NON WOVEN","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Cherry Blossom 13-3207 TPG / Backing White","Illusion Blue 13-4103 TPG / Backing White","Crystal Teal 19-4536 TPG / Backing Grey"],"k":"MAIN","c":"HEEL CAP"},
{"x":21,"m":"DECO SINGLE STITCH ROW","u":"ME","p":"UNIMITRA KHARISMA, PT","w":["Cherry Blossom 13-3207 TPG","Illusion Blue 13-4103 TPG","Crystal Teal 19-4536 TPG"],"k":"SUB","a":4,"s":"DECORATION SINGLE STITCHING ROW TEMBUS LINING SESUAI ART WORK ( SEE DRAWING )"},
{"x":22,"m":"MERISKIN KD DE-7 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Blue De France 2727 C / Backing White","Metallic Silver 877 C / Backing White","Island Paradise 14-4620 TPG / Backing White"],"k":"MAIN","c":"COLLAR LINING"},
{"x":23,"m":"COCOTEX","u":"ME","d":"2 MM X 44\"","p":"SU INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"VAMP LINING"},
{"x":24,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["None","None","None"],"k":"SUB","a":7,"s":"SINGLE STICKER"},
{"x":25,"m":"FOAM 50KG 6 MM X 44\"","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","r":"COATING","w":["White","White","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":26,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"TOE BOX"},
{"x":27,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"COLLAR REINF IN / OUT"},
{"x":28,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","r":"COATING","w":["White","White","Black"],"k":"MAIN","c":"HEEL CAP REINF"},
{"x":29,"m":"SUPERLIGHT SL 560","u":"ME","d":"0.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","Black"],"k":"MAIN","c":"EYESTAY REINF"},
{"x":30,"m":"SINGLE STICKER","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["none","none","none"],"k":"SUB","a":13,"s":"SINGLE STICKER"},
{"x":31,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL DIAMETER 2.0 X 5MM","w":["none","none","none"],"k":"MAIN","c":"PUNCH HOLE"},
{"x":32,"m":"POLY FLAT TUBULAR (BSL-0040)","u":"PRS","d":"6 MM X 115 CM","p":"SUN-TEX INDONESIA, PT","r":"37-40 :110CM/41-45:115CM","w":["Cherry Blossom 13-3207 TPG","Illusion Blue 13-4103 TPG","Crystal Teal 19-4536 TPG"],"k":"MAIN","c":"SHOE LACE"},
{"x":33,"m":"TR COUNTER SC-02 (HARDNESS 99)","u":"PRS","p":"TOPRO INDONESIA,PT","w":["Black","Black","Black"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":34,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","r":"LAMINATING","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":35,"m":"EVA HARDNESS 40-45 ASKER C","u":"ME","d":"2 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["White","White","White"],"k":"SUB","a":18,"s":"2.0 MM EVA HARDNESS 40 - 45 ASKER C"},
{"x":36,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","r":"LAMINATING","w":["Black","Black","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":37,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["Black","Black","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":38,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO \" SPECS + VICTORY BOW \" ( 45MM X 30MM )","w":["Blue De France 2727 C / Backing Layer White","Metallic Silver 877 C / Backing Layer White","Island Paradise 14-4620 TPG / Backing Layer White"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":39,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Cherry Blossom 13-3207 TPG","Illusion Blue 13-4103 TPG","Crystal Teal 19-4536 TPG"],"k":"MAIN","c":"SEWING THREAD"},
{"x":40,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Blue De France 2727 C","Metallic Silver 877 C","Island Paradise 14-4620 TPG"],"k":"SUB","c":"SEWING THREAD","a":23,"s":"SEWING THREAD"},
{"x":41,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":42,"m":"OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"BASE SIDE WALL + IN SIDE BASE / LOGO","w":["Cherry Blossom 13-3207 TPG","Illusion Blue 13-4103 TPG","Crystal Teal 19-4536 TPG"],"k":"MAIN","c":"OUTSOLE"},
{"x":45,"m":"HANGTAG ESSORER 2 IN","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Red/Black","Red/Black","Red/Black"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":46,"m":"SIZE LABEL ESSORER 2 IN","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":47,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":48,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":49,"m":"INNER BOX SPECS","u":"SET","d":"A3 (300 X 200 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black Neon Volt","Black Neon Volt","Black Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":50,"m":"INNER BOX SPECS","u":"SET","d":"A6 (310 X 215 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black Neon Volt","Black Neon Volt","Black Neon Volt"],"k":"SUB","a":31,"s":"A6 ( 310 X 215 X 110 MM ) SIZE 41 - 44"},
{"x":51,"m":"INNER BOX SPECS","u":"SET","d":"A7 (320 X 220 X 125 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black Neon Volt","Black Neon Volt","Black Neon Volt"],"k":"SUB","a":31,"s":"A7 ( 330 X 220 X 125 MM ) SIZE 45 - 45"},
{"x":52,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":53,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":34,"s":"CARTON BOX"},
{"x":54,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":34,"s":"CARTON BOX"},
{"x":55,"m":"STICKER INNER BOX ESSORER 2 IN","u":"PCS","d":"10 CM X 6 CM","p":"EMRAN GHANIM ASAHI,PT","w":[null,null,null],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":59,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["neon Volt / Black","neon Volt / Black","neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":60,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":61,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]}]}$j$::jsonb;
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
