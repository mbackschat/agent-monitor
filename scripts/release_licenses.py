"""Retain the notice index and locked dependency notices in distribution artifacts."""
import json
import shutil


def copy_licenses(root, destination):
    shutil.copy2(root / 'LICENSE', destination / 'LICENSE')
    shutil.copy2(root / 'THIRD_PARTY_NOTICES.md', destination / 'THIRD_PARTY_NOTICES.md')
    notices = destination / 'licenses'
    notices.mkdir()
    for dependency in json.loads((root / 'Package.resolved').read_text())['pins']:
        identity = dependency['identity']
        checkout = root / '.build/checkouts' / identity
        license_file = next((p for p in (checkout / 'LICENSE', checkout / 'LICENSE.txt') if p.is_file()), None)
        if license_file is None:
            raise FileNotFoundError(f'Missing license for {identity}')
        target = notices / identity
        target.mkdir()
        shutil.copy2(license_file, target / license_file.name)
        for path in checkout.glob('NOTICE*'):
            shutil.copy2(path, target / path.name)

    vendor = root / '.build/checkouts/swift-tui/Vendor'
    for pattern in ('*/LICENSE*', '*/NOTICE*'):
        for path in vendor.glob(pattern):
            target = notices / 'swift-tui/Vendor' / path.relative_to(vendor)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
    shutil.copytree(vendor / 'swift-figlet/Fonts', notices / 'swift-tui/Vendor/swift-figlet/Fonts')
    shutil.copy2(root / 'Package.resolved', notices / 'Package.resolved')
