# ADR-0010: Pygame Zero on the virtual display without a window manager

**Status:** Accepted
**Date:** 2026-08-10
**Decision Makers:** Project lead

## Context

A class was planned around [Pygame Zero](https://pygame-zero.readthedocs.io/) (`pgzero`), a teaching-oriented wrapper over Pygame. This is the first workload on the platform that is both **graphical and interactive**: earlier graphical use (matplotlib) only needed to display a static window, while a game needs keyboard and mouse input flowing back into the container at interactive frame rates.

The virtual display stack added in v1.0.3 (Xvfb `:1` at 1280x720 → x11vnc → noVNC, exposed at `/screen/alunoXX/`) had never been exercised this way. Three questions had to be answered before the class:

1. Does the monitor carry input, not just output?
2. Does an animation loop fit inside the per-student resource limits?
3. Does the window land somewhere the student can actually see?

Testing the built image answered all three, and the third one was a blocker.

**Xvfb runs with no window manager.** Nothing assigns window position or input focus. Under those conditions SDL2 opens the Pygame Zero window at `+590+310`. On a 1280x720 screen an 800x600 game therefore extends to `(1390, 910)` — the student sees only the top-left corner of their own game, and clicks aimed at the visible part land outside the window and are silently dropped.

Two other findings came out of the same testing:

- The container has no sound card. `pygame.mixer` falls back to ALSA and prints a block of `ALSA lib ...` errors to the student's terminal on every run. The errors are not fatal, but in a beginners' class any red text in the terminal reads as "my program is broken".
- matplotlib was no longer needed for the planned classes, and its only reason to exist in the image was `plt.show()` on this same display.

## Decision

**Do not install a window manager.** Fix window placement with `ENV SDL_VIDEO_CENTERED=1` in `aluno.Dockerfile`.

**Set `ENV SDL_AUDIODRIVER=dummy`** so `pygame.mixer` initializes against a null device. Sound calls become silent no-ops instead of error spam.

**Install `pgzero` via pip** in the same block as `pygame`. This also provides the `pgzrun` CLI at `/usr/local/bin/pgzrun`.

**Remove matplotlib** from the image, along with the artifacts that existed only to serve it: the `python3-pil.imagetk` package, the `/home/abc/.config/matplotlib/matplotlibrc` file pinning the TkAgg backend, and `ENV MPLBACKEND=TkAgg`. `python3-tk` stays, because tkinter is independent of matplotlib and useful on its own.

**Raise `LIMITE_CPU` from 0.28 to 0.5** in `config.env`.

## Alternatives Considered

**Install a lightweight window manager (matchbox, openbox).** This is the conventional fix and would also provide focus handling and window decorations. Rejected: it adds a package, a process, and memory to all 60 containers to solve a problem that one environment variable solves completely. Testing confirmed keyboard focus already works without a WM — SDL sets input focus explicitly, and keys reach the game even when the pointer is outside the window. Placement was the only real gap.

**`SDL_VIDEO_WINDOW_POS=0,0` instead of centering.** Also tested and also works, anchoring the window at the top-left so game coordinates coincide with screen coordinates. Rejected in favor of centering, which looks deliberate on the monitor. The trade-off is that a window larger than 1280x720 is clipped on all four sides rather than only on the bottom-right.

**Enlarge the Xvfb screen so the default placement fits.** A screen of at least 1390x910 would contain the badly-placed window. Rejected: it treats the symptom, gives x11vnc more pixels to encode for every student, and still breaks for any other window size.

**Keep matplotlib installed with the Agg backend.** Rejected: it would stay in the image purely to avoid an import error for code nobody is running. Removing it is reversible in one line.

**Leave `LIMITE_CPU` at 0.28.** Measured ~16–23 FPS for a simple game (9 Actors) at that cap versus ~39 FPS at 0.5, on a 6-core/12-thread i7. `--cpus` is an opportunistic ceiling rather than a reservation: raising it helps whenever only part of the class is animating, and when all 30 run games at once the kernel falls back to fair-share anyway. Rejected because ~20 FPS is visibly choppy for a game.

## Consequences

**Enabled.** Pygame Zero games run and are fully playable in the browser tab at `/screen/alunoXX/`. Verified end-to-end in the built image: window centered at `+240+60` and fully visible; `Actor` sprites loading from `images/`; text rendering; a click injected via XTEST at screen `(500, 400)` arriving in the game as `(260, 340)` — exactly the centering offset; arrow keys arriving as `K_LEFT`. Terminal output is clean of ALSA errors.

**Resource envelope.** A container running code-server, the display stack, and a game measured 143 MiB against the 256 MiB limit, with no OOM kill. Memory is not the constraint; CPU is — the game saturates its quota. Idle (no game) is ~51 MiB.

**Prevented.** `import matplotlib` now raises `ModuleNotFoundError` in student containers. Any class needing plots must restore it in `aluno.Dockerfile` and rebuild.

**New problem: window size.** Because the window is centered, a student setting `WIDTH`/`HEIGHT` above 1280x720 loses content on all four edges. The practical ceiling for a game on this platform is 1280x720.

**Audio is unavailable, not merely silenced.** `sounds.foo.play()` runs without error and produces nothing. This is inherent to the monitor — VNC carries no audio — and is not something the dummy driver caused. A class built around sound effects will not work on this platform.

> **Superseded on this point by [ADR-0011](./0011-audio-pcm-cru-via-websockify.md) (v1.0.5).** The conclusion above was right about VNC and wrong about the platform: audio now travels on a second channel alongside the video, and `SDL_AUDIODRIVER` became `pulse,dummy` rather than `dummy`.

**No window decorations.** With no window manager there is no title bar, and windows cannot be moved or resized. For a single fullscreen-ish game window this is invisible to the student.

## References

- [Feature: virtual display / monitor](../operations/troubleshooting.md#symptom-screenalunoxx-shows-a-blank-page-or-connection-failed)
- [ADR-0005: On-demand container spawning](./0005-on-demand-containers.md) — the resource budget this decision spends against
- [Pygame Zero documentation](https://pygame-zero.readthedocs.io/)
