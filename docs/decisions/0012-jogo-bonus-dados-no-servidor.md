# ADR-0012: Bonus game served from the server, gated by the portal

**Status:** Accepted
**Date:** 2026-11-12
**Decision Makers:** Project lead

## Context

The bonus game ([feature spec](../features/bonus-game.md)) uses an open-source browser port of a 2002 PC game ([joncodeofficial/gta-vice-city-wasm](https://github.com/joncodeofficial/gta-vice-city-wasm), MIT). The port ships no game data: each visitor imports their own PC install, which the page converts and stores in the browser (OPFS), and a Service Worker then serves those files back to the engine.

That design does not fit a classroom:

- Service Workers and OPFS only exist in secure contexts. The classroom runs on plain HTTP over the LAN, so the port's page refuses to start.
- Every student would have to import a 1.5 GB install on their own Chromebook.
- The teacher owns the copy of the game; the data must stay on the teacher's server and be reachable only by logged-in students, in the room.

## Decision

1. **Convert once, on the server.** `preparar_jogo.sh` runs the port's own Node converter (`scripts/convert-pc.mjs`) against the teacher's install and writes the result to `./jogo-data/`, outside git and outside any image.
2. **Serve it from a static container.** `sala_jogo` (nginx) serves the port at `/jogo/` and the data at `/vcbr/` and `/vcsky/` — the same paths the Service Worker would have answered. The last two sit at the root because the engine binary requests them by absolute path.
3. **Pin and patch the port.** The image builds a fixed upstream commit and applies `jogo/code-sphere.patch`, which removes the Service Worker/OPFS requirement and the import UI, and adds a 30-second ping to the portal. Nothing else in the port is changed.
4. **Gate every request with `forwardAuth`.** Traefik asks the portal before serving any game path. The portal answers from an in-memory table of passes.
5. **The container is the switch.** The admin button starts and stops `sala_jogo`. There is no separate "enabled" flag to drift out of sync, and stopping it actually frees the resources.

## Alternatives Considered

**Use the port unmodified, behind the Cloudflare tunnel (HTTPS).** Works technically, but sends the game data out to the internet and back for every student, makes each Chromebook import 1.5 GB, and exposes the game outside the room.

**One game container per student.** Unnecessary: the engine runs entirely in the browser, so the server only hands out files. One nginx costs a few MB of RAM for the whole class.

**Signed URLs or a cookie checked by nginx instead of `forwardAuth`.** Fewer portal requests, but a second place that knows about sessions. The portal check is a dictionary lookup; revisit only if the portal shows up in profiles while a class is playing.

**A persisted on/off flag in `portal-data/`.** Would survive restarts, which is the opposite of what a classroom wants: the bonus should be off unless the teacher turned it on today.

## Consequences

- The server's cost is file transfer, not CPU. The first load is the heavy moment: every student downloads the data package over the classroom Wi-Fi. The off switch exists for this.
- The game loads its whole data package into the Chromebook's memory. Whether a given Chromebook copes is a client-side question the server cannot answer.
- Passes are lost when the portal restarts; students answer a new question. Accepted.
- The pinned commit means upstream fixes do not arrive on their own. To update: change `PORT_REF` in `jogo/Dockerfile`, regenerate the patch against the new `src/main.js`, rebuild, and re-run `preparar_jogo.sh` if the converter's output layout changed (`OPFS_VERSION` in upstream's `src/convert/layout.js`).
- The image build needs network access to GitHub and the npm registry.
- If `CLOUDFLARE_TUNNEL=true`, the game paths are reachable through the tunnel by any logged-in student with a pass, from anywhere. Teachers who need the game to stay in the room should keep the bonus off while the tunnel is on.

## References

- [Feature: Bonus Game](../features/bonus-game.md)
- [ADR-0002](./0002-traefik-reverse-proxy.md) — static routes in `routes.yml`
