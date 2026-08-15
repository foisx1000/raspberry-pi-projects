#!/bin/bash
# Manages the kiosk video service. Asks for sudo itself when it needs it.
#
#   ./service.sh install     copy the script and service into place, enable at boot
#   ./service.sh uninstall   remove them
#   ./service.sh start
#   ./service.sh stop

set -e

NAME=kiosk-video
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=/home/pi/kiosk-video.sh
UNIT=/etc/systemd/system/$NAME.service
TRIGGER=/etc/triggerhappy/triggers.d/$NAME.conf

# Check the command before asking for a password, so a typo does not make you
# authenticate first only to be told it was wrong.
case "${1:-}" in
	install | uninstall | start | stop) ;;
	*)
		echo "Usage: $0 install|uninstall|start|stop" >&2
		exit 1
		;;
esac

# All four need root, so ask once here rather than have you remember which do.
# Re-runs this same script under sudo.
if [ "$(id -u)" -ne 0 ]; then
	exec sudo "$0" "$@"
fi

case "$1" in
	install)
		for cmd in ffmpeg cvlc; do
			if ! command -v "$cmd" >/dev/null; then
				echo "$cmd is not installed. Run: sudo apt install ffmpeg vlc" >&2
				exit 1
			fi
		done
		install -m 755 "$HERE/kiosk-video.sh" "$SCRIPT"
		install -m 644 "$HERE/kiosk-video.service" "$UNIT"

		# ESC on the Pi's own keyboard stops the video. triggerhappy watches
		# /dev/input directly, so it works no matter who owns the screen.
		# Its unit hardcodes --user nobody, which cannot stop a service, hence
		# the override.
		if ! command -v thd >/dev/null; then
			apt-get install -y triggerhappy
		fi
		mkdir -p /etc/triggerhappy/triggers.d
		install -m 644 "$HERE/kiosk-video.trigger" "$TRIGGER"
		mkdir -p /etc/systemd/system/triggerhappy.service.d
		cat > /etc/systemd/system/triggerhappy.service.d/run-as-root.conf <<-'EOF'
			[Service]
			ExecStart=
			ExecStart=/usr/sbin/thd --triggers /etc/triggerhappy/triggers.d/ --socket /run/thd.socket --user root --deviceglob /dev/input/event*
		EOF

		systemctl daemon-reload
		systemctl enable "$NAME"
		systemctl enable triggerhappy
		systemctl restart triggerhappy
		echo "Installed. Start it with: ./service.sh start"
		echo "Press ESC on the Pi's keyboard to stop the video."

		# The video needs the console. Booting to the desktop leaves the
		# compositor owning the screen, and this service has no desktop session
		# to draw into, so nothing appears.
		if [ -t 0 ]; then
			echo
			read -r -p "Boot to the console? The video only plays there. [Y/n] " reply
			case "$reply" in
				n | N)
					echo "Left as it is."
					;;
				*)
					# do_boot_target is what the raspi-config menu uses:
					# B1 console, B2 desktop. There is also an older
					# do_boot_behaviour taking B1-B4, which is where the
					# B1-B4 numbering you may see elsewhere comes from.
					raspi-config nonint do_boot_target B1
					echo "Set to boot to the console, from the next reboot."
					;;
			esac
		fi
		;;
	uninstall)
		systemctl stop "$NAME" 2>/dev/null || true
		systemctl disable "$NAME" 2>/dev/null || true
		rm -f "$UNIT" "$SCRIPT" "$TRIGGER"
		rm -f /etc/systemd/system/triggerhappy.service.d/run-as-root.conf
		systemctl daemon-reload
		systemctl restart triggerhappy 2>/dev/null || true
		echo "Uninstalled."
		;;
	start)
		systemctl start "$NAME"
		systemctl --no-pager status "$NAME" | head -5
		;;
	stop)
		systemctl stop "$NAME"
		echo "Stopped."
		;;
esac
