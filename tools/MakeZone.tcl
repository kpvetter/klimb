#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
exec tclsh $0 ${1+"$@"}

##+##########################################################################
#
# MakeZone.tcl -- <description>
# by Keith Vetter
#
# Revisions:
# KPV May 07, 2004 - initial revision
#
##+##########################################################################
#############################################################################

package provide app-makezone 1.0
package require Tk
package require http 2.0
package require Img

set S(title) "KLIMB Make Zone"
set S(w) 3
set S(h) 3
set S(mag) 13
set S(nocache) 0
set S(nofetch) 0
set S(gotMap) 0
set S(fetch,count) 0
set WPT(all) {}

set Z(c,lat) "37 25 44.65"
set Z(c,lon) "122 7 20.3"

set D(up,dxy) {0 -1}
set D(down,dxy) {0 1}
set D(right,dxy) {1 0}
set D(left,dxy) {-1 0}
set D(upleft,dxy) {-1 -1}
set D(upright,dxy) {1 -1}
set D(downleft,dxy) {-1 1}
set D(downright,dxy) {1 1}

proc Lon2World {{lonVar lon}} {
    upvar 1 $lonVar lon
    set lon [expr {-abs($lon)}]
}
proc Lon2Klimb {{lonVar lon}} {
    upvar 1 $lonVar lon
    set lon [expr {abs($lon)}]
}


