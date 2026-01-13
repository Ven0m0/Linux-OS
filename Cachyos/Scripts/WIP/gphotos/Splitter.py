import os
import shutil

# Function to calculate folder size recursively
def get_folder_size(folder):
    total_size = 0
    for dirpath, _, filenames in os.walk(folder):
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            total_size += os.path.getsize(filepath)
    return total_size

# Function to create a new folder or return existing one
def create_new_folder(root_folder, folder_name):
    new_folder_path = os.path.join(root_folder, folder_name)
    if not os.path.exists(new_folder_path):
        os.makedirs(new_folder_path)
        print(f"Created new folder: {new_folder_path}")
    return new_folder_path

# Main function
def group_photos(photos_folder, target_folder_size):
    print("Grouping photos...")
    current_group_folder = None
    current_group_size = 0
    group_number = 0

    for root, dirs, files in os.walk(photos_folder):
        for file in files:
            file_path = os.path.join(root, file)
            file_size = os.path.getsize(file_path)

            # Skip moving files larger than target group size
            if file_size > target_folder_size:
                print(f"Skipping photo '{file_path}' because it's larger than the target group size.")
                continue

            # Create a new group folder if the current one is full or doesn't exist
            if current_group_folder is None or current_group_size + file_size > target_folder_size:
                group_number += 1
                current_group_folder = create_new_folder(photos_folder, f"Group_{group_number}")
                current_group_size = 0

            # Move the file to the current group folder if it's not already there
            if not file_path.startswith(current_group_folder):
                try:
                    shutil.move(file_path, current_group_folder)
                    print(f"Moved photo '{file_path}' to '{current_group_folder}'")
                    current_group_size += file_size
                except Exception as e:
                    print(f"Failed to move photo '{file_path}': {e}")

    print("Grouping completed.")

if __name__ == '__main__':
    # Set the location of the photos folder
    photos_folder = r"C:\Users\somes\OneDrive\Desktop\New folder"  # Replace this with the path to your main folder
    # Define the target size for each group (in bytes)
    target_group_size = 15 * 1024 * 1024 * 1024  # 15 GB

    # Group the photos
    group_photos(photos_folder, target_group_size)
