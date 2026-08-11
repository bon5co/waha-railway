#!/bin/sh
# Railway shim for WAHA. Runs before upstream's /entrypoint.sh, which hashes the
# API key and execs `node dist/main`.
set -e

# 1. The media URL WAHA hands to your webhooks.
#
# WAHA builds `media.url` for every incoming file from WAHA_BASE_URL
# (dist/core/media/local/MediaLocalStorage.js:38 via MediaLocalStorageConfig),
# falling back to {schema}://{hostname}:{port}, which on Railway resolves to
# http://localhost:8080. Whatever is in that field is what n8n, Make, or your
# own backend will try to GET when a customer sends a photo — so it has to be an
# address reachable from OUTSIDE the container. Railway's public domain is that
# address; the private domain is not (it resolves only inside the project's
# IPv6 network, and it carries no port, so even an in-project consumer would
# dial :80 while WAHA listens on the injected $PORT).
if [ -z "$WAHA_BASE_URL" ] && [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    WAHA_BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
    export WAHA_BASE_URL
fi
if [ -z "$WAHA_PUBLIC_URL" ] && [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    WAHA_PUBLIC_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
    export WAHA_PUBLIC_URL
fi

# 2. Node's heap ceiling.
#
# The upstream image bakes NODE_OPTIONS=--max-old-space-size=16384. On a Railway
# service that is a 16 GiB ceiling over a much smaller cgroup limit (measured:
# heap_size_limit 16480 MB inside a 2 GiB container), which is the wrong way
# round — V8 never feels memory pressure, never collects aggressively, and the
# kernel OOM-kills the container instead. Size it from the cgroup and leave
# headroom for the WhatsApp websocket buffers and the media that is being
# written to disk.
MEM_MAX=""
if [ -r /sys/fs/cgroup/memory.max ]; then
    MEM_MAX="$(cat /sys/fs/cgroup/memory.max)"
elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    MEM_MAX="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"
fi
case "$MEM_MAX" in
    ''|max|*[!0-9]*) HEAP_MB="" ;;
    *) HEAP_MB=$(( MEM_MAX / 1048576 * 75 / 100 )) ;;
esac
if [ -n "$HEAP_MB" ] && [ "$HEAP_MB" -ge 256 ] 2>/dev/null; then
    NODE_OPTIONS="--max-old-space-size=${HEAP_MB}"
    export NODE_OPTIONS
fi

# 3. The libuv threadpool.
#
# Upstream's entrypoint sizes UV_THREADPOOL_SIZE from os.cpus().length, and a
# container reports the HOST's core count, not its own quota (measured: 5 on a
# --cpus 2 container). Cap it at the cgroup quota so the pool that serves media
# writes and zip work matches the CPU the deploy actually has.
CPU_QUOTA=""
if [ -r /sys/fs/cgroup/cpu.max ]; then
    set -- $(cat /sys/fs/cgroup/cpu.max)
    if [ "$1" != "max" ] && [ -n "$2" ] && [ "$2" -gt 0 ] 2>/dev/null; then
        CPU_QUOTA=$(( $1 / $2 ))
    fi
fi
if [ -n "$CPU_QUOTA" ] && [ "$CPU_QUOTA" -ge 1 ] 2>/dev/null; then
    [ "$CPU_QUOTA" -lt 2 ] && CPU_QUOTA=2
    UV_THREADPOOL_SIZE=$(( CPU_QUOTA * 2 ))
    export UV_THREADPOOL_SIZE
fi

# 4. Both store directories exist before WAHA looks for them, on the volume.
mkdir -p "${WAHA_LOCAL_STORE_BASE_DIR:-/local/.sessions}" "${WHATSAPP_FILES_FOLDER:-/local/.media}"

echo "[railway] WAHA wrapper: engine=${WHATSAPP_DEFAULT_ENGINE} base_url=${WAHA_BASE_URL:-<unset>} heap_mb=${HEAP_MB:-<image default>} uv_threadpool=${UV_THREADPOOL_SIZE:-<image default>} sessions=${WAHA_LOCAL_STORE_BASE_DIR} media=${WHATSAPP_FILES_FOLDER}"

exec /entrypoint.sh "$@"
