#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
exec tclsh $0 ${1+"$@"}

##+##########################################################################
#
# _klippy.tsh -- <description>
# by Keith Vetter 2017-08-28
#


package require Img
package require http
catch {namespace delete ::map::slippy}
package forget map::slippy
package require map::slippy

namespace eval ::Zoom {
    variable TILES
}

namespace eval ::Klippy {
    # set tile [list zoom row col]
    variable TILES
    catch {upvar 0 ::Zoom::TILES TILES}
}

namespace eval ::Klippy::Fetch {
    variable FETCH
    catch {upvar 0 ::Zoom::FETCH FETCH}
    # FETCH(state,$tile) in IDLE, IN_PGU, DRAWN, BAD_IMAGE
}
namespace eval ::Klippy::CoreTiles {
    variable TILES
    catch {upvar 0 ::Zoom::TILES TILES}
    set TILES(size) 256
}

foreach var {TILES} {
    uplevel #0 upvar #0 ::Klippy::$var ::$var
}

proc Set_Minus {a b} {
    set result {}
    foreach item $a {
        if {$item ni $b} { lappend result $item }
    }
    return $result
}

proc ::Klippy::Delta {tile0 tile1 {scalar 1}} {
    lassign $tile0 zoom row0 col0
    lassign $tile1 . row1 col1
    return [list $zoom [expr {$row0 + $row1 * $scalar}] [expr {$col0 + $col1 * $scalar}]]
}


proc ::Klippy::InitMap {pts zoom gridWidth gridHeight} {
    variable TILES

    ::Klippy::CoreTiles::GetTilesNeeded $pts $zoom $gridWidth $gridHeight
    ::Klippy::Fetch::InitFetch
    set TILES(origin,tile) [::Klippy::Delta [lindex $TILES(core) 0] [list . -1 -1]]
    set TILES(origin,point) [::map::kpv_slippy tile 2point $TILES(origin,tile)]
}
proc ::Klippy::DrawGrid {} {
    variable TILES

    set W $::Zoom::W
    set W2 $::Zoom::W2
    $W delete all
    $W2 delete all


    set ww [expr {[winfo width $W2] / $TILES(width)}]
    set hh [expr {[winfo height $W2] / $TILES(height)}]
    set small [expr {max(5, min($ww, $hh))}]
    set ::Zoom::STATIC(small) [expr {double($::Zoom::SCREEN(tile,size)) / $small}]

    # set ww [expr {$TILES(width) * $::Zoom::SCREEN(tile,size) / ([winfo width $W2] - 5.0)}]
    # set hh [expr {$TILES(height) * $::Zoom::SCREEN(tile,size) / ([winfo height $W2] - 5.0)}]
    # set ::Zoom::STATIC(small) [expr {min(max(ceil($ww), ceil($hh)), 30)}]

    foreach tile $TILES(all) {
        set xy [::Klippy::Tile2Canvas $tile]
        set tag cell_[join $tile "_"]
        $W create rect $xy -tag [list cell $tag] -fill $::Zoom::COLORS(empty)
        set xy2 [::Zoom::Canvas2Small {*}$xy]
        $W2 create rect $xy2 -tag [list cell $tag] -fill $::Zoom::COLORS(empty)

        lassign [::Data::BboxCenter $xy] x y
        $W create text $x $y -tag cell -text $tag -font {Helvetica 18 bold}
    }

    $W config -scrollregion [$W bbox all]
    $W2 config -scrollregion [$W2 bbox cell]
    $W2 create rect -1000 -1000 -1000 -1000 -tag over -width 4
}

