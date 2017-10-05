#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
exec tclsh $0 ${1+"$@"}

##+##########################################################################
#
# MakeRegions -- carves out regions from a KLIMB zone
# by Keith Vetter
#
# Revisions:
# KPV May 07, 2004 - initial revision
#
##+##########################################################################
#############################################################################

package provide app-makeregions 1.0
package require Tk
package require img::jpeg
source packages/maps.tsh
catch {package require pgu 1.0}
if {[catch {package present pgu}]} {
    if {[file exists packages/pgu.tcl]} {
	source packages/pgu.tcl
    } else {
	wm withdraw .
	set msg "ERROR: Cannot locate the PGU package for KLIMB.\n\n"
	append msg "Download and place in the KLIMB directory:\n"
	append msg "http://www.klimb.org/binaries/pgu.tcl\n\n"
	tk_messageBox -icon error -message $msg -title "KLIMB MakeRegions"
	exit
    }
}

namespace eval ::Zone {}

set state(progname) "KLIMB MakeRegion"
set state(kdir) ""
set state(hdir) ""
set state(tcnt) 0
set state(nofetch) 0				;# For debugging
set state(nocache) 0				;# For debugging
set state(nocache) 1				;# For debugging

unset -nocomplain C
array set C {regionName "" regionFile ".klr" nodeFile "klimb.nodes"}
array set C {scale 16 theme "Google Terrain"}
array set C {lat,0 "" lon,0 "" lat,1 "" lon,1 "" tile,0 {} tile,1 {}}

