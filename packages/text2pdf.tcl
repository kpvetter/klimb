#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
# Time-stamp: "2008-03-10 00:11:46" \
exec wish $0 ${1+"$@"}

##+##########################################################################
#
# text2pdf -- package to convert text into pdf
# by Keith Vetter
# based on code by P. G. Womack, Diss, Norfolk, UK.
#
# Package to create PDF output from supplied text.
# Two routines are available:
#   Text2PDF::Configure ?optionName value...? -- lets you tweak some constants
#   Text2PDF::Text2PDF text                   -- returns text converted to PDF
#
# NB. PDF is a BINARY format so you must configure files to binary translation
#
# Missing features:
#  2 column output
#  better font handling
#  non-ASCII character handling
#

package provide text2pdf 0.2

namespace eval ::Text2PDF {
    namespace export Configure Text2PDF
    
    variable P
    set P(needInit) 1
}
proc ::Text2PDF::_Reset {} {
    variable P
    
    set P(pdf) ""
    set P(nPages) 0
    set P(objID) 1
    set P(ypos) 0
    array unset P xrefs,*
    array unset P page,*
}
proc ::Text2PDF::Configure {args} {
    set options {-width -height -margin -font -fontsize -leadsize -tabsize
        -a4 -a3 -letter -landscape -portrait}
    variable P
    
    # Paper size:
    #   A3 842 x 1190 px
    #   A4 595 x 842  px
    #   US letter 216 × 279 mm
    if {$args eq {} || $P(needInit)} {
        unset -nocomplain P
        ::Text2PDF::_Reset
	
        set P(needInit) 1
	
        set P(width) 612
        set P(height) 792
        set P(margin) 30
        set P(font) Courier
        set P(fontSize) 10
        set P(leadSize) 10
        set P(tabSize) 8
        set P(landscape) 0
    }
    
    foreach {arg val} [concat $args "MISSING"] {
        if {$arg eq "MISSING"} break
        if {[lsearch $options $arg] == -1} {error "unknown option \x22$arg\x22"}
        if {$val eq "MISSING"} { error "value for \x22$arg\x22 missing" }
        switch -exact -- $arg {
            "-width" { set P(width) $val }
            "-height" { set P(height) $val }
            "-margin" { set P(margin) $val }
            "-font" { set P(font) $val }
            "-fontsize" { set P(fontsize) $val }
            "-leadsize" { set P(leadsize) $val }
            "-tabsize" { set P(tabsize) $val }
            "-A4" { if {$val} { set P(width) 595; set P(height) 842 }}
            "-A3" { if {$val} { set P(width) 842; set P(height) 1190 }}
            "-letter" { if {$val} { set P(width) 842; set P(height) 1190 }}
            "-landscape" { set P(landscape) $val }
            "-portrait" { set P(landscape) [expr {! $val}] }
        }
    }

    # Handle portrait or landscape
    foreach {P(_width) P(_height)} [list $P(width) $P(height)] break
    if {$P(landscape)} {
	foreach {P(_width) P(_height)} [list $P(height) $P(width)] break
    }

    set P(needInit) 0
}
proc ::Text2PDF::Text2PDF {txt} {
    variable P
    
    if {$P(needInit)} ::Text2PDF::Configure
    
    ::Text2PDF::_MyPuts "%PDF-1.0\n"
    set P(pageTreeID) [::Text2PDF::_NextObjectID]
    ::Text2PDF::_DoText $txt
    
    set fontID [::Text2PDF::_NextObjectID]
    ::Text2PDF::_StartObject $fontID
    ::Text2PDF::_MyPuts "<< /Type /Font\n/Subtype /Type1\n"
    ::Text2PDF::_MyPuts "/BaseFont /$P(font)\n/Encoding /WinAnsiEncoding\n"
    ::Text2PDF::_MyPuts ">>\nendobj\n"
    ::Text2PDF::_StartObject $P(pageTreeID)
    ::Text2PDF::_MyPuts "<< /Type /Pages\n/Count $P(nPages)\n"
    
    ::Text2PDF::_MyPuts "/Kids \[\n"
    for {set i 0} {$i < $P(nPages)} {incr i} {
        ::Text2PDF::_MyPuts "$P(page,$i) 0 R\n"
    }
    ::Text2PDF::_MyPuts "]\n"
    
    ::Text2PDF::_MyPuts "/Resources <<\n/ProcSet \[/PDF /Text]\n"
    ::Text2PDF::_MyPuts "/Font << /F0 $fontID 0 R >>\n>>\n"
    ::Text2PDF::_MyPuts "/MediaBox \[ 0 0 $P(_width) $P(_height) ]\n"
    ::Text2PDF::_MyPuts ">>\nendobj\n"
    set catalogID [::Text2PDF::_NextObjectID]
    ::Text2PDF::_StartObject $catalogID
    ::Text2PDF::_MyPuts "<< /Type /Catalog\n/Pages $P(pageTreeID) 0 R >>\n"
    ::Text2PDF::_MyPuts "endobj\n"
    
    set startXRef [::Text2PDF::_GetPosition]
    ::Text2PDF::_MyPuts "xref\n"
    ::Text2PDF::_MyPuts "0 $P(objID)\n"
    ::Text2PDF::_MyPuts "0000000000 65535 f \n"
    for {set i 1} {$i < $P(objID)} {incr i} {
        ::Text2PDF::_MyPuts [format "%010ld 00000 n \n" $P(xrefs,$i)]
    }
    ::Text2PDF::_MyPuts "trailer\n<<\n/Size $P(objID)\n"
    ::Text2PDF::_MyPuts "/Root $catalogID 0 R\n>>\n"
    ::Text2PDF::_MyPuts "startxref\n$startXRef\n%%EOF\n"
    
    set pdf $P(pdf)
    ::Text2PDF::_Reset                          ;# Clear out memory
    return $pdf
}

