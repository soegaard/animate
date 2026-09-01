#lang racket/base

;;;
;;; SCENE-AA Joined Offset Path Model Tests
;;;

;; Tests continuous line-path offsets, inside/outside corner semantics,
;; miter limits, bevel and round joins, closed paths, validation, and direct
;; reuse of generated offset geometry by path-following animation.
;;
;; This module intentionally imports no Pict, bitmap, filesystem, or process
;; adapter.


;;;
;;; Imports
;;;

(require (only-in racket/math pi)
         rackunit
         "../private/animation.rkt"
         "../private/geometry.rkt"
         "../private/path-geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")


(module+ test
  ; outside-elbow : path-geometry?
  ;;   Turns right, so a positive left offset lies on the outside corner.
  (define outside-elbow
    (polyline-path
     (list origin
           (vec2 2 0)
           (vec2 2 -2))))

  ; miter-offset : path-geometry?
  ;;   Extends both shifted edge lines to their outside intersection.
  (define miter-offset
    (path-geometry-offset outside-elbow 1))
  (check-equal?
   (path-geometry-subpath-points miter-offset)
   (list (list (vec2 0 1)
               (vec2 3 1)
               (vec2 3 -2))))

  ; bevel-offset : path-geometry?
  ;;   Connects the outside endpoints by a straight corner chord.
  (define bevel-offset
    (path-geometry-offset outside-elbow 1 #:join 'bevel))
  (check-equal?
   (path-geometry-subpath-points bevel-offset)
   (list (list (vec2 0 1)
               (vec2 2 1)
               (vec2 3 0)
               (vec2 3 -2))))

  ; round-offset : path-geometry?
  ;;   Uses a cubic quarter-circle approximation at the outside corner.
  (define round-offset
    (path-geometry-offset outside-elbow 1 #:join 'round))
  (check-equal?
   (path-geometry-subpath-points round-offset)
   (list (list (vec2 0 1)
               (vec2 2 1)
               (vec2 3 0)
               (vec2 3 -2))))
  (define round-subpath
    (car (path-geometry-subpaths round-offset)))
  (define round-segments
    (path-subpath-segments round-subpath))
  (check-equal? (length round-segments) 3)
  (check-true (line-path-segment? (list-ref round-segments 0)))
  (check-true (cubic-bezier-path-segment? (list-ref round-segments 1)))
  (check-true (line-path-segment? (list-ref round-segments 2)))

  ;; The round cubic leaves the incoming line tangent in the forward direction
  ;; and arrives tangent to the outgoing line.
  (define round-corner
    (list-ref round-segments 1))
  (define round-control1
    (cubic-bezier-path-segment-control1 round-corner))
  (define round-control2
    (cubic-bezier-path-segment-control2 round-corner))
  (check-true (> (vec2-x round-control1) 2))
  (check-= (vec2-y round-control1) 1 1e-12)
  (check-= (vec2-x round-control2) 3 1e-12)
  (check-true (> (vec2-y round-control2) 0))

  ;; Round sweeps larger than a quarter turn are deterministically subdivided.
  (define wide-round-offset
    (path-geometry-offset
     (polyline-path
      (list origin
            (vec2 2 0)
            (vec2 1 -1)))
     1
     #:join 'round))
  (define wide-round-segments
    (path-subpath-segments
     (car (path-geometry-subpaths wide-round-offset))))
  (check-equal? (length wide-round-segments) 4)
  (check-equal?
   (for/sum ([segment (in-list wide-round-segments)])
     (if (cubic-bezier-path-segment? segment) 1 0))
   2)

  ;; A strict miter limit falls back to the bevel outside join.
  (check-equal?
   (path-geometry-offset outside-elbow 1
                         #:join 'miter
                         #:miter-limit 1)
   bevel-offset)

  ; inside-elbow : path-geometry?
  ;;   Turns left, so a positive left offset lies inside the corner.
  (define inside-elbow
    (polyline-path
     (list origin
           (vec2 2 0)
           (vec2 2 2))))
  (define expected-inside
    (list (list (vec2 0 1)
                (vec2 1 1)
                (vec2 1 2))))
  ;; Outside join policy does not alter an inside corner.
  (for ([join (in-list '(miter bevel round))])
    (check-equal?
     (path-geometry-subpath-points
      (path-geometry-offset inside-elbow 1 #:join join))
     expected-inside))

  ;; The sign selects the opposite parallel side. A negative offset on the same
  ;; left turn is outside, so bevel exposes the corner chord.
  (check-equal?
   (path-geometry-subpath-points
    (path-geometry-offset inside-elbow -1 #:join 'bevel))
   (list (list (vec2 0 -1)
               (vec2 2 -1)
               (vec2 3 0)
               (vec2 3 2))))

  ; square : path-geometry?
  ;;   Gives a counter-clockwise closed polygon.
  (define square
    (polygon-path
     (list origin
           (vec2 4 0)
           (vec2 4 4)
           (vec2 0 4))))
  ; inset-square : path-geometry?
  ;;   Positive left offset is inside every corner of this traversal.
  (define inset-square
    (path-geometry-offset square 1 #:join 'round))
  (define inset-subpath
    (car (path-geometry-subpaths inset-square)))
  (check-true (path-subpath-closed? inset-subpath))
  (check-equal?
   (path-subpath-points inset-subpath)
   (list (vec2 1 1)
         (vec2 3 1)
         (vec2 3 3)
         (vec2 1 3)
         (vec2 1 1)))

  ;; Zero distance is an identity operation even for cubic geometry.
  (define cubic-route
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment
       (vec2 1 2)
       (vec2 2 2)
       (vec2 3 0)))))
  (check-eq? (path-geometry-offset cubic-route 0) cubic-route)

  ;; Nonzero joined offsets intentionally remain straight-segment geometry in
  ;; SCENE-AA. Undefined normals and U-turn joins are rejected deterministically.
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-offset cubic-route 1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-offset
                (polyline-path
                 (list origin origin (vec2 1 0)))
                1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-offset
                (polyline-path
                 (list origin (vec2 1 0) origin))
                1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-offset outside-elbow 1 #:join 'spline)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-offset outside-elbow 1 #:miter-limit 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (path-geometry-offset outside-elbow +inf.0)))

  ;; Generated offset geometry is ordinary semantic path geometry. It therefore
  ;; works directly as a route for both translation and tangent orientation.
  (define rider
    (rectangle #:id 'rider
               #:center (path-geometry-point-at round-offset 0)
               #:width 1
               #:height 1/2))
  (define traversal
    (scene-play
     (scene-add (make-scene) rider)
     (move-along-path rider round-offset)
     (orient-along-path rider round-offset)
     #:duration 4))
  (define start-rider
    (scene-state-ref (scene-sample traversal 0) 'rider))
  (define end-rider
    (scene-state-ref (scene-sample traversal 4) 'rider))
  (check-equal? (visual-position start-rider) (vec2 0 1))
  (check-= (visual-rotation start-rider) 0 1e-12)
  (check-equal? (visual-position end-rider) (vec2 3 -2))
  (check-= (visual-rotation end-rider) (- (/ pi 2)) 1e-12))
