#!/bin/sh
# Restart with tcl: -*- mode: tcl; tab-width: 8; -*- \
exec tclsh $0 ${1+"$@"}

##+##########################################################################
#
# Parallel Geturl -- package (and demo) that efficiently downloads large
# numbers of web pages while also handling timeout failures. Web requests
# are queued up and a set number are simultaneously fired off. As requests
# complete, new ones are popped off the queue and launched.
# by Keith Vetter, March 5, 2004
# by Keith Vetter, October 2, 2017 -- added sessions and made more OO
#
# Usage:
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
#

package require http
package provide pgu 2.0

catch {namespace delete ::PGU}

namespace eval ::PGU {
    variable options                            ;# User tweakable values
    variable queue                              ;# Request queue
    variable Q
    set Q(next,sid) 0

    proc ::PGU::New {} {
        variable Q
        set sid [incr Q(next,sid)]
        set name "::PGU::pgu$sid"
        set commandMap {}
        foreach cmd [info commands [namespace current]::*] {
            set tail [namespace tail $cmd]
            if {[string index $tail 0] eq "_" || [string totitle $tail] ne $tail} continue
            if {$tail eq "New"} continue
            lappend commandMap $tail [list $cmd $sid]
        }
        namespace ensemble create -command $name -map $commandMap
        ::PGU::_Reset $sid
        return $name
    }
    proc ::PGU::_Reset {sid} {
        variable Q
        variable queue

        array unset queue $sid,*
        array unset Q $sid,*

        set Q($sid,qhead) 1
        set Q($sid,qtail) 0
        set Q($sid,wait) 0
        set Q($sid,options) [dict create -degree 50 -timeout 30000 -maxRetries 5 -stop 0 -log false]
        set Q($sid,stats) [dict create qlen 0 pending 0 done 0 timeouts 0 failures 0 cancelled 0]
    }

    ::PGU::_Reset 0

}
proc ::PGU::Close {sid} {
    if {$sid eq "-all"} {
        foreach pgu [info commands ::PGU::pgu*] {
            $pgu Close
        }
        return
    }
    array unset ::PGU::Q $sid,*
    array unset ::PGU::queue $sid,*
    set name "::PGU::pgu$sid"
    rename $name {}
}

