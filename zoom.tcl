

## BON ZOOM
##+##########################################################################
#
# ::Zoom::Go -- zooms given road id
#


foreach var {ZMAP RINFO T W W2 DS STATIC SCREEN FETCH COLORS stats google lcxy} {
    uplevel #0 upvar #0 ::Zoom::$var ::$var
}
source klippy.tsh
proc ss {} { uplevel 1 source klippy.tsh }

set what road ; set who r759

proc ::Zoom::Go {what who} {
    variable ZMAP

    ::Zoom::Init
    if {! $::state(zoom,canDo)} return

    set what [string tolower $what]
    if {$what eq "popup"} {
        set what $::state(popup,what)
        set who $::state(popup,who)
        if {$what eq "map"} {
            set what "coords"
            set who "map"
        }
    }
    set n [lsearch -exact {road node poi geo route track coords} $what]
    if {$n == -1} return

    set ZMAP(what) $what
    set ZMAP(who) $who
    set ZMAP(readonly) [expr {!$::state(su) && [string range $who 0 0] ne "X"}]
    set ZMAP(guessable) [expr {$::state(su) || ($what eq "road" \
                                    && [string match "X*" $who])}]

    ::Zoom::DoDisplay
    ::Zoom::GetDetails $what $who
    set ::Zoom::DS(title) $::Zoom::RINFO(title)
    ::Zoom::MakeMap
    ::Data::UniqueTrace ::Zoom::RINFO {::Zoom::IsModified 1}
    ::Atlas::Reparent
}
##+##########################################################################
#
# ::Zoom::Init -- loads everything needed by the zoom feature
#   http://terraserver-usa.com/about.aspx?n=AboutLinktoHtml
#
proc ::Zoom::Init {} {
    variable STATIC
    global state

    set STATIC(maxRendered) $state(zoom,maxRendered)
    if {[info exists state(zoom,canDo)] && ! $state(zoom,canDo)} return

    set state(zoom,canDo) 0                     ;# Assume we can't do it
    if {! [::Data::CanDo internet]} {
        return [WARN "This feature requires the http extension"]
    }
    if {! $state(can,jpeg)} {
        return [WARN "This feature requires the Img extension"]
    }
    if {! [::Data::CanDo pgu]} {
        return [WARN "This feature requires KLIMB's pgu extension"]
    }

    set state(zoom,canDo) 1
    set STATIC(url2) $STATIC(url)
    ::Zoom::FindCache
}
##+##########################################################################
#
# ::Zoom::FindCache -- returns location of our cache directory
#
proc ::Zoom::FindCache {} {
    set ::Zoom::STATIC(cache) [file join $::state(zdir) zoom]
    return $::Zoom::STATIC(cache)
}
##+##########################################################################
#
# ::Zoom::MakeMap -- sets us up for a new map to be displayed
#
proc ::Zoom::MakeMap {} {
    variable DS
    variable ZMAP
    variable stats
    variable RINFO
    variable SCREEN

    #::PGU::Cancel -all
    set ZMAP(ready) 0
    set ZMAP(mag) $DS(mag)
    set ZMAP(theme) $DS(theme)
    set ZMAP(rendered) {}                       ;# List of all rendered cells
    incr ZMAP(sid)                              ;# Session id

    ::Klippy::InitMap $RINFO(pts) $::Zoom::ZMAP(mag) $SCREEN(cols) $SCREEN(rows)
    ::Klippy::DrawGrid
    ::Klippy::DrawPoints

    if {$ZMAP(what) eq "route"} {
        ::MilePost::Go $::Zoom::W
        ::Arrow::Go $::Zoom::W
    }
    if {$::state(atlas)} {
        ::Atlas::Begin
    }
    update

    ::Klippy::Fetch::BuildQueues
    set ZMAP(ready) 1
    set stats(rendered) 0
    #::Zoom::RunAllQueues ;# this happens via Expose from scrollbar
}
##+##########################################################################
#
# ::Zoom::Canvas2Small -- converts W coordinates to W2 coordinates
#
proc ::Zoom::Canvas2Small {args} {
    variable STATIC

    set xy {}
    foreach x $args {
        lappend xy [expr {$x / $STATIC(small)}]
    }
    return $xy
}
##+##########################################################################
#
# Clear -- clears the map and deletes all map images
#
proc ::Zoom::Clear {} {
    variable W
    variable W2
    variable ZMAP

    if {[info exists ::nnode(l0)] && $::nnode(l0) eq "Elevation"} {
        destroy .nnode
    }
    if {[winfo exist $W]} {
        $W delete all
        $W2 delete all

        $W config -scrollregion {0 0 99999 99999}
        $W xview moveto 0
        $W yview moveto 0
        update
    }
    foreach img [image names] {
        if {[string match "::zoom::*" $img]} {
            image delete $img
        }
    }
    set ZMAP(rendered) {}
}
##+##########################################################################
#
# ::Zoom::MyScroller -- our scroll procedure that also gets maps
#
proc ::Zoom::MyScroller {xy first last} {
    ::Zoom::GetScreenRect
    ${::Zoom::T}.sb_$xy set $first $last
    ::Zoom::OverviewBox
    if {$::state(atlas)} {::ClipBox::Onscreen $::Zoom::W}
    after idle ::Zoom::Expose
}
##+##########################################################################
#
# ::Zoom::OverviewBox -- moves overview box on the grid window
#
proc ::Zoom::OverviewBox {} {
    variable W2
    variable SCREEN

    if {! [winfo exists $W2]} {
        INFO "missing $W2"
        return
    }

    set xy [::Zoom::Canvas2Small $SCREEN(l) $SCREEN(t) $SCREEN(r) $SCREEN(b)]
    $W2 coords over $xy
    ::Zoom::OverviewVisible $xy
    $W2 raise over
}
##+##########################################################################
#
# ::Zoom::OverviewVisible -- keeps center of the overview box visible
#
proc ::Zoom::OverviewVisible {xy} {
    variable W2
    lassign $xy x0 y0 x1 y1
    ;# Coordinates of overview box
    set x [expr {($x0 + $x1) / 2}]              ;# Center of overview box
    set y [expr {($y0 + $y1) / 2}]

    lassign [::Display::GetScreenRect $W2] l t r b
    if {$x <= $r && $y <= $b && $x >= $l && $y >= $t} return ;# Visible
    lassign [$W2 cget -scrollregion] l t r b
    set cw [winfo width $W2]
    set ch [winfo height $W2]

    set xview [expr {(($x - $cw/2.0) - $l) / ($r - $l)}]
    set yview [expr {(($y - $ch/2.0) - $t) / ($b - $t)}]

    $W2 xview moveto $xview
    $W2 yview moveto $yview
}
##+##########################################################################
#
# ::Zoom::GetScreenRect -- gets coordinates of the visible part of the canvas
#
proc ::Zoom::GetScreenRect {} {
    variable SCREEN
    variable W

    lassign [$W cget -scrollregion] sl st sr sb
    set sw [expr {$sr - $sl}]                   ;# Scroll width
    set sh [expr {$sb - $st}]                   ;# Scroll height

    # Get canvas info (could have used scrollbar for this)
    lassign [$W xview] xl xr
    lassign [$W yview] yt yb

    set SCREEN(l) [expr {round($sl + $xl * $sw)}]
    set SCREEN(r) [expr {round($sl + $xr * $sw)}]
    set SCREEN(t) [expr {round($st + $yt * $sh)}]
    set SCREEN(b) [expr {round($st + $yb * $sh)}]

    set SCREEN(w) [expr {$SCREEN(r) - $SCREEN(l)}]
    set SCREEN(h) [expr {$SCREEN(b) - $SCREEN(t)}]

    set SCREEN(rows) [expr {int(ceil($SCREEN(h) / double($SCREEN(tile,size))))}]
    set SCREEN(cols) [expr {int(ceil($SCREEN(w) / double($SCREEN(tile,size))))}]
}
##+##########################################################################
#
# ::Zoom::GetDetails -- gets meta info about road or node
#
proc ::Zoom::GetDetails {what who} {
    variable RINFO

    array unset ::Zoom::RINFO
    set RINFO(what) $what
    set RINFO(who) $who
    if {$what eq "road"} {
        ::Zoom::GetRoadInfo $who
    } elseif {$what eq "node"} {
        ::Zoom::GetNodeInfo $who
    } elseif {$what eq "route"} {
        ::Zoom::GetRouteInfo
    } elseif {$what eq "track"} {
        ::Zoom::GetTrackInfo $who
    } elseif {$what eq "coords"} {
        ::Zoom::GetCoordsInfo $who
    } elseif {$what eq "poi" || $what eq "geo"} {
        ::Zoom::GetPOIInfo $what $who
    }

    ::Zoom::SwapNodeRoad $what
    ::Zoom::DisplayReadOnly
    ::Zoom::IsModified 0
}
##+##########################################################################
#
# ::Zoom::GetRoadInfo -- fills in RINFO w/ data about the road
#
proc ::Zoom::GetRoadInfo {who} {
    variable RINFO

    set RINFO(pts) [::Route::GetXYZ $who]       ;# All the bends in the road
    foreach {. . RINFO(north) RINFO(dist) RINFO(south) RINFO(type) \
                 RINFO(title)} $::roads($who) break
    ::Zoom::GuessDistance
    ::Zoom::GuessClimbing
}
##+##########################################################################
#
# ::Zoom::GetNodeInfo -- fills in RINFO w/ data about the node
#
proc ::Zoom::GetNodeInfo {who} {
    variable RINFO

    set RINFO(pts) [::Route::GetXYZ "" $who]
    lassign [lindex $RINFO(pts) 0] RINFO(title) RINFO(ele) lat lon
    set usgs [lindex $RINFO(pts) 0 8]
    if {$usgs eq {}} {set usgs "0+?"}
    set RINFO(usgs) [::Data::Label $usgs climb 3 2]
}
##+##########################################################################
#
# ::Zoom::GetPOIInfo -- Gets info about a POI
#
proc ::Zoom::GetPOIInfo {what who} {
    variable RINFO
    global poi

    if {$what eq "poi"} {
        lassign $poi($who) RINFO(type) RINFO(title) lat lon RINFO(loc) RINFO(desc)
        set RINFO(pts) [list [list $RINFO(title) ? $lat $lon poi $who]]
        return
    }
    if {$what eq "geo"} {
        lassign $::GPS::wpts($who) lat lon . RINFO(title)
        set RINFO(pts) [list [list $RINFO(title) ? $lat $lon geo $who]]
        return
    }
}
##+##########################################################################
#
# ::Zoom::GetRouteInfo -- fills in RINFO w/ data about the current route
#
proc ::Zoom::GetRouteInfo {} {
   variable RINFO

    set RINFO(pts) [::Route::GetXYZ]
    set RINFO(title) "Current Route"
    set RINFO(dist) $::msg(dist2)
    set RINFO(climb) $::msg(climb2)
    set RINFO(desc) $::msg(desc2)
    set ::Zoom::ZMAP(readonly) 1
}
##+##########################################################################
#
# ::Zoom::GetTrackInfo -- fills RINFO w/ data about a GPS track
#
proc ::Zoom::GetTrackInfo {who} {
    variable RINFO

    set rpts [::GPS::GetXYZ $who]
    set wpts [::GPS::GetWpts]
    set RINFO(pts) [concat $rpts $wpts]

    #set all [::Tracks::GetInfo $who]

    foreach var [list title dist climb desc] val [::Tracks::GetInfo $who] {
        set RINFO($var) $val
    }
    set ::Zoom::ZMAP(readonly) 1
}
##+##########################################################################
#
# ::Zoom::GetCoordsInfo -- fills RINFO w/ data about current coord
# can be called from coordinate locator or directly from map popup
#
proc ::Zoom::GetCoordsInfo {who} {
    variable RINFO

    set RINFO(title) "User Coordinates"
    if {$who eq "map"} {
        lassign $::state(popup) x y
        lassign [::Display::canvas2pos $x $y] . . . . lat lon
        set lat [int2lat $lat]
        set lon [int2lat $lon]
    } else {
        lassign [::Coords::Where] lat lon
    }
    lassign [::Display::PrettyLat $lat $lon] RINFO(lat) RINFO(lon)
    set lat [lat2int {*}$lat]
    set lon [lat2int {*}$lon]

    set RINFO(pts) [list [list "" ? $lat $lon coords "" ""]]
    set ::Zoom::ZMAP(readonly) 1
}
##+##########################################################################
#
# ::Zoom::ShowCore -- debugging routines highlight core cells
# in the status window
#
proc ::Zoom::ShowCore {} {
    variable ZMAP

    foreach cell $ZMAP(core) {
        lassign $cell x y
        ::Zoom::Status $x $y cancel
    }
}
##+##########################################################################
#
# ::Zoom::Close -- cleans up and closes all the zoom windows
#
proc ::Zoom::Close {} {
    ::PGU::Cancel 0 -all
    ::Zoom::Clear
    destroy $::Zoom::T
    ::Atlas::Reparent
}
##+##########################################################################
#
# ::Zoom::Chunk2canvas -- returns x,y of lower left corner of a chunk
#
proc ::Zoom::Chunk2canvas {XX YY {small 0}} {
    variable ZMAP
    variable STATIC
    variable SCREEN

    set z [expr {$small ? $STATIC(small) : 1}]
    set x [expr {$SCREEN(tile,size) * ($XX-$ZMAP(o,x)) / $z}]
    set y [expr {$SCREEN(tile,size) * ($ZMAP(o,y)-$YY) / $z}]
    return [list $x $y]
}
##+##########################################################################
#
# ::Zoom::MoveNode -- moves a route point to the mouse position
#
proc ::Zoom::MoveNode {what tag idx x y} {
    set ::tag $tag ; set ::what $what; set ::idx $idx ; set ::x $x ; set ::y $y
    variable ZMAP
    variable RINFO
    variable W
    variable W2
    variable lcxy                               ;# Last cursor xy

    if {$ZMAP(readonly) || ! $ZMAP(ready)} return
    set cx [$W canvasx $x]
    set cy [$W canvasy $y]
    set cxy [list $cx $cy]

    if {$what eq "down"} {
        set lcxy $cxy
        ::Balloon::Cancel
        return
    } elseif {$what eq "up"} {
        # Enable balloon help
    }

    lassign $lcxy old_cx old_cy
    set lcxy $cxy

    # Move the node
    set dx [expr {$cx - $old_cx}]
    set dy [expr {$cy - $old_cy}]
    $W move $tag $dx $dy
    $W2 move $tag {*}[::Zoom::Canvas2Small $dx $dy]

    # Move the road
    set xy [$W coords road]
    if {$xy ne {}} {
        lset xy [expr {2 * $idx}] $cx
        lset xy [expr {2 * $idx + 1}] $cy
        $W coords road $xy
    }

    set xy [$W2 coords road]
    if {$xy ne {}} {
        foreach {sx sy} [::Zoom::Canvas2Small $cx $cy] break
        lset xy [expr {2 * $idx}] $sx
        lset xy [expr {2 * $idx + 1}] $sy
        $W2 coords road $xy
    }

    # Update the points list
    # NB. use exact center instead of cx,cy
    lassign [::Data::BboxCenter [$W bbox $tag]] x0 y0
    lassign [::Klippy::Canvas2LatLon $x0 $y0] lat lon

    lset RINFO(pts) $idx 2 $lat
    lset RINFO(pts) $idx 3 $lon
    if {[lindex $RINFO(pts) $idx 1] ne "?"} {
        lset RINFO(pts) $idx 1 ?                ;# Destroy elevation info
        $W delete ppt_$idx
    }
    ::Zoom::IsModified 1
    ::Zoom::GuessDistance
    ::Zoom::GuessClimbing

    set RINFO(usgs) ?
}
##+##########################################################################
#
# ::Zoom::GuessDistance -- how long the road is
#
proc ::Zoom::GuessDistance {} {
    variable RINFO
    variable ZMAP

    set RINFO(guess,dist) ""
    if {$ZMAP(what) ne "road"} return

    set lat0 -1
    set dist 0

    set idx -1
    foreach pt $RINFO(pts) {
        incr idx
        lassign $pt . . lat1 lon1

        if {$lat0 != -1} {
            set d [::Data::Distance $lat0 $lon0 $lat1 $lon1]
            set dist [expr {$dist + $d}]
        }
        set lat0 $lat1
        set lon0 $lon1
    }
    set RINFO(guess,dist) [::Data::Convert [Round1 $dist] dist]
}
##+##########################################################################
#
# ::Zoom::GuessClimbing -- computes climbing for a road smoothing
# out small bumps.
#
proc ::Zoom::GuessClimbing {} {
    variable RINFO
    variable ZMAP

    set RINFO(guess,north) "?"
    set RINFO(guess,south) "?"
    if {$ZMAP(what) ne "road"} return

    set z {}
    foreach pt $RINFO(pts) {
        set alt [lindex $pt 1]
        if {[string is double -strict $alt]} {
            lappend z $alt
        }
    }
    if {[llength $z] < 2} return                ;# Not enough data points

    lassign [::Data::PreCalcClimb $z] climb desc
    set RINFO(guess,north) $desc
    set RINFO(guess,south) $climb
}
##+##########################################################################
#
# ::Zoom::NewMag -- handles changing zoom level
#
proc ::Zoom::NewMag {delta} {
    variable ZMAP
    variable DS

    if {! $ZMAP(ready)} return
    if {$delta < 0 && $DS(mag) > 10} {
        incr DS(mag) -1
    } elseif {$delta > 0 && $DS(mag) < 23} {
        incr DS(mag)
    }

    if {$DS(mag) == $ZMAP(mag)} return     ;# Hasn't changed
    ::Zoom::MakeMap
}
##+##########################################################################
#
# NewTheme -- Handles changing between topo and aerial views
#
proc ::Zoom::NewTheme {} {
    variable ZMAP
    variable DS

    return
# KPV    if {$DS(theme) eq "topo"} {
# KPV        raise $::Zoom::T.left.b-2_cover         ;# Hide illegal mag level
# KPV        raise $::Zoom::T.left.b-1_cover
# KPV        raise $::Zoom::T.left.b0_cover
# KPV        if {$DS(mag) < 10} {                    ;# Not legal mag value
# KPV            set DS(mag) 15
# KPV        }
# KPV    } elseif {$DS(theme) eq "aerial"} {
# KPV        raise $::Zoom::T.left.b-2_cover         ;# Hide illegal mag level
# KPV        raise $::Zoom::T.left.b-1_cover
# KPV        lower $::Zoom::T.left.b0_cover
# KPV        if {$DS(mag) < 0} {                     ;# Not legal mag value
# KPV            set DS(mag) 0
# KPV        }
# KPV        if {$DS(mag) == 1} {
# KPV            set DS(mag) 0
# KPV        }
# KPV    } else {                                    ;# Urban
# KPV        lower $::Zoom::T.left.b-2_cover
# KPV        lower $::Zoom::T.left.b-1_cover
# KPV        lower $::Zoom::T.left.b0_cover
# KPV        if {$DS(mag) == 1} {
# KPV            set DS(mag) 0
# KPV        }
# KPV    }
# KPV    if {! $ZMAP(ready)} return
# KPV    if {$DS(theme) eq $ZMAP(theme) && $DS(mag) + 10 == $ZMAP(mag)} return
# KPV    ::Zoom::MakeMap
    return
}
##+##########################################################################
#
# ::Zone::DoDisplay -- Creates our GUI
#
proc ::Zoom::DoDisplay {} {
    global state
    variable T
    variable W
    variable W2
    variable DS
    variable SCREEN
    variable RINFO

    if {[winfo exists $T]} {
        ::Zoom::Clear
        raise $T
        set txt "Save [string totitle $::Zoom::ZMAP(what)] Data"
        .sr_popup entryconfig 9 -label $txt
        return
    }

    destroy $T
    toplevel $T
    wm geom $T +10+10
    wm title $T "$::state(progname) Zoom"
    wm transient $T .
    wm protocol $T WM_DELETE_WINDOW ::Zoom::Close

    set W "$T.c"
    set W2 "$T.zgrid.c"

    ::tk::frame $T.main -borderwidth 2 -relief ridge -background beige
    ::my::frame $T.ctrl -borderwidth 2 -relief ridge -pad 5

    ::my::label $T.title -background beige -borderwidth 0 \
        -font bolderFont -anchor c -textvariable ::Zoom::DS(title) -pad 5
    ::tk::frame $T.left -bg beige
    ::ttk::scrollbar $T.sb_x -command [list $W xview] -orient horizontal
    ::ttk::scrollbar $T.sb_y -command [list $W yview] -orient vertical
    canvas $W -width $SCREEN(w) -height $SCREEN(h) -highlightthickness 0 \
        -bg $::Zoom::COLORS(empty) -bd 0
    $W config -xscrollcommand [list ::Zoom::MyScroller x]
    $W config -yscrollcommand [list ::Zoom::MyScroller y]
    $W config -scrollregion [list 0 0 [$W cget -width] [$W cget -height]]

    # Road info
    ::ttk::frame $T.data
    ::Zoom::MakeRoadFrame $T.data
    ::Zoom::MakeNodeFrame $T.data
    ::Zoom::MakePOIFrame $T.data
    ::Zoom::MakeGEOFrame $T.data
    ::Zoom::MakeRouteFrame $T.data route
    ::Zoom::MakeRouteFrame $T.data track
    ::Zoom::MakeCoordsFrame $T.data

    # Map status
    ::my::labelframe $T.zgrid -text "Map Status"
    set W2 "$T.zgrid.c"
    ::ttk::scrollbar $T.zgrid.sb_x -command [list $W2 xview] -orient horizontal
    ::ttk::scrollbar $T.zgrid.sb_y -command [list $W2 yview] -orient vertical
    canvas $W2 -width 300 -height 200 -yscrollcommand [list $T.zgrid.sb_y set] \
        -xscrollcommand [list $T.zgrid.sb_x set] -highlightthickness 0 \
        -scrollregion {0 0 200 200}
    ::Display::TileBGFix $W2
    grid rowconfigure $T.zgrid 0 -minsize 10
    grid $W2 $T.zgrid.sb_y -sticky news -row 1
    grid $T.zgrid.sb_x -sticky news
    grid rowconfigure $T.zgrid 1 -weight 1
    grid columnconfigure $T.zgrid 0 -weight 1

    # Legend
    ::my::labelframe $T.zlegend -text "Map Legend"
    set WW $T.zlegend
    set items {Queued queued Fetching pending Retrieved done  \
                   Web web Cache cache Empty empty \
                   Timeout timeout Failure failure Discarded discarded}
    set row 1
    set col 0
    foreach {txt color} $items {
        ::tk::label $WW.$color -text $txt -anchor c -bd 1 -relief solid \
            -bg $::Zoom::COLORS($color) -font boldFont
        if {$::Zoom::COLORS($color) eq "blue"} { $WW.$color config -fg white}
        grid $WW.$color -row $row -column $col -sticky ew -padx 5 -pady 2
        if {[incr col] >= 3} {
            incr row
            set col 0
        }
    }
    grid columnconfigure $WW {0 1 2} -weight 1 -uniform a
    grid rowconfigure $WW 100 -minsize 5

    # Internet statistics
    ::my::labelframe $T.stats -text "Internet Statistics" -pad 5
    ::my::label $T.lqueue -text Queued -anchor w
    ::my::label $T.equeue -textvariable ::Zoom::stats(queued) -relief sunken \
        -width 5 -anchor c
    ::my::label $T.lload -text Loading -anchor w
    ::my::label $T.eload -textvariable ::Zoom::stats(loading) -relief sunken \
        -width 5 -anchor c
    ::my::label $T.lretrieve -text Retrieved -anchor w
    ::my::label $T.eretrieve -textvariable ::Zoom::stats(retrieved) \
        -width 5 -relief sunken -anchor c
    ::my::label $T.lrendered -text Rendered -anchor w
    ::my::label $T.erendered -textvariable ::Zoom::stats(rendered) \
        -width 5 -relief sunken -anchor c
    grid $T.lqueue $T.equeue -in $T.stats -sticky ew
    grid $T.lload $T.eload -in $T.stats -sticky ew
    grid $T.lretrieve $T.eretrieve -in $T.stats -sticky ew
    grid $T.lrendered $T.erendered -in $T.stats -sticky ew
    grid columnconfigure $T.stats 0 -weight 1
    grid columnconfigure $T.stats 5 -minsize 5

    # Buttons
    ::my::frame $T.buttons -borderwidth 2 -relief ridge
    ::ttk::button $T.buttons.print -text "Print" -command [list ::Print::Dialog zoom]
    ::ttk::button $T.buttons.save -text "Update" -command ::Zoom::Save -state disabled
    ::ttk::button $T.buttons.dismiss -text "Dismiss" -command ::Zoom::Close
    ::ttk::button $T.buttons.view -text "Google Maps" -command [list ::Zoom::Google zoom]

    grid x $T.buttons.print x $T.buttons.view x -pady 5 -sticky ew
    grid x $T.buttons.save x $T.buttons.dismiss x -pady 5 -sticky ew
    grid columnconfigure $T.buttons {0 2 4} -weight 1
    grid columnconfigure $T.buttons {1 3} -uniform a

    # Grid outer frames
    grid $T.main $T.ctrl -sticky news
    grid columnconfigure $T 0 -weight 1
    grid rowconfigure $T 0 -weight 1

    # Grid main window
    grid x $T.title x -in $T.main -sticky news -row 0
    grid $T.left $W $T.sb_y -in $T.main -sticky news
    grid ^ $T.sb_x x -in $T.main -sticky ew
    grid columnconfigure $T.main 1 -weight 1
    grid rowconfigure $T.main 1 -weight 1


    # Grid the control frame
    grid $T.data -in $T.ctrl -sticky news -pady 5
    grid $T.zgrid -in $T.ctrl -sticky news -pady 5
    grid $T.zlegend -in $T.ctrl -sticky news -pady 5
    grid $T.stats -in $T.ctrl -sticky news -pady 5
    grid rowconfigure $T.ctrl 100 -weight 1
    grid $T.buttons -in $T.ctrl -sticky news -row 101

    # Set up bindings
    if {1} {
        set bMiddle [expr {$state(macosx) ? "3" : "2"}]
        bind $W <${bMiddle}> [bind Text <2>]                 ;# Enable dragging w/ <2>
        bind $W <B${bMiddle}-Motion> [bind Text <B2-Motion>]
        $W bind img <1> [bind $W <${bMiddle}>]
        $W bind img <B1-Motion> [bind $W <B${bMiddle}-Motion>]

        bind $W2 <${bMiddle}> [bind Text <2>]                ;# Enable dragging w/ <2>
        bind $W2 <B${bMiddle}-Motion> [bind Text <B2-Motion>]
        $W2 bind img <1> [bind $W2 <${bMiddle}>]
        $W2 bind img <B1-Motion> [bind $W2 <B${bMiddle}-Motion>]
    }
    if {$::state(su)} {
        catch {bind .zoom <Key-.> ::Zoom::Save&Close}
    }
    ::Zoom::DrawScale $T.left

    destroy .sr_popup
    menu .sr_popup -tearoff 0
    .sr_popup add command -label "Add New Route Point" -underline 0 \
        -command [list ::Zoom::RoutePoint add]
    .sr_popup add command -label "Delete this Route Point" -underline 0 \
        -command [list ::Zoom::RoutePoint delete]
    .sr_popup add command -label "Split Road at Point" -underline 0 \
        -command [list ::Zoom::RoutePoint "split"]
    .sr_popup add separator
    .sr_popup add command -label "Add Elevation" -underline 4 \
        -command [list ::Zoom::RoutePoint elevation]
    .sr_popup add command -label "Insert Waypoint" -underline 0 \
        -command [list ::Zoom::RoutePoint insert]
    .sr_popup add command -label "Create Arrow" -underline 0 \
        -command [list ::Arrow::Dialog $::Zoom::W "" {0 0}]
    .sr_popup add command -label "Google Maps" -underline 0 \
        -command [list ::Zoom::RoutePoint google]
    .sr_popup add separator
    .sr_popup add command -label "Delete All Waypoints" -underline 7 \
        -command [list ::Zoom::RoutePoint deleteall]
    if {$::state(su)} {
        .sr_popup add separator
        set txt "Save [string totitle $::Zoom::ZMAP(what)] Data"
        .sr_popup add command -label $txt -command ::Zoom::Save -underline 0
    }
    update
}
##+##########################################################################
#
# ::Zoom::Save&Close
#
proc ::Zoom::Save&Close {} {
    ::Zoom::USGSAllWaypoints
    ::Zoom::Save
    ::Save::SaveUserDataCmd 1
    ::Zoom::Close
    #puts "::Zoom::Save&Close: dist: $::Zoom::RINFO(dist) north: $::Zoom::RINFO(north) south: $::Zoom::RINFO(south)"
}
##+##########################################################################
#
# ::Zoom::MakeRoadFrame -- draws the frame w/ road title, distance & climbing
#
proc ::Zoom::MakeRoadFrame {parent} {
    set PW $parent.road
    ::my::labelframe $PW -text "Road Data"

    set tw 8
    set a [list -width $tw -justify center -state readonly]

    ::my::label $PW.atitle -text "Data"
    ::my::label $PW.etitle -text "Est."

    ::my::entry $PW.title -textvariable ::Zoom::RINFO(title) -justify center
    ::my::label $PW.ldist -text "Distance" -anchor w
    ::my::entry $PW.edist -textvariable ::Zoom::RINFO(dist) -width $tw -justify center
    ::my::entry $PW.gdist -textvariable ::Zoom::RINFO(guess,dist) {*}$a
    ::my::label $PW.lnorth -text "North climbing" -anchor w
    ::my::entry $PW.enorth -textvariable ::Zoom::RINFO(north) -width $tw -justify center
    ::my::entry $PW.gnorth -textvariable ::Zoom::RINFO(guess,north) {*}$a
    ::my::label $PW.lsouth -text "South climbing" -anchor w
    ::my::entry $PW.esouth -textvariable ::Zoom::RINFO(south) -width $tw -justify center
    ::my::entry $PW.gsouth -textvariable ::Zoom::RINFO(guess,south) {*}$a

    ::ttk::button $PW.save -text "Update" -command ::Zoom::Save
    ::ttk::button $PW.usgs -image ::img::star -command ::Zoom::USGSAllWaypoints
    bind $PW.usgs <Button-3> ::Zoom::Save&Close
    bind $PW.usgs <Button-2> ::Zoom::Save&Close
    ::Balloon::Create $PW.usgs static usgs "Query USGS for all waypoint elevation" ""

    set ::Zoom::DS($PW,focus) $PW.edist

    grid $PW.title - - -sticky ew -pady 5 -padx 5
    grid $PW.ldist $PW.edist -sticky ew -padx 5 -row 2
    grid $PW.lnorth $PW.enorth -sticky ew -padx 5
    grid $PW.lsouth $PW.esouth -sticky ew -padx 5
    if {1 || $::Zoom::ZMAP(guessable)} {
        grid x $PW.atitle $PW.etitle -row 1
        grid $PW.gdist  -row 2 -column 2 -sticky ew -padx {0 5}
        grid $PW.gnorth -row 3 -column 2 -sticky ew -padx {0 5}
        grid $PW.gsouth -row 4 -column 2 -sticky ew -padx {0 5}
        grid $PW.usgs   -row 5 -column 2 -padx {0 5}
    }
    grid $PW.save - - -row 5 -pady 5
    grid columnconfigure $PW 0 -weight 1
}
##+##########################################################################
#
# ::Zoom::MakeNodeFrame -- draws the frame w/ node data
#
proc ::Zoom::MakeNodeFrame {parent} {
    set PW $parent.node
    ::my::labelframe $PW -text "Node Data"

    ::my::entry $PW.title -textvariable ::Zoom::RINFO(title) -justify center
    ::my::label $PW.lele -text "Elevation" -anchor w
    ::my::entry $PW.eele -textvariable ::Zoom::RINFO(ele) -width 20 -justify center
    ::my::label $PW.luele -text "USGS Elevation" -anchor w
    ::my::frame $PW.euele -borderwidth 2 -relief sunken
    ::my::label $PW.euele.v -textvariable ::Zoom::RINFO(usgs) \
        -background grey80 -anchor c \
        -relief sunken -borderwidth 0 -justify center
    ::ttk::button $PW.euele.star -image ::img::star -command ::Zoom::GoUSGS
    pack $PW.euele.v -side left -fill both -expand 1
    pack $PW.euele.star -side right

    set txt "Query USGS for elevation"
    ::Balloon::Create $PW.euele.star zoom usgs $txt $txt

    ::ttk::button $PW.save -text Update -command ::Zoom::Save -state disabled
    set ::Zoom::DS($PW,focus) $PW.eele

    grid $PW.title - -sticky ew -pady 5 -padx 5
    grid $PW.lele $PW.eele -sticky ew -padx 5
    grid $PW.luele $PW.euele -sticky ew -padx 5
    grid $PW.save - -pady 5
    grid columnconfigure $PW 0 -weight 1
}
##+##########################################################################
#
# ::Zoom::MakePOIFrame -- draws the frame w/ POI data
#
proc ::Zoom::MakePOIFrame {parent} {
    set PW $parent.poi
    ::my::labelframe $PW -text "POI Data"

    ::my::entry $PW.title -textvariable ::Zoom::RINFO(title) -justify center
    ::my::entry $PW.desc -textvariable ::Zoom::RINFO(desc) -justify center

    ::ttk::button $PW.save -text Update -state disabled -command ::Zoom::Save
    set ::Zoom::DS($PW,focus) $PW.title

    grid $PW.title - -sticky ew -pady 5 -padx 5
    grid $PW.desc - -sticky ew -pady 5 -padx 5
    grid $PW.save - -pady 5
    grid columnconfigure $PW 0 -weight 1
}
##+##########################################################################
#
# ::Zoom::MakeGEOFrame -- draws the frame w/ GEO data
#
proc ::Zoom::MakeGEOFrame {parent} {
    set PW $parent.geo
    ::my::labelframe $PW -text "Geocaching Data"

    ::my::entry $PW.title -textvariable ::Zoom::RINFO(title) -justify center

    ::ttk::button $PW.save -text Update -state disabled -command ::Zoom::Save
    set ::Zoom::DS($PW,focus) $PW.title

    grid $PW.title - -sticky ew -pady 5 -padx 5
    grid $PW.save - -pady 5
    grid columnconfigure $PW 0 -weight 1
}
##+##########################################################################
#
# ::Zoom::MakeRouteFrame -- draws the frame w/ track info
#
proc ::Zoom::MakeRouteFrame {parent {what route}} {
    set PW $parent.$what
    ::my::labelframe $PW -text "[string totitle $what] Data"

    ::my::entry $PW.title -textvariable ::Zoom::RINFO(title) -justify center
    ::my::label $PW.ldist -text "Distance" -anchor w
    ::my::entry $PW.edist -textvariable ::Zoom::RINFO(dist) -width 10 -justify center
    ::my::label $PW.lclimb -text "Climbing" -anchor w
    ::my::entry $PW.eclimb -textvariable ::Zoom::RINFO(climb) -width 10 -justify center
    ::my::label $PW.ldesc -text "Descending" -anchor w
    ::my::entry $PW.edesc -textvariable ::Zoom::RINFO(desc) -width 10 -justify center
    set ::Zoom::DS($PW,focus) $PW.edist

    ::ttk::button $PW.save -text "Update" -command ::Zoom::Save

    grid $PW.title - -sticky ew -pady 5 -padx 5
    grid $PW.ldist $PW.edist -sticky ew -padx 5
    grid $PW.lclimb $PW.eclimb -sticky ew -padx 5
    grid $PW.ldesc $PW.edesc -sticky ew -padx 5
    #grid $PW.save - -pady 5
    grid columnconfigure $PW 0 -weight 1
}
##+##########################################################################
#
# ::Zoom::MakeCoordsFrame -- draws the frame w/ user coordinates
#
proc ::Zoom::MakeCoordsFrame {parent} {
    set PW $parent.coords
    ::my::labelframe $PW -text "Coordinate Data"

    ::my::entry $PW.title -textvariable ::Zoom::RINFO(title) -justify center
    ::my::label $PW.llat -text "Latitude:"  -anchor w
    ::my::entry $PW.lat -textvariable ::Zoom::RINFO(lat) -justify center
    ::my::label $PW.llon -text "Longitude:" -anchor w
    ::my::entry $PW.lon -textvariable ::Zoom::RINFO(lon) -justify center

    ::ttk::button $PW.save -text Update -state disabled -command ::Zoom::Save
    set ::Zoom::DS($PW,focus) $PW.title

    grid $PW.title - -sticky ew -pady 5 -padx 5
    grid $PW.llat $PW.lat -sticky ew -padx 5
    grid $PW.llon $PW.lon -sticky ew -padx 5
    grid columnconfigure $PW 0 -weight 1
}
##+##########################################################################
#
# ::Zoom::DisplayReadOnly -- updates display for readonly mode
#
proc ::Zoom::DisplayReadOnly {} {
    set w ${::Zoom::T}.data
    set how [expr {$::Zoom::ZMAP(readonly) ? "disabled" : "normal"}]
    set how [expr {$::Zoom::ZMAP(readonly) ? "readonly" : "normal"}]
    ::Zoom::DisplayReadOnly2 $w $how
}
proc ::Zoom::DisplayReadOnly2 {WW how} {
    foreach w [winfo children $WW] {
        if {[string match "*data.road.g*" $w]} continue
        catch {$w config -state $how}
        ::Zoom::DisplayReadOnly2 $w $how
    }
}
##+##########################################################################
#
# ::Zoom::GoUSGS -- initiates querying USGS for elevation of a node
#
proc ::Zoom::GoUSGS {} {
    variable RINFO

    lassign [lindex $RINFO(pts) 0] . . lat lon
    set latlon [concat [int2lat $lat] [int2lat $lon]]
    set usgs [::USGS::Dialog $::Zoom::T $latlon]

    # First convert to external units
    set usgs [::Data::Convert $usgs climb]
    if {! [string is double -strict $usgs]} {
        set RINFO(usgs) $usgs
        return
    }

    set RINFO(usgs) [::Data::Label $usgs climb 3]
    if {$::Zoom::ZMAP(readonly)} return
    if {[string is double -strict $RINFO(ele)]} return
    set RINFO(ele) $usgs
}
##+##########################################################################
#
# ::Zoom::DrawScale -- creates our zoom buttons
#
proc ::Zoom::DrawScale {WW} {
    variable STATIC

    if {[lsearch [image names] ::img::plus] == -1} {
        image create bitmap ::img::plus -foreground white -background darkblue \
            -data {
                #define plus_width 20
                #define plus_height 20
                static char plus_bits = {
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x3f, 0x00, 0xe0,
                    0x7f, 0x00, 0x70, 0xe0, 0x00, 0x38, 0xc0, 0x00, 0x18, 0x86,
                    0x01, 0x1c, 0x86, 0x03, 0x0c, 0x06, 0x03, 0xcc, 0x3f, 0x03,
                    0xcc, 0x3f, 0x03, 0x0c, 0x06, 0x03, 0x1c, 0x86, 0x03, 0x18,
                    0x86, 0x01, 0x38, 0xc0, 0x01, 0x70, 0xe0, 0x00, 0xe0, 0x7f,
                    0x00, 0xc0, 0x3f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
            } -maskdata {
                #define mask_width 20
                #define mask_height 20
                static char mask_bits = {
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
            }
        image create bitmap ::img::minus -foreground white \
            -background darkblue -data {
                #define minus_width 20
                #define minus_height 20
                static char minus_bits = {
                    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xc0, 0x3f, 0x00, 0xe0,
                    0x7f, 0x00, 0x70, 0xe0, 0x00, 0x38, 0xc0, 0x00, 0x18, 0x80,
                    0x01, 0x1c, 0x80, 0x03, 0x0c, 0x00, 0x03, 0xcc, 0x3f, 0x03,
                    0xcc, 0x3f, 0x03, 0x0c, 0x00, 0x03, 0x1c, 0x80, 0x03, 0x18,
                    0x80, 0x01, 0x38, 0xc0, 0x01, 0x70, 0xe0, 0x00, 0xe0, 0x7f,
                    0x00, 0xc0, 0x3f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
            } -maskdata {
                #define mask_width 20
                #define mask_height 20
                static char mask_bits = {
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
                    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
            }
        image create photo ::img::button -width 18 -height 6
    }

    ::tk::label $WW.zin -text "Zoom\nIn" -font {{MS Sans Serif} 6 bold} -bg beige \
        -activebackground darkblue
    grid $WW.zin -row 1 -sticky s
    ::tk::button $WW.bp -image ::img::plus -bg darkblue -takefocus 0 \
        -activebackground darkblue -command {::Zoom::NewMag -1}
    ::Balloon::Create $WW.bp zoom plus "Zoom in by 2x" ""
    grid  $WW.bp -pady 2 -row 2
    for {set i 10} {$i < 23} {incr i} {
        ::tk::radiobutton $WW.b$i \
            -bg lightblue \
            -image ::img::button \
            -command [list ::Zoom::NewMag 0] \
            -overrelief groove \
            -variable ::Zoom::DS(mag) \
            -value $i \
            -activebackground darkblue \
            -indicatoron 0 \
            -takefocus 0 \
            -selectcolor darkblue
        ::Balloon::Create $WW.b$i zoom b$i "Zoom $i" ""
        grid $WW.b$i -pady 2 -row [expr {$i+3+2}]
        if {$i <= 0} {
            canvas $WW.b${i}_cover -bd 0 -highlightthickness 0 -bg beige
            place $WW.b${i}_cover -in $WW.b$i -bordermode outside -x 0 -y 0 \
                -relheight 1 -relwidth 1
        }
    }
    ::tk::button $WW.bm -image ::img::minus -bg darkblue \
        -activebackground darkblue -takefocus 0 -command {::Zoom::NewMag 1}
    grid $WW.bm -pady 2
    ::Balloon::Create $WW.bm zoom minus "Zoom out by 2x" ""
    ::tk::label $WW.zout -text "Zoom\nOut" -font [$WW.zin cget -font] -bg beige \
        -activebackground darkblue
    grid $WW.zout -pady {0 20}

    foreach w {topo aerial urban} \
        msg {{View topo map} {View aerial photograph} \
                 "View urban photograph\n(not available everywhere)"} {
        ::tk::radiobutton $WW.$w -text [string totitle $w] \
            -command ::Zoom::NewTheme \
            -font [$WW.zin cget -font] \
            -indicatoron 0 \
            -relief raised \
            -activeforeground white \
            -activebackground darkblue \
            -selectcolor darkblue \
            -fg white \
            -bg lightblue \
            -takefocus 0 \
            -variable ::Zoom::DS(theme) \
            -value $w
        ::Balloon::Create $WW.$w zoom $w $msg ""
        grid $WW.$w -pady 2 -sticky ew -padx 5
    }
    ::Zoom::NewTheme
}
##+##########################################################################
#
# ::Zoom::SwapNodeRoad -- swaps the node info and the road info frames
#
proc ::Zoom::SwapNodeRoad {what} {
    set parent ${::Zoom::T}.data
    set w [pack slaves $parent]                 ;# Who is there now
    set w2 "$parent.$what"                      ;# Who should be there
    focus $::Zoom::DS($w2,focus)
    catch {$::Zoom::DS($w2,focus) icursor end}

    if {$w eq $w2} return
    pack forget $w

    if {[winfo exists $w2]} {
        pack $w2 -side top -fill both -expand 1
    }
}
##+##########################################################################
#
# ::Zoom::Expose -- called when window scrolls, sets up after event to handle it
#
proc ::Zoom::Expose {} {
    variable FETCH

    after cancel $FETCH(aid)
    set FETCH(aid) [after 200 ::Zoom::_Expose]
}
##+##########################################################################
#
# ::Zoom::_Expose -- called when window scrolls, updates visible queue
#
proc ::Zoom::_Expose {} {
    variable FETCH
    variable ZMAP

    if {! $ZMAP(ready)} {                       ;# For BIG zooms, this gets
        ::Zoom::Expose                          ;# called too early
        return
    }
    set FETCH(q,visible) [::Klippy::Fetch::GetVisibleTiles]
    if {$FETCH(q,visible) ne {}} {
        after idle ::Zoom::RunAllQueues
    }
}
##+##########################################################################
#
# ::Zoom::GetFilename -- returns name of where to store the map file
#
proc ::Zoom::GetFilename {XX YY} {
    variable STATIC
    variable ZMAP

    set fname "${XX}_${YY}_$ZMAP(zone).jpg"
    set dirname [file join $STATIC(cache) $ZMAP(theme) $ZMAP(mag) $XX]
    if {! [file isdirectory $dirname]} {
        file mkdir $dirname
        if {! [file isdirectory $dirname]} {
            WARN "Can't create directory '$dirname'"
            set ZMAP(nofetch) 1
            return ""
        }
    }
    set fname [file join $dirname $fname]
    return $fname
}
proc ::Zoom::GetIName {XX YY} {
    set fname [::Zoom::GetFilename $XX $YY]
    set iname "::zoom::[file rootname [file tail $fname]]"
    return $iname
}
##+##########################################################################
#
# ::Zoom::GetURL -- return the url needed to fetch a particular map
#
proc ::Zoom::GetURL {XX YY} {
    variable STATIC
    variable ZMAP

    set arg "T=$STATIC(rtheme,$ZMAP(theme))&S=$ZMAP(mag)&X=$XX&y=$YY"
    append arg "&Z=$ZMAP(zone)"
    set url "$STATIC(url2)?$arg"
    return $url
}
proc ::Zoom::MakeGrayscale {img} {
    set w [image width $img]
    set h [image height $img]
    image create photo ::zoom::tmp -width $w -height $h
    ::zoom::tmp config -data [$img data -format jpeg -grayscale]
    $img blank
    $img copy ::zoom::tmp
    image delete ::zoom::tmp
}
##+##########################################################################
#
# Status -- displays status of a cell and its fetching state
# PGS how: queued pending cancel timeout failure done
# zoom how: cache web
#
proc ::Zoom::Status {XX YY how} {
    variable W
    variable W2
    variable stats
    variable COLORS

    if {! [winfo exists $W]} return
    $W itemconfig cell$XX,$YY -fill $COLORS($how)
    $W2 itemconfig cell$XX,$YY -fill $COLORS($how)

    if {$how eq "queued"} {
        incr stats(queued)
    } elseif {$how eq "pending"} {
        incr stats(queued) -1
        incr stats(loading)
    } elseif {$how eq "done"} {
        incr stats(loading) -1
        incr stats(retrieved)
    } elseif {$how eq "failure" || $how eq "cancel"} {
        incr stats(loading) -1
    }
}
##+##########################################################################
#
# ::Zoom::RunAllQueues -- empties the visible and/or core queues
#
proc ::Zoom::RunAllQueues {} {
    variable FETCH
    variable STATIC

    set qlen [::PGU::Statistics 0 qlen]
    set n [expr {$STATIC(maxFetch) - $qlen}]

    set cnt [::Klippy::Fetch::RunOneQueue visible $n]
    incr cnt [::Klippy::Fetch::RunOneQueue core [expr {$n - $cnt}]]
    after idle ::PGU::Launch 0
    return $cnt
}
##+##########################################################################
#
# ::Zoom::DoPopupMenu -- puts up the right-click popup menu
#
proc ::Zoom::DoPopupMenu {x y what {who ""}} {
    variable W
    variable DS
    variable ZMAP

    set DS(popup,cxy) [list [$W canvasx $x] [$W canvasy $y]]
    set DS(popup,what) $what
    set DS(popup,who) $who

    # Short circuit shortcuts
    if {$what eq "add" || $what eq "delete"} {
        ::Zoom::RoutePoint $what
        return
    }

    # 0 = new route point
    # 1 = delete
    # 2 = split
    # 3
    # 4 = elevation
    # 5 = insert waypoint
    # 6 = arrow
    # 7 = google
    # 8
    # 9 = delete all
    # 10
    # 11 = save

    set isRtept [expr {$what eq "rtept"}]
    set notRtept [expr {$what ne "rtept"}]
    set isMap [expr {$what eq "map"}]
    set ss(0) disabled ; set ss(1) normal

    .sr_popup entryconfig 0 -state $ss($notRtept)
    .sr_popup entryconfig 1 -state $ss($isRtept)
    .sr_popup entryconfig 2 -state $ss($notRtept)
    .sr_popup entryconfig 4 -state $ss($isRtept)
    .sr_popup entryconfig 5 -state $ss($notRtept)
    if {$what eq "arrow"} {
        .sr_popup entryconfig 6 -label "Update Arrow" -state normal \
            -command [list ::Arrow::Dialog $Zoom::W $who]
    } else {
        .sr_popup entryconfig 6 -label "Create Arrow" -state $ss($isMap) \
            -command [list ::Arrow::Dialog $::Zoom::W "" $DS(popup,cxy)]
    }
    .sr_popup entryconfig 7 -state normal
    .sr_popup entryconfig 9 -state normal

    if {$ZMAP(readonly)} {
        .sr_popup entryconfig 0 -state disabled
        .sr_popup entryconfig 1 -state disabled
        .sr_popup entryconfig 4 -state disabled
        .sr_popup entryconfig 5 -state disabled
        .sr_popup entryconfig 9 -state disabled
    }
    tk_popup .sr_popup [winfo pointerx $W] [winfo pointery $W] \
        [expr {$what eq "road" ? 0 : ""}]
}
##+##########################################################################
#
# RoutePoint -- handles adding or deleting route points
#
proc ::Zoom::RoutePoint {what} {
    variable RINFO
    variable DS

    if {$what eq "delete"} {
        set RINFO(pts) [lreplace $RINFO(pts) $DS(popup,who) $DS(popup,who)]
        ::Zoom::IsModified 1
        ::Klippy::DrawPoints
        ::Zoom::GuessDistance
        ::Zoom::GuessClimbing
    } elseif {$what eq "add" || $what eq "insert"} {
        lassign [::Zoom::FindSplit] idx seg
        if {$what eq "insert"} {
            set xy [::Data::NearestPointOnLine {*}$DS(popup,cxy) {*}$seg]
            lassign [::Klippy::Canvas2LatLon {*}$xy] lat lon
        } else {
            lassign [::Klippy::Canvas2LatLon {*}$DS(popup,cxy)] lat lon
        }

        set pt [list {} ? $lat $lon routepoint $RINFO(who) {} added]
        set RINFO(pts) [linsert $RINFO(pts) $idx $pt]
        ::Zoom::IsModified 1
        ::Klippy::DrawPoints
        ::Zoom::GuessDistance
        ::Zoom::GuessClimbing
    } elseif {$what eq "elevation"} {
        ::Zoom::UpdateRoutePoint $DS(popup,who)
        ::Zoom::GuessClimbing
    } elseif {$what eq "split"} {
        #::Zoom::Close
        set ::state(popup,what) "zoom"
        set ::state(popup,who) $RINFO(who)
        set ::state(popup,latlon) [::Klippy::Canvas2LatLon {*}$DS(popup,cxy)]
        ::Edit::CreateSplit
    } elseif {$what eq "google"} {
        set ll [::Klippy::Canvas2LatLon {*}$DS(popup,cxy)]
        ::Zoom::Google zoompoint $ll
    } elseif {$what eq "deleteall"} {
        set RINFO(pts) [list [lindex $RINFO(pts) 0] [lindex $RINFO(pts) end]]
        ::Zoom::IsModified 1
        ::Klippy::DrawPoints
        ::Zoom::GuessDistance
        ::Zoom::GuessClimbing
    }
}
##+##########################################################################
#
# ::Zoom::IsModified -- called whenever modified status changes
#
proc ::Zoom::IsModified {onoff args} {
    set s [expr {$onoff ? "normal" : "disabled"}]

    if {! [winfo exists ${::Zoom::T}]} return
    foreach w [winfo child ${::Zoom::T}.data] {
        $w.save config -state $s
        if {[winfo exists $w.usgs]} {
            $w.usgs config -state $s
        }
    }
    .sr_popup entryconfig 9 -state $s
    ${::Zoom::T}.buttons.save config -state $s
}
##+##########################################################################
#
# ::Zoom::FindSplit -- finds which leg the split point should be made on
#
proc ::Zoom::FindSplit {} {
    variable W
    variable DS

    foreach {cx cy} $DS(popup,cxy) break

    set xy [$W coords road]
    set best 0
    set dist 999999
    set seg {}
    for {set i 0} {$i+2 < [llength $xy]} {incr i 2} {
        foreach {x0 y0 x1 y1} [lrange $xy $i [expr {$i+3}]] break
        set d [::Data::DistanceToLine $cx $cy $x0 $y0 $x1 $y1]
        if {$d < $dist} {
            set dist $d
            set best $i
            set seg [list $x0 $y0 $x1 $y1]
        }
    }
    set best [expr {($best / 2) + 1}]
    return [list $best $seg]
}
##+##########################################################################
#
# ::Zoom::UpdateRoutePoint -- dialog to add elevation to a route point
#
proc ::Zoom::UpdateRoutePoint {idx} {
    variable RINFO
    global nnode

    unset -nocomplain nnode
    set lat [int2lat [lindex $RINFO(pts) $idx 2]]
    set lon [int2lat [lindex $RINFO(pts) $idx 3]]
    set nnode(latlon) [concat $lat $lon]
    foreach {lat lon} [::Display::PrettyLat $lat $lon] break

    set txt "Add Route Point Elevation"
    set nnode(wtitle) "$::state(progname) $txt"
    set nnode(title)  "$txt\nLatitude $lat\nLongitude $lon"
    set nnode(l0) Elevation
    set nnode(e0) [lindex $RINFO(pts) $idx 1]
    set nnode(t0) 1
    set nnode(l1) "USGS Elevation"
    set nnode(e1) "?"
    set nnode(t1) 8
    ::Edit::NewDlg "Route Point" 2 $idx
    # Calls Edit::AddRoutePoint when done
}
##+##########################################################################
#
# ::Edit::AddRoutePoint -- called from ::Zoom::UpdateRoutePoint's dialog
#
proc ::Edit::AddRoutePoint {idx} {
    global nnode

    set elev "?"
    if {[string is double -strict $nnode(e0)]} {
        set elev $nnode(e0)
    }
    lset ::Zoom::RINFO(pts) $idx 1 $elev
    ::Zoom::IsModified 1
    destroy .nnode
    ::Klippy::DrawPoints
    ::Zoom::GuessClimbing
}
##+##########################################################################
#
# ::Zoom::SortCells -- sorts list of cells by closeness to given cell
#
proc ::Zoom::SortCells {ox oy cells} {
    set all {}
    foreach cell $cells {
        foreach {x y} $cell break
        set dist [expr {($x - $ox)*($x - $ox) + ($y - $oy) * ($y - $oy)}]
        lappend all [list $cell $dist]
    }
    set all [lsort -real -index 1 $all]
    set cells {}
    foreach cell $all { lappend cells [lindex $cell 0]}
    return $cells
}
##+##########################################################################
#
# Save -- saves the current road into <zone dir>/user.nodes
#
proc ::Zoom::Save {} {
    variable RINFO
    variable DS
    global state roads nnode poi

    ::Data::MarkModified $RINFO(what) $RINFO(who)
    if {$RINFO(what) eq "road"} {
        set rid $RINFO(who)
        set ll {}
        set elevs {}
        foreach pt [lrange $RINFO(pts) 1 end-1] {
            lassign $pt . elev lat lon
            lappend ll {*}[int2lat $lat] {*}[int2lat $lon]
            lappend elevs $elev
        }
        if {[llength $ll] == 1} {set ll {}}     ;# No xy data

        # Store north, dist & south but use our guess if bad data
        foreach what {north dist south} idx {2 3 4} {
            if {[::BadMath::IsBad $RINFO($what)]} {
                set RINFO($what) "$RINFO(guess,$what)+?"
            }
            lset roads($rid) $idx $RINFO($what)
        }
        lset roads($rid) 6 $RINFO(title)        ;# Road name
        lset roads($rid) 8 $ll                  ;# XY data
        lset roads($rid) 9 $elevs               ;# Z data
        lset roads($rid) 11 zoom                ;# Data source
        ::Data::ReProcessOneRoad $rid
        ::Zoom::IsModified 0
        ::Route::StatRoute 1
        return
    }

    if {$RINFO(what) eq "node"} {
        set nnode(e0) $RINFO(title)             ;# Put into Edit's global array
        set nnode(e1) $RINFO(ele)
        set nnode(e2) $RINFO(usgs)
        lassign [lindex $RINFO(pts) 0] . . lat lon
        set nnode(latlon) [list $lat 0 0 $lon 0 0]
        ::Edit::AddNode $RINFO(who)
        ::Zoom::IsModified 0
        return
    }
    error "not converted to slippy yet"

    if {$RINFO(what) eq "poi"} {
        lassign [lindex $RINFO(pts) 0] . . lat lon
        lset poi($RINFO(who)) 1 $RINFO(title)
        lset poi($RINFO(who)) 2 $lat
        lset poi($RINFO(who)) 3 $lon
        lset poi($RINFO(who)) 6 [::Display::pos2canvas root $lat $lon]
        ::Display::DrawPOI $RINFO(who)
        ::Zoom::IsModified 0
        return
    }
    if {$RINFO(what) eq "geo"} {
        lassign [lindex $RINFO(pts) 0] . . lat lon
        lset ::GPS::wpts($RINFO(who)) 0 $lat
        lset ::GPS::wpts($RINFO(who)) 1 $lon
        lset ::GPS::wpts($RINFO(who)) 3 $RINFO(title)
        lset ::GPS::wpts($RINFO(who)) 6 [::Display::pos2canvas root $lat $lon]
        ::GPS::DrawWpts g 0
        ::Zoom::IsModified 0
    }
}
##+##########################################################################
#
# ::Zoom::Google -- brings up google maps at a specific lat/lon
# NB. google doesn't supply any marker on the map yet
#
proc ::Zoom::Google {what {who ?}} {
    variable ZMAP
    variable google

    if {$what eq "zoom" && $ZMAP(what) eq "road"} { ;# Called from w/i zoom
        set what $::Zoom::ZMAP(what)
        set who $::Zoom::ZMAP(who)
    } elseif {$what eq "popup"} {
        set what $::state(popup,what)
        set who $::state(popup,who)
    }
    set what [string tolower $what]
    set last $google(last)
    set google(last) [list $what $who]

    set to ""
    set mid ""
    if {$what eq "node"} {
        foreach {. . lat lon} $::nodes($who) break
        lassign $::nodes($who) . . lat lon
        set from "$lat+-$lon"
    } elseif {$what eq "zoom"} {
        lassign [lindex $::Zoom::RINFO(pts) 0] . . lat lon
        Lon2World
        set from "$lat+$lon"
    } elseif {$what eq "poi"} {
        lassign $::poi($who) . . lat lon
        Lon2World
        set from "$lat+$lon"
    } elseif {$what eq "geo"} {
        lassign $::GPS::wpts($who) lat lon
        Lon2World
        set from "$lat+$lon"
    } elseif {$what eq "coords"} {
        lassign [::Coords::Where] lat lon
        set lat [lat2int {*}$lat]
        set lon [lat2int {*}$lon]
        Lon2World
        set from "$lat+$lon"
    } elseif {$what eq "map" || $what eq "embellishment"} {
        lassign $::state(popup) x y
        lassign [::Display::canvas2pos $x $y] . . . . lat lon
        Lon2World
        set from "$lat+$lon"
    } elseif {$what eq "zoompoint"} {
        lassign $who lat lon
        Lon2World
        set from "$lat+$lon"
    } elseif {$what eq "road"} {
        lassign $::roads($who) nid1 nid2
        lassign $::nodes($nid1) . . lat lon
        Lon2World
        set from "$lat+$lon"
        lassign $::nodes($nid2) . . lat lon
        Lon2World
        set to "$lat+$lon"

        # If repeating google map road, then put in a midpoint
        if {$last eq [list $what $who]} {
            set xy [lindex $::roads($who) 8]
            set len [expr {[llength $xy] / 6}]
            if {$len > 0} {
                set n [expr {($len/2) * 6}]
                set lat3 [lrange $xy $n [expr {$n+2}]]
                set lon3 [lrange $xy [expr {$n+3}] [expr {$n+5}]]
                set lat [lat2int {*}$lat3]
                set lon [lat2int {*}$lon3]
                Lon2World
                set mid "$lat+$lon"
            }
        }
    } elseif {$what eq "wpt"} {
        lassign $::GPS::wpts($who) lat lon
        set from "$lat+-$lon"
    } else {
        puts "ERROR: unknown item for zoom google: '$what' '$who'"
        return
    }

    if {$to eq ""} {
        set url "http://maps.google.com/maps?q=$from"
    } elseif {$mid eq ""} {
        set url "http://maps.google.com/maps?saddr=$from&daddr=$to"
    } else {
        set url "http://maps.google.com/maps?saddr=$from&daddr=$mid+to:$to"
    }
    WebPage $url
    return $url
}
##+##########################################################################
#
# ::Zoom::USGSAllWaypoints -- gets the USGS elevation for all waypoints
#
proc ::Zoom::USGSAllWaypoints {} {
    variable W
    variable RINFO

    set who {}
    for {set i 0} {$i < [llength $RINFO(pts)]} {incr i} {
        set elev [lindex $RINFO(pts) $i 1]
        if {[string is double -strict $elev] && $elev > 0} continue
        lappend who $i
    }
    if {$who eq {}} return

    # Post dialog box for all queries
    set dlg [::USGS::_MakeWaitDialog [winfo toplevel $W]]
    after idle [list ::Zoom::_USGSAllWaypoints3 $dlg $who]
    # DoGrab $dlg $dlg
    ::Zoom::GuessClimbing
}
# ##+##########################################################################
# #
# # ::Zoom::_USGSAllWaypoints2 -- helper for ::Zoom::USGSAllWaypoints
# #
# proc ::Zoom::_USGSAllWaypoints2 {dlg who} {
#     variable RINFO

#     set cnt 0
#     foreach idx $who {
#         incr cnt
#         if {! [winfo exists $dlg]} break

#         lassign [lindex $RINFO(pts) $idx] . . lat lon
#         set latlon [concat [int2lat $lat] [int2lat $lon]]
#         set ::USGS::S(msg) "Querying waypoint [format %2d $cnt] of [llength $who]"

#         set usgs [::USGS::Query "" $latlon]
#         if {[string is double -strict $usgs]} {
#             lset RINFO(pts) $idx 1 $usgs
#         }
#         update
#     }
#     ::Zoom::IsModified 1
#     ::Klippy::DrawPoints
#     destroy $dlg
# }

proc ::Zoom::_USGSAllWaypoints3 {dlg who} {
    variable RINFO
    variable stats

    set stats(usgs,total) [llength $who]
    set stats(usgs,cnt) 0
    set pgu [::PGU::New]

    foreach idx $who {
        lassign [lindex $RINFO(pts) $idx] . . lat lon
        set url [::USGS::GetURL $lat $lon]
        set cookie $idx
        $pgu Add $url $cookie ::Zoom::_USGSCallback
    }
    puts "KPV: launching [$pgu Statistics qlen]"
    set wpts [::Data::Plural $stats(usgs,total) "waypoint" "waypoints"]
    set ::USGS::S(msg) "Querying elevation for $stats(usgs,total) $wpts"
    update idletasks
    $pgu Config -degree 10
    $pgu Launch
    $pgu Wait
    $pgu Close
    ::Zoom::IsModified 1
    ::Klippy::DrawPoints
    destroy $dlg
}
proc ::Zoom::_USGSCallback {token cookie} {
    variable RINFO
    variable stats

    incr stats(usgs,cnt)
    set ::USGS::S(msg) "Data for waypoint [format %2d $stats(usgs,cnt)] of $stats(usgs,total)"
    update idletasks
    lassign $cookie idx

    set ncode [::http::ncode $token]
    set xml [::http::data $token] ; list
    # Check content-type???
    ::http::cleanup $token
    if {$ncode != 200} {
        # set ::USGS_ERROR $save
        return
    }
    set elev [::USGS::ExtractElevation $xml]
    # puts "$idx -> $elev"
    if {[string is double -strict $elev]} {
        lset RINFO(pts) $idx 1 $elev
    }
}

proc ::Zoom::Elevs {} {
    package require Plotchart
    variable RINFO

    unset -nocomplain X
    unset -nocomplain Y
    set X {}
    set Y {}
    for {set i 0} {$i < [llength $RINFO(pts)]} {incr i} {
        set elev [lindex $RINFO(pts) $i 1]
        if {! [string is double -strict $elev]} continue
        lappend X $i
        lappend Y $elev
    }
    set y_sort [lsort -real $Y]
    set ys [::Plotchart::determineScale [lindex $y_sort 0] [lindex $y_sort end]]
    set xs [::Plotchart::determineScale [lindex $X 0] [lindex $X end]]
    lset xs 2 1

    set W .elevs
    if {! [winfo exists $W]} {
        destroy W
        toplevel $W
        wm transient $W .
        ::ttk::button $W.replot -text "Replot" -command ::Zoom::Elevs
        ::ttk::button $W.ok -text "Dismiss" -command [list destroy $W]
        set w [expr {.8 * [winfo screenwidth .]}]
        canvas $W.c -width $w -bd 0 -highlightthickness 0
        pack $W.c -expand 1 -fill both -side top
        pack $W.replot $W.ok -side left -expand 1 -pady 10
    } else {
        raise $W
        $W.c config -width [winfo width $W.c] -height [winfo height $W.c]
    }
    $W.c delete all
    set s [::Plotchart::createXYPlot $W.c $xs $ys]
    foreach x $X y $Y {
        $s plot series1 $x $y
    }
    $W.c itemconfig data -tag series1 -width 2
    set xy0 [::Plotchart::coordsToPixel $W.c [lindex $X 0] [lindex $Y 0]]
    set xy1 [::Plotchart::coordsToPixel $W.c [lindex $X end] [lindex $Y end]]

    $W.c create line [concat $xy0 $xy1] -tag a -fill green -width 2
}
## EON ZOOM
