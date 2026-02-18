#!/usr/bin/env python3
"""Fetch files/folders from GitHub/GitLab using stdlib only.

This script allows downloading files or directories from GitHub or GitLab
repositories without requiring git to be installed, using only the
standard library.

Usage:
    fetch.py <github-or-gitlab-url> [output-dir] [--token TOKEN]

Environment Variables:
    GITHUB_TOKEN - Optional auth token for GitHub
    GITLAB_TOKEN - Optional auth token for GitLab
"""

import argparse
import http.client
import json
import os
import queue
import sys
import urllib.parse
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Literal, Optional


@dataclass(slots=True)
class RepoSpec:
    """Repository specification parsed from URL."""

    platform: Literal["github", "gitlab"]
    owner: str
    repo: str
    path: str
    branch: str


def parse_url(url: str) -> RepoSpec:
    """Extract repo metadata from GitHub/GitLab URL."""
    u = urllib.parse.urlparse(url)
    parts = [p for p in u.path.strip("/").split("/") if p]
    host = u.hostname or ""

    if host == "github.com":
        if len(parts) < 2:
            raise ValueError(f"Invalid GitHub URL: {url}")
        owner, repo = parts[0], parts[1]
        branch = "main"
        path = ""
        if len(parts) > 3 and parts[2] in ("tree", "blob"):
            branch = parts[3]
            path = "/".join(parts[4:]) if len(parts) > 4 else ""
        return RepoSpec("github", owner, repo, path, branch)

    if host == "gitlab.com":
        if len(parts) < 2:
            raise ValueError(f"Invalid GitLab URL: {url}")
        owner, repo = parts[0], parts[1]
        branch = "main"
        path = ""
        if len(parts) > 3 and parts[2] == "-" and parts[3] == "tree":
            branch = parts[4] if len(parts) > 4 else "main"
            path = "/".join(parts[5:]) if len(parts) > 5 else ""
        return RepoSpec("gitlab", owner, repo, path, branch)

    raise ValueError(f"Unsupported platform: {u.netloc}")


_opener_cache: Optional[urllib.request.OpenerDirector] = None


def get_opener() -> urllib.request.OpenerDirector:
    """Get cached opener for connection reuse."""
    global _opener_cache
    if _opener_cache is None:
        _opener_cache = urllib.request.build_opener()
        _opener_cache.addheaders = [("User-Agent", "git-fetch.py")]
    return _opener_cache


def http_get(url: str, headers: dict[str, str] | None = None) -> bytes:
    """Execute HTTP GET with optional headers."""
    req = urllib.request.Request(url, headers=headers or {})
    try:
        with get_opener().open(req, timeout=30) as resp:
            return resp.read()
    except urllib.error.URLError:
        raise


