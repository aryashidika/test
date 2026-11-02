# Mesin pembuat dokumen Word manual task (python-docx).
# Isi tiap task ada di content_*.py; jalankan build.py untuk membuat ulang semua file.
import re
from docx import Document
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Pt, Cm, RGBColor

BLUE = RGBColor(0x1F, 0x3A, 0x5F)
GREY = RGBColor(0x59, 0x59, 0x59)
APP = 'Sistem Specsheet & CBD'


def _shade(cell, fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), fill)
    tcPr.append(shd)


def _borders(table, color='BFBFBF', style='single', size=4):
    tblPr = table._tbl.tblPr
    b = OxmlElement('w:tblBorders')
    for edge in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        e = OxmlElement(f'w:{edge}')
        e.set(qn('w:val'), style)
        e.set(qn('w:sz'), str(size))
        e.set(qn('w:space'), '0')
        e.set(qn('w:color'), color)
        b.append(e)
    tblPr.append(b)


def _widths(table, widths_cm):
    table.autofit = False
    for row in table.rows:
        for cell, w in zip(row.cells, widths_cm):
            cell.width = Cm(w)


def _cell_margin(table, cm=0.15):
    tblPr = table._tbl.tblPr
    m = OxmlElement('w:tblCellMar')
    for edge in ('top', 'bottom'):
        e = OxmlElement(f'w:{edge}')
        e.set(qn('w:w'), str(int(cm * 567)))
        e.set(qn('w:type'), 'dxa')
        m.append(e)
    tblPr.append(m)


def rich(par, text, size=None, color=None, italic=False):
    """**teks** = tebal (label di layar). Sisanya teks biasa."""
    for i, part in enumerate(re.split(r'\*\*(.+?)\*\*', text)):
        if not part:
            continue
        r = par.add_run(part)
        r.bold = (i % 2 == 1)
        r.italic = italic
        if size:
            r.font.size = Pt(size)
        if color:
            r.font.color.rgb = color
    return par


