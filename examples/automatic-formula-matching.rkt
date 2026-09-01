#lang racket/base

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (part name source x)
  (latex-formula-part source #:name name #:center (vec2 x 0)
                      #:mode 'inline #:font-size 2/5 #:vertical-alignment 'baseline))

(define (make-demo-scene)
  (define source
    (formula-assembly
     (list (part 'x "x^2" -9/5) (part 'plus-a "+" -9/10)
           (part 'two-x "2x" 0) (part 'plus-b "+" 9/10) (part 'one "1" 9/5))
     #:id 'equation))
  (define destination
    (formula-assembly
     (list (part 'one-renamed "1" -9/5) (part 'plus-left "+" -9/10)
           (part 'two-x-renamed "2x" 0) (part 'plus-right "+" 9/10)
           (part 'x-renamed "x^2" 9/5))
     #:id 'destination))
  (define title
    (plain-text "SCENE-BF: automatic formula matching" #:id 'title
                #:center (vec2 0 3) #:font-size 2/5 #:color "navy"))
  (define start (scene-add (scene-add (make-scene) source) title))
  (scene-wait
   (scene-play start (transform-formula-parts (formula-correspondence-auto source destination))
               #:duration 2)
   1/2))

(module+ main (run-demo "automatic-formula-matching.rkt" make-demo-scene))
