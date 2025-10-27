#!/usr/bin/env bash
# https://cachyos.org/blog/2411-kernel-autofdo/
# https://github.com/CachyOS/cachyos-benchmarker
#https://github.com/CachyOS/CachyOS-PKGBUILDS/tree/master/autofdo-bin
# Setup
WORKDIR="$(builtin cd -- "$(dirname -- "${BASH_SOURCE[0]:-}")" && printf '%s\n' "$PWD")"
builtin cd -- "$WORKDIR" || exit 1
export LC_ALL=C.UTF-8 LANG=C.UTF-8
DIR="${HOME}/projects/kernel"
KERNELDIR="${DIR}/linux/linux-cachyos/linux-cachyos"
AUTOPROF="${KERNELDIR}/kernel-compilation.afdo"
VM_PATH="/usr/lib/modules/6.12.0-rc5-00015-gd89df38260bb/build/vmlinux"
export LLVM=1 LLVM_IAS=1
sudo -v

mkdir -p -- "$KERNELDIR" && cd -- "$KERNELDIR" || exit

# Dependencies
sudo pacman -S --needed --noconfirm perf cachyos-benchmarker llvm clang

# Compile
# https://github.com/torvalds/linux
git clone -b 6.17/cachy https://github.com/CachyOS/linux.git && cd linux || exit

zcat /proc/config.gz >.config
make LLVM=1 LLVM_IAS=1 prepare
## Enable AutoFDO and ThinLTO
scripts/config -e CONFIG_AUTOFDO_CLANG
scripts/config -e CONFIG_LTO_CLANG_THIN

make LLVM=1 LLVM_IAS=1 pacman-pkg -j"$(nproc)"
rm -f -- linux-upstream-api-headers-"$pkgver"

sudo pacman -U linux-upstream-"$pkgver".tar.zst linux-upstream-headers-"$pkgver".tar.zst linux-upstream-debug-"$pkgver".tar.zst

# Profiling
git clone https://github.com/cachyos/linux-cachyos && cd linux-cachyos/linux-cachyos || exit

# Optional
# sudo pacman -S --needed --noconfirm perf llvm-bolt llvm-propeller

# Allow to profile with branch sampling
sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"
sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid"

# Run the CachyOS benchmarker
cachyos-benchmarker "$KERNELDIR"

# Sysbench Tests

echo "Running Sysbench tests..."

# CPU Test
echo "CPU Test:"
sysbench --time=30 cpu --cpu-max-prime=50000 --threads="$NPROC" run

# Memory Tests
echo "Memory Test:"
sysbench memory --memory-block-size=1M --memory-total-size=16G run
sysbench memory --memory-block-size=1M --memory-total-size=16G --memory-oper=read --num-threads=16 run

# I/O Tests
echo "I/O Test:"
sysbench fileio --file-total-size=5G --file-num=5 prepare
sysbench fileio --file-total-size=5G --file-num=5 \
  --file-fsync-freq=0 --file-test-mode=rndrd --file-block-size=4K run
sysbench fileio --file-total-size=5G --file-num=5 \
  --file-fsync-freq=0 --file-test-mode=seqwr --file-block-size=1M run
sysbench fileio --file-total-size=5G --file-num=5 cleanup

# Kernel compilation with AutoFDO Profile

# Intel:
perf record --pfm-events BR_INST_RETIRED.NEAR_TAKEN:k -a -N -b -c 500009 -o kernel.data -- time makepkg -sfci --skipinteg

# AMD:
# perf record --pfm-events RETIRED_TAKEN_BRANCH_INSTRUCTIONS:k -a -N -b -c 500009 -o kernel.data -- time makepkg -sfc --skipinteg

./create_llvm_prof --binary="$VM_PATH" --profile="${KERNELDIR}/kernel.data" --format=extbinary --out="$AUTOPROF"

#pacman -Ql linux-upstream-headers | grep vmlinux

git clone --depth=1 -b 6.12/base git@github.com:CachyOS/linux.git linux

cd -- "${DIR}/linux" || exit
make clean
make LLVM=1 LLVM_IAS=1 CLANG_AUTOFDO_PROFILE="$AUTOPROF" pacman-pkg -j"$(nproc)"
