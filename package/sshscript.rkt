#lang racket
(require racket/file)
(require racket/file)
(require "ssh-subprocess.rkt")

; Options I want
;
; --trace Print each command as it is run
; --debug,d Print all debugging messages
; --verbose,v Print all communications to stdout
; --user,u Supply username to be used to replace USERNAME in script
; --password,p Supply password to replace PASSWORD in script
; --servername,s
; --hostname,h
(define debug-mode (make-parameter #f))
(define verbose-mode (make-parameter #f))



(define file-to-run
  (command-line
   #:program "sshscript"
   #:once-each
   [("-v" "--verbose") "Print all communications"
                       (verbose-mode #t)]
   [("-d" "--debug") "Print all (internal) debugging information"
                       (debug-mode #t)]
   #:args (filename) ; expect one command-line argument: <filename>
   ; return the argument as a filename to compile
   filename))

[define prog [file->value file-to-run]]
(define-namespace-anchor a)
(define ns (namespace-anchor->namespace a))

[eval prog ns]
