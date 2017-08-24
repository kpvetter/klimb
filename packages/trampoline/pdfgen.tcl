# pdfgen.tcl
# $Revision: 1.2 $
# $Date: 2004/12/01 04:19:25 $

# Trampoline! and TclPDF (c) 2004 Mac A. Cody.  All rights reserved.
# The following terms apply to all files associated with the software
# unless explicitly disclaimed in individual files or directories.

# The authors hereby grant permission to use, copy, modify, distribute,
# and license this software for any purpose, provided that existing
# copyright notices are retained in all copies and that this notice is
# included verbatim in any distributions. No written agreement, license,
# or royalty fee is required for any of the authorized uses.
# Modifications to this software may be copyrighted by their authors and
# need not follow the licensing terms described here, provided that the
# new terms are clearly indicated on the first page of each file where
# they apply.

# IN NO EVENT SHALL THE AUTHORS OR DISTRIBUTORS BE LIABLE TO ANY PARTY
# FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES
# ARISING OUT OF THE USE OF THIS SOFTWARE, ITS DOCUMENTATION, OR ANY
# DERIVATIVES THEREOF, EVEN IF THE AUTHORS HAVE BEEN ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# THE AUTHORS AND DISTRIBUTORS SPECIFICALLY DISCLAIM ANY WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.  THIS SOFTWARE
# IS PROVIDED ON AN "AS IS" BASIS, AND THE AUTHORS AND DISTRIBUTORS HAVE
# NO OBLIGATION TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR
# MODIFICATIONS.

# GOVERNMENT USE: If you are acquiring this software on behalf of the
# U.S. government, the Government shall have only "Restricted Rights"
# in the software and related documentation as defined in the Federal 
# Acquisition Regulations (FARs) in Clause 52.227.19 (c) (2).  If you
# are acquiring the software on behalf of the Department of Defense, the
# software shall be classified as "Commercial Computer Software" and the
# Government shall have only "Restricted Rights" as defined in Clause
# 252.227-7013 (c) (1) of DFARs.  Notwithstanding the foregoing, the
# authors grant the U.S. Government and others acting in its behalf
# permission to use and distribute the software in accordance with the
# terms specified in this license. 


# The Portable Document Format standard is Copyright (c) 1987-2004 Adobe
# Systems Incorporated and its licensors.  All rights reserved. Adobe, the
# Adobe logo, Acrobat, the Acrobat logo, PostScript, and the PostScript logo
# are either registered trademarks or trademarks of Adobe Systems Incorporated
# in the United States and/or other countries.

# Protected by U.S. Patents 4,837,613; 5,050,103; 5,185,818;
# 5,200,740; 5,233,336; 5,237,313; 5,255,357; 5,546,528;
# 5,634,064; 5,737,599; 5,781,785; 5,819,301; 5,832,530;
# 5,832,531; 5,860,074; 5,929,866; 5,930,813; 5,943,063;
# 5,995,086; 6,049,339; 6,073,148; 6,289,364; Patents Pending.

namespace eval pdf {
    variable var

    set var(libDir) [file dirname [info script]]

    # Multiplication factor for splines in ovals.
    set var(kappa) [expr {(4.0 * (sqrt(2.0) - 1.0)) / 3.0}]
    # Various factors of pi
    set var(piDiv2) [expr {acos(0.0)}]
    set var(pi) [expr {2.0 * $var(piDiv2)}]
    set var(2pi) [expr {2.0 * $var(pi)}]
    set var(3piDiv2) [expr {$var(2pi) - $var(piDiv2)}]
    # Conversion multiplier from degrees to radians.
    set var(deg2rad) [expr {$var(pi) / 180.0}]

    ################# BITMAP AND IMAGE MANAGEMENT PROCEDURES ##################

    # Procedure: ParseX11Bitmap - Extract width, height, and data from an X11
    #                             bitmap structure.
    # Inputs: 
    #   xbmStruct - An X11 XBM bitmap text structure.
    # Output: 
    #   {width height {data byte list}} or {} if invalid structure.
    #
    proc ParseX11Bitmap {xbmStruct} {
	# Parse the bitmap width out of the bit map data.
	if {[regexp -- {define.+_width[ ]+([0-9]+)} \
		 $xbmStruct junk width] eq 0} {
	    # There is something wrong with the image, so skip it.
	    return {}
	}
	# Parse the bitmap height out of the bit map data.
	if {[regexp -- {define.+_height[ ]+([0-9]+)} \
		 $xbmStruct junk height] eq 0} {
	    # There is something wrong with the image, so skip it.
	    return {}
	}
	# Parse the bitmap data out of the bit map data.
	if {[regexp -- {define.+_bits\[\].+=.+\{\n*[ ]*(.+)[ ]*\n*\};} \
		 $xbmStruct junk data] eq 0} {
	    # There is something wrong with the image, so skip it.
	    return {}
	}
	# Remove commas and return characters.
	regsub -all -- {((0x[0-9a-f]{2}),?\n*)} $data {\2} bytes
	# Remove excess white space characters.
	regsub -all -- {[ ]+} $bytes { } bytes
	# Return list of width, height, and data.
	return [list $width $height $bytes]
    }

    # Procedure: BitmapToImageData - Convert bitmap data to photo image data.
    # Inputs:
    #   fg     - Foreground color.
    #   bg     - Background color.
    #   width  - Bitmap width.
    #   height - Bitmap height.
    #   bytes  - Bitmap byte data.
    #   masks  - Bitmap mask data (optional).
    # Output:
    #   List of row lists containing color data as returned
    #   by the image data command.
    #
    proc BitmapToImageData {fg bg width height bytes {masks {}}} {
	set col 0
	set row {}
	# Iterate on each byte of the bitmap byte data and
	# bit mask data (if present).
	foreach byte $bytes mask $masks {
	    # Set default value for empty bit mask variable.
	    if {$mask eq {}} {
		set mask 0xff
	    }
	    set bits 8
	    # Iterate on each bit in the byte.
	    while {$bits} {
		# Select the bit map foreground or background color
		# according to the bit state.
		if {0x1 & $byte} {
		    set color $fg
		} else {
		    set color $bg
		}
		# Select the bit mask color according to the bit state.
		if {0x1 & $mask} {
		    lappend row $color
		} else {
		    lappend row #ffffff
		}
		incr bits -1
		incr col
		# Does the column count less than the bitmap width?
		if {$col < $width} {
		    # Shift to place the next bit map bit in the lsb.
		    set byte [expr {$byte >> 1}]
		    # Shift to place the next bit mask bit in the lsb.
		    set mask [expr {$mask >> 1}]
		} else {
		    # Add the row to the image data list.
		    lappend imgData $row
		    # Empty the row data variable for the next row.
		    set row {}
		    # Zero the column counter variable for the next row.
		    set col 0
		    # Zero the bit counter variable to exit the loop.
		    set bits 0
		}
	    }
	}
	return $imgData
    }

