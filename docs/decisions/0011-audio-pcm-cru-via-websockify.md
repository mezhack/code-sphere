# ADR-0011: Audio to the browser as raw PCM over websockify

**Status:** Accepted
**Date:** 2026-08-10
**Decision Makers:** Project lead

## Context

[ADR-0010](./0010-pygame-zero-sem-window-manager.md) recorded that the monitor carries no audio, and that a class built around sound effects would not work. That conclusion was correct about the existing stack but not about the platform: the RFB protocol has no audio channel and noVNC implements none, so audio simply needs a **second channel alongside the video**, not a change to the video path.

The constraint that decides the design is CPU. A Pygame Zero game already saturates its `LIMITE_CPU` quota, so anything added to the audio path is taken directly from the student's frame rate. Memory is secondary but not free — the container measured 143 MiB of its 256 MiB limit before audio.

Two designs were built and measured on the real image.

## Decision

Stream **raw PCM (s16le, mono, 22050 Hz) over a WebSocket**, and decode it in the browser with the Web Audio API.

Inside each student container:

1. PulseAudio runs as `abc` with `-n` (no default config) and exactly three modules: `module-null-sink` (there is no sound card), `module-native-protocol-unix` with `auth-anonymous=1`, and `module-simple-protocol-tcp` publishing `virtual.monitor` on `127.0.0.1:4713`.
2. A second `websockify` bridges that TCP port to `6081` — the same tool already in the image for noVNC, so no new dependency.
3. Traefik routes `/audio/alunoXX/` to port 6081, mirroring the existing `/screen/alunoXX/` route.
4. `novnc-defaults/audio.js` is injected into noVNC's own `vnc.html` and plays the stream through an `AudioWorklet`.

`SDL_AUDIODRIVER` is set to **`pulse,dummy`** — a list, not a single driver. See the consequences below; this is the part most likely to be "simplified" by a later change and must not be.

## Alternatives Considered

**Opus via ffmpeg.** Also built and measured: PulseAudio → `ffmpeg -c:a libopus` → fragmented WebM → `<audio>` element. Works, and uses far less bandwidth (48 kbps versus 353 kbps). Rejected on two counts. It costs more CPU (6.2% of a core versus 3.8%) in a container where CPU is exactly what is scarce, and it adds 205 MB to the image against 136 MB. The decisive factor is latency: the `<audio>` element buffers aggressively, giving 1–3 s, which is useless for a game reacting to a key press. Raw PCM has no codec buffer, so latency is whatever jitter buffer we choose (150 ms by default).

**KasmVNC.** Purpose-built for browser desktops and has audio built in via PulseAudio plus a NodeJS helper (Kclient). Rejected because it replaces Xvfb + x11vnc + noVNC wholesale, and the student image extends `linuxserver/code-server`, not a desktop base image. The migration cost is out of proportion to adding one channel.

**pygbag (run the game in the browser via WebAssembly).** Eliminates the problem rather than solving it: zero latency, native browser audio, and the CPU moves to the student's Chromebook. Rejected for now because pygbag's Pygame Zero support is documented by the project as "mostly untested", it requires all audio in OGG, and it introduces a build step between writing code and seeing it run — friction that works against the platform's goal.

**An `<iframe>` wrapper around noVNC with an audio bar.** Cleaner separation than injecting a script into a vendored file. Rejected because iframing noVNC risks breaking keyboard focus forwarding, and interactive input is the whole point of the games class.

## Consequences

**Enabled.** Game audio reaches the browser. Verified end to end through Traefik on the built image: the WebSocket upgrade at `/audio/aluno01/` returns `101` with the `binary` subprotocol negotiated, and 132 KB of PCM arrived carrying the game's tone (RMS 5548 against 0 for silence). Keyboard and mouse were re-tested afterwards and still reach the game unchanged — a click at screen (500,400) still arrives as (260,340).

**Cost.** PulseAudio 2.4% + websockify 1.4% ≈ **3.8% of a core**, taken from the same quota as the game. Memory went from 143 MiB to 167 MiB of the 256 MiB limit (the second websockify is ~37 MiB of that). Image grows 136 MB. Bandwidth is 353 kbps per student, on top of the VNC video — about 10 Mbps for 30 students, and the video stream is the larger consumer.

**`SDL_AUDIODRIVER=pulse,dummy` is load-bearing.** With `pulse` alone, if PulseAudio fails to start then `sounds.foo.play()` raises `UnsupportedFormat` and **kills the student's game** — measured, not theorized. Leaving the variable unset is no better: SDL then falls through to ALSA, which does not exist here, fails anyway, and prints eight lines of ALSA errors first. The list makes SDL fall back to the mute driver, so a broken audio daemon costs the class silence instead of crashes.

**Audio requires a click.** Browser autoplay policy means the "Ativar som" button is not optional. Students must press it once per monitor tab.

**Latency is designed, not measured.** The jitter buffer starts playback at 150 ms and discards backlog beyond 500 ms. Real end-to-end latency in a classroom has not been measured — that needs students and a network, not a container.

**Sound is per-student and private.** Each container has its own sink; the teacher hears nothing centrally. Thirty students playing sounds at once is a classroom-management problem, not a technical one, and headphones are the answer.

**The injected `<script>` tag is fragile against upstream.** It is added with `sed` into the distribution's `vnc.html`. The build fails loudly (`grep -q`) if the tag is not present afterwards, so a noVNC package update that changes the file cannot pass silently.

## References

- [ADR-0010: Pygame Zero without a window manager](./0010-pygame-zero-sem-window-manager.md) — states audio is unavailable; superseded on that point by this ADR
- [ADR-0005: On-demand container spawning](./0005-on-demand-containers.md) — the resource budget this spends against
- [KasmVNC](https://github.com/kasmtech/KasmVNC) and [LinuxServer baseimage-kasmvnc](https://docs.linuxserver.io/images/docker-baseimage-kasmvnc/)
- [pygbag](https://github.com/pygame-web/pygbag)
