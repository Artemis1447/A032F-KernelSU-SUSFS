#!/usr/bin/env bash
# Fetch the kernel source tree.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WORKSPACE=${WORKSPACE:?WORKSPACE must be set}
KERNEL_DIR="${WORKSPACE}/android-kernel"

group "Cloning kernel source"
info "${KERNEL_SOURCE} @ ${KERNEL_SOURCE_BRANCH}"

ref_exists "$KERNEL_SOURCE" "$KERNEL_SOURCE_BRANCH" \
	|| die "branch/tag '${KERNEL_SOURCE_BRANCH}' does not exist in ${KERNEL_SOURCE}"

rm -rf "$KERNEL_DIR"
retry 3 git clone -q --recursive --depth=1 \
	-b "$KERNEL_SOURCE_BRANCH" "$KERNEL_SOURCE" "$KERNEL_DIR" \
	|| die "failed to clone ${KERNEL_SOURCE}"

if [ -n "${KERNEL_SOURCE_COMMIT:-}" ]; then
	requested_commit=${KERNEL_SOURCE_COMMIT,,}
	current_commit=$(git -C "$KERNEL_DIR" rev-parse HEAD)
	if [ "$current_commit" != "$requested_commit" ]; then
		git -C "$KERNEL_DIR" fetch -q --no-tags --depth=1 origin "$requested_commit" \
			|| die "failed to fetch pinned kernel commit ${requested_commit}"
		git -C "$KERNEL_DIR" checkout -q --detach FETCH_HEAD \
			|| die "failed to check out pinned kernel commit ${requested_commit}"
		git -C "$KERNEL_DIR" submodule update --init --recursive \
			|| die "failed to update submodules for ${requested_commit}"
	fi

	actual_commit=$(git -C "$KERNEL_DIR" rev-parse HEAD)
	[ "$actual_commit" = "$requested_commit" ] \
		|| die "kernel source resolved to ${actual_commit}, not requested ${requested_commit}"
	export_env KERNEL_SOURCE_COMMIT_RESOLVED "$actual_commit"
	info "pinned kernel commit: ${actual_commit}"
else
	export_env KERNEL_SOURCE_COMMIT_RESOLVED "$(git -C "$KERNEL_DIR" rev-parse HEAD)"
	warn "KERNEL_SOURCE_COMMIT is not pinned; the source branch may move"
fi

# KernelSU forks compute their version from the commit count, and several
# read it straight out of the enclosing git repo. A depth-1 clone reports 1
# commit, which produces a nonsense version. Unshallow just enough to count.
if [ -f "${KERNEL_DIR}/.git/shallow" ]; then
	debug "kernel tree is shallow; that is fine for building"
fi

KVER=$(kernel_version "$KERNEL_DIR") \
	|| die "could not read VERSION/PATCHLEVEL from ${KERNEL_DIR}/Makefile -- is this a kernel tree?"
export_env KERNEL_VERSION "$KVER"
export_env KERNEL_DIR "$KERNEL_DIR"
ok "kernel source ready (Linux ${KVER})"
summary "| Kernel | \`${KERNEL_SOURCE##*/}\` @ \`${KERNEL_SOURCE_BRANCH}\` (Linux ${KVER}) |"

# LOCALVERSION is used purely to decorate artifact names.
if is_true "${ADD_LOCALVERSION_TO_FILENAME:-false}" && [ -f "${KERNEL_DIR}/localversion" ]; then
	export_env LOCALVERSION "$(cat "${KERNEL_DIR}/localversion")"
else
	export_env LOCALVERSION ""
fi
endgroup
