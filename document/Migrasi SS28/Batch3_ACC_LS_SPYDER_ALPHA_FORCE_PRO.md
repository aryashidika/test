# Batch 3: ACC LS SPYDER + ALPHA FORCE PRO

Draf untuk ditempel ke doc "Migrasi Specsheet SS28" (format sama dengan Batch 1 dan 2). Delapan file: ACC LS SPYDER FG, IN, CORE FG, CORE IN, FG JR, IN JR dan ALPHA FORCE PRO FG, IN. Aturan Batch 1 dan 2 tetap berlaku: stage Preview, rev 0 DRAFT, nomor article kosong, atas nama Migrasi data, material/link/Master Options yang belum ada didaftarkan impor, kode ERP 10 digit terbentuk otomatis lewat R22 (material baru disambung ke awalan kamus bila namanya sama atau ditulis di `dict`).

Sudah dicocokkan dengan M1 dan M3 terbaru (2 Nov). Dari M3: komponen UPPER LOOP (440), VAMP + QUARTER REINF IN (450), dan SPRAY OUT SOLE (4130) sudah ada, jadi impor tidak perlu mendaftarkan komponen baru.

## Batch 3: material yang ikut aturan lama (tanpa pertanyaan)

| Teks Excel | Material di sistem | Dimension | Dipakai di |
| --- | --- | --- | --- |
| Decoration Printing (semua jenis), Decoration Block + Flash | PRINTING SCREEN (Process) | tanpa | 8 model |
| Single Stiker | SINGLE STICKER (Process, MKU) | tanpa | 4 model |
| Decoration Pounch Hole, Punch hole OVAL 2.0 X 5 mm | PUNCH HOLE (Process, UMK), ukuran ke Process | tanpa | 8 model |
| 1.6 Hysock 16 N | HY SOCK 16N (HAN YOUNG) | 1.6 MM X 44" | 8 model |
| Merry Mesh Gramasi 100 / Mery Mesh (Gramasi 100) + | MERRY MESH GRAMASI 100 (BHS) | 44" (baru, seperti Batch 2) | 4 model |
| Merry Mesh (Sockliner Cover, MKU) | MERRY MESH (MKU terhubung) | 44" (baru, M1 tanpa Dimension) | 4 model |
| 5 mm Shoe Lace Spun Tubular NSL 0208 | SHOELACE SPUN TUBULAR (NSL0208) (SUN-TEX) | 5 MM X 115 CM / 110 CM | 4 model |
| CM 02 | CM 02 (JING XING) | tanpa | 6 model |
| 2.0 mm Foam 50 Kg (sub) | 2 MM FOAM 50 KG (SERIM) | 2 MM X 44" (baru) | 2 model |
| 2.0 mm Eva Hardness 40 Asker C | EVA HARDNESS 40 ASKER C (didaftarkan Batch 2, MKU) | 2 MM X 44" | 2 model |
| 0.7 mm MERRY KD DE 07 | MERISKIN KD DE-7 BACKING KNITWEAR (KINDO), keputusan Batch 2 no. 1 | 0.7 MM X 54" | 2 model |
| W/ Coating FA 7300 / 50 Micron + Sticker | COATING FA7300/50 MICRON, link ke ASSEMS INDO, PT (keputusan Batch 2 no. 12) | tanpa | 4 model |
| 0,7 mm Merry KD KL (R)054 / Backing Knitwear | MERRY KD KL R-054 BACKING KNITWEAR (KINDO) | 0.7 MM X 54" | 8 model |
| 1,2 mm PU Shyntetic KD AR 100 M | PU SYNTHETIC KD AR-100 M BACKING NON WOVEN (KINDO) | 1.2 MM X 54" (baru, M1 hanya 1.3 MM X 54") | 4 model |
| 0.9mm PU Shyntetic KD KL-R054 | PU SYNTHETIC KD KL-R054 BACKING NON WOVEN (KINDO) | 0.9 MM X 54" (baru) | 2 model |
| 6 mm Foam 50 + 5KG ( SHL ) | 2 MM FOAM 50 KG +5 SHL (SERIM) | 6 MM X 44" (baru) | 2 model |
| Standard Carton Box SPECS MB: A1A (JR) | STANDARD CARTON BOX NEW | tanpa | JR |
| Hangtag / Size Label / Sticker Inner Box | per model: HANGTAG, SIZE LABEL, STICKER INNER BOX + nama model (EMRAN), Dimension seperti Batch 2 | 60 MM X 40 MM; tanpa; 10 CM X 6 CM (JR 7.8 CM X 5 CM) | 8 model (24 material baru) |

