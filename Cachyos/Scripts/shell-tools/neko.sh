#!/usr/bin/env bash

CATEGORY="${1:-neko}"  # default to 'neko' if no argument

IMG_URL=$(curl -s "https://nekos.best/api/v2/$CATEGORY" | jaq -r '.results[0].url')
curl -s "$IMG_URL" | chafa -O 6 -w 4 --clear
