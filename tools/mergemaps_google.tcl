#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
    # Time-stamp: "2009-08-25 11:23:34" \
    exec wish $0 ${1+"$@"}

##+##########################################################################
#
# MergeMaps.tcl -- Merges small maps of region into bigger images
# by Keith Vetter
#
# Revisions:
# KPV Jan 31, 2007 - initial revision
#
##+##########################################################################
#############################################################################

package provide app-MergeMaps 1.0
package require Tk
package require Img
if {! [catch {package require tile}]} {
    if {[info commands ::tk::button] eq ""} {
	rename ::button ::tk::button
	interp alias {} button {} ::tk::button
	namespace import -force ::ttk::button
    }
}
set S(chunk,col) 3
set S(chunk,row) 3
set S(chunk,col) 5
set S(chunk,row) 5
set S(margin) 30

set MAPS(col,cnt) ?
set MAPS(row,cnt) ?
set MAPS(iw) ?
set MAPS(ih) ?
set MAPS(iw2) ?
set MAPS(ih2) ?

array set CLRS {0 cyan 1 red 2 blue}

proc DoDisplay {} {
    global S MAPS

    set W .name
    labelframe $W -text "Region Info" -bd 2 -padx 10 -pady 10
    label $W.lname -text "Name" -anchor e
    entry $W.ename -textvariable S(rname)
    button $W.gname -image ::img::star -command GetFile
    label $W.lsize -text "Region Size" -anchor e
    label $W.lwidth -textvariable MAPS(col,cnt) -relief sunken -width 4
    label $W.x -text "x" -width 0
    label $W.lheight  -textvariable MAPS(row,cnt) -relief sunken -width 4

    label $W.ilsize -text "Tile Size" -anchor e
    label $W.ilwidth -textvariable MAPS(iw) -relief sunken -width 4
    label $W.ix -text "x" -width 0
    label $W.ilheight  -textvariable MAPS(ih) -relief sunken -width 4
    
    button $W.go -text "Get Info" -command FetchRegionInfo
    
    grid $W.lname $W.ename - - - $W.gname  -sticky news -pady {0 5}
    grid $W.lsize $W.lwidth $W.x $W.lheight
    grid $W.ilsize $W.ilwidth $W.ix $W.ilheight
    grid columnconfig $W 4 -weight 1
    grid $W.go - - - - - -pady {10 0}

    set W .block
    labelframe $W -text "Block Info" -bd 2 -padx 10 -pady 10
    label $W.ly -text "Row Chunk" -anchor e
    entry $W.ey -textvariable S(chunk,row) -width 5 -validate key -vcmd {string is integer %P}
    label $W.lx -text "Column Chunk" -anchor e
    entry $W.ex -textvariable S(chunk,col) -width 5 -validate key -vcmd {string is integer %P}
    label $W.ilsize -text "Chunk Size" -anchor e
    label $W.ilwidth -textvariable MAPS(iw2) -relief sunken -width 4
    label $W.ix -text "x" -width 0
    label $W.ilheight  -textvariable MAPS(ih2) -relief sunken -width 4
    button $W.go -text "Merge" -command MergeMaps
    grid $W.ly $W.ey - - -sticky w
    grid $W.lx $W.ex - - -sticky w
    grid $W.ilsize $W.ilwidth $W.ix $W.ilheight
    grid $W.go - - -pady {10 0} -row 100
    grid rowconfigure $W 99 -weight 1
    grid columnconfigure $W 100 -minsize 50

    canvas .c -bd 2 -relief ridge -highlightthickness 0 -bg lightblue
    grid .name .block -sticky news
    grid .c - -sticky news
    grid columnconfigure . {0 1} -weight 1
    grid rowconfigure . {1} -weight 1
    
    trace remove variable MAPS write Tracer
    trace remove variable S write Tracer
    trace variable MAPS w Tracer
    trace variable S w Tracer
    set S(chunk,col) $S(chunk,col)

    bind all <Key-F2> {console show}
}
proc Tracer {var1 var2 op} {
    global S MAPS

    if {[file exists $S(rname)]} {
	.name.go config -state normal
    } else {
	.name.go config -state disabled
    }
    if {! [string is integer -strict $MAPS(row,cnt)] || 
	! [string is integer -strict $MAPS(col,cnt)] ||
	! [string is integer -strict $S(chunk,col)] || 
	! [string is integer -strict $S(chunk,row)]} {
	.block.go config -state disabled
    } else {
	.block.go config -state normal
    }
    set MAPS(iw2) ?
    set MAPS(ih2) ?
    catch {set MAPS(iw2) [expr {$MAPS(iw) * $S(chunk,col)}] }
    catch {set MAPS(ih2) [expr {$MAPS(ih) * $S(chunk,row)}] }
}
proc GetFile {} {
    set types {{{KLIMB Region Files} {.klr}} {{All Files} *}}
    set rname [tk_getOpenFile -defaultextension "klr" -filetypes $types]
    if {$rname eq ""} { return 0 }
    set ::S(rname) $rname
    .c delete all
    ClearInfo
    FetchRegionInfo
}
proc ClearInfo {} {
    global MAPS

    # Clear all GUI variables
    set MAPS(col,cnt) ?
    set MAPS(row,cnt) ?
    set MAPS(iw) ?
    set MAPS(ih) ?
    set MAPS(iw2) ?
    set MAPS(ih2) ?

}
proc FetchRegionInfo {} {
    ParseRegionFile $::S(rname)
    MakeGrid
}
proc MergeMaps {} {
    ChunkAll
    WriteRegionFile $::S(rname)
}
##+##########################################################################
# 
# MakeGrid -- Draws grid and maps grid to map tiles
# 
proc MakeGrid {} {
    global MAPS S GRID2TILE

    .c delete all
    unset -nocomplain GRID2TILE
    if {! [string is integer -strict $MAPS(col,cnt)] || 
	! [string is integer -strict $MAPS(row,cnt)]} return

    set w [expr {[winfo width .c] - 2*$S(margin)}]
    set h [expr {[winfo height .c] - 2*$S(margin)}]

    set dw [expr {$w / double($MAPS(col,cnt))}]
    set dh [expr {$h / double($MAPS(row,cnt))}]
    set dd [expr {$dw > $dh ? $dh : $dw}]

    set lm [expr {([winfo width .c] - ($dd*$MAPS(col,cnt)))/2}]
    set tm [expr {([winfo height .c] - ($dd*$MAPS(row,cnt)))/2}]

    for {set row 0} {$row < $MAPS(row,cnt)} {incr row} {
	set r [expr {$MAPS(row,min) + $row}]
	set y0 [expr {$tm + $row * $dd}]
	set y1 [expr {$y0 + $dd}]
	for {set col 0} {$col < $MAPS(col,cnt)} {incr col} {
	    set c [expr {$MAPS(col,min) + $col}]

	    set x0 [expr {$lm + $col * $dd}]
	    set x1 [expr {$x0 + $dd}]
	    set GRID2TILE($row,$col) "$r,$c"
	    set tag box$row,$col
	    set clr $::CLRS(0)
	    .c create rect $x0 $y0 $x1 $y1 -tag [list box $tag] -fill $clr \
		-outline black -stipple gray50
	}
    }
}

