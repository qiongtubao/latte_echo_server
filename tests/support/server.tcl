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

# doesn't really belong here, but highly coupled to code in start_server
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