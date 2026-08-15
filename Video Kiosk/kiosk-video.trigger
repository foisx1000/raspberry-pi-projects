# Keys that stop the video, pressed on the Pi's own keyboard.
#
# Read by triggerhappy, which watches /dev/input directly. It does not care
# which program owns the screen or the terminal, which is why this works when
# pressing keys at the video does not.
#
# Installed to /etc/triggerhappy/triggers.d/kiosk-video.conf
# Format: <key>[+<modifier>] <1 = pressed> <command>
#
# No blank lines: thd logs a parse error for each one. Comments are fine.
#
# These fire on the physical keyboard whatever is on screen, so while the video
# is playing, typing q or Ctrl+C at a console stops it too. Delete any line you
# would rather not have.
KEY_ESC             1   /usr/bin/systemctl stop kiosk-video
KEY_Q               1   /usr/bin/systemctl stop kiosk-video
KEY_C+KEY_LEFTCTRL  1   /usr/bin/systemctl stop kiosk-video
KEY_C+KEY_RIGHTCTRL 1   /usr/bin/systemctl stop kiosk-video
