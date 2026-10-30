import pickle, re, collections, sys
names, tok, ex = pickle.load(open('tok.pkl', 'rb'))
N = [n for c, n in names]

def W(*toks):
    return [r'(?<![A-Z0-9])' + re.escape(t) + r'(?![A-Z])' for t in toks]

# (bentuk baku, [(label, regex list)], catatan)
A = [
('HEATSEAL', [('HTSL', W('HTSL')), ('HEATSL', W('HEATSL')), ('HEATSEL', W('HEATSEL')), ('HT SEAL / HEAT SEAL', W('HT SEAL', 'HEAT SEAL')), ('HTSEAL', W('HTSEAL')), ('HS (di depan SZ/LBL)', [r'(?<![A-Z])HS ?SZ', r'(?<![A-Z])HS LBL'])], ''),
('SIZE LABEL', [('SZ LBL', W('SZ LBL')), ('SZLBL', W('SZLBL')), ('SZ LB', W('SZ LB')), ('SZLB', W('SZLB')), ('SZ LABEL / SZLABEL', W('SZ LABEL', 'SZLABEL')), ('SZ LBEL / SZ LZBEL', W('SZ LBEL', 'SZ LZBEL')), ('SIZELABEL / SIZELBEL', W('SIZELABEL', 'SIZELBEL')), ('SZL', W('SZL')), ('SLBL / SL / S L / S LABEL', [r'HEATSEAL S ?L(BL)? ', r'(?<![A-Z])S LABEL'])], ''),
('LABEL', [('LBL', W('LBL')), ('LB', W('LB')), ('LBEL', W('LBEL')), ('LABL', W('LABL')), ('LZBEL', W('LZBEL'))], ''),
('WOVEN', [('WVN', W('WVN')), ('WV', W('WV')), ('WOVN', W('WOVN')), ('WOVEL (salah ketik)', W('WOVEL'))], ''),
('NON WOVEN', [('NWV / NWN / NWVN / NW', W('NWV', 'NWN', 'NWVN', 'NW')), ('N WVN / NN WVN / NNWVN / N WV / N W', W('N WVN', 'NN WVN', 'NNWVN', 'N WV', 'N W')), ('NONWV / NONWOVEN / NON WVN', W('NONWV', 'NONWOVEN', 'NON WVN'))], 'BACKNWN, BCKNWN, BACKNWV jadi BACK NON WOVEN'),
('BACK', [('BCK', W('BCK')), ('BK', W('BK'))], 'BCKNG jadi BACKING'),
('MICROFIBER', [('MICRO F / MCRO F', W('MICRO F', 'MCRO F')), ('MICROF / MICRFB / MICROFBR / MCROFBR', W('MICROF', 'MICRFB', 'MICROFBR', 'MCROFBR')), ('MCRFB / MCRFBR / MCFB / MCFBR / MCRF', W('MCRFB', 'MCRFBR', 'MCFB', 'MCFBR', 'MCRF')), ('MC FB / MC FIBER', W('MC FB', 'MC FIBER'))], ''),
('KNITWEAR', [('KNWEAR / KNITWR / KNEATWEAR', W('KNWEAR', 'KNITWR', 'KNEATWEAR'))], ''),
('STICKER', [('STK', W('STK')), ('STC / STCKR / STIKER', W('STC', 'STCKR', 'STIKER')), ('ST (di depan C/B, IB, INBOX, PRICE, BCD)', [r'(?<![A-Z])ST ?(C/B|IB|INBOX|PRICE|BCD)'])], 'S.STK, SNGLE STC, SNGLE STIKER jadi SINGLE STICKER'),
('INNER BOX', [('INBOX', W('INBOX')), ('INBX', W('INBX')), ('IB', W('IB')), ('IN BOX', W('IN BOX')), ('INNERBOX', W('INNERBOX'))], 'STINBOX jadi STICKER INNER BOX'),
('BARCODE', [('BCD', W('BCD')), ('BARCD / BARCOD', W('BARCD', 'BARCOD')), ('BRCD', W('BRCD'))], 'STKBARCD / STBCD jadi STICKER BARCODE'),
('HANGTAG', [('HANGTG / HNGTG', W('HANGTG', 'HNGTG')), ('HTAG', W('HTAG')), ('HANG TAG / HANG (di depan BC/BCD/BARCODE)', [r'(?<![A-Z])HANG (TAG|BC|BCD|BARCODE)'])], ''),
('EXISTING', [('EXISTNG / EXSTNG / EXIST', W('EXISTNG', 'EXSTNG', 'EXIST'))], ''),
('JOGGER', [('JGR', W('JGR')), ('JGGR', W('JGGR')), ('JOGER', [r'JOGER']), ('JG', W('JG'))], 'JGRPRM / JGGRPRM jadi JOGGER PREMIUM'),
('PREMIUM', [('PRM (tanpa angka sesudahnya)', [r'(?<![A-Z])PRM(?![A-Z]|-?\d)'])], 'PRM-042, PRM074 tetap kode part'),
('ACCELERATOR', [('ACCLTR / ACLTR / ACCLRTR', W('ACCLTR', 'ACLTR', 'ACCLRTR')), ('ACCELERATO / ACCELRTR / ACCELERTR', W('ACCELERATO', 'ACCELRTR', 'ACCELERTR'))], ''),
('LIGHT SPEED', [('LIGHTSPEED / LIGHTSPED', W('LIGHTSPEED', 'LIGHTSPED')), ('LGT SPEED / LGT SPD / LGTSPD / LGHT SPD', W('LGT SPEED', 'LGT SPD', 'LGTSPD', 'LGHT SPD')), ('LT.SPD / LTSPD', [r'LT\.?SPD']), ('LS (bukan kode seperti LS-221)', [r'(?<![A-Z])LS(?![A-Z]|-\d| \d{3})'])], 'LSREBORN jadi LIGHT SPEED REBORN'),
('ILLUZION', [('ILUZION / ILZION / ILZ', W('ILUZION', 'ILZION', 'ILZ'))], ''),
('ELITE', [('ELIT / ELT', W('ELIT', 'ELT'))], 'ELITFG, ELITEFG, ELITIN dipisah jadi ELITE FG / ELITE IN'),
('REBORN', [('REBRN', W('REBRN'))], ''),
('REACTO BLITZ', [('REACTOBLITZ / BLTZ / REACTOBLTZ', W('REACTOBLITZ', 'BLTZ', 'REACTOBLTZ'))], ''),
('METASALA', [('MTSL / MTSLA / MTASALA', W('MTSL', 'MTSLA', 'MTASALA'))], ''),
('BARRICADA', [('BRRCDA / BARICADA', W('BRRCDA', 'BARICADA'))], ''),
('HYPERCHAOS', [('HYPRCHAOS', W('HYPRCHAOS'))], ''),
('GALACTICA', [('GALACTCA', W('GALACTCA'))], ''),
('SWERVO', [('SWRVO / SWRV', W('SWRVO', 'SWRV'))], ''),
('VELOCITY', [('VELCTY / VLCTY', W('VELCTY', 'VLCTY'))], ''),
('SUPREME', [('SPRM', W('SPRM'))], ''),
('UNIVERSAL', [('UNIV / UNV / UNIVRS', W('UNIV', 'UNV', 'UNIVRS'))], ''),
('SUBLIMASI', [('SBLMS / SBLM / SBMS / SBM', W('SBLMS', 'SBLM', 'SBMS', 'SBM')), ('SBLMASI / SBLMSI / SUBLM / SUBLMASI', W('SBLMASI', 'SBLMSI', 'SUBLM', 'SUBLMASI'))], ''),
('MOTIF', [('MTF', W('MTF'))], ''),
('BLOCK', [('BLOK', W('BLOK'))], ''),
('QUARTER', [('QRTR / QTR', W('QRTR', 'QTR'))], ''),
('TONGUE', [('TNGU / TG', W('TNGU', 'TG'))], ''),
('COLLAR', [('COLAR', W('COLAR'))], ''),
('UPPER', [('UPPR', W('UPPR'))], ''),
('COATING', [('COAT / COT', W('COAT', 'COT')), ('COTFA / COATFA (jadi COATING FA...)', [r'CO(A)?TFA'])], ''),
('MICRON', [('MC sesudah angka (FA7300/50MC)', [r'\d ?MC(?![A-Z])'])], ''),
('GRAMASI', [('GRMS / GRMASI / GRAMSI', W('GRMS', 'GRMASI', 'GRAMSI'))], ''),
('MERRY MESH', [('MERRYMESH / MERYMESH', W('MERRYMESH', 'MERYMESH')), ('MMESH / MMES / M.MES', W('MMESH', 'MMES', 'M.MES'))], ''),
('ASKER C', [('ASKC / ASK C', W('ASKC', 'ASK C'))], ''),
('HARDNESS', [('HARDNES', W('HARDNES')), ('HD di depan angka (HD 40-45)', [r'(?<![A-Z])HD ?\d'])], ''),
('PHYLON', [('PHYLN / PHY', W('PHYLN', 'PHY'))], ''),
('INJECTION', [('INJ / INJC / INJT / INJEC / INJECT', W('INJ', 'INJC', 'INJT', 'INJEC', 'INJECT'))], 'INJPHYLN jadi INJECTION PHYLON, TPUINJ jadi TPU INJECTION'),
('OUTSOLE', [('O/S / OS', [r'(?<![A-Z])O/S', r'(?<![A-Z])OS(?![A-Z])'])], 'OSTPU jadi OUTSOLE TPU'),
('INSOLE', [('INSL / INS', W('INSL', 'INS'))], ''),
('GENZA', [('GNZA / GNZ', W('GNZA', 'GNZ'))], ''),
('POLYPAG', [('POLIPAG / POLYPG / POLYP', W('POLIPAG', 'POLYPG', 'POLYP'))], ''),
('CANVAS', [('CVS', W('CVS'))], 'PCVS / PCV / PL CVS jadi POLY CANVAS'),
('PU SYNTHETIC', [('PUSYNTHETIC / PUSYNTH / PU SYNTH / SYNTHETC / SYNTHTIC', W('PUSYNTHETIC', 'PUSYNTH', 'PU SYNTH', 'SYNTHETC', 'SYNTHTIC'))], 'PUSPECS jadi PU SPECS'),
('KNIT', [('KNT / KNITR', W('KNT', 'KNITR'))], ''),
('LOGO', [('LG', [r'(?<![A-Z])LG(?![A-Z])'])], 'LGT tetap LIGHT'),
('WOMEN', [('WMN / WMNS', W('WMN', 'WMNS'))], ''),
('PACK', [('PCK', W('PCK'))], ''),
('CRUSH', [('CRSH', W('CRSH'))], ''),
('PERFORATED', [('PERF', W('PERF'))], ''),
('LEATHER', [('LEA', W('LEA'))], ''),
('WEBBING TAPE', [('WEBBINGTAPE / WEBING TP', W('WEBBINGTAPE', 'WEBING TP'))], ''),
('FLAT LACE', [('FLATLACE / POLYFLATLACE', W('FLATLACE', 'POLYFLATLACE'))], ''),
('SAMPLE', [('SMPL, CFM (confirmation sample)', W('SMPL', 'CFM'))], ''),
('SPANDEX', [('SPAND / SPAN', W('SPAND', 'SPAN'))], ''),
('TRICOT', [('TRCT', W('TRCT'))], ''),
('ILLUMINATE PACK', [('ILMNTE / ILUMINAT / ILP', W('ILMNTE', 'ILP') + [r'ILUMIN'])], ''),
('VISATERRY', [('VISATERY / VISSATERY / VSTERY', W('VISATERY', 'VISSATERY', 'VSTERY'))], ''),
]

