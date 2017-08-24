# Trampoline - pkgIndex.tcl
# $Revision: 1.1.1.1 $
# $Date: 2004/11/21 23:20:41 $
if {![regexp {^(8[.][4-9]([.][0-9])?)} [info patchlevel] junk plevel]} {return}
if {![package vsatisfies $plevel 8.4.0]} {return}
package ifneeded trampoline 0.5.3 [list source [file join $dir pdfgen.tcl]]
