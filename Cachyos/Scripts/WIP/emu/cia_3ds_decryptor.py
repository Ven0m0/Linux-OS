#!/usr/bin/env python3
"""CIA/3DS Decryptor – Cross-platform Nintendo 3DS file decryptor."""

import logging
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import os
import concurrent.futures
from dataclasses import dataclass
from pathlib import Path
from contextlib import contextmanager

VERSION = "v2.0.1"
IS_WIN = platform.system() == "Windows"


@dataclass(slots=True)
class Counters:
    total: int = 0
    final: int = 0
    count_3ds: int = 0
    count_cia: int = 0
    cia_err: int = 0
    cci_err: int = 0
    ds_err: int = 0
    convert_to_cci: bool = False

    def __add__(self, other):
        if not isinstance(other, Counters):
            return NotImplemented
        return Counters(
            total=self.total + other.total,
            final=self.final + other.final,
            count_3ds=self.count_3ds + other.count_3ds,
            count_cia=self.count_cia + other.count_cia,
            cia_err=self.cia_err + other.cia_err,
            cci_err=self.cci_err + other.cci_err,
            ds_err=self.ds_err + other.ds_err,
            # For boolean flags, OR them or keep from main?
            # convert_to_cci is a config flag, not a result.
            # But we should preserve it if needed.
            convert_to_cci=self.convert_to_cci,
        )


@dataclass(slots=True)
class TitleInfo:
    title_id: str = ""
    title_version: str = "0"
    crypto_key: str = ""


VALID_CHARS = frozenset("-_abcdefghijklmnopqrstuvwxyz1234567890. ")
TRANSLATE_TABLE = str.maketrans(
    "", "", "".join(chr(i) for i in range(256) if chr(i).lower() not in VALID_CHARS)
)
TITLE_ID_RE = re.compile(r"Title id:\s*(\S+)", re.IGNORECASE)
TITLE_VERSION_RE = re.compile(r"TitleVersion:\s*(\d+)", re.IGNORECASE)
TWL_TITLE_ID_RE = re.compile(r"TitleId:\s*(\S+)", re.IGNORECASE)
TWL_ENCRYPTED_RE = re.compile(r"Encrypted:\s*(\S+)", re.IGNORECASE)
CIA_GAME_RE = re.compile(r"00040000")
CIA_SYSTEM_RE = re.compile(
    r"00040010|0004001b|00040030|0004009b|000400db|00040130|00040138"
)
CIA_DEMO_RE = re.compile(r"00040002")
CIA_PATCH_RE = re.compile(r"0004000e")
CIA_DLC_RE = re.compile(r"0004008c")
UNSUPPORTED_CCI_RE = re.compile(
    r"000400db|0004001b|0004009b|00040010|00040030|00040130|0004000e|0004008c|00048005|0004800f|00048004|00040002",
    re.IGNORECASE,
)


def die(msg: str) -> None:
    logging.error(msg)
    sys.stderr.write(f"{msg}\n")
    sys.exit(1)


def setup_logging(log_dir: Path) -> None:
    log_dir.mkdir(exist_ok=True)
    log_file = log_dir / "programlog.txt"
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s = %(message)s",
        datefmt="%Y-%m-%d - %H:%M:%S",
        handlers=[logging.FileHandler(log_file, mode="w", encoding="utf-8")],
    )
    logging.info("CIA/3DS Decryptor Redux %s", VERSION)
    logging.info("[i] Script started")


def find_tool(name: str, bin_dir: Path) -> Path:
    if IS_WIN:
        exe = bin_dir / f"{name}.exe"
        if not exe.is_file():
            die(f"Missing {name}.exe in {bin_dir}")
        return exe
    native = shutil.which(name)
    if native:
        return Path(native)
    wine_exe = bin_dir / f"{name}.exe"
    if wine_exe.is_file() and shutil.which("wine"):
        return wine_exe
    die(f"Cannot find {name} (native) or wine + {name}.exe")


def run_tool(
    tool: Path, args: list[str], stdin: str = "", cwd: Path | None = None
) -> tuple[int, str]:
    cmd = ["wine"] if not IS_WIN and tool.suffix == ".exe" else []
    cmd.extend([str(tool)] + args)
    proc = subprocess.run(
        cmd,
        input=stdin.encode("utf-8") if stdin else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        cwd=str(cwd) if cwd else None,
    )
    return proc.returncode, proc.stdout.decode("utf-8", errors="replace")


def link_or_copy(src: Path, dst: Path) -> None:
    if IS_WIN:
        shutil.copy2(src, dst)
    else:
        os.symlink(src.resolve(), dst)


