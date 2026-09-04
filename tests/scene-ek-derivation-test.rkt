#lang racket/base

;;;
;;; SCENE-EK Matching-Strategy Derivation Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; The strategy is one transparent value on the step, rather than a second
  ;; collection of mutually exclusive formula-step keywords.  It may carry its
  ;; own source anchor, so formula-derivation needs no unrelated global anchor.
  (define before
    (math-tex
     #:id 'equation #:font-size 1/2 #:source-map 'tokens
     "x + 3 = 7"))
  (define after
    (math-tex
     #:id 'equation #:font-size 1/2 #:source-map 'tokens
     "x = 7 - 3"))
  (define strategy
    (matching-strings
     #:anchor "="
     #:stationary (list "x")
     #:key-map (list (string-match "+" "-"))
     #:path-arc 1/3
     #:mismatch-mode 'fade-transform))
  (check-true (matching-strings? strategy))
  (define derivation
    (formula-derivation
     (scene-add (make-scene) before)
     before
     #:steps
     (list
      (formula-step
       after
       #:matching strategy
       #:pause 0
       #:duration 1))))
  (check-equal? (scene-duration derivation) 1)
  (check-equal?
   (formula-source (scene-visual-at derivation 'equation 1))
   "x = 7 - 3")

  ;; Named-fragment derivations remain available as an explicit strategy too;
  ;; no global anchor is necessary when a step is a non-anchored transform.
  (define fragment-before
    (formula-assembly
     (list
      (formula-part 'x (latex-formula "x" #:id 'x #:center origin)))
     #:id 'fragment-equation))
  (define fragment-after
    (formula-assembly
     (list
      (formula-part 'x (latex-formula "x" #:id 'x #:center (vec2 1 0))))
     #:id 'fragment-equation))
  (define fragment-derivation
    (formula-derivation
     (scene-add (make-scene) fragment-before)
     fragment-before
     #:steps
     (list
      (formula-step
       fragment-after
       #:matching (matching-fragments)
       #:pause 0))))
  (check-equal? (scene-duration fragment-derivation) 1)

  (check-exn
   exn:fail:contract?
   (lambda ()
     (matching-strings #:on-ambiguity 'guess)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-derivation
      (scene-add (make-scene) fragment-before)
      fragment-before
      #:steps (list (formula-step fragment-after #:pause 0))))))
