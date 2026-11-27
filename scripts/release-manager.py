#!/usr/bin/env python3
"""Stage the signed a3core manager or attach it to published GitHub releases."""

import argparse
import hashlib
import json
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.request import urlopen


APK = "SukiSU_Nova_v3.0.0_35000-armeabi-v7a-release.apk"
SHA256 = "dfbc39b662a30419b408a97bfdb2edc836b225a871bf12d38432b7266c104b4d"
UPSTREAM = f"https://github.com/SukiSU-Nova/SukiSU-Nova/releases/download/v3.0.0/{APK}"


def stage(directory):
    with urlopen(UPSTREAM, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise ValueError("Upstream APK differs from the verified SM-A032F manager")
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / APK
    target.write_bytes(data)
    return target


def github_items(endpoint):
    pages = subprocess.check_output(["gh", "api", "--paginate", "--slurp", f"{endpoint}?per_page=100"])
    return [item for page in json.loads(pages) for item in page]


def has_manager(release):
    for asset in github_items(release["assets_url"]):
        if asset["name"] == APK:
            if asset["state"] != "uploaded" or asset["digest"] != f"sha256:{SHA256}":
                raise ValueError(f"{release['tag_name']}: existing {APK} does not match; left untouched")
            return True
    return False


def sync(repository):
    with TemporaryDirectory() as temp:
        apk = None
        for release in github_items(f"repos/{repository}/releases"):
            if release["draft"]:
                continue
            tag = release["tag_name"]
            if not has_manager(release):
                if apk is None:
                    apk = stage(Path(temp))
                label = "SukiSU Nova Manager v3.0.0 (32-bit ARM, for SukiSU kernels)"
                if tag == "a3core-ksu-susfs-v12-20261123":
                    label = "SukiSU Nova Manager APK for V17/V19 only (incompatible with V12)"
                result = subprocess.run(["gh", "release", "upload", "--repo", repository, "--", tag, f"{apk}#{label}"])
                # A simultaneous upload may have won the name; accept only the same bytes.
                if not has_manager(release):
                    result.check_returncode()
                    raise RuntimeError(f"{tag}: GitHub did not return the uploaded manager")
            print(f"{tag}: verified {APK}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--stage", type=Path, metavar="DIRECTORY", help="include the APK before publishing")
    mode.add_argument("--sync", metavar="OWNER/REPO", help="verify published releases and fill missing assets")
    args = parser.parse_args()
    if args.stage:
        print(stage(args.stage))
    else:
        sync(args.sync)
