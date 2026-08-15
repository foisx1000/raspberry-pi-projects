# Video Kiosk

Plays a video on an endless loop at boot, on a Raspberry Pi with the desktop.

ffmpeg repeats the file into a pipe and VLC plays that pipe, so the player never
reaches the end of the file and the loop has no gap.

## Setup

Put your video at `/home/pi/video-loop/myvideo.mp4`, then:

```bash
chmod +x service.sh
sudo ./service.sh install
sudo ./service.sh start
```

It starts automatically at every boot from then on.

| Command | Does |
| --- | --- |
| `sudo ./service.sh install` | Installs the script and service, enables it at boot |
| `sudo ./service.sh uninstall` | Removes both |
| `sudo ./service.sh start` | Starts it now |
| `sudo ./service.sh stop` | Stops it |

To change the video path, edit `VIDEO_FILE` at the top of `kiosk-video.sh` and run
`sudo ./service.sh install` again.

Logs: `journalctl -u kiosk-video -b`

## Files

| File | What |
| --- | --- |
| `kiosk-video.sh` | Runs ffmpeg and VLC. Installed to `/home/pi/kiosk-video.sh`. |
| `kiosk-video.service` | systemd unit. Installed to `/etc/systemd/system/`. |
| `service.sh` | Install, uninstall, start, stop. |