## Batch 3: calon pendaftaran dan pertanyaan

**Data model**

| Field | SPYDER FG | SPYDER IN | SPYDER CORE FG | SPYDER CORE IN | SPYDER FG JR | SPYDER IN JR | ALPHA FG | ALPHA IN |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Nama | ACC LS SPYDER FG | ACC LS SPYDER IN | ACC LIGHTSPEED SPYDER CORE FG | ACC LIGHTSPEED SPYDER CORE IN | ACC LS SPYDER FG JR | ACC LS SPYDER IN JR | ALPHA FORCE PRO FG | ALPHA FORCE PRO IN |
| Category | FOOTBALL (kosong di Excel) | FUTSAL (kosong) | FOOTBALL (kosong) | FUTSAL (Excel: FUTSAL PHYLON) | FOOTBALL | FUTSAL (Excel: FUTSAL RUBBER) | FOOTBALL (kosong) | FUTSAL (Excel: FUTSAL PHYLON) |
| Construction | STROBLE + TOE LASTING | sama | sama | sama | sama | sama | sama | sama |
| Last | PRL-023 | PRL-014 | PRL-023 MID | PRL-023 MID | PRL-024 JR | PRL-014 JR (Excel: PRL 014 JR MID) | PRL-023 MID | PRL-014 |
| Outsole mold | PRM-105 | PRM-106 | PRM-112 | PRM-099 | PRM-091 JR | PRM-099 JR | PRM-110 | PRM-109 |
| Ukuran / sample | 37-44 / 41 | 37-44 / 41 | 37-44 / 41 | 37-46 / 41 | 32-36 / 34 | 32-36 / 34 | 37-44 / 41 | 37-46 / 41 |
| Gender | MEN | MEN | MEN | MEN | JR | JR | MEN | MEN |
| Season / stage | SS28 / Preview | sama | sama | sama | sama | sama | sama | sama |

Master Options baru: tidak ada yang pasti; PRL-014 JR, PRM-099, PRM-106, PRM-109, PRM-110 didaftarkan impor bila belum ada.

**Material baru** (sudah dicek ke M1; semua belum ada)

| Nama | Category | UoM | Supplier | Dipakai di |
| --- | --- | --- | --- | --- |
| HANGTAG / SIZE LABEL / STICKER INNER BOX + nama model (8 model, 24 material) | PACKAGING / LABEL / PACKAGING | PCS / PRS / PCS | EMRAN GHANIM ASAHI,PT | semua |
| OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-106 | OUTSOLE | PRS | UNIMITRA KHARISMA, PT | SPYDER IN |
| OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099 | OUTSOLE | PRS | UNIMITRA KHARISMA, PT | CORE IN |
| OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-109 | OUTSOLE | PRS | UNIMITRA KHARISMA, PT | ALPHA IN |
| OUTSOLE TPU INJECTION BASE 95 A / 64 D STUD 90 A PRM-110 | OUTSOLE | PRS | WINFAITH,PT | ALPHA FG |
| HULEX NAPPA GRIP EFFECT | SYNTHETIC LEATHER | ME | FUJIAN HEHE INTERNATIONAL TRAD | Vamp Overlay, 0.3 MM X 54" |
| SINGLE MESH JZ 9036 | FABRIC | ME | FUJIAN HEHE INTERNATIONAL TRAD | Vamp, 54" |
| POLY FLAT TUBULAR BYL C028 | LACE | PRS | BOO YOUNG INDONESIA,PT | Shoe Lace ALPHA, 6 MM X 115 CM |
| NEGATIVE FILM (Process) | PROCESS | PRS | MULTI KARYA USAHA, PT (Excel: MGE) | lihat no. 11 |

Link supplier baru (dibuat otomatis oleh impor): CORE FG outsole ke TOPRO bila dipilih (no. 7); MERRY MESH GRAMASI 100 dan lainnya sesuai supplier Excel.

