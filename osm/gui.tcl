#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
exec tclsh $0 ${1+"$@"}

##+##########################################################################
#
# gui.tcl -- GUI on top of XML exported data
# by Keith Vetter 2018-11-23
#
# TODO: name filter intersects with highway/surface filter

package require Tk
package require tooltip

source osm_lib.tsh
source button_listbox.tcl

set ST(osm,dir) "~/misc/klimb/osm"
set ST(osm,url) "https://www.openstreetmap.org/way/"

set S(osm,dom) ""
set S(osm,site,last) "none"
set S(osm,bounds) "no bounds"

image create photo ::img::down -file /Library/Tcl/wub-5.0.0/Domains/Introspect/images/16x16/Down.png
image create photo ::img::erase -file /Library/Tcl/wub-5.0.0/Domains/Introspect/images/16x16/Erase.png
image create photo ::img::zoom -file /Library/Tcl/wub-5.0.0/Domains/Introspect/images/16x16/Zoom.png

proc DoDisplay {} {
    pack [::ttk::frame .banner] -side top -fill x
    ::ttk::label .banner.lbl -text "OpenStreetMap XML Data" -font {Helvetica 36 bold}
    pack .banner.lbl -side top

    # Holds road blurbs
    ::ttk::scrollbar .sb_t -orient vertical -command {.blurbs yview}
    text .blurbs -exportselection 0 -yscroll {.sb_t set} -width 60
    .blurbs tag config banner -background red
    pack .sb_t -side right -fill y
    pack .blurbs -side right -fill both -expand 1

    ::ttk::frame .f -borderwidth 2 -relief solid
    pack .f -side top -fill x
    ::ttk::labelframe .f.osm -text "OSM Data"
    ::ttk::labelframe .f.names -text "Road Names"
    ::ttk::labelframe .f.ids -text "OSM Id"
    ::ttk::labelframe .f.highway -text "Highway Type"
    ::ttk::labelframe .f.surface -text "Surface Type"
    ::ttk::labelframe .f.waterway -text "Waterway Type"
    ::ttk::button .f.filter -text Filter -command FillInWaysDisplay
    grid .f.osm .f.names .f.highway .f.surface .f.waterway -sticky ewn
    grid ^      .f.ids    ^          ^          ^ -sticky ewn
    grid columnconfig .f {0 1 2} -weight 1
    grid .f.filter - - - -pady {0 .1i}

    ::ttk::frame .fways -borderwidth 2 -relief solid
    pack .fways -side left -fill both -expand 1

    set headers {Id Surface Highway Waterway Name Nodes}
    set hwidths {100 70 70 70 150}
    ButtonListBox::Create .fways $headers $hwidths
    .fways.tree config -height 20
    bind .fways.tree <<ButtonListBoxPress>> {ShowWayInfo %d}

    # On macos, after some updates we get black sections on the window. This fixes it.
    # bind .ways <Configure> {apply {{} {.ways config -bg [.ways cget -bg]}}}
}

proc PopulateSelectFilters {} {
    if {[winfo child .f.osm] eq {}} {
        set sites [ListOSMSites]
        ::ttk::labelframe .f.osm.sites -text "XML File"
        tk_optionMenu .f.osm.sites.sites ::S(osm,site) {*}$sites
        for {set i 0} {$i <= [[.f.osm.sites.sites cget -menu] index end]} {incr i} {
            [.f.osm.sites.sites cget -menu] entryconfig $i -command NewSite
        }
        ::ttk::labelframe .f.osm.bounds -text "Bounds"
        ::ttk::label .f.osm.bounds.bounds -textvariable ::S(osm,bounds)
        pack .f.osm.sites .f.osm.bounds -side top -fill x -pady {0 .2i}
        pack .f.osm.sites.sites
        pack .f.osm.bounds.bounds

        foreach key {"Anything" "Non-empty" "Contains"} {
            set key2 [string tolower [string map {" " "" "-" ""} $key]]
            ::ttk::radiobutton .f.names.$key2 -text $key -variable ::S(osm,filter_name) -value $key2
        }
        set ::S(osm,filter_name) "anything"
        set ::S(osm,filter_name,match) ""
        pack {*}[winfo children .f.names] -side top -anchor w
        ::ttk::entry .f.names.match_value -textvariable ::S(osm,filter_name,match) -width 10
        bind .f.names.match_value <FocusIn> {set ::S(osm,filter_name) contains}
        pack .f.names.match_value -padx {.2i 0} -side top -fill x

        set ::S(osm,filter_id,onoff) 0
        set ::S(osm,filter_id,value) ""
        ::ttk::checkbutton .f.ids.cb -text "Id Value" -variable ::S(osm,filter_id,onoff)
        ::ttk::entry .f.ids.value -textvariable ::S(osm,filter_id,value) -width 10
        pack .f.ids.cb -side top -anchor w
        pack .f.ids.value -padx {.2i 0} -side top -fill x
    }
    foreach who {highway surface waterway} {
        array unset ::S osm,filter,$who,*
        set w .f.$who
        destroy {*}[winfo children $w]
        set labels [::osmlib::UniqueTagAttributes $::S(osm,dom) $who]
        foreach label $labels {
            set wl "$w.$label"
            set ::S(osm,filter,$who,$label) 0
            ::ttk::checkbutton $wl -text $label -variable ::S(osm,filter,$who,$label)
            pack $wl -side top -fill both -padx {.25i 0}
        }
    }
}


