#!/bin/bash
# Checks whether a video will loop seamlessly on the kiosk, and says what is
# wrong if it will not.
#
#   ./check-video.sh                 check the video named in kiosk.conf
#   ./check-video.sh myvideo.mp4     check one file
#   ./check-video.sh --facts FILE    print its numbers as shell assignments
#
# Exit code is 0 if the file will loop cleanly, 1 if it will not.
#
# install.sh uses this to vet a video before fitting it, and kiosk.sh uses it to
# warn on screen at startup. It is also worth running by hand against a file
# before you go out to the site with it.

set -uo pipefail

RATE=48000
FACTS=no

if [ "${1:-}" = "--facts" ]; then
	FACTS=yes
	shift
fi

VIDEO=${1:-}
if [ -z "$VIDEO" ]; then
	# No file given, so use whatever the kiosk is configured to play.
	if [ -r /etc/kiosk/kiosk.conf ]; then
		# shellcheck source=/dev/null
		. /etc/kiosk/kiosk.conf
	fi
	VIDEO=${VIDEO:-/opt/kiosk/video.mkv}
fi

# ffprobe pads csv output with a trailing comma, and emits CRLF line endings on
# Windows. Strip both, so the values compare cleanly wherever this is run.
clean() {
	tr -d '\r' | sed 's/,*$//'
}

# Faults are of two kinds. A PROBLEM is in the picture and cannot be repaired
# without re-exporting the video, so the installer refuses those. A FIXABLE
# fault is in the sound, which the installer rebuilds anyway, so it is expected
# on a source file and only worth reporting on a file already in place.
PROBLEMS=()
FIXABLE=()
problem() {
	PROBLEMS+=("$1")
}
fixable() {
	FIXABLE+=("$1")
}

# Prints everything found, then leaves with the right exit code.
finish() {
	if [ "$FACTS" = "yes" ]; then
		echo "fps=${FPS:-0}"
		echo "frames=${FRAMES:-0}"
		echo "samples=${SAMPLES:-0}"
		echo "has_audio=${HAS_AUDIO:-}"
		echo "codec=${CODEC:-}"
		if [ ${#PROBLEMS[@]} -gt 0 ]; then
			printf '%s\n' "${PROBLEMS[@]}" >&2
		fi
		# Sound faults are what the installer is about to put right, so they
		# are not a reason to stop it.
		[ ${#PROBLEMS[@]} -eq 0 ]
		exit $?
	fi

	if [ ${#PROBLEMS[@]} -eq 0 ] && [ ${#FIXABLE[@]} -eq 0 ]; then
		echo "$VIDEO will loop cleanly."
		echo "${CODEC:-?}, ${FPS:-?} fps, ${FRAMES:-?} frames$NOTE"
		exit 0
	fi

	echo "$VIDEO will not loop cleanly:"
	printf '  - %s\n' ${PROBLEMS[@]+"${PROBLEMS[@]}"} ${FIXABLE[@]+"${FIXABLE[@]}"}
	if [ ${#PROBLEMS[@]} -eq 0 ]; then
		echo "Run install.sh with this file to put that right."
	fi
	exit 1
}

NOTE=""
FPS=0
FRAMES=0
SAMPLES=0
HAS_AUDIO=""
CODEC=""

if [ ! -r "$VIDEO" ]; then
	problem "the file is missing, or cannot be read"
	finish
fi

CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$VIDEO" | clean)
if [ -z "$CODEC" ]; then
	problem "there is no video track in it"
	finish
fi
if [ "$CODEC" != "h264" ]; then
	NOTE=" (not H.264, so a Pi 3B or 4 cannot decode it in hardware)"
fi

# The frame rate has to be a whole number that divides evenly into the $RATE
# samples of sound per second, or picture and sound can never end on the same
# sample. 24, 25, 30, 50 and 60 work. Broadcast rates such as 29.97
# (30000/1001) never can.
R_RATE=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$VIDEO" | clean)
FPS_NUM=${R_RATE%/*}
FPS_DEN=${R_RATE#*/}
if [ "$FPS_DEN" != "1" ] || [ "$FPS_NUM" -le 0 ] 2>/dev/null || [ $((RATE % FPS_NUM)) -ne 0 ] 2>/dev/null; then
	problem "it runs at $R_RATE fps; needs a whole rate that divides into $RATE, so 24, 25, 30, 50 or 60"
	finish
fi
FPS=$FPS_NUM

# The stream has to start on a keyframe, or the first frames after the loop
# point have nothing to decode against.
if [ "$(ffprobe -v error -select_streams v:0 -read_intervals "%+#1" \
	-show_entries frame=key_frame -of csv=p=0 "$VIDEO" | head -n1 | clean)" != "1" ]; then
	problem "it does not start on a keyframe, so the loop point would break"
fi

# Frames must be evenly spaced. This is measured from the timestamps rather
# than read from the file header, because the header happily claims a constant
# rate for files that do not have one. Sorting puts the frames back in display
# order, since B-frames are stored out of order.
UNEVEN=$(ffprobe -v error -select_streams v:0 -show_entries packet=pts_time \
	-of csv=p=0 "$VIDEO" | tr -d '\r,' | sort -n | \
	awk -v fps="$FPS" 'NR > 1 { d = $1 - p; g = 1 / fps
		if (d - g > 0.003 || g - d > 0.003) bad++ } { p = $1 } END { print bad + 0 }')
if [ "$UNEVEN" != "0" ]; then
	problem "$UNEVEN frames are unevenly spaced, so it has a variable frame rate"
fi

FRAMES=$(ffprobe -v error -select_streams v:0 -count_packets \
	-show_entries stream=nb_read_packets -of csv=p=0 "$VIDEO" | clean)
SAMPLES=$((FRAMES * (RATE / FPS)))
HAS_AUDIO=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$VIDEO" | clean)

if [ -n "$HAS_AUDIO" ]; then
	# The picture ends where the frame count says it does. Reading it back from
	# the file would be wrong: with B-frames the packets are stored in decode
	# order, so the last one is not the latest one. Sound has no such
	# reordering, so the furthest point any packet reaches is its end.
	# Matroska rounds timestamps to whole milliseconds, hence the 3 ms.
	VIDEO_END=$(awk -v f="$FRAMES" -v r="$FPS" 'BEGIN { printf "%.6f", f / r }')
	AUDIO_END=$(ffprobe -v error -select_streams a -show_entries packet=pts_time,duration_time \
		-of csv=p=0 "$VIDEO" | tr -d '\r' | \
		awk -F, 'BEGIN { m = 0 } { e = $1 + $2; if (e > m) m = e } END { printf "%.6f", m }')
	if ! awk -v v="$VIDEO_END" -v a="$AUDIO_END" \
		'BEGIN { d = v - a; if (d < 0) d = -d; exit (d < 0.003) ? 0 : 1 }'; then
		fixable "the picture ends at ${VIDEO_END}s but the sound ends at ${AUDIO_END}s, so the loop would freeze by the difference every pass"
	fi

	if [ "$HAS_AUDIO" != "flac" ] && [ "$HAS_AUDIO" != "pcm_s16le" ] && [ "$HAS_AUDIO" != "opus" ]; then
		fixable "the sound is $HAS_AUDIO, which carries padding at both ends that clicks on every loop; it needs to be FLAC"
	fi
fi

finish