proc DoDisplay {} {
    global S Z

    wm title . $S(title)
    frame .left -bd 2 -relief ridge
    frame .right -bd 2 -relief ridge
    grid .left .right -sticky news
    grid rowconfigure . 0 -weight 1
    grid columnconfigure . 0 -weight 1

    scrollbar .sb_x -command [list .c xview] -orient horizontal
    scrollbar .sb_y -command [list .c yview] -orient vertical
    canvas .c -highlightthickness 0 \
	-xscrollcommand {.sb_x set} -yscrollcommand {.sb_y set}
    lassign [CellCoords $S(h) $S(w)] x y
    .c config -width [expr {$x+1}] -height [expr {$y+1}]
    bind .c <2> [bind Text <2>]			;# Enable dragging w/ <2>
    bind .c <B2-Motion> [bind Text <B2-Motion>]
    bind .c <Double-Button-1> [list BClick %x %y]
    .c bind all <Control-Button-1> [list BCtrlClick %x %y]

    grid .c .sb_y -in .left -sticky news
    grid .sb_x -in .left -sticky ew
    grid rowconfigure .left 0 -weight 1
    grid columnconfigure .left 0 -weight 1

    # Geographic Info
    labelframe .geo -text "Geographic Info" -padx 5
    .geo configure  -font "[font actual [.geo cget -font]] -weight bold"
    option add *Labelframe.font [.geo cget -font]
    option add *Button.font [.geo cget -font]
    label .geo.lat -text "Latitude"
    label .geo.lon -text "Longitude"
    label .geo.cen -text "Center:" -anchor e
    label .geo.help -text "(double click to recenter)"
    entry .geo.elat -textvariable Z(c,lat) -width 10
    entry .geo.elon -textvariable Z(c,lon) -width 10
    label .geo.width -text "Width:" -anchor e
    entry .geo.ewidth -textvariable S(w) -width 5
    label .geo.height -text "Height:" -anchor e
    entry .geo.eheight -textvariable S(h) -width 5
    label .geo.scale -text "Scale:" -anchor e

    frame .geo.buttons
    ::Klippy::FetchAndZoomOptionMenu .geo.suppliers S(supplier) NewSupplier .geo.om S(mag) NewMag
    button .geo.fetch -text "Get Maps" -command GetMaps

    grid x .geo.lat .geo.lon
    grid .geo.cen .geo.elat .geo.elon -sticky ew
    grid x .geo.help - -pady {0 5}
    grid .geo.width .geo.ewidth -sticky w
    grid .geo.height .geo.eheight -sticky w
    grid .geo.scale .geo.om -sticky w
    grid .geo.buttons - - -pady 10 -sticky ew
    pack .geo.fetch .geo.suppliers -side left -in .geo.buttons -expand 1

    # Waypoint
    labelframe .waypoint -bd 2 -relief ridge -text "Markers"
    button .waypoint.add -text "New Marker" -command WaypointDialog \
	 -state disabled
    pack .waypoint.add -pady 10 -expand 1

    # Zone info
    labelframe .zone -text "Zone Info" -padx 5 -pady 5
    label .zone.name -text "Name:" -anchor e
    entry .zone.ename -textvariable Z(zname)
    label .zone.dir -text "Directory:" -anchor e
    entry .zone.edir -textvariable Z(zdir)
    button .zone.makezone -text "Make Zone" -command MakeZone -state disabled
    grid .zone.name .zone.ename -sticky we
    grid .zone.dir .zone.edir -sticky we
    grid .zone.makezone - - -pady {10 5}


    label .fetches -textvariable S(fetch,count)
    place .fetches -relx 1 -rely 1 -x -5 -y -5 -anchor se

    grid .geo -in .right -sticky news
    grid .waypoint -in .right -sticky news
    grid .zone -in .right -sticky news -pady 20
    grid rowconfigure .right 100 -weight 1

    foreach d {upleft up upright right downright down downleft left} {
	::ttk::button .c.$d -image ::bit::$d -command [list Shift $d]
    }

    place .c.upleft -x .1i -y .1i -anchor nw
    place .c.up -relx .5 -y .1i -anchor n
    place .c.upright -relx 1 -x -.1i -y .1i -anchor ne
    place .c.right -relx 1 -x -.1i -rely .5 -anchor e
    place .c.downright -relx 1 -x -.1i -rely 1 -y -.1i -anchor se
    place .c.down -relx .5 -rely 1 -y -.1i -anchor s
    place .c.downleft -x .1i -rely 1 -y -.1i -anchor sw
    place .c.left -x .1i -rely .5 -anchor w


    # bind all <MouseWheel> {MouseWheel %W %D %X %Y yview}
    # bind all <Shift-MouseWheel> {MouseWheel %W %D %X %Y xview}
    bind all <Key-F2> {console show}

    trace variable Z(zname) w Tracer
    trace variable Z(zdir) w Tracer
    focus .zone.ename
    set Z(zname) ""
}
image create bitmap ::bit::up -data {
    #define up_width 11
    #define up_height 11
    static char up_bits = {
        0x00, 0x00, 0x20, 0x00, 0x70, 0x00, 0xf8, 0x00, 0xfc, 0x01, 0xfe,
        0x03, 0x70, 0x00, 0x70, 0x00, 0x70, 0x00, 0x00, 0x00, 0x00, 0x00
    }
}
image create bitmap ::bit::down -data {
    #define down_width 11
    #define down_height 11
    static char down_bits = {
        0x00, 0x00, 0x00, 0x00, 0x70, 0x00, 0x70, 0x00, 0x70, 0x00, 0xfe,
        0x03, 0xfc, 0x01, 0xf8, 0x00, 0x70, 0x00, 0x20, 0x00, 0x00, 0x00
    }
}
image create bitmap ::bit::left -data {
    #define left_width 11
    #define left_height 11
    static char left_bits = {
        0x00, 0x00, 0x20, 0x00, 0x30, 0x00, 0x38, 0x00, 0xfc, 0x01, 0xfe,
        0x01, 0xfc, 0x01, 0x38, 0x00, 0x30, 0x00, 0x20, 0x00, 0x00, 0x00
    }
}
image create bitmap ::bit::right -data {
    #define right_width 11
    #define right_height 11
    static char right_bits = {
        0x00, 0x00, 0x20, 0x00, 0x60, 0x00, 0xe0, 0x00, 0xfc, 0x01, 0xfc,
        0x03, 0xfc, 0x01, 0xe0, 0x00, 0x60, 0x00, 0x20, 0x00, 0x00, 0x00
    }
}
image create bitmap ::bit::upleft -data {
    #define upleft_width 11
    #define upleft_height 11
    static char upleft_bits = {
	0x00, 0x00, 0x7e, 0x00, 0x3e, 0x00, 0x3e, 0x00, 0x7e, 0x00, 0xfe,
	0x00, 0xf2, 0x01, 0xe0, 0x00, 0x40, 0x00, 0x00, 0x00, 0x00, 0x00
    }
}
image create bitmap ::bit::upright -data {
    #define upright_width 11
    #define upright_height 11
    static char upright_bits = {
	0x00, 0x00, 0xf0, 0x03, 0xe0, 0x03, 0xe0, 0x03, 0xf0, 0x03, 0xf8,
	0x03, 0x7c, 0x02, 0x38, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00
    }
}
image create bitmap ::bit::downleft -data {
    #define downleft_width 11
    #define downleft_height 11
    static char downleft_bits = {
	0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0xe0, 0x00, 0xf2, 0x01, 0xfe,
	0x00, 0x7e, 0x00, 0x3e, 0x00, 0x3e, 0x00, 0x7e, 0x00, 0x00, 0x00
    }
}
image create bitmap ::bit::downright -data {
    #define downright_width 11
    #define downright_height 11
    static char downright_bits = {
	0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x38, 0x00, 0x7c, 0x02, 0xf8,
	0x03, 0xf0, 0x03, 0xe0, 0x03, 0xe0, 0x03, 0xf0, 0x03, 0x00, 0x00
    }
}