proc ::tcl::dict::get? {d args} {
    if {[dict exists $d {*}$args]} { return [dict get $d {*}$args] }
    return {}
}
namespace ensemble configure dict -map \
    [dict merge [namespace ensemble configure dict -map] {get? ::tcl::dict::get?}]

proc NewSite {} {
    global S
    if {$S(osm,site,last) == $S(osm,site)} return
    label .busy -text "Loading data for\n$S(osm,site)" -font "Helvetica 36 bold" \
        -bd 5 -relief solid -bg cyan
    place .busy -in . -relx .5 -rely .5 -anchor c
    update
    set S(osm,site,last) $S(osm,site)

    unset -nocomplain S(osm,dom)
    set S(osm,xml) [file join $::ST(osm,dir) "$S(osm,site).xml"]
    set S(osm,dom) [::osmlib::NewSiteDom $S(osm,xml)]

    set bounds [regsub -all {0+ |0+$} [::osmlib::Bounds $S(osm,dom)] " "]
    lassign $bounds lat0 lon0 lat1 lon1
    set S(osm,bounds) "$lat0\t$lon0\n$lat1\t$lon1"
    PopulateSelectFilters
    DeleteBlurbs
    FillInWaysDisplay
    destroy .busy
}
proc ListOSMSites {} {
    set globs [glob -tail -directory $::ST(osm,dir) -- *.xml]
    set sites [lsort -dictionary [lmap site $globs { file rootname $site }]]
    return $sites
}
proc FillInWaysDisplay {} {
    global S

    ::ButtonListBox::Clear .fways.tree
    set S(osm,ways) [ExtractWaysWithFilter]
    set S(osm,ids) [dict keys $S(osm,ways)]
    foreach id $S(osm,ids) {
        set surface [dict get? $S(osm,ways) $id tags surface]
        if {$surface eq ""} {
            set isBuilding [expr {[dict get? $S(osm,ways) $id tags building] == "yes"}]
            if {$isBuilding} { set surface "building" }
        }
        set highway [dict get? $S(osm,ways) $id tags highway]
        set waterway [dict get? $S(osm,ways) $id tags waterway]
        set name [dict get? $S(osm,ways) $id tags name]
        set nodeCount [GetWayNodeCount $id]
        ::ButtonListBox::AddItem .fways.tree [list $id $surface $highway $waterway $name $nodeCount]
    }
}

proc ExtractWaysWithFilter {} {
    global S
    lassign [GetFilters] roadFilters nameFilters idFilter


    if {$idFilter ne {}} {
        set ids [::osmlib::FilteredRoads $S(osm,dom) $idFilter]
        return $ids
    }

    if {$roadFilters eq {}} {
        set roads [::osmlib::FilteredRoads $S(osm,dom) $nameFilters]
        return $roads
    }
    if {$nameFilters eq {}} {
        set names [::osmlib::FilteredRoads $S(osm,dom) $roadFilters]
        return $names
    }
    set roads [::osmlib::FilteredRoads $S(osm,dom) $roadFilters]
    set names [::osmlib::FilteredRoads $S(osm,dom) $nameFilters]
    set result [IntersectDicts $roads $names]
    return $result
}
proc IntersectDicts {d1 d2} {
    set result [dict create]
    dict for {key value} $d1 {
        if {[dict exists $d2 $key]} {
            dict set result $key $value
        }
    }
    return $result
}

