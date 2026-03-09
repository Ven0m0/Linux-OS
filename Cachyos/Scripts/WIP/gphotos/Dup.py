#!/usr/bin/env python3
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
  except OSError as e:
    print(f"Error partial hashing {file_path}: {e}")
    return file_path, None


def hash_file(file_path):
  try:
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
      for byte_block in iter(lambda: f.read(65536), b""):
        sha256_hash.update(byte_block)
    return file_path, sha256_hash.hexdigest()
  except Exception as e:
    print(f"Error hashing {file_path}: {e}")
    return file_path, None


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


def find_duplicate_photos(starting_path, output_file_path):
  # Step 1: Group by size
  size_dict = group_files_by_size(starting_path)

  # Collect all candidates for partial hashing (any file that shares a size with another)
  all_candidates = []
  for paths in size_dict.values():
    if len(paths) > 1:
      all_candidates.extend(paths)

  if not all_candidates:
    return

  final_duplicates = {}

  with Pool(processes=cpu_count()) as pool:
    # Step 2: Partial hashing
    # Map: path -> partial_hash
    partial_results = pool.map(hash_file_partial, all_candidates)
    partial_hashes = dict(partial_results)

    # Regroup by partial hash within size groups
    full_hash_candidates = []
    groups_to_check = []

    for paths in size_dict.values():
      if len(paths) < 2:
        continue

      # Group by partial hash
      ph_groups = {}
      for p in paths:
        ph = partial_hashes.get(p)
        if ph:
          if ph not in ph_groups:
            ph_groups[ph] = []
          ph_groups[ph].append(p)

      # Identify groups that still have multiple candidates
      for group in ph_groups.values():
        if len(group) > 1:
          groups_to_check.append(group)
          full_hash_candidates.extend(group)

    if full_hash_candidates:
      # Remove duplicates from full_hash_candidates list to avoid redundant hashing?
      # Actually `groups_to_check` might contain same file if I messed up? No.
      # But `full_hash_candidates` is flat list.
      # Files are unique in `all_candidates` (from `os.walk`).

      # Step 3: Full hashing
      full_results = pool.map(hash_file, full_hash_candidates)
      full_hashes = dict(full_results)

      # Step 4: Identify final duplicates
      for group in groups_to_check:
        fh_groups = {}
        for p in group:
          fh = full_hashes.get(p)
          if fh:
            if fh not in fh_groups:
              fh_groups[fh] = []
            fh_groups[fh].append(p)

        for fh, files in fh_groups.items():
          if len(files) > 1:
            final_duplicates[fh] = files

  # Output results
  with open(output_file_path, "w") as f:
    for key, value in final_duplicates.items():
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