@contextmanager
def prepare_task_env(tools: list[Path], seeddb: Path):
    with tempfile.TemporaryDirectory() as tmp_dir:
        task_bin_dir = Path(tmp_dir) / "bin"
        task_bin_dir.mkdir()

        # Link tools
        new_tools = []
        for tool in tools:
            dst = task_bin_dir / tool.name
            link_or_copy(tool, dst)
            new_tools.append(dst)

        # Link seeddb
        new_seeddb = task_bin_dir / seeddb.name
        link_or_copy(seeddb, new_seeddb)

        yield task_bin_dir, new_tools, new_seeddb


def sanitize_filename(name: str) -> str:
    out = name.translate(TRANSLATE_TABLE)
    return out if out else name


def parse_ctrtool_output(text: str) -> TitleInfo:
    info = TitleInfo()
    for line in text.splitlines():
        if not info.title_id and (m := TITLE_ID_RE.search(line)):
            info.title_id = m.group(1)
        if not info.title_version and (m := TITLE_VERSION_RE.search(line)):
            info.title_version = m.group(1)
        if not info.crypto_key and "Crypto Key" in line:
            info.crypto_key = line.strip()
    return info


def parse_twl_ctrtool_output(text: str) -> TitleInfo:
  info = TitleInfo()
  for line in text.splitlines():
    if not info.title_id and (m := TWL_TITLE_ID_RE.search(line)):
      info.title_id = m.group(1)
    if not info.title_version and (m := TITLE_VERSION_RE.search(line)):
      info.title_version = m.group(1)
    if not info.crypto_key and (m := TWL_ENCRYPTED_RE.search(line)):
      info.crypto_key = m. group(1)
  return info

def clean_ncch_files(bin_dir:  Path) -> None:
  ncch = list(bin_dir.glob("*. ncch"))
  if ncch:
    # logging.info("[i] Found unused NCCH file(s). Deleting.")
    for f in ncch:
      f.unlink(missing_ok=True)

def rename_ncch_to_tmp(bin_dir: Path) -> None:
    for f in bin_dir.glob("*.ncch"):
        if not f.name.startswith("tmp."):
            f.rename(bin_dir / f"tmp.{f.stem}.ncch")


def build_ncch_args(bin_dir: Path) -> str:
    mapping = {
        "tmp.Main.ncch": 0,
        "tmp.Manual.ncch": 1,
        "tmp.DownloadPlay.ncch": 2,
        "tmp.Partition4.ncch": 3,
        "tmp.Partition5.ncch": 4,
        "tmp.Partition6.ncch": 5,
        "tmp.N3DSUpdateData.ncch": 6,
        "tmp.UpdateData.ncch": 7,
    }
    parts = [
        f'-i "{ncch}:{mapping.get(ncch.name, 0)}:{mapping.get(ncch.name, 0)}"'
        for ncch in sorted(bin_dir.glob("tmp.*.ncch"))
    ]
    return " ".join(parts)


def build_ncch_args_sequential(bin_dir: Path) -> str:
    return " ".join(
        f'-i "{ncch}:{i}:{i}"'
        for i, ncch in enumerate(sorted(bin_dir.glob("tmp.*.ncch")))
    )


def build_ncch_args_contentid(bin_dir: Path, content_txt: Path) -> str:
    content_ids = []
    if content_txt.exists():
        for line in content_txt.read_text(errors="replace").splitlines():
            if "ContentId:" in line:
                cid = line.split("ContentId:")[1].strip()[:8]
                if cid:
                    content_ids.append(int(cid, 16))
    ncch_files = sorted(bin_dir.glob("tmp.*.ncch"))
    parts = [
        f'-i "{ncch}:{i}:{content_ids[i] if i < len(content_ids) else i}"'
        for i, ncch in enumerate(ncch_files)
    ]
    return " ".join(parts)