def download_worker(host: str, file_q: queue.Queue, headers: dict[str, str]) -> None:
    """Worker thread: process files from queue using a persistent connection."""
    # Make a per-thread copy so we don't mutate a shared headers dict.
    headers = dict(headers)
    if "User-Agent" not in headers:
        headers["User-Agent"] = "git-fetch.py"

    conn = http.client.HTTPSConnection(host, timeout=30)

    try:
        while True:
            try:
                # Get next file from queue
                item = file_q.get_nowait()
            except queue.Empty:
                break

            try:
                url_path, local_path, display_path = item

                # Process download
                retries = 3
                while retries > 0:
                    try:
                        conn.request("GET", url_path, headers=headers)
                        resp = conn.getresponse()

                        # Check if the server wants to close the connection
                        connection_header = resp.getheader("Connection", "").lower()
                        should_close = connection_header == "close"

                        if resp.status == 200:
                            with open(local_path, "wb") as f:
                                while True:
                                    chunk = resp.read(65536)
                                    if not chunk:
                                        break
                                    f.write(chunk)
                            print(f"✓ {display_path}")

                            if should_close:
                                conn.close()
                                # Reconnect for the next file in the queue
                                conn = http.client.HTTPSConnection(host, timeout=30)

                            break
                        elif resp.status in (301, 302, 307, 308):
                            loc = resp.getheader("Location")
                            resp.read()  # Consume body
                            if loc:
                                print(
                                    f"✗ {display_path}: Redirect to {loc} not handled in persistent mode"
                                )
                            else:
                                print(f"✗ {display_path}: HTTP {resp.status}")

                            if should_close:
                                conn.close()
                                conn = http.client.HTTPSConnection(host, timeout=30)
                            break
                        else:
                            print(f"✗ {display_path}: HTTP {resp.status}")
                            resp.read()  # Consume body
                            if should_close:
                                conn.close()
                                conn = http.client.HTTPSConnection(host, timeout=30)

                            # Non-retriable client errors: fail fast
                            if resp.status in (401, 403, 404):
                                break

                            # Retry on transient server errors and rate limiting
                            if 500 <= resp.status < 600 or resp.status == 429:
                                retries -= 1
                                if retries > 0:
                                    continue
                                # Out of retries, give up
                                break

                            # Default: treat other statuses as non-retriable
                            break
                    except (http.client.HTTPException, OSError) as e:
                        # Connection might have been closed by server unexpectedly
                        conn.close()
                        retries -= 1
                        if retries > 0:
                            conn = http.client.HTTPSConnection(host, timeout=30)
                        else:
                            print(f"✗ {display_path}: {e}")
            finally:
                file_q.task_done()
    finally:
        conn.close()


def fetch_github(spec: RepoSpec, output: Path, token: Optional[str] = None) -> None:
    """Download from GitHub using Contents/Trees API."""
    token = token or os.getenv("GITHUB_TOKEN", "")
    headers = {"Accept": "application/vnd.github.v3+json"}
    if token:
        headers["Authorization"] = f"token {token}"

    using_subtree = bool(spec.path)
    if using_subtree:
        # Use subtree fetch: git/trees/REF:PATH
        # We clean the path to remove leading/trailing slashes.
        clean_path = spec.path.strip("/")
        ref = f"{spec.branch}:{clean_path}"
        encoded_ref = urllib.parse.quote(ref, safe=":")
        api_url = f"https://api.github.com/repos/{spec.owner}/{spec.repo}/git/trees/{encoded_ref}?recursive=1"
    else:
        # Root fetch
        api_url = f"https://api.github.com/repos/{spec.owner}/{spec.repo}/git/trees/{spec.branch}?recursive=1"

    try:
        data_bytes = http_get(api_url, headers)
        data = json.loads(data_bytes)
    except urllib.error.HTTPError as e:
        # 404: Not found (or private repo without token)
        # 422: Unprocessable Entity (e.g. path is a blob, not a tree)
        if e.code == 404 or e.code == 422:
            if spec.path:
                # Fallback to single file download attempt
                raw_url = f"https://raw.githubusercontent.com/{spec.owner}/{spec.repo}/{spec.branch}/{urllib.parse.quote(spec.path)}"
                try:
                    content = http_get(raw_url, headers)
                    output.parent.mkdir(parents=True, exist_ok=True)
                    output.write_bytes(content)
                    print(f"✓ {spec.path}")
                    return
                except urllib.error.HTTPError:
                    pass
            raise
        raise

    files_to_download = []
    tree = data.get("tree", [])

    for item in tree:
        item_path = item["path"]

        # local_path is always relative to output dir using the item's relative path from the fetch root
        local_path = output / item_path

        if item["type"] == "tree":
            local_path.mkdir(parents=True, exist_ok=True)
        elif item["type"] == "blob":
            # Determine full path for URL construction
            if using_subtree:
                # Prepend cleaned path because item_path is relative to the subtree
                full_path = f"{clean_path}/{item_path}"
            else:
                full_path = item_path

            encoded_path = "/".join(urllib.parse.quote(p) for p in full_path.split("/"))
            path_part = f"/{spec.owner}/{spec.repo}/{spec.branch}/{encoded_path}"
            # Store full_path for display
            files_to_download.append((path_part, local_path, full_path))

    if not files_to_download:
        return

    # Use queue for dynamic load balancing among workers
    file_q = queue.Queue()
    for f in files_to_download:
        file_q.put(f)

    max_workers = min(32, (os.cpu_count() or 1) * 4)
    num_workers = max(1, min(max_workers, len(files_to_download)))

    dl_headers = headers.copy()
    if "Connection" not in dl_headers:
        dl_headers["Connection"] = "keep-alive"

    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        futures = [
            executor.submit(
                download_worker, "raw.githubusercontent.com", file_q, dl_headers
            )
            for _ in range(num_workers)
        ]
        for future in as_completed(futures):
            try:
                future.result()
            except Exception as e:
                print(f"Worker error: {e}", file=sys.stderr)



