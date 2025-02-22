#lang racket

(require "package/ssh-subprocess.rkt"              ; <-- your SSH library
         web-server/servlet
         web-server/servlet-env
         web-server/http
         racket/string
         racket/format)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 1) Minimal HTML DSL (no varargs), same idea as before
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (x-tag tag-symbol attrs children)
  (append (list tag-symbol attrs) children))

(define (x-html attrs children)
  (x-tag 'html attrs children))

(define (x-head attrs children)
  (x-tag 'head attrs children))

(define (x-body attrs children)
  (x-tag 'body attrs children))

(define (x-div attrs children)
  (x-tag 'div attrs children))

(define (x-span attrs children)
  (x-tag 'span attrs children))

(define (x-button attrs children)
  (x-tag 'button attrs children))

(define (x-meta attrs)
  (x-tag 'meta attrs '()))

(define (x-title attrs children)
  (x-tag 'title attrs children))

(define (x-script attrs children)
  (x-tag 'script attrs children))

(define (x-style attrs children)
  (x-tag 'style attrs children))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 2) Higher-level Widgets: vbox, hbox, text, button
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (vbox children)
  (x-div '((class "vbox")) children))

(define (hbox children)
  (x-div '((class "hbox")) children))

(define (text str)
  (x-span '() (list str)))

(define (button label hx-post hx-target hx-swap)
  (x-button
   (list (list 'class "button")
         (list 'hx-post hx-post)
         (list 'hx-target hx-target)
         (list 'hx-swap hx-swap))
   (list label)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 3) Page Builder
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (page title body-children)
  (x-html
   '()
   (list
    (x-head
     '()
     (list
      (x-meta '((charset "UTF-8")))
      (x-title '() (list title))
      (x-script (list (list 'src "https://unpkg.com/htmx.org@1.9.3")) '())
      (x-style
       '()
       (list
        "body { font-family: sans-serif; margin: 20px; }
         .vbox { display: flex; flex-direction: column; }
         .hbox { display: flex; flex-direction: row; align-items: center; }
         .button { margin: 5px; padding: 5px 10px; }
         .status-light {
           width: 12px; height: 12px;
           border-radius: 6px;
           margin: 0 6px;
           display: inline-block;
         }
         .running { background-color: #4caf50; }
         .stopped { background-color: #f44336; }
         .unknown { background-color: #999999; }
         "))))
    (x-body '() body-children))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 4) Integrating the SSH module for status
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; EXAMPLE: We'll define a function that logs into a server,
;; runs `systemctl is-active <some-service>`, and returns "running", "stopped", or "unknown".
;; Modify as needed for your actual service check.

(define (check-systemd-service-status service server user pass)
  (define result
    (ssh-script
      "dummy-server-name"   ;; [a-server], just a label, not always used
      server
      user
      pass
      (thunk
        ;; Send a quick command to check service:
        (sn (format "systemctl is-active ~a" service))
        ;; Wait for either "active" or "inactive" in transcript:
        (waitfor #px"(active|inactive)")
        (define out (send ssh get-transcript))
        (send ssh close)
        out)))
  ;; Now `result` is the transcript from that SSH command.
  (cond
    [(regexp-match? #px"active" result)  "running"]
    [(regexp-match? #px"inactive" result) "stopped"]
    [else "unknown"]))

(define (check-ps-service-status server-name service-name server user pass)
  "Check if SERVICE-NAME appears in 'ps' on SERVER. Returns 'running' or 'stopped' or 'unknown'."
  (define result
    (ssh-script
      server-name  ;; A label used by ssh-script
      server
      user
      pass
      (thunk
       (displayln (format "connected to docker"))
       (wsn "/ #" "apk update")
       (wsn "/ #"  "apk add openssh-client sshpass")
       (wsn "/ #"  [format "ssh -o StrictHostKeyChecking=no %s@%s" user server])
       (wsn "assword" pass)
       (display (format "looged in to ~a" server))
        ;; Command: if 'grep' finds the service, we see the 'ps' line; 
        ;; otherwise we echo NOTFOUND.
        (sn (format "ps ax | grep -v grep | grep ~a" service-name))
        (clear-transcript)
        ;; Now wait until we see either "NOTFOUND" or some digits (PID in 'ps' output).
        (waitfor user-prompt)
        
        (define out (send ssh get-transcript))
        (send ssh close)
        out)))
  
  (cond
    ;; If transcript has "NOTFOUND", the process wasn't found
    [(regexp-match? #px"NOTFOUND" result)
     "stopped"]
    ;; If we see some digits (PID) in the transcript, assume running
    [(regexp-match? #px"[0-9]+" result)
     "running"]
    [else
     "unknown"]))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 5) Building the UI
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Some servers to manage
(define my-servers '(
                     ;("192.168.11.25" "user" "aaaaaa" "tower")
  ("192.168.11.22" "void" "void" "void")))

;; Build a row that includes:
;;  - The server name
;;  - A small color indicator (based on actual SSH check)
;;  - A "Restart" button
;;
;; We'll do a synchronous check at page load. This is a simple approach
;; but blocks the server while checking. For a non-blocking approach,
;; you might move the check to an HTMX call or a background thread.
(define (server-row s)
  (define status (check-ps-service-status (fourth s) "vort" (first s) (second s) (third s)))  ; <-- Adjust user/pass as needed
  (hbox
   (list
    (text (format "~a status:" s))
    (x-span
     (list (list 'class (format "status-light ~a" status)))
     '())   ; no children
    (text (string-upcase status))
    (button
     (format "Restart ~a" s)
     (format "/event?server=~a&action=restart" s)
     "this"
     "outerHTML"))))



;; The main layout is a vbox of all the server rows
(define (main-layout)
  (vbox
   (for/list ([srv my-servers])
     (server-row srv))))

(define (main-page)
  (page "Cluster Manager"
        (list (main-layout))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 6) Web Server: Dispatch
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (not-found)
  (response/xexpr
   (page "404" (list (text "Not Found")))))

(define (handle-event req)
  (define params (request-bindings req))
  (define server (hash-ref params "server" "unknown"))
  (define action (hash-ref params "action" ""))
  ;; Insert real SSH logic or logging here:
  (printf "Performing '~a' on ~a\n" action server)
  ;; Just show a snippet:
  (response/xexpr
   (x-div '() (list (format "Action '~a' performed on ~a" action server)))))

(define (dispatch req)
  (define path (url->string (request-uri req)))
  (cond
    [(string=? path "/")          (response/xexpr (main-page))]
    [(string-prefix? "/event" path) (handle-event req)]
    [else                         (not-found)]))

(serve/servlet dispatch
               #:servlet-path "/"
               #:port 8080)