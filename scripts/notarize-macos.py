#!/usr/bin/env python3
"""Sign, notarize and package a prepared Mac release; retries preserve Apple's submission ID."""
import argparse
import fcntl
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

from macos_bundle import validate_bundle_version, verify_archive


def run(*args):
    return subprocess.check_output(list(map(str, args)), text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, text):
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_text(text)
    temporary.replace(path)


def notarize(root, version, identity, profile, timeout='10m', submission_id=None):
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise RuntimeError('Expected a semantic release version')
    if submission_id is not None:
        submission_id = str(uuid.UUID(submission_id))
    revision = run('git', '-C', root, 'rev-parse', 'HEAD')
    if run('git', '-C', root, 'status', '--porcelain'):
        raise RuntimeError('Commit source changes before notarizing')
    dist = root / 'dist'
    cli_receipt = dist / f'agent-monitor-{version}-macos-arm64.commit'
    if not cli_receipt.exists() or cli_receipt.read_text().strip() != revision:
        raise RuntimeError('Run release.sh preparation for this committed revision first')
    name = f'agent-monitor-app-{version}-macos-arm64'
    archive = dist / f'{name}.zip'
    receipt = dist / f'{name}.commit'
    checksum = dist / f'{name}.zip.sha256'
    if archive.exists() and receipt.exists() and checksum.exists():
        if receipt.read_text().strip() != revision or checksum.read_text() != f'{digest(archive)}  {archive.name}\n':
            raise RuntimeError('Existing release archive receipts do not match; inspect them before retrying')
        verify_archive(archive, version)
        print(f'Already verified: {archive}')
        return

    stage = dist / f'macos-{version}'
    app = stage / 'Agent Monitor.app'
    source = stage / 'source.commit'
    if not stage.exists():
        original = root / '.build/Agent Monitor.app'
        validate_bundle_version(original, version)
        stage.mkdir()
        run('ditto', original, app)
        binary = app / 'Contents/MacOS/agent-monitor-menubar'
        shutil.copy2(binary, dist / f'{name}-unstripped')
        run('strip', binary)
        write(source, revision + '\n')
    if not source.exists() or source.read_text().strip() != revision:
        raise RuntimeError('Staged app has an incomplete or different source revision; inspect it before retrying')
    validate_bundle_version(app, version)
    submission = stage / 'submission.json'
    started = stage / 'submission-started.json'
    upload = stage / 'submission.zip'
    if submission_id:
        if not upload.exists():
            raise RuntimeError('Recovery requires the original submitted archive')
        if submission.exists() and json.loads(submission.read_text())['id'] != submission_id:
            raise RuntimeError('Recovery ID differs from the saved submission')
        write(submission, json.dumps({'id': submission_id}) + '\n')
    if not submission.exists():
        if started.exists():
            raise RuntimeError('Upload result is uncertain. Inspect notarytool history, then retry with --submission-id ID; do not submit again.')
        run('codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp',
            '--entitlements', root / 'scripts/macos-release.entitlements', app)
        run('codesign', '--verify', '--deep', '--strict', app)
        run('ditto', '-c', '-k', '--keepParent', app, upload)
        # An interrupted submit may have reached Apple; the marker prevents a duplicate upload.
        # Apple's recovery contract: https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
        write(started, json.dumps({'sha256': digest(upload), 'revision': revision}) + '\n')
        response = run('xcrun', 'notarytool', 'submit', upload, '--keychain-profile', profile, '--output-format', 'json')
        data = json.loads(response)
        uuid.UUID(data['id'])
        write(submission, response + '\n')
    saved_id = str(uuid.UUID(json.loads(submission.read_text())['id']))
    print(f'Notarization submission: {saved_id}', flush=True)
    status = json.loads(run('xcrun', 'notarytool', 'info', saved_id,
                            '--keychain-profile', profile, '--output-format', 'json'))['status']
    if status == 'In Progress':
        run('xcrun', 'notarytool', 'wait', saved_id, '--keychain-profile', profile, '--timeout', timeout)
        status = json.loads(run('xcrun', 'notarytool', 'info', saved_id,
                                '--keychain-profile', profile, '--output-format', 'json'))['status']
    log = stage / 'notary-log.json'
    run('xcrun', 'notarytool', 'log', saved_id, '--keychain-profile', profile, log)
    report = json.loads(log.read_text())
    if status != 'Accepted' or report['status'] != 'Accepted':
        raise RuntimeError(f'Notarization status: {status}; inspect {log}')
    if report['sha256'] != digest(upload):
        raise RuntimeError('Notarization log does not match the submitted archive')
    if report.get('issues'):
        print(json.dumps(report['issues'], indent=2), file=sys.stderr)
    run('xcrun', 'stapler', 'staple', app)
    run('xcrun', 'stapler', 'validate', app)
    candidate = stage / 'distribution.zip'
    if not candidate.exists():
        partial = stage / 'distribution.partial.zip'
        partial.unlink(missing_ok=True)
        run('ditto', '-c', '-k', '--keepParent', app, partial)
        verify_archive(partial, version)
        partial.replace(candidate)
    verify_archive(candidate, version)
    if archive.exists() and digest(archive) != digest(candidate):
        raise RuntimeError('Refusing to overwrite a different release archive')
    if not archive.exists():
        temporary = dist / f'.{name}.partial.zip'
        shutil.copy2(candidate, temporary)
        temporary.replace(archive)
    write(checksum, f'{digest(archive)}  {archive.name}\n')
    write(receipt, revision + '\n')
    print(f'Verified: {archive}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('version')
    parser.add_argument('--identity', required=True, help='Developer ID Application certificate SHA-1')
    parser.add_argument('--keychain-profile', default='agent-monitor-notary')
    parser.add_argument('--timeout', default='10m', help='Apple wait timeout; retry resumes the saved submission')
    parser.add_argument('--submission-id', help='Recover an interrupted upload using its Apple submission ID')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+', args.version):
        parser.error('expected a semantic release version')
    root = Path(__file__).resolve().parent.parent
    (root / 'dist').mkdir(exist_ok=True)
    with (root / 'dist' / f'.notarize-{args.version}.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Another notarization command is running for this version')
        notarize(root, args.version, args.identity, args.keychain_profile, args.timeout, args.submission_id)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'FAIL: {error}\nExisting submission records are preserved; resolve the error and rerun the same command.')
