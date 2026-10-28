#!/usr/bin/env bash
# installs the Rojo plugin into Roblox Studio on Linux
#
# `rojo plugin install` says "Your platform is not currently supported", it
# only knows the Windows and macOS paths. under Vinegar Studio runs in a Wine
# prefix inside the flatpak sandbox, so the plugin has to be copied there by hand
#
# the prefix gets created the first time Studio starts, so run this after
# opening it at least once

set -euo pipefail

PLUGIN_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/Rojo.rbxm"
VINEGAR_DATA="$HOME/.var/app/org.vinegarhq.Vinegar/data/vinegar"

# plugin version has to match the server version in rokit.toml or Rojo refuses
# to connect
ROJO_VERSION="$(sed -n 's/^rojo = "rojo-rbx\/rojo@\(.*\)"/\1/p' \
	"$(dirname "${BASH_SOURCE[0]}")/../../rokit.toml")"
ROJO_VERSION="${ROJO_VERSION:-7.7.0}"

if [[ ! -f "$PLUGIN_SRC" ]]; then
	echo "Downloading the Rojo plugin $ROJO_VERSION..."
	curl -fsSL -o "$PLUGIN_SRC" \
		"https://github.com/rojo-rbx/rojo/releases/download/v${ROJO_VERSION}/Rojo.rbxm" || {
		echo "Download failed, grab it by hand from:" >&2
		echo "  https://github.com/rojo-rbx/rojo/releases/tag/v${ROJO_VERSION}" >&2
		echo "and put it in $PLUGIN_SRC" >&2
		exit 1
	}
fi

if [[ ! -d "$VINEGAR_DATA" ]]; then
	echo "Vinegar has no data in $VINEGAR_DATA yet" >&2
	echo "Start Roblox Studio once, then run this script again." >&2
	exit 1
fi

# the plugin goes in the Wine user's AppData inside the prefix. there's also a
# Plugins folder under versions/, but that's the Studio install and it gets
# wiped on every update: a plugin put there would vanish after a few days
mapfile -t APPDATA < <(
	find "$VINEGAR_DATA/prefixes" -maxdepth 8 -type d -ipath '*users/*/AppData/Local' 2>/dev/null
)

if [[ ${#APPDATA[@]} -eq 0 ]]; then
	echo "No Wine prefix under $VINEGAR_DATA/prefixes" >&2
	echo "Open Roblox Studio once (just studio) and try again." >&2
	exit 1
fi

TARGET="${APPDATA[0]}/Roblox/Plugins"
mkdir -p "$TARGET"

cp -f "$PLUGIN_SRC" "$TARGET/Rojo.rbxm"
echo "Plugin installed in:"
echo "  $TARGET/Rojo.rbxm"
echo

# Studio only scans the plugin folder on startup, if it's open right now the
# plugin won't show up until it's restarted
if pgrep -f "RobloxStudioBeta.exe" >/dev/null 2>&1; then
	echo "HEADS UP: Studio is open and only reads plugins on startup."
	echo "Close it and open it again (just studio) or you won't see Rojo."
else
	echo "Start Studio with 'just studio'."
fi
echo "Then Plugins > Rojo > Connect, with 'just serve' running."
