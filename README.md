# ssh-expect
A library and convenient mini language for scripting ssh

ssh-expect is a scripting solution that automates boring server jobs

# Use

expectssh can be used to auto   mate installs, configure servers and almost anything that can be done in an interactive terminal.

    (require "ssh-subprocess.rkt")
    [ssh-script "myAwesomeServerbox" "mybox.coolservers.com" "bob" "sekretpassword"
                            [lambda [] 
                              [send ssh set-echo-to-stdout #t]
                              [wsn user-prompt "ls"]
                              [wsn user-prompt "echo Done"]]]

expectssh will connect to "mybox.coolservers.com", log in, wait for the prompt, and run "ls".  It will then wait for the user prompt, and then exit.

Note that this is a standard racket program, so you can run any racket command in the middle of the session.  This is very handy when you want to e.g. check that a file exists, and create it if it doesn't.

# Manual intervention

expectssh monitors STDIN, so you can type into STDIN while expectssh is running any script, and your keystrokes will be sent to the server.  This is incredibly useful during a long script, when there is an unexpected prompt on the server that stops your script e.g. "Continue(y/n)".  You can press "y" and the script will continue.

You can also use expectssh to log into a server and start a mysql session, then take control and type commands directly into mysql.

# Starting a script

    [ssh-script "server name" "server ip address or full dns name" "login name" "login password" thunk]

as in the example, connect to a server and run the script defined in thunk.

    [ssh-command "server address" "login name" "login password" "command"]

logs into a server, runs "command", and returns the transcript of the session.

# Basic commands

The following functions are provided inside the script.  Some patterns are some common, like waitfor, send, send newline, that they have convenient short names.

    [s "y"]

Sends a string to server.

    [sn "ls"]

Sends the string to the server, then a newline.  Common when scripting commands on the command line.

    [waitfor "regex"]

Waits until the server outputs a string that matches "regex".  "regex" is passed straight to regexp-match, so you can use any normal Racket regex.  waitfor is often used for waiting for the command prompt to appear.

Because so many scripts use this pattern:

    [waitfor prompt-regex]
    [send "command"]
    [send newline]

they are combined into wsn:

    [wsn "regex" "command"]

which waits until it sees "regex", then sends "command" and then a newline.  wsn will timeout after a default time.

    [waitforsecs "regex" 60]

allows you to choose the timeout.

# Convenient variables

There are a few default variables created to help your scripting:

    user-prompt

Made from your login details, looks like "user@server".  In the example, it would be "bob@myAwesomeServerbox".  Note that because a lot of shells add colour commands to the prompt, this might not actually match your prompt.  Check the transcript output to see if you have bursts of characters like '[^ESC['.  These are colour and terminal graphics commands.

    root-prompt

Same, but for the root user.

# The ssh object

The ssh object in the script has many useful methods.  

    [send ssh set-echo-to-stdout #t]

Echoes your session to stdout

    [send ssh get-transcript]

expectssh keeps a log of everything the server sends.  You can extract the results of commands from this


FIXME: Document options command