proc DoDisplay {} {
    global state zone coords

    font create boldFont -family Helvetica -size 10 -weight bold
    font create bigBoldFont -family Helvetica -size 18 -weight bold
    label .l
    eval font create smallBoldFont "[font actual [.l cget -font]] -weight bold"
    destroy .l
    option add *Labelframe.font boldFont
    option add *Button.font boldFont

    wm title . "KLIMB Make Region"
    wm geom . +20+20
    frame .right -bd 2 -relief ridge
    frame .left -bd 2 -relief ridge
    #grid .left .right -sticky news
    pack .right -side right -fill both
    pack .left -side left -fill both -expand 1

    set w [expr {$coords(iw) > 1000 ? 1000 : $coords(iw)}]
    set h [expr {$coords(ih) > 850 ? 850 : $coords(ih)}]

    label .title -textvariable zone(name,pretty) -font {Times 24}
    scrollbar .vsb -orient vertical -command [list .c yview]
    scrollbar .hsb -orient horizontal -command [list .c xview]
    canvas .c -width $w -height $h \
	-highlightthickness 0 -yscrollcommand [list .vsb set] \
	-xscrollcommand [list .hsb set]
    grid .title - -in .left -sticky news
    grid .c .vsb -in .left -sticky ns
    grid configure .c -sticky news
    grid .hsb -in .left -sticky ew
    grid rowconfigure .left 1 -weight 1
    grid columnconfigure .left 0 -weight 1

    # Region frame
    set W .region
    labelframe $W -text "Region Info"
    #$W configure  -font "[font actual [$W cget -font]] -weight bold"
    catch {$W configure -font boldFont}
    #option add *Labelframe.font [$W cget -font]
    #option add *Button.font [$W cget -font]

    label $W.rname -text "Region name:"
    entry $W.ername -textvariable C(regionName)
    menubutton $W.m -image ::img::star -relief raised -menu $W.m.menu
    menu $W.m.menu -tearoff 0 -postcommand [list MenuPostCmd $W.m.menu]
    label $W.rfile -text "Region File:"
    entry $W.erfile -textvariable C(regionFile)
    label $W.nfile -text "Node File:"
    entry $W.enfile -textvariable C(nodeFile)

    grid $W.rname $W.ername $W.m -sticky nsw
    grid $W.rfile $W.erfile -sticky w
    grid $W.nfile $W.enfile -sticky w
    grid columnconfigure $W 100 -weight 1

    # Map frame
    labelframe .map -text "Map Info"
    catch {.map config -bd 2 -relief ridge}
    frame .fscale
    frame .ftheme
    label .tscale -text "Scale"
    # spinbox .scale -width 3 -from 11 -to 19 -textvariable C(scale)
    label .ttheme -text "Theme"
    # spinbox .theme -width 7 -textvariable C(theme) -values {Topo Aerial} \
        #     -wrap 1 -justify center
    ::Klippy::FetchAndZoomOptionMenu .theme C(theme) {} .scale C(scale) NewZoom
    .theme config -width 12
    grid .fscale .ftheme -in .map
    grid .tscale .scale -in .fscale
    grid .ttheme .theme -in .ftheme
    grid columnconfigure .map {0 1} -weight 1

    # Waypoint
    labelframe .waypoint -text "Markers"
    catch {.waypoint config -bd 2 -relief ridge }
    button .waypoint.add -text "New Marker" -command WaypointDialog
    pack .waypoint.add -pady {0 5} -expand 1

    # Coordinate frame
    labelframe .latlon -text "Region Extents"
    catch { .latlon config -bd 2 -relief ridge -padx 5}
    label .tlat -text Latitude
    label .tlon -text Longitude
    label .topleft -text "Top left"
    option add *Entry.disabledForeground black
    #option add *Entry.disabledBackground white
    entry .elat0 -textvariable C(plat,tl) -width 14 -state disabled
    entry .elon0 -textvariable C(plon,tl) -width 14 -state disabled
    label .bottomright -text "Bottom right"
    entry .elat1 -textvariable C(plat,br) -width 14 -state disabled
    entry .elon1 -textvariable C(plon,br) -width 14 -state disabled
    label .lcnt -text "Size:"
    label .lcnt2 -textvariable state(cells)
    label .lpixels -textvariable state(pixels)
    label .lsize2 -textvariable state(size)

    grid x .tlat .tlon -in .latlon
    grid .topleft .elat0 .elon0 -in .latlon -sticky ew
    grid .bottomright .elat1 .elon1 -in .latlon -sticky ew -pady {0 5}
    grid .lcnt .lcnt2 -in .latlon
    grid x .lpixels -in .latlon
    grid x .lsize2 -in .latlon
    grid columnconfigure .latlon {1 2} -weight 1

    set htxt "Left click to set top left corner\n"
    append htxt "Right click to set other corner"
    label .help -text $htxt -font boldFont

    # Make Region frame
    frame .fmregion -bd 2 -relief sunken
    button .mregion -text "Make Region" -command MakeRegion -state disabled

    grid .region -in .right -ipadx 5 -ipady 5 -sticky news -pady 5
    grid .map -in .right -ipadx 5 -ipady 5 -sticky news -pady 5
    grid .waypoint -in .right -ipadx 5 -ipady 5 -sticky news -pady 5
    grid .latlon -in .right -ipadx 5 -sticky news -pady 5
    grid .help -in .right -row 50 -sticky ew -pady 20
    grid .fmregion -in .right -pady 20 -row 101
    pack .mregion -in .fmregion -padx 15 -pady 15
    grid rowconfigure .right 100 -weight 1

    .c create image 0 0 -image ::img::zone -anchor nw -tag zone
    .c config -scrollregion [.c bbox all]
    .c create rect -100 -100 -100 -100 -tag region -fill red -outline red \
	-width 3 -stipple gray25
    .c itemconfig region -stipple {} -fill {} -width 2
    .c bind all <Button-1> [list BClick 0 %x %y]
    .c bind all <B1-Motion> [list BClick 0 %x %y]
    .c bind all <Button-3> [list BClick 1 %x %y]
    .c bind all <B3-Motion> [list BClick 1 %x %y]
    .c bind all <Control-Button-1> [list BCtrlClick %x %y]
    bind .c <2>		 [bind Text <2>]	 ;# Enable dragging w/ <2>
    bind .c <B2-Motion>	 [bind Text <B2-Motion>]
    bind all <Key-F2> {console show}

    focus .region.rname
    wm deiconify .
}
image create bitmap ::img::star -data {
    #define plus_width	11
    #define plus_height 9
    static char plus_bits[] = {
	0x00,0x00, 0x24,0x01, 0xa8,0x00, 0x70,0x00, 0xfc,0x01,
	0x70,0x00, 0xa8,0x00, 0x24,0x01, 0x00,0x00 }
}
proc Lon2World {{lonVar lon}} {
    upvar 1 $lonVar lon
    set lon [expr {-abs($lon)}]
}
proc Lon2Klimb {{lonVar lon}} {
    upvar 1 $lonVar lon
    set lon [expr {abs($lon)}]
}
proc ZoneInit {} {
    global state coords zone

    set state(mapdir) [file join $state(zone,dir) Maps]
    set state(wptFile) [file join $state(zone,dir) waypoints.tcl]
    ::Zone::ReadZoneFile [file join $state(zone,dir) zone.data]
    set zone(name,pretty) "$zone(name) Zone"

    set iname [file join $state(zone,dir) $zone(makezone,map)]
    if {! [file exists $iname]} {
	DIE "No zone map"
    }
    image create photo ::img::zone -file $iname

    set coords(iw) [image width ::img::zone]
    set coords(ih) [image height ::img::zone]

    foreach who {top left bottom right} {a b c} $zone(makezone,coords) {
        set coords($who) [lat2int $a $b $c]
    }
    set coords(dx) [expr {$coords(right) - $coords(left)}]
    set coords(dy) [expr {$coords(bottom) - $coords(top)}]

}
##+##########################################################################
#
# FindZones -- finds all KLIMB zones, these are directories
# with the name <zonename>.zone in which resides a "zone.data" file.
#
proc FindZones {} {
    global zone state

    set state(zone,names) {}
    set znames [concat [glob -nocomplain [file join $state(kdir) *.zone]] \
		    [glob -nocomplain [file join $state(hdir) *.zone]]]

    foreach dir $znames {
	set zname [file join $dir zone.data]
	if {! [file isfile $zname]} continue

	set name [GetZoneName $zname]
	if {[lsearch $state(zone,names) $name] == -1} {
	    lappend state(zone,names) $name
	    set state(zone,$name,zdir) [file dirname $zname]
	}
    }
    set state(zone,names) [lsort -dictionary $state(zone,names)]
    set state(zone,lnames) {}
    foreach name $state(zone,names) {
	lappend state(zone,lnames) [string tolower $name]
    }
    if {[llength $state(zone,names)] > 0} return

    wm withdraw .
    set msg "$state(progname) could not find any zone information.\n\n"
    append msg "You must run this program from the KLIMB directory\n"
    append msg "which is typically at c:\\Program Files\\Klimb."
    DIE $msg
}
##+##########################################################################
#
# GetZoneName -- dig zone name out of zone.data file
#
proc GetZoneName {zname} {
    set FIN [open $zname r]			;# Slurp up the zone.data file
    set data [read $FIN]
    close $FIN

    set name [file rootname [file tail [file dirname $zname]]] ;# Default value
    regexp -line ^name=(.*)$ $data => name	;# Overridden in zone.data

    return $name
}
proc TryZone {try} {
    global state

    if {$try eq ""} { return "" }
    set try [string tolower $try]
    set who [lsearch -exact $state(zone,lnames) $try]
    if {$who ne -1} { return [lindex $state(zone,names) $who] }
    set who [lsearch -all -glob $state(zone,lnames) "$try*"]
    if {[llength $who] == 1} { return [lindex $state(zone,names) $who] }
    return ""
}

