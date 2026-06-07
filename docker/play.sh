#!/usr/bin/env bash
# Host (Mac/Linux): arranca el juego de forma interactiva y lo expone por VNC.
# Requiere haber compilado antes con ./docker/build.sh.
#
# Uso:   ./docker/play.sh [VARIANTE]
#   Sin argumento: se muestra un selector gráfico de módulos al conectar por VNC.
#   Con argumento (p.ej. ZAngbandTk): arranca directo ese módulo, sin selector.
# Luego conéctate desde el Mac a  vnc://localhost:5900  (contraseña: omniband)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=omnibandtk-deps:bookworm
VARIANT="${1:-}"

if [ -n "${VARIANT}" ]; then
    # Variante explícita: comprobar que está compilada.
    if [ ! -f "${REPO_ROOT}/build-docker/variant/${VARIANT}/angband.so" ]; then
        echo "ERROR: faltan binarios de ${VARIANT}. Ejecuta primero ./docker/build.sh" >&2
        exit 1
    fi
else
    # Sin variante: el selector necesita al menos un módulo compilado.
    if ! ls "${REPO_ROOT}"/build-docker/variant/*/angband.so >/dev/null 2>&1; then
        echo "ERROR: no hay módulos compilados. Ejecuta primero ./docker/build.sh" >&2
        exit 1
    fi
fi

echo "=== Construyendo/actualizando imagen (${IMAGE}) ==="
docker build --target deps -t "${IMAGE}" -f "${REPO_ROOT}/docker/Dockerfile" "${REPO_ROOT}/docker"

echo "=== Arrancando ${VARIANT:-(selector de módulo)} con VNC en 127.0.0.1:5900 + noVNC en 127.0.0.1:6080 ==="
echo "    Navegador (recomendado):  http://localhost:6080/vnc.html (pass: omniband)"
echo "    Cliente VNC nativo:       vnc://localhost:5900 (pass: omniband)"
# -p 127.0.0.1:... -> VNC/noVNC SOLO accesibles desde este Mac (no la red).
#   6080 -> noVNC (navegador),  5900 -> VNC nativo.
exec docker run --rm -it \
    -p 127.0.0.1:6080:6080 \
    -p 127.0.0.1:5900:5900 \
    -e OMNI_DEBUG="${OMNI_DEBUG:-}" \
    -v "${REPO_ROOT}:/work" \
    -w /work \
    "${IMAGE}" \
    bash /work/docker/run-vnc.sh "${VARIANT}"
