# V19 EXTREME: validation on the SM-A032F

V19 was tested on one Galaxy A03 Core running LineageOS 21 (Android 14, ARM32 userspace) with the stock PowerVR Rogue driver. The tested build is [Actions run 45915725325](https://github.com/Artemis1447/A032F-V19-EXTREME/actions/runs/45915725325), recipe commit `6e8865fb67521923ada8aa3814ae9a47c80d4638`. The documentation and build-dispatch changes on `main` do not alter that image's source patches or profile.

## Settings launch and rendering

Each launch window contained 12 measured process-cold `am start -W` launches. The four- and seven-minute windows used the same handset and ROM. There were two measured V17 boots, one V18 boot, and two V19 boots. p95 is the nearest-rank percentile; with 12 samples it equals the largest observed time in that window.

| Cold Settings launch | V17 median / p95 | V18 median / p95 | V19 median / p95 |
|---|---:|---:|---:|
| 4 minutes after boot | 1,035–1,045 / 1,128–1,347 ms | 1,030 / 1,266 ms | **1,024–1,032 / 1,104–1,117 ms** |
| 7 minutes after boot | 1,011.5–1,025 / 1,035–1,039 ms | 1,001.5 / 1,023 ms | **1,000–1,002 / 1,030–1,044 ms** |
| 15 minutes after boot | Not measured | Not measured | **993 / 1,024 ms** |

Pooling the 4- and 7-minute windows across both boots gives **1,029 → 1,012.5 ms** from V17 to V19 (48 launches per kernel, **16.5 ms or 1.6% lower**). Pooled p95 was essentially unchanged (**1,102 → 1,103 ms**). V19's minimum was **975 ms** in the 15-minute series. The 743–800 ms historical target was not reached. Small gaps between kernels should be read alongside differences in device temperature and background paging.

Settings scroll HWUI p95 went **19 → 12 ms**, a **7 ms or 37% reduction** versus V17's first run (1 janky frame out of 424 → 0 out of 423). V17's repeat run and V18 already measured 12 ms p95. This is a short Settings workload, not a gaming or battery-life result.

## Memory and storage

| On-device check | V17, two observed runs | V18 | V19 |
|---|---:|---:|---:|
| 16 MiB direct eMMC read, median | 107.44–112.43 ms | 113.13 ms | **110.20 ms** |
| 8 MiB LZO-RLE write, median | 143.12–151.47 ms | 153.28 ms | **144.16 ms** |
| 8 MiB LZ4 write, median | 147.88–156.43 ms | 156.34 ms | **149.51 ms** |

Compared with V18, V19 cut the direct eMMC read median by **2.93 ms (2.6%)** and the LZO-RLE write median by **9.12 ms (6.0%)**, bringing both back within the observed V17 range. ZRAM readback matched for both codecs. The production compressor was LZO-RLE. A separate F2FS file test produced a slightly faster direct read (79.76 → 76.02 ms) and a slower fsync write (137.76 → 144.82 ms) versus the second V17 boot. V19 began the bounded 60-second CPU load cooler than the other builds, so peak temperatures do not establish a power or thermal improvement.

## Build and boot checks

- Android Clang **11.0.1 `r383902`**, pinned kernel/SukiSU/SUSFS inputs, strict patch application, and embedded kernel configuration consistent with V17 apart from `CONFIG_LOCALVERSION`.
- **267/267** stock `pvrsrvkm` CRCs matched; the complete `Module.symvers` matched V17 byte-for-byte. This checks the stock GPU ABI; the pre-existing optional `incrementalfs` symbol-version mismatch remains.
- A full Boot-only installation in TWRP was verified by SHA-256 readback. Android booted twice with SELinux Enforcing, working SukiSU root, SUSFS extension ABI 2, SurfaceFlinger and Activity Manager available, and `pvrsrvkm` loaded. Recovery, DTBO and vbmeta hashes matched V17.
- The selected touch driver registered. The alternate Novatek probe still reported its missing firmware-name property; the V18 cleanup warning did not recur in the captured V19 boot. Physical touch input was not independently measured.
- The AnyKernel3 ZIP was checked against the same raw `Image`. The installed package in the device test was the separately repacked full Boot image, not the ZIP.

## What still limits Settings launch

Three later V19 userspace traces measured a **518 ms median** from preferences ready to first display. The Settings main thread spent a median **397 ms on-CPU** and about **1–2 ms runnable but off-CPU** during that interval. Matched synchronous Binder calls accounted for **37–43 ms** of elapsed time within the gap, and the longest matched fence wait on any captured thread was **6.47 ms**. Per-layer SurfaceFlinger timing was unavailable, and the individual Settings methods responsible for its CPU time were not identified.

The phone retained its original animation scales (`0.5`) and `vm.swappiness=140`. The ROM's `/system/bin/phh-on-boot.sh` writes 140 after `sys.boot_completed=1`; early test windows that read back 140 after being assigned 100 were excluded as swappiness treatment samples. No persistent userspace tweak is part of V19.

## Verify the downloaded files

| File from the verified run | SHA-256 |
|---|---|
| `Image` | `76c4fe051d4c57c6275e82e4bb4840bf4b7a0e6d02a4833ad7f0e8c565a632c7` |
| `AnyKernel3-V19-20261127T001623Z-45915725325-1.zip` | `c41270d9edabd77db753dc33500efd8b88ea694fe8be7b998050bea4cccfd6aa` |
| `v19-source.tar.gz` | `1372ef17cabb39339c0599f261c189481651ca9bd83592cddf809ae2579e6715` |

These digests identify the specified run only. For any later build, use that run's `SHA256SUMS.txt` and `manifest.json`. [Back to the build, installation and rollback guide.](../V19.md)
