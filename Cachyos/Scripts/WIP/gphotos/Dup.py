import os
import hashlib
import argparse
from multiprocessing import Pool, cpu_count


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


def hash_file_partial(file_path):
    try:
        sha256_hash = hashlib.sha256()
        with open(file_path, "rb") as f:
            byte_block = f.read(65536)
            sha256_hash.update(byte_block)
        return file_path, sha256_hash.hexdigest()
    except Exception as e:
        print(f"Error partial hashing {file_path}: {e}")
        return None, None


def get_files_by_size(starting_path):
    size_dict = {}
    for dirpath, _, filenames in os.walk(starting_path):
        for filename in filenames:
            if filename.lower().endswith(('.jpg', '.jpeg', '.png', '.gif')):
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


def get_hash_groups(file_list, hash_func, pool):
    results = pool.map(hash_func, file_list)
    hash_dict = {}
    for file_path, file_hash in results:
        if file_hash is not None:
            if file_hash in hash_dict:
                hash_dict[file_hash].append(file_path)
            else:
                hash_dict[file_hash] = [file_path]
    return hash_dict


def find_duplicate_photos(starting_path, output_file_path):
    # Dictionary to group files by size: {size: [path1, path2, ...]}
    size_dict = get_files_by_size(starting_path)

    # Identify files that have the same size (potential duplicates)
    potential_duplicates = []
    for paths in size_dict.values():
        if len(paths) > 1:
            potential_duplicates.extend(paths)

    final_duplicates = {}

    # Only run heavy hashing on files that share a size with another file
    if potential_duplicates:
        # Use multiprocessing for hashing as it is CPU bound
        pool = Pool(processes=cpu_count())
        try:
            # Phase 1: Partial Hash (first 64KB) to filter candidates
            partial_hash_dict = get_hash_groups(potential_duplicates, hash_file_partial, pool)

            # Identify files that have same partial hash
            full_hash_candidates = []
            for paths in partial_hash_dict.values():
                if len(paths) > 1:
                    full_hash_candidates.extend(paths)

            # Phase 2: Full Hash on remaining candidates
            if full_hash_candidates:
                full_hash_dict = get_hash_groups(full_hash_candidates, hash_file, pool)
                final_duplicates = full_hash_dict
        finally:
            pool.close()
            pool.join()

    with open(output_file_path, 'w') as f:
        for key, value in final_duplicates.items():
            if len(value) > 1:
                f.write(f"Duplicate Photos (Hash: {key}):\n")
                # Preserving original behavior: write only the first path found
                f.write(f"{value[0]}\n")
                f.write("\n")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Find duplicate photos.")
    parser.add_argument("directory", help="Directory to scan")
    parser.add_argument("output", help="Output file for duplicates")
    args = parser.parse_args()

    find_duplicate_photos(args.directory, args.output)
