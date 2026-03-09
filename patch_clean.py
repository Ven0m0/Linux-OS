import re

with open('Cachyos/clean.sh', 'r') as f:
    content = f.read()

def repl(m):
    return """    local -a cache_dirs=("/var/cache/pacman/pkg" "${HOME}/.cache/paru/clone" "${HOME}/.cache/yay")
    local -i total_before=0 total_after=0
    for d in "${cache_dirs[@]}"; do
      (( total_before += $(get_cache_size "$d") ))
    done"""

content = re.sub(r'    pacman_before=\$\(get_cache_size "/var/cache/pacman/pkg"\)\n    paru_before=\$\(get_cache_size "\$\{HOME\}/\.cache/paru/clone"\)\n    yay_before=\$\(get_cache_size "\$\{HOME\}/\.cache/yay"\)', repl, content, count=1)

def repl2(m):
    return """    for d in "${cache_dirs[@]}"; do
      (( total_after += $(get_cache_size "$d") ))
    done
    total_freed=$(( total_before - total_after ))"""

content = re.sub(r'    pacman_after=\$\(get_cache_size "/var/cache/pacman/pkg"\)\n    paru_after=\$\(get_cache_size "\$\{HOME\}/\.cache/paru/clone"\)\n    yay_after=\$\(get_cache_size "\$\{HOME\}/\.cache/yay"\)\n    total_freed=\$\(\(\(pacman_before - pacman_after\) \+ \(paru_before - paru_after\) \+ \(yay_before - yay_after\)\)\)', repl2, content, count=1)

with open('Cachyos/clean.sh', 'w') as f:
    f.write(content)
