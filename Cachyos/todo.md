# Todo
- https://wiki.archlinux.org/title/List_of_applications
- https://www.commandlinefu.com/commands/browse
- https://wiki.archlinux.org/title/Domain_name_resolution
- https://github.com/macp3o/linux-tweaks
- https://github.com/644/compressimages

```bash
git clone --depth 1 --shallow-submodules --filter='blob:none'
```

```bash
sudo sysctl -q kernel.perf_event_paranoid="$orig_perf"
echo "$orig_kptr" | sudo tee /proc/sys/kernel/kptr_restrict >/dev/null
echo "$orig_turbo" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo >/dev/null

sync;echo 3 | sudo tee /proc/sys/vm/drop_caches

echo within_size | sudo tee /sys/kernel/mm/transparent_hugepage/shmem_enabled
echo 1 | sudo tee /sys/kernel/mm/ksm/use_zero_pages

echo 1 | sudo tee /proc/sys/kernel/perf_event_paranoid >/dev/null

sudo sh -c "echo 0 > /proc/sys/kernel/kptr_restrict"
sudo sh -c "echo 0 > /proc/sys/kernel/perf_event_paranoid" # 2

sudo sh -c "echo 0 > /proc/sys/kernel/randomize_va_space"
sudo sh -c "echo 0 > /proc/sys/kernel/nmi_watchdog" || (sudo sysctl -w kernel.nmi_watchdog=0)
sudo sh -c "echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo"
sudo sh -c "echo 0 > /sys/devices/system/cpu/intel_pstate/no_turbo"

cargo install fecr
cargo install rustminify-cli
cargo install webcomp
```

## Java:
- https://www.graalvm.org/22.2/reference-manual/native-image/guides/optimize-native-executable-with-pgo
- https://www.graalvm.org/22.2/reference-manual/native-image/optimizations-and-performance/MemoryManagement
- https://github.com/XDream8/kiss-repo/blob/main/bin/openjdk17-jdk/build
- https://gitlab.com/arkboi/dotfiles
- https://lancache.net
- https://github.com/DanielFGray/fzf-scripts
- https://crates.io/crates/autokernel
