# ssh-expect
A library and mini language for scripting ssh

ssh-expect is a scripting solution that automates tedious server jobs.  It is loosely modelled on the TCL expect library.

# Use

ssh-expect automates installs, configures servers and almost anything that can be done in an interactive terminal.

It was originally written to automate a very tedious procedure that required me to log into several relay ssh servers in order to access the actual server I needed to work on.

```racket
    (require "ssh-subprocess.rkt")
    [ssh-script "myAwesomeServerbox" "mybox.coolservers.com" "bob" "sekretpassword"
                            [lambda [] 
                              [send ssh set-echo-to-stdout #t]
                              [wsn user-prompt "ls"]
                              [wsn user-prompt "echo Done"]]]
```

expectssh will connect to "mybox.coolservers.com", log in, wait for the prompt, and run "ls".  It will then wait for the user prompt, and then exit.

Note that this is a standard racket program, so you can run any racket command in the middle of the session.

# Manual intervention

ssh-expect allows you to type commands while your script is running.  So you can use ssh-expect to log into a server and start a mysql session, then take control and type commands directly into mysql.  You can also deal with errors or enter passwords, then allow the script to continue processing.

# Scripting with ssh-expect

The sshscript command can be used to run a ssh script from a file.  Run with 

```bash
    racket sshscript.rkt scriptfile.txt
```

Several example files are included, they all follow the same format:

```racket
    [ssh-script "" "192.168.1.104" "pi" "raspberry" [lambda []
          [send ssh set-echo-to-stdout #t]
          [wsn user-prompt "restart"]
          [waitfor user-prompt]
          [exit 0]]]
```

# Writing you own programs using ssh-expect

# Starting a script

```racket
    [ssh-script "server name" "server address" "login name" "login password" thunk]
```

as in the example, connect to a server and run the script defined in thunk.

```racket
    [ssh-command "server address" "login name" "login password" "command"]
```

logs into a server, runs "command", and returns the transcript of the session.

# Basic commands

The following functions are provided inside the script.  Some patterns are so common, like waitfor->send->send newline, that they have convenient short names.

    [s "y"]

Sends a string to server.

    [sn "ls"]

Sends the string to the server, then a newline.  Common when scripting commands on the command line.

    [waitfor "regex"]

Waits until the server outputs a string that matches "regex".  "regex" is passed straight to regexp-match, so you can use any normal Racket regex.  waitfor is useful when waiting for the command prompt to appear.  Note that waitfor doesn't clear the transcript, so you should clear it yourself.  Otherwise your [waitfor "regex"] might match a previous command in the transcript.  e.g.

```racket
    [waitfor user-prompt]
    [send ssh clear-transcript]
    [sn "ls"]
    [waitfor user-prompt]
```

Because so many scripts use this pattern:

```racket
    [waitfor prompt-regex]
    [send ssh clear-transcript]
    [send "command"]
    [send newline]
```

they are combined into wsn:

```racket
    [wsn "regex" "command"]
```

which waits until it sees "regex", then clears the transcript, sends "command" and then a newline.  wsn will timeout after a default time.  (Set the timeout with [send ssh set-timeout 120]).

```racket
    [waitforsecs "regex" 60]
```

waits for 60 seconds for the regex to appear.

# Advanced commands

```racket
    [ssh-case '[
        [ "regex" "command" ] 
        [ "regex" "command" ] 
        [ "regex" "command" ] 
        [ "regex" "command" ] 
    ]]
```

ssh-case takes a list of pairs, where each pair is a regex, and a command to run if that regex matches.  It is effectively a "case" statement that works on the remote machine.

An example that toggles the snmp demon on a remote server

```racket
    [send ssh clear-transcript]                    ;Make sure there is nothing in the transcript that could accidentally trigger a regex
    [sn "service snmpd status"]                    ;Get the status of the snmpd service
    [ssh-case '[
        ["is running" "service snmpd stop"]         ;If the server prints "is running", we send "service snmpd stop"
        ["is stopped" "service snmpd start"]        ;If the service is not running, start it
        ]
```

Or use options-thunks to handle cases where you need something more complex than just sending a string.
 
 ```racket
    [options-thunks '[[ "regex" [lambda[]] ] [ "regex" [lambda[]] ] ... ] ]
```

option-thunks takes a list of pairs, where each pair is a regex, and a command to run if that regex matches.  The thunk is run in the context of the script, so it has full access to the ssh object and the racket interpreter, so you can print message, pop up a window, or add data to a database.

An example that displays the status of the snmp demon

```racket
    [send ssh clear-transcript]                    ;Make sure there is nothing in the transcript that could accidentally trigger a regex
    [sn "service snmpd status"]                    ;Get the status of the snmpd service
    [options-thunks '[
        ["is running" [thunk [displayln "SNMP is running"]]]
        ["is stopped" [thunk [displayln "SNMP has stopped"]]]
        ]
```

# Convenient variables

There are a few default variables created to help your scripting:

    user-prompt

Made from your login details, looks like "user@server".  In the example above, user-prompt would be "bob@myAwesomeServerbox".  Beware: a lot of shells add colour commands to the prompt.  Check the transcript output to see if you have bursts of characters like '^ESC[m.  These are colour and terminal graphics commands.

    root-prompt