proc ::Klippy::DrawPoints {} {
    stacktrace
    global nodes state

    set W $::Zoom::W
    set W2 $::Zoom::W2
    if {! [winfo exists $W]} return

    $W delete route
    $W2 delete route

    set bindAll [expr {$::Zoom::ZMAP(what) ne "road"}]
    set xy {}
    set xys {}
    set cnt -1
    set color $state(n,0,color)
    foreach pt $::Zoom::RINFO(pts) {
        incr cnt
        lassign $pt name ele lat lon type who .
        Lon2World
        lassign [::Klippy::LatLon2Canvas $lat $lon] x y
        lappend xy $x $y
        lassign [::Zoom::Canvas2Small $x $y] xs ys
        lappend xys $xs $ys

        set tag pt_$cnt
        set tag2 ppt_$cnt
        ::Balloon::Delete [list $W $tag]
        ::Balloon::Delete [list $W2 $tag]

        if {$type eq "waypoint"} {
            set item [expr {[string match "X*" $who] ? "rect" : "oval"}]
            set coords [::Display::MakeBox [list $x $y] $state(n,size)]
            $W create $item $coords -tag [list route node $tag] -fill $color
            set coords2 [::Display::MakeBox [list $xs $ys] 5]
            $W2 create $item $coords2 -tag [list route node $tag] -fill $color

            set txt ""
            regexp {[A-Za-z0-9]+} [string map {n {} N {}} $who] txt
            if {$state(n,size) > 8} {
                $W create text $x $y -tag [list route node $tag] \
                    -font {times 8} -text $txt
            }
            if {$::state(me) && $::Zoom::ZMAP(what) eq "node"} {
                lassign $coords x0 y0 x1 y1
                $W create line $x0 $y0 $x1 $y1 -tag [list route node a $tag] \
                    -width 2
                $W create line $x0 $y1 $x1 $y0 -tag [list route node a $tag] \
                    -width 2
            }
            ::Balloon::Create [list $W $tag] node $who "" ""
            ::Balloon::Create [list $W2 $tag] node $who "" ""
            if {$bindAll && ! $::Zoom::ZMAP(readonly)} {
                $W bind $tag <Button-1> \
                    [list ::Zoom::MoveNode down $tag $cnt %x %y]
                $W bind $tag <B1-Motion> \
                    [list ::Zoom::MoveNode move $tag $cnt %x %y]
            }
        } elseif {$type eq "trackpoint"} {
            set coords [::Display::MakeBox [list $x $y] $state(n,size)]
            $W create oval $coords -tag [list trackpoint $tag] -fill $color
            set coords2 [::Display::MakeBox [list $xs $ys] 5]
            $W2 create oval $coords2 -tag [list trackpoint $tag] -fill $color
            set xy [lrange $xy 0 end-2]
            set xys [lrange $xys 0 end-2]

            ::Balloon::Create [list $W $tag] trkpt $name $name $name
            ::Balloon::Create [list $W2 $tag] trkpt $name $name $name
        } elseif {$type eq "poi"} {
            set coords [::Display::MakeStar [list $x $y] [expr {2*$state(p,size)}]]
            $W create poly $coords -fill $state(p,color) -tag [list route node $tag]
            set coords [::Display::MakeStar [list $xs $ys] 10]
            $W2 create poly $coords -fill $state(p,color) \
                -tag [list route node $tag]
            ::Balloon::Create [list $W $tag] poi $who
            ::Balloon::Create [list $W2 $tag] poi $who

            if {$bindAll && ! $::Zoom::ZMAP(readonly)} {
                $W bind $tag <Button-1> \
                    [list ::Zoom::MoveNode down $tag $cnt %x %y]
                $W bind $tag <B1-Motion> \
                    [list ::Zoom::MoveNode move $tag $cnt %x %y]
            }
        } elseif {$type eq "geo"} {
            puts "KPV: ::GPS::Symbol $W [list $x $y] g [list route geo $tag] true"
            ::GPS::Symbol $W [list $x $y] g [list route geo $tag] true
            ::GPS::Symbol $W2 [list $xs $ys] g [list route geo $tag]
            ::Balloon::Create [list $W $tag] wpt $who
            ::Balloon::Create [list $W2 $tag] wpt $who
            if {$bindAll && ! $::Zoom::ZMAP(readonly)} {
                $W bind $tag <Button-1> \
                    [list ::Zoom::MoveNode down $tag $cnt %x %y]
                $W bind $tag <B1-Motion> \
                    [list ::Zoom::MoveNode move $tag $cnt %x %y]
            }
        } elseif {$type eq "coords"} {
            set ltag [list route node $tag]
            $W create line $x -99999 $x 99999 -tag $ltag -width 2
            $W create line -99999 $y 99999 $y -tag $ltag -width 2
            $W2 create line $xs -99999 $xs 99999 -tag $ltag -width 2
            $W2 create line -99999 $ys 99999 $ys -tag $ltag -width 2

            set coords [::Display::MakeBox [list $x $y] $state(n,size)]
            $W create oval $coords -tag $ltag -fill $color -width 2

            set coords [::Display::MakeBox [list $xs $ys] 5]
            $W2 create oval $coords -tag $ltag -fill $color -width 2
        } else {                                ;# Routepoints
            set coords [::Display::MakeBox [list $x $y] 4]
            $W create oval $coords -tag [list route rtept $tag] -fill $color
            if {[string is double -strict $ele]} {
                $W create oval [::Display::MakeBox [list $x $y] 1] -fill black \
                    -tag [list route rtept $tag $tag2]
            }

            set coords [::Display::MakeBox [list $xs $ys] 3]
            $W2 create oval $coords -fill $color -tag [list route rtept $tag]

            $W bind $tag <<MenuMousePress>> \
                [list ::Zoom::DoPopupMenu %x %y rtept $cnt]
            if {! $::Zoom::ZMAP(readonly)} {
                $W bind $tag <Control-Button-2> \
                    [list ::Zoom::DoPopupMenu %x %y add $cnt]
                $W bind $tag <Control-Button-3> \
                    [list ::Zoom::DoPopupMenu %x %y delete $cnt]
                $W bind $tag <Button-1> \
                    [list ::Zoom::MoveNode down $tag $cnt %x %y]
                $W bind $tag <B1-Motion> \
                    [list ::Zoom::MoveNode move $tag $cnt %x %y]
            }
        }
    }
    if {[llength $xy] > 2} {
        set clr $state(r,0,9,color)
        set width $state(r,0,9,width)
        $W create line $xy -tag {route road} -fill $clr -width $width
        $W2 create line $xys -tag {route road} -fill $clr -width $width
        ::Balloon::Create [list $W road] road $who "" ""
        ::Balloon::Create [list $W2 road] road $who "" ""
    }
    $W raise node
    $W raise geo
    $W raise rtept
    $W raise trackpoint
    $W raise milepost
    $W raise arrow
    $W raise zoom
    $W raise BOX
    $W2 raise node
    $W2 raise geo
    $W2 raise rtept
    $W2 raise trackpoint
    # if {$::Zoom::ZMAP(mag) > 13} { $W lower rtept }

    bind $W <Control-Button-1> break            ;# Disable bend road buttons
    bind $W <Control-Button-2> break

    $W bind img <<MenuMousePress>> "::Zoom::DoPopupMenu %x %y map; break"
    if {$::Zoom::ZMAP(what) eq "node"} {
        $W bind road <<MenuMousePress>> {::Zoom::DoPopupMenu %x %y node; break}
        if {! $::Zoom::ZMAP(readonly)} {
            $W bind node <Enter> [list $W config -cursor hand2]
            $W bind node <Leave> [list $W config -cursor {}]
        }
    } else {
        $W bind road <<MenuMousePress>> {::Zoom::DoPopupMenu %x %y road; break}
        if {! $::Zoom::ZMAP(readonly)} {
            # $W bind road <Control-Button-3> {::Zoom::DoPopupMenu %x %y add; break}
            # $W bind img <Control-Button-3> {::Zoom::DoPopupMenu %x %y add; break}
            $W bind road <Control-Button-2> {::Zoom::DoPopupMenu %x %y add; break}
            $W bind img <Control-Button-2> {::Zoom::DoPopupMenu %x %y add; break}
            $W bind rtept <Enter> [list $W config -cursor hand2]
            $W bind rtept <Leave> [list $W config -cursor {}]
        }
    }
}

