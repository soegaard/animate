#lang racket/base

;;;
;;; SCENE-EF — Numeric Animation II
;;;

;; The numerical formats and transitions remain ordinary immutable scene data:
;; every assertion below samples directly at its requested absolute time.

(require rackunit
         racket/class
         racket/draw
         "../main.rkt")

(module+ test
  ;; Formatting is deterministic and deliberately renderer-independent.
  (check-equal? (format-scientific 1234.5) "1.23e+3")
  (check-equal? (format-scientific 0 #:significant-figures 4) "0.000e+0")
  (check-equal? (format-scientific (expt 10 400)) "1.00e+400")
  (check-equal? (format-significant 0.001234 #:significant-figures 3)
                "0.00123")
  (check-equal? (format-rational 1/3) "1/3")
  (check-equal? (format-rational -7/3 #:mixed? #t) "-2 1/3")
  (check-equal? (format-complex 3-1/2i #:decimal-places 1) "3.0 - 0.5i")
  (check-equal?
   (format-unit (unit-product (unit "m") (unit "s" #:power -2)))
   "m·s⁻²")

  ;; Complex numbers are interpolable semantic values, including exact
  ;; endpoints and the cartesian midpoint.
  (check-equal? (interpolate-value 1+2i 5+6i 0) 1+2i)
  (check-equal? (interpolate-value 1+2i 5+6i 1/2) 3+4i)
  (check-equal? (interpolate-value 1+2i 5+6i 1) 5+6i)

  (define counter (parameter 'counter 2))
  (define phasor (parameter 'phasor 1+2i))
  (define counter-display
    (parameter-display counter #:id 'counter-display #:center (vec2 -2 0)
                       #:kind 'scientific #:significant-figures 3
                       #:unit (unit "m" #:power 2) #:anchor 'right))
  (define phasor-display
    (parameter-display phasor #:id 'phasor-display #:center (vec2 2 0)
                       #:kind 'complex #:decimal-places 1 #:anchor 'right))
  (define wheels
    (rolling-number-display counter #:id 'wheels #:center (vec2 0 -1)
                            #:integer-digits 2 #:decimal-places 1
                            #:font-size 1/2))
  (define initial
    (scene-add
     (scene-set-value (scene-set-value (make-scene) counter) phasor)
     counter-display phasor-display wheels))

  ;; count-to reads the named clip-start value, while count-from declares both
  ;; endpoints and therefore need not depend on its predecessor.
  (define counted
    (scene-play initial (count-to counter 8) #:duration 1 #:easing linear))
  (check-true (count-to-request? (count-to counter 8)))
  (check-equal? (scene-value-at counted counter 0) 2)
  (check-equal? (scene-value-at counted counter 1/2) 5)
  (check-equal? (scene-value-at counted counter 1) 8)
  (define explicit-count
    (scene-play counted (count-from counter 30 42) #:duration 1 #:easing linear))
  (check-true (count-from-request? (count-from counter 30 42)))
  (check-equal? (scene-value-at explicit-count counter 1) 30)
  (check-equal? (scene-value-at explicit-count counter 3/2) 36)
  (check-equal? (scene-value-at explicit-count counter 2) 42)

  ;; change-number-to supplies the more general finite-complex numeric
  ;; transition; the complex display itself is rederived at every sample.
  (define changing-phasor
    (scene-play initial (change-number-to phasor 5+6i)
                #:duration 1 #:easing linear))
  (check-true (change-number-to-request? (change-number-to phasor 5+6i)))
  (check-equal? (scene-value-at changing-phasor phasor 1/2) 3+4i)
  (check-equal?
   (text-visual-content
    (scene-visual-at changing-phasor 'phasor-display 1/2))
   "3.0 + 4.0i")

  ;; A rolling display is a derived vector group, not a rendered-frame cache.
  ;; It can be sampled and rendered directly at a fractional animation time.
  (check-true (group-visual? (scene-visual-at counted 'wheels 1/2)))
  (check-true (is-a? (scene-frame->bitmap counted 15 #:fps 30) bitmap%))

  ;; Numeric request families own the same scalar component and are rejected
  ;; when scheduled concurrently for one named parameter.
  (check-exn
   exn:fail?
   (lambda ()
     (scene-play initial
                 (animation-group (count-to counter 4)
                                  (change-number-to counter 5))
                 #:duration 1)))
  (check-exn exn:fail:contract?
             (lambda () (count-to counter +nan.0)))
  (check-exn exn:fail:contract?
             (lambda () (change-number-to counter +inf.0))))
