# Video Kiosk

Plays a video on an endless loop at boot, on a Raspberry Pi with the desktop.

ffmpeg repeats the file into a pipe and VLC plays that pipe, so the player never
reaches the end of the file and the loop has no gap.

## Setup

Put your video at `/home/pi/video-loop/myvideo.mp4`, then:

```bash
chmod +x service.sh
./service.sh install
./service.sh start
```

It starts automatically at every boot from then on. No need for `sudo` — the script
asks for it when it needs it.

| Command | Does |
| --- | --- |
| `./service.sh install` | Installs the script and service, enables it at boot |
| `./service.sh uninstall` | Removes both |
| `./service.sh start` | Starts it now |
| `./service.sh stop` | Stops it |

## Boot mode

**The Pi has to boot to the console.** Booting to the desktop leaves the compositor
owning the screen, and this service has no desktop session to draw into, so no video
appears. `install` offers to set this for you.

By hand it is `sudo raspi-config` → **System Options → Boot / Auto Login**:

| | Boots to |
| --- | --- |
| `B1` | Console — **what this needs** |
| `B2` | Desktop |

or without the menus: `sudo raspi-config nonint do_boot_target B1`

Logging in automatically is a separate setting, under **System Options → Auto Login**.
The video does not need it: the service starts on its own whether or not anyone logs in.

Note if you follow guides elsewhere: many describe a `B1`–`B4` list where `B2` is
"console autologin". That is an older `raspi-config` function (`do_boot_behaviour`,
still in the file) rather than the menu above, where `B2` means desktop. Setting `B2`
from an old guide would boot you to the desktop and the video would not start.

To change the video path, edit `VIDEO_FILE` at the top of `kiosk-video.sh` and run
`sudo ./service.sh install` again.

Logs: `journalctl -u kiosk-video -b`

## Files

| File | What |
| --- | --- |
| `kiosk-video.sh` | Runs ffmpeg and VLC. Installed to `/home/pi/kiosk-video.sh`. |
| `kiosk-video.service` | systemd unit. Installed to `/etc/systemd/system/`. |
| `service.sh` | Install, uninstall, start, stop. |
