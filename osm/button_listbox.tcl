##+##########################################################################
#
# button_listbox.tcl -- Multicolumn list box with column 0 a button image
# which generates <<ButtonListBoxPress>> -data $id

# by Keith Vetter 2018-11-25

namespace eval ::ButtonListBox {
    variable banding 0
}

##+##########################################################################
#
# ::ButtonListBox::Create -- Creates and packs a new tile table widget
# into a parent frame.
#
proc ::ButtonListBox::Create {parent headers {headerSizes {}}} {
    set w $parent.tree

    ::ttk::treeview $w -columns $headers  \
        -yscroll "$parent.vsb set" -xscroll "$parent.hsb set"
    scrollbar $parent.vsb -orient vertical -command "$w yview"
    scrollbar $parent.hsb -orient horizontal -command "$w xview"

    # Set up headings and widths
    set font [::ttk::style lookup [$w cget -style] -font]
    foreach col $headers hSize $headerSizes {
        $w heading $col -text $col -anchor c \
            -image ::ButtonListBox::arrowBlank \
            -command [list ::ButtonListBox::_SortBy $w $col 0]
        if {[string is integer -strict $hSize]} {
            $w column $col -width $hSize
        } else {
            if {$hSize eq ""} { set hSize $col }
            set width [font measure $font [string cat $hSize $hSize]]
            $w column $col -width $width
        }
    }
    # Fix up heading #0 (over the tree section)
    # $w heading \#0 -command [list ::ButtonListBox::_SortBy $w \#0 1] \
    #     -image ::ButtonListBox::arrowBlank
    $w column \#0 -width 45 -stretch 0

    #bind $w <<TreeviewSelect>> {set ::id [%W selection]} ;# Debugging
    bind $w <1> [list ::ButtonListBox::_ButtonPress %W %x %y]

    grid $w $parent.vsb -sticky nsew
    grid $parent.hsb          -sticky nsew
    grid column $parent 0 -weight 1
    grid row    $parent 0 -weight 1

    return $w
}
proc ::ButtonListBox::AddItem {w itemData} {
    set id [$w insert {} end -text "" -image ::img::search -values $itemData]
    $w item $id -tags $id ;# For banding
    ::ButtonListBox::_BandTable $w
    return $id
}
##+##########################################################################
#
# ::ButtonListBox::AddManyItems -- Fills in tree with given data
#
proc ::ButtonListBox::AddManyItems {w data} {
    $w delete [$w child {}]
    foreach datum $data {
        set id [$w insert {} end -values $datum -text "" -image ::img::search]
        $w item $id -tags $id
    }
    ::ButtonListBox::_SortBy $w [$w heading #1 -text] 0
    ::ButtonListBox::_BandTable $w
}
##+##########################################################################
#
# ::ButtonListBox::Clear -- Deletes all items
#
proc ::ButtonListBox::Clear {w} {
    $w delete [$w child {}]
}
#
# Internal routines
#
image create bitmap ::ButtonListBox::arrow(0) -data {
    #define arrowUp_width 7
    #define arrowUp_height 4
    static char arrowUp_bits[] = {
        0x08, 0x1c, 0x3e, 0x7f
    };
}
image create bitmap ::ButtonListBox::arrow(1) -data {
    #define arrowDown_width 7
    #define arrowDown_height 4
    static char arrowDown_bits[] = {
        0x7f, 0x3e, 0x1c, 0x08
    };
}
image create bitmap ::ButtonListBox::arrowBlank -data {
    #define arrowBlank_width 7
    #define arrowBlank_height 4
    static char arrowBlank_bits[] = {
        0x00, 0x00, 0x00, 0x00
    };
}
image create photo ::img::search -data {
    iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAADrElEQVR42m2Sa0zTVxiHfwfaSgthCxTE
    uZlMdkn2wW26utlEwtQB2rUUicSJ4gRS7cBNXIlmSGCbcYuGbMsYirawoWSJyEAm09VOII6tYKmOS8cY
    tEBrL7b0Tiv08t9/zZa4ZOfDSc553/Pk5Pe8BI+s3cUljrzc3FSj6T41NjZOLn/bRv6+31tSSvH5m6hJ
    3e9kfFLnuaW88fi/b8ijgLJy6ZL8QhPL4fSjq7sLkrKSWL29/TK1Z88uWBxeHJO9//DiN3L2/wK2C8XT
    IoEgs3/gNn4bvYfJidFYXVxQRG3kb0RPZzfC4WWHRjOc9h/Aidr6D9LTMo72DfQl7ywsZI6MaKH+ZRDq
    X2/H6ufOK6jC4t0ofWsfDPqZaAo3dSHgXxzUaIYKYg3Ha+rChw5K42fn/kRvrwpTf+jAZDJgsVjg9/pw
    ov4kNBo1nlv7DGwOG9gJiejvU+FqdychlYer+C63b1Amq8KaJ7jwBJfQ/FUzrA/siI9jYqD/Jta9vAEe
    jxs/3rgGr9sJl28RPVev04COHFJT++E+p9fbVnmoHHHReDooOzo7rsDpciIaAbTaIWRlb8UDmwVnzzbC
    arbCanPAYrPjYptCSmSy4/XJKal1ktK3kchmwWRzoUUhh8NqRSgKDA8PIntLDuz0+bz8HDhJHExN6ZH4
    WAqq35UqyIFSycj42Nj6CEXhYTCIYCCAlasy8NKL67Gw4MDo6F28nv0Gpg163NOqEfAHQOjkCL2tfnK1
    lVRUvncyLX1VzbHqKlz7QYVbdDgUHazZOB/gcrnapOSku0ajsexNkZhTVCDEqTOfwevxwDCjh9fl+IJU
    HDl6msfbVF1cJIKitR3jEzpEIhGY5ueWv+/5bsU/E7okEOazdgrz8PGpM/DQZrxuN53H/CekXPLOhChf
    /MIrG9bRvltgNpsRCYVx32iEUtkb01xSVk5t2ZqLLD4PDQ2N8C76EA2FMDc7rSPSiiOB/Qf2sp99OhNN
    F1rh93ngcroxO2+AsrcnBpAcrqKyN2dBKMjBp6c/h9vpjFmaM+iDJE8gpj6qrYPda0dzkxwhmhwOLSMa
    jeIn1fUYYP/BCqp4VyFMJgs6Oq8gshxChIrARpshmZnPUw2NX0KlvIlLrS10exQJHDaeWrMWd9Q/xwDb
    tuVSX7ddwo7tefS39WCtYCF9ZQZYDAbIq/zNEcGO/LiZmUlqaEgNGg0Gkwk2J4HcGVbHADzea5RAVEB1
    d3XASauNoxXS40ziGXHRvwAVvrukyLa34QAAAABJRU5ErkJggg==}

##+##########################################################################
#
# ::ButtonListBox::_SortBy -- Code to sort tree content when clicked on a header
#
proc ::ButtonListBox::_SortBy {tree col direction} {

    # Build something we can sort
    # if {$col eq "\#0"} { set col [lindex [$tree cget -columns] 0] }
    set sortData [lmap row [$tree children {}] {list [$tree set $row $col] $row}]

    set dir [expr {$direction ? "-decreasing" : "-increasing"}]

    # Now reshuffle the rows into the sorted order
    set r -1
    foreach rinfo [lsort -dictionary -index 0 $dir $sortData] {
        $tree move [lindex $rinfo 1] {} [incr r]
    }

    # Switch the heading command so that it will sort in the opposite direction
    set cmd [list ::ButtonListBox::_SortBy $tree $col [expr {!$direction}]]
    $tree heading $col -command $cmd
    # if {$col eq [lindex [$tree cget -columns] 0]} {
    #     set cmd [list ::ButtonListBox::_SortBy $tree #0 [expr {!$direction}]]
    #     $tree heading #0 -command $cmd
    # }
    ::ButtonListBox::_BandTable $tree
    ::ButtonListBox::_ArrowHeadings $tree $col $direction
}
##+##########################################################################
#
# ::ButtonListBox::_ArrowHeadings -- Puts in up/down arrows to show sorting
#
proc ::ButtonListBox::_ArrowHeadings {tree sortCol dir} {
    set idx -1
    foreach col [$tree cget -columns] {
        incr idx
        set img ::ButtonListBox::arrowBlank
        if {$col == $sortCol} {
            set img ::ButtonListBox::arrow($dir)
        }
        $tree heading $idx -image $img
    }
    set img ::ButtonListBox::arrowBlank
    if {$sortCol eq "\#0"} {
        set img ::ButtonListBox::arrow($dir)
    }
    $tree heading "\#0" -image $img
}
##+##########################################################################
#
# ::ButtonListBox::_BandTable -- Draws bands on our table
#
proc ::ButtonListBox::_BandTable {tree} {
    variable banding
    if {! $banding} return

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
# ::ButtonListBox::_ButtonPress -- handles mouse click which can
#  toggle checkbutton, control selection or resize headings.
#
proc ::ButtonListBox::_ButtonPress {w x y} {
    lassign [$w identify $x $y] what id detail

    # Disable resizing heading #0
    if {$what eq "separator" && $id eq "\#0"} {
        return -code break
    }
    if {$what eq "item"} {
        event generate $w <<ButtonListBoxPress>> -data [$w set $id Id]
        return -code break
    }
}

################################################################
proc Demo {} {
    set data {
        {38449949 dirt path {Loop Trail}}
        {38449969 dirt path {Bear Gulch Trail}}
        {38450161 dirt path {Bear Gulch Trail}}
        {38904103 dirt path {Sierra Morena Trail}}
        {38905166 dirt path {Tafoni Trail}}
        {42054541 dirt track {Bear Gulch Trail}}
        {42054542 dirt track {Bear Gulch Trail}}
        {234792351 dirt path {Alambique Trail}}
        {234792352 dirt path {Madrone Trail}}
        {234897703 dirt path {Madrone Trail}}
        {235211301 dirt path {Bear Gulch Trail}}
        {235557435 dirt track {Bear Gulch Trail}}
        {235557436 dirt path {Loop Trail}}
        {235557440 dirt path {Redwood Trail}}
        {235557444 dirt track {}}
        {235557446 dirt track {}}
        {249015506 dirt path {Trail11 Bypass}}
        {249361145 dirt path {}}
        {249361146 dirt path {}}
        {249361147 dirt path {}}
        {327010065 dirt path {Molder Trail}}
        {512377049 dirt path {El Corte de Madera Creek Trail}}
    }



    destroy .top
    set parent [toplevel .top]
    set headers {Id Surface Highway Name}
    set hwidths {100 70 70 150}
    set w [ButtonListBox::Create $parent $headers $hwidths]
    set tree $w
    ::ButtonListBox::AddManyItems $w $data
    bind $tree <<ButtonListBoxPress>> {puts "Button Press for %d" }
}
