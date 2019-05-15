#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
exec tclsh $0 ${1+"$@"}

##+##########################################################################
#
# test_pgu2.tcl -- <description>
# by Keith Vetter 2018-07-23
#

#package require Tk
catch {wm withdraw .}

#  set pgu [::PGU::New]
#  $pgu Config  ?-degree 50? ?-timeout 30000? ?-maxRetries 5?
#  $pgu Add url cookie doneCmd ?statusCmd? ?progressCmd? => id
#         proc doneCmd {token cookie} {}
#         proc statusCmd {id how cookie} {}
#                            how: queued pending cancel timeout failure done
#         proc progressCmd {cookie token total current} {}
#  $pgu Launch
#  $pgu Cancel who  => who: -all -queue id
#  $pgu Wait
#  $pgu Statistics => Dictionary: qlen pending done timeouts failures cancelled
#  $pgu Close

source packages/pgu.tcl

proc doneCmd {token cookie} {
    lassign $cookie id fname
    set meta [::http::meta $token]
    puts "KPV: in doneCmd: cookie: $cookie -> [::http::ncode $token]"
    set fout [open $fname wb]
    puts -nonewline $fout [::http::data $token]
    close $fout
}

set cookie1 {1 /tmp/foo1.jpg}
set cookie2 {2 /tmp/foo2.jpg}
set url1 http://khm.google.com/vt/lbw/lyrs=p&x=329&y=795&z=11
set url2 http://khm.google.com/vt/lbw/lyrs=p&x=329&y=796&z=11

::PGU::Add $url1 $cookie1 doneCmd
::PGU::Add $url2 $cookie2 doneCmd
::PGU::Launch
::PGU::Wait

return
package require http
set url1 http://khm.google.com/vt/lbw/lyrs=p&x=329&y=795&z=11
set token [::http::geturl $url1 -binary 1]
set data [::http::data $token] ; list
set meta [::http::meta $token]
set ncode [::http::ncode $token]
puts "ncode: $ncode"
dict print $meta
puts "len: [string length $data]"
>>> /tmp/foo.jpg $data
