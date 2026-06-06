# Modernización / Porting de OmnibandTk

Objetivo: hacer que OmnibandTk 1.5 (Tim Baker, ~2009) compile y funcione en
sistemas modernos, usando Docker como entorno reproducible. Endgame: portar
también otras variantes de la misma época basadas en Angband.

## Naturaleza del proyecto

- Variantes de Angband (Angband, KAngband, OAngband, ZAngband) sobre base 2.9.x.
- **UI en Tcl/Tk**; el motor del juego en C se compila como **librería compartida**
  (`angband.so`/`.dll`) que se carga desde Tcl. Un pequeño ejecutable `boot`
  (con USE_TCL_STUBS) arranca el intérprete y carga la librería.
- Build ya en **CMake** (min 2.6). El `build/CMakeCache.txt` original es de la
  máquina del autor (`/home/nick/OmnibandTk-1.5`, Linux) → hay que regenerarlo.
- Existe ruta **Unix/X11** completa (`src/common/main-x11.c`, `TclTk-x11.c`),
  además de la de Windows.

## Obstáculos identificados

1. **Tcl/Tk 8.5 con API interna** (el más serio): incluye cabeceras privadas
   (`tclInt.h`, `tkInt.h`) y usa símbolos internos (`TclStat`, `interp->result`)
   eliminados/cambiados en Tcl 8.6 y 9.0. Ficheros afectados: `main-x11.c`,
   `canv-widget.c`, `widget1-dll.c`, `TclTk-dll.c`.
2. **Dependencias externas no incluidas en el repo**: árbol fuente de Tcl/Tk 8.5.7
   (`tcl8.5.7`, `tk8.5.7`) + install dir con `tclConfig.sh`; `treectrl 2.2.9`
   (solo runtime `.tcl` en `lib/`, falta el C); `TkHtml3.0` (solo `pkgIndex.tcl`);
   `zlib`.
3. **Ataduras a Windows / propietario**: enlaza `comdlg32`/`gdi32` (rama WIN32,
   evitable); audio vía **BASS** (`lib/bass.dll`, propietario Windows-only). Hay
   backend alternativo `src/sound/NoSoundCard` → compilable **sin sonido**.
4. **C de los 90**: requiere `-std=gnu89 -fcommon` y silenciar warnings.

## Nota sobre "buildpack"

Los Cloud Native Buildpacks (Heroku/Paketo) son para apps web sin estado y NO
encajan con una GUI Tcl/Tk. La herramienta correcta es un **Dockerfile** normal
(Debian + toolchain). Para *ejecutar* la GUI hará falta X11 (montar `$DISPLAY`)
o un VNC dentro del contenedor; para *solo compilar/validar* basta la imagen.

## Fases

### Resultado Fase 1 (2026-05-29) — ✅ ÉXITO

Compila y enlaza **limpio** en Debian 12 / gcc 12 contra Tcl/Tk 8.5.7 vendados.
**0 errores de compilador.** Artefactos producidos:
- `variant/AngbandTk/angband.so` (2.5M) — motor del juego
- `src/common-dll/common.so` (485K) — DLL de widgets Tcl/Tk (la del API interna)
- `src/boot/angband` (122K) — ejecutable lanzador
- `src/sound/NoSoundCard/sound-nocard.so`, `src/dbwin/dbwin.so`

Conclusión clave: vendar Tcl/Tk 8.5.7 desde fuente **esquiva por completo** el
problema de API interna en esta fase. El reto real se traslada a la Fase 3
(runtime/extensiones) y, si se quiere Tcl moderno, a la Fase 4.

Cómo reproducir: `./docker/build.sh` (log en `build-docker/build.log`).

**Las 4 variantes compilan** (0 errores): AngbandTk 2.5M, KAngbandTk 2.8M,
OAngbandTk 3.1M, ZAngbandTk 3.5M. Parche aplicado: `comdlg32` guardado bajo
`IF (CMAKE_HOST_WIN32)` en las 4. El enfoque escala a toda la colección.

