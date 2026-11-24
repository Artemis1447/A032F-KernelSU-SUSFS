#!/usr/bin/env bash
# V17: connect the pinned SukiSU SUSFS reboot dispatcher to Linux 4.14.
#
# ksud installs the [ksu_driver] fd with a reboot(2) call using
# KSU_INSTALL_MAGIC1/KSU_INSTALL_MAGIC2. With CONFIG_KSU_SUSFS, SukiSU's
# ksu_handle_sys_reboot() handles both that fd request and the SUSFS commands,
# but the stock a3core kernel never calls it. This script proves the gap and
# applies the standard upstream call site before the CAP_SYS_BOOT gate so a
# non-root manager app can also receive its driver fd.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR must be set}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

[ "${KSU_VARIANT:-}" = "sukisu-ultra" ] \
	|| die "the SUSFS reboot hook is only for SukiSU-Ultra"
printf '%s' "${KSU_REF:-}" | grep -qE '^[0-9a-f]{40}$' \
	|| die "SukiSU-Ultra must be pinned to a full commit SHA"
[ "${ENABLE_SUSFS:-false}" = "true" ] \
	|| die "the SUSFS reboot hook requires ENABLE_SUSFS=true"

ksu_dir="${KERNEL_DIR}/${KSU_DIR:-KernelSU}"
[ -d "$ksu_dir/.git" ] || die "SukiSU source checkout not found: ${ksu_dir}"
reboot="${KERNEL_DIR}/kernel/reboot.c"
[ -f "$reboot" ] || die "kernel reboot syscall source not found: ${reboot}"

group "Proving the reboot hook gap"
head_sha=$(git -C "$ksu_dir" rev-parse HEAD)
[ "$head_sha" = "$KSU_REF" ] \
	|| die "SukiSU checkout ${head_sha} does not match pinned KSU_REF ${KSU_REF}"
info "SukiSU source SHA: ${head_sha}"

kver=$(kernel_version "$KERNEL_DIR") || die "cannot read kernel version"
[ "$kver" = "4.14" ] || die "the SUSFS reboot hook requires Linux 4.14 (found ${kver})"

# A second hook would be wrong: the vendor tree has none today, and SukiSU must
# keep its single SUSFS dispatcher definition.
if grep -q 'ksu_handle_sys_reboot' "$reboot"; then
	die "kernel/reboot.c already has a KSU reboot hook; do not add a second one"
fi
dispatch="${ksu_dir}/kernel/supercall/dispatch.c"
supercall="${ksu_dir}/kernel/supercall/supercall.c"
[ -s "$dispatch" ] || die "missing ${dispatch}"
[ -s "$supercall" ] || die "missing ${supercall}"
grep -qF 'int ksu_handle_sys_reboot(int magic1, int magic2, unsigned int cmd, void __user **arg)' "$dispatch" \
	|| die "the pinned SukiSU SUSFS reboot dispatcher is missing"
grep -qF 'if (magic2 == KSU_INSTALL_MAGIC2)' "$dispatch" \
	|| die "the SUSFS dispatcher does not recognise the KSU fd-install magic"
grep -qF 'return ksu_supercall_reboot_handler(arg);' "$dispatch" \
	|| die "the SUSFS dispatcher does not forward fd-install requests"
grep -qF 'int ksu_supercall_reboot_handler(void __user **arg)' "$supercall" \
	|| die "the SukiSU fd-install handler is missing"
grep -qF 'ns_capable(pid_ns->user_ns, CAP_SYS_BOOT)' "$reboot" \
	|| die "the expected CAP_SYS_BOOT gate is missing from reboot.c"
info "reboot syscall has no KSU hook; the SUSFS dispatcher can install driver fds"
endgroup

patch_file="${REPO_ROOT}/patches/a3core-v17-sukisu-reboot-hook-4.14.patch"
[ -s "$patch_file" ] || die "reboot hook patch is missing: ${patch_file}"
git -C "$KERNEL_DIR" apply --check --whitespace=error-all "$patch_file" \
	|| die "reboot hook patch does not apply cleanly or adds whitespace errors"
git -C "$KERNEL_DIR" apply "$patch_file" \
	|| die "failed to apply the reboot hook patch"

group "Verifying the applied reboot hook"
git -C "$KERNEL_DIR" diff --check -- kernel/reboot.c \
	|| die "reboot hook patch introduced whitespace errors"
grep -qF 'ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);' "$reboot" \
	|| die "the reboot syscall does not call the SUSFS dispatcher"
[ "$(grep -c '^extern int ksu_handle_sys_reboot' "$reboot")" -eq 1 ] \
	|| die "expected exactly one ksu_handle_sys_reboot declaration in reboot.c"
hook_line=$(grep -nF 'ksu_handle_sys_reboot(magic1, magic2, cmd, &arg);' "$reboot" | cut -d: -f1)
cap_line=$(grep -nF 'ns_capable(pid_ns->user_ns, CAP_SYS_BOOT)' "$reboot" | cut -d: -f1)
[ -n "$hook_line" ] && [ -n "$cap_line" ] && [ "$hook_line" -lt "$cap_line" ] \
	|| die "the reboot hook must run before the CAP_SYS_BOOT gate"
info "hook at line ${hook_line}, CAP_SYS_BOOT gate at line ${cap_line}"
endgroup

ok "applied the Linux 4.14 SUSFS reboot hook"
