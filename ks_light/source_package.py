"""Create or verify a deterministic source ZIP from the reviewed release file list."""
import argparse
import hashlib
import io
import json
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import zipfile


LIMIT = 32 * 1024 * 1024
FILE_LIMIT = 4 * 1024 * 1024
MANIFEST = "SOURCE_MANIFEST.json"
STAMP = (1980, 1, 1, 0, 0, 0)
BINARY = {".png", ".jar"}
PRIVATE_DIRS = {".git", ".venv", "venv", ".hub-local", ".gradle", ".dart_tool", ".pio", "node_modules", "build", "outputs"}


def canonical(value):
    return (json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")


def valid_name(name):
    if not isinstance(name, str) or not name or len(name.encode("utf-8")) > 512 or "\\" in name or ":" in name or any(ord(c) < 32 for c in name):
        raise ValueError("Invalid source path")
    path = PurePosixPath(name)
    if path.is_absolute() or path.as_posix() != name or any(p in {".", "..", ""} for p in path.parts):
        raise ValueError("Source paths must be canonical and relative")
    lower = [p.casefold() for p in path.parts]
    if any(p in PRIVATE_DIRS for p in lower) or lower[-1] in {"key.properties", "local.properties", "ks_config.h", ".env", "connection.private.json"}:
        raise ValueError("Private or generated files cannot enter source packages")
    if path.suffix.casefold() in {".jks", ".keystore", ".apk", ".aab", ".streamdeckplugin", ".zip", ".pyc"} or ".private." in lower[-1]:
        raise ValueError("Private files and compiled outputs cannot enter source packages")
    if name.casefold() == MANIFEST.casefold():
        raise ValueError("Reserved package manifest path")
    return path


def source_bytes(root, name):
    relative = valid_name(name)
    target = root
    for part in relative.parts:
        target = target / part
        info = target.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise ValueError("Linked files/directories cannot enter source packages")
    if not target.is_file() or not target.resolve().is_relative_to(root):
        raise ValueError("Source path is not a regular file inside the checkout")
    with target.open("rb") as file:
        raw = file.read(FILE_LIMIT + 1)
    if len(raw) > FILE_LIMIT:
        raise ValueError("Source file exceeds size limit")
    if relative.suffix.casefold() not in BINARY:
        # Git checkout line endings and timestamps do not change package identity.
        text = raw.decode("utf-8").replace("\r\n", "\n")
        if "\0" in text:
            raise ValueError("Unexpected binary source file")
        if relative.suffix.casefold() == ".bat":
            text = text.replace("\n", "\r\n")
        raw = text.encode("utf-8")
    return raw


def mode(name):
    return 0o100755 if name.endswith("/gradlew") or name.endswith(".sh") else 0o100644


def check_inventory(root, names):
    """Require an explicit review when Git-visible source files are added or removed."""
    result = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
                            cwd=root, check=True, capture_output=True)
    candidates = set(result.stdout.decode("utf-8").split("\0")) - {""}
    if not isinstance(names, list) or any(not isinstance(name, str) for name in names):
        raise ValueError("Invalid inventory")
    for name in candidates:
        valid_name(name)
    if candidates != set(names) or len(names) != len(set(names)):
        added, removed = sorted(candidates - set(names)), sorted(set(names) - candidates)
        details = "".join(f"\n  + {name}" for name in added) + "".join(f"\n  - {name}" for name in removed)
        raise ValueError("Review and update release/source-files.json before packaging" + (details or "\n  duplicate entries"))


