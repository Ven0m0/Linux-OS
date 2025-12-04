<https://docs.searxng.org/admin/installation-scripts.html#installation-scripts>
<https://docs.searxng.org/admin/installation-nginx.html>

**Install on arch**
```bash
sudo -H pacman -S nginx-mainline
sudo -H systemctl enable nginx
sudo -H systemctl start nginx

git -C "{$HOME}/Downloads" clone https://github.com/searxng/searxng.git searxng
cd -- "{$HOME}/Downloads/searxng"
sudo -H ./utils/searxng.sh install nginx

# Later
mkdir -p /etc/nginx/default.d
mkdir -p /etc/nginx/default.apps-available

```