class Manual:
    def __init__(self, number, title, who, page, before, goal):
        self.doc = Document()
        self.fig = 0
        self.step = 0
        self.number, self.title = number, title
        self._setup()
        d = self.doc
        p = d.add_paragraph()
        r = p.add_run(f'MANUAL TASK {number}  |  {APP.upper()}')
        r.font.size = Pt(9)
        r.font.color.rgb = GREY
        r.bold = True
        h = d.add_heading(title, level=0)
        h.paragraph_format.space_after = Pt(6)
        t = d.add_table(rows=0, cols=2)
        _borders(t)
        _cell_margin(t)
        for k, v in (('Dikerjakan oleh', who), ('Halaman', page), ('Sebelum mulai', before)):
            row = t.add_row().cells
            _shade(row[0], 'E8EEF5')
            rich(row[0].paragraphs[0], k).runs[0].bold = True
            rich(row[1].paragraphs[0], v)
        _widths(t, [4.0, 12.5])
        d.add_paragraph()
        self.h('Tujuan')
        self.p(goal)

    def _setup(self):
        d = self.doc
        s = d.sections[0]
        s.page_width, s.page_height = Cm(21), Cm(29.7)
        s.left_margin = s.right_margin = Cm(2.2)
        s.top_margin, s.bottom_margin = Cm(2), Cm(2)
        st = d.styles['Normal']
        st.font.name = 'Calibri'
        st.element.rPr.rFonts.set(qn('w:eastAsia'), 'Calibri')
        st.font.size = Pt(11)
        st.paragraph_format.space_after = Pt(4)
        st.paragraph_format.line_spacing = 1.15
        for name, size in (('Title', 22), ('Heading 1', 14), ('Heading 2', 12)):
            hs = d.styles[name]
            hs.font.name = 'Calibri'
            hs.font.size = Pt(size)
            hs.font.color.rgb = BLUE
            hs.font.bold = True
        d.styles['Heading 1'].paragraph_format.space_before = Pt(14)
        d.styles['Heading 2'].paragraph_format.space_before = Pt(10)
        # footer: judul + nomor halaman
        fp = s.footer.paragraphs[0]
        fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = fp.add_run(f'{APP}  |  Manual Task {self.number}: {self.title}  |  Halaman ')
        r.font.size = Pt(8)
        r.font.color.rgb = GREY
        run = fp.add_run()
        run.font.size = Pt(8)
        run.font.color.rgb = GREY
        for tag, txt in (('begin', None), (None, 'PAGE'), ('end', None)):
            if tag:
                f = OxmlElement('w:fldChar')
                f.set(qn('w:fldCharType'), tag)
                run._r.append(f)
            else:
                it = OxmlElement('w:instrText')
                it.set(qn('xml:space'), 'preserve')
                it.text = txt
                run._r.append(it)

    # ---- blok isi ----
    def h(self, text, level=1):
        self.doc.add_heading(text, level=level)
        if level == 1:
            self.step = 0

    def p(self, text):
        return rich(self.doc.add_paragraph(), text)

    def steps(self, *items):
        """Langkah bernomor; nomor berlanjut sampai judul bab berikutnya."""
        for it in items:
            if isinstance(it, tuple) and it[0] == 'shot':
                self.shot(it[1])
                continue
            if isinstance(it, tuple) and it[0] == 'sub':
                for s in it[1:]:
                    par = self.doc.add_paragraph()
                    par.paragraph_format.left_indent = Cm(1.6)
                    par.paragraph_format.first_line_indent = Cm(-0.5)
                    rich(par, '•  ' + s)
                continue
            self.step += 1
            par = self.doc.add_paragraph()
            par.paragraph_format.left_indent = Cm(0.9)
            par.paragraph_format.first_line_indent = Cm(-0.9)
            par.paragraph_format.tab_stops.add_tab_stop(Cm(0.9))
            r = par.add_run(f'{self.step}.\t')
            r.bold = True
            r.font.color.rgb = BLUE
            rich(par, it)

    def bullets(self, *items):
        for it in items:
            par = self.doc.add_paragraph()
            par.paragraph_format.left_indent = Cm(0.9)
            par.paragraph_format.first_line_indent = Cm(-0.5)
            rich(par, '•  ' + it)

    def shot(self, caption):
        """Kotak tempat screenshot (diisi user nanti)."""
        self.fig += 1
        t = self.doc.add_table(rows=1, cols=1)
        t.alignment = WD_TABLE_ALIGNMENT.CENTER
        _borders(t, color='8EA9C8', style='dashed', size=8)
        c = t.rows[0].cells[0]
        _shade(c, 'F3F6FA')
        c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        tr = t.rows[0]._tr
        trPr = tr.get_or_add_trPr()
        hgt = OxmlElement('w:trHeight')
        hgt.set(qn('w:val'), str(int(5.5 * 567)))
        trPr.append(hgt)
        par = c.paragraphs[0]
        par.alignment = WD_ALIGN_PARAGRAPH.CENTER
        r = par.add_run('[ Tempel screenshot di sini ]')
        r.font.color.rgb = RGBColor(0x8E, 0xA9, 0xC8)
        r.font.size = Pt(10)
        _widths(t, [16.5])
        cap = self.doc.add_paragraph()
        cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        rich(cap, f'Gambar {self.fig}. {caption}', size=9, color=GREY, italic=True)

    def note(self, text, kind='Penting'):
        t = self.doc.add_table(rows=1, cols=1)
        _borders(t, color='E0B252' if kind == 'Penting' else '8EA9C8')
        c = t.rows[0].cells[0]
        _shade(c, 'FFF6E0' if kind == 'Penting' else 'EEF4FB')
        par = c.paragraphs[0]
        r = par.add_run(kind + ': ')
        r.bold = True
        rich(par, text)
        _widths(t, [16.5])
        self.doc.add_paragraph().paragraph_format.space_after = Pt(0)

    def table(self, header, rows, widths):
        t = self.doc.add_table(rows=1, cols=len(header))
        _borders(t)
        _cell_margin(t, 0.08)
        for c, hdr in zip(t.rows[0].cells, header):
            _shade(c, '1F3A5F')
            run = c.paragraphs[0].add_run(hdr)
            run.bold = True
            run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
            run.font.size = Pt(10)
        for row in rows:
            cells = t.add_row().cells
            for c, v in zip(cells, row):
                rich(c.paragraphs[0], v, size=10)
        _widths(t, widths)
        self.doc.add_paragraph().paragraph_format.space_after = Pt(0)

    def messages(self, rows):
        self.h('Jika muncul pesan ini')
        self.table(['Pesan di layar', 'Artinya', 'Yang perlu dilakukan'], rows, [5.8, 4.7, 6.0])

    def related(self, *items):
        self.h('Manual terkait')
        self.bullets(*items)

    def save(self, path):
        self.doc.core_properties.title = self.title
        self.doc.core_properties.author = APP
        self.doc.save(path)
