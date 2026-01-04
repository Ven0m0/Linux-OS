import re
import sys
from pathlib import Path

WORD_PATTERN = re.compile(r"[a-zA-Z0-9]+")
VALID_WORD_PATTERN = re.compile(r"^[a-zA-Z0-9_.,!?@#$%^&*()-=+ ]+$")


def detect_encoding(data: bytes) -> str:
    try:
        import chardet
        result = chardet.detect(data)
        return result["encoding"] or "utf-8"
    except ImportError:
        return "utf-8"


def process_file(filepath: str) -> set[str]:
    raw_data = Path(filepath).read_bytes()
    encoding = detect_encoding(raw_data)
    text = raw_data.decode(encoding, errors="ignore")
    return set(WORD_PATTERN.findall(text))


def main() -> None:
    if len(sys.argv) < 4:
        print("Usage: combine.py <file1> <file2> <output>", file=sys.stderr)
        sys.exit(1)

    filepath1, filepath2, outputfile = sys.argv[1], sys.argv[2], sys.argv[3]

    words1 = process_file(filepath1)
    words2 = process_file(filepath2)
    combined = sorted(words1 | words2)

    valid_words = [w for w in combined if w and VALID_WORD_PATTERN.match(w)]

    Path(outputfile).write_text("\n".join(valid_words) + "\n", encoding="utf-8")
    print(f"✓ Wrote {len(valid_words)} unique words to {outputfile}")


if __name__ == "__main__":
    main()
