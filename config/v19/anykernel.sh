properties() { '
kernel.string=A03 Core V19 EXTREME
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=1
device.name1=a3core
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

BLOCK=/dev/block/by-name/boot;
is_slot_device=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=0;
. tools/ak3-core.sh;
[ "$(getprop ro.boot.em.model)" = SM-A032F ] || abort "SM-A032F only";
[ "$(readlink -f "$BLOCK")" = /dev/block/mmcblk0p40 ] || abort "Unexpected Boot partition";
split_boot;
flash_boot;
