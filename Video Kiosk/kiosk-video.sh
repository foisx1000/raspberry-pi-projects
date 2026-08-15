#!/bin/bash
set -e  # exit on any unexpected error

# ==========================
# Configuration
# ==========================
VIDEO_FILE="/home/pi/video-loop/myvideo.mp4"
PIPE_FILE="/tmp/video.pipe"

# ------------- Do not start if a graphical session is active -------------
# If the machine has a graphical target active, or a display manager (lightdm/gdm3/sddm),
# or X/Wayland processes are present, exit 0 (intentional success).
echo "[KIOSK] startup: checking environment..."
if systemctl is-active --quiet graphical.target \
   || systemctl is-active --quiet lightdm.service \
   || systemctl is-active --quiet gdm.service \
   || systemctl is-active --quiet gdm3.service \
   || systemctl is-active --quiet sddm.service \
   || pgrep -x Xorg >/dev/null 2>&1 \
   || pgrep -x Xwayland >/dev/null 2>&1 \
   || pgrep -x wayland >/dev/null 2>&1; then
    echo "[KIOSK] Graphical session detected (desktop). Exiting without starting." >&2
    exit 0
fi

# Check video exists
if [ ! -f "$VIDEO_FILE" ]; then
    echo "[KIOSK] ERROR: Video file not found: $VIDEO_FILE" >&2
    exit 1
fi

echo "[KIOSK] Starting kiosk video script..."
echo "[KIOSK] Using video file: $VIDEO_FILE"

# ==========================
# Cleanup old pipe
# ==========================
if [ -e "$PIPE_FILE" ]; then
    echo "[KIOSK] Removing old pipe..."
    rm -f "$PIPE_FILE"
fi
echo "[KIOSK] Creating new named pipe..."
mkfifo "$PIPE_FILE"

# ==========================
# Kill previous instances
# ==========================
echo "[KIOSK] Killing any leftover VLC or ffmpeg processes..."
pkill -9 ffmpeg 2>/dev/null || true
pkill -9 vlc 2>/dev/null || true

# ==========================
# Launch ffmpeg streaming into the pipe
# ==========================
echo "[KIOSK] Launching ffmpeg..."
ffmpeg -y -stream_loop -1 -re -i "$VIDEO_FILE" -c copy -f mpegts "$PIPE_FILE" &

# Give ffmpeg a moment to start
sleep 4

# ==========================
# Launch VLC reading the pipe
# ==========================
echo "[KIOSK] Launching VLC..."
cvlc --fullscreen --no-video-title-show "$PIPE_FILE"