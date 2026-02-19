#!/usr/bin/env bash
# setup.sh - CachyOS fresh install setup
set -euo pipefail
shopt -s nullglob globstar
IFS=$'\n\t'
export LC_ALL=C PYTHONOPTIMIZE=1

# When running via curl-pipe, set REPO_RAW to your raw content URL, e.g.:
# curl -fsSL https://raw.githubusercontent.com/USER/REPO/main/setup.sh | REPO_RAW=https://raw.githubusercontent.com/USER/REPO/main bash
REPO_RAW="${REPO_RAW:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-/dev/null}")" 2>/dev/null && pwd || echo "")"

# --- Colors ---
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' DEF=$'\e[0m'

# --- Helpers ---
has()  { command -v "$1" &>/dev/null; }
try()  { "$@" >/dev/null 2>&1 || true; }
log()  { printf '%b\n' "${GRN}[+]${DEF} $*"; }
warn() { printf '%b\n' "${YLW}[!]${DEF} $*"; }
err()  { printf '%b\n' "${RED}[!]${DEF} $*" >&2; }
die()  { err "$*"; exit "${2:-1}"; }

WORKDIR=$(mktemp -d)
cleanup() { set +e; rm -rf "${WORKDIR:-}"; }
trap 'cleanup' EXIT
trap 'err "failed at line $LINENO"' ERR
trap ':' INT TERM

# --- Package list loader ---
# Reads a pkg file: strips blank lines, comments (#), trims whitespace
read_pkgfile() {
  local content="$1"
  while IFS= read -r line; do
    line="${line%%#*}"       # strip inline comments
    line="${line//[[:space:]]/}"
    [[ -n $line ]] && printf '%s\n' "$line"
  done <<< "$content"
}

fetch_pkgfile() {
  local name="$1"  # e.g. "pacman" -> pkg/pacman.txt
  local path="pkg/${name}.txt"

  if [[ -n $SCRIPT_DIR && -f "$SCRIPT_DIR/$path" ]]; then
    cat "$SCRIPT_DIR/$path"
  elif [[ -n $REPO_RAW ]]; then
    curl -fsSL "${REPO_RAW%/}/$path"
  else
    warn "pkg/${name}.txt not found and REPO_RAW not set, skipping"
    return 0
  fi
}

load_pkgs() {
  local name="$1"
  local content
  content="$(fetch_pkgfile "$name")" || return 0
  read_pkgfile "$content"
}

# --- Repo & AUR helper setup ---
pm_detect() {
  for pm in paru yay pacman; do
    has "$pm" && printf '%s' "$pm" && return
  done
}
PKG_MGR="${PKG_MGR:-$(pm_detect)}"

setup_repos() {
  log "Configuring repositories..."

  sudo sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

  if ! grep -q "chaotic-aur" /etc/pacman.conf; then
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
      'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' \
      | sudo tee -a /etc/pacman.conf >/dev/null
  fi

  sudo pacman -Sy --noconfirm

  has paru || {
    sudo pacman -S --needed --noconfirm base-devel git
    git clone https://aur.archlinux.org/paru-bin.git "$WORKDIR/paru-bin"
    (cd "$WORKDIR/paru-bin" && makepkg -si --noconfirm)
  }
  PKG_MGR=paru
}

install_pkgs() {
  log "Installing pacman packages..."
  local -a pacman_pkgs
  mapfile -t pacman_pkgs < <(load_pkgs pacman)
  if (( ${#pacman_pkgs[@]} > 0 )); then
    paru -S --needed --noconfirm "${pacman_pkgs[@]}" || warn "Some pacman packages failed"
  fi

  log "Installing AUR packages..."
  local -a aur_pkgs
  mapfile -t aur_pkgs < <(load_pkgs aur)
  if (( ${#aur_pkgs[@]} > 0 )); then
    paru -S --needed --noconfirm "${aur_pkgs[@]}" || warn "Some AUR packages failed"
  fi
}

install_bun_pkgs() {
  has bun || { warn "bun not found, skipping bun packages"; return 0; }
  log "Installing bun packages..."
  local -a bun_pkgs
  mapfile -t bun_pkgs < <(load_pkgs bun)
  (( ${#bun_pkgs[@]} > 0 )) && bun install -g "${bun_pkgs[@]}" || warn "Some bun packages failed"
}

install_uv_pkgs() {
  has uv || { warn "uv not found, skipping uv packages"; return 0; }
  log "Installing uv/pip packages..."
  local -a uv_pkgs
  mapfile -t uv_pkgs < <(load_pkgs uv)
  (( ${#uv_pkgs[@]} > 0 )) && uv tool install "${uv_pkgs[@]}" || warn "Some uv packages failed"
}

setup_git() {
  local name="${GIT_NAME:-}"
  local email="${GIT_EMAIL:-}"

  if [[ -z $name ]]; then
    read -rp "Git username: " name
  fi
  if [[ -z $email ]]; then
    read -rp "Git email: " email
  fi

  git config --global user.name  "$name"
  git config --global user.email "$email"
  git config --global init.defaultBranch main
  log "Git configured for $name <$email>"
}

readonly DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/Ven0m0/dotfiles.git}"
readonly YADM_DIR="${HOME}/.local/share/yadm/repo.git"

setup_dotfiles() {
  has yadm || { warn "yadm not found, skipping dotfiles"; return 0; }
  if [[ ! -d $YADM_DIR ]]; then
    log "Cloning dotfiles via yadm..."
    # --bootstrap triggers Home/.config/yadm/bootstrap automatically
    yadm clone --bootstrap "$DOTFILES_REPO" || die "yadm clone failed"
  else
    log "Dotfiles already cloned, pulling..."
    yadm pull || warn "yadm pull failed"
    yadm bootstrap || warn "yadm bootstrap failed"
  fi
}

# Called standalone if yadm bootstrap was skipped
deploy_home() {
  local worktree
  worktree="$(yadm config core.worktree 2>/dev/null || printf '%s' "$HOME")"
  local home_dir="${worktree}/Home"
  [[ -d $home_dir ]] || { warn "Home/ not found at $home_dir"; return 0; }
  log "Deploying Home/ → $HOME/..."
  rsync -a --delete --exclude='.git' --exclude='.gitignore' "${home_dir}/" "${HOME}/"
}

configure_shell() {
  log "Configuring shell..."
  mkdir -p "${HOME}/.config" "${HOME}/.local/bin"
  if has zsh; then
    local zsh_path; zsh_path="$(command -v zsh)"
    [[ ${SHELL:-} != "$zsh_path" ]] && \
      chsh -s "$zsh_path" "$USER" 2>/dev/null || warn "chsh failed; run: chsh -s $zsh_path"
  fi
  if has starship && [[ ! -f ${HOME}/.config/starship.toml ]]; then
    starship preset nerd-font-symbols -o "${HOME}/.config/starship.toml"
  fi
}

link_system_configs() {
  local worktree
  worktree="$(yadm config core.worktree 2>/dev/null || printf '%s' "$HOME")"
  local hooks_file="${worktree}/hooks.toml"
  if has tuckr; then
    log "Linking system configs via tuckr..."
    for pkg in etc usr; do
      [[ -d ${worktree}/${pkg} ]] || continue
      local cmd=(sudo tuckr link -d "$worktree" -t / "$pkg")
      [[ -f $hooks_file ]] && cmd+=(-H "$hooks_file")
      "${cmd[@]}" || warn "tuckr failed for $pkg"
    done
  elif has stow; then
    log "Linking system configs via stow (fallback)..."
    for pkg in etc usr; do
      [[ -d ${worktree}/${pkg} ]] || continue
      (cd "$worktree" && sudo stow -t / -d . "$pkg") || warn "stow failed for $pkg"
    done
  else
    warn "Neither tuckr nor stow found; skipping system config deployment"
  fi
}

apply_konsave_profile() {
  has konsave || return 0
  local worktree
  worktree="$(yadm config core.worktree 2>/dev/null || printf '%s' "$HOME")"
  local profile_file="${worktree}/main.knsv"
  [[ -f $profile_file ]] || { warn "main.knsv not found in $worktree"; return 0; }
  local profile_name="main"
  if ! konsave -l 2>/dev/null | grep -qF "$profile_name"; then
    konsave -i "$profile_file" || { warn "konsave import failed"; return 0; }
  fi
  konsave -a "$profile_name" || warn "konsave apply failed"
}

setup_am() {
  if has am; then
    log "am already installed, updating..."
    am --update am
    return 0
  fi
  log "Installing AM (appman)..."
  curl -fsSL "https://raw.githubusercontent.com/ivan-hc/AM/main/INSTALL" \
    | AGREE=y bash >/dev/null
  has am || die "AM installation failed"
  log "Installing AM apps..."
  # Add your apps here, e.g.:
  # am -i am-gui nix-portable
}

setup_rust() {
  has rustup || { warn "rustup not found, skipping"; return 0; }
  log "Setting up Rust..."
  rustup default stable
  rustup target add wasm32-unknown-unknown
  rustup component add rust-std-wasm32-unknown-unknown llvm-bitcode-linker llvm-tools rust-analyzer rust-src
}

setup_flatpak() {
  has flatpak || return 0
  log "Setting up Flatpak..."
  flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --system -y io.github.flattool.Warehouse || true
}

setup_services() {
  log "Enabling services..."
  local svcs=(NetworkManager bluetooth sshd)
  for s in "${svcs[@]}"; do try sudo systemctl enable --now "$s"; done
}

fix_permissions() {
  log "Fixing permissions..."
  if [[ -d $HOME/.ssh ]]; then
    chmod 700 "$HOME/.ssh"
    fd -t f 'id_.*[^.pub]$' "$HOME/.ssh" -x chmod 600
    fd -t f '\.pub$'        "$HOME/.ssh" -x chmod 644
  fi
  if [[ -d $HOME/.gnupg ]]; then
    chmod 700 "$HOME/.gnupg"
    fd -t f '\.gpg$' "$HOME/.gnupg" -x chmod 600
  fi
  if [[ -d $HOME/.local/bin ]]; then
    fd -t f . "$HOME/.local/bin" --no-ignore -x bash -c '[[ -x "$1" ]] || chmod +x "$1"' _ {}
  fi
}

export_pkgs() {
  log "Exporting installed packages..."
  local out="${SCRIPT_DIR:-.}/packages.txt"
  pacman -Qqe > "$out"
  log "Exported to $out"
}

cleanup_orphans() {
  local -a orphans
  mapfile -t orphans < <(pacman -Qdtq 2>/dev/null || true)
  if (( ${#orphans[@]} > 0 )); then
    log "Removing ${#orphans[@]} orphans..."
    try sudo pacman -Rns --noconfirm "${orphans[@]}"
  fi
}

# --- Main ---
main() {
  case "${1:-}" in
    --export) export_pkgs; return 0 ;;
    --help)
      printf 'Usage: %s [--export]\n' "${BASH_SOURCE[0]}"
      printf '  REPO_RAW=URL  fetch pkg/*.txt from remote (for curl-pipe mode)\n'
      return 0 ;;
  esac

  [[ $EUID -eq 0 ]] && die "Run as user, not root."

  setup_repos
  setup_git
  install_pkgs        # pacman + AUR from pkg/*.txt — includes yadm, tuckr/stow, konsave
  setup_dotfiles      # yadm clone --bootstrap → triggers yadm/bootstrap (Home/, tuckr, konsave)
  # These are no-ops if bootstrap already ran them, safe to call again as idempotent fallbacks:
  configure_shell
  link_system_configs
  apply_konsave_profile
  install_bun_pkgs
  install_uv_pkgs
  setup_rust
  setup_am
  setup_flatpak
  setup_services
  fix_permissions
  cleanup_orphans

  try sudo fstrim -av
  log "Setup complete! Reboot recommended."
}

main "$@"
