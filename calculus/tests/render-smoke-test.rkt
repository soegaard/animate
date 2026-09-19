#lang racket/base

;;;
;;; Calculus Rendering Smoke Tests
;;;

;; Verifies the public rendering adapter consumes the same lesson declaration
;; as headless inspection and produces ordinary Animate and Pict artifacts.


;;;
;;; Imports and Exports
;;;

;; Imports
(require rackunit
         (prefix-in pict: pict)
         (prefix-in native: "../../main.rkt")
         "../render.rkt")

;; Exports
(provide run-calculus-render-smoke-tests)


;;;
;;; Fixture
;;;

;; render-reading-square : calculus-lesson?
;;   A compact graph-reading lesson with a visible graph and moving reading.
(define-calculus-lesson render-reading-square
  (model
    [a (parameter 2 #:domain (closed -2 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [R (input-reading G a)])
  (views
    [plot (graph-view #:x (closed -5/2 5/2)
                      #:y (closed -1/2 5)
                      #:objects (G R))])
  (initially (show G))
  (step show-reading (show R))
  (step scan (vary a #:to -2 #:duration 1)))


;;;
;;; Tests
;;;

;; run-calculus-render-smoke-tests : -> void?
;;   Checks native preparation dimensions and terminal scene/Pict agreement.
(define (run-calculus-render-smoke-tests)
  (define prepared
    (prepare-calculus-lesson render-reading-square #:width 480 #:height 270))
  (check-true (prepared-calculus-lesson? prepared))
  (define picture (prepared-lesson->pict prepared #:at 'final))
  (check-true (pict:pict? picture))
  (check-equal? (pict:pict-width picture) 480)
  (check-equal? (pict:pict-height picture) 270)
  (define scene (prepared-lesson->scene prepared))
  (check-true (native:scene? scene))
  (check-equal? (native:scene-duration scene)
                (calculus-plan-duration (prepared-lesson-plan prepared)))
  (define scene-picture (native:scene->pict scene (native:scene-duration scene)))
  (check-equal? (pict:pict-width scene-picture) 480)
  (check-equal? (pict:pict-height scene-picture) 270))

(module+ test
  (run-calculus-render-smoke-tests))
