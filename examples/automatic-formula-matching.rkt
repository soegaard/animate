#lang racket/base

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (part name source x)
  (latex-formula-part source #:name name #:center (vec2 x 0)
                      #:mode 'inline #:font-size 2/5 #:vertical-alignment 'baseline))

(define (assembly id parts)
  (formula-assembly parts #:id id))

(define (make-demo-scene)
  (define source
    (assembly
     'equation
     (list (part 'x "x^2" -9/5) (part 'plus-a "+" -9/10)
           (part 'two-x "2x" 0) (part 'plus-b "+" 9/10) (part 'one "1" 9/5))))
  (define reordered
    (assembly
     'equation
     (list (part 'one-renamed "1" -9/5) (part 'plus-left "+" -9/10)
           (part 'two-x-renamed "2x" 0) (part 'plus-right "+" 9/10)
           (part 'x-renamed "x^2" 9/5))))
  (define named
    (assembly
     'equation
     (list (part 'f "f(x)" -43/20) (part 'equals "=" -5/4)
           (part 'one-named "1" -9/20) (part 'plus-named-left "+" 1/10)
           (part 'two-x-named "2x" 3/4) (part 'plus-named-right "+" 7/5)
           (part 'x-named "x^2" 43/20))))
  (define renamed
    (assembly
     'equation
     (list (part 'g "g(x)" -43/20) (part 'equals-renamed "=" -5/4)
           (part 'x-restored "x^2" -9/20) (part 'plus-restored-left "+" 1/10)
           (part 'two-x-restored "2x" 3/4) (part 'plus-restored-right "+" 7/5)
           (part 'one-restored "1" 43/20))))
  (define title
    (plain-text "SCENE-BF: automatic formula matching" #:id 'title
                #:center (vec2 0 3) #:font-size 2/5 #:color "navy"))
  (define start (scene-add (scene-add (make-scene) source) title))
  (define first-pause (scene-wait start 1))
  (define after-reordering
    (scene-play first-pause
                (transform-formula-parts (formula-correspondence-auto source reordered))
                #:duration 2))
  (define second-pause (scene-wait after-reordering 1))
  (define after-naming
    (scene-play second-pause
                (transform-formula-parts (formula-correspondence-auto reordered named))
                #:duration 2))
  (define third-pause (scene-wait after-naming 1))
  (define after-renaming
    (scene-play third-pause
                (transform-formula-parts (formula-correspondence-auto named renamed))
                #:duration 2))
  (scene-wait after-renaming 1))

(module+ main (run-demo "automatic-formula-matching.rkt" make-demo-scene))
