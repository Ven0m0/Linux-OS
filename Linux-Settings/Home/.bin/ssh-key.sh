EmailL=""
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/pi_ed25519 -C "${email}"
Target=""
ssh-copy-id -i ~/.ssh/pi_ed25519.pub dietpi@192.168.178.86
