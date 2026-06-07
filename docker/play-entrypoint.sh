#!/usr/bin/env bash
# Entrypoint de la imagen autocontenida (stage 'runtime' de docker/Dockerfile).
# A diferencia de run-vnc.sh, NO monta ni copia nada del repo: el layout de
# runtime ya está horneado en /opt/omniband. Arranca Xvfb + fluxbox + x11vnc +
# noVNC, muestra el selector de variante (o la que se pase como argumento) y
# lanza el juego.
#
# Uso (dentro del contenedor):  play-omniband [VARIANTE]
#   Sin argumento: selector gráfico de módulos por VNC.
#   Con argumento (p.ej. ZAngbandTk): arranca directo esa variante.
set -uo pipefail

PREFIX="${OMNI_TCL_PREFIX:-/opt/tcltk8616}"
STAGE="${OMNI_STAGE:-/opt/omniband}"
VARIANT="${1:-}"
VNCPASS="${OMNI_VNCPASS:-omniband}"

export TCL_LIBRARY="${PREFIX}/lib/tcl8.6"
export TK_LIBRARY="${PREFIX}/lib/tk8.6"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
export HOME=/tmp
export DISPLAY=:99

echo "=== Arrancando Xvfb + fluxbox + x11vnc + noVNC ==="
Xvfb :99 -screen 0 1920x1200x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
sleep 2

mkdir -p /tmp/.fluxbox
cat > /tmp/.fluxbox/init <<'FBEOF'
session.styleFile: /usr/share/fluxbox/styles/BlueFlux
session.screen0.windowPlacement: CascadePlacement
session.screen0.focusModel: ClickToFocus
session.screen0.workspaces: 1
FBEOF
fluxbox >/tmp/fluxbox.log 2>&1 &
sleep 1

x11vnc -storepasswd "${VNCPASS}" /tmp/vncpw >/dev/null 2>&1
# Sin -localhost: bind 0.0.0.0 dentro del contenedor; el host lo limita vía el
# mapeo de puertos (ver docker-compose.yml / la bandera -p de docker run).
x11vnc -display :99 -forever -shared -rfbauth /tmp/vncpw -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
sleep 1
websockify --web=/usr/share/novnc 6080 localhost:5900 >/tmp/novnc.log 2>&1 &
sleep 1

cat <<EOF

===================================================================
  OmnibandTk listo. Conéctate desde el host:

  Navegador (recomendado):
    http://localhost:6080/vnc.html?host=localhost&port=6080
    Contraseña:  ${VNCPASS}

  Cliente VNC nativo (p.ej. Compartir pantalla de macOS):
    vnc://localhost:5900   (contraseña: ${VNCPASS})

  Ctrl+C para parar.
===================================================================

EOF

cd "${STAGE}"

# Sin variante explícita: mostrar el selector gráfico por VNC y esperar elección.
if [ -z "${VARIANT}" ]; then
    AVAIL=()
    for vso in "${STAGE}"/variant/*/angband.so; do
        [ -f "${vso}" ] || continue
        AVAIL+=("$(basename "$(dirname "${vso}")")")
    done
    WISH="${PREFIX}/bin/wish8.6"
    [ -x "${WISH}" ] || WISH="${PREFIX}/bin/wish"
    echo "=== Esperando elección de módulo en el selector (VNC)... ==="
    CHOSEN="$("${WISH}" "${STAGE}/variant-chooser.tcl" "${AVAIL[@]}" 2>/tmp/chooser.log)"
    VARIANT="${CHOSEN:-${AVAIL[0]:-AngbandTk}}"
    echo "=== Módulo elegido: ${VARIANT} ==="
fi

exec ./angband -variant "${VARIANT}"
