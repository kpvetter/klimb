#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
exec tclsh $0 ${1+"$@"}

##+##########################################################################
#
# CheckedListBox.tcl -- creates multi-column checkedListBox using ttk::treeview
#  by Keith Vetter, March 2010
#
# API
#   ::CheckedListBox::Create parent headers ?headerSizes?
#   ::CheckedListBox::AddItem w itemData
#   ::CheckedListBox::AddManyItems w data
#   ::CheckedListBox::Clear w
#   ::CheckedListBox::ToggleAll w onOff
#   ::CheckedListBox::GetChecked w
#
namespace eval ::CheckedListBox {
    variable ButtonState
    unset -nocomplain ButtonState
}

##+##########################################################################
#
# ::CheckedListBox::Create -- Creates and packs a new tile table widget
# into a parent frame.
#
proc ::CheckedListBox::Create {parent headers {headerSizes {}}} {
    set w $parent.tree

    ::ttk::treeview $w -columns $headers  \
        -yscroll "$parent.vsb set" -xscroll "$parent.hsb set"
    scrollbar $parent.vsb -orient vertical -command "$w yview"
    scrollbar $parent.hsb -orient horizontal -command "$w xview"

    # Set up headings and widths
    set font [::ttk::style lookup [$w cget -style] -font]
    foreach col $headers hSize $headerSizes {
        $w heading $col -text $col -anchor c \
            -image ::CheckedListBox::arrowBlank \
            -command [list ::CheckedListBox::_SortBy $w $col 0]
        if {[string is integer -strict $hSize]} {
            $w column $col -width $hSize
        } else {
            if {$hSize eq ""} { set hSize $col }
            set width [font measure $font $hSize]
            $w column $col -width $width
        }
    }
    # Fix up heading #0 (over the tree section)
    $w heading \#0 -command [list ::CheckedListBox::_SortBy $w \#0 1] \
        -image ::CheckedListBox::arrowBlank
    $w column \#0 -width 38 -stretch 0

    #bind $w <<TreeviewSelect>> {set ::id [%W selection]} ;# Debugging
    bind $w <1> [list ::CheckedListBox::_ButtonPress %W %x %y]
    bind $w <space> [list ::CheckedListBox::_SpaceKeyPress %W]

    grid $w $parent.vsb -sticky nsew
    grid $parent.hsb          -sticky nsew
    grid column $parent 0 -weight 1
    grid row    $parent 0 -weight 1

    return $w
}
proc ::CheckedListBox::AddItem {w itemData} {
    variable ButtonState

    set id [$w insert {} end -text "" -image ::img::cb(0) -values $itemData]
    $w item $id -tags $id ;# For banding
    set ButtonState($w,$id) 0
    ::CheckedListBox::_BandTable $w
    return $id
}
##+##########################################################################
#
# ::CheckedListBox::AddManyItems -- Fills in tree with given data
#
proc ::CheckedListBox::AddManyItems {w data} {
    variable ButtonState

    array unset ButtonState $w,*
    $w delete [$w child {}]
    set lnum -1
    foreach datum $data {
        set id [$w insert {} end -values $datum -text "" -image ::img::cb(0)]
        $w item $id -tags $id
        set ButtonState($w,$id) 0
    }
    ::CheckedListBox::_SortBy $w [$w heading #1 -text] 0
    ::CheckedListBox::_BandTable $w
}
##+##########################################################################
#
# ::CheckedListBox::Clear -- Deletes all items
#
proc ::CheckedListBox::Clear {w} {
    variable ButtonState

    array unset ButtonState $w,*
    $w delete [$w child {}]
}
##+##########################################################################
#
# ::CheckedListBox::ToggleAll -- Turns on or off all items
#
proc ::CheckedListBox::ToggleAll {w how} {
    variable ButtonState

    foreach id [$w child {}] {
        set ButtonState($w,$id) $how
        $w item $id -image ::img::cb($how)
    }
}
##+##########################################################################
#
# ::CheckedListBox::GetChecked -- Returns id's of all checked items
#
proc ::CheckedListBox::GetChecked {w} {
    variable ButtonState

    set who {}
    foreach id [$w child {}] {
        if {$ButtonState($w,$id)} {
            lappend who $id
        }
    }
    return $who
}
#
# Internal routines
#
image create bitmap ::CheckedListBox::arrow(0) -data {
    #define arrowUp_width 7
    #define arrowUp_height 4
    static char arrowUp_bits[] = {
        0x08, 0x1c, 0x3e, 0x7f
    };
}
image create bitmap ::CheckedListBox::arrow(1) -data {
    #define arrowDown_width 7
    #define arrowDown_height 4
    static char arrowDown_bits[] = {
        0x7f, 0x3e, 0x1c, 0x08
    };
}
image create bitmap ::CheckedListBox::arrowBlank -data {
    #define arrowBlank_width 7
    #define arrowBlank_height 4
    static char arrowBlank_bits[] = {
        0x00, 0x00, 0x00, 0x00
    };
}
image create photo ::img::cb(0) -data {
    R0lGODlhDwAPANUAANnZ2Y6Pj/T09K6zua+0urS5vbu+wcvP1dDT2NXY3Nvd38HDxc3R1tLV2tjb
    3t3f4eLj5MbHyM3R19DU2dTX2+Hi4+Xm5ujo6MzNzbK3vNrc3+Dh4+zs7O3t7dTV1ri7v+Tl5erq
    6u/v7/Ly8tzd3ry/wuPk5enp6fX19eHi4sLExvDw8Pb29ubm5srLzNTU1dvb3ODh4ebn5+rr6+vs
    7Ovr7Onp6v///////////////////////////////////yH5BAEAAAAALAAAAAAPAA8AAAZvQIBw
    SCwCAsikMikMCJ7QqCDQFAyuWELBMK0ODuADIqFYdI9WMKPheEAiZ+dAMqEoKpYLJi7IJDQbFxwd
    HR58Hw8gISIjjSR8JSYnHSMCKAIpfCqTKwIsny18Li8wMTIzNDU2fFJSVEdLsa9GtABBADs=}
image create photo ::img::cb(1) -data {
    R0lGODlhDwAPAOYAANnZ2Y6Pj/T09Pj4+Pn5+fb29q6zucnM0J2nwHeGq9zf5PX19cvP1czQ1u3u
    8VdqnURakrm/0M3R1uDi5q+4z0VakmV3pefn6NXZ3d/i5dXY3PLz9F5xoUdclLzD1tvc3MXJzcnP
    3aOuyO3u7rrB1UlelmR2pdXV1t7g4W5/qs/U4md4p0tgl7e/1dzd3s3P0d7h6UhdlUlflmFzpPj5
    +uHi4sbIyurs8IuZu0pfl0xhmLC50ebm5srLzNra29/i6YyZupCdvfLz9uzt7evr7Onp6v//////
    ////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////
    /////////////////////////////////////////////////////////////////////////yH5
    BAEAAAAALAAAAAAPAA8AAAeFgACCg4SFAAGIiYqJggECj5ACAwQFAgGNAgaamgcICQoLl4eZDKUN
    Dg8QEQWijgalEhMUFRYXlpgGGBkaGxwdHh+3oyAhIiMkJSYDJ8KOKCkdKissLQUuzQIvMDEyLDM0
    AjXYNjc4OTo7lDzYPT4/QEFCQ0RF2I8LBAMLka2L/qKGAgIIBAA7}

##+##########################################################################
#
# ::CheckedListBox::_SortBy -- Code to sort tree content when clicked on a header
#
proc ::CheckedListBox::_SortBy {tree col direction} {
    variable ButtonState

    # Build something we can sort
    set data {}
    foreach row [$tree children {}] {
        if {$col eq "\#0"} {
            lappend data [list $ButtonState($tree,$row) $row]
        } else {
            lappend data [list [$tree set $row $col] $row]
        }
    }

    set dir [expr {$direction ? "-decreasing" : "-increasing"}]
    set r -1

    # Now reshuffle the rows into the sorted order
    foreach rinfo [lsort -dictionary -index 0 $dir $data] {
        $tree move [lindex $rinfo 1] {} [incr r]
    }

    # Switch the heading command so that it will sort in the opposite direction
    set cmd [list ::CheckedListBox::_SortBy $tree $col [expr {!$direction}]]
    $tree heading $col -command $cmd
    ::CheckedListBox::_BandTable $tree
    ::CheckedListBox::_ArrowHeadings $tree $col $direction
}
##+##########################################################################
#
# ::CheckedListBox::_ArrowHeadings -- Puts in up/down arrows to show sorting
#
proc ::CheckedListBox::_ArrowHeadings {tree sortCol dir} {
    set idx -1
    foreach col [$tree cget -columns] {
        incr idx
        set img ::CheckedListBox::arrowBlank
        if {$col == $sortCol} {
            set img ::CheckedListBox::arrow($dir)
        }
        $tree heading $idx -image $img
    }
    set img ::CheckedListBox::arrowBlank
    if {$sortCol eq "\#0"} {
        set img ::CheckedListBox::arrow($dir)
    }
    $tree heading "\#0" -image $img
}
##+##########################################################################
#
# ::CheckedListBox::_BandTable -- Draws bands on our table
#
proc ::CheckedListBox::_BandTable {tree} {
    return
    array set colors {0 white 1 \#aaffff}

    set id 0
    foreach row [$tree children {}] {
        set id [expr {! $id}]
        set tag [$tree item $row -tag]
        $tree tag configure $tag -background $colors($id)
    }
}
##+##########################################################################
#
# ::CheckedListBox::_ButtonPress -- handles mouse click which can
#  toggle checkbutton, control selection or resize headings.
#
proc ::CheckedListBox::_ButtonPress {w x y} {
    variable ButtonState

    lassign [$w identify $x $y] what id detail

    # Disable resizing heading #0
    if {$what eq "separator" && $id eq "\#0"} {
        return -code break
    }
    if {$what ne "item"} return

    # Here when clicking near the checkedbox
    set new [expr {! $ButtonState($w,$id)}]
    set ButtonState($w,$id) $new
    $w item $id -image ::img::cb($new)

    # Multi-line : make all like the one just clicked
    set select [$w selection]
    if {[llength $select] > 1 && $id in $select} {
        foreach id2 $select {
            set ButtonState($w,$id2) $new
            $w item $id2 -image ::img::cb($new)
        }
    }
    return -code break
}
##+##########################################################################
#
# ::CheckedListBox::_SpaceKeyPress -- toggles selected rows on or off
#
proc ::CheckedListBox::_SpaceKeyPress {w} {
    variable ButtonState

    set how 0
    set select [$w selection]
    # If any selected items are off, turn all on
    foreach id $select {
        if {$ButtonState($w,$id) == 0} {
            set how 1
            break
        }
    }
    foreach id $select {
        set ButtonState($w,$id) $how
        $w item $id -image ::img::cb($how)
    }
}
#
# Demo code
#
set help {
    CheckedListBox Widget
    by Keith Vetter, March 2010

    A scrollable multi-column list of checkboxes.

    Behavior:
    o clicking the checkbox toggles that row on or off.
      o clicking any heading sorts that column--twice for reverse sort.
      o when one or more rows are selected
         - clicking the checkbox turns all on or off
         - space bar toggles all on or off
      o all columns are resizeable
}

set headers {Year Games AB Runs Hits 2B 3B HR RBI BB SO BA OBP SLG}
set hSizes {46 46 47 46 45 46 48 48 47 46 49 42 51 46}
set data {
 {1939 149 565 131 185 44 11 31 145 107 64 .327 .436 .609}
 {1940 144 561 134 193 43 14 23 113 96 54 .344 .442 .594}
 {1941 143 456 135 185 33 3 37 120 147 27 .406 .553 .735}
 {1942 150 522 141 186 34 5 36 137 145 51 .356 .499 .648}
 {1946 150 514 142 176 37 8 38 123 156 44 .342 .497 .667}
 {1947 156 528 125 181 40 9 32 114 162 47 .343 .499 .634}
 {1948 137 509 124 188 44 3 25 127 126 41 .369 .497 .615}
 {1949 155 566 150 194 39 3 43 159 162 48 .343 .490 .650}
 {1950 89 334 82 106 24 1 28 97 82 21 .317 .452 .647}
 {1951 148 531 109 169 28 4 30 126 144 45 .318 .464 .556}
 {1952 6 10 2 4 0 1 1 3 2 2 .400 .500 .900}
 {1953 37 91 17 37 6 0 13 34 19 10 .407 .509 .901}
 {1954 117 386 93 133 23 1 29 89 136 32 .345 .513 .635}
 {1955 98 320 77 114 21 3 28 83 91 24 .356 .496 .703}
 {1956 136 400 71 138 28 2 24 82 102 39 .345 .479 .605}
 {1957 132 420 96 163 28 1 38 87 119 43 .388 .526 .731}
 {1958 129 411 81 135 23 2 26 85 98 49 .328 .458 .584}
 {1959 103 272 32 69 15 0 10 43 52 27 .254 .372 .419}
 {1960 113 310 56 98 15 0 29 72 75 41 .316 .451 .645}
}
proc Demo {w} {
    set items [::CheckedListBox::GetChecked $w]
    if {$items eq {}} {
        set msg "nothing"
    } else {
        set msg ""
        foreach item $items { append msg [$w set $item Year] " " }
    }
    tk_messageBox -message $msg
}

wm title . "CheckedListBox Demo"
::ttk::setTheme alt ;# Windows ttk::treeview themes don't show selection
::ttk::frame .f
pack .f -side top -fill both -expand 1
set w [::CheckedListBox::Create .f $headers $hSizes]
::CheckedListBox::AddManyItems $w $data
::ttk::button .b -text "What's Checked" -command [list Demo $w]
::ttk::button .help -text "About" -command [list tk_messageBox -message $help]
pack .b .help -side left -pady .2i -expand 1

return