proc GetFilters {} {
    global S

    set filters [lmap key [array names ::S osm,filter,*] {
        if {$::S($key) == 0} continue
        lrange [split $key ","] 2 3
    }]
    set nameFilters {}
    if {$S(osm,filter_name) ne "anything"} {
        lappend nameFilters [list name $S(osm,filter_name) $S(osm,filter_name,match)]
    }

    set idFilter {}
    if {$S(osm,filter_id,onoff)} {
        foreach value [regexp -inline -all {\w+} $S(osm,filter_id,value)] {
            lappend idFilter [list id contains $value]
        }
    }
    return [list $filters $nameFilters $idFilter]
}

proc GetWayInfo {wayId} {
    global S WAY

    if {[info exists WAY($wayId)]} {
        return $WAY($wayId)
    }
    set tags [dict get $S(osm,ways) $wayId tags]
    ShowBlurbMessage "getting node references\n"
    set ndRefs [::osmlib::AllNodeRefs $S(osm,dom) $wayId]
    ShowBlurbMessage "getting waypoints\n"
    set wpts [::osmlib::AllNodeLatLon $S(osm,dom) $ndRefs]
    ShowBlurbMessage "computing distance\n"
    set dist [TotalDistance $wpts]
    set url [string cat $::ST(osm,url) $wayId]
    set WAY($wayId) [dict create id $wayId tags $tags wpts $wpts dist $dist url $url]
    return $WAY($wayId)
}
proc GetWayNodeCount {wayId} {
    set count [llength [::osmlib::AllNodeRefs $::S(osm,dom) $wayId]]
    return $count
}
proc TotalDistance {wpts} {
    lassign [lindex $wpts 0] . lat0 lon0
    set distance 0
    foreach wpt [lrange $wpts 1 end] {
        lassign $wpt . lat lon
        set leg [Distance $lat0 $lon0 $lat $lon]
        set distance [expr {$distance + $leg}]

        set lat0 $lat
        set lon0 $lon
    }
    return $distance
}
proc ShowBlurbMessage {msg} {
    set where [lindex [concat 0.0 [.blurbs tag ranges banner]] end]
    .blurbs insert $where $msg banner
    update
}
proc ShowWayInfo {wayId} {
    .blurbs config -state normal
    if {! [info exists ::WAY($wayId)]} {
        ShowBlurbMessage "Extracting info about $wayId\n"
        update
        GetWayInfo $wayId
        foreach {hi lo} [lreverse [.blurbs tag ranges banner]] {
            .blurbs delete $lo $hi
        }
    }

    set way [GetWayInfo $wayId]
    set w .blurbs.$wayId
    destroy $w
    ::ttk::frame $w -borderwidth 2 -relief solid -width 200

    set msg "Id:\t[dict get $way id]\n"
    append msg "Name:\t[dict get? [dict get $way tags] name]\n"
    append msg "Url:\t[dict get $way url]\n"
    append msg "Distance:\t[PrettyDistance [dict get $way dist]]\n"
    append msg "Count:\t[llength [dict get $way wpts]]\n"
    append msg "Tags:"
    dict for {key value} [dict get $way tags] {
        append msg "\n  $key:\t$value"
    }
    ::ttk::label $w.msg -text $msg
    ::ttk::frame $w.buttons
    ::ttk::button $w.buttons.zoom -image ::img::zoom -command [list OpenUrl [dict get $way url]]
    ::tooltip::tooltip $w.buttons.zoom "View on OpenStreetMaps"
    ::ttk::button $w.buttons.down -image ::img::down -command [list Download $w $wayId]
    ::tooltip::tooltip $w.buttons.down "Download road data"
    ::ttk::button $w.buttons.erase -image ::img::erase -command [list DestroyBlurb $w]
    ::tooltip::tooltip $w.buttons.erase "Remove this blurb"

    pack $w.msg -side left -fill y
    pack $w.buttons.zoom $w.buttons.down $w.buttons.erase -side left -anchor n
    place $w.buttons -relx 1 -rely 0 -anchor ne
    .blurbs window create 0.0 -window $w
}
##+##########################################################################
#
# Distance -- Computes the great circle distance between two points
#
proc Distance {lat1 lon1 lat2 lon2 {feet 0}} {
    set y1 $lat1
    set x1 $lon1
    set y2 $lat2
    set x2 $lon2

    set pi [expr {acos(-1)}]
    set x1 [expr {$x1 * 2 * $pi / 360.0}]            ;# Convert degrees to radians
    set x2 [expr {$x2 * 2 * $pi / 360.0}]
    set y1 [expr {$y1 * 2 * $pi / 360.0}]
    set y2 [expr {$y2 * 2 * $pi / 360.0}]
    # calculate distance:
    ##set d [expr {acos(sin($y1)*sin($y2)+cos($y1)*cos($y2)*cos($x1-$x2))}]
    set d [expr {sin($y1)*sin($y2)+cos($y1)*cos($y2)*cos($x1-$x2)}]
    if {abs($d) > 1.0} {                        ;# Rounding error
        set d [expr {$d > 0 ? 1.0 : -1.0}]
    }
    set d [expr {acos($d)}]

    set meters [expr {20001600/$pi*$d}]
    set miles [expr {$meters * 100 / 2.54 / 12 / 5280}]
    if {$feet} {
        return [expr {$miles * 5280}]
    }
    return $miles
}

