# Xiaomi Pad 6 (pipa) N0 + ReSukiSU + SUSFS

Manual GitHub Actions build for Xiaomi Pad 6 running MIUI Android 13.
Kernel: bcggxx/android_kernel_xiaomi_n0_pipa, n0-A15 branch.
Root: official ReSukiSU (now Baka-SU/BakaSU), v4.2.0-rc3, UAPI 4.
SUSFS: v2.3.0, with the upstream pipa task_mmu compatibility fix.

This recipe follows bcggxx/NonGKI_Kernel_Build_2nd run 36694479829.
Source revisions and patch hashes are recorded in source-pins.json.
Original patch authorship and license notices are preserved. Source and
changes needed to reproduce the binary are available through the pins
and the exported kernel-integration.patch.

No keyboxes, boot backups, private keys, account tokens or device files
are uploaded. The build exports raw Image/Image.gz, DTB/DTBO, AnyKernel3,
configuration and integration evidence. It does not flash a device.
ReKernel, Droidspaces and KPM additions are omitted from this build.
AnyKernel3 updates boot, DTBO and vendor_boot DTB according to its pinned
installation script. Compilation does not prove hardware compatibility.
