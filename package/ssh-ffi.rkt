;  ssh module by Jeremy Price
;  Copyright Jeremy Price, 2011
;  Released under the GPL 

[module ssh  racket/gui
[provide ssh% ssh-multi% make-login remove-escapes process-escapes ssh-command ssh-script]
  (require ffi/unsafe
         ffi/unsafe/define)
(require racket/class)
(require racket/generator)
(require mzlib/defmacro)
[require racket/function]
(require file/md5)


[require srfi/1]                 


[define linux #t]
[define windows #f]



;CTRL-C: 3 (ETX)
;CTRL-X: 18 (CAN)
;CTRL-D: 4 (EOT)
;CTRL-K: B (VT)
;CTRL-O: F (SI)

;also:  http://www.cs.tut.fi/~jkorpela/chars/c0.html
;[define debug [λ args #t]]
[define debug [λ args [displayln args]]]
  
(define _SSH_SESSION-pointer (_cpointer 'SSH_SESSION))
(define _SSH_CHANNEL-pointer (_cpointer 'SSH_CHANNEL))
(define-ffi-definer define-ssh [if windows [ffi-lib "ssh"][ffi-lib "libssh"]])
(define-ssh ssh_init (_fun -> _int))
[define-ssh ssh_new (_fun -> _SSH_SESSION-pointer)]
[define-ssh ssh_channel_new (_fun  _SSH_SESSION-pointer -> _SSH_CHANNEL-pointer)]
[define-ssh ssh_disconnect (_fun _SSH_SESSION-pointer -> _int)]
[define-ssh ssh_free (_fun _SSH_SESSION-pointer -> _void)]
[define-ssh ssh_channel_close (_fun _SSH_CHANNEL-pointer -> _void)]
[define-ssh ssh_connect (_fun _SSH_SESSION-pointer -> _int)]
[define-ssh ssh_get_error (_fun _SSH_SESSION-pointer -> _string)]
[define-ssh ssh_is_server_known (_fun _SSH_SESSION-pointer -> _int)]
[define-ssh ssh_is_connected (_fun _SSH_SESSION-pointer -> _int)]
[define-ssh ssh_userauth_password (_fun _SSH_SESSION-pointer _string _string -> _int)]

[define-ssh ssh_channel_open_session (_fun  _SSH_CHANNEL-pointer -> _int)]
[define-ssh ssh_channel_request_pty (_fun  _SSH_CHANNEL-pointer -> _int)]
[define-ssh ssh_channel_request_shell (_fun  _SSH_CHANNEL-pointer -> _int)]
[define-ssh ssh_channel_change_pty_size (_fun  _SSH_CHANNEL-pointer _int _int -> _int)]
[define-ssh ssh_channel_write (_fun  _SSH_CHANNEL-pointer _string _int -> _int)]
[define-ssh ssh_channel_send_eof (_fun  _SSH_CHANNEL-pointer -> _int)]
[define-ssh ssh_channel_free (_fun  _SSH_CHANNEL-pointer -> _int)]



[define-ssh ssh_channel_request_exec (_fun  _SSH_CHANNEL-pointer _string -> _int)]
[define-ssh ssh_channel_read (_fun  _SSH_CHANNEL-pointer _pointer _int _int -> _int)]
[define-ssh ssh_channel_read_nonblocking (_fun  _SSH_CHANNEL-pointer _pointer _int _int -> _int)]


;[define-ssh ssh_options_set (_fun _SSH_SESSION-pointer _int _void*  -> _int)]
(define-ssh ssh_finalize (_fun -> _int))
(define interfaces (make-hash))

(define (ssh_options_set session opt_index x)
  (define itypes
    [cons _SSH_SESSION-pointer (cons _int
                                     
                                     [cons (cond [(and (integer? x) (exact? x)) _int]
                                                 [(and (number? x) (real? x))   _double*]
                                                 [(string? x)  _string]
                                                 [(bytes? x)   _bytes]
                                                 [(symbol? x)  _symbol]
                                                 [(cpointer? x) _pointer]
                                                 [else (error 'c-printf
                                                              "don't know how to deal with ~e" x)]) '[] ])])
  (let ([printf (hash-ref interfaces itypes
                          (lambda ()
                            ;; Note: throws away the return value of printf
                            (let ([i (get-ffi-obj "ssh_options_set" [if windows [ffi-lib "ssh"][ffi-lib "libssh"]]
                                                  (_cprocedure itypes _int))])
                              (hash-set! interfaces itypes i)
                              i)))])
    (apply printf session opt_index [list x])))


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
  [define connected? ssh_is_connected]
[define when-connected [lambda [a-ssh a-thunk ][if a-ssh 
                     [if [equal? 1 [ssh_is_connected a-ssh]] [a-thunk] #f]
                     #f]]]
  
[define printer-thread [thread  [lambda argsk
                                                        ;[display "Starting printer"]
                                                        [letrec [[myloop [lambda []
                                                                             ;[display [read-bytes 1024 stream-in]]
                                                                           [sleep 1]
                                                                             [myloop]]]]
                                                          [myloop]
                                                          
                                                          ]
                                                        ;[display "Printer thread shutting down"]
                                                        #t
                                                        ]]]


[define [transmit-string a-chan line]
  [debug [format "Sending ~s~n" line]]
  [let
  [[retval [ssh_channel_write a-chan line [string-length line]]]]
    [when [< retval 0 ]
        [begin
          (ssh_channel_close a-chan)
                                     (ssh_channel_free a-chan)
                                     [error "Channel closed"]
                                     ]]
  ;[ssh_channel_write a-chan [format "~n"] [string-length [format "~n"]] ]
  ]]


[define [receive-string  a-chan]
  (let [[SIZE [* 1024 1024]]]
    (define buffer (malloc 'raw SIZE))
    (memset buffer 0 SIZE)
    ;We need to do non-blocking here because for some reason even bytes arriving won't cause the blocking version to return
    [letrec [[bytes-read [ssh_channel_read_nonblocking a-chan buffer [- SIZE 8] 0]]
             [retval (cast buffer _pointer _string/latin-1)]
             
             [return-value [if [< 0 bytes-read] retval ""]]]
      
      ;[display retval]
      ;[append-text retval]
      
      (free buffer)
      [sleep 0]
      [when [< bytes-read 0 ]
        [begin
          (ssh_channel_close a-chan)
                                     (ssh_channel_free a-chan)
                                     [error "Channel closed"]
                                     ]]
      return-value])]

[define make-transmitter-thread [lambda [a-chan] 
                                  [thread  [lambda args
                                                            [letrec [[printloop [lambda []
                                                                                  [let [[line [read-line]]]
                                                                                    [transmit-string a-chan line]
                                                                                    [printloop]
                                                                                    ] ]]]
                                                              [printloop]
                                                              ]
                                                            [display "Transmitter thread shutting down"]
                                                            #t
                                                            ]]]]

[define make-receiver-thread [lambda [a-chan a-callback][thread  [lambda args
                                                        [debug "Starting receiver"]
                                                        [letrec [[readloop [lambda []
                                                                             [let [[stuff [receive-string a-chan]]]
                                                                             [display stuff stream-out]
                                                                               ;[set! transcript [string-append transcript stuff]]
                                                                               [a-callback stuff]
                                                                               [display stuff transcript-port]
                                                                               ]
                                                                             [sleep 1]
                                                                             [readloop]]]]
                                                          [readloop]
                                                          
                                                          ]
                                                        [debug "Receiver thread shutting down"]
                                                        #t
                                                        ]]]]
  [define slave-port-num 3000]
  [define incport [lambda [] [set! slave-port-num [add1 slave-port-num]] slave-port-num]]
(define slave-mode (make-parameter #f))
(define listen-port (make-parameter 1024))
 [define lp #f]
  (command-line
   #:once-each
   [("-s" "--slave") "Start in command slave mode"
                       (slave-mode #t)]
   [("-p" "--port") lp ; flag takes one argument
                          "Listen on <lp> port"
                          (listen-port [string->number lp])]
   
   )
  
  
  [define-macro [eval-in-this-context a-form] 
    `[eval-syntax  [datum->syntax [quote-syntax here]  ,a-form]] ]
  
  [define ssh-multi% 
  (class object%
    (init )                ; initialization argument
    
    (field [sess #f] [chan #f] [server-address #f] [user #f] [password #f] 
           [receiver-thread #f] [transmitter-thread #f] [transcript ""] 
           [echo-to-stdout #f] [real-ssh #f]  ; [real-ssh [new ssh%]]
           [read-port #f] [write-port #f]
           [a-port [incport]]
           [procvals #f]) ; field
  ;  [displayln "Spawning child proc"]
    [let [[cmd [format "\"c:\\Program Files (x86)\\Racket\\Racket.exe\" \"e:\\sshcommander\\ssh.rkt\" --slave --port ~a" a-port]]]
     [display cmd][newline]
    [set! procvals [process cmd]]]
    
    
    [write  [[fifth procvals] 'status] ][newline]
    [displayln "Connecting to child proc"]
    [sleep 15]
    [let-values [[[r w][tcp-connect "localhost" a-port]]]
      (file-stream-buffer-mode r 'none)
      (file-stream-buffer-mode w 'none)
      [set! read-port r]
      [set! write-port w]]
    [displayln "Proxxy ssh setup complete"]
    (super-new)                ; superclass initialization
    [define/public relay [lambda [a-form ]
                           [displayln [format "Relaying ~s" a-form]]
                           [write a-form write-port][flush-output write-port]
                           ;[write '[format "~a" real-ssh] write-port]
                           [newline write-port]
                           ;[sleep 15]
                           ;[displayln "Peeking response"]
                           ;[displayln [peek-string 1000 0 read-port]]
                           [displayln "Reading response"]
                           [let [[result [read read-port]]]
                             [displayln "Read result"]
                             [write result]
                             [newline]
                             result]]]
    [define/public relay-no-wait [lambda [a-form ] 
                           [displayln [format "Relaying ~s" a-form]]
                           [write a-form write-port][flush-output write-port]
                           ;[write '[format "~a" real-ssh] write-port]
                           [newline write-port]
                           ;[sleep 15]
                           ;[displayln "Peeking response"]
                           ;[displayln [peek-string 1000 0 read-port]]
;                           [thread [thunk 
;                                    [displayln "Reading response"]
;                           [let [[result [read read-port]]]
;                             [displayln "Read result"]
;                             [write result]
;                             [newline]
;                             result]]]
                                   ]]
    [define/public set-echo-to-stdout [lambda [a-boolean] [relay '[send real-ssh set-echo-to-stdout ,a-boolean]]]]
    [define ex [lambda [code] [relay `[send real-ssh ex ,code]]]]    
    (define/public (new_session a-server-address a-user a-password  )
      [relay-no-wait `[send real-ssh new_session ,a-server-address ,a-user ,a-password] ])
    [define/public get-transcript [lambda [ ] [relay '[send real-ssh get-transcript]]]]
    [define/public close [lambda [] [relay `[send real-ssh close]]]]
    [define/public [clear-transcript] [relay `[send real-ssh clear-transcript]]]
    [define/public send-string  [lambda [a-string] [relay `[send real-ssh send-string ,a-string]]]]
    [define/public send-bytes  [lambda [a-bytes] [relay `[send real-ssh send-bytes ,a-bytes]]]]
    [define/public run-command [λ [a-string] [relay `[send real-ssh run-command ,a-string]]]]
    )]
  
[define ssh% 
  (class object%
    (init )                ; initialization argument
    
    (field [sess #f] [chan #f] [server-address #f] [user #f] [password #f] [receiver-thread #f] [transmitter-thread #f] [transcript ""] [echo-to-stdout #f] [timeout 120]) ; field
  [debug "Created ssh object"]
    (super-new)                ; superclass initialization
[define/public set-echo-to-stdout [lambda [a-boolean] [set! echo-to-stdout a-boolean]]]
    [define ex [lambda [code] 
             [display [format "Return code: ~a~n" code]]
             [when [not [equal? 0 code]] [error  [format "ssh error: ~a~n"[ssh_get_error sess]]]]]]    
    (define/public (new_session a-server-address a-user a-password  )
      [set! sess [ssh_new]]
      [set! server-address a-server-address]
      [set! user a-user]
      [set! password a-password]
      [debug [format "Setting target to ~s~n" server-address]]
      [display [format "Setting target to ~s~n" server-address]]
      [ex [ssh_options_set sess 0 server-address ]]
      [debug [format "Setting user to ~s~n" user ]]
      [ex [ssh_options_set sess 4 user]]
      (let[[ block (malloc _int 5)]]
(ptr-set! block _int 0 40)
      [ex [ssh_options_set sess 9 block]]
      [debug "Connecting..."][newline]
      [ex [ssh_connect sess]]
      [debug "Is server known? "][newline]
      ;[ex [ssh_is_server_known sess]]
      [debug "userauth password "]
      [ex [ssh_userauth_password sess user password]]
      
      [set! chan [ssh_channel_new sess]]
      [ex [ssh_channel_open_session chan]]
      [ex (ssh_channel_request_pty chan)];
      [ex (ssh_channel_change_pty_size chan 80 24)];
      [ex (ssh_channel_request_shell chan)];
      [set! receiver-thread [make-receiver-thread chan [lambda [a-string] 
                                                         [when echo-to-stdout [begin [when [< 0 [string-length a-string]][display [format "-- ~a --~n" server-address]]][display [remove-escapes a-string]]]]
                                                         [set! transcript [string-append transcript a-string]]]]]
      [set! transmitter-thread [make-transmitter-thread chan]]
        
      ))
    [define/public get-transcript [lambda [ ] transcript]]
    [define/public close [lambda []
                           (ssh_channel_send_eof chan);
                           
                           [kill-thread receiver-thread]
                           [kill-thread transmitter-thread]
                                            
                                     (ssh_channel_close chan);
                                     (ssh_channel_free chan);
                           [when-connected sess [thunk
                                    (ssh_disconnect sess)
                                    (ssh_free sess)]]
                           [set! sess #f]
                           [set! chan #f]
                           #t
  ]]
    [define/public [clear-transcript] [set! transcript ""]#t]
    [define/public send-string  [lambda [a-string]
                                  [when-connected sess
                                                  [thunk
                                  [when [not chan]
                                   [error "You must call new_session first!"]]
                                  [debug [format "Sending ~s~n" a-string]]
                                  [ssh_channel_write chan a-string [string-length a-string]]]]
                                  ;[ssh_channel_write chan [format "~n"] [string-length [format "~n"]] ]
                                  #t]
      ]
    [define/public send-bytes  [lambda [a-bytes]
                                  [when-connected sess
                                                  [thunk
                                  [when [not chan]
                                   [error "You must call new_session first!"]]
                                  [debug [format "Sending ~s~n" a-bytes]]
                                  [ssh_channel_write chan a-bytes [bytes-length a-bytes]]]]
                                  ;[ssh_channel_write chan [format "~n"] [string-length [format "~n"]] ]
                                 #t 
                                 ]
      ]
    
    [define/public run-command [λ [a-string]
                                 [when [not sess]
                                   [error "You must call new_session first!"]]
                                 [when-connected sess
                                                 [thunk 
                                                  [let [[chan [ssh_channel_new sess]]]
                                   
                                   [ssh_channel_open_session chan]
                                   [ssh_channel_request_exec chan a-string]
                                   (letrec [[SIZE 40096]
                                            (buffer (malloc 'raw SIZE))]
                                     (memset buffer 0 SIZE)
                                     [sleep 15]
                                     [ssh_channel_read_nonblocking chan buffer [- SIZE 8] 0]
                                     [define retval (cast buffer _pointer _string)]
                                     
                                     ;[append-text retval]
                                     (free buffer)
                                     [display retval]
                                     
                                     (ssh_channel_send_eof chan);
                                     (ssh_channel_close chan);
                                     (ssh_channel_free chan);
                                     retval
                                     
                                     )]]]]]
    )]

[displayln "Creating default ssh object"]  
  [define real-ssh [new ssh%]]
[when [slave-mode]
  [displayln "Starting slave mode"]
    [letrec [[logport (open-output-nowhere)] ;[open-output-file "log.txt" #:exists 'append ]]
             [listener (tcp-listen	 	(listen-port)	 	 	 	 
 	 	1	 	 	 	 
 	 	#t	 	 	 	 
 	 	#f)]
             [read-port #f]
             [write-port #f]
          ]
      [displayln "Slave mode active" logport]
      (displayln [format "Started, listening on ~a" [listen-port]] logport)
      ;(send real-ssh new_session "146.11.57.236" "root" "rootpw")
      ;[sleep 600]
    [let-values [[[r w ] (tcp-accept listener)]]
      [displayln "Accepted connection!" logport]
      [displayln "Accepted connection!"]
      (file-stream-buffer-mode r 'none)
      (file-stream-buffer-mode w 'none)
      [set! read-port r]
      [set! write-port w]
      [letrec [[io-loop [lambda []
                       [let [[a-form [read read-port]]]
                       [newline]
                         
                         [if [eof-object? a-form]
                             [exit]
                         [let [[result [with-handlers [[[const #t][lambda args [list "Eval failed" [format "~s" args]]]]]
                                         [display "Evalling " logport][write a-form logport][newline logport]
                         [display "Evalling " ][write a-form ][newline ]
                  [eval-in-this-context a-form]
                                         ;[map [lambda [a][write "boo"  write-port][newline write-port]] [iota 15]]
                                         
                   ;[eval a-form]                      
                                         ]]]
                           [write [list [format " \"~a\" " result]] logport][newline logport]
                           [when [not [void? result]][write result  write-port][newline write-port]]
                           [flush-output write-port]
                           [write [list result]]
                           [flush-output logport]
                           ]]        
                       ]
                       [io-loop]]]]
        
       [with-handlers  [[[const #t][lambda args args]]]
        [io-loop]]]]]
  [exit]
    ]

[define [make-login a-server a-user a-password]
  [lambda [] [let [[ssh [new ssh%]]]
               [send ssh new_session a-server a-user a-password] ssh]]]
  
[define ssh-command [lambda [host user pass command]
                     [let [[ssh [new ssh%]]]
                       [send ssh new_session host user pass]
                       ;[display command]
                     [send ssh run-command  command ]
                       [send ssh get-transcript]]]]
  
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
  ; [define do-eet [lambda [a-db a-server an-ip a-user a-password ]
  ;                 [ssh-script a-db a-server an-ip a-user a-password 
  ;                          [lambda [] 
  ;                            [send ssh set-echo-to-stdout #t]
  ;                            [wsn user-prompt "ls"]
  ;                            [wsn user-prompt "echo Done"]]]]]
  [defmacro ssh-script [a-db a-server an-ip a-user a-password thunk]
    
    `[letrec [
              
              [ssh [[make-login ,an-ip ,a-user ,a-password]]]
              [clear-transcript [send ssh clear-transcript]]
              [s [lambda [a-string] [send ssh send-string a-string]]]
              [sb [lambda [a-string] [send ssh send-bytes a-string]]]
              [sn [lambda [a-string] [s a-string][s [format "~n"]]]]
              
              [waitforsecs [lambda [a-string a-time][if [< a-time 0]
                                                        [error [format "Timeout waiting for string ~s~n" a-string]]
                                                        [begin
                                                          [unless [regexp-match a-string [send ssh get-transcript]] 
                                                            [begin [sleep 0.5][waitforsecs a-string [- a-time 0.5]]]]]]]]
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
                                                                 [sleep 1]
                                                                            [options some-opts]]]]]
              
              [this-server ,a-server]
              [root-prompt [format "root@~a" ,a-server]]
              [tron [send ssh set-echo-to-stdout #t]]
              [troff [send ssh set-echo-to-stdout #f]]
              [user-prompt [format "~a@~a" ,a-user ,a-server]]
              
              [a-db ,a-db]
              ]
       [let [[result [,thunk] ]]
         
         [send ssh close]
         result]
       
       ]]
  ]
