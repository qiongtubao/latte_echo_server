



set ::last_port_attempted 0
proc find_available_port {start count} {
    set port [expr $::last_port_attempted + 1]
    for {set attempts 0} {$attempts < $count} {incr attempts} {
        if {$port < $start || $port >= $start+$count} {
            set port $start
        }
        if {[catch {set fd1 [socket 127.0.0.1 $port]}] &&
            [catch {set fd2 [socket 127.0.0.1 [expr $port+10000]]}]} {
            set ::last_port_attempted $port
            return $port
        } else {
            catch {
                close $fd1
                close $fd2
            }
        }
        incr port
    }
    error "Can't find a non busy port in the $start-[expr {$start+$count-1}] range."
}

# Test if TERM looks like to support colors
proc color_term {} {
    expr {[info exists ::env(TERM)] && [string match *xterm* $::env(TERM)]}
}

proc colorstr {color str} {
    if {[color_term]} {
        set b 0
        if {[string range $color 0 4] eq {bold-}} {
            set b 1
            set color [string range $color 5 end]
        }
        switch $color {
            red {set colorcode {31}}
            green {set colorcode {32}}
            yellow {set colorcode {33}}
            blue {set colorcode {34}}
            magenta {set colorcode {35}}
            cyan {set colorcode {36}}
            white {set colorcode {37}}
            default {set colorcode {37}}
        }
        if {$colorcode ne {}} {
            return "\033\[$b;${colorcode};49m$str\033\[0m"
        }
    } else {
        return $str
    }
}

proc start_echo_server {options {code undefined}} {
    set baseconfig "default.conf"
    set overrides {}
    set omit {}
    set tags {}
    set keep_persistence false
    # parse options
    foreach {option value} $options {
        switch $option {
            "config" {
                set baseconfig $value
            }
            "overrides" {
                set overrides $value
            }
            "omit" {
                set omit $value
            }
            "tags" {
                # If we 'tags' contain multiple tags, quoted and seperated by spaces,
                # we want to get rid of the quotes in order to have a proper list
                set tags [string map { \" "" } $value]
                set ::tags [concat $::tags $tags]
            }
            "keep_persistence" {
                set keep_persistence $value
            }
            default {
                error "Unknown option $option"
            }
        }
    }
    # We skip unwanted tags
    if {![tags_acceptable err]} {
        incr ::num_aborted
        send_data_packet $::test_server_fd ignore $err
        set ::tags [lrange $::tags 0 end-[llength $tags]]
        return
    }
}