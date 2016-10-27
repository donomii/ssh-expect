;  ssh module by Jeremy Price
;  Copyright Jeremy Price, 2011
;  Released under the GPL 

[module ssh  racket/gui
  [provide  ssh-wrapper% make-login remove-escapes process-escapes ssh-command ssh-script]
  (require ffi/unsafe
           ffi/unsafe/define)
  (require racket/class)
  (require racket/generator)
  (require mzlib/defmacro)
  [require racket/function]
  (require file/md5)
  ;	(require (planet jaymccarthy/sqlite:5:1/sqlite))
  ;[define db [open [build-path "stuff.sqlite"]]]
  ;[define insert-content [lambda [some-content ]
  ;[let [[insert-data (prepare db "INSERT  INTO data (md5, content) VALUES (?, ?);")]]
  ;[with-handlers [[[const #t][const #t]]][run insert-data [md5 some-content ] some-content]]
  ; (select db "SELECT id from data where md5=?;" [md5 some-content])]]]
  ;
  ;[define insert-check [lambda [timestamp server a-path id ]
  ;[let [[insert-check (prepare db "INSERT  INTO retrievals (timestamp, server, path, data) VALUES (?, ?, ?, ?);")]]
  ;;[with-handlers [[[const #t][const #t]]][run insert-check timestamp server path id]]
  ;  [run insert-check timestamp server a-path id]
  ; ]]]
  ;[define insert-error [lambda [timestamp server user error  ]
  ;[let [[insert-check (prepare db "INSERT  INTO errors (timestamp, server, user, error) VALUES (?, ?, ?, ?);")]]
  ;;[with-handlers [[[const #t][const #t]]][run insert-check timestamp server path id]]
  ;  [run insert-check timestamp server user error]
  ; ]]]
  
  [require srfi/1]                 
  
  
  [define linux #f]
  [define windows #t]
  
  ;
  ;CTRL-C: 3 (ETX)
  ;CTRL-X: 18 (CAN)
  ;CTRL-D: 4 (EOT)
  ;CTRL-K: B (VT)
  ;CTRL-O: F (SI)
  
  ;also:  http://www.cs.tut.fi/~jkorpela/chars/c0.html
  ;[define debug [λ args #t]]
  [define debug [λ args [displayln ""][displayln args]]]
  
  
  (define interfaces (make-hash))
  
  
  
  
  [define-values [stream-in stream-out] [make-pipe]]
  ;[define transcript ""]
  [define escape-list [list ".\\[K" ".\\[..;..m" ".\\[.;..m" ".\\[m.\\]0;" ".\\[.;"   ".\\[..m" ".\\[.m"  ]]
  [define remove-escapes [lambda [a-string] 
                           [fold [lambda [ pattern the-string] [regexp-replace* pattern the-string [format ""]]] a-string escape-list]
                           ]]
  [define process-escapes [lambda [a-string] 
                            [fold [lambda [ pattern the-string] [fold [lambda [pattern1 the-string1] [regexp-replace pattern1 the-string1 ""]] the-string [make-list 100 pattern]]] a-string escape-list]]]
  [define transcript-port ;[open-output-file "transcript.txt" #:exists 'replace]
    (open-output-nowhere)
    ]
  
  
  
  [define printer-thread [thread  [lambda argsk
                                    ;[display "Starting printer"]
                                    [letrec [[myloop [lambda []
                                                       ;[display [read-bytes 1024 stream-in]]
                                                       [sleep 0.01]
                                                       [myloop]]]]
                                      [myloop]
                                      
                                      ]
                                    ;[display "Printer thread shutting down"]
                                    #t
                                    ]]]
  
  
  ;(define g (generator (a-chan a-string)
  ;                     [displayln "Start of generator"]                
  ;                     ;[send ssh send-string "ssh root@server"]
  ;                     [transmit-string a-chan "password" ]
  ;                     
  ;                     
  ;                     [yield]
  ;                     ;[send ssh send-string "password"]
  ;                     [transmit-string a-chan "password" ]
  ;                     
  ;                     
  ;                     ;[send ssh send-string "ls"]
  ;                     [transmit-string a-chan "ls" ]
  ;                     
  ;                     
  ;                     [exit]
  ;                     ))
  
  
  
  [define [transmit-string a-chan line]
    [displayln [format "Sending ~s~n" line]]
    [display line a-chan]]
  
  
  [define [receive-string  a-chan]
    [if [byte-ready? a-chan]
        [letrec [[buff [make-bytes 80 32]]
                 [readbytes [read-bytes-avail! buff a-chan]]]
          [format "~a" [subbytes buff 0 readbytes]]]
        
        #""]]
  
  [define make-transmitter-thread
    [lambda [a-chan] 
      [thread  [lambda args
                 [letrec [[printloop [lambda []
                                       [let [[line [read-line]]]
                                         [transmit-string a-chan [format "~a~a~n"  line #\return]]
                                         [printloop]
                                         ] ]]]
                   [printloop]
                   ]
                 [display "Transmitter thread shutting down"]
                 #t
                 ]]]]
  
  [define make-receiver-thread
    [lambda [a-chan a-callback]
      [thread  [lambda args
                 [debug "Starting receiver"]
                 [letrec [[readloop [lambda []
                                      [let [[stuff [format "~a" [receive-string a-chan]]]]
                                        ;[display stuff stream-out]
                                        ;[set! transcript [string-append transcript stuff]]
                                        [a-callback stuff]
                                        [display stuff transcript-port]
                                        ]
                                      ;[sleep 0.001]  FIXME?
                                      [readloop]]]]
                   [readloop]
                   
                   ]
                 [debug "Receiver thread shutting down"]
                 #t
                 ]]]]
  
  
  
  [define-macro [eval-in-this-context a-form] 
    `[eval-syntax  [datum->syntax [quote-syntax here]  ,a-form]] ]
  
  
  
  [define ssh-wrapper% 
    (class object%
      (init )                ; initialization argument
      
      (field [sess #f] [chan #f] [server-address #f] [user #f] [password #f] [receiver-thread #f] [transmitter-thread #f] [transcript ""] [echo-to-stdout #t][conn-sleep 0.001]
             [timeout 20][procvals #f][writeport #f][readport #f][killfunc #f]) ; field
      [debug "Created ssh object"]
      (super-new)                ; superclass initialization
      [define/public set-echo-to-stdout [lambda [a-boolean] [set! echo-to-stdout a-boolean]]]
      [define/public set-timeout [lambda [a-number] [set! timeout a-number]]]
      [define/public read-sleep [lambda [a-number] [set! conn-sleep a-number]]]
      
      (define/public (new_session a-server-address a-user a-password  )
        ""
        ;[let [[cmd [format "package\\sshbin\\bin\\ssh.exe -o PreferredAuthentications=keyboard-interactive  ~a@~a" a-user a-server-address]]]
        ;[let [[cmd [format "\"c:\\Program Files (x86)\\PuTTY\\plink.exe\"   ~a@~a" a-user a-server-address]]]
        [let [[cmd
               [if [or [equal? [system-type 'os] 'unix] [equal? [system-type 'os] 'macosx]]
                   [format "/usr/bin/ssh -t -t   ~a@~a" a-user a-server-address]
                   [format "\"c:\\Program Files (x86)\\PuTTY\\plink.exe\"   ~a@~a" a-user a-server-address]]]]
          [display cmd][newline]
          [set! procvals [process cmd]]]
        [write  [[fifth procvals] 'status] ][newline]
        [debug "Connecting to remote server"]
        [set! writeport [second procvals]]
        [set! readport [first procvals]]
        [set! killfunc [fifth procvals]]
        (file-stream-buffer-mode readport 'none)
        (file-stream-buffer-mode writeport 'none)
        ;[displayln password writeport]
        [debug "Wrapper setup complete"]
        [set! receiver-thread
              [make-receiver-thread readport
                                    [lambda [a-string] 
                                      [when echo-to-stdout
                                        [begin
                                          ;[when [< 0 [string-length a-string]][display [format "-- ~a --~n" server-address]]]
                                          [display [remove-escapes a-string]]]]
                                      [set! transcript [string-append transcript a-string]]]]]
        [set! receiver-thread
              [make-receiver-thread
               [fourth procvals]
               [lambda [a-string] 
                 ;[when echo-to-stdout [begin [when [< 0 [string-length a-string]][display [format "-- ~a --~n" server-address]]][display [remove-escapes a-string]]]]
                 [set! transcript [string-append transcript a-string]]]]]
        [set! transmitter-thread [make-transmitter-thread writeport]]
        )
      
      [define/public get-transcript [lambda [ ] transcript]]
      [define/public close [lambda []
                             (killfunc 'kill)]]
      [define/public [clear-transcript] [set! transcript ""]#t]
      [define/public send-string
        [lambda [a-string]
          [[thunk
            [when [not writeport]
              [error "You must call new_session first!"]]
            [debug [format "Sending ~s" a-string]]
            [display a-string writeport]]]
          ;[ssh_channel_write chan [format "~n"] [string-length [format "~n"]] ]
          #t]
        ]
      [define/public send-bytes
        [lambda [a-bytes]
          
          [[thunk
            [when [not writeport]
              [error "You must call new_session first!"]]
            [debug [format "Sending ~s" a-bytes]]
            [display a-bytes writeport]]]
          ;[ssh_channel_write chan [format "~n"] [string-length [format "~n"]] ]
          #t 
          ]
        ]
      
      
      )]

  
  
  [displayln "Creating default ssh object"]  
  [define real-ssh [new ssh-wrapper%]]
  
  
  [define [make-login a-server a-user a-password]
    [lambda [] [let [[ssh [new ssh-wrapper%]]]
                 [send ssh new_session a-server a-user a-password] 
                 ssh]]]
  
  [define ssh-command
    [lambda [host user pass command]
      [ssh-script "aaa" host user pass
                  [thunk 
                   [sn command] 
                   [wsn "assword:" pass] 
                   [sleep 15]
                   [send ssh get-transcript]]]]]
  
  ;ssh-script - Opens a ssh connection using the details provided, and binds a number of handy functions for scripting
  ;
  ; [s "a string"]  - sends a string through the connection
  ; [sn "a string"] - sends a string, followed by a newline
  ; [waitforsecs "a regex" a-number] - waits for "a regex", and throws an error after a-number of seconds
  ; [waitfor "a regex"] - waits for "a regex", times out after 10 mins
  ; [wsn "a regex" "a string" ] - clears the buffer, waits for "a regex", then sends "a string" followed by a newline
  ;
  ; variables
  ;
  ; root-prompt - the default unix prompt, "root@a-server"
  ; user-prompt - the default prompt, "a-user@a-server"
  ;
  ; returns the result of your expression
  ;
  ; Example
  ;
  ; [define do-eet [lambda [a-server an-ip a-user a-password ]
  ;                 [ssh-script a-server an-ip a-user a-password 
  ;                          [lambda [] 
  ;                            [send ssh set-echo-to-stdout #t]
  ;                            [wsn user-prompt "ls"]
  ;                            [wsn user-prompt "echo Done"]]]]]
  [defmacro ssh-script [a-server an-ip a-user a-password thunk]
    
    `[letrec [
              
              [ssh [[make-login ,an-ip ,a-user ,a-password]]]
              [clear-transcript [send ssh clear-transcript]]
              [s [lambda [a-string] [send ssh send-string a-string]]]
              [sb [lambda [a-string] [send ssh send-bytes a-string]]]
              [sn [lambda [a-string] [s a-string][s [format "~n"]]]]
              
              [waitforsecs [lambda [a-string a-time]
                             [if [< a-time 0]
                                 [error [format "Timeout waiting for string ~s~n" a-string]]
                                 [begin
                                   [unless [regexp-match a-string [send ssh get-transcript]] 
                                     [begin [sleep [get-field conn-sleep ssh]][waitforsecs a-string [- a-time [get-field conn-sleep ssh]]]]]]]]]
              [waitfor [lambda [a-string][waitforsecs a-string [get-field  timeout  ssh]]]]
              [wsn [lambda [a-string a-nother-string]
                     [if [waitfor a-string]
                         [begin [send ssh clear-transcript][sn a-nother-string]]
                         [error "Waitfor string timed out"]]]]
              [options [lambda [some-opts] [call-with-escape-continuation [lambda [return] 
                                                                            [map [lambda [a-pair]
                                                                                   [when [with-handlers [[[const #t][const #f]]]
                                                                                           [waitforsecs [first a-pair] 1]]
                                                                                     [begin [send ssh clear-transcript][sn [second a-pair]] [return #t]]
                                                                                     ]] some-opts]
                                                                            [sleep [get-field conn-sleep ssh]]
                                                                            [options some-opts]]]]]
              
              [this-server ,a-server]
              [root-prompt [format "root@~a" ,a-server]]
              [user-prompt [format "~a@~a" ,a-user ,a-server]]
              ]
       [let [[result [,thunk] ]]
         
         [send ssh close]
         result]
       
       ]]
  ]