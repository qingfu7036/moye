#!/usr/bin/env python3
"""Generate deterministic Phase 0 sample documents.

The generated files are intentionally small and contain known strings so the
reader/TTS spikes can assert against real document content instead of mocks.
Requirements: reportlab, python-docx, Pillow.
"""

from __future__ import annotations

import io
import os
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw
from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt
from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "spikes" / "phase0_lab" / "assets" / "fixtures"
OUT.mkdir(parents=True, exist_ok=True)

FONT_CANDIDATES = [
    Path(r"C:\Windows\Fonts\simhei.ttf"),
    Path(r"C:\Windows\Fonts\simsunb.ttf"),
    Path("/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc"),
]


def font_path() -> Path:
    for candidate in FONT_CANDIDATES:
        if candidate.exists():
            return candidate
    raise RuntimeError("No CJK font found; edit FONT_CANDIDATES")


def make_cover() -> Image.Image:
    image = Image.new("RGB", (900, 1200), "#243447")
    draw = ImageDraw.Draw(image)
    draw.rectangle((70, 70, 830, 1130), outline="#d4af72", width=8)
    draw.ellipse((330, 300, 570, 540), outline="#d4af72", width=6)
    draw.text((450, 760), "MOYE", fill="#f1eadc", anchor="mm")
    draw.text((450, 830), "Phase 0", fill="#d4af72", anchor="mm")
    return image


def make_pdf(path: Path) -> None:
    font = TTFont("FixtureCJK", str(font_path()))
    pdfmetrics.registerFont(font)
    c = canvas.Canvas(str(path), pagesize=A4, pageCompression=1)
    width, height = A4

    pages = [
        (
            "墨页阅读引擎验证样本",
            [
                "第一章 文本型 PDF 与坐标",
                "这是一段可以在 PDF 中被选择和定位的中文文字。",
                "The quick brown fox jumps over the lazy dog.",
                "阅读记忆需要同时保存页码、页面坐标和缩放比例。",
                "文字同步朗读使用句子级切分，并映射到页面矩形。",
            ],
        ),
        (
            "第二章 标注定位",
            [
                "高亮、下划线和批注都必须保存稳定的位置信息。",
                "如果只保存字符串，文档更新后就无法可靠恢复。",
                "本页包含可用于搜索的唯一短语：MOYE-PHASE0-ANCHOR。",
                "每个字符的边界矩形由 PDFium 提供。",
            ],
        ),
        (
            "第三章 扫描件识别",
            [
                "本样本另有 scanned.pdf 用于验证无文本层分支。",
                "文本型 PDF 与扫描型 PDF 必须在导入时区分。",
                "没有 OCR 时，页面渲染、缩放和书签仍然必须可用。",
                "结束页：MOYE-END-OF-TEXT.",
            ],
        ),
    ]

    for index, (heading, lines) in enumerate(pages, start=1):
        c.setFillColor(HexColor("#1f2937"))
        c.setFont("FixtureCJK", 22)
        c.drawString(64, height - 90, heading)
        c.setFillColor(HexColor("#334155"))
        c.setFont("FixtureCJK", 12)
        y = height - 150
        for line in lines:
            c.drawString(64, y, line)
            y -= 30
        c.setFillColor(HexColor("#64748b"))
        c.setFont("FixtureCJK", 9)
        c.drawString(64, 42, f"MOYE technical fixture - page {index} of 3")
        c.showPage()
    c.save()


def make_scanned_pdf(path: Path) -> None:
    image = Image.new("RGB", (1240, 1754), "white")
    draw = ImageDraw.Draw(image)
    draw.rectangle((80, 80, 1160, 1674), outline="#cbd5e1", width=3)
    draw.text((620, 260), "SCANNED PAGE - NO TEXT LAYER", fill="#111827", anchor="mm")
    draw.text((620, 340), "Use this file to verify the OCR-absent branch.", fill="#475569", anchor="mm")
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    buffer.seek(0)

    # A PDF containing only a full-page image and no text operators.
    c = canvas.Canvas(str(path), pagesize=A4, pageCompression=1)
    from reportlab.lib.utils import ImageReader

    c.drawImage(ImageReader(buffer), 0, 0, width=A4[0], height=A4[1])
    c.showPage()
    c.save()


