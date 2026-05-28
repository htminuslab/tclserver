# -------------------------------------------------------------------------------------------------
#  Generic Tcl CLI server (standalone "wait" variant)
#
#  https://github.com/htminuslab/tcl_cli_server
#
#  Same protocol as tclserver.tcl, but designed to be launched standalone with `tclsh`
#  rather than sourced into a host application. Uses `vwait` to keep the event loop alive
#  and shuts down cleanly when the client sends "exit" or "quit".
#
#  The TCL port is read from the TCL_CLI_PORT environment variable; this must be set
#  before running this script.
# -------------------------------------------------------------------------------------------------
#  Revision History:
#
#  Date:        Revision    Author
#  23 May 2026  0.1         HT-Lab
# -------------------------------------------------------------------------------------------------
set debug 1

proc json_escape {s} {
    return [string map [list \
        \\   \\\\  \
        \"   \\\"  \
        \n   \\n   \
        \r   \\r   \
        \t   \\t   \
        \b   \\b   \
        \f   \\f   \
    ] $s]
}

proc json_ok {result} {
    set escaped [json_escape $result]
    return "{\"status\": \"ok\", \"result\": \"$escaped\"}"
}

proc json_error {msg} {
    set escaped [json_escape $msg]
    return "{\"status\": \"error\", \"message\": \"$escaped\"}"
}

proc handle_client {chan addr port} {
    global debug
    fconfigure $chan -buffering line -translation crlf
    set command [gets $chan]

    if {$debug} {
        puts "DEBUG socket  recv : '$command'"
        puts "DEBUG socket  from : $addr:$port"
    }

    if {$command eq "status"} {
        puts $chan "{\"status\": \"online\"}"
        close $chan
    } elseif {$command eq "exit" || $command eq "quit"} {
        puts $chan "{\"status\": \"ok\", \"result\": \"shutting down\"}"
        close $chan
        if {$debug} { puts "DEBUG socket  shutdown requested by $addr:$port" }
        set ::server_done 1
    } elseif {[catch {eval $command} result]} {
        set response [json_error $result]
        if {$debug} { puts "DEBUG socket  result: ERROR: $result" }
        puts $chan $response
        close $chan
    } else {
        set response [json_ok $result]
        if {$debug} { puts "DEBUG socket  result: '$result'" }
        puts $chan $response
        close $chan
    }
}

if {[info exists env(TCL_CLI_PORT)]} {
    set port $env(TCL_CLI_PORT)
} else {
    puts "ERROR: TCL_CLI_PORT environment variable not set"
    exit 1
}

if {[catch {socket -server handle_client $port} err]} {
    puts "ERROR: Failed to create socket server on port $port: $err"
    exit 1
}
puts "Listening on port $port (send 'exit' or 'quit' to shut down) ..."

# Block in the event loop until a client sends exit/quit, which sets ::server_done.
set ::server_done 0
vwait ::server_done

puts "Server shut down."
