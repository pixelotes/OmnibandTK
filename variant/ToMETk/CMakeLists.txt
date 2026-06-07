# ToMETk — variante ToME 2.2.2 bajo el framework Omniband (EN CURSO).
#
# Modelado sobre variant/ZAngbandTk/CMakeLists.txt. El motor de ToME se compila
# junto con la "cola" Tk común (common_SRCS) y el intérprete Lua embebido.
# Los bindings tolua (w_*.c) se pre-generan en la Fase 0 (ya están en src/).

SET (d ${OmnibandTk_SOURCE_DIR}/src/common/)
SET (common_SRCS
    ${d}bind.c ${d}birth-tnb.c ${d}canv-widget.c ${d}const.c ${d}debug.c
    ${d}describe.c ${d}file_character.c ${d}icon1.c ${d}icon2.c ${d}interp1.c
    ${d}interp2.c ${d}map.c ${d}mon_memory.c ${d}plat.c ${d}r_info.c ${d}savefile-z.c ${d}setting.c ${d}sound.c ${d}struct.c
    ${d}town.c ${d}util-tnb.c ${d}widget.c ${d}widget-iso.c ${d}wor-z.c ${d}treectrl.c
    ${d}tome-tnb-stubs.c
)

# Motor de ToME: todos los .c de src/ EXCEPTO:
#  - front-ends de display (main.c, main-*.c, maim-*.c) -> los sustituye el term
#    Tk de Omniband (main-tnb.c).
#  - ficheros que NO son unidades de compilación: se #incluyen dentro de otros
#    (q_*.c y load_gif.c en plots.c; maid-x11.c en main-x11.c). Compilarlos
#    sueltos da una cascada de errores falsa.
FILE (GLOB tome_engine_SRCS ${CMAKE_CURRENT_SOURCE_DIR}/src/*.c)
LIST (FILTER tome_engine_SRCS EXCLUDE REGEX "/(main|main-.*|maim-.*|maid-.*|load_gif|readdib|q_[a-z]+)\\.c$")

# Intérprete Lua embebido + runtime tolua (excluye la herramienta tolua.c/tolualua.c).
FILE (GLOB tome_lua_SRCS ${CMAKE_CURRENT_SOURCE_DIR}/src/lua/*.c)
LIST (FILTER tome_lua_SRCS EXCLUDE REGEX "/(tolua|tolualua)\\.c$")

SET_PROPERTY (
    DIRECTORY
    PROPERTY COMPILE_DEFINITIONS
     ${PLATFORM}
     TOMETK
     TNB_BACKUP
     # TNB_SQUELCH: ToME no tiene object_kind.squelch -> deshabilitado.
     ${SDL_CFLAGS}
     ${TREECTRL_CFLAGS}
)

IF (CMAKE_HOST_UNIX)
	ADD_DEFINITIONS (${TCL_DEFS})
ENDIF (CMAKE_HOST_UNIX)

INCLUDE_DIRECTORIES (
    src
    src/lua
    ${COMMONTK}/src/common
    ${COMMONTK}/src/common-dll
    ${COMMONTK}/src/misc
    ${TREECTRL_HDRS}
    ${DBWIN_HDRS}
)

ADD_LIBRARY (tome_library
    SHARED
    ${OmnibandTk_SOURCE_DIR}/src/common/main-tnb.c
    ${common_SRCS}
    ${tome_engine_SRCS}
    ${tome_lua_SRCS}
)
SET_TARGET_PROPERTIES (tome_library
	PROPERTIES
	OUTPUT_NAME angband
	PREFIX ""
)

TARGET_LINK_LIBRARIES (tome_library
    common
    misc
    ${TCL_LIBRARY}
    ${TK_LIBRARY}
    ${DBWIN_LIB}
)
IF (CMAKE_HOST_WIN32)
    TARGET_LINK_LIBRARIES (tome_library comdlg32)
ENDIF (CMAKE_HOST_WIN32)

INSTALL (
	TARGETS tome_library
	RUNTIME DESTINATION variant/ToMETk
)
