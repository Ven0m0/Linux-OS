import os
import hashlib
import argparse
from multiprocessing import Pool, cpu_count


def hash_file(file_path):
    try:
        print(f"Checking {file_path}")
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(65536), b""):
                sha256_hash.update(byte_block)
        return file_path, sha256_hash.hexdigest()
    except Exception as e:
        print(f"Error hashing {file_path}: {e}")
        return None, None


def find_duplicate_photos(starting_path, output_file_path):
    hash_dict = {}
    pool = Pool(processes=cpu_count())

    # Step 1: Group files by size
    size_map = {}
    for dirpath, _, filenames in os.walk(starting_path):
        for filename in filenames:
            if filename.lower().endswith((".jpg", ".jpeg", ".png", ".gif")):
                file_path = os.path.join(dirpath, filename)
                try:
                    file_size = os.path.getsize(file_path)
                    if file_size in size_map:
                        size_map[file_size].append(file_path)
                    else:
                        size_map[file_size] = [file_path]
                except OSError as e:
                    print(f"Error accessing {file_path}: {e}")

    # Step 2: Filter for files that have the same size
    file_paths_to_hash = []
    for size, paths in size_map.items():
        if len(paths) > 1:
            file_paths_to_hash.extend(paths)

    results = pool.map(hash_file, file_paths_to_hash)
    pool.close()
    pool.join()

    for file_path, file_hash in results:
        if file_hash is not None:
            if file_hash in hash_dict:
                hash_dict[file_hash].append(file_path)
            else:
                hash_dict[file_hash] = [file_path]

    with open(output_file_path, "w") as f:
        for key, value in hash_dict.items():
            if len(value) > 1:
                f.write(f"Duplicate Photos (Hash: {key}):\n")
                f.write(f"{value[0]}\n")  # Save only the first path
                f.write("\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Find duplicate photos in a directory."
    )
    parser.add_argument("directory", help="The directory to scan for photos.")
    parser.add_argument("output", help="The file to write duplicate findings to.")
    args = parser.parse_args()

    find_duplicate_photos(args.directory, args.output)
