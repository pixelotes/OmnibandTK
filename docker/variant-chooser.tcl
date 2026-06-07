# OmnibandTk - module/variant chooser (shown before the game starts).
#
# Runs under wish (the Tcl/Tk 8.6 already built into the image, no new frameworks
# installed) INSIDE the VNC display. Receives as argv the list of available
# variants (those with a compiled angband.so). Shows one button per variant; on
# click it prints the chosen name to stdout and exits. Closing the window without
# choosing exits with code 1 and prints nothing.

package require Tk

# Readable name + short description per variant (key = variant dir).
array set INFO {
    AngbandTk   {"Angband"   "Tolkien's classic roguelike (2.9.2 base)"}
    KAngbandTk  {"Kangband"  "Variant with more races, classes and monsters"}
    OAngbandTk  {"Oangband"  "Redesigned classes and combat system"}
    ZAngbandTk  {"ZAngband"  "Zelazny's world: towns, quests and magic"}
}

proc pick {v} { puts $v; flush stdout; exit 0 }

wm title . "OmnibandTk - Choose module"
. configure -bg "#1e1e2e"

label .t -text "OmnibandTk" -font {Helvetica 28 bold} -fg "#cdd6f4" -bg "#1e1e2e"
label .s -text "Choose the module you want to play" -font {Helvetica 13} \
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

label .q -text "(close this window to cancel)" -font {Helvetica 9} \
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
