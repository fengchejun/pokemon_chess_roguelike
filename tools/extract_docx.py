"""Extract all text (paragraphs + tables, in document order) from a .docx file.

Usage:
    python tools/extract_docx.py <input.docx> [output.txt]

Requires python-docx (bundled with the Codex primary runtime).
"""
import sys
import os


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    src = sys.argv[1]
    dst = sys.argv[2] if len(sys.argv) > 2 else None

    sys.path.insert(0, os.environ.get("CODEX_PY_PACKAGES", ""))
    import docx  # noqa: E402
    from docx.document import Document as _Document  # noqa: E402
    from docx.table import Table  # noqa: E402
    from docx.text.paragraph import Paragraph  # noqa: E402
    from docx.oxml.ns import qn  # noqa: E402

    doc = docx.Document(src)
    lines: list[str] = []
    for child in doc.element.body.iterchildren():
        if child.tag == qn("w:p"):
            para = Paragraph(child, doc)
            text = para.text.strip()
            if not text:
                continue
            style = para.style.name if para.style is not None else ""
            if style and "Heading" in style:
                level = style.replace("Heading", "").strip() or "1"
                hashes = "#" * min(max(int(level), 1), 6) if level.isdigit() else "##"
                lines.append(f"{hashes} {text}")
            else:
                lines.append(text)
        elif child.tag == qn("w:tbl"):
            table = Table(child, doc)
            lines.append("")
            lines.append("[表格开始]")
            for row in table.rows:
                cells = [c.text.strip().replace("\n", " / ") for c in row.cells]
                lines.append(" | ".join(cells))
            lines.append("[表格结束]")
            lines.append("")

    out = "\n".join(lines)
    if dst:
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write(out)
        print(f"wrote {len(out)} chars to {dst}")
    else:
        print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