def decrypt_3ds(
    root: Path,
    bin_dir: Path,
    file: Path,
    ctrtool: Path,
    decrypt: Path,
    makerom: Path,
    seeddb: Path,
    cnt: Counters,
) -> None:
    stem = sanitize_filename(file.stem)
    if "-decrypted" in stem.lower():
        return
    out_cci = root / f"{stem}-decrypted.cci"
    if out_cci.exists():
        logging.warning("[^] 3DS file '%s' was already decrypted", file.name)
        cnt.final += 1
        return
    tmp_content = bin_dir / "CTR_Content.txt"
    _, txt = run_tool(ctrtool, ["--seeddb", str(seeddb), str(file)], cwd=root)
    tmp_content.write_text(txt, encoding="utf-8", errors="replace")
    info = parse_ctrtool_output(txt)
    if "None" in info.crypto_key:
        logging.warning(
            "[^] 3DS file '%s' [%s v%s] is already decrypted",
            file.name,
            info.title_id,
            info.title_version,
        )
        cnt.ds_err += 1
        return
    run_tool(decrypt, [str(file)], stdin="\n", cwd=root)
    rename_ncch_to_tmp(bin_dir)
    arg_str = build_ncch_args(bin_dir)
    cmd = [
        "-f",
        "cci",
        "-ignoresign",
        "-target",
        "p",
        "-o",
        str(out_cci),
    ] + arg_str.split()
    run_tool(makerom, cmd, cwd=root)
    clean_ncch_files(bin_dir)
    if out_cci.exists():
        logging.info("[i] Decrypting succeeded for file '%s'", file.name)
        cnt.final += 1
    else:
        logging.error("[^! ] Decrypting failed for file '%s'", file.name)
        cnt.ds_err += 1


def decrypt_cia(
    root: Path,
    bin_dir: Path,
    file: Path,
    ctrtool: Path,
    decrypt: Path,
    makerom: Path,
    seeddb: Path,
    cnt: Counters,
) -> None:
    stem = sanitize_filename(file.stem)
    if "-decrypted" in stem.lower():
        return
    tmp_content = bin_dir / "CTR_Content.txt"
    _, txt = run_tool(ctrtool, ["--seeddb", str(seeddb), str(file)], cwd=root)
    tmp_content.write_text(txt, encoding="utf-8", errors="replace")
    if "ERROR" in txt:
        logging.error("[^! ] CIA is invalid [%s]", file.name)
        cnt.cia_err += 1
        return
    info = parse_ctrtool_output(txt)
    tid = info.title_id.upper()
    if "Secure" not in info.crypto_key:
        if not tid.startswith("00048"):
            if "None" in info.crypto_key:
                logging.warning(
                    "[^] CIA file '%s' [%s v%s] is already decrypted",
                    file.name,
                    info.title_id,
                    info.title_version,
                )
                cnt.cia_err += 1
            return
        twl_info = parse_twl_ctrtool_output(txt)
        if twl_info.crypto_key.upper() == "NO":
            logging.warning(
                "[^] TWL CIA file '%s' [%s v%s] is already decrypted",
                file.name,
                twl_info.title_id,
                twl_info.title_version,
            )
            cnt.cia_err += 1
            return
        if twl_info.crypto_key.upper() == "YES" and tid.startswith("00048"):
            logging.info(
                "[i] CIA file '%s' [%s v%s] is a TWL title",
                file.name,
                twl_info.title_id,
                twl_info.title_version,
            )
            # Fix hardcoded bin/ path to use bin_dir
            run_tool(
                ctrtool,
                [
                    f"--contents={bin_dir}/00000000.app",
                    f"--meta={bin_dir}/00000000.app",
                    str(file),
                ],
                cwd=root,
            )
            app_file = bin_dir / "00000000.app.0000.00000000"
            if app_file.exists():
                app_file.rename(bin_dir / "00000000.app")
            out_cia = root / f"{stem} TWL-decrypted.cia"
            makerom_args = [
                "-srl",
                str(bin_dir / "00000000.app"),
                "-f",
                "cia",
                "-ignoresign",
                "-target",
                "p",
                "-o",
                str(out_cia),
                "-ver",
                twl_info.title_version,
            ]
            run_tool(makerom, makerom_args, cwd=root)
            (bin_dir / "00000000.app").unlink(missing_ok=True)
            if out_cia.exists():
                logging.info(
                    "[i] Decrypting succeeded [%s v%s]",
                    twl_info.title_id,
                    twl_info.title_version,
                )
                cnt.final += 1
            else:
                logging.error(
                    "[^!] Decrypting failed [%s v%s]",
                    twl_info.title_id,
                    twl_info.title_version,
                )
                cnt.cia_err += 1
            return
        return
    cia_type = ""
    for name, pattern in [
        ("Game", CIA_GAME_RE),
        ("System", CIA_SYSTEM_RE),
        ("Demo", CIA_DEMO_RE),
        ("Patch", CIA_PATCH_RE),
        ("DLC", CIA_DLC_RE),
    ]:
        if pattern.search(tid):
            cia_type = name
            break
    if not cia_type:
        logging.error("[^!] Could not determine CIA type [%s]", file.name)
        return
    type_descriptions = {
        "Game": "eShop or Gamecard",
        "System": "system",
        "Demo": "demo",
        "Patch": "update",
        "DLC": "DLC",
    }
    logging.info(
        "[i] CIA file '%s' [%s v%s] is a %s title",
        file.name,
        info.title_id,
        info.title_version,
        type_descriptions[cia_type],
    )
    out_cia = root / f"{stem} {cia_type}-decrypted.cia"
    if out_cia.exists():
        logging.warning("[^] CIA file '%s' was already decrypted", file.name)
        if not cnt.convert_to_cci:
            cnt.final += 1
        return
    run_tool(decrypt, [str(file)], stdin="\n", cwd=root)
    rename_ncch_to_tmp(bin_dir)
    arg_str = (
        build_ncch_args_contentid(bin_dir, tmp_content)
        if cia_type in ("Patch", "DLC")
        else build_ncch_args_sequential(bin_dir)
    )
    cmd = ["-f", "cia", "-ignoresign", "-target", "p", "-o", str(out_cia)]
    if cia_type == "DLC":
        cmd.append("-dlc")
    cmd.extend(arg_str.split() + ["-ver", info.title_version])
    logging.info(
        "[i] Calling makerom for %s CIA [%s v%s]",
        cia_type,
        info.title_id,
        info.title_version,
    )
    run_tool(makerom, cmd, cwd=root)
    clean_ncch_files(bin_dir)
    if out_cia.exists():
        logging.info(
            "[i] Decrypting succeeded [%s v%s]", info.title_id, info.title_version
        )
        if not cnt.convert_to_cci:
            cnt.final += 1
    else:
        logging.error(
            "[^!] Decrypting failed [%s v%s]", info.title_id, info.title_version
        )
        cnt.cia_err += 1


