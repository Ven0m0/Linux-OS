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
    """Finds the highest numbered Group_N folder and its size."""
    max_group_num = 0
    if os.path.exists(photos_folder):
        for item in os.listdir(photos_folder):
            if item.startswith("Group_") and os.path.isdir(
                os.path.join(photos_folder, item)
            ):
                try:
                    num = int(item.split("_")[1])
                    if num > max_group_num:
                        max_group_num = num
                except (ValueError, IndexError):
                    continue

    if max_group_num == 0:
        return 1, None, 0

    group_folder = os.path.join(photos_folder, f"Group_{max_group_num}")
    return max_group_num, group_folder, get_folder_size(group_folder)


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

    for root, dirs, files in os.walk(photos_folder):
        # Exclude generated group folders from os.walk
        dirs[:] = [d for d in dirs if not d.startswith("Group_")]

        for file in files:
            file_path = os.path.join(root, file)
            try:
                file_size = os.path.getsize(file_path)
            except OSError:
                continue

            # Skip moving files larger than target group size
            if file_size > target_folder_size:
                print(
                    f"Skipping photo '{file_path}' because it's larger than the target group size."
                )
                continue

            # Check if current group is full, and move to next until we find one with space or create new
            while current_group_size + file_size > target_folder_size:
                current_group_num += 1
                current_group_folder = os.path.join(
                    photos_folder, f"Group_{current_group_num}"
                )
                if os.path.exists(current_group_folder):
                    current_group_size = get_folder_size(current_group_folder)
                else:
                    create_new_folder(photos_folder, f"Group_{current_group_num}")
                    current_group_size = 0

            # Move the file to the current group folder if it's not already there
            # We use absolute paths for comparison to be safe
            abs_file_path = os.path.abspath(file_path)
            abs_group_folder = os.path.abspath(current_group_folder)

            if not abs_file_path.startswith(abs_group_folder):
                try:
                    shutil.move(file_path, current_group_folder)
                    print(f"Moved photo '{file_path}' to '{current_group_folder}'")
                    current_group_size += file_size
                except Exception as e:
                    print(f"Failed to move photo '{file_path}': {e}")

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
        default="15GB",
        help="Target size for each group (e.g., 15GB, 500MB). Default is 15GB.",
    )

    args = parser.parse_args()

    if not os.path.isdir(args.photos_folder):
        print(f"Error: '{args.photos_folder}' is not a directory.")
        exit(1)

    group_photos(args.photos_folder, args.size)
