# final-frontier: GameShell / arm64 Docker fork

This is a fork of [ShovelTime/final-frontier](https://github.com/ShovelTime/final-frontier)
(GLFrontier / FrontVM3, the 2006 C port of *Frontier: Elite II*). The fork:

* builds the game as a **Linux arm64 (aarch64) binary inside Docker** (Ubuntu 22.04
  images, built on an Apple Silicon Mac),
* runs it headless in a container (**Xvfb + x11vnc + noVNC**) so you can play it in a
  browser or any VNC client,
* fixes mouse and keyboard handling so the game is playable over VNC, and
* is the starting point for a port to the **ClockworkPi GameShell** (Debian/ARM handheld).
  See [GameShell port status](#gameshell-port-status).

The upstream README is kept unchanged [at the bottom of this file](#upstream-readme),
and the original FrontVM3 `README` is still in the repo root.

Branch: `gameshell-arm64-docker` (base: upstream `master` @ `dc753ac`).

---

## Contents

- [What changed](#what-changed)
- [Getting it to build on arm64 Linux](#getting-it-to-build-on-arm64-linux)
- [Build and run with Docker](#build-and-run-with-docker)
- [Connecting (noVNC / VNC)](#connecting-novnc--vnc)
- [One-command launcher](#one-command-launcher)
- [Troubleshooting](#troubleshooting)
- [GameShell port status](#gameshell-port-status)
- [Credits](#credits)
- [Upstream README](#upstream-readme)

---

## What changed

### 1. `Makefile`: `-fsigned-char -fcommon`

```diff
-export CFLAGS = -O2 -g -Wall -DOGG_MUSIC
+export CFLAGS = -O2 -g -Wall -DOGG_MUSIC -fsigned-char -fcommon
 ...
-$(CC) -DPART1 -O1 -fomit-frame-pointer -Wall -Wno-unused -s ...
+$(CC) -DPART1 -O1 -fomit-frame-pointer -Wall -Wno-unused -fcommon -s ...
-$(CC) -DPART2 -O0 -fomit-frame-pointer -Wall -Wno-unused -s ...
+$(CC) -DPART2 -O0 -fomit-frame-pointer -Wall -Wno-unused -fcommon -s ...
```

* **`-fsigned-char`**: on ARM, plain `char` is *unsigned*, but on x86 it is signed. The
  68k assembler `as68k` (which converts `fe2.s` into the huge `fe2.s.c`) keeps its
  AVL-tree balance factor in a `char balance` field, which needs to go negative. On ARM
  it wraps instead, and `as68k --output-c fe2.s` doesn't work. `CFLAGS` is exported,
  so `as68k/` and `src/` both pick up the flag.
* **`-fcommon`**: GCC 10 changed its default to `-fno-common`, and linking then fails on
  the tentative ("common") global definitions shared between the generated `fe2.s.c`
  objects and `src/`. The flag is in the global `CFLAGS` and on both
  `fe2.part1.o` / `fe2.part2.o` compile lines, which don't use `CFLAGS`.

### 2. `src/input.c`: clamp mouse motion, never grab

```diff
-	/* lazy lazy lazy lazy */
-	if ((abs (input.motion_x) > 100) || (abs (input.motion_y) > 100)) {
-			input.motion_x = input.motion_y = 0;
-	}
+	/* VNC delivers large absolute jumps; clamp instead of dropping. */
+	if (input.motion_x > 80) input.motion_x = 80;
+	if (input.motion_x < -80) input.motion_x = -80;
+	if (input.motion_y > 80) input.motion_y = 80;
+	if (input.motion_y < -80) input.motion_y = -80;
```

Upstream worked around a mouse bug by **dropping** every motion event larger than
100 px. A VNC client sends large absolute jumps, so a lot of real mouse movement was
lost. Motion is now **clamped** to ±80 per axis, so big moves still count.

```diff
 static void do_mouse_grab ()
 {
-	/* grab mouse on right-button hold for correct controls */
-	if (input.cur_mousebut_state & 0x1) {
-		SDL_WM_GrabInput (SDL_GRAB_ON);
-	} else {
-		SDL_WM_GrabInput (SDL_GRAB_OFF);
-	}
+	/* Never grab under VNC: grab desyncs the visible cursor from clicks. */
+	SDL_WM_GrabInput (SDL_GRAB_OFF);
 }
```

Upstream grabbed the pointer while the right mouse button was held (the
upstream comment: "grab mouse on right-button hold for correct controls"). Under VNC, a grab puts the
visible cursor and the game's idea of the pointer out of sync, so clicks land in the
wrong place. `do_mouse_grab()` (called on mouse press and release) now always
releases the grab.

### 3. `src/screen.c`: start ungrabbed

```diff
 	SDL_ShowCursor(SDL_ENABLE);
+	SDL_WM_GrabInput(SDL_GRAB_OFF);
+	bGrabMouse = FALSE;
 }
```

At the end of `Screen_Init()` the grab is explicitly released and the `bGrabMouse` flag
cleared, so the game always starts ungrabbed.

### 4. `src/keymap.c`: only Ctrl starts a shortcut

```diff
-  if((modkey&KMOD_MODE) || (modkey&KMOD_RMETA) || (modkey&KMOD_CTRL))
+  if (modkey & KMOD_CTRL)
   {
     ShortCutKey.Key = symkey;
-    if( modkey&(KMOD_LCTRL|KMOD_RCTRL) )  ShortCutKey.bCtrlPressed = TRUE;
-    if( modkey&(KMOD_LSHIFT|KMOD_RSHIFT) )  ShortCutKey.bShiftPressed = TRUE;
+    ShortCutKey.bCtrlPressed = TRUE;
+    if (modkey & (KMOD_LSHIFT|KMOD_RSHIFT)) ShortCutKey.bShiftPressed = TRUE;
   }
```

Upstream treated a key as an emulator shortcut if Mode, **Right-Meta**, or Ctrl was held.
macOS VNC clients often set META on *every* key, so every keypress was treated as a
shortcut and normal typing never reached the game. Now only Ctrl starts a shortcut
(Ctrl-E renderer toggle, Ctrl-Q quit, and so on).

### 5. Docker build and runtime (`.docker-build/`)

| File | Purpose |
|---|---|
| `.docker-build/Dockerfile` | Toolchain image (`ubuntu:22.04` + `build-essential`, `libsdl1.2-dev`, `libglu1-mesa-dev`, `libvorbis-dev`, `libogg-dev`). You mount the source tree at `/src` and run `make`. |
| `.docker-build/runtime.Dockerfile` | Runtime image (`ubuntu:22.04` + SDL 1.2, Mesa software GL, Xvfb, x11vnc, xdotool, noVNC, websockify). Copies `frontier`, `fe2.s.bin`, `sfx/`, `music/`, `start.sh` into `/game`. Sets `LIBGL_ALWAYS_SOFTWARE=1`, `SDL_VIDEODRIVER=x11`, `DISPLAY=:99`. Exposes 5900 and 6080. |
| `.docker-build/runtime-ctx/start.sh` | Container entrypoint. See below. |

`start.sh` does this:

1. Sets `SDL_VIDEO_X11_MOUSEWARP=0` and `SDL_VIDEO_X11_DGAMOUSE=0` (no pointer warping or DGA mouse under VNC).
2. Removes a stale `/tmp/.X99-lock` and `/tmp/.X11-unix/X99` (see [Troubleshooting](#troubleshooting)).
3. Starts `Xvfb :99 -screen 0 1680x1050x24 -ac +extension XTEST`.
4. Starts `x11vnc` on port 5900 with password `frontier` (`-forever -shared -always_inject -cursor most -arrow 1 -buttonmap 123`).
5. Starts `websockify`/noVNC on port 6080, proxying to 5900.
6. Runs `./frontier --nosound --size 1680 1050`, focuses its window with `xdotool`, and waits on it.

The staged binaries and asset copies in `.docker-build/runtime-ctx/` are gitignored. You
produce them with the build steps below.

---

## Getting it to build on arm64 Linux

The game was built inside an **arm64 Ubuntu 22.04** container (Debian-family, GCC 11) on
an Apple Silicon Mac. These are the problems we hit and how we fixed them:

| Problem | Cause | Fix |
|---|---|---|
| `as68k --output-c fe2.s` doesn't work on ARM | `char` is unsigned on ARM, and as68k's AVL `char balance` wraps | `-fsigned-char` in `CFLAGS` |
| Link fails with GCC 10+ | GCC 10+ defaults to `-fno-common` (common/tentative globals become multiple definitions) | `-fcommon` in `CFLAGS` and on the `fe2.part*.o` lines |
| `fe2.s.c` is huge (~8 MB of generated C) | One giant function in PART2 | Upstream already compiles PART2 at `-O0`. Kept that. Build on a machine or VM with plenty of RAM. |
| Mouse unusable over VNC | Large-motion drop and pointer grab | Clamp and never grab (changes 2 and 3) |
| Typing swallowed from macOS VNC clients | META treated as a shortcut modifier | Only Ctrl starts a shortcut (change 4) |
| No GPU in the container | Headless Xvfb | Mesa software GL (`LIBGL_ALWAYS_SOFTWARE=1`) |
| `docker start` fails with "No available video device" | Stale X lock from the previous run | `start.sh` removes it (see Troubleshooting) |

A successful start logs:

```
fe2.s.bin: 0x83ac9 bytes (code end 0x83042), 759 fixups; loaded at 0x0.
```

---

## Build and run with Docker

You need Docker. On an **arm64 host** (Apple Silicon, Raspberry Pi 4/5, and so on) these
steps produce a native arm64 binary. On an x86_64 host the same steps produce an x86_64
build (the input fixes and Docker files aren't arch-specific, but only the arm64 build
has been tested). To produce an arm64 binary on x86_64, add
`--platform linux/arm64` to both `docker build` and `docker run` (needs QEMU/binfmt, and
the huge `fe2.s.c` compile will be slow). That cross-build path has not been tested.

Run everything from the repo root.

### 1. Build the toolchain image

```sh
docker build -t final-frontier-build -f .docker-build/Dockerfile .docker-build
```

### 2. Compile the game inside it

```sh
# start clean if you have objects from a host (e.g. macOS) build
docker run --rm -v "$PWD":/src final-frontier-build \
  sh -c 'make clean && make -C as68k clean; make'
```

On a fresh clone the `clean` step prints `Error 1 (ignored)` because there is nothing to
delete yet. That's harmless.

This builds `as68k`, converts `fe2.s` into `fe2.s.c` and `fe2.s.bin`, compiles the two
halves, and links `./frontier` in the repo root. Check it with:

```sh
file frontier   # e.g. ELF 64-bit LSB pie executable, ARM aarch64 ...
```

### 3. Stage the runtime build context

```sh
cp frontier fe2.s.bin .docker-build/runtime-ctx/
cp -R sfx music .docker-build/runtime-ctx/
```

### 4. Build the runtime image

```sh
docker build -t final-frontier:runtime \
  -f .docker-build/runtime.Dockerfile .docker-build/runtime-ctx
```

### 5. Run it

```sh
docker run -d --name frontier -p 5900:5900 -p 6080:6080 final-frontier:runtime
```

These steps were run end-to-end from a fresh clone of this branch on an Apple Silicon Mac
(Docker Desktop, arm64) on 2026-09-26. The build took about 20 seconds, and
stop/start of the container worked.

Stop and remove it with:

```sh
docker rm -f frontier
```

---

## Connecting (noVNC / VNC)

* **Browser (noVNC):** open <http://localhost:6080/vnc.html>, click *Connect*, and enter
  the password `frontier`. To connect automatically with scaling:
  <http://localhost:6080/vnc.html?autoconnect=true&password=frontier&resize=scale>
* **VNC client:** connect to `localhost:5900` (password `frontier`). On macOS you can
  use `open vnc://localhost:5900` for Screen Sharing.

The virtual display is 1680×1050 and the game runs at that size.

Game keys (from the original README, still valid): `F11` fullscreen, `Ctrl-E` toggle GL /
original software renderer, `Ctrl-Q` quit, `F` debug/FPS readout, `F12` options menu.
Mouse grabbing is disabled in this fork (see above).

The password `frontier` is hard-coded in `start.sh`, and the ports are published on all
interfaces by default. Use `-p 127.0.0.1:6080:6080 -p 127.0.0.1:5900:5900` if you don't
want the game reachable from your network.

---

## One-command launcher

Add this to `~/.zshrc` (macOS). It recreates the container every time (which also avoids
the stale-lock problem on older images), waits for noVNC, opens the browser with
auto-connect, and sends Ctrl-Cmd-F to make the browser window full screen:

```zsh
frontier() {
  docker rm -f frontier >/dev/null 2>&1
  docker run -d --name frontier -p 5900:5900 -p 6080:6080 final-frontier:runtime >/dev/null || return 1
  echo "Starting Frontier..."
  until curl -s -o /dev/null http://localhost:6080/vnc.html; do sleep 1; done
  sleep 2
  open "http://localhost:6080/vnc.html?autoconnect=true&password=frontier&resize=scale"
  osascript -e 'delay 2' -e 'tell application "System Events" to keystroke "f" using {control down, command down}'
}
alias frontier-stop='docker rm -f frontier'
```

`open` and `osascript` are macOS-only. On **Linux**, use `xdg-open` and let the browser
handle full screen (press `F11`):

```sh
frontier() {
  docker rm -f frontier >/dev/null 2>&1
  docker run -d --name frontier -p 5900:5900 -p 6080:6080 final-frontier:runtime >/dev/null || return 1
  echo "Starting Frontier..."
  until curl -s -o /dev/null http://localhost:6080/vnc.html; do sleep 1; done
  sleep 2
  xdg-open "http://localhost:6080/vnc.html?autoconnect=true&password=frontier&resize=scale" >/dev/null 2>&1
}
alias frontier-stop='docker rm -f frontier'
```

(Works in bash or zsh. The macOS accessibility prompt for `osascript` keystrokes has to be
granted once to your terminal app.)

---

## Troubleshooting

**`docker start frontier` exits right away: `Could not initialize the SDL library: No available video device`**

When a container is stopped, Xvfb leaves `/tmp/.X99-lock` (and the `/tmp/.X11-unix/X99`
socket) in the container filesystem. On `docker start` the new Xvfb sees the lock and
refuses to start, so SDL has no display. `start.sh` in this fork now runs

```sh
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99
```

before launching Xvfb, so stop/start works. **Images built before this fix still have the
problem.** Either rebuild the runtime image (step 4) or just recreate the container
(`docker rm -f frontier` and then `docker run ...`, which is what the launcher does).

**No sound.** This is expected. `start.sh` runs the game with `--nosound`, and the
container has no audio device or sound server. The `sfx/` and `music/` files are still
copied into the image, so audio could be wired up later.

**Cursor and clicks don't line up / typing does nothing.** Make sure you're running a
build of this branch (changes 2–4). Upstream grabs the pointer and treats META as a
shortcut modifier, and both break under VNC.

**Port already in use.** Another container (or an old `frontier`) holds 5900 or 6080. Run
`docker rm -f frontier` or map different host ports, e.g. `-p 16080:6080`.

**Build runs out of memory.** `fe2.s.c` PART2 is one enormous function, compiled at
`-O0` on purpose. Give Docker more memory.

---

## GameShell port status

Target: ClockworkPi GameShell (Allwinner R16-J, 4× Cortex-A7, **armhf/ARMv7**, 1 GB RAM,
320×240 panel, Mali-400, ClockworkOS/Debian armhf). The plan for v1 is the original
**software renderer** at 320×240, D-pad/button input, cross-compiled in Docker. No
OpenGL/GLES in v1, and `fe2.s.c` is never compiled on the device.

| Milestone | Status |
|---|---|
| arm64 Linux build + VNC-playable runtime (this branch) | **Done** |
| M0: patches extracted and dry-run against upstream `master`; static armhf hello-world built and run in `debian:12` `linux/arm/v7` via QEMU | **Done** |
| M1: armhf `frontier` binary (`R_OLD` default renderer, `--size 320 240`, `-fsigned-char -fcommon`) | Not started |
| M2: synthetic pointer/keys (D-pad → pointer, buttons → clicks/keys) tested under Xvfb | Not started |
| M3: on-device bring-up on the GameShell | Not started |
| M4: playable loop with buttons only | Not started |

Notes so far:

* An armhf toolchain on `debian:11` failed (`apt-get install gcc` got a 404 from
  security.debian.org), so the armhf stub image is `debian:12`. The device's glibc
  version is still unknown and has to be checked with `ldd --version` on the unit before
  the final build image is picked.
* The current arm64 binary **can't** be copied to the GameShell. It is aarch64 and links
  desktop GL/GLU.
* The GameShell build shouldn't enable `SDL_WM_GrabInput` either, and it keeps the
  Ctrl-only shortcut fix.

---

## Credits

* **Tom Morton**: FrontierVM / FrontVM3 / GLFrontier, the 68k assembler/disassembler, and
  the C port (see `README`).
* **David Braben / Frontier Developments**: *Frontier: Elite II* (Atari ST version,
  reverse-engineered).
* **Hatari** project: portions of the host code.
* **Lee Braiden** ([lee-b](https://github.com/lee-b/final-frontier)): made it build on
  modern 64-bit Linux.
* **ShovelTime** ([ShovelTime/final-frontier](https://github.com/ShovelTime/final-frontier)):
  the upstream repository this fork is based on.
* This fork: arm64/Docker build, VNC input fixes, runtime image, GameShell groundwork.

Licensing follows upstream (see `README`).

---

## Upstream README

The original `README.md` from ShovelTime/final-frontier, unchanged:

> final-frontier
> ==============
> 
> GLFrontier's (Frontier: Elite II's OpenGL port), modified to build on a modern 64-bit linux machine