def convert_cia_to_cci(
    root: Path, cia_file: Path, makerom: Path, cnt: Counters
) -> None:
    stem = cia_file.stem
    out_cci = root / f"{stem}.cci"
    if out_cci.exists():
        logging.warning(
            "[^] CIA file '%s' was already converted into CCI", cia_file.name
        )
        cnt.final += 1
        return
    tid_match = re.search(r"\[([0-9a-fA-F]+)\s+v(\d+)\]", stem)
    if tid_match:
        tid = tid_match.group(1)
        if UNSUPPORTED_CCI_RE.search(tid):
            logging.error(
                "[^!] Converting to CCI for this title is not supported [%s v%s]",
                tid,
                tid_match.group(2),
            )
            cia_file.unlink(missing_ok=True)
            cnt.cci_err += 1
            return
    run_tool(makerom, ["-ciatocci", str(cia_file), "-o", str(out_cci)], cwd=root)
    if out_cci.exists():
        cia_file.unlink(missing_ok=True)
        logging.info("[i] Converting to CCI succeeded [%s]", out_cci.name)
        cnt.final += 1
    else:
        logging.error("[^!] Converting to CCI failed [%s]", cia_file.name)
        cia_file.unlink(missing_ok=True)
        cnt.cci_err += 1


def process_file_task(func, root, file, tools_list, seeddb_path):
    """
    Wrapper to process a single file in an isolated environment.
    """
    with prepare_task_env(tools_list, seeddb_path) as (
        task_bin_dir,
        new_tools,
        new_seeddb,
    ):
        ctrtool, decrypt, makerom = new_tools
        local_cnt = Counters()
        func(root, task_bin_dir, file, ctrtool, decrypt, makerom, new_seeddb, local_cnt)
        return local_cnt


def process_conversion_task(root: Path, cia_file: Path, tools_list: list[Path], seeddb_path: Path) -> Counters:
    """
    Wrapper to process a single conversion.

    For conversion we do not need a per-task temporary environment, so we
    call convert_cia_to_cci directly with the existing makerom binary.
    """
    # tools_list is [ctrtool, decrypt, makerom]
    makerom = tools_list[2]
    local_cnt = Counters()
    convert_cia_to_cci(root, cia_file, makerom, local_cnt)
    return local_cnt


def banner() -> None:
  print("  ############################################################")
  print("  ###                                                      ###")
  # Fixed syntax error: {VERSION: 8} -> {VERSION:8}
  print(f"  ###         CIA/3DS Decryptor Redux {VERSION:8}         ###")
  print("  ###                                                      ###")
  print("  ############################################################\n")