proc ::Text2PDF::_MyPuts {str} {
    append ::Text2PDF::P(pdf) $str
}
proc ::Text2PDF::_GetPosition {} {
    return [string length $::Text2PDF::P(pdf)]
}

proc ::Text2PDF::_StorePage {id} {
    variable P
    
    set P(page,$P(nPages)) $id
    incr P(nPages)
}

proc ::Text2PDF::_StartObject {id} {
    set ::Text2PDF::P(xrefs,$id) [::Text2PDF::_GetPosition]
    ::Text2PDF::_MyPuts "$id 0 obj\n"
}
proc ::Text2PDF::_NextObjectID {} {
    set val $::Text2PDF::P(objID)
    incr ::Text2PDF::P(objID)
    return $val
}

proc ::Text2PDF::_StartPage {} {
    variable P
    
    set P(streamID) [::Text2PDF::_NextObjectID]
    set P(streamLenID) [::Text2PDF::_NextObjectID]
    ::Text2PDF::_MyPuts "% Starting Page\n"
    ::Text2PDF::_StartObject $P(streamID)
    ::Text2PDF::_MyPuts "<< /Length $P(streamLenID) 0 R >> % streamLenID\n"
    ::Text2PDF::_MyPuts "stream\n"
    set P(streamStart) [::Text2PDF::_GetPosition]
    ::Text2PDF::_MyPuts "BT\n/F0 $P(fontSize) Tf % fontSize\n"
    set P(ypos) [expr {$P(_height) - $P(margin)}]
    ::Text2PDF::_MyPuts "$P(margin) $P(ypos) Td % Position\n"
    ::Text2PDF::_MyPuts "$P(leadSize) TL % leadSize\n"
    ::Text2PDF::_MyPuts "% Start Page\n"
}
proc ::Text2PDF::_EndPage {} {
    variable P
    
    ::Text2PDF::_MyPuts "% Ending Page\n"
    set pageID [::Text2PDF::_NextObjectID]
    ::Text2PDF::_StorePage $pageID
    ::Text2PDF::_MyPuts "ET\n"
    set streamLen [expr {[::Text2PDF::_GetPosition] - $P(streamStart)}]
    ::Text2PDF::_MyPuts "endstream\nendobj\n"
    ::Text2PDF::_StartObject $P(streamLenID)
    ::Text2PDF::_MyPuts "$streamLen % streamLen\nendobj\n"
    ::Text2PDF::_StartObject $pageID
    ::Text2PDF::_MyPuts "<<\n/Type /Page\n/Parent $P(pageTreeID) 0 R\n"
    ::Text2PDF::_MyPuts "/Contents $P(streamID) 0 R\n>>\nendobj\n"
    ::Text2PDF::_MyPuts "% End Page\n"
}

proc ::Text2PDF::_DoText {txt} {
    variable P
    
    ::Text2PDF::_StartPage
    
    foreach line [split $txt \n] {
        set line [::Text2PDF::UntabifyLine $line $P(tabSize)]
        if {$P(ypos) < $P(margin)} {
            ::Text2PDF::_EndPage
            ::Text2PDF::_StartPage
        }
        if {$line eq ""} {
            ::Text2PDF::_MyPuts "T*\n"
        } else {
            if {[string index $line 0] eq "\f"} {
                ::Text2PDF::_EndPage
                ::Text2PDF::_StartPage
            } else {
                regsub -all {([\\()])} $line {\\\1} line
                ::Text2PDF::_MyPuts "($line)'\n"
            }
        }
        set P(ypos) [expr {$P(ypos) - $P(leadSize)}]
    }
    ::Text2PDF::_EndPage
}
proc ::Text2PDF::UntabifyLine { line num } {

    set currPos 0
    while { 1 } {
	set currPos [string first \t $line $currPos]
	if { $currPos == -1 } {
	    # no more tabs
	    break
	}

	# how far is the next tab position ?
	set dist [expr {$num - ($currPos % $num)}]
	# replace '\t' at $currPos with $dist spaces
	set spaces [string repeat " " $dist]
	set line [string replace $line $currPos $currPos $spaces]

	# set up for next round (not absolutely necessary but maybe a trifle
	# more efficient)
	incr currPos $dist
    }
    return $line
}
