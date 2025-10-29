#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C LANG=C LANGUAGE=C HOME="/home/${SUDO_USER:-$USER}"
cd -P -- "$(cd -P -- "${BASH_SOURCE[0]%/*}" && echo "$PWD")" || exit 1
sudo -v

cargo install etchdns -f
pbin="$(command -v etchdns || echo ${HOME}/.cargo/bin/etchdns)"
sudo ln -sf "$pbin" "/usr/local/bin/$(basename $pbin)"
# sudo chown root:root "/usr/local/bin/$(basename $pbin)"
# sudo chmod 755 "/usr/local/bin/$(basename $pbin)"

# prepare config
sudo touch /etc/etchdns.toml
sudo cat > /etc/etchdns/etchdns.toml <<'EOF'
listen_addresses = ["0.0.0.0:53"]
log_level = "warn"
authoritative_dns = false
upstream_servers = ["1.1.1.2:53","1.0.0.2:53"]
load_balancing_strategy = "fastest"
probe_interval = 60
cache = true
cache_size = 100000
cache_in_memory_only = true
min_cache_ttl = 10
serve_stale_grace_time = 86400
serve_stale_ttl = 60
negative_cache_ttl = 120
prefetch_popular_queries = true
prefetch_threshold = 10
udp_rate_limit_window = 0
tcp_rate_limit_window = 0
doh_rate_limit_window = 0
max_udp_clients = 10000
max_tcp_clients = 1000
max_concurrent_queries = 10000
enable_ecs = true
ecs_prefix_v4 = 24
ecs_prefix_v6 = 56
query_log_include_client_addr = false
query_log_include_query_type = false
block_private_ips = false
block_loopback_ips = false
user = "$USER"
group = "$USER"
metrics_listen_address = "127.0.0.1:9100"
EOF

# create service
sudo cat > /etc/systemd/system/etchdns.service <<'EOF'
[Unit]
Description=EtchDNS high-performance DNS proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/etchdns -c /etc/etchdns/etchdns.toml
User=root
Group=root
LimitNOFILE=65536
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# enable and start
systemctl daemon-reload
systemctl enable --now etchdns

echo "EtchDNS setup complete. Check service status: systemctl status etchdns"
