
package require Tcl 8.5
package provide echo_client 0.1


namespace eval echo_client {}
set ::echo_client::id 0
array set ::echo_client::fd {}
array set ::echo_client::addr {}
array set ::echo_client::blocking {}
array set ::echo_client::deferred {}
array set ::echo_client::reconnect {}
array set ::echo_client::callback {}
array set ::echo_client::state {} ;# State in non-blocking reply reading
array set ::echo_client::statestack {} ;# Stack of states, for nested mbulks


proc echo_client  {{server 127.0.0.1} {port 6379} {defer 0} {tls 0} {tlsoptions {}}} {
    # if {$tls} {
    #     package require tls
    #     ::tls::init \
    #         -cafile "$::tlsdir/ca.crt" \
    #         -certfile "$::tlsdir/redis.crt" \
    #         -keyfile "$::tlsdir/redis.key" \
    #         {*}$tlsoptions
    #     set fd [::tls::socket $server $port]
    # } else {
        set fd [socket $server $port]
    # }
    fconfigure $fd -translation binary
    set id [incr ::echo_client::id]
    set ::echo_client::fd($id) $fd
    set ::echo_client::addr($id) [list $server $port]
    set ::echo_client::blocking($id) 1
    set ::echo_client::deferred($id) $defer
    set ::echo_client::reconnect($id) 0
    set ::echo_client::tls $tls
    ::echo_client::client_reset_state $id
    interp alias {} ::echo_client::clientHandle$id {} ::echo_client::__dispatch__ $id

}

# This is a wrapper to the actual dispatching procedure that handles
# reconnection if needed.
proc ::echo_client::__dispatch__ {id method args} {
    set errorcode [catch {::echo_client::__dispatch__raw__ $id $method $args} retval]
    if {$errorcode && $::echo_client::reconnect($id) && $::echo_client::fd($id) eq {}} {
        # Try again if the connection was lost.
        # FIXME: we don't re-select the previously selected DB, nor we check
        # if we are inside a transaction that needs to be re-issued from
        # scratch.
        set errorcode [catch {::echo_client::__dispatch__raw__ $id $method $args} retval]
    }
    return -code $errorcode $retval
}

proc ::echo_client::__dispatch__raw__ {id method argv} {

    set fd $::echo_client::fd($id)

    # Reconnect the link if needed.
    if {$fd eq {}} {
        lassign $::echo_client::addr($id) host port
        if {$::echo_client::tls} {
            set ::echo_client::fd($id) [::tls::socket $host $port]
        } else {
            set ::echo_client::fd($id) [socket $host $port]
        }
        fconfigure $::echo_client::fd($id) -translation binary
        set fd $::echo_client::fd($id)
    }

    set blocking $::echo_client::blocking($id)
    set deferred $::echo_client::deferred($id)
    if {$blocking == 0} {
        if {[llength $argv] == 0} {
            error "Please provide a callback in non-blocking mode"
        }
        set callback [lindex $argv end]
        set argv [lrange $argv 0 end-1]
    }
    if {[info command ::echo_client::__method__$method] eq {}} {
        # set cmd "*[expr {[llength $argv]+1}]\r\n"
        # append cmd "$[string length $method]\r\n$method\r\n"
        # foreach a $argv {
        #     append cmd "$[string length $a]\r\n$a\r\n"
        # }
        # ===
        set cmd "$argv\n"
        ::echo_client::client_write $fd $cmd
        if {[catch {flush $fd}]} {
            set ::echo_client::fd($id) {}
            return -code error "I/O error reading reply"
        }

        if {!$deferred} {
            if {$blocking} {
                ::echo_client::client_read_reply $id $fd
            } else {
                # Every well formed reply read will pop an element from this
                # list and use it as a callback. So pipelining is supported
                # in non blocking mode.
                lappend ::echo_client::callback($id) $callback
                fileevent $fd readable [list ::echo_client::client_readable $fd $id]
            }
        }
    } else {
        uplevel 1 [list ::echo_client::__method__$method $id $fd] $argv
    }
}

proc ::echo_client::__method__blocking {id fd val} {
    set ::echo_client::blocking($id) $val
    fconfigure $fd -blocking $val
}

proc ::echo_client::__method__reconnect {id fd val} {
    set ::echo_client::reconnect($id) $val
}

proc ::echo_client::__method__read {id fd} {
    ::echo_client::client_read_reply $id $fd
}

proc ::echo_client::__method__write {id fd buf} {
    ::echo_client::client_write $fd $buf
}

proc ::echo_client::__method__flush {id fd} {
    flush $fd
}

proc ::echo_client::__method__close {id fd} {
    catch {close $fd}
    catch {unset ::echo_client::fd($id)}
    catch {unset ::echo_client::addr($id)}
    catch {unset ::echo_client::blocking($id)}
    catch {unset ::echo_client::deferred($id)}
    catch {unset ::echo_client::reconnect($id)}
    catch {unset ::echo_client::state($id)}
    catch {unset ::echo_client::statestack($id)}
    catch {unset ::echo_client::callback($id)}
    catch {interp alias {} ::echo_client::clientHandle$id {}}
}

