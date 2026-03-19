import os
import shutil
import argparse


# Function to calculate folder size recursively
def get_folder_size(folder):
    total_size = 0
    for dirpath, _, filenames in os.walk(folder):
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            try:
                total_size += os.path.getsize(filepath)
            except OSError:
                continue
    return total_size


# Function to create a new folder or return existing one
def create_new_folder(root_folder, folder_name):
    new_folder_path = os.path.join(root_folder, folder_name)
    if not os.path.exists(new_folder_path):
        os.makedirs(new_folder_path)
        print(f"Created new folder: {new_folder_path}")
    return new_folder_path


def get_latest_group_info(photos_folder):
    """Finds the highest numbered Group_N folder under photos_folder and its size."""
    max_group_num = 0
    latest_group_folder = None

    if os.path.exists(photos_folder):
        for entry in os.scandir(photos_folder):
            if entry.name.startswith("Group_") and entry.is_dir():
                try:
                    num = int(entry.name.split("_")[1])
                    if num > max_group_num:
                        max_group_num = num
                        latest_group_folder = entry.path
                except (ValueError, IndexError):
                    continue

    if max_group_num == 0 or latest_group_folder is None:
        return 1, None, 0

    return max_group_num, latest_group_folder, get_folder_size(latest_group_folder)


def move_file_to_group(file_path, group_folder):
    """Moves a file to a group folder and returns true if moved."""
    abs_file_path = os.path.abspath(file_path)
    abs_group_folder = os.path.abspath(group_folder)

    if os.path.commonpath([abs_file_path, abs_group_folder]) != abs_group_folder:
        try:
            shutil.move(file_path, group_folder)
            print(f"Moved photo '{file_path}' to '{group_folder}'")
            return True
        except Exception as e:
            print(f"Failed to move photo '{file_path}': {e}")
            return False
    return False


def ensure_space_in_group(
    photos_folder,
    file_size,
    target_folder_size,
    group_info,
    group_size_cache
):
    """Ensures there is space in the current group for the given file size."""
    num, folder, size = group_info

    while size + file_size > target_folder_size:
        num += 1
        folder = os.path.join(photos_folder, f"Group_{num}")
        if folder in group_size_cache:
            size = group_size_cache[folder]
        elif os.path.exists(folder):
            size = get_folder_size(folder)
            group_size_cache[folder] = size
        else:
            create_new_folder(photos_folder, f"Group_{num}")
            size = 0
            group_size_cache[folder] = size

    return num, folder, size


def process_file(
    file_path,
    photos_folder,
    target_folder_size,
    group_info,
    group_size_cache
):
    """Processes a single file, ensuring it fits into a group folder."""
    try:
        file_size = os.path.getsize(file_path)
    except OSError:
        return group_info

    # Skip moving files larger than target group size
    if file_size > target_folder_size:
        print(
            f"Skipping photo '{file_path}' because it's larger than the target group size."
        )
        return group_info

    # Check and update group info if current group is full
    num, folder, size = ensure_space_in_group(
        photos_folder, file_size, target_folder_size, group_info, group_size_cache
    )

    if move_file_to_group(file_path, folder):
        size += file_size
        group_size_cache[folder] = size

    return num, folder, size


# Main function
def group_photos(photos_folder, target_folder_size):
    print(
        f"Grouping photos in '{photos_folder}' with target size {target_folder_size} bytes..."
    )

    current_group_num, current_group_folder, current_group_size = get_latest_group_info(
        photos_folder
    )

    if current_group_folder is None:
        current_group_folder = create_new_folder(
            photos_folder, f"Group_{current_group_num}"
        )

    # Initialize cache with the current group's size
    group_size_cache = {current_group_folder: current_group_size}
    current_group_info = (current_group_num, current_group_folder, current_group_size)

    for root, dirs, files in os.walk(photos_folder):
        # Exclude generated group folders from os.walk
        dirs[:] = [d for d in dirs if not d.startswith("Group_")]

        for file in files:
            file_path = os.path.join(root, file)
            current_group_info = process_file(
                file_path,
                photos_folder,
                target_folder_size,
                current_group_info,
                group_size_cache
            )

    print("Grouping completed.")


def parse_size(size_str):
    """Helper to parse size strings like '15GB', '500MB'."""
    units = {"B": 1, "KB": 1024, "MB": 1024**2, "GB": 1024**3, "TB": 1024**4}
    size_str = size_str.upper().strip()

    for unit, multiplier in sorted(
        units.items(), key=lambda x: len(x[0]), reverse=True
    ):
        if size_str.endswith(unit):
            try:
                return int(float(size_str[: -len(unit)].strip()) * multiplier)
            except ValueError:
                break
    try:
        return int(size_str)
    except ValueError:
        raise argparse.ArgumentTypeError(
            f"Invalid size format: {size_str}. Use e.g. 15GB, 500MB, or bytes."
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Group photos into folders by size.")
    parser.add_argument("photos_folder", help="Path to the folder containing photos.")
    parser.add_argument(
        "--size",
        type=parse_size,
        default=parse_size("15GB"),
        help="Target size for each group (e.g., 15GB, 500MB). Default is 15GB.",
    )

    args = parser.parse_args()

    if not os.path.isdir(args.photos_folder):
        import sys
        print(f"Error: '{args.photos_folder}' is not a directory.", file=sys.stderr)
        sys.exit(1)

    group_photos(args.photos_folder, args.size)
