-- Impor specsheet dari Excel lama (Migrasi Specsheet SS28). Satu transaksi.
-- v_simpan = false: semua dijalankan lalu DIBATALKAN, pesan "UJI SAJA" menampilkan jumlahnya.
-- v_simpan = true : disimpan. Pengaman: model yang sudah ada tidak ditimpa, semua nama master harus ditemukan.
DO $$
DECLARE
  v_simpan  boolean := false;   -- false = uji saja (dibatalkan), true = simpan
  d         jsonb := $j${"user":"Migrasi data","season":"SS28","stage":"PREV","options":[{"kind":"KATEGORI","value":"FOOTBALL"},
{"kind":"CONSTRUCTION","value":"STROBLE + TOE LASTING"},
{"kind":"GENDER","value":"MEN"},
{"kind":"LAST","value":"PRL-015"},
{"kind":"OUTSOLE_MOLD","value":"PRM-101"},
{"kind":"KATEGORI","value":"FUTSAL"},
{"kind":"LAST","value":"PRL-014"},
{"kind":"OUTSOLE_MOLD","value":"PRM-102"}],"materials":[{"name":"SIZE LABEL LIGHT SPEED NEW REBORN FG","category":"LABEL","uom":"PRS","is_process":false},
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
{"name":"HULEX DIVE KD KL-R070 BACKING MICRO FIBER","category":"SYNTHETIC LEATHER","uom":"ME","is_process":false},
{"name":"PRINTING SCREEN","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"PERFORATED","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"MERRY MESH GRAMASI 100","category":"MESH","uom":"ME","is_process":false},
{"name":"COATING FA7300/50 MICRON","category":"PROCESS","uom":"ME","is_process":true},
{"name":"FOAM 50KG 6 MM X 44\"","category":"FOAM","uom":"ME","is_process":false},
{"name":"CANVAS 6 OZ","category":"FABRIC","uom":"ME","is_process":false},
{"name":"1.2 MM NON WOVEN NW 260","category":"FABRIC","uom":"ME","is_process":false},
{"name":"POLYPAG 2 (HASI 028)","category":"FABRIC","uom":"ME","is_process":false},
{"name":"FLATLACE TIP 15 MM BYL E 005","category":"LACE","uom":"PRS","is_process":false},
{"name":"PUNCH HOLE","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"CM 02","category":"COUNTER","uom":"EA","is_process":false},
{"name":"HY SOCK 16N","category":"FABRIC","uom":"ME","is_process":false},
{"name":"EVA HARDNESS 45-50","category":"FOAM","uom":"ME","is_process":false},
{"name":"TRANSFER PAPER","category":"PROCESS","uom":"PRS","is_process":true},
{"name":"BONDED THREAD(210D/3P)","category":"THREAD","uom":"CON","is_process":false},
{"name":"BONDED THREAD(N280D/3P)","category":"THREAD","uom":"CON","is_process":false},
{"name":"TISSUE PAPER","category":"PACKAGING","uom":"RIM","is_process":false},
{"name":"INNER BOX SPECS","category":"PACKAGING","uom":"SET","is_process":false},
{"name":"STANDARD CARTON BOX NEW","category":"PACKAGING","uom":"EA","is_process":false},
{"name":"STANDARD ISOLATAPE SPECS","category":"PACKAGING","uom":"ME","is_process":false},
{"name":"STRING PIN","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"SILICAGEL","category":"PACKAGING","uom":"PCS","is_process":false},
{"name":"INJECTION PHYLON HARDNESS 50-55 ASKER C PRM-102","category":"MIDSOLE","uom":"PRS","is_process":false}],"models":[{"file":"GALACTICA HYDRA ENERGA FG SS 28.xlsx","name":"GALACTICA HYDRA ENERGA FG","category":"FOOTBALL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-015","outsole_mold":"PRM-101","sizes":[37,38,39,40,41,42,43,44],"sample":41,"articles":[{"colorway":"FLAME RED / WHITE / PALE GOLD","code":null},
{"colorway":"PHANTOM / BLACK / SILVER","code":null},
{"colorway":"WHITE / BLUE BIRD / PINK","code":null}],"lines":[{"x":16,"m":"HULEX DIVE KD KL-R070 BACKING MICRO FIBER","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Flame Scarlet 18-1662 TPG / Backing White","Phantom 19-4205 TPG / Backing Black","White C / Backing White"],"k":"MAIN","c":"UPPER"},
{"x":17,"m":"PRINTING 3D","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"0.8 MM","w":["Glossy Clear","Glossy Clear","Glossy Clear"],"k":"SUB","a":0,"s":"DECORATION 0.8 MM PRINTING 3D MOTIF SESUAI ART WORK ( SEE DRAWING )"},
{"x":18,"m":"PRINTING SCREEN","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["White C Matte","Black Matte","Blue Bird 16-4834 TPG Matte"],"k":"SUB","a":0,"s":"DECORATION PRINTING BLOCK + GRADATION SESUAI ART WORK ( SEE DRAWING )"},
{"x":19,"m":"PRINTING SCREEN","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["Glossy Metallic Pale Gold 15-0927 TPG","Glossy Metallic Silver 877 C","Glossy Neon Knock Out Pink 16-2130 TN"],"k":"SUB","a":0,"s":"DECORATION PRINTINGOUT LINE FLASH + WORDING \" GRIP TOUCH \" AREA LATERAL & WORDING \"GALACTICA + OUT LINE LINE WORDING HYDRA \"AREA MEDIAL SESUAI ART WORK ( SEE DRAWING )"},
{"x":20,"m":"HULEX DIVE KD KL-R070 BACKING MICRO FIBER","u":"ME","d":"0.9 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Flame Scarlet 18-1662 TPG / Backing White","Phantom 19-4205 TPG / Backing Black","White C / Backing White"],"k":"MAIN","c":"TONGUE"},
{"x":21,"m":"PRINTING SCREEN","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["White C Matte","Black Matte","Blue Bird 16-4834 TPG Matte"],"k":"SUB","a":4,"s":"DECORATION PRINTING LOGO FLASH + WORDING \" SPECS \" + LINE BLOCK GRADATION SESUAI ART WORK ( SEE DRAWING )"},
{"x":22,"m":"PERFORATED","u":"PRS","p":"UNIMITRA KHARISMA, PT","w":["None","None","None"],"k":"SUB","a":4,"s":"DECORATION PEPORATED SESUAI ART WORK ( SEE DRAWING )"},
{"x":23,"m":"MERRY KD KL-R534 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Flame Scarlet 18-1662 TPG / Backing White","Phantom 19-4205 TPG / Backing Black","White C / Backing White"],"k":"MAIN","c":"COLLAR LINING"},
{"x":24,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","w":["White","Black","White"],"k":"MAIN","c":"VAMP LINING"},
{"x":25,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":8,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":26,"m":"FOAM 50KG 6 MM X 44\"","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","w":["White","Black","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":27,"m":"CANVAS 6 OZ","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL IND","w":["Natural","Natural","Natural"],"k":"MAIN","c":"TOE BOX"},
{"x":28,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":11,"s":"W/ COATING FA 7300 / 100 MICRON + STICKER"},
{"x":29,"m":"1.2 MM NON WOVEN NW 260","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL,PT","w":["White","Black","White"],"k":"MAIN","c":"COLLAR REINF IN / OUT"},
{"x":30,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":13,"s":"W/ COATING FA 7300 / 100 MICRON + STICKER"},
{"x":31,"m":"POLYPAG 2 (HASI 028)","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL,PT","w":["White","Black","White"],"k":"MAIN","c":"EYESTAY REINF IN"},
{"x":32,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":15,"s":"W/ COATING FA 7300 / 100 MICRON + STICKER"},
{"x":33,"m":"FLATLACE TIP 15 MM BYL E 005","u":"PRS","d":"5 MM X 115 CM","p":"BOO YOUNG INDONESIA,PT","w":["Base : Flame Scarlet 18-1662 TPG / Asken : Flame Scarlet 18-1662 TPG","Base : Phantom 19-4205 TPG / Asken : Phantom 19-4205 TPG","Base : White C / Asken :White C"],"k":"MAIN","c":"SHOE LACE"},
{"x":34,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL DIAMETER 1.5 X 5 MM","w":[null,null,null],"k":"MAIN","c":"PUNCH HOLE"},
{"x":35,"m":"CM 02","u":"EA","p":"JING XING INDONESIA, PT","w":["White","White","White"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":36,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":37,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","w":["Black","Black","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":38,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["Black","Black","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":39,"m":"PERFORATED","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"DIECUTT EVA","w":["None","None","None"],"k":"SUB","a":22,"s":"PERPORATED DIECUTT EVA"},
{"x":40,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO WORDING \" \" 60MM X 3.9MM","w":["White","Phantom 19-4205 TPG","Blue Bird 16-4834 TPG"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":41,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Flame Scarlet 18-1662 TPG","Phantom 19-4205 TPG","White C"],"k":"MAIN","c":"SEWING THREAD"},
{"x":42,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","Black","White"],"k":"SUB","c":"SEWING THREAD","a":25,"s":"SEWING THREAD"},
{"x":43,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":44,"m":"OUTSOLE TPU INJECTION BASE 98 D STUD 98 A PRM-101","u":"PRS","p":"SINAR MASANDA INDUSTRI,PT","r":"BASE HARDNESS 98 SHORE D / STUD TIP TPU HARDNESS 98A","w":["EXTRA GLOSSY White C / Translucent Metallic Pale Gold 15-0927 TPG","EXTRA GLOSSY Black / Translucent Metallic Silver 877 C","EXTRA GLOSSY Blue Bird 16-4834 TPG / Translucent Neon Knock Out Pink 16-2130 TN"],"k":"MAIN","c":"OUTSOLE"},
{"x":47,"m":"HANGTAG GALACTICA HYDRA ENERGA FG","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Red /Black","Red /Black","Red /Black"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":48,"m":"SIZE LABEL GALACTICA HYDRA ENERGA FG","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":49,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":50,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["White","White","White"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":51,"m":"INNER BOX SPECS","u":"SET","d":"A3 (300 X 200 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":52,"m":"INNER BOX SPECS","u":"SET","d":"A6 (310 X 215 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":33,"s":"A6 ( 310 X 215 X 110 MM ) SIZE 41 - 44"},
{"x":53,"m":"INNER BOX SPECS","u":"SET","d":"A7 (320 X 220 X 125 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":33,"s":"A7 ( 320 X 220 X 125 MM ) SIZE 45 - 45"},
{"x":54,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":55,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":36,"s":"CARTON BOX"},
{"x":56,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":36,"s":"CARTON BOX"},
{"x":57,"m":"STICKER INNER BOX GALACTICA HYDRA ENERGA FG","u":"PCS","d":"10 CM X 6 CM","p":"EMRAN GHANIM ASAHI,PT","w":["Brown /Black","Brown /Black","Brown /Black"],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":61,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["Neon Volt / Black","Neon Volt / Black","Neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":62,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":63,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]},
{"file":"GALACTICA HYDRA ENERGA IN SS 28.xlsx","name":"GALACTICA HYDRA ENERGA IN","category":"FUTSAL","construction":"STROBLE + TOE LASTING","gender":"MEN","last":"PRL-014","outsole_mold":"PRM-102","sizes":[37,38,39,40,41,42,43,44,45,46],"sample":41,"articles":[{"colorway":"FLAME RED / WHITE / PALE GOLD","code":null},
{"colorway":"PHANTOM / BLACK / SILVER","code":null},
{"colorway":"WHITE / BLUE BIRD / PINK","code":null}],"lines":[{"x":16,"m":"HULEX DIVE KD KL-R070 BACKING MICRO FIBER","u":"ME","d":"1.2 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Flame Scarlet 18-1662 TPG / Backing White","Phantom 19-4205 TPG / Backing Black","White C / Backing White"],"k":"MAIN","c":"UPPER"},
{"x":17,"m":"PRINTING 3D","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"0.8 MM","w":["Glossy Clear","Glossy Clear","Glossy Clear"],"k":"SUB","a":0,"s":"DECORATION 0.8 MM PRINTING 3D MOTIF SESUAI ART WORK ( SEE DRAWING )"},
{"x":18,"m":"PRINTING SCREEN","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["White C Matte","Black Matte","Blue Bird 16-4834 TPG Matte"],"k":"SUB","a":0,"s":"DECORATION PRINTING BLOCK + GRADATION SESUAI ART WORK ( SEE DRAWING )"},
{"x":19,"m":"PRINTING SCREEN","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["Glossy Metallic Pale Gold 15-0927 TPG","Glossy Metallic Silver 877 C","Glossy Neon Knock Out Pink 16-2130 TN"],"k":"SUB","a":0,"s":"DECORATION PRINTINGOUT LINE FLASH + WORDING \" GRIP TOUCH \" AREA LATERAL & WORDING \"GALACTICA + OUT LINE LINE WORDING HYDRA \"AREA MEDIAL SESUAI ART WORK ( SEE DRAWING )"},
{"x":20,"m":"HULEX DIVE KD KL-R070 BACKING MICRO FIBER","u":"ME","d":"0.9 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Flame Scarlet 18-1662 TPG / Backing White","Phantom 19-4205 TPG / Backing Black","White C / Backing White"],"k":"MAIN","c":"TONGUE"},
{"x":21,"m":"PRINTING SCREEN","u":"PRS","p":"MULTI KARYA USAHA, PT","w":["White C Matte","Black Matte","Blue Bird 16-4834 TPG Matte"],"k":"SUB","a":4,"s":"DECORATION PRINTING LOGO FLASH + WORDING \" SPECS \" + LINE BLOCK GRADATION SESUAI ART WORK ( SEE DRAWING )"},
{"x":22,"m":"PERFORATED","u":"PRS","p":"UNIMITRA KHARISMA, PT","w":["None","None","None"],"k":"SUB","a":4,"s":"DECORATION PEPORATED SESUAI ART WORK ( SEE DRAWING )"},
{"x":23,"m":"MERRY KD KL-R534 BACKING KNITWEAR","u":"ME","d":"0.7 MM X 54\"","p":"KINDO MAKMUR JAYA,PT","w":["Flame Scarlet 18-1662 TPG / Backing White","Phantom 19-4205 TPG / Backing Black","White C / Backing White"],"k":"MAIN","c":"COLLAR LINING"},
{"x":24,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","w":["White","Black","White"],"k":"MAIN","c":"VAMP LINING"},
{"x":25,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":8,"s":"W/ COATING FA 7300 / 50 MICRON + STICKER"},
{"x":26,"m":"FOAM 50KG 6 MM X 44\"","u":"ME","d":"6 MM X 44\"","p":"SERIM INDONESIA,PT","w":["White","Black","White"],"k":"MAIN","c":"COLLAR FOAM"},
{"x":27,"m":"CANVAS 6 OZ","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL IND","w":["Natural","Natural","Natural"],"k":"MAIN","c":"TOE BOX"},
{"x":28,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":11,"s":"W/ COATING FA 7300 / 100 MICRON + STICKER"},
{"x":29,"m":"1.2 MM NON WOVEN NW 260","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL,PT","w":["White","Black","White"],"k":"MAIN","c":"COLLAR REINF IN / OUT"},
{"x":30,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":13,"s":"W/ COATING FA 7300 / 100 MICRON + STICKER"},
{"x":31,"m":"POLYPAG 2 (HASI 028)","u":"ME","d":"44\"","p":"HWASUNG INTERNATIONAL,PT","w":["White","Black","White"],"k":"MAIN","c":"EYESTAY REINF IN"},
{"x":32,"m":"COATING FA7300/50 MICRON","u":"ME","p":"ASSEMS INDO, PT","w":["None","None","None"],"k":"SUB","a":15,"s":"W/ COATING FA 7300 / 100 MICRON + STICKER"},
{"x":33,"m":"FLATLACE TIP 15 MM BYL E 005","u":"PRS","d":"5 MM X 115 CM","p":"BOO YOUNG INDONESIA,PT","w":["Base : Flame Scarlet 18-1662 TPG / Asken : Flame Scarlet 18-1662 TPG","Base : Phantom 19-4205 TPG / Asken : Phantom 19-4205 TPG","Base : White C / Asken :White C"],"k":"MAIN","c":"SHOE LACE"},
{"x":34,"m":"PUNCH HOLE","u":"PRS","p":"UNIMITRA KHARISMA, PT","r":"OVAL DIAMETER 1.5 X 5 MM","w":[null,null,null],"k":"MAIN","c":"PUNCH HOLE"},
{"x":35,"m":"CM 02","u":"EA","p":"JING XING INDONESIA, PT","w":["White","White","White"],"k":"MAIN","c":"HEEL COUNTER"},
{"x":36,"m":"HY SOCK 16N","u":"ME","d":"1.6 MM X 44\"","p":"HAN YOUNG INDONESIA,PT","w":["White","White","White"],"k":"MAIN","c":"INSOLE"},
{"x":37,"m":"MERRY MESH GRAMASI 100","u":"ME","d":"44\"","p":"BUKIT HIJAU SENTOSA,PD","w":["Black","Black","Black"],"k":"MAIN","c":"SOCKLINER COVER"},
{"x":38,"m":"EVA HARDNESS 45-50","u":"ME","d":"4 MM X 44\"","p":"MULTI KARYA USAHA, PT","w":["Black","Black","Black"],"k":"MAIN","c":"SOCKLINER DIE CUT"},
{"x":39,"m":"PERFORATED","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"DIECUTT EVA","w":["None","None","None"],"k":"SUB","a":22,"s":"PERPORATED DIECUTT EVA"},
{"x":40,"m":"TRANSFER PAPER","u":"PRS","p":"MULTI KARYA USAHA, PT","r":"LOGO WORDING \" \" 60MM X 3.9MM","w":["White","Phantom 19-4205 TPG","Blue Bird 16-4834 TPG"],"k":"MAIN","c":"SOCKLINER LOGO"},
{"x":41,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["Flame Scarlet 18-1662 TPG","Phantom 19-4205 TPG","White C"],"k":"MAIN","c":"SEWING THREAD"},
{"x":42,"m":"BONDED THREAD(210D/3P)","u":"CON","d":"2000 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","Black","White"],"k":"SUB","c":"SEWING THREAD","a":25,"s":"SEWING THREAD"},
{"x":43,"m":"BONDED THREAD(N280D/3P)","u":"CON","d":"1500 ME","p":"IDAMAN ERA MANDIRI, PT","w":["White","White","White"],"k":"MAIN","c":"STROBEL THREAD"},
{"x":47,"m":"INJECTION PHYLON HARDNESS 50-55 ASKER C PRM-102","u":"PRS","p":"KUMKANG TECH INDONESIA,PT","w":["White C","Black","Blue Bird 16-4834 TPG"],"k":"MAIN","c":"MIDSOLE"},
{"x":48,"m":"SIZE LABEL GALACTICA HYDRA ENERGA IN","u":"PRS","p":"EMRAN GHANIM ASAHI,PT","w":["White/Black","White/Black","White/Black"],"k":"MAIN","c":"SIZE LABEL"},
{"x":49,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","Natural","Natural"],"k":"MAIN","c":"TISSUE PAPER"},
{"x":50,"m":"HANGTAG GALACTICA HYDRA ENERGA IN","u":"PCS","d":"60 MM X 40 MM","p":"EMRAN GHANIM ASAHI,PT","w":["Red / White","Red / White","Red / White"],"k":"MAIN","c":"HANG TAG PRICE"},
{"x":51,"m":"TISSUE PAPER","u":"RIM","d":"44 X 69 CM","p":"ROYAL QUICK INDO,CV","w":["Natural","White","Natural"],"k":"MAIN","c":"WRAPPING PAPER"},
{"x":52,"m":"INNER BOX SPECS","u":"SET","d":"A3 (300 X 200 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"MAIN","c":"INNER BOX"},
{"x":53,"m":"INNER BOX SPECS","u":"SET","d":"A6 (310 X 215 X 110 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":33,"s":"A6 ( 310 X 215 X 110 MM ) SIZE 41 - 44"},
{"x":54,"m":"INNER BOX SPECS","u":"SET","d":"A7 (320 X 220 X 125 MM)","p":"KARYA INDAH MULTIGUNA,PT","w":["Black / Neon Volt","Black / Neon Volt","Black / Neon Volt"],"k":"SUB","a":33,"s":"A7 ( 320 X 220 X 125 MM ) SIZE 45 - 45"},
{"x":55,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"MAIN","c":"CARTON BOX"},
{"x":56,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":36,"s":"CARTON BOX"},
{"x":57,"m":"STANDARD CARTON BOX NEW","u":"EA","p":"KARYA INDAH MULTIGUNA,PT","w":["Brown/Black","Brown/Black","Brown/Black"],"k":"SUB","a":36,"s":"CARTON BOX"},
{"x":58,"m":"STICKER INNER BOX GALACTICA HYDRA ENERGA IN","u":"PCS","d":"10 CM X 6 CM","p":"EMRAN GHANIM ASAHI,PT","w":["Red / White","Red / White","Red / White"],"k":"MAIN","c":"STICKER INNER BOX"},
{"x":62,"m":"STANDARD ISOLATAPE SPECS","u":"ME","p":"RUNGKUT CAHAYA,PT","w":["Neon Volt / Black","Neon Volt / Black","Neon Volt / Black"],"k":"MAIN","c":"ISOLATAPE"},
{"x":63,"m":"STRING PIN","u":"PCS","d":"3\"","p":"DARMA SUKSES MANDIRI,CV","w":["Clear","Clear","Clear"],"k":"MAIN","c":"STRING PIN"},
{"x":64,"m":"SILICAGEL","u":"PCS","p":"IMCO SILICA","w":["Natural","Natural","Natural"],"k":"MAIN","c":"SILICA GEL"}]}]}$j$::jsonb;
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
