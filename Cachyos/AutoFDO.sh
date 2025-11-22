#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C.UTF-8 LANG=C.UTF-8 LLVM=1 LLVM_IAS=1
DIR="${HOME}/projects/kernel"
KERNELDIR="${DIR}/linux/linux-cachyos/linux-cachyos"
AUTOPROF="${KERNELDIR}/kernel-compilation.afdo"
VM_PATH="/usr/lib/modules/6.12.0-rc5-00015-gd89df38260bb/build/vmlinux"
NPROC=$(nproc)
sudo -v
mkdir -p "$KERNELDIR" && cd "$KERNELDIR" || exit

sudo pacman -S --needed --noconfirm perf cachyos-benchmarker llvm clang

git clone -b 6.17/cachy https://github.com/CachyOS/linux.git && cd linux || exit
zcat /proc/config.gz >.config
make LLVM=1 LLVM_IAS=1 prepare
scripts/config -e CONFIG_AUTOFDO_CLANG -e CONFIG_LTO_CLANG_THIN
make LLVM=1 LLVM_IAS=1 pacman-pkg -j"$NPROC"
rm -f linux-upstream-api-headers-"$pkgver"
sudo pacman -U linux-upstream{,-headers,-debug}-"$pkgver".tar.zst

git clone https://github.com/cachyos/linux-cachyos && cd linux-cachyos/linux-cachyos || exit
sudo sh -c "echo 0 >/proc/sys/kernel/{kptr_restrict,perf_event_paranoid}"
cachyos-benchmarker "$KERNELDIR"

echo "Running sysbench: CPU, Memory, I/O..."
sysbench cpu --time=30 --cpu-max-prime=50000 --threads="$NPROC" run
sysbench memory --memory-block-size=1M --memory-total-size=16G run
sysbench memory --memory-block-size=1M --memory-total-size=16G --memory-oper=read --num-threads=16 run
sysbench fileio --file-total-size=5G --file-num=5 prepare
sysbench fileio --file-total-size=5G --file-num=5 --file-fsync-freq=0 --file-test-mode=rndrd --file-block-size=4K run
sysbench fileio --file-total-size=5G --file-num=5 --file-fsync-freq=0 --file-test-mode=seqwr --file-block-size=1M run
sysbench fileio --file-total-size=5G --file-num=5 cleanup

perf record --pfm-events BR_INST_RETIRED.NEAR_TAKEN:k -a -N -b -c 500009 -o kernel.data -- time makepkg -sfci --skipinteg
./create_llvm_prof --binary="$VM_PATH" --profile="${KERNELDIR}/kernel.data" --format=extbinary --out="$AUTOPROF"

git clone --depth=1 -b 6.12/base git@github.com:CachyOS/linux.git linux
cd "${DIR}/linux" || exit
make clean
make LLVM=1 LLVM_IAS=1 CLANG_AUTOFDO_PROFILE="$AUTOPROF" pacman-pkg -j"$NPROC"
