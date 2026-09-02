#lang racket/base

;;;
;;; SCENE-AO Succession Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define dot
    (circle #:id 'dot
            #:radius 1/2
            #:center origin
            #:fill "seagreen"))

  (define other
    (rectangle #:id 'other
               #:width 1
               #:height 1
               #:center (vec2 -4 -2)
               #:fill "slateblue"))

  (define (visual-at scene time id)
    (scene-state-ref (scene-sample scene time) id))

  ;; succession is a first-class Visual/camera composition request. It accepts
  ;; either separate children or one list, and nested successions remain
  ;; compositions.
  (define two-step
    (succession (move-to dot (vec2 2 0))
                (move-to dot (vec2 6 0))))
  (check-true (succession-animation-request? two-step))
  (check-true
   (succession-animation-request?
    (succession
     (list (move-to dot (vec2 1 0))
           (rotate-by dot 1)))))
  (check-true
   (succession-animation-request?
    (succession
     (move-to dot (vec2 1 0))
     (succession (rotate-by dot 1)
                 (scale-by dot 2)))))
  (check-exn exn:fail:contract?
             (lambda () (succession)))
  (check-true
   (succession-animation-request?
    (succession (camera-pan-to (vec2 1 0)))))
  ;; SCENE-AR extends the child grammar with timed leaves/compositions.
  (check-true
   (succession-animation-request?
    (succession
     (timed (move-to dot (vec2 1 0)) #:duration 1))))
  (check-true (timed-animation-request? (timed two-step #:duration 1)))

  ;; Direct children receive equal consecutive shares of the enclosing clip.
  ;; Endpoints are held until the next child starts and the whole composition
  ;; remains one chronological scene clip.
  (define equal-slices
    (scene-play
     (scene-add (make-scene) dot)
     two-step
     #:duration 4))
  (check-equal? (visual-position (visual-at equal-slices 0 'dot))
                origin)
  (check-equal? (visual-position (visual-at equal-slices 1 'dot))
                (vec2 1 0))
  (check-equal? (visual-position (visual-at equal-slices 2 'dot))
                (vec2 2 0))
  (check-equal? (visual-position (visual-at equal-slices 3 'dot))
                (vec2 4 0))
  (check-equal? (visual-position (visual-at equal-slices 4 'dot))
                (vec2 6 0))
  (check-equal? (scene-duration equal-slices) 4)
  (check-equal? (scene-clip-count equal-slices) 1)

  ;; Relative children compile against exact succession boundaries rather than
  ;; the enclosing clip start.
  (define relative-sequence
    (scene-play
     (scene-add (make-scene) dot)
     (succession (rotate-by dot 1)
                 (rotate-by dot 2))
     #:duration 2))
  (check-equal? (visual-rotation (visual-at relative-sequence 1 'dot)) 1)
  (check-equal? (visual-rotation (visual-at relative-sequence 3/2 'dot)) 2)
  (check-equal? (visual-rotation (visual-at relative-sequence 2 'dot)) 3)

  ;; Succession is chronological even when consecutive children target different
  ;; Visuals. A completed child holds while the next child runs.
  (define chronological-targets
    (scene-play
     (scene-add (make-scene) dot other)
     (succession
      (move-to dot (vec2 4 0))
      (move-to other (vec2 4 -2)))
     #:duration 4))
  (check-equal?
   (visual-position (visual-at chronological-targets 1 'dot))
   (vec2 2 0))
  (check-equal?
   (visual-position (visual-at chronological-targets 1 'other))
   (vec2 -4 -2))
  (check-equal?
   (visual-position (visual-at chronological-targets 3 'dot))
   (vec2 4 0))
  (check-equal?
   (visual-position (visual-at chronological-targets 3 'other))
   (vec2 0 -2))

  ;; A nested succession receives one direct-child share, then subdivides that
  ;; share recursively. Here the outer split is 2 + 2 seconds and the nested
  ;; split is 1 + 1 second.
  (define nested-sequence
    (scene-play
     (scene-add (make-scene) dot)
     (succession
      (move-to dot (vec2 4 0))
      (succession (rotate-by dot 2)
                  (scale-by dot 2)))
     #:duration 4))
  (check-equal?
   (visual-position (visual-at nested-sequence 1 'dot))
   (vec2 2 0))
  (check-equal?
   (visual-position (visual-at nested-sequence 2 'dot))
   (vec2 4 0))
  (check-equal?
   (visual-rotation (visual-at nested-sequence 5/2 'dot))
   1)
  (check-equal?
   (visual-rotation (visual-at nested-sequence 3 'dot))
   2)
  (check-equal?
   (visual-scale (visual-at nested-sequence 7/2 'dot))
   (vec2 3/2 3/2))
  (check-equal?
   (visual-scale (visual-at nested-sequence 4 'dot))
   (vec2 2 2))

  ;; The enclosing scene-play easing is applied independently to each leaf's
  ;; local progress, rather than once across the complete sequence.
  (define (square progress)
    (* progress progress))
  (define eased-sequence
    (scene-play
     (scene-add (make-scene) dot)
     (succession (move-to dot (vec2 2 0))
                 (move-to dot (vec2 4 0)))
     #:duration 2
     #:easing square))
  (check-equal?
   (visual-position (visual-at eased-sequence 1/2 'dot))
   (vec2 1/2 0))
  (check-equal?
   (visual-position (visual-at eased-sequence 3/2 'dot))
   (vec2 5/2 0))

  ;; A succession can run beside an ordinary full-clip Visual request. The two
  ;; schedules compose when their active components are disjoint.
  (define parallel-sibling
    (scene-play
     (scene-add (make-scene) dot other)
     (succession (move-to dot (vec2 2 0))
                 (rotate-by dot 2))
     (move-to other (vec2 4 -2))
     #:duration 2))
  (check-equal?
   (visual-position (visual-at parallel-sibling 1/2 'dot))
   (vec2 1 0))
  (check-equal?
   (visual-position (visual-at parallel-sibling 1/2 'other))
   (vec2 -2 -2))
  (check-equal?
   (visual-rotation (visual-at parallel-sibling 3/2 'dot))
   1)
  (check-equal?
   (visual-position (visual-at parallel-sibling 3/2 'other))
   (vec2 2 -2))

  ;; A top-level timed sibling uses its explicit interval beside the succession.
  ;; It remains independent when it targets a different component/identity.
  (define timed-sibling
    (scene-play
     (scene-add (make-scene) dot other)
     (succession (move-to dot (vec2 2 0))
                 (rotate-by dot 2))
     (timed (fade-to other 0) #:start 1/2 #:duration 1)
     #:duration 2))
  (check-equal?
   (visual-opacity (visual-at timed-sibling 1 'other))
   1/2)
  (check-equal?
   (visual-rotation (visual-at timed-sibling 3/2 'dot))
   1)
  (check-equal?
   (visual-opacity (visual-at timed-sibling 3/2 'other))
   0)

  ;; A top-level sibling that overlaps the same component still conflicts with
  ;; the concrete succession leaves produced by expansion.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) dot)
      (succession (move-to dot (vec2 2 0))
                  (move-to dot (vec2 4 0)))
      (move-to dot (vec2 8 0))
      #:duration 2)))

  ;; Structural introduction can be followed immediately by an ordinary
  ;; animation in the next succession slice. The second child sees the exact
  ;; completed Visual produced at the first boundary.
  (define badge
    (rectangle #:id 'badge
               #:width 2
               #:height 1
               #:center (vec2 -3 0)
               #:fill "gold"
               #:opacity 4/5))
  (define introduced-sequence
    (scene-play
     (make-scene)
     (succession (fade-in badge)
                 (move-to 'badge (vec2 3 0)))
     #:duration 2))
  (define introduced-start
    (visual-at introduced-sequence 0 'badge))
  (check-equal? (visual-opacity introduced-start) 0)
  (check-equal? (visual-position introduced-start) (vec2 -3 0))
  (check-equal?
   (visual-opacity (visual-at introduced-sequence 1 'badge))
   4/5)
  (check-equal?
   (visual-position (visual-at introduced-sequence 3/2 'badge))
   origin)
  (check-equal?
   (visual-position (visual-at introduced-sequence 2 'badge))
   (vec2 3 0))

  ;; Removal and same-ID reintroduction at an exact child boundary reuse AN's
  ;; structural ordering: removal finalizes before the next introduction starts.
  (define replacement
    (rectangle #:id 'badge
               #:width 1
               #:height 2
               #:center (vec2 3 1)
               #:fill "tomato"
               #:opacity 3/4))
  (define replacement-sequence
    (scene-play
     (scene-add (make-scene) badge)
     (succession (fade-out badge)
                 (fade-in replacement))
     #:duration 2))
  (check-true (scene-state-has? (scene-sample replacement-sequence 1) 'badge))
  (check-equal?
   (visual-position (visual-at replacement-sequence 1 'badge))
   (vec2 3 1))
  (check-equal?
   (visual-opacity (visual-at replacement-sequence 1 'badge))
   0)
  (check-equal?
   (visual-opacity (visual-at replacement-sequence 2 'badge))
   3/4)

  ;; camera-follow remains a full-clip camera animation but follows the actual
  ;; successive target motion across both child intervals.
  (define follow-camera
    (make-camera #:width 320 #:height 180 #:world-width 12 #:center origin))
  (define follow-sequence
    (scene-play
     (scene-add (make-scene #:camera follow-camera) dot)
     (succession (move-to dot (vec2 2 0))
                 (move-to dot (vec2 4 0)))
     (camera-follow dot)
     #:duration 2))
  (check-equal? (camera-center (scene-camera-at follow-sequence 1/2))
                (vec2 1 0))
  (check-equal? (camera-center (scene-camera-at follow-sequence 3/2))
                (vec2 3 0))
  (check-equal? (camera-center (scene-camera-at follow-sequence 2))
                (vec2 4 0))

  ;; The convenient single-list scene-play form accepts a succession request.
  (define list-form
    (scene-play
     (scene-add (make-scene) dot)
     (list (succession (move-to dot (vec2 1 0))
                       (rotate-by dot 1)))
     #:duration 2))
  (check-equal?
   (visual-position (visual-at list-form 1 'dot))
   (vec2 1 0))
  (check-equal?
   (visual-rotation (visual-at list-form 2 'dot))
   1))