proc ::echo_client::__method__channel {id fd} {
    return $fd
}

proc ::echo_client::__method__deferred {id fd val} {
    set ::echo_client::deferred($id) $val
}

proc ::echo_client::client_write {fd buf} {
    puts -nonewline $fd $buf
}

proc ::echo_client::client_writenl {fd buf} {
    client_write $fd $buf
    client_write $fd "\r\n"
    flush $fd
}

proc ::echo_client::client_readnl {fd len} {
    set buf [read $fd $len]
    read $fd 2 ; # discard CR LF
    return $buf
}

proc ::echo_client::client_bulk_read {fd} {
    set count [client_read_line $fd]
    if {$count == -1} return {}
    set buf [client_readnl $fd $count]
    return $buf
}

proc ::echo_client::client_multi_bulk_read {id fd} {
    set count [client_read_line $fd]
    if {$count == -1} return {}
    set l {}
    set err {}
    for {set i 0} {$i < $count} {incr i} {
        if {[catch {
            lappend l [client_read_reply $id $fd]
        } e] && $err eq {}} {
            set err $e
        }
    }
    if {$err ne {}} {return -code error $err}
    return $l
}

proc ::echo_client::client_read_line fd {
    string trim [gets $fd]
}

proc ::echo_client::client_read_reply {id fd} {
    # set type [read $fd 1]
    # switch -exact -- $type {
    #     : -
    #     + {client_read_line $fd}
    #     - {return -code error [client_read_line $fd]}
    #     $ {client_bulk_read $fd}
    #     * {client_multi_bulk_read $id $fd}
    #     default {
    #         if {$type eq {}} {
    #             set ::echo_client::fd($id) {}
    #             return -code error "I/O error reading reply"
    #         }
    #         return -code error "Bad protocol, '$type' as reply type byte"
    #     }
    # }

    # ===
    client_read_line $fd
}

proc ::echo_client::client_reset_state id {
    set ::echo_client::state($id) [dict create buf {} mbulk -1 bulk -1 reply {}]
    set ::echo_client::statestack($id) {}
}

proc ::echo_client::client_call_callback {id type reply} {
    set cb [lindex $::echo_client::callback($id) 0]
    set ::echo_client::callback($id) [lrange $::echo_client::callback($id) 1 end]
    uplevel #0 $cb [list ::echo_client::clientHandle$id $type $reply]
    ::echo_client::client_reset_state $id
}

# Read a reply in non-blocking mode.
proc ::echo_client::client_readable {fd id} {
    if {[eof $fd]} {
        client_call_callback $id eof {}
        ::echo_client::__method__close $id $fd
        return
    }
    if {[dict get $::echo_client::state($id) bulk] == -1} {
        set line [gets $fd]
        if {$line eq {}} return ;# No complete line available, return
        switch -exact -- [string index $line 0] {
            : -
            + {client_call_callback $id reply [string range $line 1 end-1]}
            - {client_call_callback $id err [string range $line 1 end-1]}
            $ {
                dict set ::echo_client::state($id) bulk \
                    [expr [string range $line 1 end-1]+2]
                if {[dict get $::echo_client::state($id) bulk] == 1} {
                    # We got a $-1, hack the state to play well with this.
                    dict set ::echo_client::state($id) bulk 2
                    dict set ::echo_client::state($id) buf "\r\n"
                    ::echo_client::client_readable $fd $id
                }
            }
            * {
                dict set ::echo_client::state($id) mbulk [string range $line 1 end-1]
                # Handle *-1
                if {[dict get $::echo_client::state($id) mbulk] == -1} {
                    client_call_callback $id reply {}
                }
            }
            default {
                client_call_callback $id err \
                    "Bad protocol, $type as reply type byte"
            }
        }
    } else {
        set totlen [dict get $::echo_client::state($id) bulk]
        set buflen [string length [dict get $::echo_client::state($id) buf]]
        set toread [expr {$totlen-$buflen}]
        set data [read $fd $toread]
        set nread [string length $data]
        dict append ::echo_client::state($id) buf $data
        # Check if we read a complete bulk reply
        if {[string length [dict get $::echo_client::state($id) buf]] ==
            [dict get $::echo_client::state($id) bulk]} {
            if {[dict get $::echo_client::state($id) mbulk] == -1} {
                client_call_callback $id reply \
                    [string range [dict get $::echo_client::state($id) buf] 0 end-2]
            } else {
                dict with ::echo_client::state($id) {
                    lappend reply [string range $buf 0 end-2]
                    incr mbulk -1
                    set bulk -1
                }
                if {[dict get $::echo_client::state($id) mbulk] == 0} {
                    client_call_callback $id reply \
                        [dict get $::echo_client::state($id) reply]
                }
            }
        }
    }
}
