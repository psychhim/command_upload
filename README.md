# Upload.sh – Command-Line File Uploader with History & Status

**Upload.sh** is a versatile Bash script to upload files to a server via HTTP POST, track uploaded files, and manage their status. It supports authentication, additional headers and form fields, clipboard copying, colored output, and maintains a hidden history of uploads with active/expired status checks.

---

## Features

- Upload files to a remote server with **POST** requests.
- Supports **HTTP Basic Authentication**.
- Add custom **headers** and **form fields**.
- **Copy URL to clipboard** automatically (`-c` / `--clipboard`).
- Maintains a **hidden history** of uploads (`~/.uploaded_files.txt`), keeping the last 100 entries.
- Check whether uploads are **active or expired**.
- View all uploads in chronological order.
- Colorful output for better readability:
  - **Green**: Upload successful  
  - **Orange**: URL copied to clipboard  
  - **Red**: Expired uploads
- Fully configurable **upload URL**.

---

## Installation

1. Clone this repository or download `upload.sh`:

git clone https://github.com/yourusername/upload.sh.git
cd upload.sh

2. Make the script executable:

chmod +x upload.sh

3. Optionally, move it to a directory in your PATH for global access:

sudo mv upload.sh /usr/local/bin/upload

## Usage

### Basic upload:

upload -f path/to/file.png

### Upload with authentication:

upload -f file.png -u user:password

### Upload and copy URL to clipboard:

upload -f file.png -c

### Specify a custom upload URL:

upload -f file.png -U https://upload.example.com

### Add custom headers and form fields:

upload -f file.png -H "X-API-Key: key" -F "extra=field"

## Viewing History:

### Recent Uploads (Outputs all uploads (oldest → newest) with timestamp, filename, and URL)

upload -r

### Check all uploads (active first, then expired):

upload -C

### Check only active uploads:

upload -C -a

### Check only expired uploads:

upload -C -e

### History is saved in this file (can be changed in script):

~/.uploaded_files.txt

Each line format:

YYYY-MM-DD HH:MM:SS | filename | URL

    Used for tracking last 100 uploads.

    --recent shows chronological uploads.

    --check verifies if URLs are still active.

## Colors

    Green: Successful uploads

    Orange: URL copied to clipboard

    Red: Expired uploads

### Disable color output:

upload -f file.png --no-color

## Requirements

    Bash 4+

    curl

    Optional for clipboard copying:

        Linux: xclip

        macOS: pbcopy

## License

MIT License

### Author
Created by psychhim – https://github.com/psychhim/command_upload
