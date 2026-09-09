#lang racket/base

;; The left swatch is deliberately branded and literal. The other two are
;; themeable token forms.

(require animate
         animate/colors
         "../private/run-demo.rkt")

(provide make-demo-scene)

(define (sample id x color label)
  (group (list (circle #:id (string->symbol (format "~a-dot" id))
                       #:center (vec2 x 1/2) #:radius 4/5
                       #:fill color #:stroke theme-axis #:stroke-width 2)
               (plain-text label #:id (string->symbol (format "~a-label" id))
                           #:center (vec2 x -4/5) #:font-size 1/5
                           #:color theme-foreground))
         #:id id))

(define (make-demo-scene)
  (define title
    (plain-text "Literals and tokens" #:id 'title #:center (vec2 0 2)
                #:font-size 2/5 #:font-weight 'bold #:color theme-foreground))
  (scene-wait
   (scene-add (make-scene) title
              (sample 'literal -3 pure-blue "literal pure-blue")
              (sample 'palette 0 blue-c "palette blue-c")
              (sample 'role 3 theme-accent "role theme-accent"))
   1))

(module+ main
  (run-demo "colors/literals-and-tokens.rkt" make-demo-scene))