    # Procedure: InlineImage - Generate a PDF inline image from photo image
    #                          data.
    # Inputs:
    #   anchorData - Specification of the anchor point in the PDF document.
    #   imageData  - List of row lists containing color data as returned
    #                by the image data command.
    #   width      - Width of the image contained within imageData.
    #   height     - Height of the image contained within imageData.
    # Output:
    #   PDF data stream representing the inline image.
    #
    proc InlineImage {anchorData imageData width height} {
	# Save the graphics state.
	append streamdata "q\n"
	# The coordinate space be scale.
	append streamdata $width " 0 0 " $height " "
	append streamdata $anchorData
	append streamdata " cm\n"
	# Begin the inline image object.
	append streamdata "BI\n"
	# Indicate the image width in samples.
	append streamdata "/W " $width "\n"
	# Indicate the image height in samples.
	append streamdata "/H " $height "\n"
	# Indicate and RGB colorspace.
	append streamdata "/CS /RGB\n"
	# Specify eight bits per component for the image..
	append streamdata "/BPC 8\n"
	# Indicate the beginning of the inline image data.
	append streamdata "ID "
	# Iterate on each row of the image data.
	foreach rawRow $imageData {
	    # Remove spaces and # characters
	    set rawRow [join $rawRow " "]	;# KPV 8.5 fix
	    regsub -all -- {((\#)|( ))} $rawRow {} row
	    # Convert data to binary format and add to data stream.
	    append streamdata [binary format H* $row]
	}
	# Indicate the end of the inline image data.
	append streamdata ">\nEI\n"
	# Restore the graphics state.
	append streamdata "Q\n"
	return $streamdata
    }

    # Procedure: AssembleWidgetImage - Generate a image out of a widget and
    #                                  its child widgets.  This proc is called
    #                                  recursively until an image containing
    #                                  all children is created.
    # Inputs:
    #   w - Path to the widget to be rendered as an image.
    #
    # Output:
    #   Tk image of the parent and all child widgets.
    #
    proc AssembleWidgetImage {w} {
	# This operation requires the Img extension!
	set pImg [image create photo -data $w -format window]
	# Process each child widget of the parent widget.  Note that the list
	# of child widgets returned from "winfo children" is in the stacking
	# order of bottom-most widget to top-most widget.  How convenient!
	foreach child [winfo children $w] {
	    # Recurse on viewable child widgets.
	    if {[winfo viewable $child]} {
		# Create a image of the child widget and all of its children.
		set cImg [AssembleWidgetImage $child]
		# Copy the child widget image on top of its parent.  Due to the
		# ordering of the child widgets in the iterator list of the
		# foreach loop, the widgets in the composite image will be
		# stacked properly.
		$pImg copy $cImg -to [winfo x $child] [winfo y $child]
		# Delete the image of the child widget.
		image delete $cImg
	    }
	}
	# Return to composit image.
	return $pImg
    }

    # Procedure: InlineImageMask - Generate a PDF inline image mask from
    #                              X11 bitmap data.
    # Inputs:
    #   width  - Bitmap width.
    #   height - Bitmap height.
    #   bytes  - Bitmap byte data.
    # Output:
    #   PDF data stream representing the inline image mask.
    #
    proc InlineImageMask {width height bytes} {
	variable var
	# Save the graphics state.
	append streamdata "q\n"
	# The coordinate space be scale.
	append streamdata $width " 0 0 " $height " 0.0 0.0 cm\n"
	# Begin the inline image object.
	append streamdata "BI\n"
	# Indicate the image width in samples.
	append streamdata "/W " $width "\n"
	# Indicate the image height in samples.
	append streamdata "/H " $height "\n"
	# Indicate that the image is an image mask.
	append streamdata "/IM true\n"
	# Specify only one bit per component for a mask.
	append streamdata "/BPC 1\n"
	# Indicate the beginning of the inline image data.
	append streamdata "ID "
	# Iterate on each byte of the bitmap byte data.
	foreach byte $bytes {
	    set byte [expr {0xff ^ $byte}]
	    set bits 8
	    # Iterate on each bit in the byte.
	    while {$bits} {
		# Add each individual bit to the bit string..
		append bitstr [expr {0x1 & $byte}]
		# Shift to place the next bit map bit in the lsb.
		set byte [expr {$byte >> 1}]
		incr bits -1
	    }
	}
	# Convert bit string to binary byte data and add to the data stream.
	append streamdata [binary format B* $bitstr]
	# Indicate the end of the inline image data.
	append streamdata ">\nEI\n"
	# Restore the graphics state.
	append streamdata "Q\n"
	return $streamdata
    }

    # Procedure: RegisterPattern - Place the pattern name into the
    #            patterns list and return pattern reference number.
    # Inputs:
    #   patname - The name of the pattern.
    #
    # Output:
    #   The reference number of the registered pattern.
    #
    proc RegisterPattern {patname} {
	variable var

	# Determine if the pattern name is already in the list
	if {[set ref [lsearch -exact $var(pats) $patname]] eq -1} {
	    # If not, add it to the list.
	    lappend var(pats) $patname
	    set ref [llength $var(pats)]
	} else {
	    # If it is, return the reference number.
	    incr ref
	}
	return $ref
    }

    ##################### COLOR AND PAINT MANAGEMENT PROCEDURES ###############

    # Procedure: StrokeColor - Generate the appropriate PDF RGB stroke
    #                          color statements depending upon the
    #                          presence or absense of a pattern.
    # Inputs:
    #   color   - Stroke color in RGB fractional triplet format.
    #   pattern - PDF pattern specifier.
    # Output:
    #   PDF RGB stroke color statement.
    #
    proc StrokeColor {color pattern} {
	if {$pattern eq {}} {
	    append line $color " RG % Stroke color\n"
	} else {
	    set line "/Cs1 CS\n"
	    append line $color " /P" $pattern " SCN % Stroke color\n"
	}
	return $line
    }

    # Procedure: FillColor - Generate the appropriate PDF RGB fill
    #                        color statements depending upont the
    #                        presence or absense of a pattern.
    # Inputs:
    #   color   - Fill color in RGB fractional triplet format.
    #   pattern - PDF pattern specifier.
    # Output:
    #   PDF RGB fill color statement.
    #
    proc FillColor {color pattern} {
	if {$pattern eq {}} {
	    append line $color " rg % Fill color\n"
	} else {
	    set line "/Cs1 cs\n"
	    append line $color " /P" $pattern " scn % Fill color\n"
	}
	return $line
    }

    # Procedure: GetColor - Translate an X11 color name
    #                       to an RGB fractional triplet.
    # Inputs:
    #   color - X11 color name.
    # Output:
    #   RGB fractional triplet.
    #
    proc GetColor {color} {
	if {$color ne {}} {
	    # Obtain rgb triplet for the given color name and
	    # Break it up into red, green, and blue components.
	    foreach {r g b} [winfo rgb . $color] {}
	    # Scale each color value to range from 0.0 to 1.0.
	    set r [expr {double($r) / 65535.0}]
	    set g [expr {double($g) / 65535.0}]
	    set b [expr {double($b) / 65535.0}]
	    # Combine back into an rgb triplet.
	    set color [list $r $g $b]
	}
	return $color
    }

    # Procedure: ColorNameToRGB - Translate an X11 color name to a 24-bit
    #                             RGB triplet.
    # Inputs:
    #   cname - X11 color name.
    # Output:
    #   24-bit RGB triplet.
    #
    proc ColorNameToRGB {cname} {
	# Obtain rgb triplet for the given color name and
	# break it up into red, green, and blue components.
	foreach {r g b} [winfo rgb . $cname] {}
	# Return rgb triplet with color values scaled from 0 to 255.
	return [format "#%02x%02x%02x" [expr {int($r / 256.0)}] \
		    [expr {int($g / 256.0)}] [expr {int($b / 256.0)}]]
    }

    # Procedure: ColorAndPathPaint - Generate PDF statements for stroke color,
    #                                fill color, and line width as needed.
    # Inputs:
    #   w    - Path to the canvas widget containing the item.
    #   item - Identifier of the canvas  item.
    # Output:
    #   PDF statements in a two-element list.  The first element is a sequence
    #   of strings specifying the line width, dash pattern, dash offset, stroke
    #   color, stroke pattern, fill color, and fill pattern as needed.  The
    #   second element is the path painting operator.
    #
    proc ColorAndPathPaint {w item} {
	set lineWidth {}
	# Set the stroke and fill colors according to type of canvas item.
	switch -- [set itemType [$w type $item]] {
	    line {
		# Obtain the line width of the canvas item.
		set lineWidth [$w itemcget $item -width]
		# Get the stroke color.
		set strokeColor [$w itemcget $item -fill]
		# The fill color is the same as the stroke color.
		set fillColor $strokeColor
		# Get the stroke pattern.
		set strokePat [$w itemcget $item -stipple]
		# The fill pattern is the same as the stroke pattern.
		set fillPat $strokePat
		# Assume the dash pattern is -dash.  Only the first
		# two elements of the dash pattern are used.
		set dashPat [lrange [$w itemcget $item -dash] 0 1]
	    }
	    text {
		# There is no stroke color.
		set strokeColor {}
		# Get the fill color.
		set fillColor [$w itemcget $item -fill]
		# There is no stroke pattern.
		set strokePat {}
		# Get the fill pattern.
		set fillPat [$w itemcget $item -stipple]
		# Text items have no dash option
		set dashPat {}
	    }
	    default {
		# Obtain the line width of the canvas item.
		set lineWidth [$w itemcget $item -width]
		# Get the stroke color.
		set strokeColor [$w itemcget $item -outline]
		# Get the fill color.
		set fillColor [$w itemcget $item -fill]
		# Get the stroke pattern.
		set strokePat [$w itemcget $item -outlinestipple]
		# Get the fill pattern.
		set fillPat [$w itemcget $item -stipple]
		# Assume the dash pattern is -dash.  Only the first
		# two elements of the dash pattern are used.
		set dashPat [lrange [$w itemcget $item -dash] 0 1]
	    }
	}
	# Update the stroke and fill colors
	# according to the state of the canvas item.
	switch -- [$w itemcget $item -state] {
	    active {
		switch -- $itemType {
		    line {
			expr {[set lw [$w itemcget $item -activewidth]] \
				  != 0 ? [set lineWidth $lw] : {}}
			# Get the stroke color if it in non-empty.
			expr {[set sc [$w itemcget $item -activefill]] \
				  ne {} ? [set strokeColor $sc] : {}}
			# The fill color is the same as the stroke color.
			set fillColor $sc
			# Get the stroke pattern.
			expr {[set sp [$w itemcget $item -activestipple]] \
				  ne {} ? [set strokePat $sp] : {}}
			# The fill pattern is the same as the stroke pattern.
			set fillPat $sp
			# Assume the dash pattern is -activedash.  Only the
			# first two elements of the dash pattern are used.
			expr {[set dp [lrange \
					   [$w itemcget $item -activedash] \
					   0 1]] ne {} ? [set dashPat $dp] \
				  : {}}
		    }
		    text {
			# There is no stroke color.
			set strokeColor {}
			# Get the fill color if it in non-empty.
			expr {[set fc [$w itemcget $item -activefill]] \
				  ne {} ? [set fillColor $fc] : {}}
			# There is no stroke pattern.
			set strokePat {}
			# Get the fill pattern.
			expr {[set fp [$w itemcget $item -activestipple]] \
				  ne {} ? [set fillPat $fp] : {}}
		    }
		    default {
			expr {[set lw [$w itemcget $item -activewidth]] \
				  != 0 ? [set lineWidth $lw] : {}}
			# Get the stroke color if it in non-empty.
			expr {[set sc [$w itemcget $item -activeoutline]] \
				  ne {} ? [set strokeColor $sc] : {}}
			# Get the fill color if it in non-empty.
			expr {[set fc [$w itemcget $item -activefill]] \
				  ne {} ? [set fillColor $fc] : {}}
			# Get the stroke pattern.
			expr {[set sp \
				   [$w itemcget $item -activeoutlinestipple]] \
				  ne {} ? [set strokePat $sp] : {}}
			# Get the fill pattern.
			expr {[set fp [$w itemcget $item -activestipple]] \
				  ne {} ? [set fillPat $fp] : {}}
			# Assume the dash pattern is -activedash.  Only the
			# first two elements of the dash pattern are used.
			expr {[set dp [lrange \
					   [$w itemcget $item -activedash] \
					   0 1]] ne {} ? [set dashPat $dp] \
				  : {}}
		    }
		}
	    }
	    disabled {
		switch -- $itemType {
		    line {
			expr {[set lw [$w itemcget $item -disabledwidth]] \
				  != 0 ? [set lineWidth $lw] : {}}
			# Get the stroke color if it in non-empty.
			expr {[set sc [$w itemcget $item -disabledfill]] \
				  ne {} ? [set strokeColor $sc] : {}}
			# The fill color is the same as the stroke color.
			set fillColor $sc
			# Get the stroke pattern.
			expr {[set sp [$w itemcget $item -disabledstipple]] \
				  ne {} ? [set strokePat $sp] : {}}
			# The fill pattern is the same as the stroke pattern.
			set fillPat $sp
			# Assume the dash pattern is -disableddash.  Only the
			# first two elements of the dash pattern are used.
			expr {[set dp [lrange \
					   [$w itemcget $item -disableddash] \
					   0 1]] ne {} ? [set dashPat $dp] \
				  : {}}
		    }
		    text {
			# There is no stroke color.
			set strokeColor {}
			# Get the fill color if it in non-empty.
			expr {[set fc [$w itemcget $item -disabledfill]] \
				  ne {} ? [set fillColor $fc] : {}}
			# There is no stroke pattern.
			set strokePat {}
			# Get the fill pattern.
			expr {[set fp [$w itemcget $item -disabledstipple]] \
				  ne {} ? [set fillPat $fp] : {}}
		    }
		    default {
			expr {[set lw [$w itemcget $item -disabledwidth]] \
				  != 0 ? [set lineWidth $lw] : {}}
			# Get the stroke color if it in non-empty.
			expr {[set sc [$w itemcget $item -disabledoutline]] \
				  ne {} ? [set strokeColor $sc] : {}}
			# Get the fill color if it in non-empty.
			expr {[set fc [$w itemcget $item -disabledfill]] \
				  ne {} ? [set fillColor $fc] : {}}
			# Get the stroke pattern.
			expr {[set sp \
				   [$w itemcget $item \
					-disabledoutlinestipple]] \
				  ne {} ? [set strokePat $sp] : {}}
			# Get the fill pattern.
			expr {[set fp [$w itemcget $item -disabledstipple]] \
				  ne {} ? [set fillPat $fp] : {}}
			# Assume the dash pattern is -disableddash.  Only the
			# first two elements of the dash pattern are used.
			expr {[set dp \
				   [lrange [$w itemcget $item \
						-disableddash] 0 1]] \
				  ne {} ? [set dashPat $dp] : {}}
		    }
		}
	    }
	    hidden {
		# This item is hidden, so abort processing.
		return -code return {}
	    }
	}
	# If necessary, register the stipple pattern and
	# retrieve the PDF pattern reference.
	if {$strokePat ne {}} {
	    set strokePatRef [RegisterPattern $strokePat]
	} else {
	    set strokePatRef {}
	}
	if {$fillPat ne {}} {
	    set fillPatRef [RegisterPattern $fillPat]
	} else {
	    set fillPatRef {}
	}
	# Add the line width to the data stream.
	if {$lineWidth ne {}} {
	    append streamdata $lineWidth " w % Line width\n"
	}
	# Add the appropriate dash pattern to the data stream.
	if {$dashPat ne {}} {
	    # Need to handle the different ways that dash patterns are
	    # described.  Only the numeric format with one or two values
	    # are accepted.
	    if {[regexp {^[1-9][0-9]*( +[1-9][0-9]*)?$} $dashPat]} {
		append streamdata "\[" $dashPat "\] "
		append streamdata [$w itemcget $item -dashoffset] " d\n"
	    } else {
		append streamdata \
		    "\[\] 0 d % Reset dash pattern to a solid line\n"
	    }
	} else {
	    append streamdata "\[\] 0 d % Reset dash pattern to a solid line\n"
	}
	# Add the appropriate stroke and fill color messages to the data stream
	# and the appropriate rendering command..
	if {($strokeColor eq {}) && ($fillColor eq {})} {
	    # This item is not visible, so abort processing.
	    return -code return {}
	} elseif {($strokeColor ne {}) && ($fillColor eq {})} {
	    # Place the stroke color string into the stream.
	    # (IS THE PATTERN REFERENCE CORRECT?)
	    append streamdata \
		[StrokeColor [GetColor $strokeColor] $strokePatRef]
	    # Place the stroke path operator into the stream.
	    set pathPaint S
	} elseif {($strokeColor eq {}) && ($fillColor ne {})} {
	    # Place the fill color string into the stream.
	    append streamdata [FillColor [GetColor $fillColor] $fillPatRef]
	    # Place the fill path operator into the stream.
	    set pathPaint f
	} else {
	    # Place the stroke color string into the stream.
	    append streamdata \
		[StrokeColor [GetColor $strokeColor] $strokePatRef]
	    # Place the fill color string into the stream.
	    append streamdata [FillColor [GetColor $fillColor] $fillPatRef]
	    # Place the fill and then stroke path operator into the stream.
	    set pathPaint B
	}
	
	return [list $streamdata $pathPaint]
    }


    ###################### COORDINATE MANAGEMENT PROCEDURES ###################

    # Procedure: FormatCoords - Restate the item coordinates within the page
    #                           framework.  This routine is used with canvas
    #                           items with coordinate lists of arbitrary
    #                           length.
    # Inputs:
    #   coords - Ordered pair of x-y coordinates.
    # Output:
    #   List of x-y coordinate pairs within the page framework.
    #
    proc FormatCoords {coords} {
	variable var
	foreach {xline yline} $coords {
	    lappend newCoords $xline [expr {$var(height) - $yline}]
	}
	return $newCoords
    }

    # Procedure: FormatCorners - Restate the coordinates for the bounding
    #                            rectangle of a canvas item within the page
    #                            framework. 
    # Inputs:
    #   coords - Ordered pair of x-y coordinates.
    # Output:
    #   List of four corner coordinates.
    #
    proc FormatCorners {coords} {
	foreach {x1 y1 x2 y2} [FormatCoords $coords] {}
	if {$x1 <= $x2} {
	    set xa $x1
	    set xb $x2
	} else {
	    set xa $x2
	    set xb $x1
	}
	if {$y1 <= $y2} {
	    set ya $y1
	    set yb $y2
	} else {
	    set ya $y2
	    set yb $y1
	}
	return [list $xa $ya $xb $yb]
    }

    # Procedure: FormatAnchor - Adjust the coordinate for a canvas item within
    #                           the page framework according to its anchoring.
    #                           This procedure only applies to canvas items
    #                           with a single x-y coordinate pair.
    # Inputs:
    #   w      - Path to the canvas widget containing the item.
    #   item   - Identifier of the canvas item.
    #   width  - Width of the canvas item.
    #   height - Height of the canvas item.
    # Output:
    #   The adjusted x-y coordinate pair.
    # 
    proc FormatAnchor {w item width height} {
	# Restate coordinates in page domain.
	foreach {x y} [FormatCoords [$w coords $item]] {}
	# Position page anchor point according to item anchor point.
	# Note that nothing is done for anchor of "sw".
	switch -- [$w itemcget $item -anchor] {
	    n {
		set x [expr {$x - ($width / 2)}]
		set y [expr {$y - $height}]
	    }
	    ne {
		set x [expr {$x - $width}]
		set y [expr {$y - $height}]
	    }
	    e {
		set x [expr {$x - $width}]
		set y [expr {$y - ($height / 2)}]
	    }
	    se {
		set x [expr {$x - $width}]
	    }
	    s {
		set x [expr {$x - ($width / 2)}]
	    }
	    w {
		set y [expr {$y - ($height / 2)}]
	    }
	    nw {
		set y [expr {$y - $height}]
	    }
	    center {
		set x [expr {$x - ($width / 2)}]
		set y [expr {$y - ($height / 2)}]
	    }
	}
	return [list $x $y]
    }

    ###################### FONT MANAGEMENT PROCEDURES #########################

    # Procedure: RegisterFont - Process font information from the given font
    #                           name, place into the fonts list, and return
    #                           font data.
    # Inputs:
    #   w    - Path to the canvas widget containing the item.
    #   item - Identifier of the canvas item.
    #
    # Output:
    #   A four-element list containing the font information.  The first list
    #   element is the font reference number.  The second list element is the
    #   font size.  The third list element is the font line space.  The fourth
    #   list element is the font ascent.
    proc RegisterFont {fontname} {
	variable var

	# Obtain the font information.
	array set fdata [font actual $fontname]
	array set fdata [font metrics $fontname]
	set basefont [string toupper $fdata(-family) 0]
	if {$basefont eq "Arial"} {set basefont "Helvetica"} ;# KPV
	if {$basefont eq "Times New Roman"} {set basefont "TimesNewRoman"};# KPV
	switch -- $fdata(-weight) {
	    bold {
		set modifier Bold
	    }
	    default {
		set modifier {}
	    }
	}
	switch -- $fdata(-slant) {
	    i -
	    italic {
		append modifier Italic
	    }
	    o -
	    oblique {
		append modifier Oblique
	    }
	    default {
	    }
	}
	if {$modifier ne {}} {
	    append basefont - $modifier
	}
	if {$basefont eq "TimesNewRoman-Bold"} {;# KPV
	    set basefont "TimesNewRoman,Bold"}
	# Determine if basefont is already in the list
	if {[set ref [lsearch -exact $var(fonts) $basefont]] eq -1} {
	    # If not, add it to the list.
	    lappend var(fonts) $basefont
	    set ref [llength $var(fonts)]
	} else {
	    # If it is, return the reference number.
	    incr ref
	}
	return [list $ref $fdata(-size) $fdata(-linespace) $fdata(-ascent)]
    }

    ################### CANVAS ITEM CONVERSION PROCEDURES #####################

    # Procedure: ArcConvert - Convert the arc item's characteristics
    #                         into an appropriate PDF bezier curve.
    # Inputs:
    #   w    - Path to the canvas widget containing the arc item.
    #   item - Identifier of the canvas arc item.
    #
    # Output:
    #   Text stream of PDF elements representing the canvas arc item..
    #
    proc ArcConvert {w item} {
	variable var
	append streamdata "% Draw a arc for item " $item "\n"
	# Determine the coloring and path painting.
	set rendering [ColorAndPathPaint $w $item]
	append streamdata [lindex $rendering 0]
	# Find the lower-left and upper-right corners.
	foreach {xa ya xb yb} [FormatCorners [$w coords $item]] {}
	# Normalize start to range of -360 degrees to +360 degrees.
	set start [$w itemcget $item -start]
	if {$start >= 0} {
	    while {$start >= 360} {
		set start [expr {$start - 360}]
	    }
	} else {
	    while {$start <= -360} {
		set start [expr {$start + 360}]
	    }
	}
	# Normalize extent to range of -360 degrees to +360 degrees.
	set extent [$w itemcget $item -extent]
	if {$extent >= 0} {
	    while {$extent >= 360} {
		set extent [expr {$extent - 360}]
	    }
	    # Break up the arc as necessary.
	    if {$extent > 180} {
		set end [expr {$start + 180}]
		set end2 [expr {$start + $extent}]
	    } else {
		set end [expr {$start + $extent}]
		set end2 {}
	    }
	} else {
	    while {$extent <= -360} {
		set extent [expr {$extent + 360}]
	    }
	    # Break up the arc as necessary.
	    if {$extent < -180} {
		set end [expr {$start - 180}]
		set end2 [expr {$start + $extent}]
	    } else {
		set end [expr {$start + $extent}]
		set end2 {}
	    }
	}

	# Find the center of the fitting ellipse.
	set x [expr {($xa + $xb) / 2}]
	set y [expr {($ya + $yb) / 2}]
	# Find the x/y extens of the fitting ellipse.
	set a [expr {($xb - $xa) / 2}]
	set b [expr {($yb - $ya) / 2}]
	# Find the radian values of the start and end angles.
	set alpha [expr {$start * $var(deg2rad)}]
	set beta [expr {$end * $var(deg2rad)}]
	# Establish the Bezier control point for the arc.
	set bcp [expr {4.0/3.0 * \
			   (1 - cos(($beta - $alpha)/2)) \
			   / sin(($beta - $alpha)/2)}]
	# Calculate sines and cosines of the start and end angles.
	set sin_alpha [expr {sin($alpha)}]
	set cos_alpha [expr {cos($alpha)}]
	set sin_beta [expr {sin($beta)}]
	set cos_beta [expr {cos($beta)}]
	# Find the start point of the Bezier.
	set p0_x [expr {$x + $a * $cos_alpha}]
	set p0_y [expr {$y + $b * $sin_alpha}]
	# Start the new sub-path and current point.
	append streamdata $p0_x " " $p0_y " m\n"
	# Find the control points and end point of the Bezier.
	set p1_x [expr {$x + $a * ($cos_alpha - $bcp * $sin_alpha)}]
	set p1_y [expr {$y + $b * ($sin_alpha + $bcp * $cos_alpha)}]
	set p2_x [expr {$x + $a * ($cos_beta + $bcp * $sin_beta)}]
	set p2_y [expr {$y + $b * ($sin_beta - $bcp * $cos_beta)}]
	set p3_x [expr {$x + $a * $cos_beta}]
	set p3_y [expr {$y + $b * $sin_beta}]
	# Append the cubic Bezier curve and
	# make p3_x/p3_y the new current point.
	append streamdata $p1_x " " $p1_y " " \
	    $p2_x " " $p2_y " " $p3_x " " $p3_y " c\n"
	# Add another cubic Bezier curve if the entire arc > 180 degrees.
	if {$end2 ne {}} {
	    # The original end angle is now the start angle.
	    set alpha $beta
	    # Find the radian value of the new end angle.
	    set beta [expr {$end2 * $var(deg2rad)}]
	    # The original end sine and cosine
	    # are are now the start sine and cosine.
	    set sin_alpha $sin_beta
	    set cos_alpha $cos_beta
	    # Calculate sine and cosine of the new end angle.
	    set sin_beta [expr {sin($beta)}]
	    set cos_beta [expr {cos($beta)}]
	    # Establish the new Bezier control point for the second arc.
	    set bcp [expr {4.0/3.0 * \
			       (1 - cos(($beta - $alpha)/2)) \
			       / sin(($beta - $alpha)/2)}]
	    # Find the control points and end point of the second Bezier.
	    set p4_x [expr {$x + $a * ($cos_alpha - $bcp * $sin_alpha)}]
	    set p4_y [expr {$y + $b * ($sin_alpha + $bcp * $cos_alpha)}]
	    set p5_x [expr {$x + $a * ($cos_beta + $bcp * $sin_beta)}]
	    set p5_y [expr {$y + $b * ($sin_beta - $bcp * $cos_beta)}]
	    set p6_x [expr {$x + $a * $cos_beta}]
	    set p6_y [expr {$y + $b * $sin_beta}]
	    # Append the second cubic Bezier curve and
	    # make p6_x/p6_y the new current point.
	    append streamdata $p4_x " " $p4_y " " \
		$p5_x " " $p5_y " " $p6_x " " $p6_y " c\n"
	}

	# Determine completion of shape for the appropriate arc style.
	switch -- [$w itemcget $item -style] {
	    "" -
	    pieslice {
		# Add lines for wedge of pieslice
		append streamdata $x " " $y " l % Line to center of slice\n"
		append streamdata "h % Close the pieslice\n"
		append streamdata [lindex $rendering 1] "\n"
	    }
	    arc {
		# An arc will only be stroked.
		append streamdata "S\n"
	    }
	    chord {
		# Draw a straight line connecting the ends of the arc.
		append streamdata "h % Close the chord\n"
		append streamdata [lindex $rendering 1] "\n"
	    }
	}
	return $streamdata
    }

    # Procedure: BitmapConvert - Convert the bitmap item's characteristics
    #                            into a PDF inline graphic element.
    # Inputs:
    #   w    - Path to the canvas widget containing the bitmap item.
    #   item - Identifier of the canvas bitmap item.
    #
    # Output:
    #   Text stream of PDF elements representing the canvas bitmap item.
    #
    proc BitmapConvert {w item} {
	variable var

	switch -- [$w itemcget $item -state] {
	    "" -
	    normal {
		set bitmapOpt -bitmap
		set fgOpt -foreground
		set bgOpt -background
	    }
	    active {
		set bitmapOpt -activebitmap
		set fgOpt -activeforeground
		set bgOpt -activebackground
	    }
	    disabled {
		set bitmapOpt -disabledbitmap
		set fgOpt -disabledforeground
		set bgOpt -disabledbackground
	    }
	    hidden {
		# This bitmap is not visible.
		return {}
	    }
	}
	if {[set xbmName [$w itemcget $item $bitmapOpt]] eq {}} {
	    # There is no bitmap to display.
	    return {}
	}
	if {[string index $xbmName 0] eq "@"} {
	    # Referencing an X11 XBM file; load it in.
	    set fp [open [string range $xbmName 1 end]]
	    set xbmData [read $fp]
	    close $fp
	} else {
	    # Referencing an internal Tk bitmap; load a representation.
	    set fp [open [file join $var(libDir) bitmaps ${xbmName}.bmp]]
	    set xbmData [read $fp]
	    close $fp
	}
	foreach {imgWidth imgHeight bytes} [ParseX11Bitmap $xbmData] {}
	if {[set fg [$w itemcget $item $fgOpt]] ne {}} {
	    set fg [ColorNameToRGB $fg]
	} else {
	    set fg #000000
	}
	if {[set bg [$w itemcget $item $bgOpt]] ne {}} {
	    set bg [ColorNameToRGB $bg]
	} else {
	    set bg #ffffff
	}
	# Convert the bitmap into image data as a list of lists.
	set imageData [BitmapToImageData $fg $bg $imgWidth $imgHeight $bytes]
	# Determine the width and height of the image.
	set width [llength [lindex $imageData 0]]
	set height [llength $imageData]
	# Determine the anchoring point of the canvas item.
	set anchorData [FormatAnchor $w $item $width $height]
	# Insert a PDF inline image into the document data stream.
	append streamdata "% Draw a bitmap for item " $item "\n"
	append streamdata [InlineImage $anchorData $imageData $width $height]
	return $streamdata
    }

    # Procedure: ImageConvert - Convert the image item's characteristics
    #                           into a PDF inline graphic element.
    # Inputs:
    #   w    - Path to the canvas widget containing the image item.
    #   item - Identifier of the canvas image item.
    #
    # Output:
    #   Text stream of PDF elements representing the canvas image item.
    #
    proc ImageConvert {w item} {
	switch -- [$w itemcget $item -state] {
	    "" -
	    normal {
		if {[set img [$w itemcget $item -image]] eq {}} {
		    # There is no bitmap to display.
		    return {}
		}
	    }
	    active {
		if {[set img [$w itemcget $item -activeimage]] eq {}} {
		    if {[set img [$w itemcget $item -image]] eq {}} {
			# There is no bitmap to display.
			return {}
		    }
		}
	    }
	    disabled {
		if {[set img [$w itemcget $item -disabledimage]] eq {}} {
		    if {[set img [$w itemcget $item -image]] eq {}} {
			# There is no bitmap to display.
			return {}
		    }
		}
	    }
	    hidden {
		# This bitmap is not visible.
		return {}
	    }
	}

	if {[image type $img] eq "bitmap"} {
	    # Determine where the data is.  Content of -data takes precidence.
	    if {[set xbmData [$img cget -data]] eq {}} {
		if {[set xbmFile [$img cget -file]] eq {}} {
		    # There is no image to render, so skip it.
		    return {}
		}
		set fp [open $xbmFile]
		set xbmData [read $fp]
		close $fp
	    }
	    foreach {imgWidth imgHeight bytes} [ParseX11Bitmap $xbmData] {}
	    if {[set xbmMaskData [$img cget -maskdata]] eq {}} {
		if {[set xbmFile [$img cget -maskfile]] ne {}} {
		    set fp [open $xbmFile]
		    set xbmMaskData [read $fp]
		    close $fp
		}
	    }
	    if {$xbmMaskData ne {}} {
		set maskbytes [lindex [ParseX11Bitmap $xbmMaskData] 2]
	    } else {
		set maskbytes {}
	    }
	    set fg [ColorNameToRGB \
			[[$w itemcget $item -image] cget -foreground]]
	    set bg [ColorNameToRGB \
			[[$w itemcget $item -image] cget -background]]
	    # Convert the bitmap into image data as a list of lists.
	    set imageData [BitmapToImageData \
			       $fg $bg $imgWidth $imgHeight $bytes $maskbytes]
	} else {
	    # Extract the image data as a list of lists.
	    set imageData [$img data -background white] ;# KPV added background
	}
	# Determine the width and height of the image.
	set width [llength [lindex $imageData 0]]
	set height [llength $imageData]
	# Determine the anchoring point of the canvas item.
        set anchorData [FormatAnchor $w $item $width $height]
	# Insert a PDF inline image into the document data stream.
	append streamdata "% Draw an image for item " $item "\n"
	append streamdata [InlineImage $anchorData $imageData $width $height]
	return $streamdata
    }

    # Procedure: DrawArrowhead - Draw the arrowhead for the end of a line.
    # Inputs:
    #   point      - Coordinate pair of the point of arrowhead.
    #   butt       - Coordinate pair of the line segment with the arrowhead.
    #   arrowShape - Shape of the arrowhead on the line.
    #   lineWidth  - Width of the line.
    #
    # Output:
    #   Text stream of PDF elements representing the arrow and the coordinates
    #   of the neck of the arrowhead.
    #
    proc DrawArrowhead {point butt arrowShape lineWidth} {
	variable var
	# Separate the arrow shape parameters.
	foreach {neckLine trailLine trailWidth} $arrowShape {}
	# Add half the line width to the trailing points width.
	set trailWidth [expr {$trailWidth + ($lineWidth / 2.0)}]
	# Create arrowhead at beginning of line if necessary.
	set pointX [lindex $point 0]
	set pointY [lindex $point 1]
	set buttX [lindex $butt 0]
	set buttY [lindex $butt 1]
	if {$buttX - $pointX != 0.0} {
	    set angle [expr {atan(($buttY - $pointY) / ($buttX - $pointX))}]
	    if {$buttX - $pointX >= 0.0} {
		if {$buttY - $pointY < 0.0} {
		    set angle [expr {$angle + $var(2pi)}]
		}
	    } else {
		set angle [expr {$angle + $var(pi)}]
	    }
	} elseif {$buttY - $pointY >= 0.0} {
	    set angle $var(piDiv2)
	} else {
	    set angle $var(3piDiv2)
	}
	#puts -nonewline "$pointX "
	#puts -nonewline "$pointY "
	#puts -nonewline "$buttX "
	#puts -nonewline "$buttY "
	#puts $angle
	# Find the coordinates of the neck of the arrowhead.
	set neckX [expr {$pointX + cos($angle) * $neckLine}]
	set neckY [expr {$pointY + sin($angle) * $neckLine}]
	# Find the coordinates of the trails cast to the line.
	set trailLineX [expr {$pointX + cos($angle) * $trailLine}]
	set trailLineY [expr {$pointY + sin($angle) * $trailLine}]
	# Find the x-offset of the trail from the cast point on the line.
	set trailWidthX \
	    [expr {cos($angle + $var(piDiv2)) * $trailWidth}]
	# Find the y-offset of the trail from the cast point on the line.
	set trailWidthY \
	    [expr {sin($angle + $var(piDiv2)) * $trailWidth}]
	# Find the coordinates of the trails.
	set trail1X [expr {$trailLineX + $trailWidthX}]
	set trail1Y [expr {$trailLineY + $trailWidthY}]
	set trail2X [expr {$trailLineX - $trailWidthX}]
	set trail2Y [expr {$trailLineY - $trailWidthY}]
	# Start drawing the arrowhead at the point
	append streamdata $pointX " " $pointY " m\n"
	append streamdata $trail1X " " $trail1Y " l\n"
	append streamdata $neckX " " $neckY " l\n"
	append streamdata $trail2X " " $trail2Y " l\n"
	append streamdata $pointX " " $pointY " l\nf\n"
	return [list $streamdata $neckX $neckY]
    }

    # Procedure: LineConvert - Convert the line item's characteristics
    #                          into a PDF line or bezier curve element.
    # Inputs:
    #   w    - Path to the canvas widget containing the line item.
    #   item - Identifier of the canvas line item.
    #
    # Output:
    #   Text stream of PDF elements representing the canvas line item.
    #
    proc LineConvert {w item} {
	append streamdata "% Draw a line for item " $item "\n"
	# Determine the line rendering.
	set rendering [ColorAndPathPaint $w $item]
	append streamdata [lindex $rendering 0]

        # Establish base coordinates of the line.
	set coords [FormatCoords [$w coords $item]]
	# Determine placement of arrowheads, if any.
	set arrowPlace [$w itemcget $item -arrow]
	if {$arrowPlace ne {none}} {
	    # Extract the width data from the rendering string.
	    if {![regexp {([0-9.]+) w % Line width} \
		      [lindex $rendering 0] junk lineWidth]} {
		set lineWidth 1
	    }
	    # Determine shape of arrowheads for the line.
	    set arrowshape [$w itemcget $item -arrowshape]
	    # Create arrowhead at beginning of line if necessary.
	    if {($arrowPlace eq {first}) || ($arrowPlace eq {both})} {
		# Draw arrowhead for the beginning of the line.
		foreach {arrowdata neckX neckY} \
		    [DrawArrowhead [lrange $coords 0 1] \
			 [lrange $coords 2 3] $arrowshape $lineWidth] {}
		# Update the beginning coordinates for the arrowhead.
		set coords [lreplace $coords 0 1 $neckX $neckY]
	    }

	    # Create arrowhead at end of line if necessary.
	    if {($arrowPlace eq {last}) || ($arrowPlace eq {both})} {
		# Draw arrowhead for the end of the line.
		foreach {data neckX neckY} \
		    [DrawArrowhead [lrange $coords end-1 end] \
			 [lrange $coords end-3 end-2] \
			 $arrowshape $lineWidth] {}
		append arrowdata $data
		# Update the ending coordinates for the arrowhead.
		set coords [lreplace $coords end-1 end $neckX $neckY]
	    }
	    # Force the cap style to butt.
	    append streamdata 0
	} else {
	    # There is no arrow data to display.
	    set arrowdata {}
	    # Generate the mapping for the cap style.
	    append streamdata [string map {butt 0 round 1 projecting 2} \
				   [$w itemcget $item -capstyle]]
	}

	# Add the cap style data.
	append streamdata " J % Line cap style\n"
	# Add the join style data.
	append streamdata [string map {miter 0 round 1 bevel 2} \
			       [$w itemcget $item -joinstyle]]
	append streamdata " j % Line join style\n"
	# Generate the basic line or spline curve to the data stream.
	append streamdata [lrange $coords 0 1] " m\n"
	if {[$w itemcget $item -smooth] eq 0} {
	    foreach {xline yline} [lrange $coords 2 end] {
		append streamdata $xline " " $yline " l\n"
	    }
	} else {
	    append streamdata [lrange $coords 2 end] " c\n"
	}
	# Even though both stroke and fill are specified, the line is stroked.
	append streamdata "S\n"
	# Add the arrow drawing data to the data stream.
	append streamdata $arrowdata
	return $streamdata
    }

    # Procedure: OvalConvert - Convert the oval item's characteristics
    #                          into a PDF bezier curve element.
    # Inputs:
    #   w    - Path to the canvas widget containing the oval item.
    #   item - Identifier of the canvas oval item.
    #
    # Output:
    #   Text stream of PDF elements representing the canvas oval item.
    #
    proc OvalConvert {w item} {
	variable var

	append streamdata "% Draw a oval for item " $item "\n"
	set rendering [ColorAndPathPaint $w $item]
	append streamdata [lindex $rendering 0]
	foreach {xa ya xb yb} [FormatCorners [$w coords $item]] {}
	# Find center point of the oval.
	set xc [expr {($xa + $xb) / 2.0}]
	set yc [expr {($ya + $yb) / 2.0}]
	# Find the major and minor axes.
	set a [expr {($xb - $xa) / 2.0}]
	set b [expr {($yb - $ya) / 2.0}]
	# Make control points offsets
	set ak [expr {$a * $var(kappa)}]
	set bk [expr {$b * $var(kappa)}]
	# Set new current point 
	append streamdata $xa " " $yc " m\n"
	append streamdata $xa " " [expr {$yc + $bk}] " " \
	    [expr {$xc - $ak}] " " $yb " " $xc " " $yb " c\n"
	append streamdata [expr {$xc + $ak}] " " $yb " " \
	    $xb " " [expr {$yc + $bk}] " " $xb " " $yc " c\n"
	append streamdata $xb " " [expr {$yc - $bk}] " " \
	    [expr {$xc + $ak}] " " $ya " " $xc " " $ya " c\n"
	append streamdata [expr {$xc - $ak}] " " $ya " " \
	    $xa " " [expr {$yc - $bk}] " " $xa " " $yc " c\n"
	append streamdata [lindex $rendering 1] "\n"
	return $streamdata
    }

    # Procedure: PolygonConvert - Convert the polygon item's characteristics
    #                             into a PDF line or bezier curve element.
    # Inputs:
    #   w    - Path to the canvas widget containing the polygon item.
    #   item - Identifier of the canvas polygon item.
    #
    # Output:
    #   Text stream of PDF elements representing the canvas polygon item.
    #
    proc PolygonConvert {w item} {
	append streamdata "% Draw a polygon for item " $item "\n"
	set rendering [ColorAndPathPaint $w $item]
	append streamdata [lindex $rendering 0]
	append streamdata \
	    [string map {miter 0 round 1 bevel 2} \
		 [$w itemcget $item -joinstyle]] " j % Line join style\n"
	set coords [FormatCoords [$w coords $item]]
	append streamdata [lrange $coords 0 1] " m\n"
	if {[$w itemcget $item -smooth] eq 0} {
	    foreach {xline yline} \
		[concat [lrange $coords 2 end] [lrange $coords 0 1]] {
		append streamdata $xline " " $yline " l\n"
	    }
	} else {
	    append streamdata [lrange $coords 2 end] " c\n"
	}
	
	append streamdata [lindex $rendering 1] "\n"
 	return $streamdata
    }

    # Procedure: RectangleConvert - Convert the rectangle item's
    #                               characteristics into a PDF rectangle
    #                               element.
    # Inputs:
    #   w    - Path to the canvas widget containing the rectangle item.
    #   item - Identifier of the canvas rectangle item.
    #
    # Output:
    #   Text stream of PDF elements representing the canvas rectangle item.
    #
    proc RectangleConvert {w item} {
	variable var
	# [$w itemcget $item -state] eq {hidden}
	if {0} {
	    return {}
	}
	append streamdata "% Draw a rectangle for item " $item "\n"
	set rendering [ColorAndPathPaint $w $item]
	append streamdata [lindex $rendering 0]
	# Find lower lefthand corner.
	foreach {xa ya xb yb} [FormatCoords [$w coords $item]] {}
	append streamdata $xa " " $ya " "
	append streamdata [expr {$xb - $xa}] " " [expr {$yb - $ya}] " re\n"
	append streamdata [lindex $rendering 1] "\n"
 	return $streamdata
    }

    # Procedure: TextConvert - Convert the test item's characteristics
    #                          into a PDF text element.
    # Inputs:
    #   w    - Path to the canvas widget containing the text item.
    #   item - Identifier of the canvas text item.
    #
    # Output:
    #   Text stream of PDF elements representing the canvas text item.
    #
    proc TextConvert {w item} {
	variable var

	append streamdata "% Draw a text for item " $item "\n"
	append streamdata "BT\n"
	# Determine stroke and fill of the text.
	set rendering [ColorAndPathPaint $w $item]
	append streamdata [lindex $rendering 0]
	set fontname [$w itemcget $item -font]
	# Register the font name and obtain its properties.
	foreach {fontref size linespace ascent} [RegisterFont $fontname] {}
        set textbody [split [$w itemcget $item -text] "\n"]
	set justification [$w itemcget $item -justify]
	set textHeight 0
	set textWidth 0
	# Break up the text into individual lines
	# and determine which line is widest.
	foreach line $textbody {
	    incr textHeight $linespace
	    if {[set newWidth [font measure $fontname $line]] > $textWidth} {
		set textWidth $newWidth
	    }
	    #puts "Line width: $newWidth"
	    lappend widthList $newWidth
	}
        foreach {x y} [FormatAnchor $w $item $textWidth $textHeight] {}
	set lineCount 0
	# Determine the horizontal position of each line of text.
	foreach newWidth $widthList {
	    switch $justification {
		right {
		    lappend offsetList [expr {$x + $textWidth - $newWidth}]
		}
		center {
		    lappend offsetList \
			[expr {$x + ($textWidth - $newWidth) / 2}]
		}
		left {
		    lappend offsetList $x
		}
	    }
	    lappend offsetList \
		[expr {$y + $textHeight - ($lineCount * $linespace) - $ascent}]
	    incr lineCount
	}

	# Add the font reference to the stream.
	append streamdata "/F" $fontref " " $size " Tf\n"
	# Render each line at its proper position on the page.
	set textX 0.0
	set textY 0.0
	foreach line $textbody {newX newY} $offsetList {
	    set diffX [expr {$newX - $textX}]
	    set diffY [expr {$newY - $textY}]
	    set textX $newX
	    set textY $newY
	    append streamdata $diffX " " $diffY " Td\n"
	    append streamdata "(" $line ") Tj\n"
	}
	append streamdata "ET\n"
 	return $streamdata
    }

    # Procedure: WindowConvert - Convert the window item's characteristics
    #                            into a PDF inline graphic element.
    # Inputs:
    #   w    - Path to the canvas widget containing the window item.
    #   item - Identifier of the canvas window item.
    #
    # Output:
    #   Text stream of PDF elements representing the canvas window item.
    #
    proc WindowConvert {w item} {
	if {[$w itemcget $item -state] eq {hidden}} {
	    return {}
	} elseif {[set wid [$w itemcget $item -window]] eq {}} {
	    return {}
	}
	append streamdata "% Draw a window for item " $item "\n"
	# Build up the window image from the widget and its child widgets.
        set img [AssembleWidgetImage $wid]
	# Extract the built-up image data as a list of lists.
	set imageData [$img data]
	# Determine the width and height of the image.
	set width [llength [lindex $imageData 0]]
	set height [llength $imageData]
	# Determine the anchoring point of the canvas item.
	set anchorData [FormatAnchor $w $item $width $height]
	# Insert a PDF inline image into the document data stream.
	append streamdata [InlineImage $anchorData $imageData $width $height]
	# The Tk image can now be deleted.
	image delete $img
  	return $streamdata
    }

    ############# PORTABLE DOCUMENT FORMAT GENERATION PROCEDURES ##############

    # Procedure: AppendInitialDocumentObjects - Add the required PDF objects
    #                                           that form the beginning of the
    #                                           document to the document
    #                                           string.
    # Inputs:
    #   None.
    #
    # Output:
    #   None.
    #
    proc AppendInitialDocumentObjects {} {
	variable var

	# Create the initial object / version indicator.
	# First entry in the xref list.
	set var(xref,values) "0000000000 65535 f \n"
	# Supporting PDF version 1.4
	set var(doc) "%PDF-1.4\n"
	# Create the /Catalog object, which
	# references the Outlines and Pages objects.
	# Add entry to the xref list.
	append var(xref,values) \
	    [format "%010d 00000 n \n" [string length $var(doc)]]
	append var(doc) $var(xref,count) " 0 obj\n"
	append var(doc) "<<\n/Type /Catalog\n"
	# Increment the reference counter to refer to the Outlines object.
	incr var(xref,count)
	# The /Pages object follows immediately after the /Pages object.
	append var(doc) "/Pages " $var(xref,count) " 0 R\n"
	append var(doc) ">>\n"
	append var(doc) "endobj\n"
	# Create the /Pages object, which references only one page.
	# Add entry to the xref list.
	append var(xref,values) \
	    [format "%010d 00000 n \n" [string length $var(doc)]]
	append var(doc) $var(xref,count) " 0 obj\n"
	# Increment the reference counter to refer to the Page object.
	incr var(xref,count)
	append var(doc) "<<\n/Type /Pages\n"
	# There is only one "Kid" page that is referenced.
	append var(doc) "/Kids \[" $var(xref,count) " 0 R\]\n"
	append var(doc) "/Count 1\n"
	append var(doc) ">>\n"
	append var(doc) "endobj\n"
    }

    # Procedure: AppendPageObject - Add the page object to the document string.
    # Inputs:
    #   w - Path to the canvas widget.
    #
    # Output:
    #   None.
    #
    proc AppendPageObject {width height} {
	variable var

	# Create the /Page object.
	# Add entry to the xref list.
	append var(xref,values) \
	    [format "%010d 00000 n \n" [string length $var(doc)]]
	append var(doc) $var(xref,count) " 0 obj\n"
	append var(doc) "<<\n/Type /Page\n"
	# Reference the parent Pages object, which
	# is one less the current reference count.
	append var(doc) "/Parent " [expr {$var(xref,count) - 1}] " 0 R\n"
	set var(width) $width
	set var(height) $height
	append var(doc) "/MediaBox \[0 0 " $var(width) " " $var(height) "\]\n"
	# Increment the reference counter to refer to the Contents object.
	incr var(xref,count)
	append var(doc) "/Contents " $var(xref,count) " 0 R\n"
	append var(doc) "/Resources " [expr {$var(xref,count) + 1}] " 0 R\n"
	append var(doc) ">>\n"
	append var(doc) "endobj\n"
    }

    # Procedure: AppendContentObject - Add the Content object to the document
    #                                  string.
    # Inputs:
    #   w - Path to the canvas widget.
    #
    # Output:
    #   None.
    #
    proc AppendContentObject {w} {
	variable var

	# Add entry to the xref list.
	append var(xref,values) \
	    [format "%010d 00000 n \n" [string length $var(doc)]]
	# Create a stream object with graphics in it.
	append var(doc) $var(xref,count) " 0 obj\n"
	# Increment the reference counter to refer to the Reference object.
	incr var(xref,count)
	set var(streamdata) {}
	foreach item [$w find all] {
	    switch -- [$w type $item] {
		arc {
		    append var(streamdata) [ArcConvert $w $item]
		}
		bitmap {
		    append var(streamdata) [BitmapConvert $w $item]
		}
		image {
		    append var(streamdata) [ImageConvert $w $item]
		}
		line {
		    append var(streamdata) [LineConvert $w $item]
		}
		oval {
		    append var(streamdata) [OvalConvert $w $item]
		}
		polygon {
		    append var(streamdata) [PolygonConvert $w $item]
		}
		rectangle {
		    append var(streamdata) [RectangleConvert $w $item]
		}
		text {
		    append var(streamdata) [TextConvert $w $item]
		}
		window {
		    append var(streamdata) [WindowConvert $w $item]
		}
		default {
		}
	    }
	}
	append var(doc) "<<\n/Length [string length $var(streamdata)]\n>>\n"
	append var(doc) "stream\n"
	append var(doc) "$var(streamdata)"
	append var(doc) "endstream\n"
	append var(doc) "endobj\n"
    }

    # Procedure: AppendResourceObject - Add the Resource object to the
    #                                   document string.
    # Inputs:
    #   None.
    #
    # Output:
    #   None.
    #
    proc AppendResourceObject {} {
	variable var

	# Create a resource object.
	# Add entry to the xref list.
	append var(xref,values) \
	    [format "%010d 00000 n \n" [string length $var(doc)]]
	# Start generation of the Resource object.
	append var(doc) $var(xref,count) " 0 obj\n"
	# Increment the reference counter to refer to the first Font object.
	incr var(xref,count)
	append var(doc) "<<\n"
	# Add resource references for fonts, if there are any.
	if {[llength var(fonts)] > 0} {
	    append var(doc) "/Font <<\n"
	    # Iterate for total number of unique fonts.
	    for {set fcount 0} \
		{$fcount < [llength $var(fonts)]} {incr fcount} {
		# Create the font name and the corresponding object reference.
		    append var(doc) "/F" [expr {$fcount + 1}] " "
		append var(doc) [expr {$var(xref,count) + $fcount}] " 0 R\n"
	    }
	    # Indicate the end of the font resource list.
	    append var(doc) ">>\n"
	}
	# Add resource references for patterns, if there are any.
	if {[llength var(pats)] > 0} {
	    append var(doc) "/ColorSpace <<\n"
	    append var(doc) "/Cs1 \[/Pattern /DeviceRGB\]\n>>\n"
	    append var(doc) "/Pattern <<\n"
	    # Iterate for total number of unique patterns.
	    for {set pcount 0} {$pcount < [llength $var(pats)]} {incr pcount} {
		# Create a pattern name and the corresponding object reference.
		append var(doc) "/P" [expr {$pcount + 1}] " "
		append var(doc) \
		    [expr {$var(xref,count) + $fcount + $pcount}] " 0 R\n"
	    }
	    # Indicate the end of the pattern resource list.
	    append var(doc) ">>\n"
	}
	# Indicate the end of the resource object.
	append var(doc) ">>\n"
	append var(doc) "endobj\n"
    }

    # Procedure: AppendFontObject - Add the Font objects to the document
    #                               string.
    # Inputs:
    #   None.
    #
    # Output:
    #   None.
    #
    proc AppendFontObjects {} {
	variable var

	set ref 1
	# Iterate over each basefont.
	foreach basefont $var(fonts) {
	    # Add entry to the xref list.
	    append var(xref,values) \
		[format "%010d 00000 n \n" [string length $var(doc)]]
	    # Create a font object
	    append var(doc) $var(xref,count) " 0 obj\n"
	    incr var(xref,count)
	    append var(doc) "<<\n/Type /Font\n"
	    # For now, only Type 1 fonts are supported
	    append var(doc) "/Subtype /Type1\n"
	    append var(doc) "/BaseFont /" $basefont "\n"
	    append var(doc) ">>\n"
	    append var(doc) "endobj\n"
	    incr ref
	}
    }

    # Procedure: AppendPatternObjects - Add the Pattern objects to the document
    #                                   string.
    # Inputs:
    #   None.
    #
    # Output:
    #   None.
    #
    proc AppendPatternObjects {} {
	variable var
	set ref 1
	foreach xbmName $var(pats) {
	    # Determine the source of the bitmap data
	    if {[string index $xbmName 0] eq "@"} {
		# Referencing an X11 XBM file; load it in.
		set fp [open [string range $xbmName 1 end]]
		set xbmData [read $fp]
		close $fp
	    } else {
		# Referencing an internal Tk bitmap; load a representation..
		set fp [open [file join $var(libDir) bitmaps ${xbmName}.bmp]]
		set xbmData [read $fp]
		close $fp
	    }

	    # Extract the X11 bitmap dimensions and data. The width is used as
	    # the horizontal step to provide the correct spacing of the tile.
	    foreach {imgWidthStep imgHeight bytes} [ParseX11Bitmap $xbmData] {}
	    # Calculate the complete width of the X11 bitmap data.
	    set imgWidth [expr {8 * [llength $bytes] / $imgHeight}]
	    # Create the data stream the contains the image.
	    set streamdata [InlineImageMask $imgWidth $imgHeight $bytes]
	    # Add entry to the xref list.
	    append var(xref,values) \
		[format "%010d 00000 n \n" [string length $var(doc)]]
	    # Create the pattern object.
	    append var(doc) $var(xref,count) " 0 obj\n"
	    append var(doc) "<<\n/Type /Pattern\n"
	    # The pattern is a tiling pattern.
	    append var(doc) "/PatternType 1\n"
	    # The tiling pattern is uncolored.
	    append var(doc) "/PaintType 2\n"
	    # The tile spacing is constant.
	    append var(doc) "/TilingType 1\n"
	    # The tile bounding box is the size of the bitmap including excess.
	    append var(doc) {/BBox [0 0 } $imgWidth " " $imgHeight {]} "\n"
	    # The horizontal step size is the true X11 bitmap width.
	    append var(doc) "/XStep " $imgWidthStep "\n"
	    append var(doc) "/YStep " $imgHeight "\n"
	    # The pattern matrix is shifted to the top of the page.
	    append var(doc)  "/Matrix \[1 0 0 1 0 " $var(height) "\]\n"
	    # No external resources are used.
	    append var(doc) "/Resources <<\n>>\n"
	    # Determine the length of the stream data.
	    append var(doc) "/Length " [string length $streamdata] "\n"
	    append var(doc) ">>\n"
	    # Add in the actual stream.
	    append var(doc) "stream\n"
	    append var(doc) $streamdata
	    append var(doc) "endstream\n"
	    # Indicate the end of the pattern object.
	    append var(doc) "endobj\n"
	    incr var(xref,count)
	    incr ref
	}
    }


    # Procedure: AppendFinalDocumentObjects - Add the trailing objects to the
    #                                         document string.
    # Inputs:
    #   None.
    #
    # Output:
    #   None.
    #
    proc AppendFinalDocumentObjects {} {
	variable var
	# get the xref position in the file.
	set xrefLen [string length $var(doc)]
	# Create the xref object.
	append var(doc) "xref\n0 " $var(xref,count) "\n" $var(xref,values)
	# Create the trailer object.
	append var(doc) "trailer\n"
	# Indicate the total number of refernces.
	append var(doc) "<<\n/Size " $var(xref,count) "\n"
	append var(doc) "/Root 1 0 R\n"
	append var(doc) ">>\n"
	append var(doc) "startxref\n"
	append var(doc) "$xrefLen\n"
	append var(doc) "%%EOF\n"
    }

    # Procedure: generate - 
    #
    proc generate {w filename args} {
	variable var

	# Set up control variables..
	set var(fonts) {}
	set var(pats) {}
	set var(xref,count) 1
	# Create the front end of the document.
	AppendInitialDocumentObjects
	# The page size mirrors the actual displayed geometry of the canvas.
	AppendPageObject [winfo width $w] [winfo height $w]
	AppendContentObject $w
	AppendResourceObject
	AppendFontObjects
	AppendPatternObjects
	AppendFinalDocumentObjects

	set fp [open $filename w]
	# Must output in unix format, regardless of
	# platform, to meet the PDF specifications.
	fconfigure $fp -translation lf
	puts -nonewline $fp $var(doc)
	close $fp
    }
}

package provide trampoline 0.5.3
