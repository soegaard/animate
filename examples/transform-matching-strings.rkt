#lang racket/base

;;;
;;; Source-Aware Formula Rewrite
;;;

;; This demonstration uses conservative `#:source-map 'tokens` atoms, so the
;; two equations do not share any hand-coordinated fragment names. The `=` and
;; `x` are fixed source selections; the changed + becomes - on an explicit
;; curved route; all remaining identical source atoms match automatically.

(require (only-in racket/math pi)
         "../main.rkt"
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define before
    (math-tex
     #:id 'equation
     #:font-size 3/5
     #:source-map 'tokens
     "x + 3 = 7"))
  (define after
    (math-tex
     #:id 'equation
     #:font-size 3/5
     #:source-map 'tokens
     "x = 7 - 3"))
  (define title
    (plain-text
     "SCENE-EK: source-aware formula matching"
     #:id 'title
     #:center (vec2 0 11/5)
     #:font-size 3/10
     #:font-family 'swiss
     #:font-weight 'bold
     #:color "navy"))
  (define explanation
    (plain-text
     "Match TeX source atoms; hold x and = fixed."
     #:id 'explanation
     #:center (vec2 0 6/5)
     #:font-size 1/5
     #:font-family 'swiss
     #:color "darkslategray"))
  (define note
    (plain-text
     "+ follows an explicit lower arc and cross-fades to -."
     #:id 'note
     #:center (vec2 0 -7/5)
     #:font-size 1/5
     #:font-family 'swiss
     #:color "darkslategray"))
  (define initial (scene-add (make-scene) title explanation note before))
  (define held (scene-wait initial 1))
  (define rewritten
    (scene-play
     held
     (rewrite-matching-strings
      before after
      #:anchor "="
      #:stationary (list "x")
      #:key-map
      (list
       (string-match
        "+" "-"
        #:route (formula-arc #:angle (- (/ pi 3)))))
      #:mismatch-mode 'fade-transform)
     #:duration 2))
  (scene-wait rewritten 1))

(module+ main
  (run-demo "transform-matching-strings.rkt" make-demo-scene))
