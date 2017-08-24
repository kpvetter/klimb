# -*- mode: tcl; tab-width: 8; -*-

## Local version of map::slippy 0.3
##   -- without snit
##   -- geo 2point had incorrect scale

## See http://wiki.openstreetmap.org/wiki/Slippy_map_tilenames#Pseudo-Code
## for the coordinate conversions and other information.

# ### ### ### ######### ######### #########
## Requisites

package require Tcl 8.4
package provide map::kpv_slippy 0.4

 # ::map::kpv_slippy length level
 # ::map::kpv_slippy tiles level
 # ::map::kpv_slippy tile size
 # ::map::kpv_slippy tile valid tile levels ?msgvar?
 # ::map::kpv_slippy tile 2geo tile
 # ::map::kpv_slippy tile 2point tile
 # ::map::kpv_slippy geo 2tile geo
 # ::map::kpv_slippy geo 2point geo
 # ::map::kpv_slippy point 2geo point
 # ::map::kpv_slippy point 2tile point

namespace eval ::map::kpv_slippy {
    namespace export length tiles tile geo point
    namespace ensemble create
    
    variable pi [expr {acos(-1)}]
    variable radtodeg  [expr {180/acos(-1)}]    ;# Conversion from radians to degrees
    variable degtorad  [expr {acos(-1)/180}]    ;# Conversion from degrees to radians
    variable ourtilesize 256
}
namespace eval ::map::kpv_slippy::tile {
    namespace export size valid 2geo 2point
    namespace ensemble create

    variable pi [set [namespace parent]::pi]
    variable radtodeg [set [namespace parent]::radtodeg]
    variable degtorad [set [namespace parent]::degtorad]
    variable ourtilesize [set [namespace parent]::ourtilesize]
}
namespace eval ::map::kpv_slippy::geo {
    namespace export size valid 2tile 2point
    namespace ensemble create
    variable pi [set [namespace parent]::pi]
    variable radtodeg [set [namespace parent]::radtodeg]
    variable degtorad [set [namespace parent]::degtorad]
    variable ourtilesize [set [namespace parent]::ourtilesize]
}
namespace eval ::map::kpv_slippy::point {
    namespace export size valid 2tile 2geo
    namespace ensemble create
    variable pi [set [namespace parent]::pi]
    variable radtodeg [set [namespace parent]::radtodeg]
    variable degtorad [set [namespace parent]::degtorad]
    variable ourtilesize [set [namespace parent]::ourtilesize]
}
proc ::map::kpv_slippy::length {level} {
    variable ourtilesize
    return [expr {$ourtilesize * [::map::kpv_slippy::tiles $level]}]
}
proc ::map::kpv_slippy::tiles {level} { return [expr {1 << $level}] }
proc ::map::kpv_slippy::tile::size {} {
    variable ourtilesize
    return $ourtilesize
}
proc ::map::kpv_slippy::tile::valid {tile levels {msgvar {}}} { error "not implemented" }
proc ::map::kpv_slippy::tile::2geo {tile} {
    ::variable radtodeg
    ::variable pi
    foreach {zoom row col} $tile break
    # Note: For integer row/col the geo location is for the upper
    #       left corner of the tile. To get the geo location of
    #       the center simply add 0.5 to the row/col values.
    set tiles [::map::kpv_slippy::tiles $zoom]
    set lat   [expr {$radtodeg * (atan(sinh($pi * (1 - 2 * $row / double($tiles)))))}]
    set lon   [expr {$col / double($tiles) * 360.0 - 180.0}]
    return [list $zoom $lat $lon]
}    
proc ::map::kpv_slippy::tile::2point {tile} {
    variable ourtilesize
    foreach {zoom row col} $tile break
    # Note: For integer row/col the pixel location is for the
    #       upper left corner of the tile. To get the pixel
    #       location of the center simply add 0.5 to the row/col
    #       values.
    #set tiles [tiles $zoom]
    set y     [expr {$ourtilesize * $row}]
    set x     [expr {$ourtilesize * $col}]
    return [list $zoom $y $x]
}
proc ::map::kpv_slippy::geo::2tile {geo {fraction 0}} {
    ::variable degtorad
    ::variable pi
    foreach {zoom lat lon} $geo break 
    # lat, lon are in degrees.
    # The missing sec() function is computed using the 1/cos equivalency.
    set tiles  [::map::kpv_slippy::tiles $zoom]
    set latrad [expr {$degtorad * $lat}]
    set row    [expr {(1 - (log(tan($latrad) + 1.0/cos($latrad)) / $pi)) / 2 * $tiles}]
    set col    [expr {(($lon + 180.0) / 360.0) * $tiles}]
    if {! $fraction} {
	set row [expr {int($row)}]
	set col [expr {int($col)}]
    }
    return [list $zoom $row $col]
}
proc ::map::kpv_slippy::geo::2point {geo} {
    ::variable degtorad
    ::variable pi
    ::variable ourtilesize
    foreach {zoom lat lon} $geo break 
    # Essence: [geo 2tile $geo] * $ourtilesize, with 'geo 2tile' inlined.
    set tiles  [::map::kpv_slippy::tiles $zoom]
    set latrad [expr {$degtorad * $lat}]
    set y      [expr {$ourtilesize * ((1 - (log(tan($latrad) + 1.0/cos($latrad)) / $pi)) / 2 * $tiles)}]
    set x      [expr {$ourtilesize * ((($lon + 180.0) / 360.0) * $tiles)}]
    #KPV set y      [expr {$tiles * ((1 - (log(tan($latrad) + 1.0/cos($latrad)) / $pi)) / 2 * $tiles)}]
    #KPV set x      [expr {$tiles * ((($lon + 180.0) / 360.0) * $tiles)}]
    return [list $zoom $y $x]
}
proc ::map::kpv_slippy::point::2tile {point} {
    ::variable ourtilesize
    foreach {zoom y x} $point break
    #set tiles [tiles $zoom]
    set row   [expr {double($y) / $ourtilesize}]
    set col   [expr {double($x) / $ourtilesize}]
    return [list $zoom $row $col]
}
proc ::map::kpv_slippy::point::2geo {point} {
    #set tile [::map::kpv_slippy::point::2tile $point]
    #set geo [::map::kpv_slippy::tile::2geo $tile]
    #return $geo
    ::variable radtodeg
    ::variable pi
    ::variable ourtilesize
    foreach {zoom y x} $point break
    set length [expr {1.0 * $ourtilesize * [::map::kpv_slippy::tiles $zoom]}]
    set lat    [expr {$radtodeg * (atan(sinh($pi * (1 - 2 * $y / $length))))}]
    set lon    [expr {$x / $length * 360.0 - 180.0}]
    return [list $zoom $lat $lon]
}