proc ::Klippy::Tile2Canvas {tile} {
    variable TILES

    set tile1 [::Klippy::Delta $tile $TILES(origin,tile) -1]
    set pt0 [::map::kpv_slippy tile 2point $tile1]
    lassign $pt0 . y0 x0
    return [list $x0 $y0 [expr {$x0 + 256}] [expr {$y0 + 256}]]
}

proc ::Klippy::LatLon2Canvas {lat lon} {
    variable TILES
    lassign $TILES(origin,point) zoom y0 x0
    lassign [::map::kpv_slippy geo 2point [list $zoom $lat $lon]] . y x
    return [list [expr {$x - $x0}] [expr {$y - $y0}]]
}
proc ::Klippy::Canvas2Geo {cx cy} {
    variable TILES

    lassign $TILES(origin,point) zoom y0 x0
    set point [list $zoom [expr {$cy + $y0}] [expr {$cx + $x0}]]
    set geo [::map::kpv_slippy point 2geo $point]
    return $geo
}
proc ::Klippy::Canvas2LatLon {cx cy} {
    variable TILES

    lassign $TILES(origin,point) zoom y0 x0
    set point [list $zoom [expr {$cy + $y0}] [expr {$cx + $x0}]]
    set geo [::map::kpv_slippy point 2geo $point]
    lassign $geo . lat lon
    Lon2Klimb
    return [list $lat $lon]
}
################################################################
#
# ::Klippy::CoreTiles
#
proc ::Klippy::CoreTiles::GetTilesNeeded {pts zoom gridWidth gridHeight} {
    variable TILES

    set core [::Klippy::CoreTiles::GetTilesAtAllPoints $pts $zoom]

    lassign [::Klippy::CoreTiles::GetBBox $core] topLeft bottomRight
    set interior [::Klippy::CoreTiles::GetTilesInRect $topLeft $bottomRight]

    lassign $topLeft . top left
    lassign $bottomRight . bottom right
    set width [expr {$right - $left + 1}]
    set height [expr {$bottom - $top + 1}]

    if {$width < $gridWidth} {
        set extra [expr {$gridWidth - $width}]
        incr left [expr {-int(ceil($extra / 2.0))}]
        incr right [expr {$extra / 2}]
    }
    if {$height < $gridHeight} {
        set extra [expr {$gridHeight - $height}]
        incr top [expr {-int(ceil($extra / 2.0))}]
        incr bottom [expr {$extra / 2}]
    }
    incr top -1 ; incr left -1
    incr bottom 1 ; incr right 1
    set topLeft [list $zoom $top $left]
    set bottomRight [list $zoom $bottom $right]
    set padding [::Klippy::CoreTiles::GetTilesInRect $topLeft $bottomRight]

    set padding [Set_Minus $padding $interior]
    set interior [Set_Minus $interior $core]

    set TILES(core) $core
    set TILES(interior) $interior
    set TILES(padding) $padding
    set TILES(all) [concat $core $interior $padding]
    set TILES(width) [expr {$right - $left + 1}]
    set TILES(height) [expr {$bottom - $top + 1}]
}


