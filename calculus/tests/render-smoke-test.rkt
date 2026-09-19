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
         racket/class
         racket/draw
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

;; render-special-value : calculus-lesson?
;;   Supplies an isolated graph value and the excluded nearby branch endpoint.
(define-calculus-lesson render-special-value
  (model
    [g (piecewise-function (x)
         [(= x 0) 4]
         [else (+ x 1)])]
    [G (graph g)])
  (views
    [plot (graph-view #:x (closed -2 2)
                      #:y (closed 0 5)
                      #:objects (G))])
  (initially (show G))
  (step retain-special-value (show G)))

;; render-trace-square : calculus-lesson?
;;   Draws an authored locus prefix directly from its sweep coordinate.
(define-calculus-lesson render-trace-square
  (model
    [u (parameter 0 #:domain (closed 0 2))]
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x u)]
    [locus (trace-of P #:parameter u #:over (closed 0 2))])
  (views
    [plot (graph-view #:x (closed 0 2)
                      #:y (closed 0 4)
                      #:objects (locus))])
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step trace-locus (trace locus #:duration 2)))

;; render-focus-square : calculus-lesson?
;;   Keeps mathematical coordinates fixed while a graph view changes window.
(define-calculus-lesson render-focus-square
  (model
    [f (function (x) (* x x))]
    [G (graph f)]
    [P (point-on G #:x 3/2)])
  (views
    [plot (graph-view #:x (closed -2 2)
                      #:y (closed -2 2)
                      #:objects (G P))])
  (initially (show G P))
  (timing [opening-pause 0] [read-delay 0] [action-duration 1] [step-pause 0])
  (step focus-plot (focus plot #:x (closed 0 2) #:y (closed 0 4) #:duration 2)))

;; bitmap-rgb : bitmap% exact-nonnegative-integer? exact-nonnegative-integer? -> bytes?
;;   Reads one rendered pixel without depending on an image-file encoder.
(define (bitmap-rgb bitmap x y)
  (define bytes (make-bytes 4))
  (send bitmap get-argb-pixels x y 1 1 bytes)
  (subbytes bytes 1 4))

;; pict->opaque-bitmap : pict? exact-positive-integer? exact-positive-integer? -> bitmap%
;;   Composites a native pict onto an opaque test surface before reading pixels.
(define (pict->opaque-bitmap picture width height)
  (define bitmap (make-bitmap width height))
  (define context (new bitmap-dc% [bitmap bitmap]))
  (send context set-pen (new pen% [color "white"] [style 'transparent]))
  (send context set-brush (new brush% [color "white"] [style 'solid]))
  (send context draw-rectangle 0 0 width height)
  (pict:draw-pict picture context 0 0)
  (send context set-bitmap #f)
  bitmap)


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
  (check-equal? (pict:pict-height scene-picture) 270)
  (define topology-picture
    (prepared-lesson->pict
     (prepare-calculus-lesson render-special-value #:width 480 #:height 270)
     #:at 'final))
  (define topology-bitmap (pict->opaque-bitmap topology-picture 480 270))
  ;; The special branch owns (0,4); the else branch contributes the open
  ;; endpoint (0,1).  The centers verify the semantic markers, not a sampled
  ;; approximation just to one side of x=0.
  (check-not-equal? (bitmap-rgb topology-bitmap 240 73) #"\xFA\xFA\xFA")
  (check-equal? (bitmap-rgb topology-bitmap 240 197) #"\xFA\xFA\xFA")
  (define trace-prepared
    (prepare-calculus-lesson render-trace-square #:width 480 #:height 270))
  (define trace-midpoint-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict trace-prepared #:at 1) 480 270))
  (define trace-final-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict trace-prepared #:at 'final) 480 270))
  ;; The point (3/2,9/4) lies beyond the mid-trace prefix but on the completed
  ;; locus. Its pixel proves native output respects semantic prefix state.
  (check-equal? (bitmap-rgb trace-midpoint-bitmap 344 122) #"\xFA\xFA\xFA")
  (check-not-equal? (bitmap-rgb trace-final-bitmap 344 122) #"\xFA\xFA\xFA")
  (define focus-prepared
    (prepare-calculus-lesson render-focus-square #:width 480 #:height 270))
  (define focus-initial-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict focus-prepared #:at 'initial) 480 270))
  (define focus-final-bitmap
    (pict->opaque-bitmap (prepared-lesson->pict focus-prepared #:at 'final) 480 270))
  ;; P remains the mathematical point (3/2,9/4), while the focused window
  ;; changes its rendered position without mutating the model.
  (check-equal? (bitmap-rgb focus-initial-bitmap 344 122) #"\xFA\xFA\xFA")
  (check-not-equal? (bitmap-rgb focus-final-bitmap 344 122) #"\xFA\xFA\xFA"))

(module+ test
  (run-calculus-render-smoke-tests))