- **Fase 1 — Prueba de concepto en Docker** ✅ COMPLETADA
  - 1a. Recopilar/fijar dependencias: Tcl/Tk 8.5.7 (fuente + install desde
    código fuente dentro de la imagen), treectrl 2.2.9, zlib (del sistema).
  - 1b. Dockerfile + script de build: Debian, variante AngbandTk, backend
    `NoSoundCard`, sin libs de Windows, ruta X11.
  - 1c. Compilar e **inventariar** todos los errores (especialmente API interna
    de Tcl) — el objetivo de la fase es medir el trabajo real, no que pase a la
    primera.
- **Fase 2 — Arreglar la compilación**: parchear `TclStat`, `interp->result`,
  includes faltantes; conseguir que enlace la librería + el `boot`.
### Resultado Fase 3 (2026-05-29) — ✅ ARRANCA CON GRÁFICOS

AngbandTk **inicializa y muestra su GUI** en Linux/Docker headless (Xvfb):
llega al diálogo de configuración de tileset (pestañas Icons/Music/Sound/Variant)
con los **tiles renderizándose** (David Gervais 32x32) y el **widget treectrl
funcionando**. Confirma: `common.so` + `angband.so` + `libtreectrl2.2.9.so`
cargados, Tcl/Tk 8.5.7 operativo, GIFs cargados nativamente por Tk (sin `Img`).

Reproducir: `./docker/build.sh` (una vez) y luego `./docker/launch.sh AngbandTk`
→ captura en `build-docker/screenshot.png`, log en `build-docker/run.log`.

Pasos clave de la fase:
- Compilar **treectrl 2.2.9** como `.so` (TEA) dentro de la imagen y parchear su
  `pkgIndex.tcl` (cargaba `treectrl22.dll`).
- Harness headless: `docker/run-game.sh` monta el layout de runtime, arranca Xvfb,
  lanza el juego y captura pantalla; `docker/launch.sh` lo orquesta.
- **Bugfix de la ruta unix** (`tk/init-startup.tcl`): el bloque que carga la consola
  tkcon (solo-unix, `[Platform unix]`) llamaba a `CPath` ~40 líneas antes de que
  `misc.tcl` lo definiera. En Windows el bloque se salta, por eso nunca falló.
  Arreglado inlineando `[CPath lib]` → `[file join $Angband(dir,common) lib]`.

Errores de fondo `IGNORE errors about tclIndex` son inofensivos (el propio
`errorInfo.tcl` dice ignorarlos: no se usa autocarga vía tclIndex).

**Tkhtml 3.0 → .so** ✅ (necesario en birth): compilado desde el mirror
`github.com/olebole/tkhtml3` (Debian-astro, declara versión 3.0; TEA). Truco:
el `configure` del tarball no es ejecutable → `sh configure`. Verificado: carga
en wish 8.5, crea widget `html`, parsea HTML, `package present Tkhtml` = 3.0.
Integrado en el staging (copiar `.so` a `lib/TkHtml3.0/` + parchear pkgIndex).
Interfaz VNC para jugar: `docker/play.sh` (x11vnc+fluxbox, `vnc://localhost:5900`).

**Bugfix 64-bit crítico (L64)** ✅: `h-type.h` define `s32b`/`u32b` como `long`
salvo que `L64` esté definido (entonces `int`). El original solo definía `L64`
para DEC Alpha/Tru64, así que en Unix LP64 (Linux/macOS x86_64/arm64) los enteros
"de 32 bits" eran de **8 bytes**. Eso: (a) rompía la RNG (`Rand_div` asume
wraparound a 32 bits → `randint` fuera de rango → el bucle de tirada de stats en
`birth-tnb.c` nunca cumplía `j<=STAT_LIMIT` → **dice roller colgado**), y (b)
corrompía el layout de structs/savefile (síntoma: warnings `size=4 != fLength=8`).
Fix: `-DL64` en `CMAKE_C_FLAGS` (en `docker/in-container-build.sh`) para Unix
64-bit. OJO: NO en Windows (LLP64, `long`=4 → la rama actual es correcta). Se usa
C_FLAGS y no `ADD_DEFINITIONS` porque cada variante hace
`SET_PROPERTY(DIRECTORY COMPILE_DEFINITIONS ...)` que pisaría la definición.
Verificado: tras recompilar, 0 warnings de struct.

