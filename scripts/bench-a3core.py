#!/usr/bin/env python3
"""Measure process-cold Settings launches on one unlocked a3core, without dropping caches."""

import argparse
import json
import re
import statistics
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--adb', default='adb')
    parser.add_argument('--serial', required=True)
    parser.add_argument('--kernel', choices=('v17', 'v18'), required=True)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--at-uptime', type=int, help='target seconds since boot for a paired run (10 s tolerance)')
    args = parser.parse_args()
    if args.out.exists():
        parser.error('choose a new results filename')
    adb = [args.adb, '-s', args.serial]

    def shell(script, *, root=False, timeout=40):
        command = adb + ['shell', '-T'] + (['su', '-c', 'sh'] if root else ['sh'])
        result = subprocess.run(command, input=(script + '\n').encode(), capture_output=True,
                                timeout=timeout)
        if result.returncode:
            raise RuntimeError(result.stderr.decode('utf-8', 'replace') or f'adb exited {result.returncode}')
        return result.stdout.decode('utf-8', 'replace').replace('\r', '').strip()

    def snapshot():
        text = shell('''
set -e
emit() { printf '%s=%s\\n' "$1" "$(cat "$2")"; }
emit uptime /proc/uptime
emit boot_id /proc/sys/kernel/random/boot_id
for i in /sys/devices/system/cpu/cpufreq/policy*; do
    for f in scaling_governor scaling_min_freq scaling_max_freq stats/time_in_state stats/total_trans; do
        printf '%s.%s=%s\\n' "${i##*/}" "$f" "$(tr '\\n' ';' < "$i/$f")"
    done
done
for z in /sys/class/thermal/thermal_zone*; do
    t=$(cat "$z/temp" 2>/dev/null) && printf 'thermal.%s=%s\\n' "$(cat "$z/type")" "$t"
done
for f in comp_algorithm disksize mm_stat io_stat; do emit "zram.$f" /sys/block/zram0/$f; done
for f in swappiness page-cluster; do emit "vm.$f" /proc/sys/vm/$f; done
for f in scheduler read_ahead_kb nr_requests; do emit "mmc.$f" /sys/block/mmcblk0/queue/$f; done
emit mmc.stat /sys/block/mmcblk0/stat
for f in governor min_freq max_freq polling_interval; do emit "gpu.$f" /sys/class/devfreq/60000000.gpu/$f; done
printf 'gpu.transitions=%s\\n' "$(tr '\\n' ';' < /sys/class/devfreq/60000000.gpu/trans_stat)"
awk '/^(pgmajfault|pswpin|pswpout|pgfault) / {print $1 "=" $2}' /proc/vmstat
awk '/^(MemAvailable|SwapFree):/ {print $1 "=" $2}' /proc/meminfo
for f in temp capacity; do emit "battery.$f" /sys/class/power_supply/battery/$f; done
emit usb.online /sys/class/power_supply/usb/online
printf 'memory.psi=%s\\n' "$(tr '\\n' ';' < /proc/pressure/memory)"
for f in window_animation_scale transition_animation_scale animator_duration_scale; do echo "$f=$(settings get global "$f")"; done
for d in /data/adb/modules/*; do [ ! -d "$d" ] || printf 'module.%s=%s\\n' "${d##*/}" "$([ -e "$d/disable" ] && echo off || echo on)"; done
printf 'selinux=%s\\n' "$(getenforce)"
printf 'ion.log_lines=%s\\n' "$(dmesg | grep -c 'ion_system_heap_allocate, size:')"
''', root=True)
        return dict(line.split('=', 1) for line in text.splitlines() if '=' in line)

    identity = shell('getprop ro.product.model; getprop ro.product.device; getprop ro.lineage.version; '
                     'getprop ro.product.cpu.abilist; getprop sys.boot_completed; uname -r').splitlines()
    expected = '4.14.199-a3core-vendorabi-' + args.kernel + '-sukisu-susfs'
    if (len(identity) != 6 or identity[:2] != ['SM-A032F', 'a3core'] or
            not identity[2].startswith('21.0-') or identity[3:] != ['armeabi-v7a,armeabi', '1', expected]):
        raise SystemExit(f'unexpected device or kernel: {identity}')
    if 'uid=0(' not in shell('id', root=True):
        raise SystemExit('root access is needed for the performance counters')
    if args.at_uptime is not None:
        delay = args.at_uptime - float(shell('cat /proc/uptime').split()[0])
        if delay < -10:
            raise SystemExit(f'missed target boot age by {-delay:.1f} s')
        if delay > 0:
            time.sleep(delay)
    shell('input keyevent KEYCODE_WAKEUP; wm dismiss-keyguard; input keyevent KEYCODE_HOME')
    if 'deviceLocked=0' not in shell('dumpsys trust | grep "(current)"'):
        raise SystemExit('unlock the current Android user before benchmarking')
    result = {'utc': datetime.now(timezone.utc).isoformat(), 'identity': identity,
              'target_uptime_s': args.at_uptime, 'warmups': 2, 'runs': 12,
              'before': snapshot(), 'samples': [], 'invalid_attempts': []}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    try:
        while len(result['samples']) < result['warmups'] + result['runs']:
            text = shell('''set -e
am force-stop --user 0 com.android.settings
sleep 1
am start -W -a android.settings.SETTINGS
sleep 2
su -c 'cat /sys/class/thermal/thermal_zone1/temp'
''')
            fields = dict(re.findall(r'^(Status|LaunchState|Activity|TotalTime|WaitTime): (.+)$', text, re.M))
            if fields.get('Status') != 'ok' or fields.get('Activity') != 'com.android.settings/.homepage.SettingsHomepageActivity':
                raise ValueError(f'invalid launch: {text}')
            if fields.get('LaunchState') != 'COLD':
                result['invalid_attempts'].append(fields)
                if len(result['invalid_attempts']) > 3:
                    raise ValueError('could not obtain a repeatable process-cold launch')
                continue
            result['samples'].append({'warmup': len(result['samples']) < result['warmups'], 'total_ms': int(fields['TotalTime']),
                                      'wait_ms': int(fields['WaitTime']), 'cpu_mC': int(text.splitlines()[-1])})
        result['after'] = snapshot()
        if result['before']['boot_id'] != result['after']['boot_id']:
            raise ValueError('the phone rebooted during the measurement')
        times = [s['total_ms'] for s in result['samples'] if not s['warmup']]
        result['median_ms'] = statistics.median(times)
        print(f'{args.kernel}: {times}; median {result["median_ms"]} ms')
    finally:
        args.out.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        shell('input keyevent KEYCODE_HOME')


if __name__ == '__main__':
    main()
