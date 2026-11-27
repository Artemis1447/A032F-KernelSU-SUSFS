#!/system/bin/sh
# Reversible, same-boot V17 parameter screening. Run after the matched suites.
set -eu
[ "$(id -u)" = 0 ] && [ "$(getprop ro.product.model)" = SM-A032F ]
[ "$(getprop ro.product.device)" = a3core ] && [ "$(getprop sys.boot_completed)" = 1 ]
[ "$(uname -r)" = 4.14.199-a3core-vendorabi-v17-sukisu-susfs ]
stats=/proc/sys/kernel/sched_schedstats
idle=/dev/stune/top-app/schedtune.prefer_idle
cluster=/proc/sys/vm/page-cluster
zone=/sys/class/thermal/thermal_zone1/temp
[ "$(cat "$stats") $(cat "$idle") $(cat "$cluster")" = '1 0 0' ]

apply() {
    [ "$(cat "$stats")" = "$1" ] || echo "$1" > "$stats"
    [ "$(cat "$idle")" = "$2" ] || echo "$2" > "$idle"
    [ "$(cat "$cluster")" = "$3" ] || echo "$3" > "$cluster"
    [ "$(cat "$stats") $(cat "$idle") $(cat "$cluster")" = "$1 $2 $3" ]
}
restore() {
    apply 1 0 0
    input keyevent KEYCODE_HOME
    echo "restored $(cat "$stats") $(cat "$idle") $(cat "$cluster")"
}
trap restore EXIT
trap 'exit 1' HUP INT TERM
input keyevent KEYCODE_WAKEUP
wm dismiss-keyguard
dumpsys trust | grep '(current).*deviceLocked=0' >/dev/null
echo "boot_id $(cat /proc/sys/kernel/random/boot_id)"
echo 'profile,block,warmup,total_ms,cpu_mC'
block=0
for profile in stock no_schedstats prefer_idle swap_ra2 \
    prefer_idle swap_ra2 stock no_schedstats \
    swap_ra2 prefer_idle no_schedstats stock \
    no_schedstats stock swap_ra2 prefer_idle; do
    block=$((block + 1))
    case "$profile" in
        stock) set -- 1 0 0 ;;
        no_schedstats) set -- 0 0 0 ;;
        prefer_idle) set -- 1 1 0 ;;
        swap_ra2) set -- 1 0 1 ;;
    esac
    apply "$@"
    input keyevent KEYCODE_HOME
    for warmup in 1 0 0 0 0; do
        am force-stop --user 0 com.android.settings
        sleep 1
        result=$(am start -W -a android.settings.SETTINGS)
        if ! printf '%s\n' "$result" | grep -qx 'LaunchState: COLD'; then
            echo "invalid $profile $block" >&2
            exit 1
        fi
        ms=$(printf '%s\n' "$result" | awk '/^TotalTime: [0-9]+$/ {print $2}')
        [ -n "$ms" ]
        temp=$(cat "$zone")
        [ "$temp" -lt 65000 ]
        echo "$profile,$block,$warmup,$ms,$temp"
        sleep 2
    done
    [ "$(cat "$stats") $(cat "$idle") $(cat "$cluster")" = "$1 $2 $3" ]
done
