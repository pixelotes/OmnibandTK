#!/usr/bin/env bash
# Host (Mac/Linux): arranca el juego de forma interactiva y lo expone por VNC.
# Requiere haber compilado antes con ./docker/build.sh.
#
# Uso:   ./docker/play.sh [VARIANTE]      (por defecto AngbandTk)
# Luego conéctate desde el Mac a  vnc://localhost:5900  (contraseña: omniband)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=omnibandtk-deps:bookworm
VARIANT="${1:-AngbandTk}"

if [ ! -f "${REPO_ROOT}/build-docker/variant/${VARIANT}/angband.so" ]; then
    echo "ERROR: faltan binarios de ${VARIANT}. Ejecuta primero ./docker/build.sh" >&2
    exit 1
fi

echo "=== Construyendo/actualizando imagen (${IMAGE}) ==="
docker build -t "${IMAGE}" -f "${REPO_ROOT}/docker/Dockerfile" "${REPO_ROOT}/docker"

echo "=== Arrancando ${VARIANT} con VNC en 127.0.0.1:5900 ==="
echo "    Cuando veas el aviso, conéctate a vnc://localhost:5900 (pass: omniband)"
# -p 127.0.0.1:5900:5900 -> el VNC SOLO es accesible desde este Mac (no la red).
exec docker run --rm -it \
    -p 127.0.0.1:5900:5900 \
    -e OMNI_DEBUG="${OMNI_DEBUG:-}" \
    -v "${REPO_ROOT}:/work" \
    -w /work \
    "${IMAGE}" \
    bash /work/docker/run-vnc.sh "${VARIANT}"
