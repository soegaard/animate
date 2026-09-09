#lang racket/base

;;;
;;; Themed Paint Interpolation Tests
;;;

(require rackunit
         "../colors.rkt"
         "../private/geometry.rkt"
         "../private/paint.rkt")

(module+ test
  (define alternate-palette
    (color-palette #:id 'alternate
                   #:extends animate-palette
                   #:colors (hash 'aqua-c "#ff8800"
                                  'red-c "#0088ff")))
  (define alternate-theme
    (color-theme #:id 'alternate
                 #:extends animate-light-theme
                 #:palette alternate-palette))

  (define midpoint (paint-lerp aqua-c red-c 1/2))
  (check-true (color-expression? midpoint))
  (check-not-equal? (resolve-color midpoint animate-light-theme)
                    (resolve-color midpoint alternate-theme))

  (define first-gradient
    (linear-gradient (vec2 0 0) (vec2 1 0)
                     (list (paint-stop 0 aqua-c) (paint-stop 1 red-c))))
  (define second-gradient
    (linear-gradient (vec2 0 0) (vec2 1 0)
                     (list (paint-stop 0 pure-red) (paint-stop 1 pure-blue))))
  (define middle-gradient (paint-lerp first-gradient second-gradient 1/2))
  (check-true
   (color-expression?
    (paint-stop-color (vector-ref (list->vector (linear-gradient-paint-stops middle-gradient)) 0))))

  (define first-checker (checker-pattern aqua-c red-c #:cell-size 1))
  (define second-checker (checker-pattern pure-red pure-blue #:cell-size 2))
  (define middle-checker (paint-lerp first-checker second-checker 1/2))
  (check-true (color-expression? (checker-pattern-paint-first middle-checker)))
  (check-equal? (checker-pattern-paint-cell-size middle-checker) 3/2)

  ;; A bad token can travel through a paint expression but fails only at the
  ;; explicit theme-resolution boundary, with the palette diagnostic.
  (define unresolved (paint-lerp (palette-color 'custom-missing) aqua-c 1/2))
  (check-exn #px"palette containing the requested key"
             (lambda () (resolve-color unresolved animate-light-theme))))
