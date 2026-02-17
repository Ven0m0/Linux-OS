import os
import hashlib
import argparse
from multiprocessing import Pool, cpu_count


def hash_file_partial(file_path, chunk_size=65536):
    """
    Computes a partial hash of the file (first 64KB) to quickly filter non-duplicates.
    """
    try:
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            chunk = f.read(chunk_size)
            sha256_hash.update(chunk)
        return file_path, sha256_hash.hexdigest()
    except (IOError, OSError) as e:
        print(f"Error partial hashing {file_path}: {e}")
        return None, None


def hash_file(file_path):
    try:
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


def get_candidates(groups):
    """Returns a flat list of files that share a key with at least one other file."""
    candidates = []
    for paths in groups.values():
        if len(paths) > 1:
            candidates.extend(paths)
    return candidates


def group_by_hash(file_list, hash_func, pool=None):
    """Groups files by hash using the provided hash function."""
    hash_groups = {}
    if not file_list:
        return hash_groups

    if pool:
        results = pool.map(hash_func, file_list)
    else:
        with Pool(processes=cpu_count()) as p:
            results = p.map(hash_func, file_list)

    for file_path, file_hash in results:
        if file_hash is not None:
            if file_hash in hash_groups:
                hash_groups[file_hash].append(file_path)
            else:
                hash_groups[file_hash] = [file_path]
    return hash_groups


def find_duplicate_photos(starting_path, output_file_path):
    # Step 1: Group by size
    size_dict = group_files_by_size(starting_path)
    potential_duplicates = get_candidates(size_dict)

    final_hash_dict = {}

    if potential_duplicates:
        with Pool(processes=cpu_count()) as pool:
            # Step 2: Partial hashing
            partial_hash_groups = group_by_hash(potential_duplicates, hash_file_partial, pool=pool)
            full_scan_candidates = get_candidates(partial_hash_groups)

            # Step 3: Full hashing
            if full_scan_candidates:
                final_hash_dict = group_by_hash(full_scan_candidates, hash_file, pool=pool)

    # Output results
    with open(output_file_path, "w") as f:
        for key, value in final_hash_dict.items():
            if len(value) > 1:
                f.write(f"Duplicate Photos (Hash: {key}):\n")
                for file_path in value:
                    f.write(f"{file_path}\n")
                f.write("\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Find duplicate photos.")
    parser.add_argument("directory", help="Directory to scan")
    parser.add_argument("output", help="Output file for duplicates")
    args = parser.parse_args()

    find_duplicate_photos(args.directory, args.output)
