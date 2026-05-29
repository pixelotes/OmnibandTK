#!/usr/bin/env bash
# Se ejecuta DENTRO del contenedor (repo en /work). Igual que run-game.sh pero
# en lugar de capturar y matar, deja el juego corriendo y lo expone por VNC para
# poder jugar de verdad desde el host (Mac) con un cliente VNC.
#
# El layout de runtime es idéntico al de run-game.sh (mantener en sync).
set -uo pipefail

PREFIX=/opt/tcltk857
BD=/work/build-docker
STAGE=${BD}/stage
VARIANT="${1:-AngbandTk}"
VNCPASS="${OMNI_VNCPASS:-omniband}"

echo "=== Montando layout de runtime (variante ${VARIANT}) ==="
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
done
cp "${BD}/src/boot/angband"                      "${STAGE}/angband"
cp "${BD}/src/common-dll/common.so"              "${STAGE}/lib/common.so"
cp "${BD}/src/sound/NoSoundCard/sound-nocard.so" "${STAGE}/lib/sound-nocard.so"
cp "${BD}/src/dbwin/dbwin.so"                    "${STAGE}/lib/dbwin/dbwin.so"
# zlib: icon-dll.c hace dlopen de "lib/libz.so" (en Windows es zlib1.dll) para
# comprimir iconos/savefile. Copiamos el libz del sistema (cp sigue el symlink).
cp "$(find /usr/lib -name 'libz.so.1' 2>/dev/null | head -1)" "${STAGE}/lib/libz.so"
# treectrl: reemplazar el dir del repo por el instalado entero (su pkgIndex carga
# el .so con el nombre correcto -libtreectrl2.2.so- + trae treectrl.tcl).
rm -rf "${STAGE}/lib/treectrl2.2.9"
cp -a "${PREFIX}/lib/treectrl2.2.9" "${STAGE}/lib/treectrl2.2.9"
# Tkhtml3 (necesario en birth): .so + parche del pkgIndex (cargaba Tkhtml30.dll)
cp "${PREFIX}/lib/Tkhtml3.0/libTkhtml3.0.so" "${STAGE}/lib/TkHtml3.0/"
sed -i 's/Tkhtml30\.dll/libTkhtml3.0.so/' "${STAGE}/lib/TkHtml3.0/pkgIndex.tcl"

export TCL_LIBRARY="${PREFIX}/lib/tcl8.5"
export TK_LIBRARY="${PREFIX}/lib/tk8.5"
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

cat <<EOF

===================================================================
  Listo para jugar (${VARIANT}).
  Conéctate desde el Mac a:   vnc://localhost:5900
    - Finder -> Cmd+K -> escribe  vnc://localhost:5900
    - Contraseña:  ${VNCPASS}
  Pulsa Ctrl+C en esta terminal para parar.
===================================================================

EOF

cd "${STAGE}"
# Volcar stdout/stderr (incluye el errorInfo con traceback) a un log que el host
# pueda leer en build-docker/play.log.
./angband -variant "${VARIANT}" 2>&1 | tee "${BD}/play.log"
