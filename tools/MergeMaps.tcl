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
set S(chunk,x) 3
set S(chunk,y) 3
set S(chunk,x) 5
set S(chunk,y) 5
set S(margin) 30

set MAPS(x,cnt) ?
set MAPS(y,cnt) ?
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
    label $W.lwidth -textvariable MAPS(x,cnt) -relief sunken -width 4
    label $W.x -text "x" -width 0
    label $W.lheight  -textvariable MAPS(y,cnt) -relief sunken -width 4

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
    label $W.lx -text "X Chunk" -anchor e
    entry $W.ex -textvariable S(chunk,x) -width 5 -validate key -vcmd {string is integer %P}
    label $W.ly -text "Y Chunk" -anchor e
    entry $W.ey -textvariable S(chunk,y) -width 5 -validate key -vcmd {string is integer %P}
    label $W.ilsize -text "Chunk Size" -anchor e
    label $W.ilwidth -textvariable MAPS(iw2) -relief sunken -width 4
    label $W.ix -text "x" -width 0
    label $W.ilheight  -textvariable MAPS(ih2) -relief sunken -width 4
    button $W.go -text "Merge" -command MergeMaps
    grid $W.lx $W.ex - - -sticky w
    grid $W.ly $W.ey - - -sticky w
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
    set S(chunk,x) $S(chunk,x)

    bind all <Key-F2> {console show}
}
proc Tracer {var1 var2 op} {
    global S MAPS

    if {[file exists $S(rname)]} {
	.name.go config -state normal
    } else {
	.name.go config -state disabled
    }
    if {! [string is integer -strict $MAPS(x,cnt)] || 
	! [string is integer -strict $MAPS(y,cnt)] ||
	! [string is integer -strict $S(chunk,x)] || 
	! [string is integer -strict $S(chunk,y)]} {
	.block.go config -state disabled
    } else {
	.block.go config -state normal
    }
    set MAPS(iw2) ?
    set MAPS(ih2) ?
    catch {set MAPS(iw2) [expr {$MAPS(iw) * $S(chunk,x)}] }
    catch {set MAPS(ih2) [expr {$MAPS(ih) * $S(chunk,y)}] }
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

    set MAPS(x,cnt) ?
    set MAPS(y,cnt) ?
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
proc MakeGrid {} {
    global MAPS S GRID

    .c delete all
    if {! [string is integer -strict $MAPS(x,cnt)] || 
	! [string is integer -strict $MAPS(y,cnt)]} return

    set w [expr {[winfo width .c] - 2*$S(margin)}]
    set h [expr {[winfo height .c] - 2*$S(margin)}]

    set dw [expr {$w / double($MAPS(x,cnt))}]
    set dh [expr {$h / double($MAPS(y,cnt))}]
    set dd [expr {$dw > $dh ? $dh : $dw}]

    set lm [expr {([winfo width .c] - ($dd*$MAPS(x,cnt)))/2}]
    set tm [expr {([winfo height .c] - ($dd*$MAPS(y,cnt)))/2}]

    for {set row 0} {$row < $MAPS(y,cnt)} {incr row} {
	set r [expr {$MAPS(y,max) - $row}]
	set y0 [expr {$tm + $row * $dd}]
	set y1 [expr {$y0 + $dd}]
	for {set col 0} {$col < $MAPS(x,cnt)} {incr col} {
	    set c [expr {$MAPS(x,min) + $col}]

	    set x0 [expr {$lm + $col * $dd}]
	    set x1 [expr {$x0 + $dd}]
	    set tag box$r,$c
	    set clr $::CLRS($GRID($c,$r))
	    .c create rect $x0 $y0 $x1 $y1 -tag $tag -fill $clr -outline black \
		-stipple gray50
	}
    }
}

proc ParseRegionFile {rname} {
    global MAPS S GRID

    set S(dirname) [file dirname $rname]
    set S(utm) 0
    set S(google) 0
    set preface ""
    
    set fin [open $rname r]
    set data [read $fin] ; list
    close $fin

    unset -nocomplain MAPS
    set XX {}
    set YY {}
    foreach line [split [string trimright $data] "\n"] {
	set ::line $line
	if {! [string match "map=*" $line]} {
	    if {[string match "utm=*" $line]} {
		set S(utm) [string range $line 4 end]
	    }
	    append preface "$line\n"
	    continue
	}

	foreach {mname zoom utm} [split [string range $line 4 end] ":"] break
	set n [regexp {/(gmap_)?(\d+)_(\d+)_\d+\.(jpg|gif)} $mname => . xx yy]
	if {! $n} {
	    set S(google) 1
	    set n [regexp {/(\d+)/(\d+)/(\d+)\.(jpg|gif|png)} $mname => . xx yy]
	}
	if {! $n} {
	    set emsg "ERROR: couldn't parse map info.\n"
	    append emsg "Has this region already been merged?"
	    tk_messageBox -icon error -message $emsg
	    return
	}
	set MAPS($xx,$yy) [list $mname $zoom $utm]
	set GRID($xx,$yy) 0
	lappend XX $xx
	lappend YY $yy
    }
    set XX [lsort -unique -integer $XX]
    set YY [lsort -unique -integer $YY]

    set MAPS(x,min) [lindex $XX 0]
    set MAPS(x,max) [lindex $XX end]
    set MAPS(x,cnt) [expr {$MAPS(x,max) - $MAPS(x,min) + 1}]
    set MAPS(y,min) [lindex $YY 0]
    set MAPS(y,max) [lindex $YY end]
    set MAPS(y,cnt) [expr {$MAPS(y,max) - $MAPS(y,min) + 1}]

    trace variable MAPS w Tracer
    GetMapSize
    set S(preface) $preface
}
proc GetMapSize {} {
    global MAPS S
    set mfile [lindex $MAPS($MAPS(x,min),$MAPS(y,min)) 0]
    set mfile [file join $S(dirname) $mfile]
    image create photo ::img::test -file $mfile
    set MAPS(iw) [image width ::img::test]
    set MAPS(ih) [image height ::img::test]
    image delete ::img::test

    catch { set MAPS(iw2) [expr {$MAPS(iw) * $S(chunk,x)}] }
    catch { set MAPS(ih2) [expr {$MAPS(ih) * $S(chunk,y)}] }
}
proc WriteRegionFile {rname} {
    global CMAPS S MAPS

    set oname "$rname.old"
    file delete $oname
    file rename $rname $oname

    set preface $S(preface)
    #regsub {name=} $S(preface) "name=$S(lbl)_" preface
    #set dir [file dirname $rname]
    #set tail [file tail $rname]
    #set fname [file join $dir "$S(lbl)_$tail"]

    set fout [open $rname w]
    puts $fout $preface

    for {set y0 $MAPS(y,max)} {$y0 >= $MAPS(y,min)} {incr y0 -$S(chunk,y)} {
	for {set x0 $MAPS(x,min)} {$x0 <= $MAPS(x,max)} {incr x0 $S(chunk,x)} {
	    if {! [info exists CMAPS($x0,$y0)]} continue
	    foreach {mname zoom utm} $CMAPS($x0,$y0) break
	    puts $fout "map=$mname:$zoom:$utm"
	}
    }
    close $fout
    tk_messageBox -message "Created region '[file tail $rname]'"
}
proc ChunkAll {} {
    global CMAPS MAPS S

    unset -nocomplain CMAPS
    set S(lbl) "C$S(chunk,x)$S(chunk,y)"
    Highlight $MAPS(x,min) $MAPS(y,max) $MAPS(x,max) $MAPS(y,min) 0
    
    for {set y0 $MAPS(y,max)} {$y0 >= $MAPS(y,min)} {incr y0 -$S(chunk,y)} {
	set y1 [expr {$y0 - $S(chunk,y) + 1}]
	if {$y1 < $MAPS(y,min)} { set y1 $MAPS(y,min) }
	for {set x0 $MAPS(x,min)} {$x0 <= $MAPS(x,max)} {incr x0 $S(chunk,x)} {
	    set x1 [expr {$x0 + $S(chunk,x) - 1}]
	    if {$x1 > $MAPS(x,max)} { set x1 $MAPS(x,max) }
	    
	    set iname [ChunkOne $x0 $y0 $x1 $y1]
	    SaveChunk $iname $x0 $y0 $x1 $y1
	}
    }
}
proc ChunkOne {x0 y0 x1 y1} {
    global MAPS S

    set dw $MAPS(iw)
    set dh $MAPS(ih)
    
    set w [expr {$dw * ($x1-$x0+1)}]
    set h [expr {$dh * ($y0-$y1+1)}]
    image create photo ::img::chunk -width $w -height $h
    ::img::chunk copy ::img::nomap -to 0 0 $w $h

    set ix -$dw
    for {set x $x0} {$x <= $x1} {incr x} {
	incr ix $dw
	set iy -$dh
	for {set y $y0} {$y >= $y1} {incr y -1} {
	    Highlight $x $y $x $y 1; update
	    
	    incr iy $dh
	    if {! [info exists MAPS($x,$y)]} continue
	    set fname [lindex $MAPS($x,$y) 0]
	    set fname [file join $S(dirname) $fname]
	    image create photo ::img::one -file $fname

	    ::img::chunk copy ::img::one -to $ix $iy
	}
    }
    Highlight $x0 $y0 $x1 $y1 2
    update
    image delete ::img::one
    return ::img::chunk
}
# map=Maps/Topo/14/145_1338_10.gif:14:4284800 464000 10 4281600 467200 10
# map=google/small2/gmap_2225_3092_4.jpg:4:40.313763888888886 0 0 82.2223888888889 0 0 40.28010416666666 0 0 82.17850000000001 0 0

proc SaveChunk {iname x0 y0 x1 y1} {
    global MAPS CMAPS S
    
    foreach {fname0 zoom0 utm0} $MAPS($x0,$y0) break
    set utm1 [GetUTMExtent $x0 $y0 $x1 $y1]

    set dir [file dirname $fname0]
    set tail [file tail $fname0]
    set fname [file join $dir "$S(lbl)_$tail"]
    
    set outname [file join $S(dirname) $fname]
    set utm [concat [lrange $utm0 0 2] $utm1]

    set CMAPS($x0,$y0) [list $fname $zoom0 $utm]
    $iname write $outname -format jpeg
}
proc GetUTMExtent {x0 y0 x1 y1} {
    global MAPS
    set n2 -; set e2 -; set z2 -
    if {[info exists MAPS($x1,$y1)]} {
	set utms [lindex $MAPS($x1,$y1) 2]
	foreach {n2 e2 z2} [lrange $utms 3 5] break
	#return [lrange $utms 3 5]
    }
    set utms [lindex $MAPS($x0,$y0) 2]
    foreach {n0 e0 z0 n1 e1 z1} $utms break

    set dn [expr {$n1 - $n0}]
    set n [expr {$n0 + ($y0-$y1+1)*$dn}]
    set de [expr {$e1 - $e0}]
    set e [expr {$e0 + ($x1-$x0+1)*$de}]

    return [list $n $e $z0]
}
proc GetChunkBounds {x0 y0 x1 y1} {
    global S MAPS

    set coords1 [lindex $MAPS($x0,$y0) 2]
    set coords2 [lindex $MAPS($x1,$y1) 2]
    if {$S(utm)} {
	set pre [lrange $coords1 0 2]
	set post [lrange $coords2 end-2 end]
    } else {
	set pre [lrange $coords1 0 5]
	set post [lrange $coords2 end-5 end]
    }


}

proc Highlight {x0 y0 x1 y1 how} {
    global GRID

    set clr $::CLRS($how)
    for {set x $x0} {$x <= $x1} {incr x} {
	for {set y $y0} {$y >= $y1} {incr y -1} {
	    set tag box$y,$x
	    .c itemconfig $tag -fill $clr
	    set GRID($x,$y) $how
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

##+##########################################################################
#
# ll2utm
#
# Convert latitude and longitude into Universal Transverse Mercator (UTM)
# coordinates. Lots of fun math which I got off the web.
#
proc ll2utm {latitude longitude {west 1}} {
    set PI [expr {atan(1) * 4}]
    set K0 0.9996

    # WGS-84
    set er 6378137                              ;# EquatorialRadius
    set es2 0.00669438                          ;# EccentricitySquared
    set es4 [expr {$es2 * $es2}]
    set es6 [expr {$es2 * $es2 * $es2}]

    # Must be in the range -180 <= long < 180
    if {$west && $longitude > 0} {
	set longitude [expr {-1 * $longitude}]
    }
    while {$longitude < -180} { set longitude [expr {$longitude + 360}]}
    while {$longitude >= 180}  { set longitude [expr {$longitude - 360}]}

    # Now convert
    set lat_rad [expr {$latitude * $PI / 180.0}]
    set long_rad [expr {$longitude * $PI / 180.0}]

    set zone [expr {int(($longitude + 180) / 6) + 1}]
    if {$latitude >= 56.0 && $latitude < 64.0 &&
        $longitude >= 3.0 && $longitude < 12.0} {
        $zone = 32
    }
    if { $latitude >= 72.0 && $latitude < 84.0 } {
        if { $longitude >= 0.0  && $longitude <  9.0 } {$zone = 31;}
        if { $longitude >= 9.0  && $longitude < 21.0 } {$zone = 33;}
        if { $longitude >= 21.0 && $longitude < 33.0 } {$zone = 35;}
        if { $longitude >= 33.0 && $longitude < 42.0 } {$zone = 37;}
    }
    # +3 puts origin in middle of zone
    set long_origin [expr {( $zone - 1 ) * 6 - 180 + 3}]
    set long_origin_rad [expr {$long_origin * $PI / 180.0}]
    set eccPrimeSquared [expr {$es2 / ( 1.0 - $es2 )}]
    set N [expr {$er / sqrt( 1.0 - $es2 * sin( $lat_rad ) * sin( $lat_rad ) )}]
    set T [expr {tan( $lat_rad ) * tan( $lat_rad )}]
    set C [expr {$eccPrimeSquared * cos( $lat_rad ) * cos( $lat_rad )}]
    set A [expr {cos( $lat_rad ) * ( $long_rad - $long_origin_rad )}]
    set M [expr { $er * ( \
			      (1.0 - $es2 / 4 - 3 * $es4 / 64 - 5 * $es6 / 256) * $lat_rad \
			      - (3 * $es2 / 8 + 3 * $es4 / 32 + 45 * $es6 / 1024) * sin(2 * $lat_rad) \
			      + (15 * $es4 / 256 + 45 * $es6 / 1024 )             * sin(4 * $lat_rad) \
			      - (35 * $es6 / 3072 )                               * sin(6 * $lat_rad) \
			      )}]
    set easting [expr {$K0 * $N * ( $A + ( 1 - $T + $C ) * $A * $A * $A / 6 \
					+ ( 5 - 18 * $T + $T * $T + 72 * $C - 58 * $eccPrimeSquared ) * \
					$A * $A * $A * $A * $A / 120 ) + 500000.0}]
    set northing [expr {$K0 * ( $M + $N * tan( $lat_rad ) * \
				    ( $A * $A / 2 + ( 5 - $T + 9 * $C + 4 * $C * $C ) * \
					  $A * $A * $A * $A / 24 + ( 61 - 58 * $T + $T * $T + \
									 600 * $C - 330 * $eccPrimeSquared ) * \
					  $A * $A * $A * $A * $A * $A / 720 ) )}]

    if {$latitude < 0} {  ;# 1e7 meter offset for southern hemisphere
        set northing [expr {$northing + 10000000.0}]
    }

    set northing [expr {int($northing)}]
    set easting [expr {int($easting)}]
    if {$latitude > 84.0 || $latitude < -80.0} {
	set letter "Z"
    } else {
	set l [expr {int(($latitude + 80) / 8.0)}]
	set letter [string index "CDEFGHJKLMNPQRSTUVWXX" $l]
    }
    
    return [list $northing $easting $zone $letter]
}
proc utm2ll {northing easting zone {letter S}} {
    set PI [expr {atan(1) * 4}]
    set K0 0.9996
    
    # WGS-84
    set er 6378137                              ;# EquatorialRadius
    set es2 0.00669438                          ;# EccentricitySquared
    set es2x [expr {1.0 - $es2}]
    
    set x [expr {$easting - 500000.0}]
    set northernHemisphere [expr {$letter >= "N"}]
    set y [expr {$northing - ($northernHemisphere ? 0.0 : 10000000.0)}]
    set long_origin [expr {($zone - 1) * 6 - 180 + 3}] ;# +3 puts in middle
    set ep2 [expr {$es2 / $es2x}]
    set e1 [expr {(1.0 - sqrt($es2x)) / (1.0 + sqrt($es2x))}]
    set M [expr {$y / $K0}]
    set mu [expr {$M / ($er * (1.0 - $es2 /4.0 - 3 * $es2 * $es2 /64.0
			       - 5 * $es2 * $es2 * $es2 /256.0))}]
    set phi [expr {$mu + (3 * $e1 / 2 - 27 * $e1 * $e1 * $e1 / 32 ) * sin(2*$mu)
		   + (21 * $e1 * $e1 / 16 - 55 * $e1 * $e1 * $e1 * $e1 / 32)
		   * sin(4*$mu ) + (151 * $e1 * $e1 * $e1 / 96 ) * sin(6*$mu)}]
    set N1 [expr {$er / sqrt(1.0 - $es2 * sin($phi) * sin($phi))}]
    set T1 [expr {tan($phi) * tan($phi)}]
    set C1 [expr {$ep2 * cos($phi) * cos($phi)}]
    set R1 [expr {$er * $es2x / pow(1.0 - $es2 * sin($phi) * sin($phi), 1.5)}]
    set D [expr {$x / ($N1 * $K0)}]
    set latitude [expr {$phi - ($N1 * tan($phi) / $R1) 
			* ($D * $D / 2
			   - (5 + 3 * $T1 + 10 * $C1 - 4 * $C1 * $C1 - 9 * $ep2)
			   * $D * $D * $D * $D / 24
			   + (61 + 90 * $T1 + 298 * $C1 + 45 * $T1 * $T1
			      - 252 * $ep2 - 3 * $C1 * $C1 )
			   * $D * $D * $D * $D * $D * $D / 720)}]
    set latitude [expr {$latitude * 180.0 / $PI}]
    set longitude [expr {($D - (1 + 2 * $T1 + $C1)
			  * $D * $D * $D / 6
			  + (5 - 2 * $C1 + 28 * $T1 - 3 * $C1 * $C1
			     + 8 * $ep2 + 24 * $T1 * $T1)
			  * $D * $D * $D * $D * $D / 120)
			 / cos($phi)}]
    set longitude [expr {$long_origin + $longitude * 180.0 / $PI}]

    return [list $latitude $longitude]
}

################################################################
#label .l -textvariable S(msg)
#image create photo ::img::chunk -width 600 -height 600
#label .l1 -relief solid -image ::img::chunk
#pack .l .l1 -side top

DoDisplay
set S(rname) [lindex $argv 0]
update 
if {[file exists $S(rname)]} {
    FetchRegionInfo
}
return

foreach rname $argv {
    if {! [file exists $rname]} {
	tk_messageBox -icon error -message "No file '$rname'"
	continue
    }
    set S(msg) $rname

    ParseRegionFile $rname
    ChunkAll
    WriteRegionFile $rname
}
set S(msg) done
if {$tcl_interactive} return
after 10000 exit
return


foreach arr [array names MAPS {[0-9]*}] {
    foreach {. . utms} $MAPS($arr) break
    foreach {n0 e0 z0 n1 e1 z1} $utms break

    set dn [expr {$n1 - $n0}]
    set de [expr {$e1 - $e0}]
    puts "$arr: $dn $de"
}


