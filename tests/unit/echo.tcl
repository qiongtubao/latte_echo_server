
tags {"echo"} {
    start_echo_server {tags {"info"}} {
        for {set i 0} {$i < 100} {incr i} {
            assert_equal [e $i] $i
        }
    }
}