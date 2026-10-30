import openpyxl, collections, re, json, sys, pickle
R="D:/OJT_PM/Mock Up/"
def rows(p,sh=None,start=2):
    wb=openpyxl.load_workbook(p,data_only=True); ws=wb[sh] if sh else wb.active
    out=[]
    for i,r in enumerate(ws.iter_rows(min_row=start,values_only=True),start):
        if all(v in (None,'') for v in r): continue
        out.append((i,'' if r[0] is None else str(r[0]), '' if r[1] is None else str(r[1])))
    return out
M=R+"document/master color master thickness upd 29 oct 2026.xlsx"
col=rows(M,'master color'); th=rows(M,'master thickness'); mat=rows(R+"document/master material ADF.xlsx")
def ws_(s): return re.sub(r'\s+',' ',s).strip().upper()
def clean_color(p): return re.sub(r'\s*([/&+,-])\s*',r'\1',ws_(p)).strip()
def tight(p): return re.sub(r'[^a-z0-9]','',(p or '').lower())
def clean_th(p):
    t=ws_(p)
    if t in ('','.','-'): return ''
    t=re.sub('[\u201C\u201D\u201E\u201F\u2033\u3003\uFF02]','"',t)
    t=re.sub("['\u2019\u2018\u2032`\u00B4]{2}",'"',t)
    t=re.sub(r'(\d),(\d)',r'\1.\2',t)
    t=re.sub(r'(^|[^0-9.])\.(\d)',r'\g<1>0.\2',t)
    t=re.sub(r'(\d)\.(\d*[1-9])0+(?![0-9])',r'\1.\2',t)
    t=re.sub(r'(\d)\.0+(?![0-9])',r'\1',t)
    t=re.sub(r'(\d)\s*(INCHES|INCH|IN)(?=$|\s*X|\s*\(|\s*-|[^A-Z0-9\s])',r'\1"',t)
    t=re.sub(r'(\d)\s*(MM|CM|UM|ME)(?=$|[^A-Z]|X\d)',r'\1 \2',t)
    t=re.sub(r'(\d|MM|CM|UM|")\s*X\s*(?=\d)',r'\1 X ',t)
    t=re.sub(r'\s*-\s*','-',t)
    t=re.sub(r'\s*\(\s*',' (',t)
    t=re.sub(r'\s+\)',')',t)
    t=re.sub(r'(\d)\s+"',r'\1"',t)
    t=re.sub(r'(\d) (MM|CM|UM)-(\d+(?:\.\d+)?) \2(?=$|[^A-Z])',r'\1-\3 \2',t)
    return re.sub(r'\s+',' ',t).strip()
erp=[r for r in openpyxl.load_workbook(R+"appsmith/MATERIAL CODE.xlsx",data_only=True).active.iter_rows(min_row=4,values_only=True) if r[0]]
used=collections.Counter(); usedm=collections.Counter(); usedp=collections.Counter()
for r in erp:
    c=str(r[0]).strip().upper(); usedp[c[:4]]+=1; usedm[c[4:7]]+=1; used[c[7:10]]+=1
pickle.dump(dict(col=col,th=th,mat=mat,erp=erp,used=used,usedm=usedm,usedp=usedp),open(sys.argv[1],'wb'))
# ---- report
def odd_codes(data,n):
    return [(i,c,nm) for i,c,nm in data if len(c.strip())!=n or c!=c.strip() or c!=c.upper() or not re.fullmatch(r'[0-9A-Za-z]+',c.strip())]
print('COLOR odd codes',odd_codes(col,3))
print('COLOR blank names',[(i,c,n) for i,c,n in col if ws_(n)==''])
print('COLOR name==code or no letters',[(i,c,n) for i,c,n in col if ws_(n) and (ws_(n)==c.upper() or not re.search('[A-Z]',ws_(n)))][:40])
g=collections.defaultdict(list)
for i,c,n in col: g[tight(n)].append((c,n))
multi=[v for k,v in g.items() if k and len(v)>1]
exact=[v for v in multi if len({clean_color(n) for c,n in v})==1]
punct=[v for v in multi if len({clean_color(n) for c,n in v})>1]
print('COLOR groups multi codes',len(multi),'rows',sum(map(len,multi)),'exact',len(exact),'punct-only diff',len(punct))
print(' sizes',collections.Counter(len(v) for v in multi))
print(' punct samples',punct[:10])
print(' used in ERP list among multi',sum(1 for v in multi if sum(used[c.upper()] for c,n in v)>0))
# thickness
print('TH odd codes',odd_codes(th,3))
print('TH blank',[(i,c,n) for i,c,n in th if clean_th(n)==''])
print('TH blank-code usage', {k:usedm[k] for k in ['000','800','K00','C00']}, [(c,n) for i,c,n in th if c in ('800','K00','C00')])
g=collections.defaultdict(list)
for i,c,n in th:
    k=clean_th(n)
    if k: g[k].append((c,n))
tm=[(k,v) for k,v in g.items() if len(v)>1]
print('TH groups multi',len(tm),'rows',sum(len(v) for k,v in tm), 'sizes',collections.Counter(len(v) for k,v in tm))
print(' changed by cleaning',sum(1 for i,c,n in th if clean_th(n) and clean_th(n)!=ws_(n)))
for k,v in tm[:15]: print('  ',k,v,[usedm[c] for c,n in v])
print(' groups with >=2 codes used in ERP list',sum(1 for k,v in tm if sum(1 for c,n in v if usedm[c])>=2))
# material
print('MAT odd codes',odd_codes(mat,4))
print('MAT blank',len([1 for i,c,n in mat if ws_(n)=='']), [(i,c) for i,c,n in mat if ws_(n)==''][:40])
g=collections.defaultdict(list)
for i,c,n in mat:
    if ws_(n): g[tight(n)].append((c,n))
mm=[v for v in g.values() if len(v)>1]
print('MAT dup groups',len(mm),'rows',sum(map(len,mm)),'used groups',sum(1 for v in mm if sum(1 for c,n in v if usedp[c.upper()])>=2))
print(' len30 names', sum(1 for i,c,n in mat if len(n.strip())>=30))
print(' prefixes in ERP list not in ADF',[p for p in usedp if p not in {c.upper() for i,c,n in mat}])
