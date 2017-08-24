#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
# Time-stamp: "2006-09-03 19:01:30" \
exec wish $0 ${1+"$@"}

##+##########################################################################
#
# newLogo.tcl -- <description>
# by Keith Vetter
#
# Revisions:
# KPV Apr 29, 2010 - initial revision
#
##+##########################################################################
#############################################################################

package require Tk

proc shadedtext3 {w x y fg bg args} {

    set cbg [ $w cget -bg ]

    $w create text $x $y -fill $bg {*}$args -tag a1
    $w create text [incr x -2] [incr y -2] -fill $cbg {*}$args -tag a2
    $w create text [incr x -1] [incr y -1] -fill  $fg {*}$args -tag a3
}
proc 3dText {w x y fg bg steps dx dy args} {

    incr x [expr {-$dx * $steps}]
    incr y [expr {-$dy * $steps}]
    for {set i 1} {$i < $steps} {incr i} {
	$w create text $x $y -fill $bg {*}$args
	incr x $dx
	incr y $dy
    }
    $w create text $x $y -fill $fg {*}$args
}
proc bbox {tag} {
    lassign [.c bbox $tag] x0 y0 x1 y1
    set width [expr {$x1-$x0}]
    set height [expr {$y1-$y0}]
    return [list $width $height]
}
canvas .c -width 700 -height 200 -bg white -bd 0 -highlightthickness 0
pack .c -fill both -expand 1

image create photo ::img::left -file biker.gif
image create photo ::img::right -file biker_r.gif

.c create image 0 0 -image ::img::left -anchor nw
.c create image 700 0 -image ::img::right -anchor ne

3dText .c 350 -15 red black 5 -1 -1 -text KLIMB -font {Times 96 bold} -anchor n -tag a
set txt "Keith's deLuxe Interactive Map Builder"
3dText .c 350 130 red black 2 -1 -1 -text $txt -font {Times 30 bold} -anchor n -tag b