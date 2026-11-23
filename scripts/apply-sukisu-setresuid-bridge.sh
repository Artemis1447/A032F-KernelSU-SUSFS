#!/usr/bin/env bash
# Linux 4.14 bridge for the SUSFS manager-fd hook.
#
# With CONFIG_KSU_SUSFS=y the pinned SukiSU source deliberately drops the
# legacy LSM task_fix_setuid handler and expects ksu_handle_setresuid() to be
# called from the setresuid syscall implementation. That call site does not
# exist in this 4.14 tree, so the manager process never receives the
# [ksu_driver] fd and the manager app reports preview mode.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR must be set}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

[ "${KSU_VARIANT:-}" = "sukisu-ultra" ] \
	|| die "the SUSFS setresuid bridge is only for SukiSU-Ultra"
printf '%s' "${KSU_REF:-}" | grep -qE '^[0-9a-f]{40}$' \
	|| die "SukiSU-Ultra must be pinned to a full commit SHA"
[ "${ENABLE_SUSFS:-false}" = "true" ] \
	|| die "the SUSFS setresuid bridge requires ENABLE_SUSFS=true"

ksu_dir="${KERNEL_DIR}/${KSU_DIR:-KernelSU}"
[ -d "$ksu_dir/.git" ] || die "SukiSU source checkout not found: ${ksu_dir}"

group "Verifying pinned SukiSU source"
head_sha=$(git -C "$ksu_dir" rev-parse HEAD)
[ "$head_sha" = "$KSU_REF" ] \
	|| die "SukiSU checkout ${head_sha} does not match pinned KSU_REF ${KSU_REF}"
info "SukiSU source SHA: ${head_sha}"
kver=$(kernel_version "$KERNEL_DIR") || die "cannot read kernel version"
[ "$kver" = "4.14" ] || die "the SUSFS setresuid bridge requires Linux 4.14 (found ${kver})"
endgroup

lsm="${ksu_dir}/kernel/hook/lsm_hook.c"
[ -f "$lsm" ] || die "missing ${lsm}"

group "Proving the SUSFS setresuid call-site gap"
# Exactly one definition of ksu_handle_setresuid(), and no caller anywhere in
# the SukiSU sources or the applied SUSFS integration patches.
defs=$(grep -R -n --include='*.c' --include='*.h' -E '^[[:space:]]*int[[:space:]]+ksu_handle_setresuid\(' "${ksu_dir}/kernel" || true)
[ "$(printf '%s\n' "$defs" | grep -c .)" -eq 1 ] \
	|| die "expected exactly one ksu_handle_setresuid definition, found: ${defs}"
info "definition: ${defs}"

callers=$(grep -R -n --include='*.c' --include='*.h' -E 'ksu_handle_setresuid[[:space:]]*\(' "${ksu_dir}/kernel" \
	| grep -v 'int[[:space:]]\+ksu_handle_setresuid(' || true)
[ -z "$callers" ] \
	|| die "a setresuid call site already exists; do not add a second one: ${callers}"

# The legacy hook is compiled out under SUSFS; that is the gap being bridged.
grep -q '^#ifndef CONFIG_KSU_SUSFS$' "$lsm" \
	|| die "expected the SUSFS guard around the legacy task_fix_setuid hook"
grep -q 'LSM_HOOK_INIT(task_fix_setuid, ksu_task_fix_setuid),' "$lsm" \
	|| die "expected the legacy task_fix_setuid registration"
if grep -q '^static int ksu_susfs_task_fix_setuid(' "$lsm"; then
	die "setresuid bridge is already applied"
fi
info "no caller found; the LSM task_fix_setuid bridge is required"
endgroup

patch_file="${REPO_ROOT}/patches/a3core-v17-sukisu-setresuid-lsm-bridge-4.14.patch"
[ -s "$patch_file" ] || die "setresuid bridge patch is missing: ${patch_file}"
git -C "$ksu_dir" apply --check "$patch_file" \
	|| die "setresuid bridge patch does not apply cleanly to the pinned SukiSU source"
git -C "$ksu_dir" apply "$patch_file" \
	|| die "failed to apply the setresuid bridge patch"

group "Verifying the applied bridge"
git -C "$ksu_dir" diff --check \
	|| die "setresuid bridge patch introduced whitespace errors"
grep -q '^static int ksu_susfs_task_fix_setuid(' "$lsm" \
	|| die "bridge handler was not installed"
grep -q 'return ksu_handle_setresuid(new->uid.val, new->euid.val, new->suid.val);' "$lsm" \
	|| die "bridge handler does not forward to ksu_handle_setresuid"
grep -q 'LSM_HOOK_INIT(task_fix_setuid, ksu_susfs_task_fix_setuid),' "$lsm" \
	|| die "bridge handler was not registered"
grep -q '^#else$' "$lsm" \
	|| die "SUSFS/non-SUSFS hook selection was not preserved"
info "manager fd hook is now reachable from Linux 4.14 setuid syscalls"
endgroup

git -C "$ksu_dir" status --short
ok "applied the Linux 4.14 SUSFS setresuid LSM bridge"