**zlib runtime** ✅: `icon-dll.c` hace `dlopen("lib/" ZLIB_LIB_SH_NAME)` =
`lib/libz.so` (en Windows `zlib1.dll`) para comprimir iconos/savefile, y verifica
que `zlibVersion()` == `ZLIB_VERSION` de compilación. Síntoma sin él: Warning
"couldn't load lib/libz.so" al generar mazmorra. Fix: stagear el `libz.so` del
sistema en `stage/lib/libz.so` (versión 1.2.13 = la de compilación → pasa el
check). En los scripts de runtime.

**UX runtime (VNC)**: con Xvfb a 1280×800 el layout por defecto de ventanas no
cabía → `NSWindowManager::Setup` calculaba geometrías negativas → error
`bad geometry specifier "-521x-950"` (en `InitOther`), que disparaba el diálogo
"Error in AngbandTk / Quit now?". Fix: Xvfb a **1920×1200** (en `run-vnc.sh` y
`run-game.sh`). Además `run-vnc.sh` configura fluxbox con tema **BlueFlux**
(controles de ventana con estilo) + ClickToFocus. NOTA: NO quitar `errorInfo.tcl`
del stage — define el manejo de errores (procs usados por otro código); sin él
cualquier error Tcl se vuelve fatal y cierra la sesión.

**treectrl: SourceForge 2.2.9 ≠ el treectrl propio de Tim Baker** (autor de ambos):
el elemento `text` de la 2.2.9 oficial no tiene `-lmargin1/-lmargin2/-rmargin`
(añadidos en treectrl posteriores; los hay en 2.4.1). AngbandTk los usa. OJO:
casi todos los usos en el tcl son `$text tag configure` (opciones VÁLIDAS del
widget text de Tk, no tocar); solo `messages-window.tcl:207` era un treectrl
`element create` → se le quitó `-lmargin2` (cosmético). NO se bumpó treectrl a
2.4.1 porque `src/common/treectrl.c` registra un tipo de elemento propio vía la
**API de stubs interna** de treectrl → sensible a la versión/ABI. Si aparecen más
opciones de treectrl no soportadas, mismo patrón (quitar del `element create`).

**TclZip** ✅ (records de personaje / record de muerte, `tomb.tcl`/`record.tcl`):
era la extensión nativa de Tim Baker (`tclzip.dll`, comando `zip` sobre minizip),
cuyo source NO está en el repo. En vez de cazar/compilar el C (ABI incierta), se
escribió un **shim en Tcl puro** en `lib/TclZip/tclzip-shim.tcl` que replica el
API (`zip` → handle con `add/write/read/glob/extract [-tomemory]`) envolviendo
`zip`/`unzip` del sistema. `pkgIndex.tcl` ahora es platform-aware (Windows: dll;
Unix: shim). Requiere `zip`/`unzip` en la imagen (añadidos al Dockerfile).
Verificado round-trip con tclsh.

**`grab failed: window not viewable`** (al morir/diálogos modales): bajo fluxbox
el mapeo de ventanas se difiere, y `NSUtils::GrabSave` (`utils.tcl`) hacía
`grab $win` antes de que la ventana fuera viewable. Fix: esperar visibilidad
(`update idletasks` + `tkwait visibility`, como tk_dialog) antes del grab.

Sonido: BASS Windows-only → mudo (NoSoundCard) o backend nuevo (SDL_mixer), Fase 4.

NOTA endgame: las nuevas variantes a portar están en `newvariants/` (p.ej.
`newvariants/calcrogue/`).