proc DrawGrid {} {
    global S

    .c delete all
    for {set row 0} {$row < $S(h)} {incr row} {
	for {set col 0} {$col < $S(w)} {incr col} {
	    set xy [CellCoords $row $col]
	    foreach {x0 y0 x1 y1} $xy break
	    .c create rect $xy -fill {} -outline black -tag ggrid -width 2
	    .c create image $x0 $y0 -anchor nw -tag [list img img$row,$col]
	    set x [expr {($x0 + $x1) / 2}]
	    set y [expr {($y0 + $y1) / 2}]
	    .c create text $x $y -anchor center -font [.zone cget -font] \
		-tag txt$row,$col
	}
    }
    .c config -scrollregion [.c bbox all]
    .c raise img
    .c raise ggrid
}
proc Tracer {var1 var2 op} {
    global Z S

    if {$var2 eq "zname"} {
	set Z(zdir) [string tolower [string map {" " ""} $Z(zname)]]
	append Z(zdir) ".zone"
    }
    set how normal
    if {$Z(zname) eq "" || $Z(zdir) eq "" || ! $S(gotMap)} {
	set how disabled
    }
    .waypoint.add config -state [expr {$S(gotMap) ? "normal" : "disabled"}]
    .zone.makezone config -state $how
}
proc Busy {onoff} {
    set who {.zone.ename .zone.edir .zone.makezone
	.geo.elat .geo.elon .geo.ewidth .geo.eheight .geo.fetch
	.geo.om .waypoint.add
    }
    set how [expr {$onoff ? "disabled" : "normal"}]
    foreach w $who { $w config -state $how }
    if {! $onoff} {
	Tracer x x x
    }
}
proc CellCoords {row col} {
    set x0 [expr {1 + $col * 256}]
    set x1 [expr {$x0 + 256}]
    set y0 [expr {1 + $row * 256}]
    set y1 [expr {$y0 + 256}]
    return [list $x0 $y0 $x1 $y1]
}
proc ll2canvas {lat lon} {
    global S

    set geo [list $S(mag) $lat $lon]
    set point [::map::slippy geo 2point $geo]
    set offset [::map::slippy tile add $point $S(topLeft,point) -1]

    lassign $offset . y x
    return [list $x $y]
}
proc canvas2ll {cx cy} {
    set offset [list . $cy $cx]
    set point [::map::slippy tile add $::S(topLeft,point) $offset 1]
    set geo [::map::slippy point 2geo $point]
    lassign $geo . lat lon
    return [list $lat $lon]
}
proc int2lat {int} {
    set int [expr {abs($int) * 3600}]

    if {[string is integer -strict $int]} {
	set sec [expr {$int % 60}]
    } else {
	set v [expr {$int + .05}]		;# Round to 1 decimal place
	foreach {int fra} [split $v "."] break	;# Use string representation
	set fra [string range $fra 0 0]		;# 1 decimal place only

	set sec [expr {$int % 60}]
	if {$fra ne {0}} { append sec ".$fra"}
    }
    set int [expr {$int / 60}]
    set min [expr {$int % 60}]
    set deg [expr {$int / 60}]

    return [list $deg $min $sec]
}
proc Shift {dir} {
    global S Z D

    lassign [ll2canvas $Z(lat) $Z(lon)] cx cy
    lassign $D($dir,dxy) dx dy
    set cx [expr {$cx + 256 * $dx}]
    set cy [expr {$cy + 256 * $dy}]
    lassign [canvas2ll $cx $cy] lat lon
    Recenter $lat $lon
}
proc BClick {x y} {
    if {! [info exists ::S(topLeft,point)]} return
    set cx [.c canvasx $x]
    set cy [.c canvasy $y]
    foreach {lat lon} [canvas2ll $cx $cy] break
    Recenter $lat $lon
}
proc BCtrlClick {cx cy} {
    global WPT

    set x [.c canvasx $cx]
    set y [.c canvasy $cy]
    foreach {lat lon} [canvas2ll $x $y] break
    foreach {WPT(lat1) WPT(lat2) WPT(lat3)} [int2lat $lat] break
    foreach {WPT(lon1) WPT(lon2) WPT(lon3)} [int2lat $lon] break
}

