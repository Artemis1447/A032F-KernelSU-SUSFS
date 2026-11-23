#!/usr/bin/env bash
# V17: bridge SukiSU-Ultra's SUSFS supercall ABI onto susfs4ksu v1.5.5
# (kernel-4.14 / non-GKI).
#
# SukiSU's builtin branch bundles its own SUSFS userspace protocol, but the
# only kernel-side SUSFS that exists for Linux 4.14 is v1.5.5. The two patches
# applied here are what makes those two halves talk to each other:
#
#   * a3core-v17-susfs-path-abi-v155.patch
#       kernel side -- adds susfs_add_sus_path_sukisu(), the entry point the
#       SukiSU dispatcher calls, and keeps the v1.5.5 inode bookkeeping.
#   * a3core-v17-sukisu-susfs-v155-compat.patch
#       SukiSU side -- routes the supported commands through the v1.5.5 API
#       and answers the rest with -EOPNOTSUPP instead of calling symbols that
#       do not exist on 4.14.
#
# Both patches are applied only after scripts/patches.sh has dropped the
# SUSFS sources into the kernel tree, so the target files exist and the build
# either gets the compatibility layer or fails here.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR must be set}
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ksu_dir="${KERNEL_DIR}/${KSU_DIR:-KernelSU}"

[ "${KSU_VARIANT:-}" = "sukisu-ultra" ] \
	|| die "the SUSFS v1.5.5 ABI bridge is only wired for SukiSU-Ultra"
[ "${ENABLE_SUSFS:-}" = "true" ] \
	|| die "SUSFS_V155_ABI_COMPAT requires ENABLE_SUSFS=true"
[ -d "$ksu_dir/.git" ] || die "SukiSU source checkout not found: ${ksu_dir}"

group "Checking SUSFS v1.5.5 kernel sources"
kver=$(kernel_version "$KERNEL_DIR") || die "cannot read kernel version"
[ "$kver" = "4.14" ] || die "the V17 SUSFS bridge requires Linux 4.14 (found ${kver})"

susfs_c="${KERNEL_DIR}/fs/susfs.c"
susfs_h="${KERNEL_DIR}/include/linux/susfs.h"
[ -s "$susfs_c" ] || die "fs/susfs.c missing; run scripts/patches.sh first"
[ -s "$susfs_h" ] || die "include/linux/susfs.h missing; run scripts/patches.sh first"

susfs_version=$(sed -nE 's/.*SUSFS_VERSION[[:space:]]+"([^"]+)".*/\1/p' "$susfs_h" | head -n1)
case "$susfs_version" in
	v1.5.5 | 1.5.5) ;;
	*) die "expected SUSFS v1.5.5 from branch kernel-4.14, found '${susfs_version:-none}'" ;;
esac
grep -q 'int susfs_add_sus_path(struct st_susfs_sus_path' "$susfs_c" \
	|| die "unexpected fs/susfs.c: susfs_add_sus_path() signature not found"
info "kernel ${kver} carries SUSFS ${susfs_version}"
endgroup

group "Applying V17 SUSFS ABI bridge"

kernel_patch="${REPO_ROOT}/patches/a3core-v17-susfs-path-abi-v155.patch"
[ -s "$kernel_patch" ] || die "kernel-side SUSFS ABI patch is missing: ${kernel_patch}"
# --whitespace=error-all checks the lines this patch adds, which is what we
# actually care about. A plain `git diff --check` on the whole kernel tree is
# useless here: patches.sh has already dropped susfs4ksu in, and that patch
# legitimately carries lines with trailing tabs, which would drown out any
# signal from our own hunks.
git -C "$KERNEL_DIR" apply --check --whitespace=error-all "$kernel_patch" \
	|| die "kernel-side SUSFS ABI patch does not apply cleanly or adds whitespace errors"
git -C "$KERNEL_DIR" apply "$kernel_patch" \
	|| die "failed to apply the kernel-side SUSFS ABI patch"

group "Porting the SUSFS per-task marker off task_struct"
# The stock vendor modules are keyed to the stock kernel's MODVERSIONS CRCs.
# SUSFS v1.5.5 adds susfs_task_state/susfs_last_fake_mnt_id to task_struct and
# susfs_mnt_id_backup to struct vfsmount; those change the layout of very
# widely used types and therefore 129/267 CRCs, so the vendor module stops
# loading. Nothing else reads those fields, so port the per-task marker to a
# thread flag and keep the two mount-only fields behind SUS_MOUNT (disabled).
python3 - "$KERNEL_DIR" <<'PY' || die "failed to port the SUSFS per-task marker"
import io, os, sys
kdir = sys.argv[1]
marker = 'current->susfs_task_state & TASK_STRUCT_NON_ROOT_USER_APP_PROC'
repl = 'susfs_is_current_proc_umounted()'
ported = 0
for root, _dirs, names in os.walk(kdir):
    for name in names:
        if not name.endswith(('.c', '.h')):
            continue
        path = os.path.join(root, name)
        try:
            text = io.open(path, encoding='utf-8', errors='surrogateescape').read()
        except OSError:
            continue
        if marker not in text:
            continue
        text = text.replace(marker, repl)
        # The helper lives in <linux/susfs.h>. These files used the bare
        # task_struct field before, so some of them only pull susfs_def.h;
        # add the include so the declaration is visible.
        if 'linux/susfs.h' not in text:
            cut = text.find('#include')
            if cut < 0:
                sys.exit('no include block in %s' % path)
            eol = text.find('\n', cut)
            text = text[:eol + 1] + '#include <linux/susfs.h>\n' + text[eol + 1:]
        io.open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text)
        ported += 1
