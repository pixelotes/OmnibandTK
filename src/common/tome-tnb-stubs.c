/*
 * tome-tnb-stubs.c — Stubs de enlace para el port ToME 2.2.2 -> Omniband (TOMETK).
 *
 * ToME carece de varias funciones/datos que la cola Tk (linaje ZAngband) espera
 * del engine, o los implementa con otro modelo (magia por skills, savefile e
 * iluminación propios, etc.). Estos stubs permiten que variant/ToMETk/angband.so
 * cargue sin "undefined symbol".
 *
 * TODO (fase runtime): sustituir cada stub por un adaptador real a la API
 * equivalente de ToME. Mientras tanto devuelven valores neutros / no-op.
 */

#include <tcl.h>
#include "angband.h"
#include "tnb.h"

#if defined(TOMETK)

/* --- Opción de la cola (en ZAngband es un bool global). --- */
bool easy_floor = TRUE;

/* --- Tabla de nombres de color de term (16 colores base + NULL).
 * Deben coincidir con los nombres "TERM_XXX" que registra el Value manager
 * (value-manager.tcl, "Manage TERM_DARK ...") porque la message-window lee
 * "Value $attr" usando estos nombres ("angband info term_attr"). El resto de
 * variantes (p.ej. ZAngband flavor.c) usan STRINGIFY2(TERM_DARK) -> "TERM_DARK". */
cptr keyword_term_color[] = {
	"TERM_DARK", "TERM_WHITE", "TERM_SLATE", "TERM_ORANGE",
	"TERM_RED", "TERM_GREEN", "TERM_BLUE", "TERM_UMBER",
	"TERM_L_DARK", "TERM_L_WHITE", "TERM_VIOLET", "TERM_YELLOW",
	"TERM_L_RED", "TERM_L_GREEN", "TERM_L_BLUE", "TERM_L_UMBER", NULL
};

/* --- Funciones de engine ausentes en ToME (valores neutros / no-op). --- */
bool sense_chance(int *mage, int *warrior)
{ if (mage) *mage = 0; if (warrior) *warrior = 0; return FALSE; }
char *store_cost(object_type *o_ptr) { (void) o_ptr; return (char *) ""; }
bool store_will_buy(const object_type *o_ptr) { (void) o_ptr; return FALSE; }
void town_illuminate(bool daytime) { (void) daytime; }
void update_lite(void) {}
void forget_lite(void) {}
void target_set_monster(int m_idx) { (void) m_idx; }
void target_set_location(int y, int x) { (void) y; (void) x; }
bool item_tester_hook_cast(object_type *o_ptr) { (void) o_ptr; return FALSE; }
bool item_tester_hook_study(object_type *o_ptr) { (void) o_ptr; return FALSE; }

/* --- Helpers de creación que la cola llama (ToME los tiene static en birth.c). --- */
void get_ahw(void) {}
void get_extra(void) {}

/* --- Sonido (init propio de ToME en su front-end, no en la cola). --- */
void init_sound(void) {}

/* --- Keymaps/macros (ToME los maneja en cmd4.c, no expuestos a la cola). --- */
errr keymap_dump(cptr fname) { (void) fname; return -1; }
errr macro_dump(cptr fname) { (void) fname; return -1; }
void macro_delete(int n) { (void) n; }

/* --- High score (ToME los tiene static en files.c con otro formato). --- */
errr highscore_read(high_score *score) { (void) score; return -1; }
int highscore_seek(int i) { (void) i; return -1; }

/* --- Info de savefile para la pantalla de carga (ToME tiene su propio formato). --- */
errr angtk_savefile_info(char *filename, char *varName)
{ (void) filename; (void) varName; return -1; }

/* --- Tcl command handlers que dependen del modelo mágico/objetos de ZAngband. --- */
int objcmd_spell(ClientData clientData, Tcl_Interp *interp, int objc,
	Tcl_Obj *CONST objv[])
{ (void) clientData; (void) objc; (void) objv;
  Tcl_SetResult(interp, (char *) "", TCL_STATIC); return TCL_OK; }
int objcmd_floor(ClientData clientData, Tcl_Interp *interp, int objc,
	Tcl_Obj *CONST objv[])
{ (void) clientData; (void) objc; (void) objv;
  Tcl_SetResult(interp, (char *) "", TCL_STATIC); return TCL_OK; }

#endif /* TOMETK */
