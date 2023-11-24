set ::tags {}
# Check if current ::tags match requested tags. If ::allowtags are used,
# there must be some intersection. If ::denytags are used, no intersection
# is allowed. Returns 1 if tags are acceptable or 0 otherwise, in which
# case err_return names a return variable for the message to be logged.
proc tags_acceptable {err_return} {
    upvar $err_return err

    # If tags are whitelisted, make sure there's match
    if {[llength $::allowtags] > 0} {
        set matched 0
        foreach tag $::allowtags {
            if {[lsearch $::tags $tag] >= 0} {
                incr matched
            }
        }
        if {$matched < 1} {
            set err "Tag: none of the tags allowed"
            return 0
        }
    }

    foreach tag $::denytags {
        if {[lsearch $::tags $tag] >= 0} {
            set err "Tag: $tag denied"
            return 0
        }
    }

    return 1
}

proc tags {tags code} {
    # If we 'tags' contain multiple tags, quoted and seperated by spaces,
    # we want to get rid of the quotes in order to have a proper list
    set tags [string map { \" "" } $tags]
    set ::tags [concat $::tags $tags]
    if {![tags_acceptable err]} {
        incr ::num_aborted
        send_data_packet $::test_server_fd ignore $err
        set ::tags [lrange $::tags 0 end-[llength $tags]]
        return
    }
    uplevel 1 $code
    set ::tags [lrange $::tags 0 end-[llength $tags]]
<<<<<<< HEAD
=======
}

proc spawn_server {main config_file stdout stderr} {
    if {$::valgrind} {
        set pid [exec valgrind --track-origins=yes --trace-children=yes --suppressions=[pwd]/src/valgrind.sup --show-reachable=no --show-possibly-lost=no --leak-check=full $main $config_file >> $stdout 2>> $stderr &]
    } elseif ($::stack_logging) {
        set pid [exec /usr/bin/env MallocStackLogging=1 MallocLogFile=/tmp/malloc_log.txt $main $config_file >> $stdout 2>> $stderr &]
    } else {
        # ASAN_OPTIONS environment variable is for address sanitizer. If a test
        # tries to allocate huge memory area and expects allocator to return
        # NULL, address sanitizer throws an error without this setting.
        puts [format "/usr/bin/env ASAN_OPTIONS=allocator_may_return_null=1 $main $config_file >> $stdout 2>> $stderr &" ]
        set pid [exec /usr/bin/env ASAN_OPTIONS=allocator_may_return_null=1 $main $config_file >> $stdout 2>> $stderr &]
    }

    if {$::wait_server} {
        set msg "server started PID: $pid. press any key to continue..."
        puts $msg
        read stdin 1
    }

    # Tell the test server about this new instance.
    send_data_packet $::test_server_fd server-spawned $pid
    return $pid
}

proc wait_server_started {config_file stdout pid} {
    set checkperiod 100;
    set maxiter [expr {120*1000/$checkperiod}]
    set port_busy 0
    while 1 {
        if {[regexp -- "start latte server success PID: " [exec cat $stdout]]} {
            break
        }
        after $checkperiod 
        incr maxiter -1
        if {$maxiter == 0} {
            start_server_error $config_file "No PID detected in log $stdout"
            puts "--- LOG CONTENT ---"
            puts [exec cat $stdout]
            puts "-------------------"
            break
        }
        if {[regexp {start latte server fail!!!} [exec cat $stdout]]} {
            set port_busy 1
            break
        }
    }
    return $port_busy
}


# Write the configuration in the dictionary 'config' in the specified
# file name.
proc create_server_config_file {filename config} {
    set fp [open $filename w+]
    foreach directive [dict keys $config] {
        puts -nonewline $fp "$directive "
        puts $fp [dict get $config $directive]
    }
    close $fp
}


# Return 1 if the server at the specified addr is reachable by PING, otherwise
# returns 0. Performs a try every 50 milliseconds for the specified number
# of retries.
proc server_is_up {host port retrynum} {
    after 10 ;# Use a small delay to make likely a first-try success.
    set retval 0
    while {[incr retrynum -1]} {
        if {[catch {ping_server $host $port} ping]} {
            set ping 0
        }
        if {$ping} {return 1}
        after 50
    }
    return 0
}

proc start_echo_server {options {code undefined}} {
    set baseconfig "default.conf"
    set overrides {}
    set omit {}
    set tags {}
    set keep_persistence false

    # # parse options
    # foreach {option value} $options {
        
    # }
    set data [split [exec cat "tests/assert/$baseconfig"] "\n"]
    set config {}

    set dir [tmpdir server]
    
    # write new configuration to temporary file
    set config_file [tmpfile redis.conf]
    set port [find_available_port $::baseport $::portcount]
    
    dict set config port $port    
    create_server_config_file $config_file $config

    set stdout [format "%s/%s" $dir "stdout"]
    set stderr [format "%s/%s" $dir "stderr"]

    # 打印进度  在执行什么test
    if {[info exists ::cur_test]} {
        set fd [open $stdout "a+"]
        puts $fd "### Starting server for test $::cur_test"
        close $fd
    }
    set server_started 0 
    while {$server_started == 0} {
        if {$::verbose} {
            puts -nonewline "=== ($tags) Starting server ${::host}:${port} "
        }

        send_data_packet $::test_server_fd "server-spawning" "port $port"
        set pid [spawn_server src/main $config_file $stdout $stderr]
        set port_busy [wait_server_started $config_file $stdout $pid]
        # Sometimes we have to try a different port, even if we checked
        # for availability. Other test clients may grab the port before we
        # are able to do it for example.
        if {$port_busy} {
            puts "Port $port was already busy, trying another port..."
            set port [find_available_port $::baseport $::portcount]
            if {$::tls} {
                dict set config "tls-port" $port
            } else {
                dict set config port $port
            }
            create_server_config_file $config_file $config

            # Truncate log so wait_server_started will not be looking at
            # output of the failed server.
            close [open $stdout "w"]

            continue; # Try again
        }
        if {$::valgrind} {set retrynum 1000} else {set retrynum 100}
        if {$code ne "undefined"} {
            set serverisup [server_is_up $::host $port $retrynum]
        } else {
            set serverisup 1
        }

        if {$::verbose} {
            puts ""
        }

        if {!$serverisup} {
            set err {}
            append err [exec cat $stdout] "\n" [exec cat $stderr]
            start_server_error $config_file $err
            return
        }
        set server_started 1
    }


    if {$code ne "undefined"} {
        # append the server to the stack
        lappend ::servers $srv

        # connect client (after server dict is put on the stack)
        reconnect

        # remember previous num_failed to catch new errors
        set prev_num_failed $::num_failed

        # execute provided block
        set num_tests $::num_tests
        if {[catch { uplevel 1 $code } error]} {
            set backtrace $::errorInfo
            set assertion [string match "assertion:*" $error]

            # fetch srv back from the server list, in case it was restarted by restart_server (new PID)
            set srv [lindex $::servers end]

            # pop the server object
            set ::servers [lrange $::servers 0 end-1]

            # Kill the server without checking for leaks
            dict set srv "skipleaks" 1
            

            if {$::dump_logs && $assertion} {
                # if we caught an assertion ($::num_failed isn't incremented yet)
                # this happens when the test spawns a server and not the other way around
                dump_server_log $srv
            } else {
                # Print crash report from log
                set crashlog [crashlog_from_file [dict get $srv "stdout"]]
                if {[string length $crashlog] > 0} {
                    puts [format "\nLogged crash report (pid %d):" [dict get $srv "pid"]]
                    puts "$crashlog"
                    puts ""
                }

                set sanitizerlog [sanitizer_errors_from_file [dict get $srv "stderr"]]
                if {[string length $sanitizerlog] > 0} {
                    puts [format "\nLogged sanitizer errors (pid %d):" [dict get $srv "pid"]]
                    puts "$sanitizerlog"
                    puts ""
                }
            }

            if {!$assertion && $::durable} {
                # durable is meant to prevent the whole tcl test from exiting on
                # an exception. an assertion will be caught by the test proc.
                set msg [string range $error 10 end]
                lappend details $msg
                lappend details $backtrace
                lappend ::tests_failed $details

                incr ::num_failed
                send_data_packet $::test_server_fd err [join $details "\n"]
            } else {
                # Re-raise, let handler up the stack take care of this.
                error $error $backtrace
            }
        } else {
            if {$::dump_logs && $prev_num_failed != $::num_failed} {
                dump_server_log $srv
            }
        }

        # fetch srv back from the server list, in case it was restarted by restart_server (new PID)
        set srv [lindex $::servers end]

        # Don't do the leak check when no tests were run
        if {$num_tests == $::num_tests} {
            dict set srv "skipleaks" 1
        }

        # pop the server object
        set ::servers [lrange $::servers 0 end-1]

        set ::tags [lrange $::tags 0 end-[llength $tags]]
        kill_server $srv
        if {!$keep_persistence} {
            clean_persistence $srv
        }
        set _ ""
    } else {
        set ::tags [lrange $::tags 0 end-[llength $tags]]
        set _ $srv
    }
    

>>>>>>> 97a5833 (only save)
}