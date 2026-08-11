# waha-railway

Railway-tuned wrapper image for [WAHA](https://waha.devlike.pro/) (WhatsApp HTTP API),
published as `ghcr.io/bon5co/waha-railway`.

What the wrapper changes, and why each change is needed on Railway:

- **Base image `devlikeapro/waha:noweb-2026.7.2`** — the NOWEB engine talks to WhatsApp over a
  websocket, so no Chromium is bundled or launched. Measured on one host, one unpaired session,
  `--memory 2g --cpus 2`: **342 MiB** resident on `noweb-2026.7.2` against **535 MiB** on
  `latest-2026.7.2` (WEBJS, six chromium processes). Railway bills memory by the hour.
- **Pinned tag** — WAHA's session authentication store migrates forward, and a Railway redeploy
  is routine; `latest` makes every redeploy an unrequested upgrade of the component holding the
  WhatsApp login.
- **Sessions *and* media on the volume** — `WAHA_LOCAL_STORE_BASE_DIR=/local/.sessions` and
  `WHATSAPP_FILES_FOLDER=/local/.media`. Upstream defaults the media folder to `/app/.media`,
  which on Railway is the disposable container layer.
- **`WHATSAPP_RESTART_ALL_SESSIONS=True`** — the real variable name. `WAHA_RESTART_ALL_SESSIONS`
  is read nowhere in the image.
- **`WAHA_BASE_URL` derived from `RAILWAY_PUBLIC_DOMAIN`** at boot — this is the prefix WAHA puts
  in `media.url` on every incoming-file webhook, so it must be reachable from outside the
  container.
- **Node heap sized from the cgroup** — the upstream image bakes
  `--max-old-space-size=16384`, a 16 GiB ceiling that on a smaller Railway container means the
  kernel OOM-kills before V8 collects.
- **`UV_THREADPOOL_SIZE` sized from the cgroup CPU quota** — upstream's entrypoint reads
  `os.cpus().length`, which in a container is the *host's* core count.

The template that deploys it lives in
[bon5co/railwaytemplate2](https://github.com/bon5co/railwaytemplate2) under `waha/`.