##+##########################################################################
#
# ::PGU::Config -- allow user to configure some parameters
#
proc ::PGU::Config {sid args} {
    variable Q

    if {[llength $args] == 0} {                 ;# Return all results
        return $Q($sid,options)
    }
    set o [lsort [dict keys $Q($sid,options)]]
    if {[llength $args] > 1 && [llength $args] % 2 != 0} {
        return -code error "Must have an even number of flag and value"
    }

    foreach {flag value} $args {                ;# Get one or set some
        if {! [dict exists $Q($sid,options) $flag]} {
            return -code error "Unknown option $flag, must be: [join $o ", "]"
        }
        if {[llength $args] == 1} {             ;# Get one config value
            return [dict get $Q($sid,options) $flag]
        }
        dict set Q($sid,options) $flag $value
    }
    return $value
}
##+##########################################################################
#
# ::PGU::Add -- adds a url and callback command to are request queue
#
proc ::PGU::Add {sid url cookie doneCmd {statusCmd ""} {progressCmd ""}} {
    variable Q
    variable queue

    for {set i $Q($sid,qhead)} {$i <= $Q($sid,qtail)} {incr i} {
        if {$queue($sid,$i,url) eq $url} return
    }
    set qtail [incr Q($sid,qtail)]
    set queue($sid,$qtail,url) $url
    set queue($sid,$qtail,cookie) $cookie
    set queue($sid,$qtail,dcmd) $doneCmd
    set queue($sid,$qtail,scmd) $statusCmd
    set queue($sid,$qtail,pcmd) $progressCmd
    set queue($sid,$qtail,timeouts) 0
    set queue($sid,$qtail,token) 0

    dict incr Q($sid,stats) qlen
    ::PGU::_StatusChange $sid $Q($sid,qtail) "queued"
}
##+##########################################################################
#
# ::PGU::Launch -- launches web requests if we have the capacity
#
proc ::PGU::Launch {sid} {
    variable queue
    variable Q

    while {1} {
        if {$Q($sid,qtail) < $Q($sid,qhead)} return             ;# Empty queue
        if {[dict get $Q($sid,options) -stop]} return  ;# Turned off
        if {[dict get $Q($sid,stats) pending] >= [dict get $Q($sid,options) -degree]} return

        set id $Q($sid,qhead)
        incr Q($sid,qhead)
        if {$queue($sid,$id,token) != 0} continue    ;# Already handled (cancel)
        set queue($sid,$id,token) zzzz               ;# Mark so can't be cancelled
        ::PGU::_Log $sid queue($sid,$id,token) <-- zzzz

        dict incr Q($sid,stats) pending
        dict incr Q($sid,stats) qlen -1
        ::PGU::_StatusChange $sid $id "pending"

        set url $queue($sid,$id,url)
        set cmd [list ::http::geturl $url -timeout [dict get $Q($sid,options) -timeout] \
                     -command [list ::PGU::_HTTPCommand $sid $id] -binary 1]
        if {$queue($sid,$id,pcmd) ne ""} {
            lappend cmd -progress [list $queue($sid,$id,pcmd) $queue($sid,$id,cookie)]
        }

        set queue($sid,$id,cmd) $cmd
        ::PGU::_Log $sid queue($sid,$id,cmd) $cmd
        set queue($sid,$id,token) [eval $cmd]
        ::PGU::_Log $sid queue($sid,$id,token) <-- $queue($sid,$id,token)
    }
}
##+##########################################################################
#
# ::PGU::Cancel -- cancels items in the queue
#   who: -all => everything
#        -queue => only those waiting in the queue
#        id => a specific entry
#
proc ::PGU::Cancel {sid {who -all}} {
    variable Q
    variable queue

    if {$sid eq "-all"} {
        foreach pgu [info commands ::PGU::pgu*] {
            $pgu Cancel -all
        }
        return
    }

    set stop [dict get $Q($sid,options) -stop]
    dict set Q($sid,options) -stop 1
    set q $who
    if {$who eq "-all" || $who eq "-queue"} {
        set q {}
        foreach qq [lsort -dictionary [array names queue $sid,*,id]] {
            lappend q $queue($qq)
        }
        set Q($sid,qhead) [expr {$Q($sid,qtail) + 1}]
    }
    foreach id $q {
        if {! [info exists queue($sid,$id,url)]} continue
        if {$queue($sid,$id,token) < 0} continue     ;# Already done
        if {$who eq "-queue" && $queue($id,token) != 0} {
            # don't cancel pending requests
            continue
        }
        ::PGU::_CancelOne $sid $id
    }

    dict set Q($sid,options) -stop $stop
    ::PGU::_CheckWait $sid
    return
}
proc ::PGU::_CancelOne {sid id} {
    variable queue
    variable Q

    set token $queue($sid,$id,token)
    if {$token < 0} return                      ;# Already done

    if {$token == 0} {                          ;# Still in the queue
        dict incr Q($sid,stats) cancelled
        dict incr Q($sid,stats) qlen -1
        set queue($sid,$id,token) -3            ;# Mark as cancelled
        ::PGU::_StatusChange $sid $id "cancel"
        array unset queue $sid,$id,*
    } else {
        ::http::reset $token cancel             ;# Pending
        dict incr Q($sid,stats) pending -1
    }
}
##+##########################################################################
#
# ::PGU::_HTTPCommand -- our geturl callback command that handles
# queue maintenance, timeout retries and user callbacks.
#
proc ::PGU::_HTTPCommand {sid id token} {
    variable queue
    variable Q

    ::PGU::_Log $sid $id $token

    set url $queue($sid,$id,url)
    set dcmd $queue($sid,$id,dcmd)
    set cookie $queue($sid,$id,cookie)
    set cnt $queue($sid,$id,timeouts)
    set token $queue($sid,$id,token)

    set status [::http::status $token]
    if {$status == "timeout"} {
        dict incr Q($sid,stats) timeouts
        incr cnt -1
        if {abs($cnt) < [dict get $Q($sid,options) -maxRetries] \
                || [dict get $Q($sid,options) -stop]} {
            ::http::cleanup $token

            ::PGU::_StatusChange $sid $id "timeout"
            set queue($sid,$id,timeouts) $cnt        ;# Remember retry attempts
            set cmd $queue($sid,$id,cmd)
            set queue($sid,$id,token) [eval $cmd]
            return
        }
        dict incr Q($sid,stats) failures
        ::PGU::_StatusChange $sid $id "failure"
        set queue($sid,$id,token) -2                 ;# Mark as failed
    } elseif {$status eq "cancel"} {
        dict incr Q($sid,stats) cancelled
        ::PGU::_StatusChange $sid $id "cancel"
        set queue($sid,$id,token) -3
    } else {  ;# status eq "ok"
        ::PGU::_StatusChange $sid $id "done"
        set queue($sid,$id,token) -1                 ;# Mark as done
        dict incr Q($sid,stats) done
        array unset queue $sid,$id,*
    }
    dict incr Q($sid,stats) pending -1          ;# One less outstanding request
    ::PGU::Launch $sid                          ;# Try launching another request

    set n [catch {$dcmd $token $cookie} emsg]	;# Call user's callback
    if {$n} {puts stderr "HTTP Callback error: $emsg\n"}
    ::http::cleanup $token

    ::PGU::_CheckWait $sid
}
##+##########################################################################
#
# ::PGU::Wait -- blocks until all geturl request queue is empty
#
proc ::PGU::Wait {sid} {
    variable Q

    if {[dict get $Q($sid,stats) qlen] > 0 || [dict get $Q($sid,stats) pending] > 0} {
        vwait ::Q($sid,wait)
    }
}
proc ::PGU::_CheckWait {sid} {
    variable Q
    if {[dict get $Q($sid,stats) qlen] == 0 && [dict get $Q($sid,stats) pending] == 0} {
        incr ::Q($sid,wait)
    }
}
##+##########################################################################
#
# ::PGU::Statistics -- returns dictionary of some statistics of the current state
#
proc ::PGU::Statistics {sid {which ""}} {
    variable Q
    if {$which eq ""} {
        return $Q($sid,stats)
    }
    return [dict get $Q($sid,stats) $which]
}
##+##########################################################################
#
# ::PGU::_StatusChange -- calls user callback when queue status changes
#
proc ::PGU::_StatusChange {sid id how} {
    variable queue

    set scmd $queue($sid,$id,scmd)
    if {$scmd eq ""} return
    set cookie $queue($sid,$id,cookie)
    set n [catch {$scmd $id $how $cookie} emsg]
    if {$n} {puts stderr "StatusChange error : $emsg\n"}
}
proc ::PGU::_Log {sid args} {
    variable Q
    if {[dict get $Q($sid,options) -log]} {
        set function [lindex [info level -1] 0]
        lappend ::LOG "$function [join $args " "]"
    }
}

