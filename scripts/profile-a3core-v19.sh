#!/system/bin/sh
# Run AFTER launch benchmarks; private trace instance, disposable userdata file.
set -eu
[ "$(id -u)" = 0 ] && [ "$(getprop ro.product.model)" = SM-A032F ]
[ "$(getprop ro.product.device)" = a3core ] && [ "$(getprop sys.boot_completed)" = 1 ]
uname -r
d=$(mktemp -d /data/local/tmp/a3core-profile.XXXXXX)
t=/sys/kernel/tracing/instances/a3core-profile-$$
owned_trace=0
cleanup() {
    if [ "$owned_trace" = 1 ]; then
        echo 0 > "$t/tracing_on"
        echo 0 > "$t/events/sched/sched_migrate_task/enable"
        rmdir "$t"
    fi
    rm -f "$d/output" "$d/trace" "$d/tids"
    rmdir "$d"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$t"
owned_trace=1
echo 0 > "$t/tracing_on"
echo 256 > "$t/buffer_size_kb"
echo 1 > "$t/events/sched/sched_migrate_task/enable"
input keyevent KEYCODE_WAKEUP
wm dismiss-keyguard
am force-stop --user 0 com.android.settings
sleep 1
echo 1 > "$t/tracing_on"
am start -W --user 0 -a android.settings.SETTINGS
echo 0 > "$t/tracing_on"
pid=$(pidof com.android.settings)
ls "/proc/$pid/task" > "$d/tids"
cat "$t/trace" > "$d/trace"
grep 'entries-in-buffer/entries-written' "$d/trace" || true
awk 'NR==FNR { tids[$1]=1; next }
 /sched_migrate_task:/ {
     pid=src=dst=-1
     for(i=1;i<=NF;i++) {
         if($i ~ /^pid=/) pid=substr($i,5)+0
         if($i ~ /^orig_cpu=/) src=substr($i,10)+0
         if($i ~ /^dest_cpu=/) dst=substr($i,10)+0
     }
     if(src<0 || dst<0) next
     all++; cross+=(int(src/4)!=int(dst/4));
     if(pid in tids) { app++; up+=(src<4 && dst>=4); down+=(src>=4 && dst<4) }
 } END { printf "migrations_all=%d cross_cluster=%d settings_surviving_threads=%d low_to_high=%d high_to_low=%d\n",all,cross,app,up,down }' "$d/tids" "$d/trace"
input keyevent KEYCODE_HOME
bb=/data/adb/ksu/bin/busybox
for _ in 1 2 3 4 5; do
    start=$(date +%s%N)
    "$bb" dd if=/system/framework/framework.jar of="$d/output" bs=1M count=8 oflag=direct conv=fsync status=none
    echo "f2fs_8MiB_direct_write_fsync_ns=$(( $(date +%s%N) - start ))"
    start=$(date +%s%N)
    "$bb" dd if="$d/output" of=/dev/null bs=1M count=8 iflag=direct status=none
    echo "f2fs_8MiB_direct_read_ns=$(( $(date +%s%N) - start ))"
done
cat /proc/pressure/memory
printf 'usb_online='; cat /sys/class/power_supply/usb/online
printf 'battery_current_now='; cat /sys/class/power_supply/battery/current_now
printf 'charge_counter='; cat /sys/class/power_supply/battery/charge_counter