def fetch_gitlab(spec: RepoSpec, output: Path, token: Optional[str] = None) -> None:
    """Download from GitLab using Repository API."""
    token = token or os.getenv("GITLAB_TOKEN", "")
    headers = {}
    if token:
        headers["PRIVATE-TOKEN"] = token

    project_id = urllib.parse.quote(f"{spec.owner}/{spec.repo}", safe="")

    tree_url = f"https://gitlab.com/api/v4/projects/{project_id}/repository/tree"
    params = {
        "path": spec.path,
        "ref": spec.branch,
        "per_page": "100",
        "recursive": "true",
    }
    full_url = f"{tree_url}?{urllib.parse.urlencode(params)}"

    try:
        data_bytes = http_get(full_url, headers)
        data = json.loads(data_bytes)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            file_path_enc = urllib.parse.quote(spec.path, safe="")
            raw_url = f"https://gitlab.com/api/v4/projects/{project_id}/repository/files/{file_path_enc}/raw?ref={spec.branch}"
            try:
                content = http_get(raw_url, headers)
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(content)
                print(f"✓ {spec.path}")
                return
            except urllib.error.HTTPError:
                pass
        raise

    dirs_created = set()
    files_to_download = []

    for item in data:
        item_path = item["path"]
        # GitLab returns full path even with path filter
        rel_path = item_path[len(spec.path) :].lstrip("/") if spec.path else item_path
        local_path = output / rel_path

        if item["type"] == "tree":
            local_path.mkdir(parents=True, exist_ok=True)
            dirs_created.add(str(local_path))
        elif item["type"] == "blob":
            if str(local_path.parent) not in dirs_created:
                local_path.parent.mkdir(parents=True, exist_ok=True)
                dirs_created.add(str(local_path.parent))

            file_path_enc = urllib.parse.quote(item_path, safe="")
            path_part = f"/api/v4/projects/{project_id}/repository/files/{file_path_enc}/raw?ref={spec.branch}"
            files_to_download.append((path_part, local_path, item_path))

    if not files_to_download:
        return

    file_q = queue.Queue()
    for f in files_to_download:
        file_q.put(f)

    max_workers = min(32, (os.cpu_count() or 1) * 4)
    num_workers = min(max_workers, len(files_to_download))

    dl_headers = headers.copy()
    if "Connection" not in dl_headers:
        dl_headers["Connection"] = "keep-alive"

    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        futures = [
            executor.submit(download_worker, "gitlab.com", file_q, dl_headers)
            for _ in range(num_workers)
        ]
        for future in as_completed(futures):
            try:
                future.result()
            except Exception as e:
                print(f"Worker error: {e}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description="Fetch files from GitHub/GitLab.")
    parser.add_argument("url", help="GitHub or GitLab URL")
    parser.add_argument("output_dir", nargs="?", default=".", help="Output directory")
    parser.add_argument("--token", help="Auth token (overrides env vars)")

    args = parser.parse_args()

    try:
        spec = parse_url(args.url)
        output_path = Path(args.output_dir) / (Path(spec.path).name or spec.repo)

        if spec.platform == "github":
            fetch_github(spec, output_path, args.token)
        else:
            fetch_gitlab(spec, output_path, args.token)

        print(f"\n✓ Downloaded to: {output_path}")
        return 0
    except Exception as e:
        print(f"✗ Error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