def main() -> None:
    root = Path.cwd()
    bin_dir = root / "bin"
    log_dir = root / "log"
    setup_logging(log_dir)
    if not bin_dir.is_dir():
        die("Missing 'bin' directory with required tools.")
    ctrtool = find_tool("ctrtool", bin_dir)
    decrypt = find_tool("decrypt", bin_dir)
    makerom = find_tool("makerom", bin_dir)
    seeddb = bin_dir / "seeddb.bin"
    if not seeddb.is_file():
        die("Missing seeddb.bin in bin/")
    clean_ncch_files(bin_dir)
    for f in root.glob("*"):
        if f.is_file():
            new_name = sanitize_filename(f.name)
            if new_name != f.name:
                try:
                    f.rename(root / new_name)
                except OSError as e:
                    logging.warning(
                        "[^] Failed to sanitize filename '%s' -> '%s': %s",
                        f.name,
                        new_name,
                        e,
                    )
    cnt = Counters()
    cnt.count_cia = sum(
        1 for f in root.glob("*.cia") if "-decrypted" not in f.stem.lower()
    )
    cnt.count_3ds = sum(
        1 for f in root.glob("*.3ds") if "-decrypted" not in f.stem.lower()
    )
    cnt.total = cnt.count_cia + cnt.count_3ds
    if cnt.total == 0:
        banner()
        print("  No CIA or 3DS files found!\n")
        logging.warning("[^] No CIA or 3DS were found")
        logging.info("[i] Script execution ended")
        return
    if cnt.count_cia >= 1:
        banner()
        print(f"  {cnt.count_cia} CIA file(s) found. Convert to CCI?")
        print("  (Not supported:  DLC, Demos, System, TWL, Updates)\n")
        print("  [Y] Yes  [N] No\n")
        choice = input("  Enter:  ").strip().lower()
        if choice in ("y", "1"):
            cnt.convert_to_cci = True
        print()
    banner()
    print("  Decrypting.. .\n")

    tools_list = [ctrtool, decrypt, makerom]

    futures = {}
    with concurrent.futures.ThreadPoolExecutor() as executor:
        if cnt.count_3ds:
            logging.info("[i] Found %d 3DS file(s). Start decrypting...", cnt.count_3ds)
            for f in sorted(root.glob("*.3ds")):
                future = executor.submit(
                    process_file_task, decrypt_3ds, root, f, tools_list, seeddb
                )
                futures[future] = "3ds"

        if cnt.count_cia:
            logging.info("[i] Found %d CIA file(s). Start decrypting...", cnt.count_cia)
            for f in sorted(root.glob("*.cia")):
                future = executor.submit(
                    process_file_task, decrypt_cia, root, f, tools_list, seeddb
                )
                futures[future] = "cia"

        # Wait for completion and accumulate results
        for future in concurrent.futures.as_completed(futures):
            task_type = futures.get(future)
            try:
                result_cnt = future.result()
                cnt += result_cnt
            except Exception as e:
                logging.error("Task failed with exception: %s", e)
                # Update error counts so failed tasks are reflected in statistics
                if task_type == "3ds":
                    cnt.ds_err += 1
                elif task_type == "cia":
                    cnt.cia_err += 1
                # If task_type is None or unrecognized, we intentionally do not guess
    if cnt.convert_to_cci:
        logging.info("[i] Starting parallel CCI conversion...")
        conv_futures = {}
        with concurrent.futures.ThreadPoolExecutor() as executor:
            for f in sorted(root.glob("*-decrypted.cia")):
                future = executor.submit(
                    process_conversion_task, root, f, tools_list, seeddb
                )
                conv_futures[future] = f.name

            for future in concurrent.futures.as_completed(conv_futures):
                try:
                    result_cnt = future.result()
                    cnt += result_cnt
                except Exception as e:
                    logging.error(
                        "CCI conversion failed for %s: %s", conv_futures.get(future), e
                    )
                    cnt.cci_err += 1

    banner()
    if cnt.final == 0:
        print("  No files were decrypted!\n")
        logging.warning("[^] No files where decrypted")
    elif cnt.final == cnt.total:
        print("  Decrypting finished!\n")
        print(f"  Summary:\n  - {cnt.count_3ds} 3DS file(s) decrypted\n  - {cnt.count_cia} CIA file(s) decrypted\n")
        logging.info("[i] Decrypting process succeeded")
    else:
        print("  Some files were not decrypted!\n")
        print(
            f"  Summary:\n  - {cnt.ds_err} from {cnt.count_3ds} 3DS failures\n  - {cnt.cia_err} from {cnt.count_cia} CIA failures\n  - {cnt.cci_err} CCI conversion failures\n"
        )
        logging.warning("[^] Some files where not decrypted")
    print(f"  Review '{log_dir / 'programlog.txt'}' for details.\n")
    logging.info("[i] Script execution ended")


if __name__ == "__main__":
    main()