proc Recenter {lat lon} {
    global S Z
    set Z(c,lat) [int2lat $lat]
    set Z(c,lon) [int2lat $lon]

    set S(nofetch) 1
    GetMaps
    set S(nofetch) 0
}
##+##########################################################################
#
# MouseWheel -- more general MouseWheel that fires in window w/ the mouse
#
proc MouseWheel {wFired D X Y dir} {

    if {[bind [winfo class $wFired] <MouseWheel>] ne ""} return	;# Already bound
    set w [winfo containing $X $Y]		;# Window mouse is over
    if {![winfo exists $w]} { catch {set w [focus]} } ;# Fail over to focus
    if {![winfo exists $w]} return

    # scrollbars have different call conventions
    if {[winfo class $w] eq "Scrollbar"} {
	catch {tk::ScrollByUnits $w \
		   [string index [$w cget -orient] 0] \
		   [expr {-($D/30)}]}
    } else {
	catch {$w $dir scroll [expr {- ($D / 120) * 4}] units}
    }
}
##+##########################################################################
#
# lll2dec -- converts latitude into decimal format
#
proc lll2dec {args} {
    if {[llength $args] == 1} {set args [lindex $args 0]}
    foreach {lat1 lat2 lat3} [concat $args 0 0] break
    return [expr {$lat1 + $lat2/60.0 + $lat3/60.0/60.0}]
}
proc lat2int {a b c} {
    return [lll2dec $a $b $c]
}

proc NewMag {} {
    NewSupplier
}
proc NewSupplier {} {
    global S
    set S(slippy) [::Klippy::GetCacher $S(supplier)]
    set S(fetcher) [::Klippy::GetFetcher $S(supplier)]
    GetMaps
}

