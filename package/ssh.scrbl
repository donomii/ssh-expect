#lang scribble/manual
@(require (for-label "ssh.rkt"))
@defmodule[my-lib/helper]
@title{libSSH Binding}
 
Bindings to the ssh library (http://www.libssh.org/)

@table-of-contents[]

@section{Abstract}

An Object-Oriented interface to the libSSH library.  

@section{Description}

LibSSH is a client library for the ssh protocol that supports SSHv1 and SSHv2.  
It provides synchronous and asynchronous connections, multiple channels and lots of convenience
functions.  This Racket binding provides an OO interface to the libSSH library, exposing a small subset 
of the full libSSH functionality.



In addition, several macros are provided to make communicating with a server more convenient.

Multiple SSH connections, both to the same server and different servers, are supported.

@section{Use}

@subsection{Example}

@racketblock[[let [[ssh [new ssh%]]]
               [send ssh new_session a-server a-user a-password] ssh ]]

@subsection{%ssh}

@defthing[%ssh ]{
  The ssh wrapper object
}

@subsection{new_session}
@racket[[send ssh new_session a-server a-user a-password]]

Opens a new connection to a server

@defthing[a-server]{Name or IP address of a server}
@defthing[a-user]{Username}
@defthing[a-password]{Password}

@section{Known Issues}

Async communication is supported, however I have not been able to get the async socket open to work, so the entire program will
block while connecting to a server.

Only one channel per ssh connection is currently supported.

Key files, known hosts files and etc are not currently supported, and the libSSH library is instructed to skip past these steps.
So this binding does not currently support the important features of ssh!

@section{Author}

Jeremy Price

@section{License}

GPL