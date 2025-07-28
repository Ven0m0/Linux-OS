#!/bin/bash
echo "Your Global IP is: $(curl -s https://api.ipify.org/)"

location="$(curl -s ipinfo.io/region)"
[[ "$location" != "Bielefeld" ]] && location="Bielefeld"
curl wttr.in/$location?0
