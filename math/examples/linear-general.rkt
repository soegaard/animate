#lang racket/base

;;;
;;; Linear General Lesson
;;;
;; Defines the held problem, explicit derivation, and presentation. Requiring this
;; module does not render frames or execute TeX.

;;;
;;; Imports and Exports
;;;
;; Imports
(require "../main.rkt" "../render.rkt")

;; Exports
(provide problem solution plan make-demo-scene)

;;;
;;; Construction and Operations
;;;
; problem : math?
;;   Gives the held original problem and its declared real-scalar context.
(define problem
  (math '(= (+ (* a x) b) c)
    #:id 'linear-general
    #:context (math-context #:real '(a b c x))))

; solution : (or/c derivation? case-derivation?)
;;   Gives the explicit worked derivation, including parameter branches where needed.
(define solution
  (derive-cases problem
    [ordinary
     '(not (= a 0))
     [subtract-b (both-sides 'subtract 'b)]
     [cancel-b (cancel-addends #:at (lhs))]
     [divide-a (both-sides 'divide 'a)]
     [reduce-a (cancel-factor #:at (lhs) #:factor 'a #:keep-one? #t)]
     [remove-one (remove-unit #:at (lhs))]]
    [identity
     '(and (= a 0) (= b c))
     [specialize-a (substitute '((a . 0)))]
     [reduce (reduce-identities)]
     [all-values (conclude 'all-real #:for 'x)]]
    [inconsistent
     '(and (= a 0) (not (= b c)))
     [specialize-a (substitute '((a . 0)))]
     [reduce (reduce-identities)]
     [no-values (conclude 'no-solutions #:for 'x)]]))

; plan : presentation-plan?
;;   Gives the deterministic classroom presentation for the worked solution.
(define plan
  (present solution
    #:groups
    (hash '(ordinary)
      '((subtract-b cancel-b) (divide-a reduce-a remove-one))
      '(identity)
      '((specialize-a reduce all-values))
      '(inconsistent)
      '((specialize-a reduce no-values)))))

; make-demo-scene : -> scene?
;;   Prepares this lesson and constructs its native scene when explicitly called.
(define (make-demo-scene)
  (math-plan->scene! plan #:title "The general linear equation"))

(module+ main (require "private/run.rkt") (run-math-example! plan "linear-general"))
