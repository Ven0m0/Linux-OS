import os
import hashlib
import argparse
from multiprocessing import Pool, cpu_count


def hash_file_partial(file_path):
    """
    Computes a partial hash of the file (first 64KB) to quickly filter non-duplicates.
    """
    try:
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            chunk = f.read(65536)
            if not chunk:
                return None, None
            sha256_hash.update(chunk)
        return file_path, sha256_hash.hexdigest()
    except Exception as e:
        print(f"Error partial hashing {file_path}: {e}")
        return None, None


def hash_file(file_path):
    try:
        # print(f"Checking {file_path}") # Removed print to reduce noise during benchmark
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            for byte_block in iter(lambda: f.read(65536), b""):
                sha256_hash.update(byte_block)
        return file_path, sha256_hash.hexdigest()
    except Exception as e:
        print(f"Error hashing {file_path}: {e}")
        return None, None


def find_duplicate_photos(starting_path, output_file_path):
    # Dictionary to group files by size: {size: [path1, path2, ...]}
    size_dict = {}

    for dirpath, _, filenames in os.walk(starting_path):
        for filename in filenames:
            if filename.lower().endswith((".jpg", ".jpeg", ".png", ".gif")):
                full_path = os.path.join(dirpath, filename)
                try:
                    file_size = os.path.getsize(full_path)
                    if file_size in size_dict:
                        size_dict[file_size].append(full_path)
                    else:
                        size_dict[file_size] = [full_path]
                except OSError:
                    # Skip files that cannot be accessed
                    continue

    # Identify files that have the same size (potential duplicates)
    potential_duplicates_by_size = []
    for paths in size_dict.values():
        if len(paths) > 1:
            potential_duplicates_by_size.extend(paths)

    hash_dict = {}

    if potential_duplicates_by_size:
        # Step 1: Partial hashing (Optimization)
        # Group by partial hash to filter out files that are definitely different
        # Use multiprocessing for hashing as it is CPU bound
        partial_hash_dict = {}
        with Pool(processes=cpu_count()) as pool:
            partial_results = pool.map(hash_file_partial, potential_duplicates_by_size)

        for file_path, p_hash in partial_results:
            if p_hash is not None:
                if p_hash in partial_hash_dict:
                    partial_hash_dict[p_hash].append(file_path)
                else:
                    partial_hash_dict[p_hash] = [file_path]

        # Step 2: Full hashing
        # Only process groups that still have potential duplicates after partial check
        full_scan_candidates = []
        for paths in partial_hash_dict.values():
            if len(paths) > 1:
                full_scan_candidates.extend(paths)

        if full_scan_candidates:
            with Pool(processes=cpu_count()) as pool:
                full_results = pool.map(hash_file, full_scan_candidates)

            for file_path, file_hash in full_results:
                if file_hash is not None:
                    if file_hash in hash_dict:
                        hash_dict[file_hash].append(file_path)
                    else:
                        hash_dict[file_hash] = [file_path]

    with open(output_file_path, "w") as f:
        for key, value in hash_dict.items():
            if len(value) > 1:
                f.write(f"Duplicate Photos (Hash: {key}):\n")
                # Preserving original behavior: write only the first path found
                f.write(f"{value[0]}\n")
                f.write("\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Find duplicate photos.")
    parser.add_argument("directory", help="Directory to scan")
    parser.add_argument("output", help="Output file for duplicates")
    args = parser.parse_args()

    find_duplicate_photos(args.directory, args.output)