- **Fase 3 — Que arranque**: resolver extensiones runtime (treectrl, TkHtml)
  para que el juego inicialice, no solo compile.

  Análisis del paquete `OmnibandTk-1.5/` (release Windows funcional que dejó el
  usuario; NO versionar). Hallazgos:
  - **Layout runtime** confirmado: `<root>/angband(.exe)` + `lib/` + `tk/` +
    `variant/<V>/angband.<so|dll>`. Coincide con `main-boot.c`.
  - **Assets = originales del repo** (ya en git): 151 tiles GIF (incl. 68 del
    tileset David Gervais en `tk/image/dg/`), 398 sonidos WAV (`lib/egg`, 17 MB),
    40 configs de tiles (`-assign/-sprite/-alternate`), 29 `.prf`, 28 `.vlt`.
    Los `-assign/-sprite` se autogeneran ("Do not edit"). Tk carga los GIF de
    forma **nativa** → no hace falta el paquete `Img` para arrancar.
  - **Lo que el paquete añade (no es fuente)**: distribución Tcl/Tk 8.5.7 y los
    binarios compilados. Extensiones binarias a portar a `.so` para Linux:
    **treectrl22, Tkhtml30, tclzip** (dbwin/common/sound-nocard ya las compilamos).
  - **Sonido**: en Windows vía BASS (propietario: `bass.dll`, `music-bass.dll`,
    `sound-bass-stream.dll`). En Linux: o mudo (`NoSoundCard`) o backend nuevo
    (SDL_mixer/OpenAL) — Fase 4.
  - Tilesets disponibles: ascii, original32, adam (Adam Bolt 16/32), dg32
    (David Gervais), +iso, y combinaciones (`adam+orig`, `ascii+dg32`, ...).
- **Fase 4 (opcional) — Modernizar y jugar**: portar a Tcl 8.6/9.0; runtime X11
  o VNC en el contenedor para jugar.
- **Fase 5 — Más variantes**: aplicar el mismo proceso a KAngband, OAngband,
  ZAngband y otras variantes de la época.

## Estudio de variantes para portar (newvariants/)

- **TinyAngband 0.0.3a** (base XAngband 1.3.0, linaje ZAngband/Hengband):
  VIABLE, esfuerzo medio. Versión inglesa ya existe (5 `#ifdef JP`), ~52 ficheros
  comparten nombre con ZAngbandTk → ZAngbandTk es plantilla directa. La más rápida.
- **ToME 2.3.5** (PernAngband→Angband; la variante OBJETIVO del revival):
  VIABLE pero el port más grande. ~276k líneas/109 .c (≈2× ZAngbandTk), Lua
  embebido (`lua/` + tolua + 62 `.lua` de contenido), `player_type` de 1101 líneas
  (skills/gods/fates), subsistemas propios (skills.c, gods.c, ~30 q_*.c, loadsave.c).
  Usa `z-term.c` (el term Tk enchufa). DECISIÓN: usar la **2.3.5 (C)**, NO la
  2.4.0 de github.com/tome2/tome2 (que es **C++**+CMake y choca con el framework C
  de Omniband). Enfoque por niveles: (1) compila+bootea en term Tk con tiles;
  (2) ventanas Omniband cableadas a sus structs (muy grande).
- **TomeTik-03** (newvariants/): ToME gráfico **Windows GDI** (NO Tk; el "Tik" no
  es "Tk"). No es atajo para la integración Tk, PERO: trae tilesheets BMP
  (8/16/32 + masks) y los `graf-*.prf` con los mapeos entidad→tile del set EXACTO
  de ToME (incl. `graf-iso.prf` completo, 2069 mapeos de H. Malthaner). El renderer
  iso en Windows es stub; **Omniband YA tiene motor iso** (`widget-iso.c` +
  `dg_iso32.gif` + configs `dg32+iso`). Plan: convertir los `.prf` de TomeTik al
  formato `-assign/-sprite` de Omniband → tileado de ToME casi gratis, e iso
  terminable (lo que TomeTik dejó a medias).

### ToME: cómo TomeTik hace los tiles (diff contra ToME 2.2.2 base)

