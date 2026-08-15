#!/bin/bash
# Manages the kiosk video service.
#
#   sudo ./service.sh install     copy the script and service into place, enable at boot
#   sudo ./service.sh uninstall   remove them
#   sudo ./service.sh start
#   sudo ./service.sh stop

set -e

NAME=kiosk-video
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT=/home/pi/kiosk-video.sh
UNIT=/etc/systemd/system/$NAME.service

case "${1:-}" in
	install)
		install -m 755 "$HERE/kiosk-video.sh" "$SCRIPT"
		install -m 644 "$HERE/kiosk-video.service" "$UNIT"
		systemctl daemon-reload
		systemctl enable "$NAME"
		echo "Installed. Start it with: sudo ./service.sh start"
		;;
	uninstall)
		systemctl stop "$NAME" 2>/dev/null || true
		systemctl disable "$NAME" 2>/dev/null || true
		rm -f "$UNIT" "$SCRIPT"
		systemctl daemon-reload
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
	*)
		echo "Usage: sudo $0 install|uninstall|start|stop" >&2
		exit 1
		;;
esac