proc PickZone {{try ""}} {
    global state

    set try [TryZone $try]
    if {$try ne ""} {
	set state(zone,dir) $state(zone,$try,zdir)
	return
    }

    wm withdraw .
    destroy .z
    toplevel .z
    wm protocol .z WM_DELETE_WINDOW exit
    wm title .z $state(progname)
    wm geom .z +[expr {[winfo screenwidth .z]/2 - 150}]+200

    grid [frame .z.f -width 300] - - -row 0	;# For sizing only

    label .z.t -text "Pick Zone" -bd 5 -relief ridge
    #.z.t configure -font "[font actual [.z.t cget -font]] -weight bold -size 18"
    .z.t configure -font bigBoldFont
    grid .z.t - - -sticky ew

    set idx -1
    foreach z $state(zone,names) {
	set w ".z.[incr idx]"
	radiobutton $w -text $z -variable ::state(zone) -value $z \
	    -command {.z.go config -state normal}
	grid x $w -sticky w
    }
    set state(zone) ?
    frame .z.bot -width 300 -bd 2 -relief ridge
    button .z.go -text "Pick Zone" -state disabled -command {destroy .z}
    grid .z.bot - - -sticky ew
    grid .z.go - - -pady 10 -in .z.bot
    grid anchor .z.bot c

    grid columnconfigure .z 0 -minsize 10 -weight 1
    grid columnconfigure .z 2 -minsize 10 -weight 1
    tkwait window .z
    set state(zone,dir) $state(zone,$state(zone),zdir)
}
proc NewZoom {} {
    global C

    if {$C(scale) < 11} { set C(scale) 11 }
    if {$C(scale) > 20} { set C(scale) 20 }

    if {$C(tile,0) eq {} && $C(tile,1) eq {}} return
    if {$C(tile,0) ne {}} {
        set C(tile,0) [ll2tile $C(lat,0) $C(lon,0)]
    }
    if {$C(tile,1) ne {}} {
        set C(tile,1) [ll2tile $C(lat,1) $C(lon,1)]
    }
    DrawRegion

}
proc SortCorners {} {
    global C

    set tile0 $C(tile,0)
    set tile1 $C(tile,1)
    if {$tile0 eq {} && $tile1 eq {}} return
    if {$tile0 eq {} || $tile1 eq {}} {
        set tile0 [expr {$tile0 ne {} ? $tile0 : $tile1}]
        set tile1 [expr {$tile1 ne {} ? $tile1 : $tile0}]
    }

    lassign $tile0 z0 row0 col0
    lassign $tile1 z1 row1 col1
    set C(topLeft) [list $z0 [expr {min($row0,$row1)}] [expr {min($col0,$col1)}]]
    set C(bottomRight) [list $z0 [expr {max($row0,$row1) + 1}] [expr {max($col0,$col1) + 1}]]
    lassign [::map::slippy tile 2geo $C(topLeft)] . lat0 lon0
    lassign [::map::slippy tile 2geo $C(bottomRight)] . lat1 lon1
    set C(plat,tl) [int2plat $lat0]
    set C(plon,tl) [int2plat $lon0]
    set C(plat,br) [int2plat $lat1]
    set C(plon,br) [int2plat $lon1]
}