U = [
('C/B, CB', [r'C/B', r'(?<![A-Z])CB(?![A-Z])'], 'CARTON BOX?'),
('S I, SI, ST I', [r'(?<![A-Z])S ?I(?![A-Z])', r'(?<![A-Z])ST I(?![A-Z])'], 'STICKER INNER BOX?'),
('Kode dalam kurung di akhir sticker: (WS), (WS-R), (W), (R), (S), (PR), (PORA), (PORB), (EP), (RE)', [r'\((WS-R|WS|W|R|S|PR|PORA|PORB|EP|RE|SI)(\)|$)'], 'kode ukuran atau vendor cetak?'),
('Komposisi T, S, K, KR, KRT, IP, IU, IPGC, PS, PLS, PLST, SY, SYT, TX, KL, LT, EV, P (contoh 60%T,40%S/65%IP,35%K)', [r'\d%(T|S|K|KR|KRT|IP|IU|IPGC|PS|PLS|PLST|SY|SYT|TX|KL|LT|EV|P)(?![A-Z])'], 'T = textile, S/SY/SYT = synthetic, K/KR/KRT = karet, KL/LT = kulit; IP, IU, IPGC, PS belum tahu'),
('S sesudah tanda + (FA7300/50MC+S)', [r'\+ ?S(?![A-Z])'], 'SINGLE STICKER?'),
('W di akhir nama (JOGGER W, ALICE W)', [r'(?<![A-Z/])W$'], 'WOMEN?'),
('SW (bukan SW MESH / SW 776)', [r'(SZ ?LBL|SZLBL|SZ LB|C/B|HS LBL|HTSL SZ) SW '], 'SWERVO?'),
('HS bukan di depan SZ/LBL (HS CORDURA, HS ALPHA, HS 2WAY)', [r'(?<![A-Z])HS (?!SZ|LBL)'], '?'),
('HD NON WOVEN, HD NONWOVEN', [r'HD NON ?WOVEN'], 'HIGH DENSITY?'),
('MM di depan nama (MM TERRY, MM+OP, MM 100)', [r'(^|\+)MM(?=[ +])'], 'MERRY MESH?'),
('BLK (SUB.BLK, DIBLK, DUSTY BLK)', W('BLK', 'DIBLK'), 'BLOCK atau BLACK?'),
('CLR (QTR+CLR, 2 CLR)', W('CLR'), 'COLLAR atau COLOR?'),
('CL (TG+CL)', W('CL'), 'COLLAR?'),
('DC (DC SUBLIMASI, W/DC, DCSBMS)', [r'(?<![A-Z])DC'], '?'),
('DB (DB BEAUTY MESH)', W('DB'), '?'),
('MT, MTA (MT CRSH P)', [r'(?<![A-Z])MTA?(?= CR)'], 'META?'),
('MK (STEAM MK, 3LX MK, FGMK)', [r'MK(?![A-Z])'], '?'),
('GA, GAE (GA22, GA24, IN GAE)', [r'(?<![A-Z])GAE?(?![A-Z])'], '?'),
('E (IL3 E FG, ALPHA NERVE E IN)', [r'(?<![A-Z])E (FG|IN|PE)'], 'ELITE?'),
('FT, FS, FB, FF, SB, RK, CH, BTS di akhir nama', [r'(SZ|LBL|LB|C/B|HEATSEAL).*(?<![A-Z])(FT|FS|FB|FF|SB|RK|CH|BTS)$'], 'FT = futsal? lainnya?'),
('TNDR, TDR, BLT (SWERVO TNDR BLT)', W('TNDR', 'TDR', 'BLT'), 'THUNDER BOLT?'),
('CNDP, CNDPACK', [r'CNDP'], 'CANDY PACK?'),
('VB, VBOW, VCTRYBOW', W('VB', 'VBOW', 'VCTRYBOW'), 'VICTORY BOW?'),
('OL, OL2, OL3 (bagian insole)', [r'(?<![A-Z])OL\d?(?![A-Z])'], 'ORTHOLITE?'),
('KA, KI', W('KA', 'KI'), 'KANAN / KIRI?'),
('MFOAM, MFOM, MLTFM, MLTFOAM', W('MFOAM', 'MFOM', 'MLTFM', 'MLTFOAM'), 'MEMORY FOAM / MULTI FOAM?'),
('PROLTFM, PNEOLTFM', [r'P(RO|NEO)LTFM'], 'PRO / NEO ORTHOLITE FOAM?'),
('SLMOLD', W('SLMOLD'), 'SOCKLINER MOLD?'),
('VTERY, VTRY', W('VTERY', 'VTRY', 'VTERYN'), 'VISATERRY atau VICTORY?'),
('OP, DECOP, SPCRCS, SPHILLS, OCLFOMD, WCLFIT, PRINOSPRM, SPKIL, LGRUNING', W('OP','DECOP')+[r'SPCRCS|SPHILLS|OCLFOMD|WCLFIT|PRINOSPRM|SPKIL|LGRUNING'], '?'),
('BS (BS98A, BS+STUD, BS/LINE)', W('BS'), 'BASE SOLE?'),
('N MESH', [r'(?<![A-Z/])N MESH'], '?'),
('P di akhir (MESH P, EM P, CRSH P)', [r'(?<![A-Z])P$'], 'PACK?'),
('NP, NV, XR, RX, LX, XT, SV, EVR, MWP, TNT, QC, BPR, BEPE, AE, EF, LFGR, KLOK, GRD', W('NP', 'NV', 'XR', 'RX', 'LX', 'XT', 'SV', 'EVR', 'MWP', 'TNT', 'QC', 'BPR', 'BEPE', 'AE', 'EF', 'LFGR', 'KLOK', 'GRD'), 'nama atau seri model?'),
('ACL, ACLS, ACILS, ACLT, AALPHAFORM', [r'(?<![A-Z])AC(L|LS|ILS|LT|ILZION)(?![A-Z])', r'AALPHA'], 'ACC LS / ACC ILLUZION?'),
('TR (TR COUNTER, TR28)', W('TR'), 'TPR atau TRICOT?'),
('RAJUT, TB.RAJUT, TBRAJUT, TUBERAJUT', [r'RAJUT'], 'KNIT / TUBE KNIT? Diganti atau tetap?'),
]

