<https://docs.searxng.org/admin/installation-scripts.html#installation-scripts>
<https://docs.searxng.org/admin/installation-nginx.html>

**Install on arch**
```bash
sudo -H pacman -S nginx-mainline
sudo -H systemctl enable --now nginx
git -C "{$HOME}/Downloads" clone https://github.com/searxng/searxng.git searxng && cd "{$HOME}/Downloads/searxng"
sudo -H bash /utils/searxng.sh install nginx
# Later
mkdir -p /etc/nginx/default.d /etc/nginx/default.apps-available
```