proc GetMaps {} {
    global Z S WPT

    Busy 1
    ClearMaps
    DrawGrid
    set Z(lat) [lll2dec $Z(c,lat)]
    set Z(lon) [lll2dec $Z(c,lon)]
    Lon2World Z(lon)

    set geo [list $S(mag) $Z(lat) $Z(lon)]
    set centerTile [::map::slippy geo 2tile $geo]
    set deltaTile [list $S(mag) [expr {$S(h)/2}] [expr {$S(w)/2}]]
    set S(topLeft) [::map::slippy tile add $centerTile $deltaTile -1]
    set S(topLeft,point) [::map::slippy tile 2point $S(topLeft)]

    for {set row 0} {$row < $S(h)} {incr row} {
	for {set col 0} {$col < $S(w)} {incr col} {
	    GetOneMap $row $col
	}
    }
    MakeWaypoint center $Z(lat) $Z(lon)
    foreach wpt $WPT(all) {
	foreach {name wlat wlon} $wpt break
	MakeWaypoint $name $wlat $wlon
    }
    set S(gotMap) 1
    Busy 0
}
proc GetOneMap {row col} {
    global S Z

    set tile [::map::slippy tile add $S(topLeft) [list . $row $col] 1]
    set cookie [list $row $col]
    $S(slippy) get $tile [list FetchDone $cookie]
}
proc FetchDone {cookie cmd tile {iname ""}} {
    incr ::S(fetch,count)
    if {$cmd ne "set"} {
        puts "ERROR: bad fetch for $tile ($cookie)"
        return
    }
    lassign $cookie row col
    PutImage $row $col $iname
}
proc ClearMaps {} {
    set S(gotMap) 0
    foreach img [image names] {
        if {! [string match "::tk::icons::*" $img] && ! [string match "::bit::*" $img]} {
            image delete $img
        }
    }
}
proc PutImage {row col iname} {
    .c itemconfig img$row,$col -image $iname
}

proc WARN {emsg} {
    tk_messageBox -message $emsg -icon error -title "$::S(title) Error"
    return 0
}
proc INFO {msg} {
    tk_messageBox -message $msg -icon info -title "$::S(title) Information"
    return 0
}

