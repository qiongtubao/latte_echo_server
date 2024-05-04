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

proc start_server_error {config_file error} {
    set err {}
    append err "Can't start the Redis server\n"
    append err "CONFIGURATION:"
    append err [exec cat $config_file]
    append err "\nERROR:"
    append err [string trim $error]
    send_data_packet $::test_server_fd err $err
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

proc ping_server {host port} {
    set retval 0
    if {[catch {
        if {$::tls} {
            set fd [::tls::socket $host $port] 
        } else {
            set fd [socket $host $port]
        }
        fconfigure $fd -translation binary
        puts $fd "PING\n"
        flush $fd
        set reply [gets $fd]
        if {[string range $reply 0 4] eq {PING}} {
            set retval 1
        }
        close $fd
    } e]} {
        if {$::verbose} {
            puts -nonewline "."
        }
    } else {
        if {$::verbose} {
            puts -nonewline "ok"
        }
    }
    return $retval
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

proc is_alive config {
    set pid [dict get $config pid]
    if {[catch {exec ps -p $pid} err]} {
        return 0
    } else {
        return 1
    }
}

proc kill_server config {
    # nothing to kill when running against external server
    if {$::external} return

    # nevermind if its already dead
    if {![is_alive $config]} { return }
    set pid [dict get $config pid]

    # check for leaks
    if {![dict exists $config "skipleaks"]} {
        catch {
            if {[string match {*Darwin*} [exec uname -a]]} {
                tags {"leaks"} {
                    test "Check for memory leaks (pid $pid)" {
                        set output {0 leaks}
                        catch {exec leaks $pid} output
                        if {[string match {*process does not exist*} $output] ||
                            [string match {*cannot examine*} $output]} {
                            # In a few tests we kill the server process.
                            set output "0 leaks"
                        }
                        set output
                    } {*0 leaks*}
                }
            }
        }
    }

    # kill server and wait for the process to be totally exited
    send_data_packet $::test_server_fd server-killing $pid
    catch {exec kill $pid}
    if {$::valgrind} {
        set max_wait 60000
    } else {
        set max_wait 10000
    }
    while {[is_alive $config]} {
        incr wait 10

        if {$wait >= $max_wait} {
            puts "Forcing process $pid to exit..."
            catch {exec kill -KILL $pid}
        } elseif {$wait % 1000 == 0} {
            puts "Waiting for process $pid to exit..."
        }
        after 10
    }

    # Check valgrind errors if needed
    if {$::valgrind} {
        check_valgrind_errors [dict get $config stderr]
    }

    # Remove this pid from the set of active pids in the test server.
    send_data_packet $::test_server_fd server-killed $pid
}

proc reconnect {args} {
    set level [lindex $args 0]
    if {[string length $level] == 0 || ![string is integer $level]} {
        set level 0
    }

    set srv [lindex $::servers end+$level]
    set host [dict get $srv "host"]
    set port [dict get $srv "port"]
    set config [dict get $srv "config"]
    set client [echo_client $host $port 0 $::tls]
    dict set srv "client" $client

    # select the right db when we don't have to authenticate
    # if {![dict exists $config "requirepass"]} {
    #     $client select 9
    # }

    # re-set $srv in the servers list
    lset ::servers end+$level $srv
}

proc start_echo_server {options {code undefined}} {
    # If we are running against an external server, we just push the
    # host/port pair in the stack the first time


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
    # set port_param [expr $::tls ? {"tls-port"} : {"port"}]
    set host $::host
    if {[dict exists $config bind]} { set host [dict get $config bind] }
    # if {[dict exists $config $port_param]} { set port [dict get $config $port_param] }

    #设置属性
    dict set srv "config_file" $config_file
    dict set srv "config" $config
    dict set srv "pid" $pid
    dict set srv "host" $host
    dict set srv "port" $port
    dict set srv "stdout" $stdout
    dict set srv "stderr" $stderr

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
            puts $error
            set backtrace $::errorInfo

            # Kill the server without checking for leaks
            dict set srv "skipleaks" 1
            kill_server $srv

            # Print warnings from log
            puts [format "\nLogged warnings (pid %d):" [dict get $srv "pid"]]
            set warnings [warnings_from_file [dict get $srv "stdout"]]
            if {[string length $warnings] > 0} {
                puts "$warnings"
            } else {
                puts "(none)"
            }
            puts ""

            error $error $backtrace
        
        
        } 

        # Don't do the leak check when no tests were run
        if {$num_tests == $::num_tests} {
            dict set srv "skipleaks" 1
        }

        # pop the server object
        set ::servers [lrange $::servers 0 end-1]

        set ::tags [lrange $::tags 0 end-[llength $tags]]
        kill_server $srv
    } else {
        set ::tags [lrange $::tags 0 end-[llength $tags]]
        set _ $srv
    }
    

}

# Return all log lines starting with the first line that contains a warning.
# Generally, this will be an assertion error with a stack trace.
proc warnings_from_file {filename} {
    set lines [split [exec cat $filename] "\n"]
    set matched 0
    set logall 0
    set result {}
    foreach line $lines {
        if {[string match {*REDIS BUG REPORT START*} $line]} {
            set logall 1
        }
        if {[regexp {^\[\d+\]\s+\d+\s+\w+\s+\d{2}:\d{2}:\d{2} \#} $line]} {
            set matched 1
        }
        if {$logall || $matched} {
            lappend result $line
        }
    }
    join $result "\n"
}