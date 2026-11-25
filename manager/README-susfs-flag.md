# SukiSU Nova manager — SUSFS display flag patch

`SukiSU-manager-v3.0.0-susfs-flag.apk` is a patched copy of
`SukiSU-manager-v3.0.0.apk`.

## What changed

On the **Extension features** screen the SuSFS card showed `Unsupported`.
The V17 kernel advertises a live SUSFS handler through `ksud extension get
susfs` (`Status: available`, `Extension ABI: 2`, `reboot=1`), but `ksud
extension list` still emits a V3 row with `supported=0` for SusFS.

The patch changes only the pill selection for the card whose wire name is
`susfs`, so the visible label becomes `Supported`. It does **not** change root,
kernel, SUSFS configuration, extension values, toggles, or the home-card
SUSFS version logic.

## Verification

- Patched APK: SHA256
  `8FB1FE6AD44B0A5D196996B6441206931F8CFA6E653A0A41D45CD9D2A08B02D3`
- Original APK: SHA256
  `DFBC39B662A30419B408A97BFDB2EDC836B225A871BF12D38432B7266C104B4D`
- Signature: v2 + v3, signer certificate SHA-256
  `d862bdac843b8b6c16252df4c7dba58f0cda04c3bdbfc9ee6dbf7dc3faa0a362`

## Install note

The patched APK is signed with a new self-signed key because the original
manager signing key is not available. Android will not upgrade the installed
`com.sukisu.nova` over it with a different signature: uninstall the existing
manager first, then install this APK. The app's data (including SUSFS
configuration files under `/data/adb`) is not part of the APK and is not
changed by this patch.
