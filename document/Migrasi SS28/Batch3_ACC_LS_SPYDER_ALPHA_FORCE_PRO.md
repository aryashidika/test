# Batch 3: ACC LS SPYDER + ALPHA FORCE PRO

Draf untuk ditempel ke doc "Migrasi Specsheet SS28" (format sama dengan Batch 1 dan 2). Delapan file: ACC LS SPYDER FG, IN, CORE FG, CORE IN, FG JR, IN JR dan ALPHA FORCE PRO FG, IN. Aturan Batch 1 dan 2 tetap berlaku: stage Preview, rev 0 DRAFT, nomor article kosong, atas nama Migrasi data, material/link/Master Options yang belum ada didaftarkan impor, kode ERP 10 digit terbentuk otomatis lewat R22 (material baru disambung ke awalan kamus bila namanya sama atau ditulis di `dict`).

Pencocokan di bawah memakai `master/material.json` (28 Okt) ditambah material yang didaftarkan pilot, Batch 1, dan Batch 2. **Belum dicocokkan dengan M1 terbaru (2 Nov).** Mohon jalankan ulang M1 (query di doc Langkah 1) dan kirim hasilnya; tabel "belum ada" bisa berubah.

## Batch 3: material yang ikut aturan lama (tanpa pertanyaan)

| Teks Excel | Material di sistem | Dimension | Dipakai di |
| --- | --- | --- | --- |
| Decoration Printing (semua jenis), Decoration Block + Flash | PRINTING SCREEN (Process) | tanpa | 8 model |
| Single Stiker | SINGLE STICKER (Process, MKU) | tanpa | 4 model |
| Decoration Pounch Hole, Punch hole OVAL 2.0 X 5 mm | PUNCH HOLE (Process, UMK), ukuran ke Process | tanpa | 8 model |
| 1.6 Hysock 16 N | HY SOCK 16N (HAN YOUNG) | 1.6 MM X 44" | 8 model |
| Merry Mesh Gramasi 100 / Mery Mesh (Gramasi 100) + | MERRY MESH GRAMASI 100 (BHS) | 44" | 4 model |
| Merry Mesh (Sockliner Cover, MKU) | MERRY MESH (ada, MKU terhubung) | 44" (baru bila belum ada) | 4 model |
| 5 mm Shoe Lace Spun Tubular NSL 0208 | SHOELACE SPUN TUBULAR (NSL0208) (SUN-TEX) | 5 MM X 115 CM / 110 CM | 4 model |
| CM 02 | CM 02 (JING XING) | tanpa | 6 model |
| 2.0 mm Foam 50 Kg (sub) | 2 MM FOAM 50 KG (SERIM) | 2 MM X 44" | 2 model |
| 2.0 mm Eva Hardness 40 Asker C | EVA HARDNESS 40 ASKER C (didaftarkan Batch 2, MKU) | 2 MM X 44" | 2 model |
| 0.7 mm MERRY KD DE 07 | MERISKIN KD DE-7 BACKING KNITWEAR (KINDO), keputusan Batch 2 no. 1 | 0.7 MM X 54" | 2 model |
| W/ Coating FA 7300 / 50 Micron + Sticker | COATING FA7300/50 MICRON, link ke ASSEMS INDO, PT (keputusan Batch 2 no. 12) | tanpa | 4 model |
| 0,7 mm Merry KD KL (R)054 / Backing Knitwear | MERRY KD KL R-054 BACKING KNITWEAR (KINDO) | 0.7 MM X 54" | 8 model |
| 1,2 mm PU Shyntetic KD AR 100 M | PU SYNTHETIC KD AR-100 M BACKING NON WOVEN (KINDO) | 1.2 MM X 54" | 4 model |
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

Master Options baru: kemungkinan PRL-014 JR (cek), selain itu semua sudah ada. Impor mendaftarkan yang belum ada.

**Material baru** (usulan)

| Nama | Category | UoM | Supplier | Dari |
| --- | --- | --- | --- | --- |
| HANGTAG / SIZE LABEL / STICKER INNER BOX untuk 8 model (24) | PACKAGING / LABEL | PCS / PRS / PCS | EMRAN GHANIM ASAHI,PT | Standard SPECS |
| OUTSOLE TPU INJECTION BASE 98 D STUD 98 D PRM-112 atau pakai OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112 | OUTSOLE | PRS | TOPRO (Excel) | CORE FG, lihat no. 5 |
| OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-106 | OUTSOLE | PRS | UNIMITRA KHARISMA, PT | SPYDER IN |
| OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-099 | OUTSOLE | PRS | UNIMITRA KHARISMA, PT | CORE IN |
| OUTSOLE RUBBER CUP SOLE HARDNESS 60 SHORE A PRM-109 | OUTSOLE | PRS | UNIMITRA KHARISMA, PT | ALPHA IN |
| OUTSOLE TPU INJECTION BASE 95 A / 64 D STUD 90 A PRM-110 | OUTSOLE | PRS | WINFAITH,PT | ALPHA FG |
| HULEX NAPPA GRIP EFFECT | FABRIC | ME | FUJIAN HEHE | Vamp Overlay, 0.3 MM X 54" |
| SINGLE MESH JZ 9036 | FABRIC | ME | FUJIAN HEHE | Vamp, 54" |
| POLY FLAT TUBULAR BYL C028 | LACE | PRS | BOO YOUNG | Shoe Lace ALPHA, 6 MM X 115 CM |
| NEGATIVE FILM (Process) | PROCESS | PRS | MGE | Decoration Negative Film, lihat no. 8 |
| SPRAY OUTSOLE sudah ada (Batch 2), dipakai lagi | PROCESS | PRS | INDOKU | SPYDER FG |