Perlu Anda cek (usulan saya di tiap nomor; jawab "setuju" atau koreksi):

1. **Category kosong dan gender.** SPYDER FG/IN, CORE FG, ALPHA FG tidak menulis category. Usul dari nama file (FG = FOOTBALL, IN = FUTSAL), gender MEN kecuali JR. Setuju?
2. **Last dan ukuran.** SPYDER IN JR "PRL 014 JR MID" jadi PRL-014 JR (seperti Batch 2 no. 4). CORE FG/IN dan ALPHA FG tetap PRL-023 MID sesuai Excel. CORE IN dan ALPHA IN ukuran 37-46 sesuai Excel. Setuju?
3. **UoM bentrok dengan M1.** Beberapa teks Excel UoM-nya PRS, sedangkan material sistem: HULEX NAPA ANTI (STICKY SURFACE) = YD, MESH TN 378B = ME, T-160 (HASI-022) = ME, POLYPAG 2 (HASI 028) = ME. Usul: pakai UoM sistem (CEK akan menolak UoM beda). Setuju?
4. **Hulex Napa Anti XHGC 025 (STICKY SURFACE, FUJIAN HEHE).** M1: HULEX NAPA ANTI (STICKY SURFACE), Dimension 0.3 MM X 51". Excel 0,3 mm tanpa lebar. Usul pakai itu dengan Dimension 0.3 MM X 51". Setuju?
5. **Mesh TN 378 B (28 GSM), HASI 022T 160, Hasi Poly Page II.** M1: MESH TN 378B (WIGHT 28 GR ) .54" (FUJIAN HEHE, HEKSATEX), T-160 (HASI-022 GRAMASI 160GSM) 44" (FUJIAN HEHE, HWASUNG), POLYPAG 2 (HASI 028) 44" (FUJIAN HEHE, HWASUNG). Supplier kosong di Excel diisi FUJIAN HEHE dari link. Usul pakai ketiganya. Setuju?
6. **1.2 mm ± 0.1mm NW 260 Non Woven (HWASUNG).** M1: 1.2 MM NON WOVEN NW 260, 44", HWASUNG terhubung. Usul pakai itu, Dimension 44" (ukuran 1.2 MM sudah di nama). Setuju?
7. **Outsole CORE FG (PRM-112, TOPRO).** Excel: TPU Injection, Base/Stud/Logo 98 Shore D. M1 punya OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112 (WINFAITH, dipakai IMPULSE FG). Usul pakai itu; supplier tetap TOPRO dari Excel (link baru) atau WINFAITH sesuai link? Process: BASE / STUD / LOGO.
8. **Outsole SPYDER FG (PRM-105, JING XING).** Excel: Base TPU 98 A, Stud Tip TPU 90 A. M1: OUTSOLE TPU INJECTION BASE 98 A TPU 95 A PRM-105 (JING XING). Usul pakai itu; Base dan Stud Tip masuk Process. Atau material baru Stud 90 A?
9. **Spray Outsole SPYDER FG.** M3 punya komponen SPRAY OUT SOLE (4130) dan M1 punya SPRAY OUTSOLE (Process, INDOKU). Keputusan Batch 2: sub-baris OUTSOLE dengan material SPRAY OUTSOLE. Dipakai lagi, atau mau baris utama komponen SPRAY OUT SOLE?
10. **Outsole FG JR (PRM-091 JR, WINFAITH).** Excel: Base dan Stud TPU 90-92 Short A. M1: OUTSOLE TPU INJECTION HARDNESS 98 A PRM-091 JR. Batch 2 no. 13 memakainya walau Excel 98 Shore D. Usul sama, Process BASE / STUD. Atau material baru 90-92 A?
11. **Outsole rubber IN (PRM-106, PRM-099, PRM-109; PRM-099 JR sudah ada).** Base, Center Mid, Logo, Base Side Wall tidak jadi sub-baris: warna ke baris outsole, nama ke Process. Setuju? Dan **Decoration Negative Film (MGE)**: material baru NEGATIVE FILM (Process), atau ikut PRINTING SCREEN seperti decoration lain?
12. **Outsole ALPHA FG (PRM-110, WINFAITH).** Excel: Base Front 95 A, Base Heel 64 D, Stud Tip 90 A. Usul material baru OUTSOLE TPU INJECTION BASE 95 A / 64 D STUD 90 A PRM-110; bagian ke Process. Setuju?
13. **Midsole PRM-106 dan PRM-109 tampak tertukar.** SPYDER IN Excel: Phylon 60±2 (DWI MITRA). ALPHA IN Excel: Phylon 50-55 (DWI MITRA). M1: PRM-106 = 50-55, PRM-109 = 60±2. Usul ikut Excel, material baru: INJECTION PHYLON HARDNESS 60±2 ASKER C PRM-106 (SPYDER IN) dan INJECTION PHYLON HARDNESS 50-55 ASKER C PRM-109 (ALPHA IN). Atau pakai material M1 apa adanya? Mohon cek mana yang benar.
14. **Dimension baru pada material yang sudah ada.** AR-100 M 1.2 MM X 54" (M1: 1.3), KL-R054 0.9 MM X 54" (M1: 1.2), EVA HARDNESS 40 ASKER C 2 MM X 44", 2 MM FOAM 50 KG 2 MM X 44", MERRY MESH 44", MERRY MESH GRAMASI 100 44". Dibuat impor. Setuju?
15. **6 mm Foam 50 + 5KG (SHL) (SERIM, Collar Foam, 2 model).** M1 tidak punya 6 MM +5 SHL; yang ada 2 MM FOAM 50 KG +5 SHL (tanpa Dimension) dan 8 MM FOAM 50+5 SHL. Usul 2 MM FOAM 50 KG +5 SHL dengan Dimension 6 MM X 44" (pola Batch 2). Atau material baru 6 MM FOAM 50+5 SHL?
16. **Hulex Nappa Grip Effect, Single Mesh JZ 9036, Poly Flat Tubular BYL C028 (115 CM).** Tidak ada di M1 (JZ 9036 dan C028 hanya mirip). Usul material baru seperti tabel. Setuju?
17. **Nama komponen (dari M3).** Semua nama Excel sudah ada atau teralias: "VAMP LINNING" jadi VAMP LINING, UPPER LOOP dan VAMP + QUARTER REINF IN sudah ada, Spray Outsole lihat no. 9. Cukup konfirmasi.
18. **Penulisan warna.** Metalic jadi Metallic, Shinny jadi Shiny, warna kosong NONE seperti Batch 2. Setuju?