proc ::Klippy::CoreTiles::GetTilesAtAllPoints {pts zoom} {
    set allTiles {}
    set lastTile {}
    foreach pt $pts {
        lassign $pt name ele lat lon type who .
        Lon2World
        set geo [list $zoom $lat $lon]
        set tile [::map::slippy geo 2tile $geo]
        set segmentTiles [::Klippy::CoreTiles::GetTilesBetween2Points $lastTile $tile]
        foreach newTile $segmentTiles {
            if {$newTile ni $allTiles} {
                lappend allTiles $newTile
            }
        }
        set lastTile $tile
    }

    return $allTiles
}


proc ::Klippy::CoreTiles::GetTilesBetween2Points {tile1 tile2} {
    if {$tile1 eq {} || $tile1 eq $tile2} { return [list $tile2] }
    lassign $tile1 zoom1 row1 col1
    lassign $tile2 zoom2 row2 col2

    set drow [expr {abs($row1 - $row2) / 2.0}]
    set dcol [expr {abs($col1 - $col2) / 2.0}]

    if {$drow <= 1 && $dcol <= 1} {
        set tiles [::Klippy::CoreTiles::GetTilesInRect $tile1 $tile2]
    } else {
        set midRow [expr {($row1 + $row2) / 2}]
        set midCol [expr {($col1 + $col2) / 2}]
        set mid [list $zoom1 $midRow $midCol]
        set tilesLeft [::Klippy::CoreTiles::GetTilesBetween2Points $tile1 $mid]
        set tilesRight [::Klippy::CoreTiles::GetTilesBetween2Points $mid $tile2]
        set tiles [concat $tilesLeft $tilesRight]
    }
    return $tiles
}

