#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
has(){ command -v "$1" &>/dev/null>/dev/null; }
log(){ printf '%b\n' "$*"; }
die(){
  echo "Error: $*" >&2
  exit 1
}
sudo -v

DOTFILES_REPO="git@github.com:Ven0m0/dotfiles.git"
DOTFILES_TOOL="yadm"

if has paru; then
  PKG="paru -S --needed --noconfirm"
  paru -Syu --needed --noconfirm --skipreview &>/dev/null>/dev/null
elif has pacman; then
  PKG="sudo pacman -S --needed --noconfirm"
  sudo pacman -Syu --needed --noconfirm &>/dev/null>/dev/null
elif has apt-get; then
  PKG="sudo apt-get install -y"
  sudo apt-get update -y &>/dev/null>/dev/null && sudo apt-get upgrade -y &>/dev/null>/dev/null
else
  die "No supported package manager found!"
fi

log "Installing $DOTFILES_TOOL & applying dotfiles..."
eval "$PKG" "$DOTFILES_TOOL"

case $DOTFILES_TOOL in
yadm) yadm clone "$DOTFILES_REPO" && yadm bootstrap 2>/dev/null || : ;;
chezmoi) chezmoi init "$DOTFILES_REPO" && chezmoi apply -v ;;
*) git clone "$DOTFILES_REPO" "${HOME}/.dotfiles" && cd "${HOME}/.dotfiles" || exit ;;
esac

localectl set-locale C.UTF-8
sudo chmod -R 700 ~/.{ssh,gnupg}
ssh-keyscan -H {aur.archlinux.org,github.com} >> ~/.ssh/known_hosts 2>/dev/null
[[ -f /etc/doas.conf ]] && sudo chown root:root /etc/doas.conf && sudo chmod 0400 /etc/doas.conf

sudo ufw default allow outgoing
# Allow ports for LocalSend
sudo ufw allow 53317/udp
sudo ufw allow 53317/tcp
# Allow Docker containers to use DNS on host
sudo ufw allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53 comment 'allow-docker-dns'

log "Setup complete!"
sudo sed -i -e s'/\#LogFile.*/LogFile = /'g -e 's/^#CleanMethod = KeepInstalled$/CleanMethod = KeepCurrent/' /etc/pacman.conf

sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com && sudo pacman-key --lsign-key 3056513887B78AEB
sudo pacman --noconfirm --needed -U \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

cat <<'EOF' | sudo tee -a /etc/pacman.conf >/dev/null
[artafinde]
Server = https://pkgbuild.com/~artafinde/repo
[endeavouros]
SigLevel = PackageRequired
Server = https://mirror.alpix.eu/endeavouros/repo/$repo/$arch
EOF

cat <<'EOF' | sudo tee -a /etc/pacman.conf >/dev/null
[xyne-x86_64]
SigLevel = Required
Server = https://xyne.dev/repos/xyne
EOF

# Filesystem optimization (merged from Cachyos/Filesystem.txt)
log "Configuring filesystem optimizations..."
setup_filesystem() {
  local device="${1:-/dev/nvme0n1p2}"

  # Format with ext4 optimizations
  # sudo mkfs.ext4 -b 4096 -O uninit_bg,fast_commit -E lazy_itable_init=1,lazy_journal_init=1 "$device"

  # Tune filesystem for performance
  # sudo tune2fs -E lazy_itable_init=1 lazy_journal_init=1 -o journal_data_writeback nobarrier -O fast_commit "$device"

  log "Note: Filesystem formatting commands are commented out for safety."
  log "Uncomment and specify the correct device if needed."
}

# Configure I/O scheduler
log "Setting up Kyber I/O scheduler..."
setup_io_scheduler() {
  # Create udev rules for Kyber scheduler
  sudo tee /etc/udev/rules.d/60-kyber.rules >/dev/null <<'EOF'
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]|nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="kyber"
ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]|nvme[0-9]*", ATTR{queue/scheduler}="kyber", RUN+="/bin/sh -c 'echo 2000000 > /sys/block/%k/queue/iosched/read_lat_nsec; echo 12000000 > /sys/block/%k/queue/iosched/write_lat_nsec'"
EOF

  # Apply Kyber scheduler to current NVMe device
  if [[ -e /sys/block/nvme0n1/queue/scheduler ]]; then
    echo kyber | sudo tee /sys/block/nvme0n1/queue/scheduler >/dev/null
    echo 2000000 | sudo tee /sys/block/nvme0n1/queue/iosched/read_lat_nsec >/dev/null
    echo 14000000 | sudo tee /sys/block/nvme0n1/queue/iosched/write_lat_nsec >/dev/null
    log "Kyber scheduler applied to nvme0n1"
  fi

  # Reload udev rules
  sudo udevadm control --reload
  sudo udevadm trigger --subsystem-match=block
  log "I/O scheduler configured"
}

setup_io_scheduler

# Kernel parameters documentation and configuration (merged from Linux-Settings/Kernel.txt)
log "Kernel parameter information available..."

# Display kernel parameter recommendations
show_kernel_params() {
  cat <<'EOF'

Recommended Kernel Parameters:
==============================

Performance & Security:
- dma_debug=off
- nompx nopku mem_encrypt=off no-steal-acc
- nohz=on
- page_poison=off powersave=off
- transparent_hugepage=always
- usbhid.mousepoll=1
- usbhid.jspoll=
- usbhid.kbpoll=1
- psmouse.resolution=1600
- tsc=reliable clocksource=tsc
- tsc=deadline
- cpuidle.governor=teo
- NVreg_EnableGpuFirmware=1
- audit=0
- scsi_mod.use_blk_mq=y nosplash

Full cmdline example:
nowatchdog quiet nosplash mitigations=off split_lock_detect=off pcie_aspm.policy=performance pcie_aspm=off clearcpuid=514 systemd.unified_cgroup_hierarchy=1 tsc=reliable clocksource=tsc init_on_alloc=0 init_on_free=0 nvme_core.default_ps_max_latency_us=0 f2fs.flush_merge_segments=1 xfs_mod.defaultcrc=0 cpuidle.governor=teo nohz=on threadirqs page_poison=off NVreg_EnableGpuFirmware=1 usbhid.mousepoll=1 usbhid.kbpoll=1 usbcore.autosuspend=10 scsi_mod.use_blk_mq=y

Bootloader configuration files:
- /boot/limine.conf
- /etc/default/limine
- /boot/loader/entries/linux-cachyos.conf

Intel microcode (add to bootloader):
- initrd /intel-ucode.img
- Limine: module_path: boot():/intel-ucode.img

Additional options:
- XFS: xfs_mod.defaultcrc=0
- Powersave: rcutree.enable_rcu_lazy=1

To verify clocksource:
- sudo dmesg | grep clocksource
- dmesg | grep -i tsc
EOF
}

# Configure CPU governor for performance
setup_cpu_governor() {
  if [[ -d /sys/devices/system/cpu/cpu0/cpufreq ]]; then
    echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
    log "CPU governor set to performance"
  else
    log "CPU frequency scaling not available"
  fi
}

setup_cpu_governor

log ""
log "To view recommended kernel parameters, run: show_kernel_params"
log "Add these parameters to your bootloader configuration as needed."
