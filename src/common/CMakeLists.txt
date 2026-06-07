# Las fuentes del motor común (main-tnb.c, interp*.c, widget*.c, etc.) NO se
# compilan aquí: cada variante (variant/<V>/CMakeLists.txt) las añade a su propia
# librería angband.so vía ${OmnibandTk_SOURCE_DIR}/src/common/*.c, y la librería
# compartida de widgets Tcl/Tk (common.so) se define en src/common-dll.
#
# Este subdirectorio existe solo para satisfacer ADD_SUBDIRECTORY(common) de
# src/CMakeLists.txt; no produce ningún target propio (coincide con el estado ya
# configurado en build-docker/, donde src/common no tiene ningún *.dir de target).
#
# NOTA: este fichero estaba sin versionar y se perdió del árbol; al copiarse el
# repo a un layer Docker (FS case-sensitive) su ausencia rompía el configure
# (mientras que el build montando el repo en macOS lo toleraba por la caché).