Same, but for the root user.

# The ssh object

The ssh object in the script has many useful methods.  

    [send ssh set-echo-to-stdout #t]

Echoes your session to stdout

    [send ssh get-transcript]

expectssh logs everything that the server sends.  You can get a copy of this with get-transcript

    [send ssh clear-transcript]

Clears the transcript

    [send ssh set-timeout 120]

Sets the default timeout (for the waitfor command)

    [send ssh read-sleep 0.1]

Due to issues with blocking threads, ssh-expect polls its input ports, rather than doing blocking reads.  This delay prevents your program chewing up 100% cpu time while polling an empty port.

# API

You are not required to use the scripting setup described above.  You can directly access the ssh object.

    [let [[ssh [new ssh-wrapper%]]]
                 [send ssh new_session a-server a-user a-password]

Create a new ssh connection to the server.

    [send ssh send-string "ls"]

Send a string to the server.

    [send ssh send-bytes #"ls"]

Send a bytestring

    [send ssh get-transcript]

Get the session's transcript

    [send ssh clear-transcript]

# Troubleshooting

By far the biggest problems are caused by timing.  Either clearing the transcript at the wrong time (and accidentally deleting the prompt you want to wait for), or by accidentally triggering a command too early (the string you want to wait for occurs many times in the transcript, and you didn't realise that).  To get full debugging, call

    [connection-debug #t]
    [send ssh set-echo-to-stdout #t]

This will show you everything sent and received, which should be enough to find your problem.

# Requires

## Racket Scheme

The [Racket Scheme](https://download.racket-lang.org/) programming language.

## The ssh command line program

Ships with linux, and MacOSX.

Windows users can download an equivalent program called [Putty](http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html).  I recommend the msi install package.

# More examples

## Log into a server and check that it can sftp to another server

```racket
#lang racket
[require "ssh-subprocess.rkt"]
[ssh-script "" "gateway.server.com" "username" "nopass"
        [lambda []
          [send ssh set-echo-to-stdout #f]
          [displayln [send ssh get-transcript]]
          [wsn user-prompt "sftp -v -o PreferredAuthentications=password -o PubkeyAuthentication=no remote_username@target.server.com"]
          [wsn "s password:" "remote password"]
          [wsn "sftp>" "ls"]
          [waitfor "sftp>"]
          [displayln [send ssh get-transcript]]
          [exit 0]]]

```

## Run a command 1000 times, collect the output and print it

```racket
#lang racket
[require srfi/1]
[require "ssh-subprocess.rkt"]
[ssh-script "" "remote.server.com" "user name" "nopass"
        [lambda []
          [send ssh set-echo-to-stdout #t]
          [displayln [send ssh get-transcript]]
          [wsn user-prompt "cd program/directory"]
          [map [lambda [n] [wsn user-prompt "./command that must run a lot"]] [iota 1000]]
          [displayln [send ssh get-transcript]]
          [exit 0]]]
```

## Log into a server, start mysql, and check that a certain row has the correct value

```racket
#lang racket

(require "ssh-subprocess.rkt")

[define test-database [lambda [ a-server an-ip a-user a-password ]
                   [ssh-script a-server an-ip a-user a-password
                            [lambda []
                              [send ssh set-echo-to-stdout #t]
                              [wsn user-prompt "mysql <database name>"]
                              [wsn "mysql>" "SELECT data FROM DataTable WHERE key='12345';"]
                              [waitfor "mysql>"]
                              [ssh-case '[
                                [ "data that we are looking for" "echo Found it!"]
                                [".*" "echo default"]]
                              ]
                              [displayln "Fell through options"]
                              [wsn "mysql>" "exit"]
                              [exit 1]
                              [wsn  "echo Done"]]]]]
```

## Log into a server, and sftp a file to another server

```racket
#lang racket
[require srfi/1]
[require "ssh-subprocess.rkt"]
[ssh-script "" "server.com" "username" "nopass"
        [lambda []
          [send ssh set-echo-to-stdout #t]
          [send ssh set-timeout 600]
          [wsn user-prompt "cd /data-directory"]
          [wsn user-prompt "ls"]
          [wsn user-prompt "sudo prepare-data"]
          [wsn user-prompt "sudo sftp  -o PreferredAuthentications=password -o PubkeyAuthentication=no remote_user@remote-server.com"]
          [wsn "assword:" "sekret password"]
          [wsn "sftp>" "mput *data*"]
          [wsn "sftp>" "get processed-file.data"]
          [wsn "sftp>" "ls -l"]
          [wsn "sftp>" "exit"]
          [exit 0]]]
```

# Bugs

There were two versins of this library, one using FFI, and the other simply wrapping an SSH subprocess.  ssh-ffi.rkt, the FFI interface to the SSH library, is currently broken and probably won't be repaired - it was incomplete, crashed often, and needed users to download a hard-to-find library.  It had a difficult API that required work-arounds to avoid blocking the entire racket interpreter.  The ssh subprocess wrapper is much more reliable, comes pre-installed on most systems, and has a simple API.  The instructions in this file are for the ssh wrapper library.

