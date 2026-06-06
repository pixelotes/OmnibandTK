#!/usr/bin/env bash
# Se ejecuta DENTRO del contenedor (repo en /work). Igual que run-game.sh pero
# en lugar de capturar y matar, deja el juego corriendo y lo expone por VNC para
# poder jugar de verdad desde el host (Mac) con un cliente VNC.
#
# El layout de runtime es idéntico al de run-game.sh (mantener en sync).
set -uo pipefail

PREFIX="${OMNI_TCL_PREFIX:-/opt/tcltk8616}"
BD=/work/build-docker
STAGE=${BD}/stage
# Variante: si se pasa por argumento se respeta (salta el selector); si no, se
# mostrará el selector gráfico de módulos en el display VNC antes de lanzar.
VARIANT="${1:-}"
VNCPASS="${OMNI_VNCPASS:-omniband}"

echo "=== Montando layout de runtime (variante ${VARIANT:-<selector>}) ==="
rm -rf "${STAGE}"
mkdir -p "${STAGE}/lib/dbwin"
cp -a /work/tk  "${STAGE}/tk"
cp -a /work/lib/. "${STAGE}/lib/"
mkdir -p "${STAGE}/variant"
# Montar TODAS las variantes compiladas (para que el selector de variante las vea)
for vso in "${BD}"/variant/*/angband.so; do
    v=$(basename "$(dirname "${vso}")")
    cp -a "/work/variant/${v}" "${STAGE}/variant/${v}"
    cp "${vso}" "${STAGE}/variant/${v}/angband.so"
    # Borg (jugador automático): si se compiló su .so, stagearlo donde el runtime
    # lo busca (angband_borg preinit -> Path borg <prefix> borg.so).
    for borgso in "${BD}/variant/${v}/borg"/*/borg.so; do
        [ -f "${borgso}" ] || continue
        cp "${borgso}" "${STAGE}/variant/${v}/borg/$(basename "$(dirname "${borgso}")")/borg.so"
    done
done
cp "${BD}/src/boot/angband"                      "${STAGE}/angband"
cp "${BD}/src/common-dll/common.so"              "${STAGE}/lib/common.so"
cp "${BD}/src/sound/NoSoundCard/sound-nocard.so" "${STAGE}/lib/sound-nocard.so"
cp "${BD}/src/dbwin/dbwin.so"                    "${STAGE}/lib/dbwin/dbwin.so"
# zlib: icon-dll.c hace dlopen de "lib/libz.so" (en Windows es zlib1.dll) para
# comprimir iconos/savefile. Copiamos el libz del sistema (cp sigue el symlink).
cp "$(find /usr/lib -name 'libz.so.1' 2>/dev/null | head -1)" "${STAGE}/lib/libz.so"
# treectrl: reemplazar el dir del repo por el instalado entero (su pkgIndex carga
# el .so con el nombre correcto -libtreectrl2.4.so- + trae treectrl.tcl).
rm -rf "${STAGE}"/lib/treectrl2.*
cp -a "${PREFIX}"/lib/treectrl2.* "${STAGE}/lib/"
# Tkhtml3 (necesario en birth): .so + parche del pkgIndex (cargaba Tkhtml30.dll)
cp "${PREFIX}/lib/Tkhtml3.0/libTkhtml3.0.so" "${STAGE}/lib/TkHtml3.0/"
sed -i 's/Tkhtml30\.dll/libTkhtml3.0.so/' "${STAGE}/lib/TkHtml3.0/pkgIndex.tcl"

export TCL_LIBRARY="${PREFIX}/lib/tcl8.6"
export TK_LIBRARY="${PREFIX}/lib/tk8.6"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
export HOME=/tmp
export DISPLAY=:99

echo "=== Arrancando Xvfb + fluxbox + x11vnc ==="
Xvfb :99 -screen 0 1920x1200x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
sleep 2
# Tema y comportamiento de fluxbox (controles de ventana con estilo)
mkdir -p /tmp/.fluxbox
cat > /tmp/.fluxbox/init <<'FBEOF'
session.styleFile: /usr/share/fluxbox/styles/BlueFlux
session.screen0.windowPlacement: CascadePlacement
session.screen0.focusModel: ClickToFocus
session.screen0.workspaces: 1
FBEOF
fluxbox >/tmp/fluxbox.log 2>&1 &
sleep 1
# Password para compatibilidad con "Compartir pantalla" de macOS.
x11vnc -storepasswd "${VNCPASS}" /tmp/vncpw >/dev/null 2>&1
# Sin -localhost: bind 0.0.0.0 dentro del contenedor; el host lo limita a
# 127.0.0.1 vía el mapeo de puerto de docker (ver play.sh).
x11vnc -display :99 -forever -shared -rfbauth /tmp/vncpw -rfbport 5900 >/tmp/x11vnc.log 2>&1 &
sleep 1

# noVNC: cliente VNC en el navegador. websockify sirve la web de noVNC en :6080
# y la puentea contra el x11vnc de :5900. El paquete 'novnc' instala la web en
# /usr/share/novnc (vnc.html es el cliente clásico; index.html redirige a él).
NOVNC_WEB=/usr/share/novnc
websockify --web="${NOVNC_WEB}" 6080 localhost:5900 >/tmp/novnc.log 2>&1 &
sleep 1

if [ -n "${VARIANT}" ]; then
    BANNER_INFO="Listo para jugar (${VARIANT})."
else
    BANNER_INFO="Conéctate y elige el módulo en el selector que aparecerá."
fi
cat <<EOF

===================================================================
  ${BANNER_INFO}

  Opción A (navegador, recomendada):
    http://localhost:6080/vnc.html?host=localhost&port=6080
    Contraseña:  ${VNCPASS}

  Opción B (cliente VNC nativo, p.ej. Compartir pantalla de macOS):
    vnc://localhost:5900   (contraseña: ${VNCPASS})

  Pulsa Ctrl+C en esta terminal para parar.
===================================================================

EOF

cd "${STAGE}"

# Si no se pidió variante explícita, mostrar el selector gráfico de módulos en
# el display VNC y esperar la elección del usuario. Usa wish (Tcl/Tk 8.6 ya
# compilado en la imagen) -> sin dependencias nuevas.
if [ -z "${VARIANT}" ]; then
    AVAIL=()
    for vso in "${BD}"/variant/*/angband.so; do
        [ -f "${vso}" ] || continue
        AVAIL+=("$(basename "$(dirname "${vso}")")")
    done
    WISH="${PREFIX}/bin/wish8.6"
    [ -x "${WISH}" ] || WISH="${PREFIX}/bin/wish"
    echo "=== Esperando elección de módulo en el selector (VNC)... ==="
    CHOSEN="$("${WISH}" /work/docker/variant-chooser.tcl "${AVAIL[@]}" 2>/tmp/chooser.log)"
    if [ -n "${CHOSEN}" ]; then
        VARIANT="${CHOSEN}"
    else
        # Selector cancelado/cerrado: caer a la primera variante disponible.
        VARIANT="${AVAIL[0]:-AngbandTk}"
        echo ">>> Selector cancelado; usando ${VARIANT} por defecto."
    fi
    echo "=== Módulo elegido: ${VARIANT} ==="
fi

# Volcar stdout/stderr (incluye el errorInfo con traceback) a un log que el host
# pueda leer en build-docker/play.log.
./angband -variant "${VARIANT}" 2>&1 | tee "${BD}/play.log"