proc BClick {who x y} {
    global C

    set x [.c canvasx $x]
    set y [.c canvasy $y]

    lassign [canvas2ll $x $y] C(lat,$who) C(lon,$who)
    set C(tile,$who) [ll2tile $C(lat,$who) $C(lon,$who)]
    DrawRegion
}
proc FakeBClick {who lat lon} {
    global C

    set C(lat,$who) $lat
    set C(lon,$who) $lon
    set C(tile,$who) [ll2tile $C(lat,$who) $C(lon,$who)]
    DrawRegion
}
proc BCtrlClick {cx cy} {
    global WPT

    set x [.c canvasx $cx]
    set y [.c canvasy $cy]
    lassign [canvas2ll $x $y] lat lon
    lassign [int2lat $lat] WPT(lat1) WPT(lat2) WPT(lat3)
    lassign [int2lat $lon] WPT(lon1) WPT(lon2) WPT(lon3)
}
proc canvas2ll {x y} {
    global coords

    set lat [expr {$coords(top) + $coords(dy) * $y / $coords(ih)}]
    set lon [expr {$coords(left) + $coords(dx) * $x / $coords(iw)}]
    return [list $lat $lon]
}
proc ll2canvas {lat lon} {
    global coords

    set lat [expr {$lat - $coords(top)}]
    set cy [expr {round(1.0 * $lat * $coords(ih) / $coords(dy))}]

    set lon [expr {abs($lon) - $coords(left)}]
    set cx [expr {round(1.0 * $lon * $coords(iw) / $coords(dx))}]

    return [list $cx $cy]
}
proc ll2tile {lat lon} {
    Lon2World
    set geo [list $::C(scale) $lat $lon]
    set tile [::map::slippy geo 2tile $geo]
    return $tile
}
proc EnterLatLon {lat1 lon1 lat2 lon2} {
    global C

    set C(lat,0) $lat1
    set C(lon,0) $lon1

    set C(lat,1) $lat2
    set C(lon,1) $lon2
    DrawRegion
}
proc MakeWaypoint {tag args} {
    if {[llength $args] == 2} {
	lassign $args lat lon
    } elseif {[llength $args] == 6} {
	foreach var {lat lon} {a b c} $args {
	    set $var [lat2int $a $b $c]
	}
    } else {
	error "Bad number of coordinates to MakeWaypoint '$args'"
    }

    lassign [ll2canvas $lat $lon] cx cy
    set xy [Box $cx $cy 15]
    lassign $xy x0 y0 x1 y1
    .c delete wp,$tag
    set n [.c create text $cx $y1 -text $tag -anchor n -tag wp,$tag]
    set n2 [.c create rect [.c bbox $n] -tag wp,$tag -fill cyan -outline black]
    .c move $n2 -1 0
    .c raise $n

    .c create poly $x0 $cy $cx $y0 $x1 $cy $cx $y1 -tag wp,$tag \
	-outline red -width 4 -fill {} ;# -fill red -stipple gray25
    .c create oval [Box $cx $cy 2] -tag wp,$tag -fill black -outline black
}
proc Box {x y d} {
    return [list [expr {$x-$d}] [expr {$y-$d}] [expr {$x+$d}] [expr {$y+$d}]]
}
proc tracer {var1 var2 op} {
    global C

    if {$var2 eq "regionName"} {
	set C(regionFile) "$C(regionName).klr"
    }
    if {$C(regionFile) eq "" || $C(regionFile) eq ".klr" ||
        $C(nodeFile) eq "" || $C(tile,0) eq {} || $C(tile,1) eq {}} {
	.mregion config -state disabled
    } else {
	.mregion config -state normal
    }
}
proc tile2box {tile0} {
    set tile1 [::map::slippy tile add $tile0 {. 1 1} 1]

    set topLeft [::map::slippy tile 2geo $tile0]
    set bottomRight [::map::slippy tile 2geo $tile1]
    lassign $topLeft . lat0 lon0
    lassign $bottomRight . lat1 lon1

    Lon2Klimb lon0
    Lon2Klimb lon1

    lassign [ll2canvas $lat0 $lon0] x0 y0
    lassign [ll2canvas $lat1 $lon1] x1 y1

    return [list $x0 $y0 $x1 $y1]
}
proc tile2geobox {tile0} {
    set tile1 [::map::slippy tile add $tile0 {. 1 1} 1]

    set topLeft [::map::slippy tile 2geo $tile0]
    set bottomRight [::map::slippy tile 2geo $tile1]
    lassign $topLeft . lat0 lon0
    lassign $bottomRight . lat1 lon1

    Lon2Klimb lon0
    Lon2Klimb lon1
    return [list $lat0 $lon0 $lat1 $lon1]
}
proc DrawRegion {} {
    global C

    SortCorners
    if {$C(tile,0) eq {} || $C(tile,1) eq {}} {
        .c coords region {-100 -100 -100 -100}
        return
    }
    lassign [ll2canvas $C(lat,0) $C(lon,0)] x0 y0
    lassign [ll2canvas $C(lat,1) $C(lon,1)] x1 y1
    set xy [list [expr {min($x0,$x1)}] [expr {min($y0,$y1)}] \
                [expr {max($x0,$x1)}] [expr {max($y0,$y1)}]]
    .c coords region $xy
    DrawGrid
}
proc DrawGrid {} {
    global C state

    .c delete grid

    lassign $C(topLeft) zoom0 row0 col0
    lassign $C(bottomRight) zoom1 row1 col1

    for {set row $row0} {$row < $row1} {incr row} {
        for {set col $col0} {$col < $col1} {incr col} {
            set tile [list $zoom0 $row $col]
            set xy [tile2box $tile]
            .c create rect $xy -tag [list grid g$row,$col] \
                -width 2 -fill {} -outline black
        }
    }
    .c raise region
    lassign [::map::slippy tile add $C(bottomRight) $C(topLeft) -1] . dy dx
    set dx [expr {$col1 - $col0}]
    set dy [expr {$row1 - $row0}]
    set state(cells) "$dx x $dy => [expr {$dx * $dy}]"
    set state(pixels) "[Comma [expr {$dx*256}]] x [Comma [expr {$dy*256}]]"
    GetSize $dx $dy

    return
}
proc GetSize {dx dy} {
    set ::state(size) "not done"
    return
    set mult [expr {100 * int(pow(2,$::C(scale)-9))}]
    set width [expr {$mult * $dx}]
    set height [expr {$mult * $dy}]
    set width [expr {int(10 * $width * 100 /2.54 / 12 / 5280) / 10.0}]
    set height [expr {int(10 * $height * 100 /2.54 / 12 / 5280)/ 10.0}]
    set ::state(size) "$width mi x $height mi"
}