TomeTik está basado en **ToME 2.2.2** (source en `newvariants/tome-222-src.tar.bz2`).
ToME 2.2.2 ya tenía modo gráfico (`use_graphics` en `main-win.c`); TomeTik añadió
~344 líneas: tileset **32X32.BMP con `ANGBAND_GRAF="gervais"`** (David Gervais 32×32)
+ `mask32.bmp`, `use_bigtile`/`use_zoom`, y blit con máscara
(`BitBlt SRCAND` + `SRCPAINT`). Los mapeos van en `lib/pref/graf-*.prf`.

CONVERGENCIA: **TomeTik y Omniband usan el MISMO tileset David Gervais 32×32**
(Omniband: `dg_*.gif`). Implicaciones para el port ToME→Omniband:
- Los gráficos ya están en Omniband (no reconvertir arte).
- Reutilizar la DATA de mapeo ToME→Gervais de TomeTik (`graf-*.prf`, incl. iso
  completo de H. Malthaner) → convertir al formato `-assign/-sprite` de Omniband.
- Omniband tiene renderer iso (`widget-iso.c`) → termina el iso que TomeTik stubó.
DECISIÓN: basar el port Omniband de ToME en **2.2.2** (base de TomeTik → tiles
encajan directos). Omniband NO reusa el render GDI de TomeTik (usa su term Tk).

## Port ToME → Omniband (EN CURSO)

Base: **ToME 2.2.2** (copiada a `variant/ToMETk/`), por compatibilidad con los
tiles de TomeTik.

### ToME Fase 0 (2026-05-29) — ✅ la base compila en gcc moderno
Build standalone X11 de ToME 2.2.2 en Docker: **0 errores, binario `tome` 3.5MB**.
El intérprete Lua + tolua (genera bindings `w_*.c` desde los `.pkg`) funcionan.
Solo 2 fixes: (1) `-Ilua` en includes; (2) 3 casts-as-lvalue en `init2.c`
(`C_MAKE((char*)a_select_flags,...)` → quitar el cast; gcc moderno no acepta
asignar a un cast). Conclusión: el código ToME 2.2.2 es modern-gcc-compatible y el
subsistema Lua se construye → de-riesga la integración.
Reproducir: `make -f makefile.std default CC=gcc "COPTS=-O0 -std=gnu89 -fcommon -w"
"INCLUDES=-Ilua" "DEFINES=-DUSE_X11" "LIBS=-lX11 -lXext"`.

### ToME Fase 1 (2026-05-29) — inventario del gap de integración
Creado `variant/ToMETk/CMakeLists.txt` (modelo ZAngbandTk; engine+Lua, excluye
main-*.c) + `ADD_SUBDIRECTORY(ToMETk)`. CMake configura OK. Primer build de
integración (`tome_library`): **2271 errores — PERO ~1800 son una CASCADA**, no
trabajo real.

Raíz de la cascada: `src/common/tnb.h` línea 20 — guard que solo reconoce
ANGBANDTK/KANGBANDTK/OANGBANDTK/ZANGBANDTK. Con `TOMETK` (nuevo), el guard lanza
`#error "you must pass -DxANGBANDTK"` y aborta ANTES de definir tipos básicos
(bool/s32b/cave_type) → todo "undeclared" en q_*.c y el engine.

`tnb.h` es la **capa de abstracción por-variante**: el código común usa nombres
genéricos (`p_ptr_py`, `cave_feat(y,x)`, `MAX_R_IDX`, `dun_level`…) y `tnb.h` los
traduce a los símbolos reales del engine. El bloque `#if defined(ZANGBANDTK)`
(líneas 114-169, ~55 mapeos) es la plantilla.

VERIFICADO: el bloque TOMETK es **~95% copia del de ZANGBANDTK** (coinciden:
max_r_idx, max_a_idx, max_quests, dun_level, point_based, autoroller, player_base,
player_name, MAX_WID/HGT, cave[y][x].feat, py/px globales). Ajustes ToME:
`maximize`/`preserve` (no `*_mode`), `MAX_P_IDX→max_rp_idx`, inscripciones vía
quarks (`quark_str(o->note)`).

