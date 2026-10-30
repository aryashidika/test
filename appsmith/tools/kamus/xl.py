import pickle, collections, re, sys, openpyxl
from openpyxl.styles import Font, PatternFill
sys.argv=[sys.argv[0],'x']; exec(open('an.py').read().split('# ---- report')[0].split("erp=[r")[0])  # reuse functions
_ct=clean_th
def clean_th(n): return _ct(re.sub(r'([A-Z])\.(\d)', lambda m: m.group(1)+'#'+m.group(2), ws_(n))).replace('#','.')
d=pickle.load(open('data.pkl','rb')); used=d['used']; usedm=d['usedm']; usedp=d['usedp']
wb=openpyxl.Workbook(); wb.remove(wb.active)
def sheet(name,head,rows):
    ws=wb.create_sheet(name); ws.append(head)
    for c in ws[1]: c.font=Font(bold=True,color='FFFFFF'); c.fill=PatternFill('solid',fgColor='305496')
    for r in rows: ws.append(r)
    ws.freeze_panes='A2'; ws.auto_filter.ref=ws.dimensions
    for i,h in enumerate(head,1): ws.column_dimensions[openpyxl.utils.get_column_letter(i)].width=max(12,min(45,len(h)+4))
# colour groups
g=collections.defaultdict(list)
for i,c,n in d['col']: g[tight(n)].append((i,c,n))
rows=[]; gid=0
for k,v in sorted(g.items(), key=lambda kv: clean_color(kv[1][0][2])):
    if not k or len(v)<2: continue
    gid+=1
    same=len({clean_color(n) for _,_,n in v})==1
    main=max(v,key=lambda x:(used[x[1].upper()],-x[0]))
    for i,c,n in v: rows.append([gid,clean_color(v[0][2]),c.upper(),n,'Sama persis' if same else 'Beda spasi/tanda baca',used[c.upper()],'Ya' if c==main[1] else '',i])
sheet('Warna banyak kode',['Kelompok','Warna (bersih)','Kode','Nama di master','Jenis','Dipakai di daftar ERP','Kode utama (kalau W4 = b)','Baris Excel'],rows)
# thickness groups
g=collections.defaultdict(list)
for i,c,n in d['th']:
    k=clean_th(n)
    if k: g[k].append((i,c,n))
rows=[]; gid=0; tgroups=[]
for k,v in sorted(g.items()):
    if len(v)<2: continue
    gid+=1
    main=max(v,key=lambda x:(usedm[x[1].upper()],-x[0]))
    tgroups.append((k,v,main))
    for i,c,n in v: rows.append([gid,k,c.upper(),n,usedm[c.upper()],'Ya' if c==main[1] else '',i])
sheet('Dimension banyak kode',['Kelompok','Dimension (bersih)','Kode','Nama di master','Dipakai di daftar ERP','Usulan kode utama','Baris Excel'],rows)
rows=[[c.upper(),n,clean_th(n),i] for i,c,n in d['th'] if clean_th(n) and clean_th(n)!=ws_(n)]
sheet('Dimension dibakukan',['Kode','Nama di master','Setelah dibakukan','Baris Excel'],rows)
g=collections.defaultdict(list)
for i,c,n in d['mat']:
    if ws_(n): g[tight(n)].append((i,c,n))
rows=[]; gid=0
for k,v in sorted(g.items(), key=lambda kv: kv[1][0][2]):
    if len(v)<2: continue
    gid+=1
    for i,c,n in v: rows.append([gid,c.strip().upper(),n,usedp[c.strip().upper()],len(n.strip())>=30 and 'Ya' or '',i])
sheet('Material nama dobel',['Kelompok','Prefix','Nama di ADF','Dipakai di daftar ERP','Nama terpotong (30 huruf)','Baris Excel'],rows)
import os; out=r"D:/OJT_PM/Mock Up/document/Kamus Kode"; os.makedirs(out,exist_ok=True)
wb.save(out+"/Review_Kamus_Kode.xlsx")
