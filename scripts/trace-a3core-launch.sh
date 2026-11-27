#!/system/bin/sh
# Feed to `adb shell -T su -c sh`; run after untraced benchmarks.
set -eu
[ "$(id -u)" = 0 ] && [ "$(getprop ro.product.model)" = SM-A032F ]
[ "$(getprop ro.product.device)" = a3core ] && [ "$(getprop sys.boot_completed)" = 1 ]
root=/sys/kernel/tracing/instances
instance=$root/a3core-launch-$$
mkdir "$instance"
cleanup() {
    echo 0 > "$instance/tracing_on"
    rmdir "$instance" >&2
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
echo 0 > "$instance/tracing_on"
echo boot > "$instance/trace_clock"
echo 768 > "$instance/buffer_size_kb"
for event in sched/sched_switch sched/sched_wakeup sched/sched_migrate_task \
    power/cpu_frequency vmscan/mm_vmscan_direct_reclaim_begin vmscan/mm_vmscan_direct_reclaim_end \
    block/block_rq_issue block/block_rq_complete dma_fence/dma_fence_wait_start dma_fence/dma_fence_wait_end; do
    [ -f "$instance/events/$event/enable" ] || { echo "missing event $event" >&2; exit 1; }
    echo 1 > "$instance/events/$event/enable"
done
echo "# kernel: $(uname -r)"
input keyevent KEYCODE_WAKEUP
wm dismiss-keyguard
input keyevent KEYCODE_HOME
for sample in 1 2 3 4 5 6; do
    echo 0 > "$instance/tracing_on"
    : > "$instance/trace"
    am force-stop --user 0 com.android.settings
    sleep 1
    echo "# launch $sample"
    echo 1 > "$instance/tracing_on"
    echo a3core_launch_begin > "$instance/trace_marker"
    am start -W --user 0 -a android.settings.SETTINGS
    echo a3core_launch_end > "$instance/trace_marker"
    echo 0 > "$instance/tracing_on"
    pid=$(pidof com.android.settings)
    echo "# settings pid: $pid"
    echo "# settings tids: $(ls "/proc/$pid/task" | tr '\n' ' ')"
    echo "# persistent tids: $(pidof system_server surfaceflinger)"
    logcat -b main -b system -v monotonic -d -t 800 -s TopLevelSettings:D ActivityTaskManager:I 2>/dev/null | \
        grep -E "^[[:space:]]*[0-9.]+[[:space:]]+$pid[[:space:]].*All preferences added|Displayed com.android.settings/" | tail -6 || true
    cat "$instance/trace"
    sleep 2
done
input keyevent KEYCODE_HOME