proc PrettyDistance {dist} {
    if {$dist < .7} {
        return "[expr {round($dist * 5280)}] ft"
    }
    return [format "%.3g mi" $dist]
}
proc OpenUrl {url} {
    exec open $url
}
proc DestroyBlurb {w} {
    destroy $w
    set wayId [string trim [file extension $w] "."]
    array unset ::WAY $wayId
}
proc DeleteBlurbs {} {
    foreach w [winfo children .blurbs] {
        DestroyBlurb $w
    }
}
proc Download {w wayId} {
    set kdata [Way2Klimb $wayId]
    set fname [string cat $::S(osm,site) ".nodes"]
    set fout [open $fname "a"]
    puts $fout $kdata
    close $fout

    SortNodeFile $fname
    DownloadBanner $w $fname
}
proc DownloadBanner {w fname} {
    set w2 [string cat $w .banner]
    destroy $w2
    label $w2 -text "Appended to $fname" -font {Times 32} -bd 2 -relief solid -fg red
    place $w2 -relx .5 -rely .25 -anchor c
    after 2000 [list destroy $w2]
}
proc Way2Klimb {wayId} {
    set way [GetWayInfo $wayId]
    set name [dict get? $way tags name]
    if {$name eq ""} { set name "OSM Road" }
    set wpts [dict get $way wpts]

    set result "# W Waypoint data\n"
    append result "# W id  lat lon alt usgs\n"
    foreach wpt $wpts {
        lassign $wpt nid lat lon
        set line "W [string cat W $nid] $lat $lon ?\n"
        append result $line
    }

    append result "\n# OSM Node Data\n"
    append result "# OSM waypoint name\n"
    set startId [string cat "W" [lindex $wpts 0 0]]
    set endId [string cat "W" [lindex $wpts end 0]]
    set line "OSM $startId\n"
    append result $line
    set line "OSM $endId\n"
    append result $line

    append result "\n# Road data\n"
    append result "# R roadid id1 id2 north distance south type name comment ...\n"
    set rid [string cat "R" $wayId]
    set line "R $rid $startId $endId ? ? ? 4 \"$name\" {} "
    set kpts [lmap pt [lrange $wpts 1 end-1] {string cat W [lindex $pt 0]}]
    append line "\{wpts $kpts\}\n"
    append result $line

    return $result
}
proc SortNodeFile {nodeFile} {
    set PREFIX(N) "# Node data\n# N nodeid \"description\" alt lat1 lat2 lat3 lon1 lon2 lon3 usgs"
    set PREFIX(N2) "# Node data\n# N wid \"description\""
    set PREFIX(R) "# Road data\n# R roadid id1 id2 north distance south type name comment xy survey"
    set PREFIX(W) "# W Waypoint data\n# W id  lat lon alt"

    set fin [open $nodeFile r]
    set lines [split [string trim [read $fin]] \n]
    close $fin

    unset -nocomplain SET
    unset -nocomplain ::DUPES
    foreach line $lines {
        set line [string trim $line]
        if {$line eq ""} continue
        if {[string match "#*" $line]} continue

        if {[info exists SET($line)]} {
            lappend ::dupes $line
        } else {
            set SET($line) 1
        }
    }

    set lines [lsort -dictionary [array names SET]]
    set outfile $nodeFile
    # set outfile /tmp/foo
    set fout [open $outfile w]
    set lastPrefix ""
    foreach line $lines {
        set prefix [string index $line 0]
        if {$prefix ne $lastPrefix} {
            puts $fout "\n"
            puts $fout $PREFIX($prefix)
            set lastPrefix $prefix
        }
        puts $fout $line
    }
    close $fout
}