def make_docx(path: Path) -> None:
    document = Document()
    document.core_properties.title = "墨页 DOCX 验证样本"
    document.core_properties.author = "MOYE Phase 0"

    heading = document.add_heading("墨页 DOCX 结构化阅读样本", level=0)
    heading.alignment = WD_ALIGN_PARAGRAPH.CENTER
    document.add_paragraph("本文件用于验证标题层级、段落、列表、表格、图片和超链接。")

    document.add_heading("一、标题层级", level=1)
    document.add_paragraph("一级标题下的普通段落。段落定位应保存 body/p[N] 与字符偏移。")
    document.add_heading("1.1 二级标题", level=2)
    document.add_paragraph("二级标题下的段落，包含 English words for mixed-script tests。")

    document.add_heading("二、列表与强调", level=1)
    document.add_paragraph("无序列表第一项", style="List Bullet")
    document.add_paragraph("无序列表第二项", style="List Bullet")
    document.add_paragraph("有序列表第一项", style="List Number")
    document.add_paragraph("有序列表第二项", style="List Number")
    paragraph = document.add_paragraph()
    paragraph.add_run("加粗文字").bold = True
    paragraph.add_run("，")
    paragraph.add_run("斜体文字").italic = True
    paragraph.add_run("，以及普通文字。")

    document.add_heading("三、表格", level=1)
    table = document.add_table(rows=3, cols=3)
    table.style = "Table Grid"
    headers = ["项目", "状态", "说明"]
    for cell, value in zip(table.rows[0].cells, headers):
        cell.text = value
    rows = [
        ("PDF", "通过", "PDFium 文字选择"),
        ("EPUB", "验证中", "CFI 与重排"),
        ("DOCX", "验证中", "段落路径定位"),
    ]
    for row, values in zip(table.rows[1:], rows):
        for cell, value in zip(row.cells, values):
            cell.text = value

    document.add_heading("四、图片", level=1)
    image_path = path.with_suffix(".png")
    make_cover().resize((300, 400)).save(image_path)
    document.add_picture(str(image_path), width=Inches(2.0))
    document.add_paragraph("图片下方说明：封面提取与附件路径测试。")
    image_path.unlink(missing_ok=True)

    document.add_heading("五、超链接", level=1)
    paragraph = document.add_paragraph("访问 ")
    part = document.part
    relationship_id = part.relate_to(
        "https://flutter.dev",
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
        is_external=True,
    )
    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("r:id"), relationship_id)
    run = OxmlElement("w:r")
    run_properties = OxmlElement("w:rPr")
    color = OxmlElement("w:color")
    color.set(qn("w:val"), "0563C1")
    underline = OxmlElement("w:u")
    underline.set(qn("w:val"), "single")
    run_properties.extend([color, underline])
    text = OxmlElement("w:t")
    text.text = "Flutter 官方网站"
    run.extend([run_properties, text])
    hyperlink.append(run)
    paragraph._p.append(hyperlink)
    paragraph.add_run(" 以验证链接保留。")

    document.add_heading("六、定位标记", level=1)
    document.add_paragraph("唯一段落标记：MOYE-DOCX-PARAGRAPH-ANCHOR。")
    document.add_paragraph("结束段落。")
    document.save(path)


def make_epub(path: Path) -> None:
    cover_path = path.with_suffix(".png")
    make_cover().resize((600, 800)).save(cover_path)
    cover_bytes = cover_path.read_bytes()
    cover_path.unlink(missing_ok=True)

    container = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""
    content_opf = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id" xml:lang="zh-CN">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="book-id">urn:uuid:moye-phase0-0001</dc:identifier>
    <dc:title>墨页 EPUB3 验证样本</dc:title>
    <dc:creator>MOYE Phase 0</dc:creator>
    <dc:language>zh-CN</dc:language>
    <meta property="dcterms:modified">2026-11-02T00:00:00Z</meta>
    <meta name="cover" content="cover-image"/>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="cover-image" href="images/cover.png" media-type="image/png" properties="cover-image"/>
    <item id="style" href="styles/book.css" media-type="text/css"/>
    <item id="ch1" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="text/chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>
