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
  VIABLE, esfuerzo medio. Versión inglesa ya existe (build sin `-DJP`), ~52 ficheros
  comparten nombre con ZAngbandTk → ZAngbandTk es plantilla directa. La más rápida.
  **ELEGIDA (2026-05-30)** como siguiente port tras estancarse ToME. Mediciones que
  decidieron (inspección directa de las 4 candidatas de `newvariants/`):
  - **TinyAngband: 53/65 `.c` comparten nombre con ZAngbandTk** (las 12 que no son
    casi todas `main-*.c`, que el bridge excluye; extra real sobre el motor = solo
    `autopick.c`, `chuukei.c`, `japanese.c`). Usa `option_type option_info[]`
    (tables.c:2669) idéntico a ZAngband → `setting.c` encaja (lo que más sufrió ToME).
    Misma época 2.9.x/gnu89, sin Lua/subrazas/dioses. ZAngbandTk es plantilla ~drop-in.
  - **FAangband 1.2.1** (línea OAngband): 93 `.c`, solo 28 en común con ZAngbandTk
    (37 con OAngbandTk); birth/opciones propios. Medio-difícil, más grande.
  - **NPPAngband 0.5.2**: base **Angband 3.1.x** (readme.txt) — una generación de
    UI/structs por delante del 2.9.x de Omniband (`option_table`, no `option_info`).
    Salto estructural MAYOR que ToME. 82 `.c`, 35 en común.
  - **Quickband 2.0.2**: construido **sobre NPP** (3.1.x) → mismo abismo que NPP.
    Irónicamente el de "sabor vanilla" más minimalista, pero de los más caros de cablear.
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

