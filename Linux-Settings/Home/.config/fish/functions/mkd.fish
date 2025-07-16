function mkd --description 'create and enter dir'
    mkdir -p $argv[1] && cd $argv[1]
end
