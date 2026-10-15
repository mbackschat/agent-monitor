#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# ///
"""Package and smoke-check an already-built Apple Silicon release."""

import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile


def run(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def public_archive_metadata(member):
    member.uid = member.gid = 0
    member.uname = member.gname = ""
    member.pax_headers = {}
    return member


def main():
    root = Path(__file__).resolve().parent.parent
    if not (root / "LICENSE").is_file():
        raise SystemExit("Choose and add the project LICENSE before packaging a public release")
    products = Path(sys.argv[1] if len(sys.argv) > 1 else root / ".build/release").resolve()
    binary = products / "agent-monitor"
    version = run(str(binary), "--version")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise SystemExit("Expected a semantic release version from --version")
    if run("lipo", "-archs", str(binary)) != "arm64":
        raise SystemExit("This release package supports Apple Silicon (arm64) only")

    name = f"agent-monitor-{version}-macos-arm64"
    output = root / "dist"
    output.mkdir(exist_ok=True)
    archive = output / f"{name}.tar.gz"
    if archive.exists():
        raise SystemExit(f"Refusing to overwrite {archive}; move the previous artifact first")

    with tempfile.TemporaryDirectory(prefix="agent-monitor-package-") as temporary:
        staged_archive = Path(temporary) / archive.name
        stage = Path(temporary) / name
        stage.mkdir()
        shutil.copy2(binary, stage / "agent-monitor")
        # Symbols are over half of the unstripped file (40.5 MB to 19.7 MB, measured 2026-10-15).
        # Keep the unstripped build to symbolicate crash reports. Xcode's strip re-signs the
        # linker's ad-hoc signature, which the archive check below verifies.
        subprocess.run(["strip", str(stage / "agent-monitor")], check=True)
        shutil.copytree(
            products / "AgentMonitor_AgentMonitorPresentation.bundle",
            stage / "AgentMonitor_AgentMonitorPresentation.bundle",
        )
        shutil.copy2(root / "LICENSE", stage / "LICENSE")
        shutil.copy2(root / "THIRD_PARTY_NOTICES.md", stage / "THIRD_PARTY_NOTICES.md")
        notices = stage / "licenses"
        notices.mkdir()
        for dependency in json.loads((root / "Package.resolved").read_text())["pins"]:
            identity = dependency["identity"]
            checkout = root / ".build/checkouts" / identity
            candidates = [checkout / "LICENSE", checkout / "LICENSE.txt"]
            license_file = next((path for path in candidates if path.is_file()), None)
            if license_file is None:
                raise SystemExit(f"Missing license for {identity}")
            destination = notices / identity
            destination.mkdir()
            shutil.copy2(license_file, destination / license_file.name)
            for path in checkout.glob("NOTICE*"):
                shutil.copy2(path, destination / path.name)

        vendor = root / ".build/checkouts/swift-tui/Vendor"
        for pattern in ("*/LICENSE*", "*/NOTICE*"):
            for path in vendor.glob(pattern):
                destination = notices / "swift-tui/Vendor" / path.relative_to(vendor)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, destination)
        shutil.copytree(
            vendor / "swift-figlet/Fonts", notices / "swift-tui/Vendor/swift-figlet/Fonts"
        )
        shutil.copy2(root / "Package.resolved", notices / "Package.resolved")
        (stage / "INSTALL.txt").write_text(
            f"Agent Monitor {version} — macOS 27+, Apple Silicon\n\n"
            "From this extracted directory:\n"
            '  mkdir -p "$HOME/.local/bin"\n'
            '  install -m 755 agent-monitor "$HOME/.local/bin/agent-monitor"\n'
            '  cp -R AgentMonitor_AgentMonitorPresentation.bundle "$HOME/.local/bin/"\n'
            '  export PATH="$HOME/.local/bin:$PATH"\n'
            "  agent-monitor --version\n"
            "  agent-monitor --tui --group session\n\n"
            "Keep the schema bundle beside the executable.\n"
            "Preserve LICENSE, THIRD_PARTY_NOTICES.md and licenses/\n"
            "when redistributing this package. This binary is ad-hoc signed, not notarized.\n"
            "If macOS blocks it, the repository provides source-build instructions.\n"
            "https://github.com/mbackschat/agent-monitor/blob/main/docs/installation.md\n"
        )
        with tarfile.open(staged_archive, "w:gz") as package:
            package.add(stage, arcname=name, filter=public_archive_metadata)
        unpacked = Path(temporary) / "verify"
        with tarfile.open(staged_archive) as package:
            if any((entry.uid, entry.gid, entry.uname, entry.gname) != (0, 0, "", "") for entry in package):
                raise SystemExit("Release archive contains local account metadata")
            package.extractall(unpacked, filter="data")
        installed = unpacked / name
        executable = installed / "agent-monitor"
        subprocess.run(["codesign", "--verify", "--strict", str(executable)], check=True)
        if run("nm", "-U", str(executable)).split("\n") != ["0000000100000000 T __mh_execute_header"]:
            raise SystemExit("Packaged executable still carries its symbol table")
        environment = dict(os.environ, PATH=f"{installed}:/usr/bin:/bin")
        if run("agent-monitor", "--version", cwd=unpacked, env=environment) != version:
            raise SystemExit("Packaged executable reports the wrong version")
        if "USAGE: agent-monitor" not in run(
            "agent-monitor", "--help", cwd=unpacked, env=environment
        ):
            raise SystemExit("Packaged executable help check failed")
        schema = json.loads(run("agent-monitor", "--json-schema", cwd=unpacked, env=environment))
        if "$schema" not in schema:
            raise SystemExit("Packaged JSON Schema check failed")
        shutil.copy2(staged_archive, archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum = archive.with_suffix(archive.suffix + ".sha256")
    checksum.write_text(f"{digest}  {archive.name}\n")
    print(f"Verified {archive}\nChecksum: {checksum}")


if __name__ == "__main__":
    main()
