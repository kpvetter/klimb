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

# Usage:
#  ::PGU::Config ?-degree 50? ?-timeout 30000? ?-maxRetries 5?
#  ::PGU::Add url cookie doneCmd ?statusCmd? ?progressCmd? => id
#         proc doneCmd {token cookie} {}
#         proc statusCmd {id how cookie} {}
#                            how: queued pending cancel timeout failure done
#         proc progressCmd {cookie token total current} {}
#  ::PGU::Launch
#  ::PGU::Cancel who  => who: -all -queue id
#  ::PGU::Wait
#  ::PGU::Statistics => Dictionary: qlen pending done timeouts failures cancelled
#

package require http
package provide pgu 1.0

namespace eval ::PGU {
    variable options                            ;# User tweakable values
    variable queue                              ;# Request queue
    variable qhead 1                            ;# First unprocessed slot
    variable qtail 0                            ;# Last in use slot
    variable stats                              ;# Array of statistics
    variable wait 0                             ;# For vwait
    variable log 0

    array set options {
        -degree 50
        -timeout 30000
        -maxRetries 5
        -stop 0
    }

    proc ::PGU::Reset {} {
        variable queue
        variable stats
        variable qhead 1
        variable qtail 0
        variable wait 0

        catch {unset queue}
        array set queue {}
        array set stats {
            qlen 0 pending 0 done 0 timeouts 0 failures 0 cancelled 0}
    }
    ::PGU::Reset
}
##+##########################################################################
#
# ::PGU::Config -- allow user to configure some parameters
#
proc ::PGU::Config {args} {
    variable options
    set o [lsort [array names options]]

    if {[llength $args] == 0} {                 ;# Return all results
        set result {}
        foreach name $o {
            lappend result $name $options($name)
        }
        return $result
    }
    foreach {flag value} $args {                ;# Get one or set some
        if {[lsearch $o $flag] == -1} {
            return -code error "Unknown option $flag, must be: [join $o ", "]"
        }
        if {[llength $args] == 1} {             ;# Get one config value
            return $options($flag)
        }
        set options($flag) $value               ;# Set the config value
    }
}
##+##########################################################################
#
# ::PGU::Add -- adds a url and callback command to are request queue
#
proc ::PGU::Add {url cookie doneCmd {statusCmd ""} {progressCmd ""}} {
    variable queue ; variable qtail ; variable stats
    variable qhead

    for {set i $qhead} {$i <= $qtail} {incr i} {
        if {$queue($i,url) eq $url} return
    }
    incr qtail
    set queue($qtail,id) $qtail
    set queue($qtail,url) $url
    set queue($qtail,dcmd) $doneCmd
    set queue($qtail,scmd) $statusCmd
    set queue($qtail,pcmd) $progressCmd
    set queue($qtail,cookie) $cookie
    set queue($qtail,timeouts) 0
    set queue($qtail,token) 0

    incr stats(qlen)
    ::PGU::_StatusChange $qtail "queued"
}
##+##########################################################################
#
# ::PGU::Launch -- launches web requests if we have the capacity
#
proc ::PGU::Launch {} {
    variable queue
    variable qtail
    variable qhead
    variable options
    variable stats

    while {1} {
        if {$qtail < $qhead} return             ;# Empty queue
        if {$options(-stop)} return             ;# Turned off
        if {$stats(pending) >= $options(-degree)} return ;# No slots open

        set id $qhead
        incr qhead
        if {$queue($id,token) != 0} continue    ;# Already handled (cancel)
        set queue($id,token) zzzz               ;# Mark so can't be cancelled
        ::PGU::Log queue($id,token) <-- zzzz

        incr stats(pending)
        incr stats(qlen) -1
        ::PGU::_StatusChange $id "pending"

        set url $queue($id,url)
        set cmd [list ::http::geturl $url -timeout $options(-timeout) \
                     -command [list ::PGU::_HTTPCommand $id] -binary 1]
        if {$queue($id,pcmd) ne ""} {
            lappend cmd -progress [list $queue($id,pcmd) $queue($id,cookie)]
        }

        set queue($id,cmd) $cmd
        ::PGU::Log queue($id,cmd) $cmd
        set queue($id,token) [eval $cmd]
        ::PGU::Log queue($id,token) <-- $queue($id,token)
    }
}
##+##########################################################################
#
# ::PGU::Cancel -- cancels items in the queue
#   who: -all => everything
#        -queue => only those waiting in the queue
#        id => a specific entry
#
proc ::PGU::Cancel {{who -all}} {
    variable queue
    variable qtail
    variable qhead
    variable options
    variable stats

    set stop $options(-stop)
    set options(-stop) 1                        ;# Turn off any more fetching
    set q $who
    if {$who eq "-all" || $who eq "-queue"} {
        set q {}
        foreach qq [lsort -dictionary [array names queue *,id]] {
            lappend q $queue($qq)
        }
        set qhead [expr {$qtail + 1}]
    }
    foreach id $q {
        if {! [info exists queue($id,url)]} continue
        if {$queue($id,token) < 0} continue     ;# Already done
        if {$who eq "-queue" && $queue($id,token) != 0} {
            # don't cancel pending requests
            continue
        }
        ::PGU::_CancelOne $id
    }
    set options(-stop) $stop

    if {$stats(qlen) == 0 && $stats(pending) == 0} { ;# If done trigger vwait
        set ::PGU::wait 1
    }
    return
}
proc ::PGU::_CancelOne {id} {
    variable queue
    variable stats

    set token $queue($id,token)
    if {$token < 0} return                      ;# Already done

    if {$token == 0} {                          ;# Still in the queue
        incr stats(cancelled)
        incr stats(qlen) -1
        set queue($id,token) -3                 ;# Mark as cancelled
        ::PGU::_StatusChange $id "cancel"
        array unset queue $id,*
    } else {
        ::http::reset $token cancel             ;# Pending
        incr stats(pending) -1
    }
}
##+##########################################################################
#
# ::PGU::_HTTPCommand -- our geturl callback command that handles
# queue maintenance, timeout retries and user callbacks.
#
proc ::PGU::_HTTPCommand {id token} {
    variable queue
    variable stats
    variable options
    variable wait

    ::PGU::Log $id $token

    #foreach {url cmd cookie cnt token} $queue($id) break
    set url $queue($id,url)
    set dcmd $queue($id,dcmd)
    set cookie $queue($id,cookie)
    set cnt $queue($id,timeouts)
    set token $queue($id,token)

    set status [::http::status $token]
    if {$status == "timeout"} {
        incr stats(timeouts)
        incr cnt -1
        if {abs($cnt) < $options(-maxRetries) || $options(-stop)} {
            ::http::cleanup $token

            ::PGU::_StatusChange $id "timeout"
            set queue($id,timeouts) $cnt        ;# Remember retry attempts
            set cmd $queue($id,cmd)
            set queue($id,token) [eval $cmd]
            return
        }
        incr stats(failures)
        ::PGU::_StatusChange $id "failure"
        set queue($id,token) -2                 ;# Mark as failed
    } elseif {$status eq "cancel"} {
        incr stats(cancelled)
        ::PGU::_StatusChange $id "cancel"
        set queue($id,token) -3
    } else {
        ::PGU::_StatusChange $id "done"
        set queue($id,token) -1                 ;# Mark as done
        incr stats(done)
        array unset queue $id,*
    }
    incr stats(pending) -1                      ;# One less outstanding request
    ::PGU::Launch                               ;# Try launching another request

    set n [catch {$dcmd $token $cookie} emsg]	;# Call user's callback
    if {$n} {puts stderr "HTTP Callback error: $emsg\n"}
    ::http::cleanup $token

    if {$stats(qlen) == 0 && $stats(pending) == 0} { ;# If done trigger vwait
        set ::PGU::wait 1
    }
}
##+##########################################################################
#
# ::PGU::Wait -- blocks until all geturl request queue is empty
#
proc ::PGU::Wait {} {
    variable stats

    if {$stats(qlen) > 0 || $stats(pending) > 0} { ;# Something to wait for
        vwait ::PGU::wait
    }
}
##+##########################################################################
#
# ::PGU::Statistics -- returns dictionary of some statistics of the current state
#
proc ::PGU::Statistics {} {
    variable stats
    set result {}
    foreach key {qlen pending done timeouts failures cancelled} {
        lappend result $key $stats($key)
    }
    return $result
}
##+##########################################################################
#
# ::PGU::_StatusChange -- calls user callback when queue status changes
#
proc ::PGU::_StatusChange {id how} {
    variable queue

    set scmd $queue($id,scmd)
    if {$scmd eq ""} return
    set cookie $queue($id,cookie)
    set n [catch {$scmd $id $how $cookie} emsg]
    if {$n} {puts stderr "StatusChange error : $emsg\n"}
}
proc ::PGU::Log {args} {
    if {$::PGU::log} {
        set function [lindex [info level -1] 0]
        lappend ::LOG "$function [join $args " "]"
    }
}

return 1

set missing {}
foreach m $downloads {
    lassign $m tile fname url
    if {! [file exists $fname]} { lappend missing [list $fname $url] }
}
