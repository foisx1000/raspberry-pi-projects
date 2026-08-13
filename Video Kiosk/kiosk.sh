#!/bin/bash
# Plays the kiosk video in an endless loop on the console screen.
# Started at boot by video-kiosk.service. See README.md.

set -u

CONFIG=/etc/kiosk/kiosk.conf
if [ -r "$CONFIG" ]; then
	# shellcheck source=/dev/null
	. "$CONFIG"
fi

VIDEO=${VIDEO:-/opt/kiosk/video.mkv}
LOOP_MODE=${LOOP_MODE:-stream}
AUDIO_DEVICE=${AUDIO_DEVICE:-}
CACHE_BYTES=${CACHE_BYTES:-64MiB}
EXTRA_MPV_OPTS=${EXTRA_MPV_OPTS:-}

WARNING_SECONDS=${WARNING_SECONDS:-8}

# The player takes over the screen through KMS, which a running desktop session
# will not allow. Say so plainly in the log, because mpv only reports it as a
# permission error on the DRM device, which explains nothing on its own.
if systemctl is-active --quiet display-manager 2>/dev/null ||
	[ "$(systemctl get-default 2>/dev/null)" = "graphical.target" ]; then
	echo "This Pi is running the desktop, which holds the screen." >&2
	echo "The kiosk needs the console. Switch it over and reboot:" >&2
	echo "  sudo raspi-config nonint do_boot_behaviour B1 && sudo reboot" >&2
fi

# Shows a message in yellow on the screen, then waits so it can be read.
warn_on_screen() {
	printf '\033[2J\033[H\033[1;33m'
	echo "$1"
	echo
	echo "Starting in ${WARNING_SECONDS} seconds. Press ESC for a console."
	printf '\033[0m'
	sleep "$WARNING_SECONDS"
}

if [ ! -r "$VIDEO" ]; then
	warn_on_screen "No video to play. Expected it at: $VIDEO"
	echo "Kiosk video not found or not readable: $VIDEO" >&2
	exit 1
fi

# Warn if the video cannot loop cleanly. The installer already checked the file
# it fitted and recorded which one that was, so this normally costs nothing.
# The full scan only runs when the video has been changed by hand, because
# reading a large file takes several seconds on a Pi 3.
CHECKER=/usr/local/bin/kiosk-check-video
STAMP=/opt/kiosk/video.ok

if [ -x "$CHECKER" ]; then
	CURRENT=$(stat -c '%s %Y' "$VIDEO" 2>/dev/null || echo unknown)
	if [ "$(cat "$STAMP" 2>/dev/null || true)" != "$CURRENT" ]; then
		if ! CHECK_OUTPUT=$("$CHECKER" "$VIDEO" 2>&1); then
			warn_on_screen "$CHECK_OUTPUT"
		fi
	fi
fi

# Output straight to the screen through KMS/DRM. There is no desktop running,
# so mpv talks to the display hardware itself.
MPV_OPTS=(
	--fullscreen
	--vo=gpu
	--gpu-context=drm
	--hwdec=auto-safe
	--no-osc
	--osd-level=0
	--cursor-autohide=always
	--no-input-default-bindings
	--input-conf=/etc/kiosk/input.conf
	--cache=yes
	--demuxer-max-bytes="$CACHE_BYTES"
	--demuxer-readahead-secs=10
	--msg-level=all=warn
)

if [ -n "$AUDIO_DEVICE" ]; then
	MPV_OPTS+=(--audio-device="$AUDIO_DEVICE")
fi

if [ -n "$EXTRA_MPV_OPTS" ]; then
	# Word splitting is wanted here so several options can be set in kiosk.conf.
	# shellcheck disable=SC2206
	MPV_OPTS+=($EXTRA_MPV_OPTS)
fi

if [ "$LOOP_MODE" = "mpv" ]; then
	# Simple mode: mpv restarts the file itself. Easier to debug, but mpv has to
	# seek back to the start on every loop, which can show a small hiccup.
	exec mpv "${MPV_OPTS[@]}" --loop-file=inf "$VIDEO"
fi

# Seamless mode (default): ffmpeg repeats the file forever and writes one
# never-ending stream into a pipe. mpv reads that pipe and never sees the end of
# the file, so it never seeks and never reloads the decoder. That is what makes
# the loop point invisible.
# systemd makes /run/kiosk for us through RuntimeDirectory= in the unit file,
# owned by the user the service runs as, and passes the path in here. The
# service is not root and cannot create anything under /run itself. When the
# script is run by hand there is no such directory, so fall back to a temporary
# one.
PIPE_DIR=${RUNTIME_DIRECTORY:-}
TEMP_PIPE_DIR=""
if [ -z "$PIPE_DIR" ] || [ ! -w "$PIPE_DIR" ]; then
	TEMP_PIPE_DIR=$(mktemp -d)
	PIPE_DIR=$TEMP_PIPE_DIR
fi
PIPE=$PIPE_DIR/stream.mkv

rm -f "$PIPE"
mkfifo "$PIPE"

ffmpeg -hide_banner -loglevel error \
	-fflags +genpts \
	-stream_loop -1 -i "$VIDEO" \
	-c copy -f matroska -y "$PIPE" &
FFMPEG_PID=$!

# Always take ffmpeg down with us, otherwise it keeps running after a restart.
cleanup() {
	kill "$FFMPEG_PID" 2>/dev/null || true
	rm -f "$PIPE"
	if [ -n "$TEMP_PIPE_DIR" ]; then
		rm -rf "$TEMP_PIPE_DIR"
	fi
	return 0
}
trap cleanup EXIT

mpv "${MPV_OPTS[@]}" --keep-open=no "$PIPE"
exit $?
