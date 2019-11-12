#!/usr/bin/env bash
# fixup-helper.sh — A quick way to generate fixup-mountpoints for devices from PLATFORM_SDK

# Variables (set on runtime)
version_id="" # e.g. '3.1.0.12'
fstab_file="" # e.g. '.../device/.../fstab.qcom'
par_prefix="" # e.g. '(/dev/)block/bootdevice/by-name'
boardname=""  # e.g. 'cheeseburger'
final_file="" # e.g. '.../hybris/hybris-boot/mountpoints-for-cheeseburger.txt'
partitions="" # e.g. 'lrwxrwxrwx 1 root root 16 1972-04-12 07:45 LOGO -> /dev/block/sde18\n...'

# Functions
msg() { echo "fixup-helper: $@"; }
append() { echo "$@" >> "$final_file"; }

# 1. Make sure we start in the correct dir
if ! cd "$ANDROID_ROOT" &> /dev/null; then
	msg "ERROR: \$ANDROID_ROOT was not set!"
	msg "Please check your configuration files and (re-)enter PLATFORM_SDK"
	exit 1
fi

# 2. Make sure we're in PLATFORM_SDK env
if ! cat /etc/os-release | grep -q Sailfish; then
	msg "ERROR: You are not in the PLATFORM_SDK environment!"
	exit 2
fi

version_id=`cat /etc/os-release | grep VERSION_ID | cut -d'=' -f2`
msg "PLATFORM_SDK env for SFOS $version_id detected"

# 3. Make sure we have ADB
if ! which adb &> /dev/null; then
	# TODO: Override for e.g. 'ls -l /dev/block/bootdevice/by-name/' output from device via arg/file?
	sudo zypper --non-interactive in android-tools-hadk &> /dev/null
	if ! which adb &> /dev/null; then
		msg "ERROR: Couldn't install missing 'android-tools-hadk' package!"
		exit 3
	fi
fi

fstab_file=`find device/ -name fstab* | head -1`

# 4. Find device fstab file
if [ -z "$fstab_file" ]; then
	# TODO: Override for partition prefix via arg/file?
	msg "ERROR: A device fstab file could not be found in '$ANDROID_ROOT/device/'!"
	msg "Have you synced all your sources?"
	exit 4
fi

msg "Using '$fstab_file' as the device fstab file"
fstab_file="$ANDROID_ROOT/$fstab_file"
par_prefix=`cat "$fstab_file" | grep "/dev\/block" | head -1 | xargs | cut -d' ' -f1 | sed 's/\(.*\)\/.*/\1/'`

# 5. Get proper prefix for partitions
if [ -z "$par_prefix" ]; then
	# TODO: Override for partition prefix via arg/file?
	msg "ERROR: Couldn't figure out partition prefix from fstab!"
	exit 5
fi

msg "Prefix for partitions from fstab: '$par_prefix'"

# 6. Wait for a device in recovery mode...
msg "Waiting for a device in recovery mode..."
while true; do
	devices_list=`adb devices`

	# Device in recovery and ADB shell works => continue
	if echo "$devices_list" | grep -q "recovery$"; then
		adb shell "ls" &> /dev/null && break

	# Assume permission issue => restart ADB server
	elif echo "$devices_list" | grep -q "permission"; then
		sudo adb kill-server &> /dev/null
		sudo adb start-server &> /dev/null
		sleep 1

	# Nothing found yet...
	else
		sleep 2
	fi
done

# 7. Attempt to fetch device boardname
# TODO: Use $DEVICE from ~/.hadk.env?
# TODO: Override for boardname via arg/file?
boardname=`adb shell "getprop ro.product.device"`
[[ -z "$boardname" || "$boardname" = *" "* || "$boardname" =~ [A-Z] ]] && boardname=`adb shell "getprop ro.build.product"`

msg "Found your $boardname in recovery mode, building list of mountpoints..."

# 8. Get all device partitions
partitions=`adb shell "ls -l $par_prefix/" | sed '1d'`

# TODO: Make sure we've found the correct pseudo-node for device partitions?

# 9. Generate output file with fixup-mountpoints for the device
par_prefix="${par_prefix:5}" # Remove '/dev/' part for fixup-mountpoints
final_file="$ANDROID_ROOT/hybris/hybris-boot/mountpoints-for-$boardname.txt"
rm -f "$final_file"

# BEGIN
append
append "    \"$boardname\")" # e.g. '    "cheeseburger")'
append "        sed -i \\"

# PARTITIONS
while IFS= read -r line
do
	label=`echo "$line" | cut -d' ' -f8`                   # e.g. 'LOGO'
	dev=`echo "$line" | sed 's|.*/||'`                     # e.g. 'sde18'
	final="            -e 's $par_prefix/$label $dev ' \\" # e.g. '            -e 's block/bootdevice/by-name/LOGO sde18 ' \'
	append "$final"
done < <(printf '%s\n' "$partitions")

# END
append "            \"\$@\""
append "        ;;"
append

msg "We're done here; mountpoints for your device can be found in '\$ANDROID_ROOT/hybris/hybris-boot/mountpoints-for-$boardname.txt'"
msg "Place the generated mountpoints in '\$ANDROID_ROOT/hybris/hybris-boot/fixup-mountpoints' among all other devices"