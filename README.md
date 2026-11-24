# a3core / SM-A032F — SukiSU-Ultra + SuSFS v1.5.5 (V17)

Fork repozytorium [KernelSU_Action](https://github.com/xiaoleGun/KernelSU_action) przygotowany dla Samsung SM-A032F (a3core, LineageOS 21 / Android 14).

Dokumentacja oryginalnego actiona (angielska): [README_EN.md](README_EN.md)

## Gotowy build do pobrania

**[Release V17 — SukiSU-Ultra 3.0.0 + SuSFS v1.5.5](https://github.com/Artemis1447/A032F-KernelSU-SUSFS/releases/tag/a3core-v17-sukisu-susfs-20261124)**

- `v17-reboothook-AnyKernel3.zip` — 11 338 464 B, SHA256 `5671583df73b1b706165bb8bd7120efef7e849daacf72ebc8aad8b2c3326ef40`
- `Image` — sam obraz jądra, jeśli składasz własny boot.img
- Zweryfikowany CI: run `45299270122` (job `138127409056`), `pvrsrvkm ABI: 267/267 matched; 0 missing; 0 mismatched; 0 ambiguous`

## Co zawiera jądro

| Element | Wersja / ustawienie |
| --- | --- |
| Jądro | 4.14.199 (IverCoder/android_kernel_samsung_a3core, branch stable), pin `81da2968a777556d20847e30b618658905af67a3` |
| SukiSU-Ultra | `builtin`, pin `4bec532dd447e2852aa8932afa768255350c103a`, kernel full version `v3.0.0-4bec532d@HEAD` |
| SuSFS | `susfs4ksu/kernel-4.14`, pin `77905b5a071e6f3669e3b1814cea30147c0801da`, v1.5.5, NON-GKI |
| Hook | `SUSFS Inline Hook`, Zygisk Next 1.5.3 |
| Manager | SukiSU-Nova v3.0.0 (35000-6) |
| ABI | stock MODVERSIONS zachowany; `pvrsrvkm` 267/267; brak nowych pól w `task_struct` / `struct vfsmount` |

## Zatwierdzony zakres SuSFS

Włączone:

- `CONFIG_KSU_SUSFS_SUS_PATH`
- `CONFIG_KSU_SUSFS_SPOOF_UNAME`
- `CONFIG_KSU_SUSFS_ENABLE_LOG`
- `CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG`

Wyłączone:

- `SUS_MOUNT`, `SUS_KSTAT`, `OPEN_REDIRECT`, `SUS_MAP`, `PRIORITY_UID_FILTER`
- `HIDE_KSU_SUSFS_SYMBOLS` — `n`
- brak mapowania `susfs_set_current_proc_no_su`

Stan per-task jest przechowywany w `TIF_PROC_UMOUNTED`, bez zmiany layoutu struktur ABI. Funkcje spoza zatwierdzonego zakresu są jawnie wyłączone, nie są pseudo-stubami.

## Co zmieniła V17

1. **Bridge menedżera fd** — most Linux 4.14 `task_fix_setuid` → `ksu_handle_setresuid()`, dzięki któremu `ksud`/menedżer dostaje fd `anon_inode:[ksu_driver]`.
2. **ABI fix** — 24 odczyty markerów zastąpione przez `susfs_is_current_proc_umounted()`; pola zależne od mountów za `CONFIG_KSU_SUSFS_SUS_MOUNT`.
3. **Reboot hook** — minimalny hook w `kernel/reboot.c` przed bramką `CAP_SYS_BOOT`, pod `CONFIG_KSU && CONFIG_KSU_SUSFS`. Bez niego `ksud` nie instalował magic-fd dla SUSFS i karty SuSFS nie miały skąd otrzymać stanu.
4. **AnyKernel3 zawsze budowany** — usunięto martwy klucz `BUILD_ANYKERNEL3`; konfiguracje muszą być w allowliście `scripts/config.sh DEFAULTS`, inaczej CI cicho pomija krok.

## Jak wgrać

1. Pobierz `v17-reboothook-AnyKernel3.zip` z Release powyżej i zweryfikuj SHA256.
2. Wejdź w TWRP → Install → wybierz ZIP. Alternatywnie: `adb sideload` (jeśli TWRP go obsługuje).
3. Po restarcie używaj **SukiSU-Nova v3.0.0**. Nie używaj KernelSU Next — sygnatura nie pasuje (`Nie znaleziono sygnatury KernelSU Next v2 w jadrze!`).
4. Sprawdzenie: `uname -a` powinien pokazać `4.14.199-a3core-vendorabi-v17-sukisu-susfs` z buildem `Tue Nov 24 00:59:10 UTC 2026`; `adb root` + `id` daje `uid=0(root) ... context=u:r:su:s0`.
5. `ksud extension get susfs` → `Status: available`, `Extension ABI: 2`; `EXTENSION_LIST_V3` zawiera `susfs` z `api=2`.

### Uwaga dla TWRP

Jeśli instalator AnyKernel3 kończy się błędem `ash: inaccessible or not found` / `magiskboot: inaccessible or not found`, TWRP gubi `PATH`. Po rozpakowaniu zipa przed `ash anykernel.sh;` dodaj:

```sh
export PATH="$AKHOME/tools:$AKHOME/bin:$PATH"
```

i uruchom `/sbin/sh /tmp/updater 1 dummy /tmp/<zip> 2>&1`.

## Jak przebudować

1. Edytuj `config/a3core-a032f-v17-sukisu-susfs.env` i `scripts/config.sh`.
2. Uruchom workflow `.github/workflows/build-kernel.yml` albo wrzuć plik do `trigger13/`.
3. Artefakty pojawią się w runie; przed flashiem zawsze sprawdź SHA256 na urządzeniu.

## Znane ograniczenie UI

Urządzenie ma 32-bitowy userspace (`armeabi-v7a`, kernel `armv8l`). W tej architekturze `ksud` nie kompiluje komendy `susfs` (`error: unrecognized subcommand 'susfs'`), a `susfs_actually_working()` jest stałym `false`. Dlatego karty **SuSFS**, **KPM** i **CPU identity spoofing** w managerze pozostają `Unsupported`, mimo że kernel ma zarejestrowany extension SUSFS (`caps=0x11`, `api=2`). To ograniczenie userspace, nie defekt jądra. Nie dodajemy fałszywych stubów, żeby tylko zmienić etykietę w UI.

## Uwagi

- Play Integrity **STRONG** nie jest osiągalne na stałe. Realnym celem jest MEETS_DEVICE.
- Opis oryginalnego upstreamu był po chińsku — ten plik zastępuje go polskim opisem tego forką.
