#!/usr/bin/env bash
# Host: (re)construye la imagen de deps (cacheada) y arranca el juego headless
# bajo Xvfb dentro del contenedor para validar la inicialización (Fase 3).
# Requiere haber compilado antes con ./docker/build.sh (usa build-docker/).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=omnibandtk-deps:bookworm
VARIANT="${1:-AngbandTk}"

if [ ! -f "${REPO_ROOT}/build-docker/variant/${VARIANT}/angband.so" ]; then
    echo "ERROR: faltan binarios. Ejecuta primero ./docker/build.sh" >&2
    exit 1
fi

echo "=== Construyendo/actualizando imagen (${IMAGE}) ==="
docker build -t "${IMAGE}" -f "${REPO_ROOT}/docker/Dockerfile" "${REPO_ROOT}/docker"

echo "=== Lanzando juego headless (variante ${VARIANT}) ==="
docker run --rm \
    -v "${REPO_ROOT}:/work" \
    -w /work \
    "${IMAGE}" \
    bash /work/docker/run-game.sh "${VARIANT}"

echo "=== Log en build-docker/run.log ==="
