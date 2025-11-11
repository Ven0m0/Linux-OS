#!/usr/bin/env bash
# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"
source "${SCRIPT_DIR}/../lib/text.sh"

# Setup environment (LC_ALL and LANG already set by common.sh)
setup_environment

# https://github.com/kboghdady/youTube_ads_4_pi-hole
# check to see if gawk is installed. if not it will install it
dpkg -l | grep -qw gawk || sudo apt-get install mawk -y

# remove the duplicate records in place
#mawk -i inplace '!a[$0]++' $blackListFile
wait 
#mawk -i inplace '!a[$0]++' $blacklist

# https://github.com/hectorm/hblock/blob/master/hblock
# Remove comments from string.
removeComments(){ sed -e 's/[[:blank:]]*#.*//;/^$/d'; }

# Remove reserved Top Level Domains.
removeReservedTLDs(){
	sed -e '/\.corp$/d' \
		-e '/\.domain$/d' \
		-e '/\.example$/d' \
		-e '/\.home$/d' \
		-e '/\.host$/d' \
		-e '/\.invalid$/d' \
		-e '/\.lan$/d' \
		-e '/\.local$/d' \
		-e '/\.localdomain$/d' \
		-e '/\.localhost$/d' \
		-e '/\.test$/d'
}

		# Read the sources file ignoring comments or empty lines.
		removeComments < "${sourcesFile:?}" > "${sourcesUrlFile:?}"

  
	# If the blocklist file is not empty, it is filtered and sorted.
	if [ -s "${blocklistFile:?}" ]; then
		if [ "${filterSubdomains:?}" = 'true' ]; then
			printInfo 'Filtering redundant subdomains'
			awkReverseScript="$(cat <<-'EOF'
				BEGIN { FS = "." }
				{
					for (i = NF; i > 0; i--) {
						printf("%s%s", $i, (i > 1 ? FS : RS))
					}
				}
			EOF
			)"
			awkFilterScript="$(cat <<-'EOF'
				BEGIN { p = "." }
				{
					if (index($0, p) != 1) {
						print($0); p = $0"."
					}
				}
			EOF
			)"
    fi
  		printInfo 'Sorting blocklist'
		sort < "${blocklistFile:?}" | uniq | sponge "${blocklistFile:?}"
	fi

	# If the blocklist file is not empty, it is sanitized.
	if [ -s "${blocklistFile:?}" ]; then
		printInfo 'Sanitizing blocklist'
		sanitizeBlocklist "${lenient:?}" < "${blocklistFile:?}" | removeReservedTLDs | sponge "${blocklistFile:?}"
	fi

	# If the allowlist file is not empty, the entries on it are removed from the blocklist file.
	if [ -s "${allowlistFile:?}" ]; then
		printInfo 'Applying allowlist'
		allowlistPatternFile="$(createTemp 'file')"
		# Entries are treated as regexes depending on whether the regex option is enabled.
		removeComments < "${allowlistFile:?}" >> "${allowlistPatternFile:?}"
		if [ "${regex:?}" = 'true' ]; then
			grep -vf "${allowlistPatternFile:?}" -- "${blocklistFile:?}" | sponge "${blocklistFile:?}"
		else
			grep -Fxvf "${allowlistPatternFile:?}" -- "${blocklistFile:?}" | sponge "${blocklistFile:?}"
		fi
		rm -f -- "${allowlistPatternFile:?}"
	fi

	# If the blocklist file is not empty, it is filtered and sorted.
	if [ -s "${blocklistFile:?}" ]; then
		if [ "${filterSubdomains:?}" = 'true' ]; then
			printInfo 'Filtering redundant subdomains'
			awkReverseScript="$(cat <<-'EOF'
				BEGIN { FS = "." }
				{
					for (i = NF; i > 0; i--) {
						printf("%s%s", $i, (i > 1 ? FS : RS))
					}
				}
			EOF
			)"
			awkFilterScript="$(cat <<-'EOF'
				BEGIN { p = "." }
				{
					if (index($0, p) != 1) {
						print($0); p = $0"."
					}
				}
			EOF
			)"
			awk "${awkReverseScript:?}" < "${blocklistFile:?}" | sort \
				| awk "${awkFilterScript:?}" | awk "${awkReverseScript:?}" \
				| sponge "${blocklistFile:?}"
		fi

		printInfo 'Sorting blocklist'
		sort < "${blocklistFile:?}" | uniq | sponge "${blocklistFile:?}"
	fi
 
