#!/bin/sh
# Installs or removes the Gravity Circuit Archipelago client in the game's Proton prefix (Linux / Steam Deck).
#   sh install.sh                     install
#   sh install.sh --uninstall         remove (saves, connection settings and logs are kept)
#   sh install.sh /path/to/save/dir   use this save folder instead of searching for the Proton prefix
set -e

APPID=858710
HERE=$(cd "$(dirname "$0")" && pwd)

# Release zips ship the client as ./mod; in the repository it lives in ../client.
SRC="$HERE/mod"
[ -d "$SRC" ] || SRC="$HERE/../client"

UNINSTALL=0
SAVE_DIR=""
for arg in "$@"; do
  case "$arg" in
    --uninstall|-u) UNINSTALL=1 ;;
    *) SAVE_DIR="$arg" ;;
  esac
done

find_prefix_save_dir() {
  for root in "$HOME/.steam/steam" "$HOME/.local/share/Steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
    [ -d "$root/steamapps" ] || continue
    libs="$root"
    if [ -f "$root/steamapps/libraryfolders.vdf" ]; then
      libs="$libs
$(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$root/steamapps/libraryfolders.vdf")"
    fi
    echo "$libs" | while IFS= read -r lib; do
      dir="$lib/steamapps/compatdata/$APPID/pfx/drive_c/users/steamuser/AppData/Roaming"
      if [ -d "$dir" ]; then
        echo "$dir/Gravity Circuit"
        return 0
      fi
    done
  done
}

if [ -z "$SAVE_DIR" ]; then
  SAVE_DIR=$(find_prefix_save_dir | head -n 1)
fi
if [ -z "$SAVE_DIR" ]; then
  echo "Could not find Gravity Circuit's Proton prefix (steamapps/compatdata/$APPID)."
  echo "Start the game once from Steam so the prefix exists, then run this again,"
  echo "or pass the save folder yourself: sh install.sh \"/path/to/AppData/Roaming/Gravity Circuit\""
  exit 1
fi

AP_DIR="$SAVE_DIR/archipelago"

if [ "$UNINSTALL" = 1 ]; then
  rm -f "$SAVE_DIR/main.lua"
  [ -d "$AP_DIR" ] && rm -f "$AP_DIR"/*.lua
  echo "Removed the Archipelago client from $SAVE_DIR. Saves, connection settings and logs were kept."
  exit 0
fi

mkdir -p "$AP_DIR"
cp "$SRC/main.lua" "$SAVE_DIR/"
cp "$SRC"/archipelago/*.lua "$AP_DIR/"
echo "Installed to $SAVE_DIR"
echo "Start Gravity Circuit, press F9, enter server/slot/password, then start a NEW GAME in an empty slot."
