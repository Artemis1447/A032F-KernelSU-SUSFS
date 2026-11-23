#!/usr/bin/env bash
# Preserve the exact config and symbol CRC table used by this kernel build.

set -euo pipefail
# shellcheck source=scripts/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KERNEL_DIR=${KERNEL_DIR:?KERNEL_DIR must be set}
WORKSPACE=${WORKSPACE:-$(cd "${KERNEL_DIR}/.." && pwd)}
OUT="${KERNEL_DIR}/out"
DEST="${WORKSPACE}/abi-diagnostics"

[ -s "${OUT}/.config" ] || die "kernel .config is missing"
grep -q '^CONFIG_MODVERSIONS=y$' "${OUT}/.config" \
	|| die "CONFIG_MODVERSIONS is not enabled; ABI diagnostics would be incomplete"
[ -s "${OUT}/Module.symvers" ] || die "Module.symvers is missing"
[ -s "${OUT}/System.map" ] || die "System.map is missing"

rm -rf "$DEST"
mkdir -p "$DEST"
cp "${OUT}/.config" "${DEST}/kernel.config"
cp "${OUT}/Module.symvers" "${DEST}/Module.symvers"
cp "${OUT}/System.map" "${DEST}/System.map"
cp "${OUT}/include/generated/utsrelease.h" "${DEST}/utsrelease.h"
cp "${OUT}/arch/${ARCH:-arm64}/boot/${KERNEL_IMAGE_NAME}" "${DEST}/kernel.Image"

{
	printf 'kernel_source=%s\n' "${KERNEL_SOURCE}"
	printf 'kernel_source_branch=%s\n' "${KERNEL_SOURCE_BRANCH}"
	printf 'kernel_source_commit=%s\n' "${KERNEL_SOURCE_COMMIT_RESOLVED:-unknown}"
	printf 'kernel_config=%s\n' "${KERNEL_CONFIG}"
	printf 'kernel_release=%s\n' "${KERNEL_RELEASE:-unknown}"
	printf 'kernel_image_sha256=%s\n' "$(sha256sum "${DEST}/kernel.Image" | cut -d' ' -f1)"
	printf 'module_symvers_sha256=%s\n' "$(sha256sum "${DEST}/Module.symvers" | cut -d' ' -f1)"
	printf 'config_sha256=%s\n' "$(sha256sum "${DEST}/kernel.config" | cut -d' ' -f1)"
} >"${DEST}/manifest.txt"

ok "ABI diagnostics exported to ${DEST}"
summary "| ABI diagnostics | \`Module.symvers\`, \`.config\`, \`System.map\` |"
