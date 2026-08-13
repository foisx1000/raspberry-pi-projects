#!/bin/bash
# Installs the video kiosk on a Raspberry Pi. Run it on the Pi, as root:
#
#   sudo ./install.sh myvideo.mp4
#
# Run it again at any time to change the video or update the scripts. Existing
# settings are kept. See README.md.

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
	echo "Run this with sudo." >&2
	exit 1
fi

SOURCE_DIR=$(cd "$(dirname "$0")" && pwd)
VIDEO_DEST=/opt/kiosk/video.mkv
RATE=48000

# ffprobe pads csv output with a trailing comma, and emits CRLF line endings on
# Windows. Strip both, so the values compare cleanly wherever this is run.
clean() {
	tr -d '\r' | sed 's/,*$//'
}

# Copies the video into place, ready to loop.
#
# The picture is copied across untouched, bit for bit. Only the sound is
# rebuilt, so that it ends on exactly the same sample the picture ends on. That
# sounds fussy, but it is the whole trick: ffmpeg starts each repeat after the
# LONGER of the two tracks, so sound that runs even 18 ms past the picture
# freezes the picture for that long on every single pass.
#
# A source that cannot loop cleanly is reported and rejected rather than
# quietly patched up.
install_video() {
	local source=$1
	local facts problems fps frames samples has_audio codec

	if [ ! -r "$source" ]; then
		echo "Cannot read $source" >&2
		exit 1
	fi

	# tools/check-video.sh is the single place that knows what a loopable file
	# looks like. In --facts mode it prints the numbers on stdout, anything
	# unfixable on stderr, and fails only when the picture itself is wrong.
	#
	# Run it through bash rather than executing it, so it works even when the
	# copy on this machine lost its executable bit, which is what happens to a
	# folder copied over from Windows.
	problems=$(mktemp)
	if ! facts=$(bash "$SOURCE_DIR/tools/check-video.sh" --facts "$source" 2>"$problems"); then
		echo "$source cannot be used as a kiosk video:" >&2
		sed 's/^/  - /' "$problems" >&2
		echo "Re-export it and try again." >&2
		rm -f "$problems"
		exit 1
	fi
	rm -f "$problems"
	eval "$facts"

	echo "Video: $codec, $fps fps, $frames frames"

	install -d /opt/kiosk
	if [ -n "$has_audio" ]; then
		echo "Copying the picture as-is and lining the sound up to $samples samples."
		# -c:v copy     the picture is not touched, so nothing is lost
		# apad + atrim  pad with silence if short, then cut to the exact sample
		#               count, so the sound ends where the picture ends
		# -c:a flac     lossless, and gapless: MP3 and AAC carry padding at both
		#               ends that you would hear as a click on every loop
		ffmpeg -hide_banner -loglevel warning -i "$source" \
			-map 0:v:0 -map 0:a:0 \
			-c:v copy \
			-filter:a "aresample=$RATE,apad,atrim=end_sample=$samples" \
			-c:a flac -ar "$RATE" \
			-y "$VIDEO_DEST"
	else
		echo "No sound track, so there is nothing to line up."
		ffmpeg -hide_banner -loglevel warning -i "$source" -map 0:v:0 -c:v copy -y "$VIDEO_DEST"
	fi

	# The frame count proves the picture came across untouched. Anything else
	# would mean it was re-encoded or truncated.
	local frames_out
	frames_out=$(ffprobe -v error -select_streams v -count_packets \
		-show_entries stream=nb_read_packets -of csv=p=0 "$VIDEO_DEST" | clean)
	if [ "$frames_out" != "$frames" ]; then
		echo "ERROR: frame count changed ($frames_out vs $frames). The picture was not copied cleanly." >&2
		exit 1
	fi

	# Now check the fitted file the same way the player will, so a fault is
	# caught here rather than on the wall.
	if ! bash "$SOURCE_DIR/tools/check-video.sh" "$VIDEO_DEST"; then
		echo "ERROR: the fitted video still will not loop cleanly." >&2
		exit 1
	fi

	# Remember which file was checked, so the player can skip re-scanning it at
	# every boot. It only re-checks when the video has been changed by hand.
	stat -c '%s %Y' "$VIDEO_DEST" > /opt/kiosk/video.ok

	echo "Installed $VIDEO_DEST"
	echo
}

