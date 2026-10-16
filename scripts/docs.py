#!/usr/bin/env python3
"""Check and maintain documentation links, folder indices and status tables.

check   report broken relative links/anchors, unindexed or undated docs and status drift
sync    regenerate the status tables in status folders from each document's Status line
status  set a document's status keyword and date, then sync
"""

import argparse
import datetime
import os
import pathlib
import re
import sys
import urllib.parse

# Each status folder's README owns a generated table; the vocabulary keeps a retired design out of
# proposals/ (see docs/development.md, documentation and instruction maintenance).
STATUS_FOLDERS = {
    "docs/proposals": ("Proposal", ["approved", "unapproved", "on hold"]),
    "docs/decisions": ("Decision", ["deferred", "rejected", "superseded"]),
}
# Index entries that must carry the date explaining them: when evidence was gathered or a version
# was published. Release notes also state their own publication date.
DATED_INDEXES = {"docs/research", "docs/releases"}
RELEASE_FOLDER = "docs/releases"
RELEASED_LINE = re.compile(r"^Released (\d{4}-\d{2}-\d{2})\.$")
DATE = re.compile(r"\d{4}-\d{2}-\d{2}")
# Folders whose files are referenced by documents rather than navigated as documents.
UNINDEXED_FOLDERS = {"docs/assets"}
TABLE_BEGIN = "<!-- status-table:begin -->"
TABLE_END = "<!-- status-table:end -->"
STATUS_LINE = re.compile(r"^Status: \*\*(?P<keyword>[a-z ]+)\*\*, (?P<date>\d{4}-\d{2}-\d{2})\.(?P<rest>.*)$")
HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*#*\s*$")
LINK = re.compile(r"!?\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
HTML_ANCHOR = re.compile(r"<a\s+(?:id|name)=\"([^\"]+)\"")
SKIPPED_DIRECTORIES = {"node_modules"}


def markdown_files(root):
    for directory, subdirectories, files in os.walk(root):
        subdirectories[:] = sorted(
            name
            for name in subdirectories
            if not name.startswith(".") and name not in SKIPPED_DIRECTORIES
            and not os.path.islink(os.path.join(directory, name))
        )
        for name in sorted(files):
            path = pathlib.Path(directory, name)
            if name.endswith(".md") and not path.is_symlink():
                yield path


def prose_lines(text):
    """Yield (line number, line) outside fenced code, with inline code spans removed."""
    fence = None
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        marker = stripped[:3]
        if marker in ("```", "~~~"):
            fence = None if fence == marker else (fence or marker)
            continue
        if fence is None:
            yield number, re.sub(r"`[^`]*`", "", line)


def slug(heading):
    """GitHub's heading anchor: drop link syntax and punctuation, lowercase, spaces to hyphens."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading).strip().lower()
    return re.sub(r"[^\w\- ]", "", text).replace(" ", "-")


def anchors(path, cache):
    if path not in cache:
        found, counts = set(), {}
        for _, line in prose_lines(path.read_text(encoding="utf-8")):
            found.update(HTML_ANCHOR.findall(line))
            match = HEADING.match(line)
            if match:
                base = slug(match.group(2))
                count = counts.get(base, 0)
                counts[base] = count + 1
                found.add(base if count == 0 else f"{base}-{count}")
        cache[path] = found
    return cache[path]


def check_links(root, path, cache):
    errors = []
    for number, line in prose_lines(path.read_text(encoding="utf-8")):
        for target in LINK.findall(line):
            if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.IGNORECASE):
                continue
            file_part, _, fragment = urllib.parse.unquote(target).partition("#")
            destination = (path.parent / file_part).resolve() if file_part else path
            location = f"{path.relative_to(root)}:{number}"
            if not destination.exists():
                errors.append(f"{location}: link target {target} does not exist")
            elif fragment and destination.suffix == ".md" and fragment not in anchors(destination, cache):
                errors.append(f"{location}: anchor #{fragment} not found in {file_part or path.name}")
    return errors


def linked_paths(readme):
    paths = set()
    for _, line in prose_lines(readme.read_text(encoding="utf-8")):
        for target in LINK.findall(line):
            file_part = urllib.parse.unquote(target).partition("#")[0]
            if file_part and not re.match(r"^[a-z][a-z0-9+.-]*:", file_part, re.IGNORECASE):
                paths.add((readme.parent / file_part).resolve())
    return paths


def check_indices(root):
    errors = []
    docs = root / "docs"
    if not docs.is_dir():
        return errors
    folders = [docs] + sorted(path for path in docs.rglob("*") if path.is_dir())
    for folder in folders:
        relative = folder.relative_to(root).as_posix()
        if any(relative == skipped or relative.startswith(skipped + "/") for skipped in UNINDEXED_FOLDERS):
            continue
        readme = folder / "README.md"
        if not readme.exists():
            errors.append(f"{relative}: missing README.md index")
            continue
        linked = linked_paths(readme)
        for entry in sorted(folder.iterdir()):
            if entry.name.startswith(".") or entry == readme:
                continue
            entry_relative = entry.relative_to(root).as_posix()
            if entry.is_dir() and entry_relative in UNINDEXED_FOLDERS:
                continue
            candidates = {entry.resolve(), (entry / "README.md").resolve()} if entry.is_dir() else {entry.resolve()}
            if not candidates & linked:
                errors.append(f"{relative}/README.md: does not link {entry.name}")
    return errors


def documents(root, folder):
    """Status documents of a folder as (path, title, keyword, date) or an error string."""
    result = []
    for path in sorted((root / folder).glob("*.md")):
        if path.name == "README.md":
            continue
        lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
        title = lines[0][2:].strip() if lines and lines[0].startswith("# ") else None
        status = STATUS_LINE.match(lines[1]) if len(lines) > 1 else None
        relative = path.relative_to(root).as_posix()
        if title is None or status is None:
            result.append(f"{relative}: needs '# Title' followed by 'Status: **keyword**, YYYY-MM-DD. ...'")
        else:
            result.append((path, title, status.group("keyword"), status.group("date")))
    return result


def status_table(root, folder):
    label, vocabulary = STATUS_FOLDERS[folder]
    rows = [entry for entry in documents(root, folder) if not isinstance(entry, str)]
    order = {keyword: index for index, keyword in enumerate(vocabulary)}
    rows.sort(key=lambda row: (order.get(row[2], len(order)), row[1].lower()))
    lines = [f"| {label} | Status | Since |", "| --- | --- | --- |"]
    lines += [f"| [{title}]({path.name}) | {keyword} | {date} |" for path, title, keyword, date in rows]
    return "\n".join(lines)


def replace_table(text, table):
    begin, end = text.find(TABLE_BEGIN), text.find(TABLE_END)
    if begin < 0 or end < begin:
        return None
    return text[: begin + len(TABLE_BEGIN)] + "\n" + table + "\n" + text[end:]


def check_status(root):
    errors = []
    for folder, (_, vocabulary) in STATUS_FOLDERS.items():
        if not (root / folder).is_dir():
            continue
        for entry in documents(root, folder):
            if isinstance(entry, str):
                errors.append(entry)
            elif entry[2] not in vocabulary:
                errors.append(
                    f"{entry[0].relative_to(root)}: status '{entry[2]}' is not one of {', '.join(vocabulary)}")
        readme = root / folder / "README.md"
        if readme.exists():
            text = readme.read_text(encoding="utf-8")
            expected = replace_table(text, status_table(root, folder))
            if expected is None:
                errors.append(f"{folder}/README.md: missing {TABLE_BEGIN} ... {TABLE_END} markers")
            elif expected != text:
                errors.append(f"{folder}/README.md: status table is out of date; run python3 scripts/docs.py sync")
    return errors


def released_date(path):
    lines = [line for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    match = RELEASED_LINE.match(lines[1]) if len(lines) > 1 else None
    return match.group(1) if match else None


def check_dates(root):
    errors = []
    for folder in sorted(DATED_INDEXES):
        readme = root / folder / "README.md"
        if not readme.exists():
            continue
        for number, line in prose_lines(readme.read_text(encoding="utf-8")):
            for target in LINK.findall(line):
                path = (readme.parent / urllib.parse.unquote(target).partition("#")[0]).resolve()
                if path.parent != readme.parent.resolve() or not path.is_file() or path == readme.resolve():
                    continue
                location = f"{folder}/README.md:{number}"
                if folder == RELEASE_FOLDER and path.suffix == ".md":
                    date = released_date(path)
                    if date is None:
                        errors.append(f"{folder}/{path.name}: needs 'Released YYYY-MM-DD.' after its title")
                    elif date not in line:
                        errors.append(f"{location}: entry for {path.name} must show its release date {date}")
                elif not DATE.search(line):
                    errors.append(f"{location}: entry for {path.name} needs the date of its evidence")
    return errors


def check(root):
    root = pathlib.Path(root).resolve()
    errors, cache = [], {}
    for path in markdown_files(root):
        errors += check_links(root, path, cache)
    return errors + check_indices(root) + check_status(root) + check_dates(root)


def sync(root):
    root = pathlib.Path(root).resolve()
    changed = []
    for folder in STATUS_FOLDERS:
        readme = root / folder / "README.md"
        if not readme.exists():
            continue
        text = readme.read_text(encoding="utf-8")
        updated = replace_table(text, status_table(root, folder))
        if updated is not None and updated != text:
            readme.write_text(updated, encoding="utf-8")
            changed.append(readme)
    return changed


def set_status(root, path, keyword, date):
    root, path = pathlib.Path(root).resolve(), pathlib.Path(path).resolve()
    folder = path.parent.relative_to(root).as_posix()
    if folder not in STATUS_FOLDERS:
        raise ValueError(f"{path.name} is not in a status folder: {', '.join(STATUS_FOLDERS)}")
    vocabulary = STATUS_FOLDERS[folder][1]
    if keyword not in vocabulary:
        raise ValueError(f"'{keyword}' is not a {folder} status; use one of {', '.join(vocabulary)}")
    datetime.date.fromisoformat(date)
    lines = path.read_text(encoding="utf-8").split("\n")
    for index, line in enumerate(lines):
        match = STATUS_LINE.match(line)
        if match:
            lines[index] = f"Status: **{keyword}**, {date}.{match.group('rest')}"
            path.write_text("\n".join(lines), encoding="utf-8")
            sync(root)
            return
    raise ValueError(f"{path.name} has no 'Status: **keyword**, YYYY-MM-DD.' line")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check")
    commands.add_parser("sync")
    status = commands.add_parser("status")
    status.add_argument("path")
    status.add_argument("keyword")
    status.add_argument("--date", default=datetime.date.today().isoformat())
    args = parser.parse_args()
    root = pathlib.Path(__file__).resolve().parent.parent
    if args.command == "check":
        errors = check(root)
        for error in errors:
            print(f"FAIL: {error}")
        print("OK: documentation links, indices and status tables" if not errors else f"{len(errors)} problem(s)")
        return 1 if errors else 0
    if args.command == "sync":
        for path in sync(root):
            print(f"updated {path.relative_to(root)}")
        return 0
    try:
        set_status(root, args.path, args.keyword, args.date)
    except ValueError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
