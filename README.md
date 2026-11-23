# a3core / SM-A032F — KernelSU + SUSFS

Fork repozytorium [KernelSU_Action](https://github.com/xiaoleGun/KernelSU_action) przygotowany dla Samsung SM-A032F (a3core, LineageOS 21 / Android 14).

Dokumentacja oryginalnego actiona (angielska): [README_EN.md](README_EN.md)

## Gotowy build do pobrania

**[Release v12 — KernelSU v0.9.5 + SUSFS v1.5.5](https://github.com/Artemis1447/KernelSU_Action/releases/tag/a3core-ksu-susfs-v12-20261123)**

- `AnyKernel3-KernelSU_v0.9.5-a3core-ksu-susfs-202611231532.zip` — plik do wgrania przez TWRP lub `adb sideload`
- `Image` — sam obraz jądra (jeśli składasz własny boot.img)

## Co zawiera jądro

| Element | Wersja / ustawienie |
| --- | --- |
| Jądro | 4.14.199 (IverCoder/android_kernel_samsung_a3core, branch stable) |
| KernelSU | tiann/KernelSU v0.9.5 (built-in) |
| SUSFS | susfs4ksu kernel-4.14, v1.5.5, NON-GKI |
| Aktywne funkcje | SUS_PATH, TRY_UMOUNT, OPEN_REDIRECT, SUS_KSTAT, SPOOF_UNAME, SPOOF_CMDLINE, HIDE_KSU_SUSFS_SYMBOLS |
| Wyłączone | SUS_MOUNT i AUTO_ADD_* (konflikt guardów w patchu 4.14) |

## Jak wgrać

1. Pobierz AnyKernel3 ZIP z linku wyżej.
2. Wejdź w TWRP → Install → wybierz ZIP → flash. Alternatywnie: `adb sideload plik.zip`.
3. Po restarcie zainstaluj oficjalnego menedżera KernelSU **v0.9.5** (`me.weishu.kernelsu`). Nie używaj KernelSU Next — nie pasuje do tej wersji jądra.
4. Dodaj ponownie Zygisk Next / PIF, jeśli używasz.
5. Sprawdzenie: `adb shell 'grep -ci susfs /proc/kallsyms'` powinno dać wartość > 0.

## Jak przebudować

1. Edytuj `config/a3core-a032f-v12.env`.
2. Uruchom workflow **Run a3core v12** (`.github/workflows/run-a3core10.yml`) albo wrzuć plik do `trigger10/`.
3. Artefakty pojawią się w runie. `publish-existing.yml` + `publish-trigger/run.txt` publikują je jako Release.

## Uwagi

- Play Integrity **STRONG** nie jest osiągalne na stałe. Realnym celem jest MEETS_DEVICE.
- Opis oryginalnego upstreamu był po chińsku — ten plik zastępuje go polskim opisem tego forką.
