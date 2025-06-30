function parinstall
  paru -S "$argv[1]" --cleanafter --removemake --skipreview --mflags siCcr --sudo "/usr/bin/sudo"
end
