#lang racket/base

;;;
;;; Source-Matched Equation Reduction
;;;

;; Formula steps describe *how* their source-mapped TeX atoms transition.  The
;; derivation itself only sequences the author-supplied algebra and explanations.

(require (only-in racket/math pi)
         "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (equation source)
  (math-tex #:id 'equation #:font-size 3/5 #:source-map 'tokens source))

(define (make-demo-scene)
  (define initial (equation "2x + 6 = 16"))
  (define subtract-six (equation "2x = 16 - 6"))
  (define evaluate (equation "2x = 10"))
  (define divide (equation "x = 5"))
  (define title
    (plain-text
     "SCENE-EK: source-matched formula derivation"
     #:id 'title #:center (vec2 0 11/5)
     #:font-size 3/10 #:font-family 'swiss #:font-weight 'bold #:color "navy"))
  (define instructions
    (plain-text
     "Each step selects its own source-aware matching strategy."
     #:id 'instructions #:center (vec2 0 6/5)
     #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define derivation
    (formula-derivation
     (scene-add (make-scene) title instructions initial)
     initial
     #:explanation-position (vec2 0 -7/5)
     #:steps
     (list
    (formula-step
     subtract-six
     #:matching
     (matching-strings
      #:anchor "="
      ;; Token mode maps `2` and `x` as separate TeX atoms, so keep both
      ;; selections explicit rather than assuming a semantic `2x` product.
      #:stationary (list "2" "x")
      #:key-map
      (list
       (string-match
        "+" "-"
        #:route (formula-arc #:angle (- (/ pi 3)))))
      #:mismatch-mode 'fade-transform)
     #:pause 1
     #:duration 3/2
     #:explanation "Subtract 6 from both sides")
    (formula-step
     evaluate
     #:matching
     (matching-strings #:anchor "=" #:stationary (list "2" "x"))
     #:pause 1
     #:duration 1
     #:explanation "Evaluate 16 - 6")
    (formula-step
     divide
     #:matching (matching-strings #:anchor "=")
     #:pause 1
      #:duration 3/2
      #:explanation "Divide both sides by 2"))))
  ;; Hold the exact endpoint: a fixed-FPS export samples frame starts, so a
  ;; clip ending on the final transition would otherwise have no fully settled
  ;; output frame.
  (scene-wait derivation 1))

(module+ main
  (run-demo "string-matched-derivation.rkt" make-demo-scene))
