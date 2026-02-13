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


def group_files_by_size(starting_path):
    """Groups files by size."""
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
                    continue
    return size_dict


def get_candidates_from_size_groups(size_dict):
    """Returns a flat list of files that share a size with at least one other file."""
    candidates = []
    for paths in size_dict.values():
        if len(paths) > 1:
            candidates.extend(paths)
    return candidates


def group_by_hash(file_list, hash_func):
    """Groups files by hash using the provided hash function."""
    hash_groups = {}
    if not file_list:
        return hash_groups

    with Pool(processes=cpu_count()) as pool:
        results = pool.map(hash_func, file_list)

    for file_path, file_hash in results:
        if file_hash is not None:
            if file_hash in hash_groups:
                hash_groups[file_hash].append(file_path)
            else:
                hash_groups[file_hash] = [file_path]
    return hash_groups


def get_candidates_from_hash_groups(hash_groups):
    """Returns a flat list of files that share a hash with at least one other file."""
    candidates = []
    for paths in hash_groups.values():
        if len(paths) > 1:
            candidates.extend(paths)
    return candidates


def find_duplicate_photos(starting_path, output_file_path):
    # Step 1: Group by size
    size_dict = group_files_by_size(starting_path)
    potential_duplicates = get_candidates_from_size_groups(size_dict)

    final_hash_dict = {}

    if potential_duplicates:
        # Step 2: Partial hashing
        partial_hash_groups = group_by_hash(potential_duplicates, hash_file_partial)
        full_scan_candidates = get_candidates_from_hash_groups(partial_hash_groups)

        # Step 3: Full hashing
        if full_scan_candidates:
            final_hash_dict = group_by_hash(full_scan_candidates, hash_file)

    # Output results
    with open(output_file_path, "w") as f:
        for key, value in final_hash_dict.items():
            if len(value) > 1:
                f.write(f"Duplicate Photos (Hash: {key}):\n")
                f.write(f"{value[0]}\n")
                f.write("\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Find duplicate photos.")
    parser.add_argument("directory", help="Directory to scan")
    parser.add_argument("output", help="Output file for duplicates")
    args = parser.parse_args()

    find_duplicate_photos(args.directory, args.output)
