# My Toolkit

### media-optimizer.sh 

***dependencies:***

- For Arch: ```sudo pacman -S imagemagick libwebp jpegoptim pngquant oxipng svt-av1```
- For Debian: ```sudo apt install imagemagick webp jpegoptim pngquant svt-av1```
- For Termux: ```pkg install imagemagick libwebp jpegoptim pngquant```
- Rust tools (optional but recommended): ```cargo install compresscli imgc simagef pixelsqueeze ffzap```

- For SVT-AV1 video encoding:
  ```bash
  git clone https://github.com/nekotrix/SVT-AV1-Essential && cd SVT-AV1-Essential && bash install.sh
  ```
  or ```paru --skipreview --noconfirm -S svt-av1-essential-git```
