#!/system/bin/sh
# Run with `adb -s SERIAL shell -T su -c sh` using this file as stdin.
set -eu
[ "$(id -u)" = 0 ] && [ "$(getprop ro.product.model)" = SM-A032F ]
[ "$(getprop ro.product.device)" = a3core ] && [ "$(getprop sys.boot_completed)" = 1 ]
case "$(uname -r)" in
    4.14.199-a3core-vendorabi-v1[78]-sukisu-susfs) ;;
    *) exit 1 ;;
esac
uname -a
id
getenforce
/data/adb/ksud extension get susfs
grep -w pvrsrvkm /proc/modules
printf 'loaded_modules='; cut -d' ' -f1 /proc/modules | sort | tr '\n' ' '; echo
cat /sys/class/devfreq/60000000.gpu/device/uevent
for p in /sys/devices/system/cpu/cpufreq/policy*; do
    echo "$p: $(cat "$p/affected_cpus") $(cat "$p/scaling_governor") $(cat "$p/scaling_available_frequencies")"
done
for service in SurfaceFlinger activity; do service check "$service"; done
for z in /sys/class/thermal/thermal_zone*; do
    echo "$(cat "$z/type") $(cat "$z/temp" 2>/dev/null || echo unavailable) $(cat "$z/policy")"
done
for d in /sys/devices/system/cpu/cpu0/cpuidle/state*; do
    echo "$(cat "$d/name") latency_us=$(cat "$d/latency") usage=$(cat "$d/usage")"
done

# An aligned direct read bypasses the Linux page cache. Read only from the
# parent eMMC; the payload is discarded. Controller caches are not flushed.
bb=/data/adb/ksu/bin/busybox
[ -x "$bb" ]
for run in 1 2 3 4 5; do
    start=$(date +%s%N)
    "$bb" dd if=/dev/block/mmcblk0 of=/dev/null bs=1M count=16 iflag=direct status=none
    echo "emmc_16MiB_read_ns=$(( $(date +%s%N) - start ))"
done

# Exercise both available fast compressors on an independent 8 MiB device.
# Never write to an active swap device or change its compressor.
work=$(mktemp -d /data/local/tmp/a3core-v18-check.XXXXXX)
index=
cleanup() {
    if [ -n "$index" ]; then echo "$index" > /sys/class/zram-control/hot_remove; fi
    rm -f "$work/input" "$work/zram-test-device"
    rmdir "$work"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
case "$(cat /proc/swaps)" in *'/dev/block/zram0 '*) ;; *) exit 1 ;; esac
# The same read-only ROM file on both kernels supplies identical page contents.
"$bb" dd if=/system/framework/framework.jar of="$work/input" bs=4096 count=2048 status=none
[ "$(stat -c %s "$work/input")" = 8388608 ]
expected=$(sha256sum "$work/input" | cut -d' ' -f1)
echo "zram.input_sha256=$expected"
id_new=$(cat /sys/class/zram-control/hot_add)
case "$id_new" in ''|0|*[!0-9]*) exit 1 ;; esac
index=$id_new
sys=/sys/block/zram$index
dev=/dev/block/zram$index
for retry in 1 2 3; do [ ! -b "$dev" ] || break; sleep 1; done
if [ ! -b "$dev" ]; then
    numbers=$(cat "$sys/dev")
    dev=$work/zram-test-device
    mknod "$dev" b "${numbers%:*}" "${numbers#*:}"
fi
[ -b "$dev" ] && [ "$(cat "$sys/disksize")" = 0 ]
for algorithm in lzo-rle lz4; do
    echo "$algorithm" > "$sys/comp_algorithm"
    echo 8388608 > "$sys/disksize"
    for run in 1 2 3; do
        start=$(date +%s%N)
        "$bb" dd if="$work/input" of="$dev" bs=4096 count=2048 oflag=direct conv=notrunc status=none
        elapsed=$(( $(date +%s%N) - start ))
        echo "zram_${algorithm}_8MiB_write_ns=$elapsed"
    done
    actual=$("$bb" dd if="$dev" bs=4096 count=2048 iflag=direct status=none | sha256sum | cut -d' ' -f1)
    [ "$actual" = "$expected" ] || { echo 'zram readback differs'; exit 1; }
    echo "zram_$algorithm readback=match mm_stat=$(cat "$sys/mm_stat")"
    echo 1 > "$sys/reset"
done
echo "active_swap=$(cat /sys/block/zram0/comp_algorithm) $(cat /sys/block/zram0/disksize)"

# Short repeatable GPU/UI load; keep the frame counts for scale as well as %.
am start -W -a android.settings.SETTINGS >/dev/null
sleep 2
dumpsys gfxinfo com.android.settings reset >/dev/null
for pair in 1 2 3 4 5 6 7 8; do
    input swipe 360 1250 360 450 400
    input swipe 360 450 360 1250 400
done
dumpsys gfxinfo com.android.settings | grep -E 'Total frames rendered:|Janky frames:|50th percentile:|90th percentile:|95th percentile:|99th percentile:'
input keyevent KEYCODE_HOME
for z in /sys/class/thermal/thermal_zone*; do
    echo "after_scroll $(cat "$z/type") $(cat "$z/temp" 2>/dev/null || echo unavailable)"
done