### ToME Fase 2b COMPLETADA (2026-05-29) — angband.so de ToME compila Y enlaza ✅
**2271 errores → 0**. `build-tome/variant/ToMETk/angband.so` = 6.7MB ELF aarch64.
Resumen del grind (todo via #ifdef TOMETK, ToME=linaje ZAngband con divergencias):
- Mapeos/defines en tnb.h: A_MAX, MAX_CLASS(max_c_idx), O_NAME_MAX, TOWN_DAWN,
  FEAT_SHOP, VERSION_NAME, high_score(struct), TR3_LITE(TR3_LITE1), item_activation,
  birther(tnb_birther), bg_max(max_bg_idx)/h_info(bg), CAVE_LITE(CAVE_PLIT),
  inventory(p_ptr->inventory), FEAT_INVIS(FEAT_NONE), look_mon_desc, object_flags
  (adaptador 7->4 args).
- TOMETK añadido a gates ZANGBANDTK en: tnb.h (LORE, ART_CURNUM, CHEAT_MAX+cheat_info),
  setting.c (cheat_variable/option_variable/bucle opciones), icon1.c (CAVE_VIEW x2,
  boring-grid), interp1.c (cheat o_var, title via quark, magia stub, health_who/
  monster_race_idx como globales, total_weight via calc_total_weight), interp2.c
  (activate, total_weight, bloque high-score gateado+stub), struct.c (NAME_TEXT_TYPE),
  sound.h (SNDGRP_MAX), bind.c (title via quark).
- TNB_SQUELCH desactivado (ToME tiene squeltch.c propio).
- Link: gateadas player_birth (birth.c) y Term_fresh (z-term.c) en el engine ToME
  con #if !defined(TOMETK) (las provee el comun, patron #if 0 /* TNB */ de ZAngband).
- CMake: excluidos del build los .c #incluidos (q_*.c, load_gif.c, maid-x11.c) y
  Windows-only (main-*.c, readdib.c). Lua/tolua bindings (w_*.c) pre-generados.

PENDIENTE (Fase 3): struct.c reflection completa para structs ToME (player_type
1101 lineas) si las ventanas Omniband muestran datos incompletos; runtime (stagear
ToME + tk + lib, arrancar bajo VNC); tiles (graf-*.prf de TomeTik -> assign).

### ToME Fase 3a COMPLETADA (2026-05-29) — angband.so de ToME hace dlopen limpio ✅
De ~35 símbolos undefined → 0 reales (solo quedan 3 weak: `_ITM_*`, `__gmon_start__`,
que todo ELF lleva y dlopen resuelve a NULL). Prueba real: `dlopen(common.so,
RTLD_GLOBAL)` + `dlopen(angband.so, RTLD_NOW|RTLD_GLOBAL)` → ambos OK.
- `variant/ToMETk/src/tome-stubs.c`: stubs para funciones/datos de la cola común
  gateados-fuera para TOMETK (no se compilan, sin conflicto): forget_lite/update_lite/
  town_illuminate, target_set_location/monster, store_cost, sense_chance,
  item_tester_hook_cast/study, macro_delete, init_sound, easy_floor; + grupo común
  gateado: keyword_term_color[16] (DARK..L_UMBER, espejo de tk/config/config-flavor),
  r_info_flags[10]={0}/r_info_flags_max=0, MonsterMemoryToArray, angtk_roff,
  angtk_savefile_info, objcmd_floor, objcmd_spell.
- `player_is_here` macro en tnb.h: usaba py/px globales → cambiado a p_ptr->py/px.

### ToME Fase 3b EN CURSO (2026-05-29) — ToME ARRANCA el GUI de Omniband ✅
`./docker/play.sh ToMETk` (VNC) / `docker/run-game.sh ToMETk` (headless). Llega al
diálogo de configuración inicial (pestañas Icons/Music/Sound/Variant con preview de
sprites) — mismo punto de init que AngbandTk. Fixes para llegar:
- `interp2.c` objcmd_game IDX_VARIANT: añadido caso TOMETK → "TOMETK".
- `interp2.c` objcmd_game IDX_VERSION: caso TOMETK → "2.2.2" (los VERSION_* de ToME
  son s32b fijados por el módulo en runtime, valen 0 en el arranque Tcl).
- `setting.c` bucle de cheats: faltaba rama TOMETK → `setting.name` quedaba obsoleto
  ("allow_animation") y se duplicaba (panic Setting_Add). Añadido TOMETK usando
  `cheat_info[i].o_text/o_desc` (ToME tiene `option_type cheat_info[CHEAT_MAX]` en
  cmd4.c, des-staticado; cheat_variable ya mapeaba `*cheat_info[i].o_var`).
- `tk/init-startup.tcl`: TOMETK añadido a `proc variant` y bloque que fija
  Angband(name)="ToMETk"/Angband(copy); version.txt = "2.2.2r1" (formato %d.%d.%dr%d).
- Andamio UI: `variant/ToMETk/tk/` copiado de ZAngbandTk (config/doc/image).

PENDIENTE Fase 3b: probar interactivo por VNC (clic OK en el diálogo → ¿birth?); la
UI de creación de ToME (razas/clases/reinos/dioses) no existe en Omniband; warnings
"r_info #N not in any group" (grupos de monstruos de ZAngband no cubren índices ToME);
config de tiles con índices de ToME (de TomeTik); sonido/música.

### ToME Fase 3b/3c (2026-05-29) — birth (creacion de personaje) FUNCIONAL ✅
Reproduccion headless: `docker/debug-birth.sh ToMETk` (lanza con `-setup false` +
env `TNB_AUTONEW=1` que dispara `NewGame` via hook temporal en init-startup.tcl).
Cadena de bloqueos depurada (cada uno revelaba el siguiente), con checkpoints
`fprintf(stderr,...) + fflush` y volcado de `errorInfo` en HandleError (bgerror.tcl):
1. `play_game(TRUE)` colgaba en `load_player()`: ToME lo llama siempre y en
   partida nueva el savefile no existe -> `msg_print(NULL)` bloquea en "-more-".
   Fix: en interp2.c IDX_NEW, `savefile[0]='\0'` antes de play_game para TOMETK.
2. Colgaba en `process_hooks(HOOK_INIT)`: el hook `lua_intro_init` (splash animado
   de ToME) hace inkey() sin ventana. Fix: desactivado en lib/scpt/intro.lua.
3. Colgaba en `validate_bg()`: race_chart[] sin inicializar para TOMETK -> recursion
   sobre charts basura desborda chart_checked[]. Fix: gateado fuera (birth-tnb.c).
4. SEGV en `objcmd_info` (Tcl_NewStringObj(NULL)): keyword_race[] sin poblar para
   TOMETK (solo A/K/O y Z). Fix: interp1.c keyword_race = rp_name+race_info[i].title,
   keyword_class = c_name+class_info[i].title (ToME guarda nombres como offset s32b).
5. Tcl `can't read amount`: msgs/birth/en.msg no fijaba $amount para TOMETK. Fix:
   anadido TOMETK al grupo amount=100.
6. Tcl `can't read screenList`: birth.tcl no definia la lista de pantallas para
   TOMETK. Fix: `Gender Race Class AutoRoll Points` (+ variante RollOne).
7. Tcl `birth stage is "class"`: objcmd_birth_class no avanzaba la etapa para TOMETK.
   Fix: birth-tnb.c -> BIRTH_GENERATE tras clase (ToME no tiene pantallas de realm).
8. Tcl `can't read height`: charinfo-canvas.tcl no fijaba alto para TOMETK. Fix:
   anadido a grupo 25-lineas.
9. NSBirth::Next/Back sin transiciones para TOMETK. Fix: anadido TOMETK al bloque
   de navegacion ANGBANDTK (mismo flujo gender/race/class/roll).
RESULTADO: la ventana de birth renderiza limpia (genero F/M/N, raza, clase) con
botones Options/Back/Next/Quit. PENDIENTE 3c: conducir birth hasta el final
(roll/aceptar) y entrar al juego (ventana de mapa + generate_cave). Quedan datos
de instrumentacion TNBDBG en el codigo (a limpiar antes de cualquier commit).
Limitaciones birth ToME: sin pantallas de subraza/especializacion/dios (valores
por defecto); falta validar que un personaje minimo arranque la partida.

### ToME Fase 3c (2026-05-29) — NULL-derefs de C tras elegir clase (gdb)
Con gdb (`docker/gdb-birth.sh`, instala gdb + Xvfb + auto-New + auto-drive) se
cazaron 3 segfaults en cadena al avanzar tras la pantalla de clase, todos por
PUNTEROS de ToME que el flujo de birth de Omniband no rellenaba:
1. `get_extra()` xtra1.c: `rmp_ptr->r_exp` NULL → ToME tiene **subrazas**
   (race modifiers). Fix: objcmd_birth_race fija subraza por defecto
   (`p_ptr->pracem=0; rmp_ptr=&race_mod_info[0]`) para TOMETK.
2. `calc_bonuses` via Lua `toluaI_get_..corruptions`: `p_ptr->corruptions[]` NULL.
   El `player_wipe` COMUN (birth-tnb.c) hacia WIPE(p_ptr) sin preservar los punteros
   dinamicos de ToME (corruptions/powers), que se alocan en init (init_corruptions
   desde Lua). Fix: player_wipe comun preserva powers/corruptions + C_WIPE corrupt.
   para TOMETK (espejo del player_wipe de ToME en birth.c).
3. `calc_bonuses` xtra1.c PRACE_FLAG: `spp_ptr->flags1` NULL → ToME tiene
   **especializaciones de clase** (spp_ptr/pspec). Fix: objcmd_birth_class fija
   `p_ptr->pspec=0; spp_ptr=&class_info[pclass].spec[0]` para TOMETK.
Tras los 3: birth avanza Gender->Race->Class sin segfault. (El auto-drive headless
provoca luego un crash en TclEvalObjvInternal que parece reentrancia del propio
auto-drive; validar conduciendo manual por VNC.)
PENDIENTE: probar manual hasta roll de stats + aceptar -> entrar al juego.

### ToME Fase 3c cont. (2026-05-29) — birth fluye hasta la pantalla final
Tras los 3 NULL-deref (subraza/corruptions/spec), el birth recorre
Gender->Race->Class->**Points** (reparto de 48 puntos de stats) SIN crash.
Fixes adicionales (Tcl):
- `birth.tcl` NSBirth::NSBirth: bloque TOMETK que rutea por point-buy
  (`Setting point_based 1` para activar la opcion del MOTOR p_ptr_point_based,
  `Info $oop pointbased 1`, e inicializa `points,$stat=10` — ninguna rama lo hacia).
  Sin esto: "not using point-based generation" (C rechazaba el point-buy).
- Auto-drive headless con guard de reentrancia (descarta que el crash fuera
  artefacto del `after` durante el bombeo de eventos de inkey).
BLOQUEO ACTUAL (real, no reentrancia): al pasar de Points a **RollOne** (que
muestra la ventana del Player con el personaje tirado) -> SIGSEGV en
TclEvalObjvInternal (Tcl puro, sin frame C cerca = corrupcion de memoria previa).
CAUSA probable: la tabla de reflection de structs (`src/common/struct.c`) tiene el
layout de `player_type` MAL para ToME -> los WARNINGs del arranque
("field='player_type.energy' size=2 != fLength=4", player_class.title 8!=4,
player_race.r_exp, monster_*, object_*, inventory...). Escribir/leer esos campos
via `struct set/get` usa offset/tamano equivocado y machaca memoria adyacente; el
crash se manifiesta despues al despachar un comando Tcl.
SIGUIENTE (sub-tarea grande): corregir la reflection de struct.c para los structs
de ToME (player_type ~1101 lineas, monster_race/type, object_kind/type, player_race/
class, inventory) — que las fLength casen con sizeof reales de ToME.

### ToME Fase 3c COMPLETADA (2026-05-29) — BIRTH end-to-end + MOTOR EN BUCLE DE JUEGO ✅
Atajo (c) para el crash de RollOne: el SEGV no era struct reflection de fondo sino
**NSCharInfoCanvas::SetInfo** (la hoja de personaje) leyendo decenas de campos via
'angband player'/'struct'/'equipinfo' con el layout player_type/inventory de ToME
sin adaptar. Diagnostico definitivo con valgrind (los use-after-free de Tkhtml3 en
el layout de <table> resultaron ser ruido; el crash real era SetInfo). Bisecado con
checkpoints: birth get_stats OK, birth get_player OK (calc_bonuses ya arreglado),
NSPlayer::SetInfo -> CRASH.
FIX atajo: `charinfo-canvas.tcl` NSCharInfoCanvas::SetInfo hace `return` temprano
para TOMETK (hoja de personaje en blanco; se reactivara al adaptar reflection).
Tambien (atajo, reversibles): birth.tcl gatea para TOMETK el render HTML de la
descripcion (Tkhtml3) y la construccion de tablas de stats; struct.c player_class/
player_race `title` FLD_STRINGPTR->FLD_INT32 (ToME usa offset s32b, no char*).
RESULTADO (auto-drive headless completo): Gender->Race->Class->Points->RollOne->
Accept -> `player_birth: inkey() returned` -> play_game: generate_cave OK ->
HOOK_GAME_START OK -> **ENTERING GAME LOOP**. ToME 2.2.2 crea personaje, genera el
nivel y CORRE EL BUCLE DE JUEGO como variante de Omniband. alive=1, sin crash.
PENDIENTE Fase 3d (display): la ventana de carga (.load) no cede el paso a la
ventana principal del mapa -> el motor juega pero no se ve el mapa. Crear/activar la
main game window para ToME. Luego: re-activar la hoja de personaje (reflection
player_type/inventory de ToME), tiles, sonido. Y limpiar TODA la instrumentacion
TNBDBG (birth-tnb.c, dungeon.c, setting.c[ya], bgerror.tcl, init-startup.tcl
[auto-drive], debug/gdb/vg-birth.sh) antes de commit.

### ToME Fase 3d (2026-05-30) — ventana principal: cadena de display despejada ~90%
Fix raiz para que aparezca el mapa: ToME's play_game no llamaba al hook de Omniband
`angtk_character_generated()` (lo llaman A/K/O/Z) que sourcea init-other.tcl ->
InitOther -> crea NSMainWindow + cierra la ventana de carga. Anadido en dungeon.c
(TOMETK) tras character_generated=TRUE. Eso destapo una CADENA de datos de ToME sin
cablear al config de display de Omniband; resueltos (todos via diagnostico gdb+valgrind):
- struct.c: `r_info find -flag` tolerante a flags desconocidos para TOMETK (r_info_flags
  stub vacio) -> no aborta el config de iconos.
- object1.c flavor_init: cablear `angtk_flavor_init(max,attr)` para TOMETK (mismos
  arrays/constantes que ZAngband) -> g_flavor dejaba de ser NULL.
- icon-dll.c Icon_GetIndexFromObj/Icon_Validate: clamp de indice de icono fuera de
  rango en vez de abortar (config de tiles andamiado no cuadra con ToME).
- config.tcl: forzar set de iconos "ascii" para TOMETK (evita cargar imagenes de tiles,
  cuyo config corrompia memoria).
- config.tcl ReadTownVault: return temprano para TOMETK (ToME genera su pueblo).
- config-map: anadir TOMETK al bloque que crea sym.water/lava/grass/tree/...
- **3 BUGS REALES de sonido (sound.c)**: (1) la tabla de keywords de monstruos asumia
  indices de 3 digitos -> ToME tiene >1000 monstruos -> sprintf desbordaba -> corrupcion
  de heap (sobre-dimensionado para TOMETK); (2) grupos de sonido con keyword NULL pero
  count>0 -> guard; (3) **`keyword_term_color` en tome-stubs.c no estaba NULL-terminado**
  -> Tcl_GetIndexFromObj leia fuera -> SIGSEGV (anadido NULL final).
- map.tcl NSMap::InitModule: features sin mapear (sym.blank) -> asignar sym.floor0 por
  defecto para TOMETK en vez de abortar.
RESULTADO: InitOther llega hasta "before NSMainWindow creation". 
BLOQUEO RESTANTE: crash dentro de la creacion de NSMainWindow, MISMO patron `0x1` en
TclEvalObjvInternal (Tcl puro, sin escritura invalida en valgrind) que el crash de
NSCharInfoCanvas::SetInfo -> es la **corrupcion de la reflection de player_type**
resurgiendo (la barra de estado / sub-ventanas leen player_type via 'struct'/'angband
player' con el layout sin adaptar para ToME). 
CONCLUSION: el arreglo de fondo ya NO es tapar displays sino **adaptar la reflection de
struct.c para player_type de ToME** (size/offset reales; ver WARNINGs del arranque).
Esa es la siguiente tarea para que la ventana del mapa aparezca.

### ToME Fase 3d COMPLETADA (2026-05-30) — GUI COMPLETO + JUGADOR EN EL MUNDO ✅✅✅
InitOther COMPLETA (InitOther returned). ToME corre con el GUI de Omniband:
barra de menu (File/Inven/Action/...), ventana de tips "Welcome to ToMETk", ventana
Debug con datos reales de ToME (objetos: Broken Dagger, Bastard Sword, Scimitar...),
status bar "You see a patch of grass y=37,x=110" (el jugador esta en el mundo),
sub-ventanas (mensajes/misc/minimapa). Fixes finales tras crear NSMainWindow:
- tome-stubs.c keyword_term_color: prefijo **TERM_** (claves del array Value de
  value-manager.tcl) + terminador NULL (Tcl_GetIndexFromObj recorre hasta NULL).
- value-manager.tcl: instalar detalle qe `<Setting-show_flavors>` para TOMETK +
  bind plain_descriptions->show_flavors + mapeo show_flavors<->plain_descriptions en
  el proc Setting (ToME tiene la opcion plain_descriptions, no show_flavors).
- choice-window.tcl: gatear el qebind <Setting-show_flavors> para TOMETK.
- init-other.tcl InitBatFile: caso `TOMETK { set name tome }`.
- main-window.tcl/misc-canvas.tcl: NSCharInfoCanvas::SetInfo y NSMiscCanvas::Arrange
  saltan el contenido del jugador para TOMETK (reflection sin adaptar).
PENDIENTE Fase 3e:
- El AREA DEL MAPA sale en negro: el motor sigue al jugador (status bar ok) pero el
  widget del mapa no dibuja el nivel (probable redraw/turno; en headless no hay input
  -> validar interactivo por VNC moviendose). 
- Error menor `can't read "combine"` (opcion de inventario) capturado.
- Reactivar hoja de personaje + misc canvas (adaptar reflection player_type/object_type
  /inventory de ToME). Tiles reales. Limpiar TODA la instrumentacion TNBDBG.

### ToME Fase 3e (2026-05-30) — dialogos despejados; mapa aun negro (validar interactivo)
- Fix error `combine`: messages-window.tcl / message-history.tcl no fijaban $combine
  para TOMETK -> anadido a la rama ZANGBANDTK (set combine 0).
- Headless: cerrados tips (.tips) + dialogos modales y forzado Ctrl-R, PERO el mapa
  sigue negro y el jugador no se movio con keypress inyectado -> 'angband keypress'
  headless NO llega al bucle de juego (el input real por VNC si). 
- Hipotesis del mapa negro: (a) el widget del mapa no esta centrado en el jugador
  (muestra area inexplorada = negro); (b) las rejillas de cave no se dibujan al widget.
  Validar MOVIENDOSE por VNC (teclas reales) -> si el mapa se puebla, era centrado/redraw.
PENDIENTE: confirmar dibujado del mapa moviendose (VNC); si no, investigar el centrado
(Global main,widget,center / <Dungeon-enter>) o la conexion term->map widget. Luego iso
(dg32+iso, requiere arreglar el config de tiles) + reflection player + limpieza TNBDBG.

### ToME Fase 3e (2026-05-30) — CAUSA del mapa que se vacia tras pintar: CAVE_SEEN
El mapa pintaba (motor+term+widget OK) y se quedaba negro al redibujar. Causa:
get_grid_info (icon1.c, el redibujado de Omniband desde g_grid) tenia a TOMETK en la
rama ZANGBANDTK, que decide "dibujar floor" con CAVE_LITE/GLOW/VIEW y NO comprueba
CAVE_SEEN. Pero el map_info de ToME (cave.c:958) dibuja con `info & (CAVE_MARK |
CAVE_SEEN)`. La hierba del wilderness es CAVE_SEEN (visible) pero no marcada/lit -> el
pintado en vivo (map_info) la mostraba, pero el redibujado (get_grid_info) la dejaba
vacia. FIX: ToME usa CAVE_SEEN como AngbandTk -> movido TOMETK a la rama A/K/O
(CAVE_SEEN) en get_grid_info, tanto para boring grids (floors) como interesting
(walls). [Tambien: timer de animacion desactivado para ToME como test; reactivar.]
Pendiente: validar por VNC que el mapa AHORA se queda pintado al moverse. Headless no
sirve (el keypress inyectado no llega al bucle -> nunca pinta).

## Port TinyAngband -> Omniband (EN CURSO)

Segundo port, arrancado al estancarse ToME en el dibujado del mapa. Estrategia:
**ZAngbandTk como plantilla casi drop-in** (53/65 `.c` comparten nombre; mismo
`option_type option_info[]`; misma época 2.9.x; sin Lua/subrazas/dioses, al
contrario que ToME). El gate del bridge sera `TINYANGBANDTK`.

### TinyAngband Fase 0 (2026-05-30) -- ✅ el motor compila Y enlaza en gcc moderno
TinyAngband 0.0.3a copiado a `variant/TinyAngbandTk/` (`src/` 65 `.c` + `lib/`,
6 MB). Build standalone X11 en Docker (Debian 12/gcc 12), **inglés (sin `-DJP`)**:
**0 errores de compilador, link rc=0, binario `tinyangband` 1.87 MB** (ELF aarch64).
Reproducir: `docker/tinyangband-build0.sh` (en el contenedor de deps;
log en `build-docker/tinyangband-build0.log`). Flags: `-O0 -std=gnu89 -fcommon -w
-DUSE_X11`, `-lX11 -lXext`. Conclusion: el codigo es modern-gcc-compatible sin
tocarlo → de-riesga la integracion (igual que la Fase 0 de ToME).
Unicos ajustes (misma leccion que ToME: el GLOB de mains coge ficheros ajenos):
excluir del build `maid-x11.c` (se `#include`-a desde main-xaw.c) y los mains que
no son X11 (`main-gcu/xaw/cap/mac/mac-carbon/win.c`, `readdib.c`).

PROXIMO PASO (Fase 1): `variant/TinyAngbandTk/CMakeLists.txt` modelo ZAngbandTk
(engine como `.so`, excluir main-*.c + maid-x11.c); `ADD_SUBDIRECTORY` en
variant/CMakeLists.txt; build inglés (sin JP). Luego Fase 2: añadir `TINYANGBANDTK`
al guard de `tnb.h` + bloque de mapeos copiado de `ZANGBANDTK` (~95% identico) y
colapsar la cascada, como en ToME.

### TinyAngband Fase 1 (2026-05-30) — ✅ CMakeLists + configura la integracion
Tras borrar el port parcial y recrear `variant/TinyAngbandTk/` desde upstream
(`newvariants/tinyangband-0.0.3/`, 65 .c + lib), siguiendo `docs/porting-guide.md`:
- `variant/TinyAngbandTk/CMakeLists.txt` (modelo ZAngbandTk, patron GLOB+FILTER de
  ToMETk): engine como `angband.so` (`tinyangband_library`), excluye main-*.c/maid/
  readdib. **Sin TNB_SQUELCH** (Tiny no tiene campo `squelch` en object_kind, verificado).
  Extra sobre ZAngband: autopick.c, chuukei.c, japanese.c (se compilan).
- `ADD_SUBDIRECTORY(TinyAngbandTk)` ya estaba en variant/CMakeLists.txt.
- Build de integracion (`docker/tinyangband-build.sh`) **configura OK**.
NOTA: el cableado de `TINYANGBANDTK` en la cola comun (`tnb.h` guard+bloque,
interp1/birth-tnb/struct/setting/sound/icon1, ~250 gates) **sobrevivio** al borrado
del intento previo (vive en src/common, compartido). Se conserva y se sigue el grind.

### TinyAngband Fase 2b EN CURSO (2026-05-30) — grind 248 -> 184
Primer build de integracion: **248 errores** (guard NO salta -> TINYANGBANDTK
reconocido). Son divergencias genuinas de TinyAngband (linaje XAngband 1.3.0) frente
a ZAngband, NO cascada falsa. Diagnostico (Tiny es variante PEQUEÑA):
- **Mutaciones**: Tiny tiene UN campo `u32b muta` con flags `MUT_*` (32); ZAngband
  usa `muta1/muta2/muta3` + `chaos_patron`. ~56 errores.
- **Razas**: Tiny tiene 9 (HUMAN..BARBARIAN), ZAngband ~34. El bridge referencia
  razas inexistentes (AMBERITE, ZOMBIE, VAMPIRE...). ~70 errores.
- **object_desc**: Tiny 3 args (buf,obj,mode); el bridge llama con 4 (estilo ZAngband).
- Otros: `O_NAME_MAX`/`maximize_mode` indefinidos, magia (min_lev/mana_cost/spell_book),
  TV_*_BOOK, TR3_INSTA_ART, leftbldg/energy/vir_types, feature_type.unused/extra.
Fixes aplicados (-> 184, todos via gate `#if (!)defined(TINYANGBANDTK)`):
- `tnb.h` bloque TINYANGBANDTK: `O_NAME_MAX 80`, `p_ptr_maximize`->`tnb_maximize`
  (Tiny solo tiene preserve_mode), adaptador `object_desc` 4->3 args (descarta pref).
- `variant/TinyAngbandTk/src/tiny-stubs.c` (NUEVO, espejo de tome-stubs.c):
  `tnb_point_based=0` (Tiny no tiene point-buy, solo autoroll), `tnb_maximize=1`.
- `birth-tnb.c`: `validate_bg()` no-op para Tiny (usa su propio switch race->chart en
  get_history; el race_chart hardcoded de ZAngband no aplica — mismo patron que TOMETK);
  race_chart hardcodeado quitado de TINYANGBANDTK.
- `interp1.c`: gateada la funcion `DumpMutations` + cases IDX_MUTATIONS/IDX_PATRON;
  neutralizada la contribucion `muta2` en `blows_per_round` (la funcion SI se usa en
  file_character.c, no se puede gatear entera).
PENDIENTE (184 -> 0, clusters claros):
- **Bloque de poderes raciales** interp1.c 2408-3083 (`power_desc[]` + switch por raza
  con todas las razas ZAngband + `muta1`): ~65 errores. Adaptar al set de Tiny o gatear
  (analizar callers primero).
- **Reflection struct.c**: player_type referencia muta1/2/3 -> adaptar a `muta` unico.
- **Magia**: `player_magic.spell_book`/min_lev/mana_cost (Tiny diverge en estructura magica).
- Long tail de constantes (TV_*_BOOK, TR3_INSTA_ART, leftbldg, energy->energy_need,
  vir_types, feature_type.unused/extra).
Tras 0 errores: link de angband.so (stubs en tiny-stubs.c para lo que la cola llame),
luego runtime (stagear Tiny+tk+lib, arrancar bajo VNC), como en ToME Fase 3.
Reproducir: `docker run --rm -v "$PWD:/work" -w /work omnibandtk-deps:bookworm bash
/work/docker/tinyangband-build.sh` (log build-tiny/build.log). Fase 0 standalone:
`docker/tinyangband-build0.sh`.

### TinyAngband Fase 2b COMPLETADA (2026-05-31) — angband.so compila Y enlaza ✅✅
**248 errores -> 0**, link OK, `build-tiny/variant/TinyAngbandTk/angband.so` = 3.8 MB
ELF aarch64. Equivale a la "Fase 2b COMPLETADA" de ToME. Todo via gates
`#if (!)defined(TINYANGBANDTK)` (Tiny = linaje XAngband, variante PEQUEÑA que
diverge de ZAngband). Resumen del grind (248->209->184->99->69->37->16->0):
- **tnb.h** bloque TINYANGBANDTK: O_NAME_MAX 80, p_ptr_maximize->tnb_maximize,
  adaptador object_desc 4->3 args, `birther`->`tnb_birther` (layout incompatible),
  TR3_INSTA_ART->TRG_INSTA_ART, magic_info->m_info, verify_mana->0.
- **tiny-stubs.c** (NUEVO): tnb_point_based=0, tnb_maximize=1.
- **birth-tnb.c**: validate_bg no-op (Tiny usa su switch race->chart propio);
  switch race->chart de get_history con las 9 razas de Tiny; chaos_patron/leftbldg/
  muta1-3 gateados; player_init (array a ceros) + player_outfit (cuerpo ZAngband)
  gateados -> sin gear inicial por ahora; quests Oberon/Serpent gateadas; RACE_BEASTMAN.
- **interp1.c**: DumpMutations/DumpVirtues + cases IDX_MUTATIONS/PATRON/VIRTUES gateados;
  blows_per_round sin muta; realm array y spellbook-range solo LIFE/SORCERY; spell_book
  switch -> rama Tiny por realm1; deadliness/owner_race/CLASS_RANGER; registro
  building/mindcraft/power gateado.
- **interp2.c**: objcmd_mindcraft gateado (Tiny sin mindcraft).
- **struct.c**: reflection de chaos_patron/muta1-3/energy/leftbldg/feature_type.extra
  gateada (Tiny usa energy_need; sin esos campos).
- **externs.h de Tiny**: gateadas decls que chocan con la cola comun (get_ahw/
  player_outfit/show_highclass/predict_score con otra firma).
- **Link (dobles definiciones engine vs comun)**: gateadas en el engine de Tiny con
  `#if !defined(TINYANGBANDTK)`: Term_fresh (z-term.c), player_birth (birth.c),
  show_highclass/race_score/race_legends (scores.c) -> las provee la cola comun.

### TinyAngband Fase 3a EN CURSO (2026-05-31) — dlopen: gaps de simbolos
Test dlopen (`dlopen(common.so, RTLD_GLOBAL)` + `dlopen(angband.so)`): common.so
carga OK; angband.so falla en `r_info_flags6`. **37 simbolos-gap** identificados
(undefined en angband.so, no en common.so, no X11/Tcl) = MISMO conjunto que ToME
resolvio en tome-stubs.c:
- Tablas de flags que Tiny declara `static` en init1.c (la cola comun las espera
  globales): r_info_flags1-9, r_info_flags, r_info_flags_max, r_info_blow_method,
  k_info_flags1-3. -> un-staticar en init1.c O stub vacio (ToME: r_info_flags[10]={0}).
- Funciones/datos common-side gateados-fuera: MonsterMemoryToArray, angtk_roff,
  angtk_savefile_info, keyword_term_color[17], cheat_info, get_virtues,
  object_desc_store, item_tester_hook_cast/study, macro_dump/delete, init_sound,
  sense_chance, spell_color, spell_info, store_cost, store_will_buy,
  target_set_location/monster, town_illuminate, highscore_read/seek.
PROXIMO: ampliar `tiny-stubs.c` (espejo de tome-stubs.c) con estos 37 + iterar
dlopen hasta 0; luego Fase 3b runtime (stagear Tiny+tk+lib, TINYANGBANDTK en
init-startup.tcl/birth.tcl/etc., arrancar bajo VNC en :5901). Multi-sesion, como ToME.

### TinyAngband Fase 3a COMPLETADA (2026-05-31) — angband.so hace dlopen limpio ✅✅✅
`dlopen(common.so, RTLD_GLOBAL)` + `dlopen(angband.so, RTLD_NOW|RTLD_GLOBAL)` ->
**ambos OK, TODOS los simbolos resuelven**. Equivale a la "Fase 3a COMPLETADA" de ToME.
Los 37 gaps resueltos en dos formas:
- **Des-staticadas en `variant/TinyAngbandTk/src/init1.c`** (datos reales de flags):
  r_info_flags1-9, k_info_flags1-3, r_info_blow_method/effect, k_info_gen_flags
  (quitado `static` -> globales que la cola comun ve via los extern de tnb.h).
- **Stubs en `variant/TinyAngbandTk/src/tiny-stubs.c`** (espejo de tome-stubs.c):
  agregador r_info_flags[10]={0}/r_info_flags_max=0, keyword_term_color[17],
  cheat_info[6], y funciones common-side no-op: MonsterMemoryToArray, angtk_roff,
  angtk_savefile_info, get_virtues, object_desc_store (-> object_desc 3-arg de Tiny),
  spell_info, spell_color, store_will_buy, store_cost, sense_chance, macro_dump,
  macro_delete, init_sound, highscore_read/seek, town_illuminate,
  target_set_location/monster, item_tester_hook_cast/study.
Test dlopen: `gcc dltest.c -ldl` (dlopen common.so luego angband.so);
LD_LIBRARY_PATH=build-tiny/src/{common-dll,dbwin,misc}.
PENDIENTE Fase 3b (runtime, multi-sesion como ToME 3b-3e): stagear Tiny+tk+lib;
anadir TINYANGBANDTK a los .tcl (init-startup, birth, charinfo-canvas, map,
config-map...); arrancar headless/VNC (:5901); depurar birth -> generate_cave ->
game loop. Los stubs no-op se iran cableando a la version real de Tiny segun bloqueen
(recall de monstruos, scores, cheats con o_var NULL, etc.).

### TinyAngband Fase 3b (2026-05-31) — ARRANCA CON GRAFICOS ✅✅✅
TinyAngbandTk **inicializa y muestra su GUI** en Linux/Docker headless: llega al
**dialogo de configuracion de tileset** (pestañas Icons/Music/Sound/Variant) con los
**tiles renderizandose** (rejilla de monstruos/objetos) y la lista de tilesets +
OK/Cancel. Titulo de ventana "ZAngbandTk 0.0.3r1". Mismo punto de init que AngbandTk.
Build en build-docker (`cmake --build build-docker --target tinyangband_library`),
luego `docker/run-game.sh TinyAngbandTk` (headless Xvfb) o con fluxbox para ver las
ventanas colocadas. Cadena de bloqueos depurada (cada fix revelaba el siguiente):
- **Variant string**: interp2.c IDX_VARIANT ya devolvia "ZANGBANDTK" para TINYANGBANDTK
  (ATAJO: tratar Tiny como ZAngband en la UI; valido porque comparten linaje/UI).
- **tk/**: TinyAngbandTk no tenia `tk/` -> copiado de ZAngbandTk (config/doc/image),
  igual que ToME. Sin esto no hay config de tiles.
- **"Cannot find required directory: ~/.angband/TinyAngband"**: Tiny define
  PRIVATE_USER_PATH (z-config.h, bajo SET_UID) -> ANGBAND_DIR_USER = ~/.angband/
  VERSION_NAME, pero init2.c no expande el '~' y el dir no se crea -> validate_dir
  aborta. FIX: gateado `#if defined(SET_UID) && !defined(TINYANGBANDTK)` en z-config.h
  -> Tiny usa lib/user (como las demas variantes Tk).
- **"version.txt file is bugged"**: el parser (init-startup.tcl ReadVariantVersionFile)
  exige formato `%d.%d.%dr%d` y que coincida con `angband game version` (FAKE_VER_*).
  FIX: `variant/TinyAngbandTk/version.txt` = "0.0.3r1" (FAKE_VER 0.0.3 + r1).
- **"unknown tval TV_NATURE_BOOK"**: el config Tk heredado de ZAngband referencia
  tvals de realms que Tiny no tiene (solo LIFE/SORCERY). FIX: `angtk_tval_const`
  (interp1.c) tolerante para TINYANGBANDTK -> tval 0 en vez de abortar.
PENDIENTE Fase 3c+ (multi-sesion, como ToME 3c-3e): click OK en el dialogo -> birth
(razas/clases de Tiny) -> roll -> generate_cave -> game loop -> dibujar mapa. Adaptar
los .tcl de birth si la UI ZAngband no cuadra con las 9 razas/6 clases/2 realms de Tiny;
cablear stubs no-op de tiny-stubs.c segun bloqueen.

### TinyAngband Fase 3c EN CURSO (2026-05-31) — birth fluye end-to-end
Auto-drive headless (`docker/debug-birth.sh TinyAngbandTk`, TNB_AUTONEW=1): el birth
recorre **AutoRoll -> RollOne (dice-roller) -> Accept -> `inkey() returned (birth
complete)`** y llega al post-birth (ventana `.load` de carga). Fixes para llegar:
- **"unknown setting point_based"** (birth.tcl rama ZANGBANDTK consulta opciones que
  Tiny no registra: point_based, maximize_mode): `objcmd_setting` (setting.c) tolerante
  para TINYANGBANDTK -> GET de setting desconocido devuelve 0, SET lo ignora.
- **"max_quest must be between 0 and 5"** (la UI envia 20): clamp en birth-tnb.c para
  TINYANGBANDTK al rango de Tiny en vez de abortar.
BLOQUEO ACTUAL (= ToME Fase 3c-3d, multi-sesion):
- **Hoja de personaje**: `NSCharInfoCanvas::SetInfo` linea 176 `expr {100 - $deadliness}`
  -> `$deadliness` vacio (campo de player_type que la reflection de Tiny no expone;
  Tiny hereda la UI ZAngband que lee campos que no tiene). Igual que ToME -> arreglar
  con `return` temprano en SetInfo para la variante O adaptar struct.c reflection.
- **Main window**: tras birth, esta la ventana `.load` pero NSMainWindow no se crea
  ("can't read Global(main,oop)", "invalid command NSMainWindow::Info"). ToME lo
  resolvio en Fase 3d llamando `angtk_character_generated()` desde dungeon.c (crea
  NSMainWindow + cierra .load). Probable mismo fix para Tiny (gatear TINYANGBANDTK en
  el sitio donde A/K/O/Z lo llaman).
PROXIMO (multi-sesion): (1) SetInfo char-sheet (reflection player_type de Tiny);
(2) crear NSMainWindow post-birth; (3) generate_cave -> game loop -> dibujar mapa
(get_grid_info CAVE_SEEN como ToME); (4) validar interactivo por VNC (:5901).

### TinyAngband Fase 3c cont. (2026-05-31) — char-sheet OK + main window EN CREACION
Dos fixes derribaron los 2 bloqueos anteriores:
- **char-sheet `$deadliness` vacio**: `tk/charinfo-canvas.tcl` NSCharInfoCanvas::SetInfo
  -> `if {$deadliness eq ""} {set deadliness 0}` (Tiny gateo fuera deadliness_conversion,
  no tiene la tabla). Tcl puro, sin recompilar.
- **NSMainWindow no se creaba**: el `dungeon.c` upstream de Tiny no llamaba al hook
  `angtk_character_generated()` (lo llaman A/K/O/Z). Añadido tras `character_icky=FALSE`
  (gateado TINYANGBANDTK) -> ahora **InitOther SI se invoca** (sourcing init-other.tcl).
NUEVO BLOQUEO (= ToME Fase 3d, cadena de display, multi-fix): InitOther aborta en
**"bad ascii \"85\": must be from 0 to 71"** (icon-dll.c) — el config de tiles heredado
de ZAngband referencia un indice de icono ascii (85) fuera del set de Tiny (72 entradas).
ToME lo resolvio en Fase 3d con ~6 fixes: clamp de indices en icon-dll.c
(Icon_GetIndexFromObj/validacion g_ascii_count), `config.tcl` forzar iconset "ascii",
flavor_init, config-map, 3 bugs de sonido (sound.c), map.tcl features sin mapear.
NOTA: icon-dll.c esta en common.so (compartido, 1 solo build) -> el clamp seria
incondicional (seguro: solo dispara en el caso fuera de rango). VNC vivo en :5901
(contenedor `omniband-tiny`) para validar cada paso interactivo.
LECCION: "Tiny" es pequeño en CONTENIDO (acelera la compilacion: pocas divergencias),
pero el runtime birth->display tiene la MISMA profundidad que cualquier Angband.

### TinyAngband Fase 3d (2026-05-31) — cadena de config de display DESPEJADA; crash C restante
Toda la cadena de ERRORES Tcl de InitOther resuelta (0 HandleError). Fixes:
- **icon-dll.c (common.so, clamp INCONDICIONAL)**: "bad ascii 85" y "bad ascii index 144"
  -> clampar indices de icono/ascii fuera del set de la variante (4 sitios de
  validacion g_ascii_count + el de Icon_FromObj) en vez de abortar. El config de tiles
  heredado de ZAngband referencia indices fuera del set de Tiny (72 ascii).
- **struct.c (angband.so, TINYANGBANDTK)**: `r_info find -flag` tolerante a flags
  desconocidos (CHAR_CLEAR/ATTR_CLEAR; r_info_flags_max=0 en stubs -> todo flag es
  "desconocido") -> ignorar en vez de abortar (anadido TINYANGBANDTK a los gates TOMETK).
- **tk/config/ascii-common**: `r_info find -name "Space monster"` (rama ZANGBANDTK)
  devuelve "" en Tiny -> guardar `if {$r_idx ne ""}` antes de `assign set monster`.
- **struct.c reflection**: object_kind.flavor es `s16b` en Tiny (no byte) -> FLD_INT16
  para TINYANGBANDTK (quita el WARNING size=1!=fLength=2; corrupcion potencial).
ESTADO: InitOther ya NO da errores Tcl, pero el proceso MUERE (alive=0, sin HandleError)
mientras carga los tiles dg32 / crea NSMainWindow -> **crash a nivel C** (= ToME Fase 3d:
"corrupcion de la reflection de player_type / config de tiles"). Pantalla en negro tras
cerrar el config dialog (birth corrio, main window no aparece).
PROXIMO (necesita gdb, multi-sesion como ToME 3d-3e):
- `docker/gdb-birth.sh` tiene `VARIANT=ToMETk` HARDCODEADO (linea 6) -> adaptarlo para
  tomar el arg, y sacar backtrace del crash de Tiny.
- Opcion ToME (de-riesgar): `config.tcl` forzar iconset "ascii" para evitar cargar
  imagenes de tiles (cuyo config corrompe memoria) -- pero Tiny reporta ZANGBANDTK, hay
  que detectarlo (no `[variant TOMETK]`).
- Adaptar struct.c reflection de player_type para Tiny (sizes/offsets reales) -- la
  causa de fondo del crash, como en ToME.
