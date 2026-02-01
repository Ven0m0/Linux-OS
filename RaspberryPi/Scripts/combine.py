import re
import sys
from pathlib import Path

try:
    import chardet
except ImportError:
    chardet = None

WORD_PATTERN = re.compile(r"[a-zA-Z0-9]+")


def detect_encoding(data: bytes) -> str:
    """
    Detects the encoding of the given byte data using chardet if available.
    Falls back to utf-8 if chardet is not installed or returns no encoding.
    """
    if chardet:
        result = chardet.detect(data)
        return result["encoding"] or "utf-8"
    return "utf-8"


def process_file(filepath: str) -> set[str]:
    with open(filepath, "rb") as f:
        raw_head = f.read(65536)
    encoding = detect_encoding(raw_head)

    words = set()
    with open(filepath, "r", encoding=encoding, errors="ignore") as f:
        for line in f:
            words.update(WORD_PATTERN.findall(line))
    return words


def main() -> None:
    if len(sys.argv) < 4:
        print("Usage: combine.py <file1> <file2> <output>", file=sys.stderr)
        sys.exit(1)

    filepath1, filepath2, outputfile = sys.argv[1], sys.argv[2], sys.argv[3]

    words1 = process_file(filepath1)
    words2 = process_file(filepath2)
    combined = sorted(words1 | words2)

    valid_words = combined

    Path(outputfile).write_text("\n".join(valid_words) + "\n", encoding="utf-8")
    print(f"✓ Wrote {len(valid_words)} unique words to {outputfile}")


if __name__ == "__main__":
    main()