proc ::Klippy::CoreTiles::GetTilesInRect {tile1 tile2} {
    lassign $tile1 zoom1 row1 col1
    lassign $tile2 zoom2 row2 col2

    if {$row1 > $row2} { lassign [list $row1 $row2] row2 row1 }
    if {$col1 > $col2} { lassign [list $col1 $col2] col2 col1 }

    set tiles {}
    for {set row $row1} {$row <= $row2} {incr row} {
        for {set col $col1} {$col <= $col2} {incr col} {
            set tile [list $zoom1 $row $col]
            lappend tiles $tile
        }
    }
    return $tiles
}

proc ::Klippy::CoreTiles::GetBBox {tiles} {
    set zoom [lindex $tiles 0 0]
    set minRow [set maxRow [lindex $tiles 0 1]]
    set minCol [set maxCol [lindex $tiles 0 2]]
    foreach tile $tiles {
        lassign $tile . row col
        set minRow [expr {min($row, $minRow)}]
        set maxRow [expr {max($row, $maxRow)}]
        set minCol [expr {min($col, $minCol)}]
        set maxCol [expr {max($col, $maxCol)}]
    }
    set topLeft [list $zoom $minRow $minCol]
    set bottomRight [list $zoom $maxRow $maxCol]

    return [list $topLeft $bottomRight]
}


################################################################
################################################################
################################################################
#
# ::Klippy::Fetch
#
proc ::Klippy::Fetch::GetVisibleTiles {} {
    variable FETCH

    if {! [winfo exists $::Zoom::W]} { return {} }
    lassign [::Display::GetScreenRect $::Zoom::W] left top right bottom . .
    foreach {who delta} {left 2 top 2 right -2 bottom -2} { incr $who $delta }
    lassign [::map::kpv_slippy geo 2tile [::Klippy::Canvas2Geo $left $top]] zoom0 row0 col0
    lassign [::map::kpv_slippy geo 2tile [::Klippy::Canvas2Geo $right $bottom]] zoom1 row1 col1

    set visible {}
    for {set row $row0} {$row <= $row1} {incr row} {
        for {set col $col0} {$col <= $col1} {incr col} {
            set tile [list $zoom0 $row $col]
            if {$FETCH(state,$tile) ne "IDLE"} continue
            lappend visible [list $zoom0 $row $col]
        }
    }
    return $visible
}

