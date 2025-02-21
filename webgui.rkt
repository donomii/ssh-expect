#lang racket

(require web-server/servlet
         web-server/servlet-env
         web-server/http
         racket/string
         racket/format)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 1) Generic HTML "DSL" with no varargs
;;
;; Each function takes:
;;   - 'attrs': a list of (attrName attrValue) pairs
;;   - 'children': a list of child xexprs or strings
;;
;; The result is a valid xexpr.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (x-tag 'div '((class "something")) (list child1 child2 ...))
;; => '(div ((class "something")) child1 child2 ...)
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
;; 2) Higher-Level Widgets: vbox, hbox, text, button
;;    All take a single list of children, except 'button' 
;;    has a fixed label parameter and a single child of text
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; vbox => <div class="vbox"> ...children... </div>
(define (vbox children)
  (x-div '((class "vbox")) children))

;; hbox => <div class="hbox"> ...children... </div>
(define (hbox children)
  (x-div '((class "hbox")) children))

;; text => <span>some string</span>
;;        Takes a single string and puts it inside <span>
(define (text s)
  (x-span '() (list s)))

;; button => <button class="button" hx-post="..." hx-target="..." hx-swap="...">
;;            label
;;          </button>
;; We have no children list here, just a single label string.
(define (button label hx-post hx-target hx-swap)
  (x-button (list (list 'class "button")
                  (list 'hx-post hx-post)
                  (list 'hx-target hx-target)
                  (list 'hx-swap hx-swap))
            (list label)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 3) Build a Full Page
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (page "Title" body-children)
(define (page title body-children)
  (x-html
   '()
   (list
    (x-head
     '()
     (list
      (x-meta (list (list 'charset "UTF-8")))
      (x-title '() (list title))
      (x-script (list (list 'src "https://unpkg.com/htmx.org@1.9.3")) '())
      (x-style
       '()
       (list
        "body { font-family: sans-serif; margin: 20px; }
         .vbox { display: flex; flex-direction: column; }
         .hbox { display: flex; flex-direction: row; }
         .button { margin: 5px; padding: 5px 10px; }"))))
    (x-body '() body-children))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 4) Example: A Simple "Cluster Manager"
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; A list of servers
(define my-servers '("server-1" "server-2" "server-3"))

;; Build a row for a server: [ "server-X status: Unknown" , [Restart button] ]
(define (server-row s)
  (hbox
   (list
    (text (format "~a status: Unknown" s))
    (button (format "Restart ~a" s)
            (format "/event?server=~a&action=restart" s)
            "this"
            "outerHTML"))))

(define (main-layout)
  ;; A vbox containing a row for each server
  (vbox
   (for/list ([srv my-servers])
     (server-row srv))))

(define (main-page)
  (page "Cluster Manager"
        (list (main-layout))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 5) Web Server: Dispatch
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (not-found)
  (response/xexpr
   (page "404" (list (text "Not Found")))))

(define (handle-event req)
  (define params (request-bindings req))
  (define server (hash-ref params "server" "unknown"))
  (define action (hash-ref params "action" ""))
  ;; Insert real SSH or logging logic here
  (printf "Performing '~a' on ~a\n" action server)
  (response/xexpr
   (x-div '() (list (format "Action '~a' performed on ~a" action server)))))

(define (dispatch req)
  (define path (url->string (request-uri req)))
  (cond
    [(string=? path "/")       (response/xexpr (main-page))]
    [(string-prefix? "/event" path) (handle-event req)]
    [else                      (not-found)]))

(serve/servlet dispatch
               #:servlet-path "/"
               #:port 8080)