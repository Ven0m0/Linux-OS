import io
import re
import string
import sys
import chardet
import concurrent.futures
from tqdm import tqdm
from multiprocessing import Pool


def process_file(filepath):
    # Detect encoding and process in single pass (avoid double I/O)
    with open(filepath, "rb") as f:
        raw_data = f.read()
    encoding = chardet.detect(raw_data)["encoding"]

    words = set()
    # Process without tqdm per-line (batch progress instead)
    text = raw_data.decode(encoding, errors="ignore")
    for line in text.splitlines():
        # remove any punctuation from the file
        line = line.translate(str.maketrans("", "", string.punctuation))
        # split the contents into a list of words
        words_in_line = re.findall(r"[a-zA-Z0-9]+", line)
        words.update(words_in_line)
    return words


def main():
    if len(sys.argv) < 4:
        print("Please specify the input and output file paths")
        return

    # read the input file paths
    filepath1 = sys.argv[1]
    filepath2 = sys.argv[2]

    # read the output file path
    outputfile = sys.argv[3]

    with tqdm(total=2, desc="Processing...") as pbar:
        with Pool() as pool:
            # process the input files in parallel (use map for true parallelism)
            results = pool.map(process_file, [filepath1, filepath2])
        # combine the unique words from both files
        words = sorted(results[0].union(results[1]))
        pbar.update(2)
    # write the processed words to a new file (filter during write, not after)
    valid_pattern = re.compile(r"^[a-zA-Z0-9_.,!?@#$%^&*()-=+ ]*$")
    with open(outputfile, "w", encoding="utf-8") as file:
        for word in tqdm(words, desc="Writing to file"):
            # Only write valid words (combine write + validation in single pass)
            if word and valid_pattern.search(word):
                file.write(word + "\n")


if __name__ == "__main__":
    main()
