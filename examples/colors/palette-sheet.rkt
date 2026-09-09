#lang racket/base

;; Five semantic palette roles and stable categorical indexes, shown without
;; selecting a theme at module initialization.

(require animate
         animate/colors
         "../private/run-demo.rkt")

(provide make-demo-scene)

(define (swatch id center color label)
  (group (list (rectangle #:id (string->symbol (format "~a-box" id))
                          #:center center #:width 9/5 #:height 4/5
                          #:fill color #:stroke theme-axis #:stroke-width 2)
               (plain-text label #:id (string->symbol (format "~a-label" id))
                           #:center (vec2 (vec2-x center) (- (vec2-y center) 7/10))
                           #:font-size 1/5 #:color theme-foreground))
         #:id id))

(define (make-demo-scene)
  (define title
    (plain-text "Animate palette roles and series"
                #:id 'title #:center (vec2 0 13/5) #:font-size 2/5
                #:font-weight 'bold #:color theme-foreground))
  (define swatches
    (list (swatch 'background (vec2 -4 1) theme-background "background")
          (swatch 'surface (vec2 -2 1) theme-surface "surface")
          (swatch 'accent (vec2 0 1) theme-accent "accent")
          (swatch 'highlight (vec2 2 1) theme-highlight "highlight")
          (swatch 'selection (vec2 4 1) theme-selection "selection")
          (swatch 'series-0 (vec2 -3 -1) (series-color 0) "series 0")
          (swatch 'series-1 (vec2 -1 -1) (series-color 1) "series 1")
          (swatch 'series-2 (vec2 1 -1) (series-color 2) "series 2")
          (swatch 'series-3 (vec2 3 -1) (series-color 3) "series 3")))
  (scene-wait (apply scene-add (make-scene) title swatches) 1))

(module+ main
  (run-demo "colors/palette-sheet.rkt" make-demo-scene))
