🔒 Fix TOCTOU Symlink Attack in Log Truncation

🎯 **What:**
Fixed a Time-of-Check to Time-of-Use (TOCTOU) symlink vulnerability in `RaspberryPi/Scripts/pi-minify.sh` where `find` combined with `truncate` or bash `>` redirection was used to clear log files in `/var/log`.

⚠️ **Risk:**
If a subdirectory in `/var/log` is writable by a compromised service, an attacker could race the cleanup script by replacing a log file with a symlink pointing to a critical system file (like `/etc/shadow`) between the time `find` identifies the file and `truncate` executes. Since `truncate` and `>` follow symlinks, the script would run as root and inadvertently wipe the target system file.

🛡️ **Solution:**
Replaced the vulnerable truncation logic with robust alternatives that enforce symlink refusal at the system call level.
- Used an inline Python script utilizing `os.open` with the `os.O_NOFOLLOW` flag to instantly fail (yielding `ELOOP`) if a file path component has been replaced by a symlink.
- Provided a secure fallback using `dd oflag=nofollow` in case Python 3 is unavailable on the system.
- Maintained the fast bulk-processing capabilities using `sys.argv[1:]` and `"$@"` alongside `find ... {} +`.