# The kiosk runs as a normal user, not as root. Use the user who called sudo,
# or fall back to the first normal account on the system.
KIOSK_USER=${SUDO_USER:-}
if [ -z "$KIOSK_USER" ] || [ "$KIOSK_USER" = "root" ]; then
	KIOSK_USER=$(awk -F: '$3 == 1000 { print $1 }' /etc/passwd | head -n1)
fi
if [ -z "$KIOSK_USER" ]; then
	echo "Could not work out which user should run the kiosk." >&2
	exit 1
fi

echo "Installing the kiosk for user: $KIOSK_USER"
echo

if ! command -v mpv >/dev/null || ! command -v ffmpeg >/dev/null; then
	apt-get update
	apt-get install -y mpv ffmpeg
fi

install -d /opt/kiosk /etc/kiosk
install -m 755 "$SOURCE_DIR/kiosk.sh" /usr/local/bin/kiosk.sh
install -m 755 "$SOURCE_DIR/tools/check-video.sh" /usr/local/bin/kiosk-check-video
install -m 644 "$SOURCE_DIR/input.conf" /etc/kiosk/input.conf

# Keep an existing config so a reinstall does not wipe local settings.
if [ ! -f /etc/kiosk/kiosk.conf ]; then
	install -m 644 "$SOURCE_DIR/kiosk.conf.example" /etc/kiosk/kiosk.conf
	echo "Wrote /etc/kiosk/kiosk.conf"
else
	echo "Kept the existing /etc/kiosk/kiosk.conf"
fi

# Only list groups that really exist, otherwise systemd refuses to start the
# service at all.
GROUPS_FOUND=""
for group in video render input audio tty; do
	if getent group "$group" >/dev/null; then
		GROUPS_FOUND="$GROUPS_FOUND $group"
	fi
done
GROUPS_FOUND=${GROUPS_FOUND# }

sed -e "s|^User=.*|User=$KIOSK_USER|" \
	-e "s|^SupplementaryGroups=.*|SupplementaryGroups=$GROUPS_FOUND|" \
	"$SOURCE_DIR/video-kiosk.service" > /etc/systemd/system/video-kiosk.service

systemctl daemon-reload
systemctl enable video-kiosk.service
echo "Installed the service."
echo

# The video goes last, on purpose. It is the only part that can be rejected,
# and when it is, everything else is already in place: fix the file and run
# this again, rather than starting over.
if [ $# -ge 1 ]; then
	install_video "$1"
fi

if [ ! -f "$VIDEO_DEST" ]; then
	echo "Done, but there is no video yet."
	echo "Run: sudo ./install.sh yourvideo.mp4"
else
	echo "Done. The kiosk starts at the next boot."
	echo "Start it now with: sudo systemctl start video-kiosk"
fi

# The player draws straight to the screen through KMS. A desktop session holds
# the display and will not give it up, so on a Pi that boots to the desktop the
# kiosk starts and immediately dies. Say so here rather than let it fail with
# nothing but a permission error in the journal.
if [ "$(systemctl get-default 2>/dev/null)" = "graphical.target" ]; then
	echo
	echo "=============================================================="
	echo " This Pi boots to the DESKTOP, and the kiosk will not start."
	echo
	echo " The player takes over the screen directly, which a desktop"
	echo " session does not allow. Switch the Pi to booting to the"
	echo " console, then reboot:"
	echo
	echo "     sudo raspi-config nonint do_boot_behaviour B1"
	echo "     sudo reboot"
	echo
	echo " The desktop stays installed; it just no longer starts. On a"
	echo " 1 GB board this also frees a few hundred MB of memory."
	echo "=============================================================="
fi
