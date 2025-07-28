#!/usr/bin/env bash
# Depends on GNU parallel, pngquant, jpegoptim, mogrify, and bash >= 4.0+
# Takes files/urls and directories from stdin, and arguments to the script
case "${BASH_VERSION}" in ''|[123].*) printf 'Bash >= 4.0+ required\n' >&2; exit 1; ;; esac

declare -a dirlist imglist pnglist jpglist depth
declare -a hidden=(\( ! -regex '.*/\..*' -a ! -name '*.gif' \))
declare -a depends=(parallel pngquant jpegoptim wget numfmt mogrify)
declare -i threads=16
declare -r urlreg='(https?|s?ftp|file)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|].(png|jpg|jpeg)'
declare opath="${HOME}/compressed/"
declare convpath="${HOME}/converted/"
declare delim=$'\n'
declare convcompress=false

hash -- "${depends[@]}" || { printf 'Unmet dependencies. Quitting..\n' >&2; exit 1; }

_info() {
	cat <<-EOF
		./${0##*/} [options] [files] [directories]

		-0         use NUL as delimiter for stdin rather than newline
		-t INT     threads to use (default: 16)
		-p PATH    path to save compressed images (default: ${HOME}/compressed)
		-nh        don't ignore directories starting with . or ..
		-depth INT limit find's maxdepth to INT
		-cc        convert images to JPG and PNG, compress, and keep the smallest file

	EOF
	exit 0
}

add_imgs(){
	if [[ -f ${1} ]]; then
		imglist+=("${1}")
	elif [[ -d ${1} ]]; then
		dirlist+=("${1}")
	elif [[ ${1} =~ ${urlreg} ]]; then
		wget -q --show-progress --backups=1 "${BASH_REMATCH[0]}"
		imglist+=("${BASH_REMATCH[0]##*/}") 
	fi
}

batchconv(){
	declare -a batchimglist=("${imglist[@]}")
	declare batchsize type

	((${#dirlist[@]})) && {
		while IFS= read -r -d '' img; do
			read -r -d '' type
			case "${type}" in
				image/*) batchimglist+=("${img}") ;;
			esac
		done < <(find "${dirlist[@]}" "${depth[@]}" "${hidden[@]}" -type f -print0 | xargs -0 file -00 --mime-type -nN -e apptype -e ascii -e cdf -e compress -e csv -e encoding -e tar -e json -e text)
	}

	batchsize=$(printf -- '%s\0' "${batchimglist[@]}" | du -bc --files0-from=- 2>/dev/null | awk 'END{printf $1}')
	printf 'Total size of %s found images is %s\n' "${#batchimglist[@]}" "$(numfmt --to=iec "${batchsize}")"
	mkdir -p "${convpath}/jpgs/"
	mkdir -p "${convpath}/pngs/"
	rm -f -- "${convpath}"/jpgs/*
	rm -f -- "${convpath}"/pngs/*
	printf -- 'Converting images to JPG\n'
	printf -- '%s\0' "${batchimglist[@]}" | parallel -0 -j16 --bar "mogrify -format jpg -path ${convpath}jpgs/ 2>/dev/null"
	printf -- 'Converting images to PNG\n'
	printf -- '%s\0' "${batchimglist[@]}" | parallel -0 -j16 --bar "mogrify -format png -path ${convpath}pngs/ 2>/dev/null"
}

rm_bigger_file(){
	declare -a pngs jpgs
	declare jpg basej png jsize psize
	declare batchjpgsize batchpngsize

	mapfile -t -d '' convjpgs < <(find "${convpath}/jpgs/" -type f -name '*.jpg' -print0)

	for jpg in "${convjpgs[@]}"; do
		basej=${jpg##*/}
		png="${convpath}/pngs/${basej%.*}.png"
		if [[ -f ${png} ]]; then
			jsize=$(stat -c%s "${jpg}")
			psize=$(stat -c%s "${png}")
			if ((psize >= jsize)); then
				rm -f -- "${png}"
			else 
				rm -f -- "${jpg}"
			fi
		fi
	done

	mapfile -t -d '' jpgs < <(find "${convpath}jpgs/" -type f -name '*.jpg' -print0)
	mapfile -t -d '' pngs < <(find "${convpath}pngs/" -type f -name '*.png' -print0)
	batchjpgsize=$(printf -- '%s\0' "${jpgs[@]}" | du -bc --files0-from=- 2>/dev/null | awk 'END{printf $1}')
	batchpngsize=$(printf -- '%s\0' "${pngs[@]}" | du -bc --files0-from=- 2>/dev/null | awk 'END{printf $1}')
	printf -- 'Total size for %s compressed JPGs and %s compressed PNGs (%s) is %s\n' "${#jpgs[@]}" "${#pngs[@]}" "$((${#jpgs[@]}+${#pngs[@]}))" "$(numfmt --to=iec "$((batchjpgsize+batchpngsize))")"
	((${#jpgs})) && { printf -- '%s\0' "${jpgs[@]}" | xargs -0r mv -t "${opath}"; }
	((${#pngs})) && { printf -- '%s\0' "${pngs[@]}" | xargs -0r mv -t "${opath}"; }
}

while(($#)); do
	case ${1} in
		-depth) shift; depth=(-maxdepth "${1}") ;;
		-p) shift; opath=${1} ;;
		-t) shift; threads=${1} ;;
		-cc) convcompress=true ;;
		-nh) hidden=() ;;
		-0) delim= ;;
		-h) _info; ;;
		*) add_imgs "${1}" ;;
	esac
	shift
done

mkdir -p -- "${opath}" "${convpath}"
[[ -d ${opath} && -d ${convpath} ]] || exit 1
[[ ${opath: -1} == '/' ]] || opath=${opath}/
[[ ${convpath: -1} == '/' ]] || convpath=${convpath}/

while [[ ! -t 0 ]] && read -r -d "${delim}" line; do
	add_imgs "${line}"
done

((${#dirlist[@]} + ${#imglist[@]})) || {
	hash zenity 2>/dev/null && mapfile -t imglist < <(zenity --file-selection --multiple --file-filter='Image Files (jpg,jpeg,png) | *.jpeg *.jpg *.png' --separator=$'\n')
}

if "${convcompress}"; then
	batchconv
	mapfile -t -d '' pnglist < <(find "${convpath}pngs/" "${depth[@]}" "${hidden[@]}" -type f -iname '*.png' -printf '%p\0')
	mapfile -t -d '' jpglist < <(find "${convpath}jpgs/" "${depth[@]}" "${hidden[@]}" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -printf '%p\0')
	printf -- 'Compressing images\n'
	printf -- '%s\0' "${pnglist[@]}" | parallel -0 -j"${threads}" --bar --plus "pngquant --speed 1 -f -o ${convpath}pngs/{/} {} 2>/dev/null"
	printf -- '%s\0' "${jpglist[@]}" | parallel -0 -j"${threads}" --bar "jpegoptim -q -o -s -m 80 -d ${convpath}jpgs/ {} 2>/dev/null"
	rm_bigger_file
	exit 0
fi

((${#dirlist[@]})) && {
	mapfile -t -d '' pnglist < <(find "${dirlist[@]}" "${depth[@]}" "${hidden[@]}" -type f -iname '*.png' -printf '%p\0')
	mapfile -t -d '' jpglist < <(find "${dirlist[@]}" "${depth[@]}" "${hidden[@]}" -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) -printf '%p\0')
}

for i in "${imglist[@]}"; do
	case ${i} in *.png) pnglist+=("${i}") ;; *.jpg|*.jpeg) jpglist+=("${i}") ;; *) continue; ;; esac
done

((${#pnglist[@]} + ${#jpglist[@]})) || exit 1

((${#pnglist[@]})) && {
	printf -- '%s\0' "${pnglist[@]}" | parallel -0 -j"${threads}" --bar --plus "pngquant --speed 1 -f -o ${opath}{/} {} 2>/dev/null"
	ucsize=$(printf -- '%s\0' "${pnglist[@]}" | du -bc --files0-from=- 2>/dev/null | awk 'END{printf $1}')
	cmpsizecount=$(printf -- "${opath}%s\0" "${pnglist[@]##*/}" | du -bc --files0-from=- | awk 'END{printf $1":"NR-1}')
	cmpsize=${cmpsizecount%:*}
	cmpcount=${cmpsizecount#*:}
	printf -- 'Saved %s for %s/%s PNGs\n' "$(numfmt --to=iec $((ucsize-cmpsize)) 2>/dev/null)" "${cmpcount}" "${#pnglist[@]}"
}

((${#jpglist[@]})) && {
	printf -- '%s\0' "${jpglist[@]}" | parallel -0 -j"${threads}" --bar "jpegoptim -q -o -s -m 80 -d ${opath} {} 2>/dev/null"
	ucsize=$(printf -- '%s\0' "${jpglist[@]}" | du -bc --files0-from=- | awk 'END{printf $1}')
	cmpsizecount=$(printf -- "${opath}%s\0" "${jpglist[@]##*/}" | du -bc --files0-from=- 2>/dev/null | awk 'END{printf $1":"NR-1}')
	cmpsize=${cmpsizecount%:*}
	cmpcount=${cmpsizecount#*:}
	printf -- 'Saved %s for %s/%s JPGs\n' "$(numfmt --to=iec $((ucsize-cmpsize)) 2>/dev/null)" "${cmpcount}" "${#jpglist[@]}"
}

exit 0
