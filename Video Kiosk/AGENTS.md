# Video Kiosk — design notes

Background for anyone (person or agent) changing this project. `README.md` is the
short practical guide and should stay that way; reasoning belongs here.

## The one hard requirement

The loop must show no gap, flicker or click. Everything below exists to serve that.
When changing anything here, verify the loop is still exact rather than assuming.

## How the seamless loop works

Telling a player to "loop the file" makes it play to the end, seek back, and resume.
That seek costs time and shows as a flicker. It is the usual reason kiosk loops look
wrong, and `mpv --loop-file=inf` is not free of it.

Instead, `ffmpeg -stream_loop -1` reads the file over and over and writes **one endless
stream** into a FIFO, renumbering timestamps so they run continuously. `mpv` reads that
FIFO. The player never sees an end of file, so it never seeks and never resets the
decoder. Video packets are copied, not re-encoded, so it costs almost no CPU.

The FIFO matters: if ffmpeg were piped to mpv's stdin, mpv would lose the terminal and
`ESC` would stop working. Reading from a FIFO path leaves stdin attached to the tty.

`LOOP_MODE=mpv` in `kiosk.conf` switches to plain `--loop-file=inf`. Keep it — it is
useful for isolating whether a fault is in the loop machinery or elsewhere.

## Why the video file has strict requirements

`ffmpeg -stream_loop` starts each repeat after the **longer** of the two streams. If the
sound runs even slightly past the picture, every repeat starts late and the picture
freezes for that long, on every pass.

This is not hypothetical. A plain `ffmpeg -i in.mp4 ... out.mkv` produced a file whose
video ended at 3.000s and whose audio ended at 3.018s — an 18 ms freeze, over half a
frame at 30 fps, forever. It is invisible unless measured.

So `install_video()` forces the sound to exactly `frames × (48000 ÷ fps)` samples. That
is also why the frame rate must be a whole number that divides into 48000: at 29.97 fps
(30000/1001) no whole number of samples ever lines up with a whole number of frames, so
such a file can never loop perfectly. Do not add a workaround for fractional rates —
there isn't one.

## Why the fitting happens at install time, not playback

This was questioned, and the answer is that playback cannot do it:

- `-stream_loop` needs a **seekable** input. It cannot loop a pipe, so the aligned data
  cannot be produced by an upstream ffmpeg and looped downstream.
- A filter such as `atrim` applied to a `-stream_loop` input acts on the whole infinite
  stream, not on each pass, so it cuts the playback dead instead of trimming each repeat.

The aligned file therefore has to exist on disk before looping starts. It lives in
`install.sh` rather than a separate script so that there are only the two scripts a user
expects — install and play — plus uninstall.

## Why it does not re-encode the picture

An earlier version re-encoded the video with `-crf 18`. That was wrong: the defect being
fixed is in the *sound*, so re-encoding the picture loses quality for nothing. It now
uses `-c:v copy`, verified bit-identical by extracting the raw H.264 stream from input
and output and comparing bytes.

If a source does not meet the requirements, the installer **reports and stops**. Fixing
the source is the user's job. Do not add re-encoding, scaling or quality options — that
was explicitly rejected.

The sound is always rebuilt as FLAC even when it is already the right length, because
MP3 and AAC carry priming and padding samples at both ends that click on every loop.
FLAC is lossless, so this costs nothing in quality.

## Where the checks live

`tools/check-video.sh` is the only place that knows what a loopable file looks like.
`install.sh` calls it in `--facts` mode to vet a source and get its numbers, calls it
again on the fitted result, and installs a copy as `kiosk-check-video`, which `kiosk.sh`
runs at startup. Do not reimplement the checks anywhere else.

It sorts faults into two kinds, and the distinction matters:

- **PROBLEM** — in the picture (frame rate, variable spacing, no keyframe, missing
  file). The installer cannot repair these and refuses the file.
- **FIXABLE** — in the sound (wrong codec, ends at the wrong time). The installer
  rebuilds the sound anyway, so these are expected on any normal source file.

`--facts` therefore fails only on PROBLEMs. Getting this wrong makes the installer reject
every ordinary MP4, since AAC audio is always a FIXABLE fault.

Scripts are called as `bash tools/check-video.sh`, never executed directly, because a
folder copied from Windows arrives without executable bits. That is a real failure that
happened, not a precaution.

`install.sh` installs the service *before* the video, so a rejected file still leaves a
working installation behind — fix the file, run it again.

