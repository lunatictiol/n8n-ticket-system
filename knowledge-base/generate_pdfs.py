"""Reproducibly generate the knowledge-base PDFs from documents.py.

Usage:  python knowledge-base/generate_pdfs.py
Deps:   fpdf2   (pip install fpdf2)

Every PDF has numbered sections, headings, and a footer carrying the document
version and effective date. Output is deterministic: re-running overwrites the
same files with identical content.
"""

from pathlib import Path

from fpdf import FPDF
from fpdf.enums import XPos, YPos


def _cell(pdf, h, txt):
    """multi_cell that always returns the cursor to the left margin."""
    pdf.multi_cell(0, h, txt, new_x=XPos.LMARGIN, new_y=YPos.NEXT)

try:
    from documents import COMPANY, DOCUMENTS  # when run from knowledge-base/
except ImportError:  # when run from repo root
    from knowledge_base_documents import COMPANY, DOCUMENTS  # pragma: no cover

OUT_DIR = Path(__file__).parent / "pdfs"


class DocPDF(FPDF):
    def __init__(self, doc):
        super().__init__()
        self._doc = doc
        self.set_auto_page_break(auto=True, margin=20)

    def footer(self):
        self.set_y(-15)
        self.set_font("Helvetica", "I", 8)
        d = self._doc
        self.set_text_color(120, 120, 120)
        self.cell(
            0, 10,
            f"{COMPANY} - {d['name']}  |  v{d['version']}  |  "
            f"Effective {d['effective_date']}  |  Access: {d['access_level']}  |  Page {self.page_no()}",
            align="C",
        )


def render(doc) -> Path:
    pdf = DocPDF(doc)
    pdf.add_page()

    pdf.set_font("Helvetica", "B", 18)
    pdf.set_text_color(20, 40, 80)
    _cell(pdf, 10, f"{COMPANY}")
    pdf.set_font("Helvetica", "B", 15)
    pdf.set_text_color(0, 0, 0)
    _cell(pdf, 9, doc["name"])
    pdf.ln(4)

    for section in doc["sections"]:
        pdf.set_font("Helvetica", "B", 12)
        _cell(pdf, 7, section["heading"])
        pdf.set_font("Helvetica", "", 11)
        _cell(pdf, 6, section["body"])
        pdf.ln(3)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    path = OUT_DIR / f"{doc['doc_id']}.pdf"
    pdf.output(str(path))
    return path


def main():
    for doc in DOCUMENTS:
        path = render(doc)
        print(f"wrote {path}  ({doc['access_level']})")


if __name__ == "__main__":
    main()
