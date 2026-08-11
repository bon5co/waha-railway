# Railway-tuned WAHA (WhatsApp HTTP API).
#
# Base is the `noweb` image, not the default `latest`. `latest` bundles Chromium
# because the default WEBJS engine drives a real WhatsApp Web browser session;
# the NOWEB engine talks to WhatsApp over a websocket instead and needs no
# browser at all. Measured on 2026-08-12, same host, one unpaired session in
# SCAN_QR_CODE, `--memory 2g --cpus 2`: 535 MiB resident on
# devlikeapro/waha:latest-2026.7.2 (WEBJS, six chromium processes) against
# 342 MiB on devlikeapro/waha:noweb-2026.7.2. The image itself is 763 MB rather
# than 1.06 GB. Railway bills memory by the GB-hour, so that difference is the
# deploy's running cost, every hour, forever.
#
# Pinned to 2026.7.2 rather than tracking `latest`: WAHA keeps its session
# authentication state in a SQLite store that each release is free to migrate
# forward, and a Railway redeploy is a routine event. An unpinned tag turns
# every redeploy into an unrequested upgrade of the component holding the
# WhatsApp login.
FROM devlikeapro/waha:noweb-2026.7.2

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

# Baked, NOT published as template variables: templateGenerate keeps a
# variable's default only when the live value is a Railway expression, so a
# literal default is dropped and the variable republishes as a blank REQUIRED
# field on the deploy form. Only values that genuinely belong to the deployer
# stay variables, and those are expressions (${{secret(n)}}).
#
# WAHA_LOCAL_STORE_BASE_DIR and WHATSAPP_FILES_FOLDER both point INSIDE the
# volume mount (/local). Upstream's defaults are /app/.sessions and /app/.media,
# and a template that mounts a volume for the sessions but leaves the media
# folder at its default keeps every received image, audio note, document and
# video on the container's disposable layer — with WHATSAPP_FILES_LIFETIME=0
# they are also never cleaned up, so they accumulate until the deploy is
# recreated and then vanish while the webhook payloads that referenced them
# remain.
#
# WHATSAPP_RESTART_ALL_SESSIONS is the real variable name. WAHA_RESTART_ALL_SESSIONS
# does not appear anywhere in this image (135 WAHA_*/WHATSAPP_* names are read by
# dist/, and that is not one of them); setting it leaves the default of false in
# place, so a session whose name is not in WHATSAPP_START_SESSION comes back
# STOPPED after every redeploy while the API keeps answering 200.
#
# PORT is deliberately absent: WAHA already prefers $PORT over
# WHATSAPP_API_PORT, and Railway's HTTP healthcheck dials the port it injected,
# not the domain's target port, so pinning the listener would fail the deploy.
ENV WHATSAPP_DEFAULT_ENGINE=NOWEB \
    WAHA_LOCAL_STORE_BASE_DIR=/local/.sessions \
    WAHA_MEDIA_STORAGE=LOCAL \
    WHATSAPP_FILES_FOLDER=/local/.media \
    WHATSAPP_FILES_LIFETIME=0 \
    WHATSAPP_RESTART_ALL_SESSIONS=True \
    WHATSAPP_START_SESSION=default \
    WAHA_DASHBOARD_ENABLED=True \
    WAHA_DASHBOARD_USERNAME=admin \
    WHATSAPP_SWAGGER_ENABLED=True \
    WHATSAPP_SWAGGER_USERNAME=admin \
    WAHA_PRINT_QR=False \
    WAHA_LOG_FORMAT=JSON \
    WAHA_LOG_LEVEL=info

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/railway-entrypoint.sh"]
