#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR must be set}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

[ "${KSU_VARIANT:-}" = "sukisu-ultra" ] \
	|| die "the static_call compatibility patch is only for SukiSU-Ultra"
printf '%s' "${KSU_REF:-}" | grep -qE '^[0-9a-f]{40}$' \
	|| die "SukiSU-Ultra must be pinned to a full commit SHA"

ksu_dir="${KERNEL_DIR}/${KSU_DIR:-KernelSU}"
[ -d "$ksu_dir/.git" ] || die "SukiSU source checkout not found: ${ksu_dir}"

group "Verifying pinned SukiSU source"
head_sha=$(git -C "$ksu_dir" rev-parse HEAD)
[ "$head_sha" = "$KSU_REF" ] \
	|| die "SukiSU checkout ${head_sha} does not match pinned KSU_REF ${KSU_REF}"
git -C "$ksu_dir" status --short --branch
git -C "$ksu_dir" log -5 --oneline --decorate
info "SukiSU source SHA: ${head_sha}"
[ -z "$(git -C "$ksu_dir" status --porcelain)" ] \
	|| die "SukiSU checkout is dirty before applying the V17 patch"
endgroup

group "Checking Linux 4.14 static_call support"
kver=$(kernel_version "$KERNEL_DIR") || die "cannot read kernel version"
[ "$kver" = "4.14" ] || die "V17 static_call patch requires Linux 4.14 (found ${kver})"
[ ! -e "${KERNEL_DIR}/include/linux/static_call.h" ] \
	|| die "static_call.h exists in this kernel tree; refusing the legacy-kernel patch"

if ksu_static_call_uses=$(grep -R -n --include='*.c' --include='*.h' 'static_call' "${ksu_dir}/kernel" \
	| grep -v '/kernel_includes.h:'); then
	die "SukiSU has static_call references outside kernel_includes.h; do not suppress the API include"
else
	search_status=$?
	[ "$search_status" -eq 1 ] \
		|| die "failed to inspect SukiSU kernel sources for static_call usage (grep exit ${search_status})"
fi

if static_call_config=$(grep -R -nE '^[[:space:]]*(config[[:space:]]+(HAVE_)?STATIC_CALL|#define[[:space:]]+CONFIG_HAVE_STATIC_CALL)' \
	--include='Kconfig*' --include='*.h' \
	"${KERNEL_DIR}/arch" "${KERNEL_DIR}/include" "${KERNEL_DIR}/kernel"); then
	die "static_call configuration/API declarations found in the Linux 4.14 tree"
else
	search_status=$?
	[ "$search_status" -eq 1 ] \
		|| die "failed to inspect Linux static_call configuration (grep exit ${search_status})"
fi

info "Linux ${kver} has no static_call header, config declaration, or SukiSU API use beyond the header include"
endgroup

patch_file="${REPO_ROOT}/patches/a3core-v17-sukisu-static-call-4.14.patch"
[ -s "$patch_file" ] || die "V17 compatibility patch is missing: ${patch_file}"
git -C "$ksu_dir" apply --check "$patch_file" \
	|| die "V17 compatibility patch does not apply cleanly to the pinned SukiSU source"
git -C "$ksu_dir" apply "$patch_file" \
	|| die "failed to apply the V17 compatibility patch"
git -C "$ksu_dir" diff --check \
	|| die "V17 compatibility patch introduced whitespace errors"

grep -q '^#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)$' \
	"${ksu_dir}/kernel/kernel_includes.h" \
	|| die "expected version guard was not applied"
grep -q '^#include <linux/static_call.h>$' "${ksu_dir}/kernel/kernel_includes.h" \
	|| die "static_call include was unexpectedly removed"

git -C "$ksu_dir" status --short
git -C "$ksu_dir" diff --stat
ok "applied only the V17 static_call include guard"
