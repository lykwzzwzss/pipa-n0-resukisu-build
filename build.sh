#!/usr/bin/env bash
set -euo pipefail
export KERNEL_SHA=07c4db462801567b2dc363cdd642baea38867c91
export ROOT_SHA=239e1e8871b8fcd51a6e5b3002e0ba522fdd99fb
export AK3_SHA=52c2c49b6abd92a922919c58d7d7b2572baf381a
export KBUILD_BUILD_USER=lykwzzwzss KBUILD_BUILD_HOST=GitHubActions
export KBUILD_BUILD_TIMESTAMP='2026-10-06 00:00:00 UTC'
mkdir -p artifacts/evidence artifacts/raw
case "$1" in
sources)
  git init device_kernel
  git -C device_kernel remote add origin https://github.com/bcggxx/android_kernel_xiaomi_n0_pipa.git
  git -C device_kernel fetch --depth 1 origin "$KERNEL_SHA"
  git -C device_kernel checkout --detach FETCH_HEAD
  test "$(git -C device_kernel rev-parse HEAD)" = "$KERNEL_SHA"
  git clone --branch v4.2.0-rc3 --single-branch https://github.com/Baka-SU/BakaSU.git device_kernel/KernelSU
  test "$(git -C device_kernel/KernelSU rev-parse HEAD)" = "$ROOT_SHA"
  test ! -e device_kernel/drivers/kernelsu
  ln -s ../KernelSU/kernel device_kernel/drivers/kernelsu
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> device_kernel/drivers/Makefile
  sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' device_kernel/drivers/Kconfig
  git init anykernel
  git -C anykernel remote add origin https://github.com/bcggxx/AnyKernel3.git
  git -C anykernel fetch --depth 1 origin "$AK3_SHA"
  git -C anykernel checkout --detach FETCH_HEAD
  test "$(git -C anykernel rev-parse HEAD)" = "$AK3_SHA"
  ;;
toolchain)
  mkdir clang
  for attempt in 1 2 3 4 5; do
    if curl -fL --retry 3 --retry-all-errors --connect-timeout 30 \
      https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r547379.tar.gz \
      -o clang.tar.gz && gzip -t clang.tar.gz; then break; fi
    sleep 5
  done
  gzip -t clang.tar.gz
  sha256sum clang.tar.gz > artifacts/evidence/clang-archive.sha256
  tar -xzf clang.tar.gz -C clang
  test -x clang/bin/clang
  clang/bin/clang --version
  ;;
patch)
  cd device_kernel
  test ! -f fs/susfs.c
  if ! patch --batch -p1 < ../patches/susfs-4.19.patch > ../susfs-base.log 2>&1; then
    cat ../susfs-base.log
    python3 - <<'PY'
from pathlib import Path
rejects = sorted(str(p) for p in Path('.').rglob('*.rej'))
assert rejects == ['fs/proc/task_mmu.c.rej'], rejects
assert Path(rejects[0]).read_text().count('@@') == 4, 'Only the two documented pipa hunks may fail'
PY
  fi
  patch --batch -p1 < ../patches/susfs-n0-fix.patch | tee ../susfs-pipa-fix.log
  grep -q '#include <linux/susfs_def.h>' fs/proc/task_mmu.c
  grep -q 'bypass_orig_flow:' fs/proc/task_mmu.c
  rm -f fs/proc/task_mmu.c.rej
  test -z "$(find . -name '*.rej' -print -quit)"
  bash ../patches/susfs-inline-hooks.sh | tee ../susfs-hooks.log
  grep -q 'ksu_handle_execveat_sucompat' fs/exec.c
  grep -q 'ksu_handle_input_handle_event' drivers/input/input.c
  grep -q 'ksu_handle_setresuid' kernel/sys.c
  grep -q 'SUSFS_VERSION "v2.3.0"' include/linux/susfs.h
  grep -Eq 'KERNEL_SU_UAPI_VERSION = 4;' KernelSU/uapi/supercall.h
  cat >> arch/arm64/configs/pipa_defconfig <<'CFG'
CONFIG_KSU=y
CONFIG_THREAD_INFO_IN_TASK=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_MAP=y
# CONFIG_KPM is not set
# CONFIG_REKERNEL is not set
CFG
  ;;
compile)
  export PATH="$GITHUB_WORKSPACE/clang/bin:$PATH"
  export CCACHE_DIR="$GITHUB_WORKSPACE/.ccache"
  cd device_kernel
  args=(ARCH=arm64 O=out CC="ccache clang" LLVM=1 LLVM_IAS=1 LD=ld.lld \
    CLANG_TRIPLE=aarch64-linux-android- CROSS_COMPILE=aarch64-linux-android- \
    AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip)
  make "${args[@]}" pipa_defconfig
  grep -qx 'CONFIG_KSU=y' out/.config
  grep -qx 'CONFIG_KSU_SUSFS=y' out/.config
  grep -qx 'CONFIG_KALLSYMS_ALL=y' out/.config
  make "${args[@]}" -j"$(nproc)" 2>&1 | tee "$GITHUB_WORKSPACE/build.log"
  test -s out/arch/arm64/boot/Image
  test -s out/arch/arm64/boot/dtbo.img
  test -s out/arch/arm64/boot/dtb
  ;;
package)
  cp device_kernel/out/arch/arm64/boot/{Image,Image.gz,dtb,dtbo.img} artifacts/raw/
  cp device_kernel/out/.config artifacts/evidence/kernel.config
  cp device_kernel/KernelSU/uapi/supercall.h artifacts/evidence/root-uapi.h
  cp device_kernel/include/linux/{susfs.h,susfs_def.h} artifacts/evidence/
  cp source-pins.json artifacts/evidence/
  git -C device_kernel diff --binary > artifacts/evidence/kernel-integration.patch
  git -C device_kernel/KernelSU rev-parse HEAD > artifacts/evidence/root-commit.txt
  cp artifacts/raw/Image.gz anykernel/
  cp artifacts/raw/{dtbo.img,dtb} anykernel/
  (cd anykernel && zip -r ../artifacts/Xiaomi-Pad6-N0-ReSukiSU-4.2.0-rc3-SUSFS-2.3-MIUI-AnyKernel3.zip . -x '.git/*')
  (cd artifacts && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
  ;;
*) exit 2;;
esac
