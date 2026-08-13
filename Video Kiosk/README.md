# Video Kiosk

A Raspberry Pi that plays one video full screen on an endless seamless loop, starting by
itself at boot, and survives being unplugged at the wall.

Background and design notes are in [AGENTS.md](AGENTS.md).

## Hardware

- Raspberry Pi 3B or newer. A 3B handles 1080p30; it cannot do 4K.
- Micro SD card, or a USB SSD for a longer life.
- HDMI screen, plus a USB keyboard for setup.

## 1. Operating system

**Raspberry Pi OS Lite** (no desktop). Pick the build by memory, not by board age:

- 1 GB or less (Pi 3B, Zero 2 W) → **32-bit**
- 2 GB or more (Pi 4, Pi 5) → **64-bit**

The player takes over the screen directly, which a desktop session does not allow, so
**the Pi has to boot to the console**. Lite already does. If you already have the
Desktop version installed you do not need to reflash — just stop it booting into the
desktop:

```bash
sudo raspi-config nonint do_boot_behaviour B1
sudo reboot
```

The desktop stays installed, it simply no longer starts. On a 1 GB board that also frees
a few hundred MB. The installer checks this and warns you if the Pi is still set to boot
to the desktop.

Flash it with Raspberry Pi Imager. Open the settings (gear icon) first and set the
hostname, username, password, Wi-Fi and SSH. If you set Wi-Fi there, skip step 2.

## 2. Wi-Fi

```bash
sudo raspi-config nonint do_wifi_country CA
sudo rfkill unblock wifi
nmcli device wifi list
sudo nmcli device wifi connect "NETWORK NAME" password "PASSWORD"
```

Check with `nmcli connection show`. It reconnects on its own at every boot.

Do this **before** step 5, or the settings will not survive a power cut.

## 3. Install

Copy this folder to the Pi, then:

```bash
chmod +x install.sh uninstall.sh
sudo ./install.sh myvideo.mp4
sudo systemctl start video-kiosk
```

If copying the folder from Windows stripped the executable bits, `sudo bash install.sh
myvideo.mp4` works just as well. The other scripts do not need the bit at all — the
installer sets it on the copies it puts in place.

That installs `mpv` and `ffmpeg`, the player script, the service, and your video. Run it
again at any time to change the video or update the scripts — your settings are kept.

### What it does to your video

Your **picture is copied bit for bit**. Nothing is re-encoded and no quality is lost.

Only the sound is rebuilt, so that it ends on exactly the same sample the picture ends
on. Video files routinely have sound running a few milliseconds past the picture, and
that difference freezes the picture on every single pass of the loop. It has to be
corrected in the file before playback, which is why the installer handles it rather than
the player.

### What your video has to be

| Requirement | Why |
| --- | --- |
| H.264 | Hardware decoding on Pi 3B and 4. Not H.265 — no hardware support on a Pi 3. |
| Constant frame rate | Uneven frames shift the loop point. |
| 24, 25, 30, 50 or 60 fps | 29.97 and 23.976 can never line up with the sound. |
| Starts on a keyframe | Otherwise the first frames after the loop have nothing to decode against. |
| 1080p or less on a Pi 3B | It has no more headroom. |

If a file does not meet these, the installer says which part is wrong and stops. It will
not silently alter your video — re-exporting it is up to you.

The clip also has to loop as *content*: the last frame should lead into the first, and
the sound should be at the same level at both ends. No player can hide a cut that does
not join up.

## 4. Working on the Pi

| To do this | Do that |
| --- | --- |
| Stop the video | Press `ESC` or `Ctrl+C`, and you get a login prompt |
| Start it again | `sudo systemctl start video-kiosk` |
| Console without stopping it | `Ctrl+Alt+F2`, or SSH in |
| Stop it starting at boot | `sudo systemctl disable video-kiosk` |
| See what went wrong | `journalctl -u video-kiosk -b` |

Other keys do nothing, so staff cannot pause or mute it by accident. The player is
restarted automatically if it crashes, but not when you quit it on purpose.

## 5. Protect against power cuts

Do this **last**, once everything works, because afterwards the SD card stops recording
changes.

```bash
sudo systemctl disable --now dphys-swapfile
sudo raspi-config
```