proc ::map::kpv_slippy::tiles {level} {
    return [expr {1 << $level}]
}


;# proc ::map::kpv_slippy::_geo_2tile {geo} {
;#     ::variable degtorad
;#     ::variable pi
;#     foreach {zoom lat lon} $geo break 
;#     # lat, lon are in degrees.
;#     # The missing sec() function is computed using the 1/cos equivalency.
;#     set tiles  [::map::kpv_slippy::tiles $zoom]
;#     set latrad [expr {$degtorad * $lat}]
;#     set row    [expr {int((1 - (log(tan($latrad) + 1.0/cos($latrad)) / $pi)) / 2 * $tiles)}]
;#     set col    [expr {int((($lon + 180.0) / 360.0) * $tiles)}]
;#     return [list $zoom $row $col]
;# }

;# proc ::map::kpv_slippy::_geo_2point {geo} {
;#     ::variable degtorad
;#     ::variable pi
;#     foreach {zoom lat lon} $geo break 
;#     # Essence: [geo 2tile $geo] * $ourtilesize, with 'geo 2tile' inlined.
;#     set tiles  [::map::kpv_slippy::tiles $zoom]
;#     set latrad [expr {$degtorad * $lat}]
;#     set y      [expr {$ourtilesize * ((1 - (log(tan($latrad) + 1.0/cos($latrad)) / $pi)) / 2 * $tiles)}]
;#     set x      [expr {$ourtilesize * ((($lon + 180.0) / 360.0) * $tiles)}]
;#     return [list $zoom $y $x]
;# }
;# proc ::map::kpv_slippy::_tile_2geo {tile} {
;#     ::variable radtodeg
;#     ::variable pi
;#     foreach {zoom row col} $tile break
;#     # Note: For integer row/col the geo location is for the upper
;#     #       left corner of the tile. To get the geo location of
;#     #       the center simply add 0.5 to the row/col values.
;#     set tiles [::map::kpv_slippy::tiles $zoom]
;#     set lat   [expr {$radtodeg * (atan(sinh($pi * (1 - 2 * $row / double($tiles)))))}]
;#     set lon   [expr {$col / double($tiles) * 360.0 - 180.0}]
;#     return [list $zoom $lat $lon]
;# }

;# proc ::map::kpv_slippy::_tile_2point {tile} {
;#     foreach {zoom row col} $tile break
;#     # Note: For integer row/col the pixel location is for the
;#     #       upper left corner of the tile. To get the pixel
;#     #       location of the center simply add 0.5 to the row/col
;#     #       values.
;#     set tiles [::map::kpv_slippy::tiles $zoom]
;#     set y     [expr {$tiles * $row}]
;#     set x     [expr {$tiles * $col}]
;#     return [list $zoom $y $x]
;# }

;# proc ::map::kpv_slippy::_point_2geo {point} {
;#     ::variable radtodeg
;#     ::variable pi
;#     foreach {zoom y x} $point break
;#     set length [expr {$ourtilesize * [::map::kpv_slippy::tiles $zoom]}]
;#     set lat    [expr {$radtodeg * (atan(sinh($pi * (1 - 2 * $y / $length))))}]
;#     set lon    [expr {$x / $length * 360.0 - 180.0}]
;#     return [list $zoom $lat $lon]
;# }

;# proc ::map::kpv_slippy::_point_2tile {point} {
;#     foreach {zoom y x} $point break
;#     set tiles [::map::kpv_slippy::tiles $zoom]
;#     set row   [expr {$y / $tiles}]
;#     set col   [expr {$x / $tiles}]
;#     return [list $zoom $y $x]
;# }

package provide map::kpv_slippy 0.4

return