##+##########################################################################
#
# lat2int -- Converts degree minutes seconds into an integer
#
proc lat2int {lat1 lat2 lat3} {
    scan "$lat1 $lat2 $lat3" "%g %g %g" lat1 lat2 lat3
    return [expr {abs($lat1) + $lat2 / 60.0 + $lat3 / 3600.0}]
}
proc int2lat {int} {
    set int [expr {abs($int) * 3600}]

    set v [expr {$int + .05}]			;# Round to 1 decimal place
    lassign [split $v "."] int fra
    set fra [string range $fra 0 0]		;# 1 decimal place only

    set sec [expr {$int % 60}]
    if {$fra ne {0}} { append sec ".$fra"}

    set int [expr {$int / 60}]
    set min [expr {$int % 60}]
    set deg [expr {$int / 60}]

    return [list $deg $min $sec]
}
proc int2plat {int} {
    lassign [int2lat $int] l1 l2 l3
    set plat "$l1\xB0 $l2' $l3\x22"
    return $plat
}
proc Distance {lat1 lon1 lat2 lon2} {
    #set y1 [expr {$lat1  / 3600.0}]		;# Convert to decimal lat/lon
    #set x1 [expr {$lon1 / 3600.0}]
    #set y2 [expr {$lat2  / 3600.0}]
    #set x2 [expr {$lon2 / 3600.0}]
    set y1 $lat1
    set x1 $lon1
    set y2 $lat2
    set x2 $lon2

    set pi 3.1415926535
    set x1 [expr {$x1 *2*$pi/360.0}]		;# Convert degrees to radians
    set x2 [expr {$x2 *2*$pi/360.0}]
    set y1 [expr {$y1 *2*$pi/360.0}]
    set y2 [expr {$y2 *2*$pi/360.0}]
    # calculate distance:
    ##set d [expr {acos(sin($y1)*sin($y2)+cos($y1)*cos($y2)*cos($x1-$x2))}]
    set d [expr {sin($y1)*sin($y2)+cos($y1)*cos($y2)*cos($x1-$x2)}]
    if {abs($d) > 1.0} {			;# Rounding error
	set d [expr {$d > 0 ? 1.0 : -1.0}]
    }
    set d [expr {acos($d)}]

    set meters [expr {20001600/$pi*$d}]
    set miles [expr {$meters * 100 / 2.54 / 12 / 5280}]
    return $miles
}