The startup check would cost several seconds per boot on a Pi 3 if it scanned every
time, so `install.sh` writes the fitted file's size and mtime to `/opt/kiosk/video.ok`
and `kiosk.sh` skips the scan when they still match. A video replaced by hand no longer
matches, so it gets checked and warned about.

## Checks that are measured, not read

Two file properties cannot be trusted from container metadata:

- **Variable frame rate.** `r_frame_rate` and `avg_frame_rate` both reported `25/1` for a
  file with genuinely uneven frames. The installer measures packet timestamps instead.
- **Where the picture ends.** With B-frames, packets are stored in decode order, so the
  last packet is not the latest one. The installer computes the end from the frame count,
  and takes the maximum over audio packets (which are not reordered).

Also note `ffprobe -of csv=p=0` appends a trailing comma and emits CRLF on Windows. The
`clean()` helper strips both; without it, string comparisons fail in Git Bash.

## How to verify a change to the loop

Do not trust that it looks right. Build a synthetic clip, loop it, and prove it.

`install_video()` can be tested without a Pi by pulling it out of `install.sh`, which
avoids the root check and the apt calls:

```bash
awk '/^clean\(\)/{f=1} /^# The kiosk runs as a normal user/{f=0} f' install.sh > fn.sh
{ echo 'set -euo pipefail'; echo 'RATE=48000'; echo "VIDEO_DEST=$PWD/out.mkv"
  sed 's|install -d /opt/kiosk|true|' fn.sh; echo 'install_video "$1"'; } > test.sh

ffmpeg -f lavfi -i "testsrc=size=640x360:rate=25:duration=3" \
       -f lavfi -i "sine=frequency=440:duration=3" \
       -c:v libx264 -c:a aac -shortest src.mp4
bash test.sh src.mp4
ffmpeg -fflags +genpts -stream_loop 2 -i out.mkv -c copy -f matroska looped.mkv

# frame count must be exactly 3x
ffprobe -select_streams v -count_packets -show_entries stream=nb_read_packets looped.mkv

# decoded audio must be byte-identical to the clip concatenated three times
ffmpeg -i looped.mkv -vn -f s32le a.raw
ffmpeg -i out.mkv    -vn -f s32le b.raw
cat b.raw b.raw b.raw > c.raw && cmp a.raw c.raw
```

## Why mpv

`mpv` is current and actively developed. It is easy to confuse with **MPlayer** and
`mplayer2`, which are the abandoned ones; mpv began as a fork of those.

The player removed from Raspberry Pi OS is `omxplayer`, and the Foundation suggests
**VLC** instead. VLC was not used here because it does not handle the pipe-fed endless
stream cleanly, and it is much heavier than mpv on a Pi 3B.

## Service behaviour

`Restart=on-failure` with `SuccessExitStatus=0 4 130 143` is what separates a crash from
a decision: mpv exits 0 when quit with `ESC`, and 4 when killed by a signal, so a
deliberate quit leaves the service down while a real crash restarts it.

The service takes tty1 via `Conflicts=getty@tty1.service`, and `ExecStopPost` starts the
login prompt again when it stops, so quitting lands on a usable console.

`--no-input-default-bindings` plus a two-line `input.conf` means only `ESC`, `q` and
`Ctrl+C` do anything. Staff pressing keys cannot pause, seek or mute the video. `ESC`
needs the explicit binding because mpv's default for it is "leave fullscreen", not
"quit".

## Deliberately not used

Common in older guides, all wrong now:

- `omxplayer` — removed from Raspberry Pi OS years ago.
- `mplayer` — unmaintained; mpv is the maintained one.
- `/etc/rc.local` — superseded by systemd.
- `/etc/wpa_supplicant/wpa_supplicant.conf` — superseded by NetworkManager.
- LXDE `autostart` — there is no desktop on Lite.
- `hdmi_force_hotplug` and other `hdmi_*` settings — ignored by the KMS driver. Use
  `video=HDMI-A-1:...` in `cmdline.txt`.

## Scope

Single video only. A folder playlist was considered and deliberately left out.

If it is ever added: `ffmpeg -f concat` combined with `-stream_loop -1` does stay
sample-exact (tested). But feeding it clips of **different resolutions** exits 0 with no
warning at all and produces a file whose resolution flips mid-stream — a glitch on the
wall with nothing in the logs. Any playlist support must normalise resolution and refuse
to start on a mismatch.

## Untested

Everything Pi-side: systemd unit, DRM/KMS output, overlay filesystem, `nmcli`, and the
`v4l2m2m` hardware decoding path. The ffmpeg and looping work is verified on real files.
