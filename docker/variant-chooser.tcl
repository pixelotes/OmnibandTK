# OmnibandTk — selector de módulo/variante (pantalla previa al juego).
#
# Se ejecuta con wish (el Tcl/Tk 8.6 ya compilado en la imagen, sin instalar
# frameworks nuevos) DENTRO del display VNC. Recibe como argv la lista de
# variantes disponibles (las que tienen angband.so compilado). Muestra un botón
# por variante; al pulsar, imprime el nombre elegido por stdout y sale. Si se
# cierra la ventana sin elegir, sale con código 1 y sin imprimir nada.

package require Tk

# Nombre legible + descripción corta por variante (clave = dir de la variante).
array set INFO {
    AngbandTk   {"Angband"   "El roguelike clásico de Tolkien (base 2.9.2)"}
    KAngbandTk  {"Kangband"  "Variante con más razas, clases y monstruos"}
    OAngbandTk  {"Oangband"  "Rediseño de clases y sistema de combate"}
    ZAngbandTk  {"ZAngband"  "Mundo de Zelazny: pueblos, misiones y magia"}
}

proc pick {v} { puts $v; flush stdout; exit 0 }

wm title . "OmnibandTk — Elige módulo"
. configure -bg "#1e1e2e"

label .t -text "OmnibandTk" -font {Helvetica 28 bold} -fg "#cdd6f4" -bg "#1e1e2e"
label .s -text "Elige el módulo que quieres jugar" -font {Helvetica 13} \
    -fg "#a6adc8" -bg "#1e1e2e"
pack .t -pady {24 2} -padx 40
pack .s -pady {0 18} -padx 40

set i 0
foreach v $argv {
    if {[info exists INFO($v)]} {
        lassign $INFO($v) name desc
    } else {
        set name $v ; set desc ""
    }
    set f .f$i
    frame $f -bg "#1e1e2e"
    button $f.b -text $name -font {Helvetica 15 bold} -width 12 \
        -bg "#89b4fa" -fg "#1e1e2e" -activebackground "#b4befe" \
        -activeforeground "#1e1e2e" -relief flat -padx 12 -pady 10 \
        -command [list pick $v]
    label $f.d -text $desc -font {Helvetica 11} -fg "#a6adc8" -bg "#1e1e2e" \
        -anchor w -justify left
    pack $f.b -side left -padx {0 16}
    pack $f.d -side left -fill x -expand 1
    pack $f -pady 6 -padx 40 -fill x
    incr i
}

label .q -text "(cierra esta ventana para cancelar)" -font {Helvetica 9} \
    -fg "#6c7086" -bg "#1e1e2e"
pack .q -pady {18 20}

# Cerrar la ventana sin elegir => cancelar (sin imprimir nada).
wm protocol . WM_DELETE_WINDOW { exit 1 }

# Centrar la ventana en pantalla.
update idletasks
set w [winfo reqwidth .]
set h [winfo reqheight .]
set x [expr {([winfo screenwidth .]  - $w) / 2}]
set y [expr {([winfo screenheight .] - $h) / 2}]
wm geometry . +$x+$y

raise .
focus -force .