##+##########################################################################
#
# DIE -- puts up an error message then exits the program
#
proc DIE {emsg} {
    tk_messageBox -message $emsg -icon error -title "KLIMB Error"
    exit
}
##+##########################################################################
#
# Zone::ReadZoneFile -- reads in a zone file which consists of overview map
# info, zone map info and default region.
#
proc ::Zone::ReadZoneFile {zname} {
    global zone

    catch {unset zone}
    set n [catch {set FIN [open $zname r]}]
    if {$n} {DIE "Can't open zone file $zname"}

    set zone(zone,map) ""
    set zone(zone,coords) ""
    while {[gets $FIN line] != -1} {
	if {[string match "\#*" $line]} continue
	set n [regexp {^(.*)\s*=\s*(.*)\s*$} $line => name value]
	if {$n} {
	    set zone($name) $value
	}
    }
    if {! [info exists zone(makezone,map)]} {
	set zone(makezone,map) $zone(zone,map)
	set zone(makezone,coords) $zone(zone,coords)
    }
    close $FIN
}
proc MakeRegion {} {
    global C state
    file mkdir $state(mapdir)

    if {$C(regionFile) eq ""} return
    if {$C(regionFile) eq "" || $C(regionFile) eq ".klr"} return
    if {$C(nodeFile) eq ""} return

    set zname [file join $state(zone,dir) $C(regionFile)]
    if {[file exists $zname]} {
	if {! [AreYouSure]} return
    }
    set mapdata [FetchMaps]

    set fout [open $zname w]
    puts $fout "# KLIMB region data, for more info see"
    puts $fout "# http://www.klimb.org/klimb.html"
    puts $fout "\nname=$C(regionName)"
    puts $fout "nodes=$C(nodeFile)"
    puts $fout [GetRegionMetaData]
    puts $fout "\n$mapdata"
    close $fout

    set nfile [file join $state(zone,dir) $C(nodeFile)]
    if {! [file exists $nfile]} {
	close [open $nfile a]			;# Create node file
    }
    tk_messageBox -message "Created the $C(regionName) Region"
    set C(regionName) ""
}
proc AreYouSure {} {
    set title "$::state(progname)"
    set txt "Region \"$::C(regionName)\" already exists.\n"
    append txt "Do you want to replace it?"
    set n [tk_messageBox -parent . -title $title -message $txt \
	       -icon warning -type yesno -default no]
    return [expr {$n eq "yes"}]
}
proc FetchMaps {} {
    set klrText ""
    set downloads [GetDownloadList]
    MakeProgressBar [llength $downloads]

    set ::errMaps {}
    foreach download $downloads {
	GetOneMap {*}$download
	append klrText [IntoKLR {*}$download] "\n"
    }
    ::PGU::Launch
    ::PGU::Wait
    DestroyProgressBar
    if {$::errMaps ne {}} {
	set ename [DumpErrorInfo]
	set cnt [llength $::errMaps]
	if {$cnt == 1} {
	    set emsg "$cnt map was not correctly loaded."
	} else {
	    set emsg "$cnt maps were not correctly loaded."
	}
	if {$ename ne ""} {
	    append emsg "\n\nError info saved in\n"
	    append emsg [file nativename [file normalize $ename]]
	}
	tk_messageBox -icon error -message $emsg -title "MakeZone Error"
    }
    return $klrText
}
proc GetRegionMetaData {} {
    global C
    set result "region=\"$C(theme)\" $C(scale) "
    append result "$C(lat,0) $C(lon,0) $C(lat,1) $C(lon,1)"
    return $result
}
proc DumpErrorInfo {} {
    global coords C errMaps

    set ename [file join $::state(zone,dir) "errInfo.txt"]
    set n [catch {set fout [open $ename w]}]
    if {$n} {return ""}

    puts $fout "Zone: $coords(top) $coords(left) $coords(bottom) $coords(right)"
    puts $fout "Theme: $C(theme)"
    puts $fout "Scale: $C(scale)"
    puts $fout "Region: $C(lat,0) $C(lon,0)  $C(lat,1) $C(lon,1)"
    puts $fout "Errors:"
    puts $fout [join $errMaps "\n"]
    close $fout

    return $ename
}
proc GetDownloadList {} {
    global C state

    set dirname [file join $state(mapdir) $C(theme) $C(scale)]
    file mkdir $dirname
    set fetcher [::Klippy::GetFetcher $C(theme)]

    lassign $C(topLeft) zoom0 row0 col0
    lassign $C(bottomRight) zoom1 row1 col1

    set result {}
    for {set row $row0} {$row < $row1} {incr row} {
        for {set col $col0} {$col < $col1} {incr col} {
            set tile [list $zoom0 $row $col]
            set fname [file join $dirname [join $tile "_"].png]
            set url [$fetcher url $tile]
            lappend result [list $tile $fname $url]
        }
    }
    return $result
}
##+##########################################################################
#
# IntoKLR -- converts fname into form used in the .klr file
# map=Maps/GoogleTerrain/13_1311_3175.jpg:13:37.5445 0 0 122.387 0 0 37.5097 0 0 122.34375 0 0

proc IntoKLR {tile fname url} {
    lassign [tile2geobox $tile] lat0 lon0 lat1 lon1
    set mapName [file join {*}[lrange [file split $fname] 1 end]]
    set scale [lindex $tile 0]
    set result "map=$mapName:$scale:$lat0 0 0 $lon0 0 0 $lat1 0 0 $lon1 0 0"
    return $result
}
proc GetOneMap {tile fname url} {
    global state

    if {! $state(nocache) && [file exists $fname]} {
        ShowTileStatus $tile "cached"
    } elseif {$state(nofetch)} {
        ShowTileStatus $tile "-"
    } else {
        set cookie [list $tile $fname $url]
        ::PGU::Add $url $cookie GotPageCmd PGUStatusCmd
    }
}
proc GotPageCmd {token cookie args} {
    StepProgressBar
    if {[::http::status $token] ne "ok"} {	;# Some kind of failure
	::http::cleanup $token
        lappend ::errMaps [list $type $cookie]
	return
    }

    set type [dict get? [::http::meta $token] Content-Type]
    if {! [string match "image/*" $type]} {
        lappend ::errMaps [list $type $cookie]
        return
    }
    lassign $cookie tile fname url
    set fout [open $fname wb]
    puts -nonewline $fout [::http::data $token]
    close $fout

    ::http::cleanup $token
}
proc PGUStatusCmd {id how cookie args} {
    lassign $cookie tile fname url
    ShowTileStatus $tile $how
}
proc ShowTileStatus {tile how args} {
    global status
    array set colors {
	queued blue  pending yellow  done green     timeout orange
	failure red  unused black    cached cyan    want magenta
	cancel plum1 image white     - black}

    lassign $tile zoom row col
    .c itemconfig g$row,$col -fill $colors($how)
}
##+##########################################################################
#
# DIE -- puts up an error message then exits the program
#
proc DIE {emsg} {
    tk_messageBox -message $emsg -icon error -title "$::state(progname) Error"
    exit
}