proc ParseRegionFile {rname} {
    global MAPS S TILEDATA

    set S(dirname) [file dirname $rname]
    set S(utm) 0
    set S(google) 0
    set preface ""
    
    set fin [open $rname r]
    set data [read $fin] ; list
    close $fin

    unset -nocomplain MAPS
    unset -nocomplain TILEDATA
    set cols {}
    set rows {}
    foreach line [split [string trimright $data] "\n"] {
	set ::line $line
	if {! [string match "map=*" $line]} {
	    if {[string match "utm=*" $line]} {
		set S(utm) [string range $line 4 end]
	    }
	    append preface "$line\n"
	    continue
	}

	lassign [split [string range $line 4 end] ":"] mname zoom coords
	set n [regexp {/(\d+)/(\d+)/(?:.*_)?(\d+)\.(jpg|gif|png)} $mname => . row col]
	if {! $n} {
	    set emsg "ERROR: couldn't parse map info.\n"
	    append emsg "Has this region already been merged?"
	    tk_messageBox -icon error -message $emsg
	    return
	}
	set TILEDATA($row,$col) [list $mname $zoom $coords]
	lappend rows $row
	lappend cols $col
    }
    set rows [lsort -unique -integer $rows]
    set cols [lsort -unique -integer $cols]

    set MAPS(row,min) [lindex $rows 0]
    set MAPS(row,max) [lindex $rows end]
    set MAPS(row,cnt) [expr {$MAPS(row,max) - $MAPS(row,min) + 1}]
    
    set MAPS(col,min) [lindex $cols 0]
    set MAPS(col,max) [lindex $cols end]
    set MAPS(col,cnt) [expr {$MAPS(col,max) - $MAPS(col,min) + 1}]

    trace variable MAPS w Tracer
    GetTileSize
    set S(preface) $preface
}
proc GetTileSize {} {
    global MAPS TILEDATA S

    set mfile [lindex $TILEDATA($MAPS(row,min),$MAPS(col,min)) 0]
    set mfile [file join $S(dirname) $mfile]
    image create photo ::img::test -file $mfile
    set MAPS(iw) [image width ::img::test]
    set MAPS(ih) [image height ::img::test]
    image delete ::img::test

    catch { set MAPS(iw2) [expr {$MAPS(iw) * $S(chunk,col)}] }
    catch { set MAPS(ih2) [expr {$MAPS(ih) * $S(chunk,row)}] }
}
proc WriteRegionFile {rname} {
    global CHUNKDATA S MAPS

    set oname "$rname.old"
    file delete $oname
    file rename $rname $oname

    set fout [open $rname w]
    puts $fout $S(preface)

    foreach chunk [lsort -dictionary [array names CHUNKDATA]] {
	lassign $CHUNKDATA($chunk) mname zoom coords
	puts $fout "map=$mname:$zoom:$coords"
    }
    close $fout
    tk_messageBox -message "Created region '[file tail $rname]'"
}
proc ChunkAll {} {
    global CHUNKDATA MAPS S

    unset -nocomplain CHUNKDATA
    Highlight 0 0 $MAPS(col,cnt) $MAPS(row,cnt) 0
    for {set row0 0} {$row0 < $MAPS(row,cnt)} {incr row0 $S(chunk,row)} {
	set row1 [expr {min($row0+$S(chunk,row),$MAPS(row,cnt))}]
	
	for {set col0 0} {$col0 < $MAPS(col,cnt)} {incr col0 $S(chunk,col)} {
	    set col1 [expr {min($col0+$S(chunk,col),$MAPS(col,cnt))}]
	    set iname [ChunkOne $row0 $col0 $row1 $col1]
	    SaveChunk $iname $row0 $col0 $row1 $col1
	}
    }
}
proc ChunkOne {row0 col0 row1 col1} {
    global MAPS S GRID2TILE TILEDATA

    set w [expr {$MAPS(iw) * ($col1-$col0)}]
    set h [expr {$MAPS(ih) * ($row1-$row0)}]
    image create photo ::img::chunk -width $w -height $h
    ::img::chunk copy ::img::nomap -to 0 0 $w $h
    image create photo ::img::one

    set iy -$MAPS(ih)
    for {set row $row0} {$row < $row1} {incr row} {
	incr iy $MAPS(ih)
	set ix -$MAPS(iw)
	for {set col $col0} {$col < $col1} {incr col} {
	    Highlight $row $col . . 1; update
	    incr ix $MAPS(iw)

	    if {! [info exists TILEDATA($GRID2TILE($row,$col))]} continue
	    set fname [lindex $TILEDATA($GRID2TILE($row,$col)) 0]
	    set fname [file join $S(dirname) $fname]
	    image create photo ::img::one -file $fname

	    ::img::chunk copy ::img::one -to $ix $iy
	}
    }
    Highlight $row0 $col0 $row1 $col1 2
    update
    image delete ::img::one
    return ::img::chunk
}
proc SaveChunk {iname row0 col0 row1 col1} {
    global MAPS CHUNKDATA S GRID2TILE TILEDATA

    lassign $TILEDATA($GRID2TILE($row0,$col0)) fname0 zoom0 coords0
    lassign $TILEDATA($GRID2TILE([expr {$row1-1}],[expr {$col1-1}])) \
	fname1 zoom1 coords1
    
    set len [expr {[llength $coords0]/2}]
    set newCoords [lrange $coords0 0 [expr {$len-1}]]
    lappend newCoords {*}[lrange $coords1 $len end]

    set dir [file dirname $fname0]
    set root [file rootname [file tail $fname0]]
    set drow [expr {$row1-$row0}]
    set dcol [expr {$col1-$col0}]
    set fname "C_${root}_${dcol}x$drow.jpg"
    set fname [file join $dir $fname]
    set outname [file join $S(dirname) $fname]
    $iname write $outname -format jpeg
    set CHUNKDATA($row0,$col0) [list $fname $zoom0 $newCoords]
}
proc Highlight {row0 col0 row1 col1 how} {
    if {$row1 eq "."} { set row1 [expr {$row0+1}]}
    if {$col1 eq "."} { set col1 [expr {$col0+1}]}
    
    set clr $::CLRS($how)
    for {set row $row0} {$row < $row1} {incr row} {
	for {set col $col0} {$col < $col1} {incr col} {
	    set tag box$row,$col
	    .c itemconfig $tag -fill $clr
	}
    }
}
image create bitmap ::img::star -data {
    #define plus_width	11
    #define plus_height 9
    static char plus_bits[] = {
	0x00,0x00, 0x24,0x01, 0xa8,0x00, 0x70,0x00, 0xfc,0x01,
	0x70,0x00, 0xa8,0x00, 0x24,0x01, 0x00,0x00 }
}
image create photo ::img::nomap -data {
    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
    2Q==}    

proc iota {start end} {
    set result {}
    if {$start <= $end} {
	for {set i $start} {$i <= $end} { incr i} {
	    lappend result $i
	}
    } else {
	for {set i $start} {$i >= $end} {incr i -1} {
	    lappend result $i
	}
    }
    return $result

}
################################################################
set row0 [set col0 0]; set row1 [set col1 2]

DoDisplay
set S(rname) [lindex $argv 0]
update 
if {[file exists $S(rname)]} {
    FetchRegionInfo
}
return
