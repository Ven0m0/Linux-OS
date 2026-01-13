import os
import hashlib
from multiprocessing import Pool, cpu_count

def hash_file(file_path):
    try:
        print(f"Checking {file_path}")
        with open(file_path, 'rb') as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()
        return file_path, file_hash
    except Exception as e:
        print(f"Error hashing {file_path}: {e}")
        return None, None

def find_duplicate_photos(starting_path):
    hash_dict = {}
    pool = Pool(processes=cpu_count())

    file_paths = []
    for dirpath, _, filenames in os.walk(starting_path):
        for filename in filenames:
            if filename.lower().endswith(('.jpg', '.jpeg', '.png', '.gif')):
                file_paths.append(os.path.join(dirpath, filename))

    results = pool.map(hash_file, file_paths)
    pool.close()
    pool.join()

    for file_path, file_hash in results:
        if file_hash is not None:
            if file_hash in hash_dict:
                hash_dict[file_hash].append(file_path)
            else:
                hash_dict[file_hash] = [file_path]

    output_file_path = "D:/duplicate_photos.txt"  # Absolute path to save the file
    with open(output_file_path, 'w') as f:
        for key, value in hash_dict.items():
            if len(value) > 1:
                f.write(f"Duplicate Photos (Hash: {key}):\n")
                f.write(f"{value[0]}\n")  # Save only the first path
                f.write("\n")

if __name__ == '__main__':
    starting_directory = "D:/Photos"
    find_duplicate_photos(starting_directory)