proc MakeZone {} {
    global S Z

    if {$Z(zname) eq "" || $Z(zdir) eq ""} return
    file mkdir $Z(zdir)
    if {! [file isdirectory $Z(zdir)]} {
	WARN "Cannot create zone directory '$Z(zdir)'"
	return
    }
    set zdata [file join $Z(zdir) "zone.data"]
    if {[file exists $zdata]} {
	WARN "Zone '$Z(zdir)' already exists"
	return
    }

    set imgDir0 "Images"
    set imgDir [file join $Z(zdir) $imgDir0]
    file mkdir $imgDir
    if {! [file isdirectory $imgDir]} {
	WARN "Cannot create Image directory '$imgDir'"
	return
    }

    # Create the zone map -- not beautiful but functional
    set mname0 [file join $imgDir0 "zone.jpg"]
    set mname [file join $imgDir "zone.jpg"]
    JoinMaps $mname

    lassign [::map::slippy tile 2geo $S(topLeft)] . top left
    Lon2Klimb left
    set bottomRight [::map::slippy tile add $S(topLeft) [list . $S(h) $S(w)] 1]
    lassign [::map::slippy tile 2geo $bottomRight] . bottom right
    Lon2Klimb bottom

    # Create the sacred zone.data file
    set fout [open $zdata w]
    puts $fout "# KLIMB zone data, for more info see"
    puts $fout "# http://www.klimb.org/klimb.html"
    puts $fout "\nname=$Z(zname)"
    puts $fout "\nzone,map=$mname0"
    puts $fout "zone,coords=$top 0 0 $left 0 0 $bottom 0 0 $right 0 0"
    close $fout
    INFO "Zone $Z(zname) created."
}
proc JoinMaps {fname} {
    global S

    set w [expr {$S(w) * 256}]
    set h [expr {$S(h) * 256}]
    image create photo ::img::zone -width $w -height $h

    for {set row 0} {$row < $S(h)} {incr row} {
	for {set col 0} {$col < $S(w)} {incr col} {
            set iname [.c itemcget img$row,$col -image]
	    set x [expr {$col * 256}]
	    set y [expr {$row * 256}]
	    ::img::zone copy $iname -to $x $y
	}
    }
    ::img::zone write $fname -format jpeg
    image delete ::img::zone
}
proc MakeWaypoint {tag lat lon} {

    lassign [ll2canvas $lat $lon] cx cy
    lassign [Box $cx $cy 15] x0 y0 x1 y1
    .c delete wp,$tag

    set n [.c create text $cx $cy -text $tag -anchor c -tag wp,$tag]
    set xy [.c bbox $n]
    .c create rect $xy -tag wp,$tag -fill cyan -outline black
    .c raise $n

    .c create line $x0 $y0 $x1 $y1 -tag wp,$tag -fill red
    .c create line $x0 $y1 $x1 $y0 -tag wp,$tag -fill red
    return
    .c create poly $x0 $cy $cx $y0 $x1 $cy $cx $y1 -tag wp,$tag \
	-fill red -outline red -width 4 -stipple gray25
}
proc Box {x y d} {
    return [list [expr {$x-$d}] [expr {$y-$d}] [expr {$x+$d}] [expr {$y+$d}]]
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
    trace variable WPT w WPT:Tracer
    set WPT(name) $WPT(name)

    CenterWindow $W .
    wm deiconify $W
}
proc WPT:Tracer {var1 var2 op} {
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
    Lon2World

    MakeWaypoint $WPT(name) $lat $lon
    lappend WPT(all) [list $WPT(name) $lat $lon]
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


################################################################

proc SaveRegion {regionName zoneDir} {
    global C state

    set zoneDir [file normalize $zoneDir]
    file mkdir $zoneDir
    set prettyName [string map {" " ""} $regionName]
    set regionFile [file join $zoneDir "${prettyName}.klr"]
    set nodeFile [file join $zoneDir klimb.nodes]
    if {! [file exists $nodeFile]} { close [open $nodeFile a] }
    set mapList [GetRegionMapList]
    set scale $::S(mag)

    set fout [open $regionFile w]
    puts $fout "# KLIMB region data, for more info see"
    puts $fout "# http://www.klimb.org/klimb.html"
    puts $fout "\nname=$regionName"
    puts $fout "nodes=[file tail $nodeFile]"
    puts $fout "slippy=1"
    puts $fout ""
    foreach mapItem $mapList {
        lassign $mapItem fname lat0 lon0 lat1 lon1
        set mapName [CopyMap $fname $zoneDir]
        # set result "map=$mapName:$scale:$lat0 0 0 $lon0 0 0 $lat1 0 0 $lon1 0 0"
        puts $fout "map=$mapName:$scale:$lat0 0 0 $lon0 0 0 $lat1 0 0 $lon1 0 0"
    }
    close $fout

    tk_messageBox -message "Created the $regionName Region"
    set C(regionName) ""
}
proc CopyMap {source zoneDir} {
    if {! [file exists $source]} {
        puts stderr "missing $source"
        return
    }

    set tails [lrange [file split $source] end-3 end]
    set zoneFile [file join Maps {*}$tails]
    set fullFile [file join $zoneDir $zoneFile]
    file mkdir [file dirname $fullFile]
    file copy -force $source $fullFile
    return $zoneFile
}

proc GetRegionMapList {} {
    global S

    set result {}
    for {set row 0} {$row < $S(h)} {incr row} {
	for {set col 0} {$col < $S(w)} {incr col} {
            set tile0 [::map::slippy tile add $S(topLeft) [list . $row $col] 1]
            set tile1 [::map::slippy tile add $tile0 [list . 1 1] 1]
            lassign [::map::slippy tile 2geo $tile0] . lat0 lon0
            lassign [::map::slippy tile 2geo $tile1] . lat1 lon1
            Lon2Klimb lon0
            Lon2Klimb lon1

            set fname [$S(slippy) fileOf $tile0]
            lappend result [list $fname $lat0 $lon0 $lat1 $lon1]
        }
    }
    return $result
}



set test [glob -nocomplain */zone.data]
if {[llength $test] == 0} {
    wm withdraw .
    set msg "ERROR: You must run this program from the KLIMB directory\n"
    append msg "(typically at c:\\program files\\klimb)."
    tk_messageBox -icon error -message $msg -title "KLIMB MakeZone"
    exit
}
source packages/maps.tsh
set S(mapdir) [file join [pwd] slippy_cache2]
file mkdir $S(mapdir)
::Klippy::Init $S(mapdir)

set S(supplier) "Google Terrain"
set S(supplier) "Google"

DoDisplay
DrawGrid
NewSupplier

return
