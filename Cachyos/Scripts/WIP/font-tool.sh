# Condense font
fonttools ttLib.scale \
  --x-scale 0.85 \
  --output JetBrainsMonoNerdFont-Condensed.ttf \
  JetBrainsMonoNerdFont.ttf \
  && ttx -o - JetBrainsMonoNerdFont-Condensed.ttf \
  | sed -E \
    -e 's/JetBrains Mono Nerd Font/JetBrains Mono Condensed Nerd Font/g' \
    -e 's/JetBrainsMonoNerdFont/JetBrainsMonoCondensedNerdFont/g' \
    -e 's/(<fontRevision value=")[0-9.]+/\10.900/g' \
    | ttx -o JetBrainsMonoNerdFont-Condensed.ttf /dev/stdin
