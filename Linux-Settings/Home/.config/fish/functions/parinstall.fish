function parinstall -d 'install aur package with paru non-interactively'
  paru -S "$argv[1]" --cleanafter --removemake --skipreview --sudo "/usr/bin/sudo"
end
