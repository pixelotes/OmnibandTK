# tclzip-shim.tcl
#
# Reemplazo en Tcl puro de la extensión nativa TclZip de Tim Baker (tclzip.dll,
# basada en minizip) para plataformas donde no tenemos ese .dll/.so. Replica el
# comando `zip` y el API de handle que usan tomb.tcl / record.tcl:
#
#   set h [zip zipCmd]            ;# crea un handle (comando); el arg es libre
#   $h add <srcFile> <nameInZip> ;# añade un fichero al archivo (modo escritura)
#   $h write <archive>           ;# escribe el .zip
#   $h read <archive>            ;# abre un .zip existente (modo lectura)
#   $h glob                      ;# lista las entradas
#   $h extract <entry> <file>    ;# extrae una entrada a un fichero
#   $h extract -tomemory <entry> ;# devuelve el contenido de una entrada
#   rename $h ""                 ;# destruye el handle
#
# Implementado sobre las utilidades `zip`/`unzip` del sistema. Binario-seguro
# mediante redirección de exec (sin traducción de fin de línea).

package provide TclZip 1.0

namespace eval ::tclzipshim {
    variable counter 0
    variable state   ;# array: $h,adds  $h,archive
}

# `zip <subcmd>` -> crea y devuelve un nuevo comando-handle.
proc zip {args} {
    set h ::tclzipshim::h[incr ::tclzipshim::counter]
    set ::tclzipshim::state($h,adds) {}
    set ::tclzipshim::state($h,archive) ""
    proc $h {method args} "::tclzipshim::Dispatch $h \$method {*}\$args"
    return $h
}

proc ::tclzipshim::Dispatch {h method args} {
    variable state
    switch -exact -- $method {
        add {
            # add <srcFile> <nameInZip>
            lassign $args src name
            lappend state($h,adds) [list $src $name]
            return
        }
        write {
            # write <archive>. Los nombres en el zip son planos (score.txt,
            # dump.txt, photo.gif, ...), así que copiamos a un temp con ese nombre
            # y usamos `zip -j` (junk paths) para almacenarlos por su basename.
            set archive [file normalize [lindex $args 0]]
            file delete -force -- $archive
            set tmp [file join [TmpDir] zipstage[pid]_[incr ::tclzipshim::counter]]
            file mkdir $tmp
            set staged {}
            foreach pair $state($h,adds) {
                lassign $pair src name
                set dst [file join $tmp $name]
                file copy -force -- $src $dst
                lappend staged $dst
            }
            if {[llength $staged]} {
                exec zip -j -q -X $archive {*}$staged
            }
            file delete -force -- $tmp
            return
        }
        read {
            # read <archive>
            set state($h,archive) [file normalize [lindex $args 0]]
            return
        }
        glob {
            # lista de nombres de entrada
            set out [exec unzip -Z1 -- $state($h,archive)]
            return [split [string trim $out] \n]
        }
        extract {
            if {[lindex $args 0] eq "-tomemory"} {
                # extract -tomemory <entry> -> contenido
                set entry [lindex $args 1]
                return [exec unzip -p -- $state($h,archive) $entry]
            }
            # extract <entry> <file>
            lassign $args entry file
            exec unzip -p -- $state($h,archive) $entry > $file
            return
        }
        default {
            error "unknown zip method \"$method\""
        }
    }
}

proc ::tclzipshim::TmpDir {} {
    foreach v {TMPDIR TEMP TMP} {
        if {[info exists ::env($v)] && [file isdirectory $::env($v)]} {
            return $::env($v)
        }
    }
    return /tmp
}
