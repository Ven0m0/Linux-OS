function touch2 --description "touch + mkdir -p, with tilde handling"
  for f in $argv
    set path (string replace -ra '^~' $HOME $f)
    mkdir -p (dirname -- "$path")
    command touch -- "$path"
  end
end
