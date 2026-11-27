# A03 Core V19 EXTREME

**The most thoroughly validated Galaxy A03 Core kernel in this project.** V19 combines targeted latency work with the original vendor GPU ABI, and backs it up with two verified Android boots and 60 measured cold Settings launches on the **Samsung Galaxy A03 Core SM-A032F**.

[**Download V19 build artifacts**](https://github.com/Artemis1447/A032F-V19-EXTREME/actions/runs/45915725325#artifacts) · [**Benchmarks and validation**](docs/v19-validation.md) · [**Build, install and roll back**](V19.md) · [**V17 recovery baseline**](https://github.com/Artemis1447/A032F-V19-EXTREME/releases/tag/a3core-v17-sukisu-susfs-20261124)

## The headline numbers

| Metric on the reference SM-A032F | V19 EXTREME |
|---|---:|
| Settled Settings cold launch at 15 minutes | **993 ms median / 1,024 ms p95** |
| Fastest measured V19 cold launch | **975 ms** |
| Settings scroll frame time, p95 | **12 ms** |
| Janky frames in the measured scroll | **0 / 423** |
| Stock PowerVR symbol-version checks | **267 / 267 passed** |

V19 also brought direct eMMC read and LZO-RLE write medians back within the range observed on V17. Results are from one handset; the 15-minute run has no matched V17/V18 comparator, and the historical 743–800 ms target was not reached. [See the full comparison and tradeoffs.](docs/v19-validation.md)

## Built for this hardware

| Component | V19 target |
|---|---|
| Device | **SM-A032F (`a3core`)**, Unisoc SC9863A, Cortex-A55 |
| Tested ROM | LineageOS 21 / Android 14, **32-bit ARM userspace** |
| Kernel | **Linux 4.14.199**, arm64, Samsung stock-derived |
| Graphics | Stock PowerVR Rogue `pvrsrvkm`; byte-identical V17 `Module.symvers` |
| Root and filesystem extension | **SukiSU-Ultra** with **SUSFS v1.5.5, extension ABI 2** |
| Build | Android Clang **11.0.1 (`r383902`)**; pinned source, strict patch application and artifact checksums |

### What makes V19 different

- **Lean graphics allocation:** ION no longer allocates and frees a temporary descriptor for each buffer chunk. It also drops per-buffer diagnostic logging from the allocation path.
- **Less work on the hot paths:** ZRAM publishes successful writes under its existing slot lock. Schedutil skips a redundant retry wakeup when a saturated frequency vote is already satisfied. LZO-RLE remains the active compressor on the tested ROM.
- **Cleaner boot:** The alternate Novatek probe's cleanup was fixed. The V18 `devm_kfree` warning was absent from the captured V19 boot, and the selected touchscreen driver registered.
- **Stock compatibility:** Existing clock limits, thermal protection, and proprietary GPU driver stay in place. On-device checks confirmed SELinux **Enforcing**, working `su`, SUSFS ABI 2, and a live PowerVR driver.

## Download and build

The verified [V19 Actions run](https://github.com/Artemis1447/A032F-V19-EXTREME/actions/runs/45915725325#artifacts) provides the raw `Image`, a device-scoped AnyKernel3 ZIP, integrated kernel source, a build manifest and SHA-256 checksums. Actions artifacts have **14-day retention**; if unavailable, dispatch a new build using the checked-in profile. `Image` is a kernel binary, not a complete Android Boot image. The hardware test used the repacked full Boot image through TWRP; the independently packaged AnyKernel3 ZIP was verified offline and was not used for that test.

Build from **Actions → Build Kernel → Run workflow → `main`**. The default dispatch profile is [`config/a3core-a032f-v19-extreme.env`](config/a3core-a032f-v19-extreme.env). [Installation and rollback instructions](V19.md) explain how to preserve your own complete V17 Boot backup. Use the manager for SukiSU-Ultra; the build is not a KernelSU Next build.

## Project history and documentation

- **V19 EXTREME:** current source and build profile on `main`; [`v19-extreme`](https://github.com/Artemis1447/A032F-V19-EXTREME/tree/v19-extreme) retains the development history.
- **V18:** [stock-derived comparison build and results](V18.md).
- **V17:** [published baseline and known-good rollback reference](https://github.com/Artemis1447/A032F-V19-EXTREME/releases/tag/a3core-v17-sukisu-susfs-20261124).
- **Build system:** [general workflow documentation](README_EN.md), based on [KernelSU Action](https://github.com/xiaoleGun/KernelSU_action). Kernel source: [IverCoder's Samsung A03 Core tree](https://github.com/IverCoder/android_kernel_samsung_a3core).
