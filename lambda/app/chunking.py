"""Step 2 of ingestion, CHUNK: cut sections into pieces small enough to search.

A whole document is too big to send to the model and too broad to match a
specific question. A single sentence is too small to answer anything.
Chunks of about 700 characters sit in between.
"""

from langchain_text_splitters import RecursiveCharacterTextSplitter

from app import config

# The splitter tries to cut at paragraph breaks first, then line breaks, then
# sentences, and only cuts in the middle of a word as a last resort.
# The overlap repeats a little text between neighbouring chunks, so a sentence
# cut in two still appears whole in one of them.
splitter = RecursiveCharacterTextSplitter(
    chunk_size=config.CHUNK_SIZE,
    chunk_overlap=config.CHUNK_OVERLAP,
)


def chunk_sections(sections):
    """Turn a list of (section, text) pairs into a list of chunks.

    We split one section at a time, so a chunk never mixes two topics and its
    section name is always accurate.
    """
    chunks = []

    for section, text in sections:
        for piece in splitter.split_text(text):
            chunks.append({"section": section, "content": piece})

    return chunks