Go to **Performance Options → Overlay File System**, enable it, and also write-protect
the boot partition. Reboot. The Pi can now be unplugged at any moment.

To change anything afterwards, turn the overlay off in `raspi-config`, reboot, make the
change, turn it back on, reboot. Otherwise your work disappears at the next power cut.
Worth putting on a label stuck to the Pi.

## 6. Clean boot screen

Optional. In `/boot/firmware/config.txt`:

```text
disable_splash=1
```

Add to the end of the single line in `/boot/firmware/cmdline.txt`:

```text
quiet loglevel=3 logo.nologo vt.global_cursor_default=0 consoleblank=0
```

`consoleblank=0` stops the screen blanking after ten minutes.

If the TV is switched on *after* the Pi boots, the Pi may output nothing. Force a mode
by also adding `video=HDMI-A-1:1920x1080@60D`. Check the connector name with
`ls /sys/class/drm/` — use the part after `card1-`.

## Tools

`tools/` holds scripts that are not part of running the kiosk but are useful around it.

`tools/check-video.sh` says whether a video will loop cleanly, and what is wrong if it
will not. Run it on your desktop before taking a file to the site:

```bash
bash tools/check-video.sh myvideo.mp4
```

The installer puts a copy on the Pi as `kiosk-check-video`, so there it is just:

```bash
kiosk-check-video                # checks the video the kiosk is set to play
kiosk-check-video other.mp4      # checks any file
```

The player runs the same check at startup. If the video has a fault it prints it on
screen in yellow for a few seconds before playing anyway, so a problem is visible on the
wall rather than buried in the logs. This costs nothing on a normal boot: the installer
records which file it already checked, and the scan only repeats if the video was
changed by hand. `WARNING_SECONDS` in `kiosk.conf` sets how long the message stays up.

## Settings

`/etc/kiosk/kiosk.conf` on the Pi holds the video path, audio output, buffer size and
extra mpv options. [`kiosk.conf.example`](kiosk.conf.example) is the same file with
every option explained. Restart the service after editing.

On a 1 GB board set `CACHE_BYTES=32MiB`.

## Uninstall

```bash
sudo ./uninstall.sh
```

This only removes the copies `install.sh` put on the system — under `/usr/local/bin`,
`/etc/kiosk` and `/opt/kiosk` — and puts the login prompt back on tty1. **Your cloned
folder is never touched, and neither is your original video file.** Use `--dry-run`
first to see the exact list of paths.

It asks before deleting the fitted copy of the video and before removing `mpv` and
`ffmpeg`. Add `--yes` to skip the questions, or `--keep-video` / `--keep-packages` to
keep either.

It does not undo the read-only overlay or the boot screen lines, since those were set by
hand in steps 5 and 6.

## Troubleshooting

**Nothing on screen.** `journalctl -u video-kiosk -b`. If mpv reports a DRM or
permission error, it is almost always because the Pi booted to the desktop, which holds
the screen — see step 1. Failing that, check with `id` that the user is in `video` and
`render`.

**Sound from the wrong output.** `mpv --audio-device=help`, then set `AUDIO_DEVICE` in
`kiosk.conf`.

**Stutters.** If `top` shows near 100% CPU the picture is being decoded in software; set
`EXTRA_MPV_OPTS=--hwdec=v4l2m2m-copy`. If it is still pegged, the file is too demanding
for the board — re-export it smaller.

**Visible jump at the loop.** Check the installer reported that picture and sound end
together, then play the file on your desktop. If it jumps there too, it is the content,
not the Pi.

**Changes keep disappearing.** The read-only overlay is on. See step 5.

## Files

| File | Purpose |
| --- | --- |
| `install.sh` | Installs everything, including checking and fitting the video. |
| `uninstall.sh` | Undoes it. `--dry-run` lists what it would remove first. |
| `kiosk.sh` | The player script, installed to `/usr/local/bin/`. |
| `tools/check-video.sh` | Checks a video will loop. Installed as `kiosk-check-video`. |
| `kiosk.conf.example` | All the settings, explained. Copied to `/etc/kiosk/kiosk.conf`. |
| `input.conf` | mpv key bindings, installed to `/etc/kiosk/`. |
| `video-kiosk.service` | systemd unit, installed to `/etc/systemd/system/`. |
