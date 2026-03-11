import concurrent.futures
import re
import sys

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
    if chardet is not None:
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

    # Process files in parallel to utilize multiple cores and bypass GIL
    with concurrent.futures.ProcessPoolExecutor() as executor:
        f1 = executor.submit(process_file, filepath1)
        f2 = executor.submit(process_file, filepath2)
        words1 = f1.result()
        words2 = f2.result()

    # Optimization: In-place update of the larger set to avoid creating a third set
    if len(words1) >= len(words2):
        words1.update(words2)
        combined = sorted(words1)
    else:
        words2.update(words1)
        combined = sorted(words2)

    valid_words = combined

    with open(outputfile, "w", encoding="utf-8") as f:
        if valid_words:
            f.writelines(word + "\n" for word in valid_words)
        else:
            f.write("\n")
    print(f"✓ Wrote {len(valid_words)} unique words to {outputfile}")


if __name__ == "__main__":
    main()
