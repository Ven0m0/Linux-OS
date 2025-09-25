# Remove only leading whitespace
sed -i 's/ *//'

#Remove newline\ nextline
sed -i ':a;N;$!ba;s/\n//g'

# Remove empty lines
sed -i '/^$/d'

#Add newline to the end
sed -i '$a\'
