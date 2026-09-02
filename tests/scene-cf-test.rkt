#lang racket/base

;;;
;;; SCENE-CF Structured Formula-Derivation Tests
;;;

;; Tests explicit rewrite-step sequencing, explanatory pre-transition pauses,
;; anchor preservation, and validation. The formulas use ordinary semantic
;; parts, so no TeX process is required for timeline coverage.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(define (part name source position)
  (formula-part name (latex-formula source #:id name #:center position)))

(define (equation left right)
  (formula-assembly
   (list (part 'left left (vec2 -1 0))
         (part 'equals "=" origin)
         (part 'right right (vec2 1 0)))
   #:id 'equation))

(define (formula-part-position scene time name)
  (visual-position
   (formula-part-formula
    (formula-assembly-visual-ref
     (scene-visual-at scene 'equation time)
     name))))

(define (formula-source-position scene time source)
  (define assembly
    (scene-visual-at scene 'equation time))
  (define matching-part
    (for/first ([entry (in-list (formula-assembly-visual-parts assembly))]
                #:when (equal?
                        (formula-visual-source (formula-part-formula entry))
                        source))
      entry))
  (visual-position (formula-part-formula matching-part)))


(module+ test
  (define initial (equation "3x+6" "21"))
  (define subtracted (equation "3x" "21-6"))
  (define evaluated (equation "3x" "15"))

  (define derivation
    (formula-derivation
     (scene-add (make-scene) initial)
     initial
     #:anchor 'equals
     #:explanation-position (vec2 0 -2)
     #:steps
     (list
      (formula-step
       subtracted
       #:matches
       (list (formula-part-match 'left 'left)
             (formula-part-match 'equals 'equals))
       #:duration 1
       #:pause 1/2
       #:explanation "Subtract 6 from both sides")
      (formula-step
       evaluated
       #:duration 3/2
       #:pause 1/4
       #:explanation "Evaluate 21 - 6"))))

  ;; Every step pauses after installing its explanation and before rewriting.
  (check-equal? (scene-duration derivation) 13/4)
  (check-equal?
   (text-visual-content (scene-visual-at derivation 'derivation-note 1/4))
   "Subtract 6 from both sides")
  (check-equal?
   (text-visual-content (scene-visual-at derivation 'derivation-note 7/4))
   "Evaluate 21 - 6")

  ;; Rewrite chaining uses each previous endpoint template but resolves the
  ;; current scene formula, retaining the requested equals anchor throughout.
  (for ([time (in-list '(0 1/2 3/2 7/4 13/4))])
    (check-equal? (formula-part-position derivation time 'equals) origin))
  (check-equal?
   (formula-visual-source
    (formula-part-formula
     (formula-assembly-visual-ref
      (scene-visual-at derivation 'equation 13/4)
      'right)))
   "15")
  (check-equal?
   (text-visual-content
    (scene-visual-at derivation 'derivation-note 13/4))
   "Evaluate 21 - 6")

  ;; SCENE-CL permits several explicitly matched parts to remain exactly at
  ;; their current locations. The shared equals anchor translates the template;
  ;; stationary parts then override their own destination transforms.
  (define repositioned
    (formula-assembly
     (list (part 'left "x" (vec2 -3 0))
           (part 'equals "=" (vec2 1 0))
           (part 'right "5" (vec2 3 0)))
     #:id 'equation))
  (define multi-fixed
    (formula-derivation
     (scene-add (make-scene) initial)
     initial
     #:anchor 'equals
     #:steps
     (list
      (formula-step
       repositioned
       #:matches
       (list (formula-part-match 'left 'left)
             (formula-part-match 'equals 'equals)
             (formula-part-match 'right 'right))
       #:stationary '(left right)
       #:duration 1
       #:pause 0))))
  ;; Interior formula-transition layers have temporary local names, so use
  ;; their formula source to examine the sampled positions directly.
  (check-equal? (formula-source-position multi-fixed 1/2 "=") origin)
  (check-equal? (formula-source-position multi-fixed 1/2 "x") (vec2 -1 0))
  (check-equal? (formula-source-position multi-fixed 1/2 "5") (vec2 1 0))
  (for ([name (in-list '(equals left right))]
        [expected (in-list (list origin (vec2 -1 0) (vec2 1 0)))])
    (check-equal? (formula-part-position multi-fixed 1 name) expected))

  (check-exn
   exn:fail:contract?
   (lambda () (formula-step subtracted #:duration 0)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-derivation
      (scene-add (make-scene) initial)
      initial
      #:anchor 'equals
      #:steps (list (formula-step subtracted #:explanation "Missing placement")))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-derivation
      (make-scene)
      initial
      #:anchor 'equals
      #:steps '()))))