def create(root, names):
    root = Path(root).resolve()
    if not isinstance(names, list) or not 1 <= len(names) <= 1000:
        raise ValueError("Expected a reviewed list of 1..1000 source paths")
    for name in names:
        valid_name(name)
    if len({name.casefold() for name in names}) != len(names):
        raise ValueError("Duplicate or case-colliding source paths")
    contents, records, total = {}, [], 0
    for name in sorted(names):
        raw = source_bytes(root, name)
        total += len(raw)
        if total > LIMIT:
            raise ValueError("Source package exceeds size limit")
        contents[name] = raw
        records.append({"path": name, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
    manifest = {"version": 1, "normalization": "UTF-8 LF; BAT CRLF; PNG/JAR unchanged",
                "content_sha256": hashlib.sha256(canonical(records)).hexdigest(), "files": records}
    contents[MANIFEST] = canonical(manifest)
    buffer = io.BytesIO()
    # Stored ZIP entries avoid compressor-version differences across platforms.
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
        for name in sorted(contents):
            info = zipfile.ZipInfo(name, STAMP)
            info.create_system = 3
            info.external_attr = mode(name) << 16
            archive.writestr(info, contents[name])
    return buffer.getvalue(), manifest


def verify(path):
    if Path(path).stat().st_size > LIMIT + 2 * 1024 * 1024:
        raise ValueError("Package exceeds size limit")
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if len(entries) > 1001 or names != sorted(names) or len({name.casefold() for name in names}) != len(names):
            raise ValueError("Invalid package inventory")
        for entry in entries:
            if entry.filename != MANIFEST:
                valid_name(entry.filename)
            if entry.file_size > FILE_LIMIT or entry.compress_type != zipfile.ZIP_STORED or entry.flag_bits & 1:
                raise ValueError("Unexpected package entry")
            if entry.date_time != STAMP or entry.external_attr >> 16 != mode(entry.filename):
                raise ValueError("Unexpected package metadata")
        if sum(entry.file_size for entry in entries) > LIMIT + FILE_LIMIT:
            raise ValueError("Package exceeds size limit")
        manifest = json.loads(archive.read(MANIFEST))
        if manifest.get("version") != 1 or not isinstance(manifest.get("files"), list):
            raise ValueError("Invalid package manifest")
        records = []
        for name in names:
            if name == MANIFEST:
                continue
            raw = archive.read(name)
            records.append({"path": name, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
        if records != manifest["files"] or hashlib.sha256(canonical(records)).hexdigest() != manifest.get("content_sha256"):
            raise ValueError("Package content does not match its manifest")
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    mode_group = parser.add_mutually_exclusive_group(required=True)
    mode_group.add_argument("--output", type=Path, help="New ZIP path; existing artifacts are never overwritten")
    mode_group.add_argument("--verify", type=Path, help="Verify without extracting or executing the archive")
    mode_group.add_argument("--check-inventory", action="store_true", help="Compare reviewed inventory with Git-visible source files")
    args = parser.parse_args()
    try:
        if args.verify:
            manifest = verify(args.verify)
            print(f"Verified {len(manifest['files'])} files; source identity {manifest['content_sha256']}")
        else:
            names = json.loads((args.root / "release/source-files.json").read_text(encoding="utf-8"))
            if args.check_inventory or (args.root / ".git").exists():
                check_inventory(args.root, names)
            if args.check_inventory:
                print(f"Reviewed inventory matches {len(names)} Git-visible files")
                return 0
            payload, manifest = create(args.root, names)
            if not re.fullmatch(r"[A-Za-z0-9._-]+\.zip", args.output.name):
                raise ValueError("Use a simple .zip output filename")
            checksum = args.output.with_suffix(args.output.suffix + ".sha256")
            if args.output.exists() or checksum.exists():
                raise ValueError("Output already exists; choose a new candidate name")
            args.output.parent.mkdir(parents=True, exist_ok=True)
            with args.output.open("xb") as file:
                file.write(payload)
            digest = hashlib.sha256(payload).hexdigest()
            with checksum.open("x", encoding="ascii", newline="\n") as file:
                file.write(f"{digest}  {args.output.name}\n")
            print(f"Packaged {len(manifest['files'])} reviewed files; ZIP SHA-256 {digest}")
        return 0
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        detail = f" {error}" if isinstance(error, ValueError) and str(error).startswith("Review") else ""
        print("Package failed: check the reviewed inventory, paths and output. No existing artifact was replaced." + detail)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
