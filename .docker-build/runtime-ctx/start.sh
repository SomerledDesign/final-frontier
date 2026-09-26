#!/bin/bash
set -e
export DISPLAY=:99
export SDL_VIDEODRIVER=x11
export LIBGL_ALWAYS_SOFTWARE=1
export SDL_VIDEO_X11_MOUSEWARP=0
export SDL_VIDEO_X11_DGAMOUSE=0
Xvfb :99 -screen 0 1680x1050x24 -ac +extension XTEST >/tmp/xvfb.log 2>&1 &
sleep 2
x11vnc -storepasswd frontier /tmp/vnc.pass >/dev/null
x11vnc -display :99 -forever -shared -always_inject -clear_all \
  -cursor most -arrow 1 -buttonmap 123 \
  -rfbauth /tmp/vnc.pass -rfbport 5900 -listen 0.0.0.0 >/tmp/x11vnc.log 2>&1 &
sleep 1
websockify --web=/usr/share/novnc 6080 127.0.0.1:5900 >/tmp/novnc.log 2>&1 &
./frontier --nosound --size 1680 1050 &
game_pid=$!
sleep 2
xdotool search --name "Frontier" windowfocus >/dev/null 2>&1 || true
wait "$game_pid"
