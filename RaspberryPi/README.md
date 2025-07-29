# <img height="30" src="https://raw.githubusercontent.com/Ven0m0/Ven0m0/refs/heads/main/Images/raspride.avif" alt="Pi"> Raspberry pi related stuff


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
```

<details>
<summary><b>Tools</b></summary>

- [cylon-deb](https://github.com/gavinlyonsrepo/cylon-deb)

</details>

<details>
<summary><b>Raspberry pi os on f2fs</b></summary>

- download an os image ([DietPi](https://dietpi.com) or [Raspberry Pi OS](https://www.raspberrypi.com/software))
- change the filenames to fit your usecase in [raspberry-fs.sh](RaspberryPi/raspberry-fs.sh)
- have [raspberry_f2fs.sh](RaspberryPi/raspberry_f2fs.sh) and the image in the same path as the raspberry-fs.sh script
- answer the prompts
- success

</details>

<details>
<summary><h2><a href="https://casaos.zimaspace.com">CasaOS</a></h2></summary>
  
```bash
sudo casaos-uninstall
curl -fsSL https://get.casaos.io | sudo bash
```

</details>

## [CasaOS](https://casaos.zimaspace.com)
```
sudo casaos-uninstall
curl -fsSL https://get.casaos.io | sudo bash
```

### Update
```
curl -fsSL https://get.casaos.io/update | sudo bash
```


[Runtipi](https://runtipi.io)

[cosmos](https://cosmos-cloud.io)

[yunohost](https://yunohost.org)

[Homepage docker](https://github.com/gethomepage/homepage)
