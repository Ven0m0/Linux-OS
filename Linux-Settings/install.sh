cd "$(dirname "${BASH_SOURCE:-}")"

git pull --rebase origin main

do_it() {
	local a=()
	a+=(
		--exclude .git/ \
		--exclude .gitattributes \
		--exclude install.sh \
		--exclude README\* \
		--exclude LICENSE \
		-avh --no-perms . ~
	)
	rsync "${a[@]}"
	\. ~/.bashrc
}

if [[ ${1:-} = --force || ${1:-} = -f ]]; then
	do_it
else
	#shellcheck disable=SC2016
	read -rp 'This may overwrite existing files in your `$HOME` directory. Are you sure? (y/n) ' -n 1
	echo
	[[ $REPLY =~ ^[Yy]$ ]] && do_it
fi
unset do_it