"""
    nav = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="zh-CN">
<head><title>目录</title></head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>目录</h1>
    <ol>
      <li><a href="text/chapter1.xhtml">第一章 动态排版</a></li>
      <li><a href="text/chapter2.xhtml">第二章 定位与标注</a></li>
    </ol>
  </nav>
</body>
</html>
"""
    chapter1 = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN">
<head><title>第一章</title><link rel="stylesheet" type="text/css" href="../styles/book.css"/></head>
<body>
  <section id="chapter-1">
    <h1>第一章 动态排版</h1>
    <p id="p1">这是 EPUB3 验证样本的第一段。字号、行距和段落间距都应该可以动态调整。</p>
    <p id="p2">EPUB CFI 是跨阅读器定位章节内容的标准方式。本段包含唯一文本 MOYE-EPUB-CFI-ANCHOR。</p>
    <p id="p3">The quick brown fox jumps over the lazy dog. 这段中英混排用于检查句子切分与字体回退。</p>
    <p id="p4">选择本段文字后，应该能够创建高亮并保存章节、段落和字符偏移。</p>
  </section>
</body>
</html>
"""
    chapter2 = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" lang="zh-CN">
<head><title>第二章</title><link rel="stylesheet" type="text/css" href="../styles/book.css"/></head>
<body>
  <section id="chapter-2">
    <h1>第二章 定位与标注</h1>
    <p id="p1">阅读位置需要同时保存章节、CFI 与文字偏移，而不是一个简单的页码。</p>
    <p id="p2">标注原文必须带有上下文和稳定锚点，才能在字体重排后回到正确位置。</p>
    <p id="p3">验证句子：墨页将阅读、知识与声音连接在一起。</p>
    <p id="p4">结束段落 MOYE-EPUB-END。</p>
  </section>
</body>
</html>
"""
    css = """html { color: #1f2937; background: #fffdf8; }
body { margin: 6%; line-height: 1.75; font-family: serif; }
h1 { font-size: 1.6em; margin: 1.2em 0 0.8em; }
p { margin: 0 0 1em; text-indent: 2em; }
"""

    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        archive.writestr(
            "META-INF/container.xml", container, compress_type=zipfile.ZIP_DEFLATED
        )
        archive.writestr("OEBPS/content.opf", content_opf, compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr("OEBPS/nav.xhtml", nav, compress_type=zipfile.ZIP_DEFLATED)
        archive.writestr(
            "OEBPS/styles/book.css", css, compress_type=zipfile.ZIP_DEFLATED
        )
        archive.writestr(
            "OEBPS/text/chapter1.xhtml", chapter1, compress_type=zipfile.ZIP_DEFLATED
        )
        archive.writestr(
            "OEBPS/text/chapter2.xhtml", chapter2, compress_type=zipfile.ZIP_DEFLATED
        )
        archive.writestr(
            "OEBPS/images/cover.png", cover_bytes, compress_type=zipfile.ZIP_DEFLATED
        )


def main() -> None:
    make_pdf(OUT / "sample.pdf")
    make_scanned_pdf(OUT / "scanned.pdf")
    make_docx(OUT / "sample.docx")
    make_epub(OUT / "sample.epub")
    (OUT / "sample.txt").write_text(
        "墨页 TXT 验证样本\n\n第一段：字符偏移量定位。\n第二段：MOYE-TXT-ANCHOR。\n",
        encoding="utf-8",
    )
    (OUT / "sample.md").write_text(
        "# 墨页 Markdown 验证样本\n\n## 定位\n\n- YAML 不是必需\n- 标题与段落保留\n\n唯一标记：MOYE-MD-ANCHOR。\n",
        encoding="utf-8",
    )
    for path in sorted(OUT.iterdir()):
        print(f"{path.name:16} {path.stat().st_size:>9,} bytes")


if __name__ == "__main__":
    main()
