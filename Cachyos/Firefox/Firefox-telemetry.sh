#!/usr/bin/env bash

export HOME="/home/${SUDO_USER:-${USER}}" # Keep `~` and `$HOME` for user not `/root`.

echo '--- Disable Firefox Pioneer study monitoring'
pref_name='toolkit.telemetry.pioneer-new-studies-available'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Clear Firefox pioneer program ID'
pref_name='toolkit.telemetry.pioneerId'
pref_value='""'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Minimize Firefox telemetry logging verbosity'
pref_name='toolkit.telemetry.log.level'
pref_value='"Fatal"'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Disable Firefox telemetry log output'
pref_name='toolkit.telemetry.log.dump'
pref_value='"Fatal"'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Disable pings to Firefox telemetry server'
pref_name='toolkit.telemetry.server'
pref_value='""'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Disable Firefox shutdown ping'
pref_name='toolkit.telemetry.shutdownPingSender.enabled'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(
  ~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/
)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi
pref_name='toolkit.telemetry.shutdownPingSender.enabledFirstSession'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi
pref_name='toolkit.telemetry.firstShutdownPing.enabled'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Disable Firefox new profile ping'
pref_name='toolkit.telemetry.newProfilePing.enabled'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Disable Firefox update ping'
pref_name='toolkit.telemetry.updatePing.enabled'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Disable Firefox prio ping'
pref_name='toolkit.telemetry.prioping.enabled'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Disable archiving of Firefox telemetry'
pref_name='toolkit.telemetry.archive.enabled'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Disable detailed telemetry collection in Firefox'
pref_name='toolkit.telemetry.enabled'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

# Disable collection of technical and interaction data in Firefox
echo '--- Disable collection of technical and interaction data in Firefox'
pref_name='datareporting.healthreport.uploadEnabled'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Disable Firefox unified telemetry'
pref_name='toolkit.telemetry.unified'
pref_value='false'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo '--- Clear Firefox telemetry user ID'
pref_name='toolkit.telemetry.cachedClientID'
pref_value='""'
echo "Setting preference \"$pref_name\" to \"$pref_value\"."
declare -a profile_paths=(~/.mozilla/firefox/*/
  ~/.var/app/org.mozilla.firefox/.mozilla/firefox/*/
  ~/snap/firefox/common/.mozilla/firefox/*/)
declare -i total_profiles_found=0
for profile_dir in "${profile_paths[@]}"; do
  if [[ ! -d $profile_dir ]]; then
    continue
  fi
  if [[ ! "$(basename "$profile_dir")" =~ ^[a-z0-9]{8}\..+ ]]; then
    continue # Not a profile folder
  fi
  ((total_profiles_found++))
  user_js_file="${profile_dir}user.js"
  echo "$user_js_file:"
  if [[ ! -f $user_js_file ]]; then
    touch "$user_js_file"
    echo $'\t''Created new user.js file'
  fi
  pref_start="user_pref(\"$pref_name\","
  pref_line="user_pref(\"$pref_name\", $pref_value);"
  if ! grep --quiet "^$pref_start" "$user_js_file"; then
    echo -n $'\n'"$pref_line" >>"$user_js_file"
    echo $'\t'"Successfully added a new preference in $user_js_file."
  elif grep --quiet "^$pref_line$" "$user_js_file"; then
    echo $'\t'"Skipping, preference is already set as expected in $user_js_file."
  else
    sed --in-place "/^$pref_start/c\\$pref_line" "$user_js_file"
    echo $'\t'"Successfully replaced the existing incorrect preference in $user_js_file."
  fi
done
if [[ $total_profiles_found -eq 0 ]]; then
  echo 'No profile folders are found, no changes are made.'
else
  echo "Successfully verified preferences in $total_profiles_found profiles."
fi

echo 'Your privacy and security is now hardened 🎉💪'
echo 'Press any key to exit.'
read -n 1 -s
