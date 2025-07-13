function touch -d "touch + mkdir -p" -w "touch"
  for f in $argv
    set dir (dirname "$f")
    set depth (count (string split '/' "$dir"))
    if test "$dir" = "." -o "$dir" = ""
      command touch "$f"
    else if test $depth[1] -le 4
      mkdir -p "$dir"; and command touch "$f"
    else
      echo "touch: directory for '$f' exceeds limit of 3 slashes" >&2
      return 1
    end
  end
end