if ported == 0:
    sys.exit('the SUSFS per-task marker pattern was not found')


def rewrite(rel, old, new):
    path = os.path.join(kdir, rel)
    text = io.open(path, encoding='utf-8', errors='surrogateescape').read()
    if old not in text:
        sys.exit('marker block not found in %s' % rel)
    io.open(path, 'w', encoding='utf-8', errors='surrogateescape').write(text.replace(old, new, 1))


rewrite('include/linux/sched.h',
        '#ifdef CONFIG_KSU_SUSFS\n\tu64 susfs_task_state;\n\tu64 susfs_last_fake_mnt_id;\n#endif',
        '#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tu64 susfs_last_fake_mnt_id;\n#endif')
rewrite('include/linux/mount.h',
        '#ifdef CONFIG_KSU_SUSFS\n\tu64 susfs_mnt_id_backup;\n#endif',
        '#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\tu64 susfs_mnt_id_backup;\n#endif')
print('ported %d files' % ported)
PY
if grep -qF 'u64 susfs_task_state;' "${KERNEL_DIR}/include/linux/sched.h"; then
	die "task_struct still carries susfs_task_state after the rewrite"
fi
if grep -rqF --include='*.c' --include='*.h' 'current->susfs_task_state' "$KERNEL_DIR"; then
	die "leftover susfs_task_state reads after the port"
fi
info "ported the SUSFS per-task marker off task_struct; mount-only fields guarded"
endgroup

ksu_patch="${REPO_ROOT}/patches/a3core-v17-sukisu-susfs-v155-compat.patch"
[ -s "$ksu_patch" ] || die "SukiSU-side SUSFS ABI patch is missing: ${ksu_patch}"
git -C "$ksu_dir" apply --check "$ksu_patch" \
	|| die "SukiSU-side SUSFS ABI patch does not apply cleanly to the pinned source"
git -C "$ksu_dir" apply "$ksu_patch" \
	|| die "failed to apply the SukiSU-side SUSFS ABI patch"

# The SukiSU checkout only carries our own patches, so a whole-tree check is
# meaningful there. The kernel tree is not -- see the note above.
git -C "$ksu_dir" diff --check \
	|| die "SukiSU-side SUSFS ABI patch introduced whitespace errors"

# The two halves must agree on the dispatcher entry point, otherwise the build
# would succeed with the command silently returning -EINVAL at runtime.
grep -q 'int susfs_add_sus_path_sukisu(void __user \*user_info)' "$susfs_c" \
	|| die "susfs_add_sus_path_sukisu() was not added to fs/susfs.c"
grep -q 'susfs_add_sus_path_sukisu' "$susfs_h" \
	|| die "susfs_add_sus_path_sukisu() was not declared in include/linux/susfs.h"
grep -q 'susfs_add_sus_path_sukisu' "${ksu_dir}/kernel/supercall/dispatch.c" \
	|| die "the SukiSU dispatcher does not call susfs_add_sus_path_sukisu()"
grep -q '^#include "susfs_compat_4_14.h"$' "${ksu_dir}/kernel/supercall/dispatch.c" \
	|| die "the 4.14 SUSFS compatibility header was not included by the dispatcher"
[ -s "${ksu_dir}/kernel/supercall/susfs_compat_4_14.h" ] \
	|| die "the 4.14 SUSFS compatibility header was not created"

# V17 supports only the approved subset. The process-marking shim must exist
# and the unsupported newer-SUSFS features must be marked and guarded, not
# stubbed as if they worked.
grep -q 'susfs_set_current_proc_umounted' "$susfs_h" \
	|| die "the v1.5.5 process marker shim is missing from include/linux/susfs.h"
grep -q 'susfs_is_current_proc_umounted' "$susfs_h" \
	|| die "the v1.5.5 thread-flag marker helper is missing from include/linux/susfs.h"
grep -q 'TIF_PROC_UMOUNTED' "$susfs_h" \
	|| die "TIF_PROC_UMOUNTED is missing from include/linux/susfs.h"
for marker in SUSFS_V155_LACKS_NO_SU SUSFS_V155_LACKS_UMOUNTED_FOR_ZYGOTE_NEXT \
	SUSFS_V155_LACKS_EXTRA_WORKS; do
	grep -q "$marker" "$susfs_h" \
		|| die "the V17 unsupported-feature marker ${marker} is missing"
done
grep -q 'SUSFS_V155_LACKS_NO_SU' "${ksu_dir}/kernel/hook/lsm_hook.c" \
	|| die "the SukiSU lsm hook is not guarded on the V17 markers"
grep -q 'kvmalloc_array' "${ksu_dir}/kernel/supercall/susfs_compat_4_14.h" \
	|| die "the Linux 4.14 kvcalloc shim is missing"

git -C "$KERNEL_DIR" status --short -- fs/susfs.c include/linux/susfs.h
git -C "$ksu_dir" status --short -- kernel/supercall
endgroup

ok "applied the V17 SUSFS v1.5.5 ABI bridge"