proc ::Klippy::Fetch::GetCacheFilename {tile mimetype} {
    # Returns the filename for this tile with extension computed from $mimetype
    if {$mimetype eq "any"} {
        set ext "{pgn,jpg}"
    } elseif {$mimetype eq "image/jpeg"} {
        set ext "jpg"
    } else {
        set ext "png"
    }

    lassign $tile zoom row col
    set fname "${zoom}_${row}_${col}.${ext}"

    set dirname [file join $::Zoom::STATIC(cache) $::Zoom::ZMAP(theme) $zoom $row]
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
proc ::Klippy::Fetch::GetImgName {tile} {
    set iname "::zoom::[join $tile _]"
    return $iname
}
proc ::Klippy::Fetch::GetOneTile {tile {immediately 0}} {
    variable FETCH

    lassign [::Klippy::Fetch::IsInCache $tile] status fname
    if {$status == "BAD"} { return $status }
    if {$status == "INCACHE"} {
        ::Klippy::Fetch::PutImage $tile $fname cache
    } else {
        if {$::Zoom::ZMAP(nofetch)} { return "nofetch" }
        set url [::Klippy::Fetch::GetUrl $tile]

        set cookie [list $::Zoom::ZMAP(sid) $tile]
        if {$immediately} {
            set token [::http::geturl $url]
            ::Klippy::Fetch::DoneCommand $token $cookie
            ::http::reset $token
            set status GETURL
        } else {
            ::PGU::Add 0 $url $cookie ::Klippy::Fetch::DoneCommand ::Klippy::Fetch::StatusCommand
            set FETCH(state,$tile) IN_PGU
        }
    }
    return $status
}

proc ::Klippy::Fetch::DoneCommand {token cookie} {
    if {[::http::ncode $token] != 200} return

    lassign $cookie sid tile
    if {$sid != $::Zoom::ZMAP(sid)} return

    set data [::http::data $token] ; list
    set meta [::http::meta $token]
    set fname [::Klippy::Fetch::GetCacheFilename $tile [dict get $meta Content-Type]]
    set fout [open $fname wb]
    puts -nonewline $fout [::http::data $token]
    close $fout

    ::Klippy::Fetch::PutImage $tile $fname web
}

proc ::Klippy::Fetch::StatusCommand {id how cookie} {
    lassign $cookie sid tile
    if {$sid != $::Zoom::ZMAP(sid)} return
    ::Klippy::TileStatus $tile $how
}
proc ::Klippy::Fetch::IsInCache {tile} {
    set fname [::Klippy::Fetch::GetCacheFilename $tile any]
    if {$fname eq ""} { return {"BAD" ""}}
    if {! $::Zoom::ZMAP(nocache)} {
        set globs [glob -nocomplain $fname]
        if {$globs ne {}} { return [list "INCACHE" [lindex $globs 0]] }
    }
    return {"MISS" ""}
}
proc ::Klippy::Fetch::GetUrl {tile} {
    lassign $tile z r c
    set mybase "http://khm.google.com/vt/lbw/lyrs=p&x=\${c}&y=\${r}&z=\${z}"

    # Google has subst based url
    if {[string first "$" $mybase] > -1} {
        set url [subst -nocommands -nobackslashes $mybase]
        return $url
    }
    return $mybase/$z/$c/$r.png
}

proc ::Klippy::Fetch::PutImage {tile fname whence} {
    variable FETCH

    if {! [winfo exists $::Zoom::W]} return

    if {! [::Klippy::Fetch::Ok2Render $tile]} {
        set FETCH(state,$tile) IDLE
        ::Klippy::TileStatus $tile discarded
        return
    }

    lassign [::Klippy::Tile2Canvas $tile] x0 y0 x1 y1
    set iname [::Klippy::Fetch::GetImgName $tile]
    if {[lsearch [image names] $iname] == -1} {
        set n [catch {image create photo $iname -file $fname}]
        if {$n} {
            set fname2 ${fname}.bad
            file rename -force $fname $fname2
            INFO "Bad image file $fname2"
            set FETCH(state,$tile) BAD_IMAGE
            return
        }
    }
    $::Zoom::W create image $x0 $y0 -image $iname -tag img -anchor nw
    incr ::Zoom::stats(rendered)
    lappend ::Zoom::ZMAP(rendered) $tile
    ::Klippy::TileStatus $tile $whence
    set FETCH(state,$tile) DRAWN

    $::Zoom::W raise road
    $::Zoom::W raise node
    $::Zoom::W raise geo
    $::Zoom::W raise rtept
    $::Zoom::W raise trackpoint
    $::Zoom::W raise milepost
    $::Zoom::W raise arrow
    $::Zoom::W raise BOX
    $::Zoom::W lower dash

}

proc ::Klippy::TileStatus {tile how} {
    if {! [winfo exists $::Zoom::W]} return
    $::Zoom::W itemconfig cell_[join $tile "_"] -fill $::Zoom::COLORS($how)
    $::Zoom::W2 itemconfig cell_[join $tile "_"] -fill $::Zoom::COLORS($how)

    if {$how eq "queued"} {
        incr ::Zoom::stats(queued)
    } elseif {$how eq "pending"} {
        incr ::Zoom::stats(queued) -1
        incr ::Zoom::stats(loading)
    } elseif {$how eq "done"} {
        incr ::Zoom::stats(loading) -1
        incr ::Zoom::stats(retrieved)
    } elseif {$how eq "failure" || $how eq "cancel"} {
        incr ::Zoom::stats(loading) -1
    }
}
proc ::Klippy::Fetch::Ok2Render {tile} {
    variable FETCH

    return 1
    set len [llength $::Zoom::ZMAP(rendered)]
    if {$len < $::Zoom::STATIC(maxRendered)} { return 1 }
    if {! [::Klippy::IsTileVisible $tile]} { return 0 }

    # Kick out an already rendered tile
    set idx [::Klippy::FindFurthestAway $::Zoom::ZMAP(rendered)]
    set tile2 [lindex $::Zoom::ZMAP(rendered) $idx]
    set ::Zoom::ZMAP(rendered) [lreplace $::Zoom::ZMAP(rendered) $idx $idx]

    set iname [::Klippy::Fetch::GetImgName $tile2]
    # KPV??? $W delete img_$xx,$yy
    image delete $iname
    set FETCH(state,$tile2) IDLE
    ::Klippy::TileStatus $tile2 discarded

    return 1
}
proc ::Klippy::IsTileVisible {tile} {
    lassign [::Klippy::Tile2Canvas $tile] x0 y0 x1 y1
    lassign [::Display::GetScreenRect $::Zoom::W] left top right bottom . .
    if {$x1 <= $left || $x0 >= $right || $y1 <= $top || $y0 >= $bottom} { return 0 }
    return 1
}

proc ::Klippy::FindFurthestAway {tiles} {
    set worst 0
    set dist 0
    set idx -1
    foreach tile $tiles {
        incr idx
        set d [::Klippy::DistanceFromVisible $tile]
        if {$d > $dist} {
            set dist $d
            set worst $idx
        }
    }
    return $worst
}
proc ::Klippy::DistanceFromVisible {tile} {
    lassign [::Klippy::Tile2Canvas $tile] x0 y0 x1 y1
    lassign [::Display::GetScreenRect $::Zoom::W] left top right bottom . .

    set drow 0
    if {$y1 < $top} { set drow [expr {$top - $y1}] }
    if {$y0 > $bottom} { set drow [expr {$y0 - $bottom}] }
    set dcol 0
    if {$x1 < $left} { set dcol [expr {$left - $x1}] }
    if {$x0 > $right} { set dcol [expr {$x0 - $right}] }
    return [expr {$drow * $drow + $dcol * $dcol}]
}
proc ::Klippy::Fetch::InitFetch {} {
    variable FETCH
    array unset FETCH *
    set FETCH(aid) ""
    foreach tile $::Zoom::TILES(all) {
        set FETCH(state,$tile) IDLE
    }
}
proc ::Klippy::Fetch::BuildQueues {} {
    variable FETCH

    set FETCH(q,visible) [set FETCH(q,core) [set FETCH(q,other) [set FETCH(q,all) {}]]]
    set FETCH(aid) ""

    foreach tile [::Klippy::Fetch::GetVisibleTiles] {
        if {$FETCH(state,$tile) ne "IDLE"} continue
        lappend FETCH(q,visible) $tile
    }
    foreach tile $::Zoom::TILES(core) {
        if {$FETCH(state,$tile) ne "IDLE"} continue
        if {$tile in $FETCH(q,visible)} continue
        lappend FETCH(q,core) $tile
    }
    foreach tile [concat $::Zoom::TILES(interior) $::Zoom::TILES(padding)] {
        if {$FETCH(state,$tile) ne "IDLE"} continue
        if {$tile in $FETCH(q,visible)} continue
        lappend FETCH(q,other) $tile
    }
    set FETCH(q,all) [concat $FETCH(q,visible) $FETCH(q,core) $FETCH(q,other)]
}

proc ::Klippy::Fetch::RunOneQueue {which max {launch "nolaunch"}} {
    variable FETCH

    set cnt 0
    while {$cnt < $max && $FETCH(q,$which) ne {}} {
        set FETCH(q,$which) [lassign $FETCH(q,$which) tile] ; list
        if {$FETCH(state,$tile) ne "IDLE"} continue
        set whence [::Klippy::Fetch::GetOneTile $tile]
        if {$whence ne "INCACHE"} {
            incr cnt
        }
    }
    if {$launch eq "launch"} {::PGU::Launch 0}
    return $cnt
}

proc ::Klippy::ShowQueues {} {
    foreach q [lsort [array names ::Klippy::Fetch::FETCH q,*]] {
        puts [format "%-10s: %3d %s ..." $q [llength $::Klippy::Fetch::FETCH($q)] \
                  [lrange $::Klippy::Fetch::FETCH($q) 0 3]]
    }
}


return
set bad {15 12698 5237}
