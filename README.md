# ssh-expect
A library and mini language for scripting ssh

ssh-expect is a scripting solution that automates tedious server jobs

# Use

ssh-expect automates installs, configures servers and almost anything that can be done in an interactive terminal.

    (require "ssh-subprocess.rkt")
    [ssh-script "myAwesomeServerbox" "mybox.coolservers.com" "bob" "sekretpassword"
                            [lambda [] 
                              [send ssh set-echo-to-stdout #t]
                              [wsn user-prompt "ls"]
                              [wsn user-prompt "echo Done"]]]

expectssh will connect to "mybox.coolservers.com", log in, wait for the prompt, and run "ls".  It will then wait for the user prompt, and then exit.

Note that this is a standard racket program, so you can run any racket command in the middle of the session.

# Manual intervention

ssh-expect allows you to type commands while your script is running.  So you can use ssh-expect to log into a server and start a mysql session, then take control and type commands directly into mysql.  You can also deal with errors or enter passwords, then allow the script to continue processing.

# Starting a script

    [ssh-script "server name" "server ip address or full dns name" "login name" "login password" thunk]

as in the example, connect to a server and run the script defined in thunk.

    [ssh-command "server address" "login name" "login password" "command"]

logs into a server, runs "command", and returns the transcript of the session.

# Basic commands

The following functions are provided inside the script.  Some patterns are so common, like waitfor->send->send newline, that they have convenient short names.

    [s "y"]

Sends a string to server.

    [sn "ls"]

Sends the string to the server, then a newline.  Common when scripting commands on the command line.

    [waitfor "regex"]

Waits until the server outputs a string that matches "regex".  "regex" is passed straight to regexp-match, so you can use any normal Racket regex.  waitfor is useful when waiting for the command prompt to appear.  Note that waitfor doesn't clear the transcript, so you should clear it yourself.  Otherwise your [waitfor "regex"] might match a previous command in the transcript.  e.g.

    [waitfor user-prompt]
    [send ssh clear-transcript]
    [sn "ls"]
    [waitfor user-prompt]
    

Because so many scripts use this pattern:

    [waitfor prompt-regex]
    [send ssh clear-transcript]
    [send "command"]
    [send newline]

they are combined into wsn:

    [wsn "regex" "command"]

which waits until it sees "regex", then clears the transcript, sends "command" and then a newline.  wsn will timeout after a default time.  (Set the timeout with [send ssh timeout 120]).

    [waitforsecs "regex" 60]

allows you to choose the timeout.

# Advanced commands

    [options '[["regex" "command"] [ "regex" ... ] ] ]

options takes a list of pairs, where each pair is a regex, and a command to run if that regex matches.  It is effectively a "case" statement that works on the remote machine.

An example that toggles the snmp demon

    [send ssh clear-transcript]                    ;Make sure there is nothing in the transcript that could accidentally trigger a regex
    [sn "service snmpd status"]                    ;Get the status of the snmpd service
    [options '[
        ["is running" "service snmpd stop"]         ;If the server prints "is running", we send "service snmpd stop"
        ["is stopped" "service snmpd start"]        ;If the service is not running, start it
        ]

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

    [send ssh timeout 120]

Sets the default timeout (for the waitfor command)

    [send ssh read-sleep 0.001]

Due to issues with blocking threads, ssh-expect polls its input ports, rather than doing blocking reads.  This delay prevents your program chewing up 100% cpu time while polling an empty port.

# Requires

## Racket Scheme

The [Racket Scheme](https://download.racket-lang.org/) programming language.

## The ssh command line program

Ships with linux  and MacOSX.  

Windows users can download an equivalent program called [Putty](http://www.chiark.greenend.org.uk/~sgtatham/putty/download.html).  I recommend the msi install package.