PRÓXIMO PASO: (1) añadir TOMETK al guard + bloque TOMETK en tnb.h + a los `#if`
de features → colapsa la cascada. (2) Resolver el gap REAL: cola común
(interp1.c ~64, birth-tnb.c ~49, struct.c ~20, interp2.c ~20, town.c, icon1.c,
describe.c…) adaptándose a los structs/API reales de ToME (~250-300 errores, el
trabajo de integración genuino, iterativo y multi-sesión).

CONFIRMADO (captura de TomeTik original): el layout multiventana de ToME
(Main+inventario+minimapa+recall+mensajes) mapea 1:1 al de Omniband.

### ToME Fase 2 — inicio: cascada colapsada, gap real cuantificado (2026-05-29)
Dos fixes derribaron el "muro" de 2271 errores → **199**:
1. **tnb.h**: añadido TOMETK al guard + bloque de mapeos TOMETK (~95% copia de
   ZANGBANDTK; ajustes ToME: `max_rp_idx`, `maximize`/`preserve`, `max_dlv[]`
   array, inscripciones por quarks `o->note`) + TOMETK en LORE + stub
   `monster_is_friend(m) 0`.
2. **CMakeLists ToMETk**: excluir del build los .c que NO son unidades de
   compilación (se #incluyen en plots.c/main-x11.c): `q_*.c`, `load_gif.c`,
   `maid-x11.c`. Eran ~1800 errores de cascada FALSOS (compilados sueltos sin
   angband.h). Lección: GLOB de *.c en variantes Angband coge ficheros #incluidos.

**Gap REAL = 199 errores, todos en la cola común** (interp1.c 39, setting.c 32,
birth-tnb.c 29, interp2.c 17, struct.c 11, describe.c 10, icon1.c 8…), adaptando
el bridge Tcl a los structs/globals/firmas de ToME. Categorías: nombres distintos
(O_NAME_MAX, inventory, player_title, CHEAT_MAX → mapeos tnb.h), structs distintos
(player_type sin total_weight), firmas distintas (object_flags), y cascadas de
parseo en setting.c desde pocas macros (raíz → limpia muchas). Trabajo iterativo
y acotado, NO una incógnita. Tras compilar: link (funciones ToME que llama la
cola), luego struct.c reflection (player_type 1101 líneas), luego runtime.

### ToME Fase 2b — grind de integración (en curso): 2271 → 105
Resolución iterativa del gap real. Trend: 199 → 136 → 105 errores.
Fixes aplicados (todos confirmando que ToME = linaje ZAngband salvo divergencias):
- tnb.h bloque TOMETK: defines A_MAX=6, MAX_CLASS→max_c_idx, O_NAME_MAX, TOWN_DAWN,
  FEAT_SHOP_HEAD/TAIL→FEAT_SHOP, VERSION_NAME; + TOMETK en gates CHEAT_MAX y
  r_info_flags4-6.
- birth-tnb.c: bloque TOMETK (BIRTH_*, keyword_birth, STAT_LIMIT 53).
- setting.c: TOMETK en gates ZANGBANDTK (cheat_variable + bucle option_info[]) —
  ToME usa option_info[]/cheat_info como ZAngband. Tumbó setting.c 32→2.

Quedan ~105, el long tail de divergencias genuinas de ToME:
- Globals vs miembro: `inventory`, `player_title`, `h_info` (existen en ToME pero
  el bridge espera otra forma), `player_type` sin `total_weight`/`health_who`/
  `monster_race_idx` (en ToME son globales).
- Sistema mágico: `mp_ptr`/`magic_info` (ToME diverge de ZAngband).
- Firmas: `object_flags`/`object_flags_known` (7 args en ToME, no 4),
  `item_activation`, `predict_score`, `look_mon_desc` → necesitan adaptadores.
- Otros: `FEAT_INVIS`, `NAME_TEXT_TYPE`, `SNDGRP_MAX`, `bg_max`, `high_score` tipo.
- Concentrados en interp1.c (33), interp2.c (13), describe.c (10), birth-tnb.c (9),
  icon1.c (8), struct.c (3).
Tras compilar: link (funcs ToME que llama la cola) → struct.c reflection
(player_type 1101 líneas) → runtime → tiles.