def matcher(pats):
    return re.compile('|'.join(f'(?:{p})' for p in pats))

rowsA, rowsU = [], []
md = ['| Bentuk baku | Ditulis di ERP sebagai (jumlah nama) | Total nama | Contoh nama ERP | Setuju? |', '| --- | --- | --- | --- | --- |']
for baku, vs, note in A:
    parts, tot, exs = [], set(), []
    for lab, p in vs:
        rx = matcher(p)
        hit = [n for n in N if rx.search(n)]
        parts.append(f'{lab} ({len(hit)})'); tot |= set(hit); exs += hit[:1]
    cell = '; '.join(parts) + (f'. {note}' if note else '')
    e = exs[0] if exs else ''
    md.append(f'| {baku} | {cell} | {len(tot)} | `{e}` | |')
    rowsA.append([baku, cell, len(tot), e])
md += ['', '| No | Kata di ERP | Jumlah nama | Contoh nama ERP | Dugaan saya | Arti (isi Anda) |', '| --- | --- | --- | --- | --- | --- |']
for i, (t, p, g) in enumerate(U, 1):
    rx = matcher(p)
    hit = [n for n in N if rx.search(n)]
    e = '; '.join(f'`{x}`' for x in hit[:2])
    md.append(f'| N{i} | {t} | {len(hit)} | {e} | {g} | |')
    rowsU.append([f'N{i}', t, len(hit), ' ; '.join(hit[:3]), g])
open('baku.md', 'w', encoding='utf-8').write('\n'.join(md))
pickle.dump((rowsA, rowsU), open('baku.pkl', 'wb'))
print('\n'.join(md))
