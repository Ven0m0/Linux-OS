

## [Docker cleaner](/RaspberryPi/Scripts/Docker-clean.sh) &nbsp; <sup>[<a href="https://github.com/samoshkin/docker-reclaim-disk-space">1</a>]</sup>

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
curl -fsSL https://raw.githubusercontent.com/samoshkin/docker-reclaim-disk-space/master/script.sh | bash -s -- -y --no-restart

```

Or just clone the repo and execute the script:

```bash
git clone https://github.com/samoshkin/docker-reclaim-disk-space && chmod +x ./docker-reclaim-disk-space/script.sh && ./docker-reclaim-disk-space/script.sh
```
