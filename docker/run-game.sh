#!/usr/bin/env bash
# Se ejecuta DENTRO del contenedor (repo en /work). Monta un layout de runtime
# con los binarios compilados + treectrl.so, arranca un X virtual (Xvfb) e intenta
# lanzar el juego para ver hasta dónde llega la inicialización Tcl/Tk.
#
# NO espera que el juego "termine": es un bucle de eventos GUI. Lo matamos por
# timeout; si llega al bucle de eventos sin volcar errorInfo, es buena señal.
set -uo pipefail

PREFIX=/opt/tcltk857
BD=/work/build-docker
STAGE=${BD}/stage
LOG=${BD}/run.log
VARIANT="${1:-AngbandTk}"

echo "=== Montando layout de runtime en ${STAGE} (variante ${VARIANT}) ==="
rm -rf "${STAGE}"
mkdir -p "${STAGE}/lib/dbwin"
cp -a /work/tk  "${STAGE}/tk"
cp -a /work/lib/. "${STAGE}/lib/"
mkdir -p "${STAGE}/variant"
for vso in "${BD}"/variant/*/angband.so; do
    v=$(basename "$(dirname "${vso}")")
    cp -a "/work/variant/${v}" "${STAGE}/variant/${v}"
    cp "${vso}" "${STAGE}/variant/${v}/angband.so"
done

# Binarios compilados -> sus posiciones de runtime
cp "${BD}/src/boot/angband"                      "${STAGE}/angband"
cp "${BD}/src/common-dll/common.so"              "${STAGE}/lib/common.so"
cp "${BD}/src/sound/NoSoundCard/sound-nocard.so" "${STAGE}/lib/sound-nocard.so"
cp "${BD}/src/dbwin/dbwin.so"                    "${STAGE}/lib/dbwin/dbwin.so"
# zlib: icon-dll.c hace dlopen de "lib/libz.so" (en Windows es zlib1.dll).
cp "$(find /usr/lib -name 'libz.so.1' 2>/dev/null | head -1)" "${STAGE}/lib/libz.so"

# treectrl: reemplazar el dir del repo por el instalado entero (su pkgIndex carga
# el .so con el nombre correcto -libtreectrl2.2.so- + trae treectrl.tcl).
rm -rf "${STAGE}/lib/treectrl2.2.9"
cp -a "${PREFIX}/lib/treectrl2.2.9" "${STAGE}/lib/treectrl2.2.9"
# Tkhtml3 (necesario en birth): .so + parche del pkgIndex (cargaba Tkhtml30.dll)
cp "${PREFIX}/lib/Tkhtml3.0/libTkhtml3.0.so" "${STAGE}/lib/TkHtml3.0/"
sed -i 's/Tkhtml30\.dll/libTkhtml3.0.so/' "${STAGE}/lib/TkHtml3.0/pkgIndex.tcl"
echo "--- pkgIndex de treectrl tras el parche ---"
grep -n "load" "${STAGE}/lib/treectrl2.2.9/pkgIndex.tcl"

# Entorno Tcl/Tk
export TCL_LIBRARY="${PREFIX}/lib/tcl8.5"
export TK_LIBRARY="${PREFIX}/lib/tk8.5"
export LD_LIBRARY_PATH="${PREFIX}/lib:${LD_LIBRARY_PATH:-}"
export HOME=/tmp

# X virtual
export DISPLAY=:99
echo "=== Arrancando Xvfb en ${DISPLAY} ==="
Xvfb :99 -screen 0 1920x1200x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
XVFB_PID=$!
sleep 2

echo "=== Lanzando ./angband -variant ${VARIANT} en segundo plano ===" | tee "${LOG}"
cd "${STAGE}"
./angband -variant "${VARIANT}" >>"${LOG}" 2>&1 &
GAME_PID=$!

# Dar tiempo a que monte la GUI, capturar pantalla, y comprobar que sigue vivo.
sleep 12
SHOT="${BD}/screenshot.png"
if import -window root "${SHOT}" 2>/dev/null; then
    echo ">>> Captura guardada en build-docker/screenshot.png" | tee -a "${LOG}"
else
    echo ">>> No se pudo capturar pantalla" | tee -a "${LOG}"
fi

sleep 8
if kill -0 "${GAME_PID}" 2>/dev/null; then
    echo ">>> El proceso sigue VIVO a los ~20s: GUI en bucle de eventos (init OK)." | tee -a "${LOG}"
    ALIVE=1
else
    echo ">>> El proceso MURIÓ antes de los 20s: init falló (ver salida arriba)." | tee -a "${LOG}"
    ALIVE=0
fi

kill "${GAME_PID}" 2>/dev/null
kill "${XVFB_PID}" 2>/dev/null
echo "=== FIN (alive=${ALIVE}) ===" | tee -a "${LOG}"