Perlu Anda cek (usulan saya di sebelah tiap nomor; jawab "setuju" atau koreksi):

1. **Category kosong** (SPYDER FG/IN, CORE FG, ALPHA FG) dan **gender**. Usul: dari nama file (FG = FOOTBALL, IN = FUTSAL), gender MEN kecuali JR. Setuju?
2. **Last SPYDER IN JR.** Excel "PRL 014 JR MID", usul PRL-014 JR seperti Batch 2. CORE FG/IN dan ALPHA FG memakai PRL-023 MID sesuai Excel. Setuju?
3. **Hulex Nappa Anti XHGC 025 (STICKY SURFACE).** Sistem punya HULEX NAPA ANTI (STICKY SURFACE). Usul pakai itu, Dimension 0.3 MM (Excel). Atau material baru?
4. **Mesh TN 378 B (28 GSM).** Sistem: MESH TN 378B (WIGHT 28 GR ).54". Usul pakai itu.
5. **HASI 022T 160 dan Hasi Poly Page II.** Sistem: T-160 (HASI-022 GRAMASI 160GSM) dan POLYPAG 2 (HASI 028). Usul pakai keduanya, supplier dari Excel (FUJIAN HEHE / kosong diisi dari link material). Setuju? Kalau bukan, material baru.
6. **1.2 mm ± 0.1mm NW 260 Non Woven (HWASUNG).** Sistem: 1.2 MM NON WOVEN NW 260. Usul pakai itu, Dimension 1.2 MM X 44".
7. **Outsole SPYDER FG (PRM-105).** Excel: Base TPU 98 A, Stud Tip TPU 90 A, JING XING. Sistem: OUTSOLE TPU INJECTION BASE 98 A TPU 95 A PRM-105 (JING XING). Usul pakai itu (Stud 90 A vs 95 A hanya beda teks, Base/Stud ke Process). Atau material baru Stud 90 A?
8. **Spray Outsole SPYDER FG.** Seperti Batch 2 no. 8: jadi sub-baris OUTSOLE dengan material SPRAY OUTSOLE (INDOKU), bukan baris utama. Setuju?
9. **Outsole CORE FG (PRM-112, TOPRO).** Excel: TPU Injection, Base/Stud/Logo 98 Shore D. Sistem (Batch 1): OUTSOLE TPU INJECTION HARDNESS 98 D PRM-112 (WINFAITH). Pakai itu dengan supplier TOPRO dari Excel (link baru), Process BASE / STUD / LOGO? Setuju?
10. **Outsole SPYDER FG JR (PRM-091 JR).** Excel: Base dan Stud TPU 90-92 Short A. Sistem: OUTSOLE TPU INJECTION HARDNESS 98 A PRM-091 JR (WINFAITH). Usul pakai itu, Process BASE / STUD. Atau material baru 90-92 A?
11. **Midsole PRM-106 / PRM-109 tampak tertukar.** SPYDER IN Excel: Phylon 60±2, tapi sistem punya PRM-106 = 50-55 dan PRM-109 = 60±2. ALPHA IN Excel: 50-55, DWI MITRA. Usul ikut Excel dan nama sistem: SPYDER IN pakai INJECTION PHYLON HARDNESS 60±2 ASKER C PRM-106 (baru), ALPHA IN pakai INJECTION PHYLON HARDNESS 50-55 ASKER C PRM-109 (baru), supplier DWI MITRA MANDIRI. Atau pakai material sistem apa adanya? Mohon cek mana yang benar.
12. **Outsole rubber IN (PRM-106, PRM-099, PRM-109, PRM-099 JR).** Rubber cup sole 60 Shore A: PRM-099 JR sudah ada (Batch 1); PRM-106, PRM-099, PRM-109 baru. Base / Center Mid / Logo / Base Side Wall tidak jadi sub-baris, warnanya ke baris outsole, namanya ke Process. Setuju?
13. **Outsole ALPHA FG (PRM-110, WINFAITH).** Excel: Base Front 95 A, Base Heel 64 D, Stud 90 A. Usul material baru OUTSOLE TPU INJECTION BASE 95 A / 64 D STUD 90 A PRM-110, bagian ke Process. Setuju?
14. **Decoration Negative Film (MGE).** Bukan Printing. Usul material baru NEGATIVE FILM (Process), atau ikut PRINTING SCREEN seperti decoration lain?
15. **Hulex Nappa Grip Effect, Single Mesh JZ 9036, Poly Flat Tubular BYL C028 (115 CM).** Tidak ada di sistem (JZ 9036 dan C028 hanya mirip). Usul material baru seperti tabel. Setuju?
16. **Ukuran CORE IN / ALPHA IN** 37-46 sesuai Excel. Setuju?
17. **Nama komponen.** Perlu M3 terbaru. Alias Batch 2 dipakai ulang; "VAMP LINNING" dianggap VAMP LINING, "SPRAY OUTSOLE" jadi sub OUTSOLE.
18. **Penulisan warna.** Metalic jadi Metallic, Shinny jadi Shiny, kosong ditulis NONE seperti Batch 2. Setuju?
