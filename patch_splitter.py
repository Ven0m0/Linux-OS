import re

with open('Cachyos/Scripts/WIP/gphotos/Splitter.py', 'r') as f:
    content = f.read()

# Replace duplicated create_new_folder logic
content = re.sub(
    r'                current_group_folder = os\.path\.join\(\n                    photos_folder, f"Group_\{current_group_num\}"\n                \)\n                if os\.path\.exists\(current_group_folder\):\n                    current_group_size = get_folder_size\(current_group_folder\)\n                else:\n                    create_new_folder\(photos_folder, f"Group_\{current_group_num\}"\)\n                    current_group_size = 0',
    r'''                current_group_folder = create_new_folder(photos_folder, f"Group_{current_group_num}")
                current_group_size = get_folder_size(current_group_folder)''',
    content
)

with open('Cachyos/Scripts/WIP/gphotos/Splitter.py', 'w') as f:
    f.write(content)