proc MakeProgressBar {max} {
    set W .pbar
    destroy $W
    toplevel $W
    wm withdraw $W
    wm title $W "$::state(progname) Status"
    wm transient $W .
    catch {wm attributes $W -toolwindow 1}

    set title "Downloading maps..."
    label $W.title -text $title -font boldFont -anchor w

    canvas $W.c -width 300 -height 20 -bg yellow -bd 2 -relief solid
    $W.c create text 150 13 -text "0%" -tag percent -font boldFont

    pack $W.title -side top -fill x -pady 5 -padx 5
    pack $W.c -side top -fill both -expand 1 -pady 5 -padx 5

    CenterWindow $W
    wm deiconify $W
    update

    set ::state(pbar,num) 0
    set ::state(pbar,max) $max
    return $W
}
proc DestroyProgressBar {} { destroy .pbar }
proc StepProgressBar {} {
    global state

    set w .pbar.c
    if {! [winfo exists $w]} return
    $w delete progress

    set num [incr state(pbar,num)]
    set max $state(pbar,max)
    if {$num > $max} {set num $max}

    set width  [winfo width $w]
    set height [winfo height $w]
    set x [expr {$num * $width / double($max)}]
    set perc [expr {round(100.0 * $num / $max)}]

    $w create rect 0 0 $x $height -tag progress -fill cyan -outline cyan
    $w lower progress
    $w itemconfig percent -text "$perc%"
    update
}

proc CenterWindow {w {anchor {}}} {
    update idletasks
    set wh [winfo reqheight $w]	       ; set ww [winfo reqwidth $w]

    if {[winfo exists $anchor]} {
	set sw [winfo width $anchor]   ; set sh [winfo height $anchor]
	set sy [winfo y $anchor]       ; set sx [winfo x $anchor]
    } else {
	set sw [winfo screenwidth .]   ; set sh [winfo screenheight .]
	set sx 0                       ; set sy 0
    }
    set x [expr {$sx + ($sw - $ww)/2}] ; set y [expr {$sy + ($sh - $wh)/2}]
    if {$x < 0} { set x 0 }	       ; if {$y < 0} {set y 0}

    wm geometry $w +$x+$y
}
proc Comma { num } {
    while {[regsub {^([-+]?[0-9]+)([0-9][0-9][0-9])} $num {\1,\2} num]} {}
    return $num
}
proc WaypointDialog {} {
    global WPT

    set W .wpt
    set WPT(W) $W

    destroy $W
    toplevel $W
    wm title $W "Add Marker"
    wm transient $W .
    wm withdraw $W

    label $W.t -text "Add Marker" -bd 5 -relief ridge -font bigBoldFont

    frame $W.middle -padx 20
    label $W.lname -text "Name:" -anchor e -font smallBoldFont
    entry $W.ename -width 12 -textvariable WPT(name)
    label $W.llat -text "Latitude:" -anchor e -font smallBoldFont
    entry $W.elat1 -width 4 -textvariable WPT(lat1)
    label $W.llat1 -width 1 -text "\xb0" -font boldFont
    entry $W.elat2 -width 4 -textvariable WPT(lat2)
    label $W.llat2 -width 1 -text "'" -font boldFont
    entry $W.elat3 -width 4 -textvariable WPT(lat3)
    label $W.llat3 -width 0 -text "\x22N" -font boldFont
    label $W.llon -text "Longitude:" -anchor e -font smallBoldFont
    entry $W.elon1 -width 4 -textvariable WPT(lon1)
    label $W.llon1 -width 1 -text "\xb0" -font boldFont
    entry $W.elon2 -width 4 -textvariable WPT(lon2)
    label $W.llon2 -width 1 -text "'" -font boldFont
    entry $W.elon3 -width 4 -textvariable WPT(lon3)
    label $W.llon3 -width 1 -text "\x22W" -font boldFont

    label $W.help -text "Ctrl-click on map to enter location"
    frame $W.buttons -bd 2 -relief ridge
    button $W.ok -text "Add" -command WPT:Done
    button $W.cancel -text Cancel -command [list destroy $W]

    grid $W.t -sticky ew -pady {0 20}
    grid $W.middle -sticky news
    grid $W.lname $W.ename - - - - - -in $W.middle -sticky ew -pady {0 10}
    grid $W.llat $W.elat1 $W.llat1 $W.elat2 $W.llat2 $W.elat3 $W.llat3 -in $W.middle -sticky ew
    grid $W.llon $W.elon1 $W.llon1 $W.elon2 $W.llon2 $W.elon3 $W.llon3 -in $W.middle -sticky ew

    grid $W.help -sticky ew
    grid $W.buttons -sticky ew -pady {20 0}
    grid $W.ok $W.cancel -in $W.buttons -padx 30 -pady 10 -sticky ew
    grid columnconfigure $W.middle {1 2 3} -weight 1
    grid columnconfigure $W.buttons {0 1} -uniform a

    trace remove variable WPT write WPT:Tracer
    trace variable WPT w WTP:Tracer
    set WPT(name) $WPT(name)

    CenterWindow $W .
    wm deiconify $W
}
proc WTP:Tracer {var1 var2 op} {
    global WPT

    set W $WPT(W)
    if {! [winfo exists $W.ok]} return
    $W.ok config -state disabled
    if {[string trim $WPT(name)] eq ""} return
    if {! [string is double -strict $WPT(lat1)]} return
    if {! [string is double -strict $WPT(lon1)]} return
    foreach who {lat2 lat3 lon2 lon3} {
	if {! [string is double $WPT($who)]} return
    }
    $W.ok config -state normal

}
proc WPT:Done {} {
    global WPT state

    set W $WPT(W)
    destroy $W
    trace remove variable WPT write WPT:Tracer

    array set _wpt [array get WPT l*\[123\]]
    foreach who {lat1 lat2 lat3 lon1 lon2 lon3} {
	if {[string trim $_wpt($who)] eq ""} { set _wpt($who) 0}
    }
    set lat [lat2int $_wpt(lat1) $_wpt(lat2) $_wpt(lat3)]
    set lon [lat2int $_wpt(lon1) $_wpt(lon2) $_wpt(lon3)]

    MakeWaypoint $WPT(name) $lat $lon

    set fout [open $state(wptFile) a]
    puts $fout "MakeWaypoint \x22$WPT(name)\x22 $lat $lon"
    close $fout
}
proc MenuPostCmd {W} {
    while {[$W entryconfig 0 -label] ne ""} {
	$W delete 0
    }
    set klrs [glob -nocomplain -directory $::state(zone,dir) *.klr]
    foreach klr [lsort -dictionary $klrs] {
	set lbl [file tail [file rootname $klr]]
	$W add command -label $lbl -command [list ReadKLRFile $klr]
    }
    return 1
}

