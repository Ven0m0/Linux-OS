# <img height="20" src="https://cdn.freebiesupply.com/logos/large/2x/raspberry-pi-logo-png-transparent.png" alt="Pi"> Raspberry pi related stuff


### Updates

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/update.sh | bash
```

### Cleaning

```bash
curl -fsSL https://raw.githubusercontent.com/Ven0m0/Linux-OS/refs/heads/main/RaspberryPi/PiClean.sh | bash
```

### Settings todo

```markdown
net.ipv4.ip_forward=1
https://gitlab.com/volian/nala/-/blob/main/docs/nala-fetch.8.rst?ref_type=heads
```

<details>
<summary><b>Tools</b></summary>

- [Pi-Apps-bash](https://github.com/Itai-Nelken/PiApps-terminal_bash-edition)

	```bash
	wget -qO- https://raw.githubusercontent.com/Itai-Nelken/PiApps-terminal_bash-edition/main/install.sh | bash
	```
 
- [cylon-deb](https://github.com/gavinlyonsrepo/cylon-deb)

</details>
<details>
<summary><b>Raspberry pi os on f2fs</b></summary>

- download an os image ([DietPi](https://dietpi.com) or [Raspberry Pi OS](https://www.raspberrypi.com/software))
- change the filenames to fit your usecase in [raspberry-fs.sh](RaspberryPi/raspberry-fs.sh)
- have [raspberry_f2fs.sh](RaspberryPi/raspberry_f2fs.sh) and the image in the same path as the raspberry-fs.sh script
- answer the prompts
- success

further links:
* https://github.com/aarontc/raspbian-f2fs
* https://github.com/d-a-v/raspbian-f2fs
* https://github.com/timothybrown/raspbian-f2fs
  
</details>
<details>
<summary><b>Dieti:</b></summary>

- Raspberry pi 4: LEMP (Ngix, Mariadb, PHP)
- Raspberry pi 3: LLSP (Lighttpd, Sqlite, PHP


[Ngix](https://docs.nginx.com/nginx/admin-guide)
[Lighttpd](https://www.lighttpd.net)
[MariaDB](https://mariadb.org/documentation/#getting-started)
[Sqlite](https://www.sqlite.org/quickstart.html)


</details>
<details> 
<summary><b>CasaOS</b></summary>

- Install [CasaOS](https://casaos.zimaspace.com)

```bash
sudo casaos-uninstall
curl -fsSL https://get.casaos.io | sudo bash
```

- Update

```bash
curl -fsSL https://get.casaos.io/update | sudo bash
```

</details>
<details>
<summary><b>Other selfhost tools/OS's</b></summary>
  
- [DietPi](https://dietpi.com)

- [NextcloudPi](https://github.com/nextcloud/nextcloudpi)

- [Runtipi](https://runtipi.io)
  <details>
    <summary><b>Install</b></summary>

    ```bash
    curl -L https://setup.runtipi.io | bash
    ```

  </details>

- [cosmos](https://cosmos-cloud.io)
  <details>
    <summary><b>Install</b></summary>

    https://cosmos-cloud.io/doc/1%20index/#automatic-installation
    ```bash
    # IF YOU NEED TO CHANGE THE PORTS, DO IT BEFORE RUNNING THE COMMAND
    # You can overwrite any other env var by adding them here
    export COSMOS_HTTP_PORT=80 COSMOS_HTTPS_PORT=443
    
    # You can run a dry run to see what will be installed
    curl -fsSL https://cosmos-cloud.io/get.sh | sudo -E bash -s -- --dry-run
    
    # If you are happy with the result, you can run the command
    curl -fsSL https://cosmos-cloud.io/get.sh | sudo -E bash -s
    ```
    One liner:
    ```bash
    env COSMOS_HTTP_PORT=80 COSMOS_HTTPS_PORT=443 curl -fsSL https://cosmos-cloud.io/get.sh | sudo -E bash -s
    ```
  </details>

- [yunohost](https://yunohost.org)

- [Homepage docker](https://github.com/gethomepage/homepage)
  <details>
    <summary><b>Install</b></summary>
    
    ```bash
    docker run --name homepage \
      -e HOMEPAGE_ALLOWED_HOSTS=gethomepage.dev \
      -e PUID=1000 \
      -e PGID=1000 \
      -p 3000:3000 \
      -v /path/to/config:/app/config \
      -v /var/run/docker.sock:/var/run/docker.sock:ro \
      --restart unless-stopped \
      ghcr.io/gethomepage/homepage:latest
    ```
  </details>

- [ShellHub](https://www.shellhub.io)

- [cloudflare tunnel](https://github.com/phipcode/phiptechblog/tree/main/cloudflaretunnel)

</details>
<details>
<summary><b>Self-hosting services</b></summary>

- [Nextcloud](https://docs.nextcloud.com/server/latest/admin_manual/contents.html)

- [Owncloud](https://doc.owncloud.com/server/next/)

- [Web-filebrowser](https://filebrowser.org/index.html)

- [NFS/Samba](https://dietpi.com/docs/software/file_servers)

- [Gitea](https://docs.gitea.com/)

<details>
<summary><b>DNS Adblock/OS's</b></summary>

- [Pihole](https://pi-hole.net)

- [Adguard](https://github.com/AdguardTeam/AdGuardHome)

- [Technitium](https://technitium.com/dns)

- [Blocky](https://0xerr0r.github.io/blocky/latest)

- [Stubby](https://github.com/getdnsapi/stubby)

</details>
<details>
<summary><b>Resources</b></summary>

- [Awesome-selfhosted](https://awesome-selfhosted.net/tags/web-servers.html)

</details>
