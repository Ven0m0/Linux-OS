# Photo Splitter

## Overview

The **Photo Splitter** is a Python script designed to organize photos within a specified folder into subfolders based on a target size for each group. It helps manage large collections of photos by grouping them into manageable chunks, ensuring that each subfolder does not exceed a specified size limit.

## Usage

### Prerequisites

- Python 3.x installed on your system.

### Instructions

1. **Download the Script**: Download the `splitter.py` file to your local machine.

2. **Specify Photos Folder**: Open the `splitter.py` file in a text editor and specify the location of the folder containing the photos by setting the `photos_folder` variable.

3. **Set Target Size**: Define the target size for each group folder (in bytes) by setting the `target_group_size` variable.

4. **Run the Script**: Open a terminal or command prompt, navigate to the directory containing the `splitter.py` file, and execute the script by running the command: python splitter.py

5. **Review Output**: The script will organize the photos into subfolders within the specified photos folder according to the target size. Review the output to ensure that the photos are appropriately grouped.

## Customization

- **Target Group Size**: Adjust the `target_group_size` variable to specify the desired size for each group folder.

- **Supported File Formats**: By default, the script organizes files with extensions `.jpg`, `.jpeg`, `.png`, and `.gif`. You can modify the file extension filters in the script to include or exclude additional formats as needed.

---

# Duplicate Photo Finder

## Overview

The **Duplicate Photo Finder** (`du.py`) is a Python script designed to identify duplicate photos within a specified directory. It utilizes cryptographic hashing to compare file contents and detect duplicates accurately.

## Usage

### Prerequisites

- Python 3.x installed on your system.

### Instructions

1. **Download the Script**: Download the `du.py` file to your local machine.

2. **Run the Script**: Open a terminal or command prompt, navigate to the directory containing the `du.py` file, and execute the script by running the command:
