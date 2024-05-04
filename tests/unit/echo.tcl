
tags {"echo"} {
    start_echo_server {tags {"info"}} {
        puts "hello"
        for {set i 0} {$i < 100} {incr i} {
            assert_equal [e echo $i] $i
        }
    }
}