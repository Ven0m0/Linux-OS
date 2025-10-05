# Raspberry pi useful scripts:

[Apt-fuzz](/RaspberryPi/Scripts/apt-fuzz)

Went a bit overboard on [apt-fuzz-dev](/RaspberryPi/Scripts/apt-fuzz-dev)

- Apt fzf/skim tui package manager

  ```bash
  mkdir -p ~/.local/bin
  curl -fsSL 'https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/Scripts/apt-fuzz' -o ~/.local/bin/apt-fuzz && chmod +x ~/.local/bin/apt-fuzz
  ~/.local/bin/apt-fuzz --install
  source "${HOME%/}/.local/share/bash-completion/completions/apt-fuzz" &>/dev/null

  # Dev version:
  curl -fsSL 'https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/Scripts/apt-fuzz-dev' -o ~/.local/bin/apt-fuzz-dev && chmod +x ~/.local/bin/apt-fuzz-dev
  ```

[Debian minify](/RaspberryPi/Scripts/Minify.sh) -> [1](https://github.com/Freifunk-Nord/nord-minify_debian.sh/blob/master/nord-minify_debian.sh) [2](https://github.com/boxcutter/debian/blob/main/script/minimize.sh)

## [Docker cleaner](/RaspberryPi/Scripts/Docker-clean.sh) <sup>[<a href="https://github.com/samoshkin/docker-reclaim-disk-space">1</a>]</sup>

- prints the Docker disk usage information
- interactively prompts you for confirmation
- removes stopped containers
- removes orphan (dangling) images layers
- removes unused volumes
- removes Docker build cache
- shrinks the `Docker.raw` file on MacOS
- restarts the Docker engine (through launchctl on macOS or systemctl on Linux). Waits until the Docker is up and running after the restart.
- prints Docker disk usage once again

### Usage

Using `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/Scripts/Docker-clean.sh | bash
```

pass the `-y` flag to suppress interactive prompts. If you don't want to restart the Docker engine, pass the `--no-restart` flag.

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/Scripts/Docker-clean.sh | bash -s -- -y --no-restart

```

Or just clone the repo and execute the script:

```bash
git clone https://github.com/samoshkin/docker-reclaim-disk-space && chmod +x ./docker-reclaim-disk-space/script.sh && ./docker-reclaim-disk-space/script.sh
```


## Build OS


- https://github.com/OctoPrint/CustoPiZer
- 
