# Receta general: portar una variante de Angband a OmnibandTk

> Documento variant-agnóstico, derivado de **comparar las 6 variantes** del
> repo contra sus fuentes upstream (`origsrc/`). Confirma la hipótesis: **la
> forma de portar es, a grandes rasgos, la misma para todas**. El caso
> trabajado en detalle está en [KAngbandTk/PORTING-DIFF.md](../variant/KAngbandTk/PORTING-DIFF.md);
> aquí está la versión reutilizable + el estado de cada variante.
>
> Metodología y trampas (marcas `/* TNB */`, CRLF ×12, deriva de versión):
> ver §0 del doc de KAngbandTk. No se repiten aquí.

---

## 1. La evidencia: el patrón es el mismo en las 4 variantes terminadas

Barrido sobre `variant/*/src` (Vía 1, marcas TNB):

| Variante | marcas TNB | ficheros con `tnb.h` | `angtk_eval()` | `main-*.c` que quedan | flags |
|---|---:|---:|---:|---:|---:|
| AngbandTk | 1079 | 25 | 88 | 0 | 55 |
| KAngbandTk | 1251 | 28 | 132 | 0 | 55 |
| OAngbandTk | 1217 | 27 | 89 | 0 | 57 |
| ZAngbandTk | 1715 | 39 | 144 | 0 | 64 |
| **ToMETk** | 69 | 0 | 0 | **20** | 97 |
| **TinyAngbandTk** | 0 | 0 | 0 | 0 | 0 |

Las 4 primeras siguen el **mismo molde** (cientos de marcas TNB, `tnb.h`
incluido en decenas de ficheros, `main-*.c` eliminados). Las dos últimas son
**ports en curso** (ver §4). El nº de marcas escala con el tamaño de la
variant (ZAngband, la más grande, tiene más).

---

## 2. Hallazgo clave: el puente NO se reescribe por variante

Toda la "cola común" del port vive en **`src/common`** y la comparten **todas**
las variantes:

```
main-tnb.c   birth-tnb.c   util-tnb.c      ← glue que sustituye a los main-*.c
interp1.c interp2.c bind.c                 ← intérprete Tcl + binding de teclado
icon1.c icon2.c canv-widget.c treectrl.c   ← canvas/tiles/widgets Tk
map.c tkterm.c widget.c widget-iso.c       ← mapa y Term sobre canvas
setting.c sound.c struct.c describe.c …
```

Implicación práctica enorme: **portar una variante NO es escribir un backend
Tk**. El backend ya existe en `src/common`. Portar = **adaptar el motor de la
variante para que lo consuma**. El trabajo por variante es casi todo
*sustracción y redirección*, no código nuevo de UI.

---

## 3. La receta (idéntica para todas)

1. **Eliminar los `main-*.c`** y `main.c` del upstream (drivers de pantalla por
   plataforma). Los reemplaza `src/common/main-tnb.c`. En las 4 terminadas
   quedan **0**; en ToMETk siguen los **20** → ahí está el trabajo pendiente.
2. **Incluir `tnb.h`** (de `src/common`) en cada `.c` que hable con el UI.
3. **Redirigir el render del mapa**: `Term_putch`/`lite_spot`/`prt` →
   `angtk_lite_spot()`, `angtk_cave_changed()`, `angtk_view_floor/wall()`.
   El motor pasa de "pintar caracteres" a "notificar que la celda cambió".
4. **Sustituir pantallas modales** (hechizos, tiendas, info de objeto/monstruo,
   pantalla de personaje) por `angtk_eval("angband_display", …)` y
   `angtk_display_info_*()`. Patrón: el vanilla hacía
   `screen_save → print_* → screen_load`; el port hace `angtk_eval(… "show"/"hide" …)`.
5. **Inyectar contexto de teclado** con `Bind_Choose(KEYWORD_*, …)` antes de
   los `get_com`/`inkey` dependientes de estado.
6. **Enganchar efectos visuales**: `project()`/disparos →
   `angtk_effect_spell/ammo/object()`, `angtk_detect_radius()`, …
7. **Activar feature-flags** (`ALLOW_*`/`USE_*`) en `config.h`/`defines.h`.
8. **Hooks de sonido** bajo `#ifdef ALLOW_SOUND`.
9. **Eventos de ciclo de vida**: `angtk_angband_initialized()`,
   `angtk_character_generated()`, `angtk_flavor_init()`.

Conserva el estilo `#if 1 /* TNB */ … #else … #endif` (Baker) o un guard propio
(en ToMETk el usuario usa `#if !defined(TOMETK)`) para **no borrar** el vanilla.
Es lo que hace este análisis posible.

---

## 4. Cabos sueltos por variante

### El cabo suelto universal: los DATOS (`lib/edit/*.txt`)
Monstruos, objetos, etc. **No** llevan marcas TNB en general → solo se
documentan por **Vía 2** (diff upstream normalizado). Estado:

| Variante | `.txt` en lib/edit | ¿TNB en los .txt? | upstream en origsrc |
|---|---:|---|---|
| AngbandTk | 11 | no | ✅ angband-2.9.2 |
| KAngbandTk | 175 | no | ✅ kangband-292r2 / final |
| OAngbandTk | 11 | **sí (24)** ⚠️ | ✅ Oangband_051 |
| ZAngbandTk | 52 | no | ✅ ZAngband |
| ToMETk | 38 | no | (../TomeTik, fuera del repo) |
| TinyAngbandTk | **0** | — | (pendiente de traer) |

⚠️ **Excepción OAngband**: Baker sí anotó cambios de datos con `-- TNB` en los
comentarios `#` (ej. `a_info.txt`: `# W:85:1:50:35000 Use unused k_info[] chance -- TNB`).
Así que en OAngband incluso los datos son documentables por Vía 1. No asumas
que "datos = siempre sin marca"; depende de la variante.

### ToMETk — port EN CURSO (no de Baker, tuyo)
- 20 `main-*.c` todavía presentes (incluye modernos: `main-sdl`, `main-gtk2`,
  `main-crb`, `main-iso`) → falta el paso 1.
- 0 `#include "tnb.h"`, 0 `angtk_eval` → falta cablear el puente.
- Las 69 marcas "TNB" son **tus propias anotaciones de port en curso**:
  `#if !defined(TOMETK) /* TNB: la provee main-tnb.c (Omniband) */`,
  guards en `z-term.c`/`birth.c`, y `src/tome-stubs.c` (stubs ToME↔Omniband).
  → **Ya estás aplicando esta misma receta**, con guard `TOMETK` en vez de
  `#if 0 /* TNB */`. El doc te sirve de checklist de lo que falta (pasos 1-9).

### TinyAngbandTk — greenfield
- 0 marcas, 0 `tnb.h`, **0 datos** en lib/edit, sin capa Tk.
- Coincide con la nota de proyecto: Fase 0 = el motor compila standalone.
- Para esta variante el doc no es arqueología sino **hoja de ruta**: aplica los
  9 pasos de cero, apoyándote en que 53/65 `.c` ya coinciden con ZAngbandTk
  (→ puedes copiar gran parte de las redirecciones ya hechas en ZAngbandTk).

---

## 5. Conclusión

Sí: el método de portado es **el mismo a grandes rasgos para todas**, y el
documento de KAngbandTk generaliza. Las diferencias entre variantes son de
**grado** (tamaño → nº de marcas) y de **detalle de contenido** (OAngband anota
datos; KAngband tiene muchos más `.txt`), no de **método**. El verdadero
trabajo por variante es redirigir el motor al puente común de `src/common`,
no construir UI.