################################################################
################################################################

proc expect {actual expected {emsg ""}} {
    if {$actual ne $expected} {
        puts stderr "error: $emsg\nexpected: '$expected'\n            got: '$actual'"
        set ::A $actual
        set ::E $expected
    }
}

proc test_config {} {
    set pgu [::PGU::New]
    expect [$pgu Config] "-degree 50 -timeout 30000 -maxRetries 5 -stop 0 -log false"
    expect [$pgu Config -degree] "50"
    expect [$pgu Config -degree 20] "20"
    expect [$pgu Config] "-degree 20 -timeout 30000 -maxRetries 5 -stop 0 -log false"
    $pgu Close
}

proc test_add {} {
    set pgu [::PGU::New]
    expect [$pgu Statistics] "qlen 0 pending 0 done 0 timeouts 0 failures 0 cancelled 0"
    $pgu Add url cookie doneCmd
    expect [$pgu Statistics] "qlen 1 pending 0 done 0 timeouts 0 failures 0 cancelled 0"
    for {set i 0} {$i < 10} {incr i} {
        $pgu Add url$i cookie$i doneCmd$i
    }
    expect [$pgu Statistics] "qlen 11 pending 0 done 0 timeouts 0 failures 0 cancelled 0"
    $pgu Close
}
proc test_add1 {} {
    set pgu [::PGU::New]

    set url "http://httpbin.org/get?a=b"
    set cookie "my cookie"
    proc done_cmd {token cookie} {
        set data [::http::data $token]
        puts "in done command: $token $cookie => $data"
    }
    $pgu Add $url $cookie done_cmd
    $pgu Launch
    $pgu Wait
    expect [$pgu Statistics done] 1
    $pgu Close
}
proc test_addN {total} {
    proc done_cmd {token cookie} {
        # set data [::http::data $token]
        if {! [string match "my cookie *" $cookie]} { puts stderr "bad cookie: '$cookie'" }
        lassign $cookie . . id
        lappend ::IDS $id
        puts -nonewline "$id "
    }
    set ::IDS [list total=$total]

    set pgu [::PGU::New]

    for {set i 0} {$i < $total} {incr i} {
        set url "http://httpbin.org/get?cnt=$i"
        set cookie "my cookie $i"
        $pgu Add $url $cookie done_cmd
    }
    $pgu Config -degree 10
    $pgu Launch
    $pgu Wait
    puts "\ndone"
    expect [$pgu Statistics done] $total
    $pgu Close
}

alink ::PGU::Q
alink ::PGU::queue
return 1
