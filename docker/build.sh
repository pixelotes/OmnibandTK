#!/usr/bin/env bash
# Fase 1: construye la imagen de dependencias (si hace falta) y compila la PoC
# montando el repo. Se ejecuta desde el host (macOS/Linux con Docker).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=omnibandtk-deps:bookworm

echo "=== Construyendo imagen de dependencias (${IMAGE}) — la primera vez tarda ==="
docker build -t "${IMAGE}" -f "${REPO_ROOT}/docker/Dockerfile" "${REPO_ROOT}/docker"

echo "=== Compilando la PoC dentro del contenedor ==="
docker run --rm \
    -v "${REPO_ROOT}:/work" \
    -w /work \
    "${IMAGE}" \
    bash /work/docker/in-container-build.sh

echo "=== Hecho. Log completo en build-docker/build.log ==="
