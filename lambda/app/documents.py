"""Step 1 of ingestion, LOAD: read a policy file and pull out its text.

Every reader returns the same thing: a list of (section, text) pairs.
The section name is what we show as the source under an answer.
"""

import csv
import re

from docx import Document
from pypdf import PdfReader


def read_md(path):
    """Markdown: a section starts at any heading, from "# Purpose" to "### Carryover".

    Two things here are easy to get wrong, and both lose text silently rather than raising:

      * Splitting only on "## " drops a document that uses other heading levels. The
        glossary has a single "# Glossary" and nothing else, so a "## " split returns
        nothing at all and the whole document disappears from the index.
      * Taking everything AFTER the first heading drops whatever came before it. In these
        documents that is the provenance block, and often the opening paragraph that states
        the policy.

    Nothing is discarded here. Text before the first heading becomes its own section.
    """
    text = path.read_text(encoding="utf-8")

    sections = []
    heading = "Introduction"
    body = []

    for line in text.splitlines():
        match = re.match(r"^(#{1,3})\s+(.*)$", line)
        if match:
            if body and "\n".join(body).strip():
                sections.append((heading, "\n".join(body).strip()))
            heading = match.group(2).strip()
            body = []
        else:
            body.append(line)

    if body and "\n".join(body).strip():
        sections.append((heading, "\n".join(body).strip()))

    return sections


def read_docx(path):
    """Word: headings are marked with a "Heading" style, so we know where sections start."""
    sections = []

    for paragraph in Document(str(path)).paragraphs:
        if paragraph.style.name.startswith("Heading"):
            # A heading starts a new, empty section
            sections.append((paragraph.text, ""))
        elif sections and paragraph.text.strip():
            # A normal paragraph is added to the body of the latest section
            heading, body = sections[-1]
            sections[-1] = (heading, body + paragraph.text + "\n")

    return sections


def read_pdf(path):
    """PDF: a PDF has no reliable headings, so each page becomes one section."""
    pages = PdfReader(path).pages
    return [(f"Page {number}", page.extract_text()) for number, page in enumerate(pages, start=1)]


def read_txt(path):
    """Plain text: no structure at all, so the whole file is one section."""
    return [("Full text", path.read_text(encoding="utf-8"))]


def read_csv(path):
    """Spreadsheet: one section per ROW, not one section for the whole table.

    Two things go wrong with the obvious approach.

    A raw row like "2026-06-19,Juneteenth" means nothing once a chunk boundary separates it
    from the header, so the column names are repeated on every line:
    "date: 2026-06-19, holiday: Juneteenth".

    And ten rows in one chunk embed as "a list of dates" - no single row is prominent enough
    to match a question about it, so "Is Juneteenth a holiday?" retrieves nothing from the
    calendar at all. One row per section makes each row its own chunk, and the row that
    answers the question is the one that matches.

    The cost: "list every holiday" now needs several chunks rather than one. That is the
    right trade for a lookup table. A table people summarise rather than look up would want
    the opposite.
    """
    with open(path, encoding="utf-8") as handle:
        rows = list(csv.reader(handle))

    # The generator writes a provenance comment as the first row; the real header follows.
    if rows and rows[0] and rows[0][0].startswith("#"):
        rows = rows[1:]

    if not rows:
        return []

    header, data = rows[0], rows[1:]
    sections = []

    for row in data:
        if not any(cell.strip() for cell in row):
            continue

        line = ", ".join(f"{column}: {value}" for column, value in zip(header, row))

        # Name the section after the first column that is not a date, so the citation reads
        # "Juneteenth" rather than "Table".
        label = next(
            (value for column, value in zip(header, row)
             if value.strip() and column.lower() not in ("date", "day")),
            "Row",
        )
        sections.append((label, line))

    return sections


def read_html(path):
    """HTML: strip the tags, and treat h1/h2/h3 as section headings.

    Left in, the tags get embedded along with the words, and every document ends up sharing
    "div", "href" and "body" - which makes unrelated pages look faintly similar to each
    other and blunts the whole index.
    """
    markup = path.read_text(encoding="utf-8")

    markup = re.sub(r"(?is)<(script|style).*?</\1>", "", markup)   # drop code and CSS
    markup = re.sub(r"(?i)<h[1-3][^>]*>", "\n## ", markup)          # headings become markers
    markup = re.sub(r"(?i)</h[1-3]>", "\n", markup)
    markup = re.sub(r"(?i)<(br|/p|/li|/div)[^>]*>", "\n", markup)   # block ends become newlines
    text = re.sub(r"<[^>]+>", "", markup)                          # every remaining tag

    for entity, character in (("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")):
        text = text.replace(entity, character)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()

    sections = []
    for block in text.split("\n## ")[1:]:
        heading, _, body = block.partition("\n")
        if body.strip():
            sections.append((heading.strip(), body.strip()))

    return sections or [("Full text", text)]


# Which reader to use for each file extension
READERS = {
    ".md": read_md,
    ".docx": read_docx,
    ".pdf": read_pdf,
    ".txt": read_txt,
    ".csv": read_csv,
    ".html": read_html,
}


def read_document(path):
    """Pick the right reader from the file extension, and read the file."""
    reader = READERS.get(path.suffix)
    if reader is None:
        raise ValueError(
            f"no reader for {path.suffix!r} ({path.name}). "
            f"Known formats: {sorted(READERS)}"
        )
    return reader(path)
