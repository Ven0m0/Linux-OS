# Useful shell stuff


<details>
<summary><b>Config file in bash</b></summary>
  
in the script:

```bash
# Load config (if it exists)
CONFIG_FILE="./config.cfg"
[[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
```
in the config file:

```bash
# ~/config.cfg || ~/config.conf
USERNAME="user"
PORT=8080
DEBUG=true
```

</details>


echo "Your Global IP is: $(curl -s https://api.ipify.org/)"