################################################################
DoDisplay
set S(osm,site) teague_osm
NewSite

set url https://www.openstreetmap.org/way/580004290
return
https://www.openstreetmap.org/way/206146322

set bear_gulch 234787482


/System/Library/Tcl/tcl8/site-tcl
/System/Library/Tcl/tcl8/8.0
/System/Library/Tcl/tcl8/8.1
/System/Library/Tcl/tcl8/8.2
/System/Library/Tcl/tcl8/8.3
/System/Library/Tcl/tcl8/8.4
/System/Library/Tcl/tcl8/8.5
/System/Library/Tcl/tcl8/8.6
/Library/Tcl/tcl8/site-tcl
/Library/Tcl/tcl8/8.0
/Library/Tcl/tcl8/8.1
/Library/Tcl/tcl8/8.2
/Library/Tcl/tcl8/8.3
/Library/Tcl/tcl8/8.4
/Library/Tcl/tcl8/8.5
/Library/Tcl/tcl8/8.6
/Users/keith/Library/Tcl/tcl8/site-tcl
/Users/keith/Library/Tcl/tcl8/8.0
/Users/keith/Library/Tcl/tcl8/8.1
/Users/keith/Library/Tcl/tcl8/8.2
/Users/keith/Library/Tcl/tcl8/8.3
/Users/keith/Library/Tcl/tcl8/8.4
/Users/keith/Library/Tcl/tcl8/8.5
/Users/keith/Library/Tcl/tcl8/8.6
/Library/Frameworks/Tk.framework/Versions/8.6/Resources/Wish.app/Contents/lib/tcl8/site-tcl
/Library/Frameworks/Tk.framework/Versions/8.6/Resources/Wish.app/Contents/lib/tcl8/8.0
/Library/Frameworks/Tk.framework/Versions/8.6/Resources/Wish.app/Contents/lib/tcl8/8.1
/Library/Frameworks/Tk.framework/Versions/8.6/Resources/Wish.app/Contents/lib/tcl8/8.2
/Library/Frameworks/Tk.framework/Versions/8.6/Resources/Wish.app/Contents/lib/tcl8/8.3
/Library/Frameworks/Tk.framework/Versions/8.6/Resources/Wish.app/Contents/lib/tcl8/8.4
/Library/Frameworks/Tk.framework/Versions/8.6/Resources/Wish.app/Contents/lib/tcl8/8.5
/Library/Frameworks/Tk.framework/Versions/8.6/Resources/Wish.app/Contents/lib/tcl8/8.6
/Library/Frameworks/Tcl.framework/Versions/8.6/Resources/tcl8/site-tcl
/Library/Frameworks/Tcl.framework/Versions/8.6/Resources/tcl8/8.0
/Library/Frameworks/Tcl.framework/Versions/8.6/Resources/tcl8/8.1
/Library/Frameworks/Tcl.framework/Versions/8.6/Resources/tcl8/8.2
/Library/Frameworks/Tcl.framework/Versions/8.6/Resources/tcl8/8.3
/Library/Frameworks/Tcl.framework/Versions/8.6/Resources/tcl8/8.4
/Library/Frameworks/Tcl.framework/Versions/8.6/Resources/tcl8/8.5
/Library/Frameworks/Tcl.framework/Versions/8.6/Resources/tcl8/8.6
