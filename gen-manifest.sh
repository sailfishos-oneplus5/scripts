#!/usr/bin/env bash
# gen-manifest — Generate build manifests for Android devices with sources on GitHub
IGNORE_DROID_PKGS=1      # ignore repos for APK package sources?
BRANCH_PREFIX="lineage-" # e.g. "cm-" for <= 14.1 sources
DEPS_PREFIX="lineage"    # e.g. "cm" for <= 14.1 sources

FIRST=0 # first instance of script?

# Setup
if [ $# -ne 4 ]; then
	read -p "Who is your device vendor (e.g. 'oneplus')? " VENDOR
	read -p "What is your device boardname (e.g. 'cheeseburger')? " DEVICE
	read -p "Which user's/organization's repos to search through (e.g. 'LineageOS')? " USER
	read -p "Which version is your base (e.g. '16.0')? " BASE
	echo

	[ -z "$VENDOR" ] && VENDOR="oneplus"
	[ -z "$DEVICE" ] && DEVICE="cheeseburger"
	[ -z "$USER" ] && USER="LineageOS"
	[ -z "$BASE" ] && BASE="16.0"

	REPO="android_device_${VENDOR}_${DEVICE}"
	BRANCH="${BRANCH_PREFIX}${BASE}"
	MANIFEST="$VENDOR-$DEVICE.xml"
	FIRST=1
else
	USER="$1"
	REPO="$2"
	BRANCH="$3"
	MANIFEST="$4"
fi

# Fetch dependencies for the current repo (if applicable)
echo "Fetching https://github.com/$USER/$REPO @ $BRANCH..."
deps="$(curl -s https://raw.githubusercontent.com/$USER/$REPO/$BRANCH/$DEPS_PREFIX.dependencies)"
if echo "$deps" | grep -q '^404'; then
	[ $FIRST -eq 1 ] && echo "ERROR: Dependencies for $REPO on branch $BRANCH were not found! Perhaps try something more specific than '$DEVICE'?"
	exit 1
elif [ $FIRST -eq 1 ]; then
	echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<manifest>
	<project path=\"device/$VENDOR/$DEVICE\" name=\"$USER/$REPO\" revision=\"$BRANCH\" />" > "$MANIFEST"
fi

# Recursively fetch dependencies
repos=()
paths=()
for repo in $(echo "$deps" | grep '"repository":' | cut -d'"' -f4); do
	repos+=("$repo")
done
for path in $(echo "$deps" | grep '"target_path":' | cut -d'"' -f4); do
	paths+=("$path")
done
for i in "${!repos[@]}"; do 
	repo="${repos[$i]}"
	path="${paths[$i]}"

	if [ $IGNORE_DROID_PKGS -eq 1 ]; then
		echo "$path" | grep -q '^packages' && continue
	fi

	echo "	<project path=\"$path\" name=\"$USER/$repo\" revision=\"$BRANCH\" />" >> "$MANIFEST"

	bash "$0" "$USER" "$repo" "$BRANCH" "$MANIFEST"
done

# Done
if [ $FIRST -eq 1 ]; then
	echo "</manifest>" >> "$MANIFEST"
	echo
	echo "All done; please see '$MANIFEST'!"
fi