## Hasil impor (2 Nov 2026)

Jawaban user atas 18 pertanyaan: semua setuju, dengan koreksi: no. 7 link TOPRO baru; no. 8 dan 10 material baru dengan nama baku; no. 11 NEGATIVE FILM material Process baru; no. 12 nama dan Process ditulis lengkap (Base Front 95 A, Base Heel 64 D, Stud Tip 90 A); no. 13 material baru sesuai Excel; no. 15 material baru 6 MM FOAM 50 KG +5 SHL (Batch 2 tidak diubah); supplier 1.2 MM NON WOVEN NW 260 = HWASUNG INTERNATIONAL,PT.

SQL: `SQL_Batch3/cek.sql`, `impor_spyder.sql` (6 model), `impor_alpha.sql` (2 model). Generator: `appsmith/tools/ss28/gen_import.py` (batch3).

UJI SAJA: SPYDER 6 model, 179 baris utama, 78 sub; ALPHA 2 model, 61 baris utama, 24 sub (sama dengan generator). Setelah disimpan, 3.3 sesuai. Recheck 3.4 (8 model) dibaca manual terhadap keluaran generator: header, material, Dimension, supplier, Process, dan warna sama.

Catatan dari Excel (disimpan apa adanya, belum dikoreksi):
- ACC LS SPYDER FG JR: kolom Process berisi warna, Strobel Thread "BLACK / NEON VOLT" dan Heel Counter "BROWN/BLACK".
- ALPHA FORCE PRO IN: warna Tissue Paper dan Wrapping Paper tertulis "NATIRAL" (maksud NATURAL); Silica Gel article 2 kosong.
- ALPHA FORCE PRO IN: Shoe Lace dan beberapa baris memakai warna dari Excel apa adanya ("Flourecent", "Mixtuer" di SPYDER IN).
