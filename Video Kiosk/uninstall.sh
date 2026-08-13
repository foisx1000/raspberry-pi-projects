#!/bin/bash
# Undoes what install.sh did to the Raspberry Pi.
#
#   sudo ./uninstall.sh              ask about the video and the packages
#   sudo ./uninstall.sh --dry-run    only list what would be removed
#   sudo ./uninstall.sh --yes        remove everything without asking
#   sudo ./uninstall.sh --keep-video
#   sudo ./uninstall.sh --keep-packages
#
# This only touches the copies install.sh placed on the system, under
# /usr/local/bin, /etc/kiosk and /opt/kiosk. The folder you cloned is never
# read from or written to, and neither is your original video file wherever you
# keep it.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
	echo "Run this with sudo." >&2
	exit 1
fi

ASSUME_YES=no
KEEP_VIDEO=no
KEEP_PACKAGES=no
DRY_RUN=no

for arg in "$@"; do
	case "$arg" in
		--yes) ASSUME_YES=yes ;;
		--dry-run) DRY_RUN=yes ;;
		--keep-video) KEEP_VIDEO=yes ;;
		--keep-packages) KEEP_PACKAGES=yes ;;
		*) echo "Unknown option: $arg" >&2; exit 1 ;;
	esac
done

# Asks a yes/no question. Answers no by itself when there is nobody to ask, so
# running this from a script never deletes something unexpected.
confirm() {
	local answer
	if [ "$DRY_RUN" = "yes" ]; then
		return 1
	fi
	if [ "$ASSUME_YES" = "yes" ]; then
		return 0
	fi
	if [ ! -t 0 ]; then
		echo "  not asked, so keeping it: nothing to ask on"
		return 1
	fi
	read -r -p "$1 [y/N] " answer
	[ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

# Removes one thing install.sh created, and says so by name.
remove() {
	if [ ! -e "$1" ]; then
		return 0
	fi
	if [ "$DRY_RUN" = "yes" ]; then
		echo "  would remove $1"
	else
		rm -rf "$1"
		echo "  removed $1"
	fi
}

run() {
	if [ "$DRY_RUN" = "yes" ]; then
		echo "  would run: $*"
	else
		"$@" >/dev/null 2>&1 || true
	fi
}

if [ "$DRY_RUN" = "yes" ]; then
	echo "Dry run. Nothing will actually be changed."
else
	echo "Removing the video kiosk. Your cloned folder is not touched."
fi
echo

# Stop the kiosk first, so the screen and tty1 are released before its files go.
echo "The service:"
run systemctl stop video-kiosk.service
run systemctl disable video-kiosk.service
remove /etc/systemd/system/video-kiosk.service
run systemctl daemon-reload
run systemctl reset-failed video-kiosk.service

echo "The installed copies of the scripts and settings:"
remove /usr/local/bin/kiosk.sh
remove /usr/local/bin/kiosk-check-video
remove /etc/kiosk
remove /run/kiosk

# Put the login prompt back on tty1, which the kiosk had taken over.
echo "The login prompt on tty1:"
run systemctl start getty@tty1.service

echo "The fitted copy of the video:"
if [ ! -e /opt/kiosk ]; then
	echo "  nothing there"
elif [ "$KEEP_VIDEO" = "yes" ]; then
	echo "  keeping /opt/kiosk as asked"
elif confirm "  Delete /opt/kiosk, holding the fitted copy of your video?"; then
	remove /opt/kiosk
else
	echo "  keeping /opt/kiosk"
fi

echo "The packages:"
if [ "$KEEP_PACKAGES" = "yes" ]; then
	echo "  keeping mpv and ffmpeg as asked"
elif confirm "  Remove mpv and ffmpeg? Other things on this Pi may use them."; then
	run apt-get remove -y mpv ffmpeg
	run apt-get autoremove -y
	echo "  removed mpv and ffmpeg"
else
	echo "  keeping mpv and ffmpeg"
fi

echo
if [ "$DRY_RUN" = "yes" ]; then
	echo "Nothing was changed. Run without --dry-run to do it."
	exit 0
fi

echo "Done."
echo
echo "Two things this does not undo, because you set them by hand:"
echo "  - the read-only overlay, in raspi-config under Performance Options"
echo "  - the boot screen lines in /boot/firmware/config.txt and cmdline.txt"
