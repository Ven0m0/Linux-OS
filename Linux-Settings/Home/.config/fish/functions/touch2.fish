function touch2 --description "touch + mkdir -p"
  for f in $argv
    mkdir -p (dirname -- "$f")
    command touch -- "$f"
  end
end
