#!/usr/bin/env bash
# Se ejecuta DENTRO del contenedor de dependencias, con el repo montado en /work.
# Configura CMake apuntando a la Tcl/Tk 8.5.7 horneada y compila los targets de
# la prueba de concepto (variante AngbandTk + librerías comunes + NoSoundCard).
set -uo pipefail

REPO=/work
BUILD=/work/build-docker
LOG="${BUILD}/build.log"

mkdir -p "${BUILD}"
: > "${LOG}"

echo "=== CMake configure ===" | tee -a "${LOG}"
cmake -S "${REPO}" -B "${BUILD}" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_FLAGS="-std=gnu89 -fcommon -w -DL64" \
    -DTCL_INSTALL_DIR="${OMNI_TCL_PREFIX}" \
    -DTCL_SOURCE_DIR="${OMNI_TCL_SRC}" \
    -DTK_SOURCE_DIR="${OMNI_TK_SRC}" \
    -DTREECTRL_HDRS="${OMNI_TREECTRL_HDRS}" \
    -DZLIB_HDRS="/usr/include" \
    2>&1 | tee -a "${LOG}"

CONFIG_RC=${PIPESTATUS[0]}
if [ "${CONFIG_RC}" -ne 0 ]; then
    echo "=== CONFIGURE FALLÓ (rc=${CONFIG_RC}); ver ${LOG} ===" | tee -a "${LOG}"
    exit "${CONFIG_RC}"
fi

# Targets: librerías comunes + las 4 variantes. Sin BASS.
TARGETS="misc libdbwin dbwin common sound-nocard boot \
         angband_library kangband_library oangband_library zangband_library"

echo "=== make (${TARGETS}) ===" | tee -a "${LOG}"
cmake --build "${BUILD}" --target ${TARGETS} -- -j"$(nproc)" -k 2>&1 | tee -a "${LOG}"
BUILD_RC=${PIPESTATUS[0]}

echo "=== RESUMEN ===" | tee -a "${LOG}"
echo "configure rc=${CONFIG_RC}  build rc=${BUILD_RC}" | tee -a "${LOG}"
echo "--- artefactos producidos (.so / boot) ---" | tee -a "${LOG}"
find "${BUILD}" -name '*.so' -o -name 'angband' -type f 2>/dev/null | tee -a "${LOG}"
echo "--- nº de errores del compilador (formato gcc fichero:linea:col: error:) ---" | tee -a "${LOG}"
grep -cE ":[0-9]+:[0-9]+: error:" "${LOG}" | tee -a "${LOG}"

exit "${BUILD_RC}"