proc ReadKLRFile {rname} {
    global C
    set fin [open $rname r]
    set data [string trim [read $fin]]; list
    close $fin

    set utm [regexp -line {^utm\s*=\s*1\s*$} $data]
    if {$utm} { error "cannot handle utm zones" }
    set first 1
    set all {}
    set newTheme {}
    foreach line [split $data \n] {
        if {[string match "region=*" $line]} {
            lassign [string range 7 end] newTheme newScale newTop newLeft newBottom newRight
            continue
        }
	if {! [string match "map=*" $line]} continue
	#map=Maps/ohio1012_bot.gif:3:40 18  0 82 48  0 40 12  0 82 36  0
	#map=Maps/Topo/14/120_1313_12.gif:14:4204800 384000 12 4201600 387200 12

	set where [lindex [split $line ":"] 2]
        foreach var {lat0 lon0 lat1 lon1} {a b c} $where {
            set $var [lat2int $a $b $c]
	}
	lappend all [list $lat0 $lon0 $lat1 $lon1]
    }
    if {$newTheme ne ""} {
        TODO
        set C(lat,0) $newTop
        set C(lon,0) $newLeft
        set C(lat,1) $newBottom
        set C(lon,1) $newRight
        set C(theme) $newTheme
        set C(scale) $newScale
    } else {
        set all1 [lsort -decreasing -index 1 -real $all]
        set all2 [lsort -decreasing -index 0 -real $all1]
        lassign [lindex $all2 0] lat0 lon0 lat1 lon1
        set C(lat,0) [expr {($lat0+$lat1)/2}]
        set C(lon,0) [expr {($lon0+$lon1)/2}]

        lassign [lindex $all2 end] lat0 lon0 lat1 lon1
        set C(lat,1) [expr {($lat0+$lat1)/2}]
        set C(lon,1) [expr {($lon0+$lon1)/2}]
    }
    set C(tile,0) [ll2tile $C(lat,0) $C(lon,0)]
    set C(tile,1) [ll2tile $C(lat,1) $C(lon,1)]
    NewZoom

    set ::C(regionName) [file rootname [file tail $rname]]
}
proc ::tcl::dict::get? {args} {
    try {                ::set x [dict get {*}$args]
    } on error message { ::set x {} }
    return $x
}

################################################################


::Klippy::Init ~/klimb/slippy_cache
FindZones
PickZone [lindex $argv 0]
ZoneInit
DoDisplay
trace variable C w tracer
::PGU::Config -timeout 15000

if {[file readable $state(wptFile)]} {
    source $state(wptFile)
}
return 1
