#lang racket/base

;;;
;;; SCENE-CY-A General Affine-Map Tests
;;;

;; Verifies the pure map algebra and the whole-Visual affine-map animation
;; layer. Existing affine-transform placement remains unchanged; the new API
;; maps complete top-level world Visuals through a full 2x2 matrix.

(require racket/math
         rackunit
         (only-in pict pict-height pict-width)
         "../private/scene-state.rkt"
         "../main.rkt")

(module+ test
  (define (check-real-close actual expected)
    (check-= actual expected 1e-10))

  (define (check-vec2-close actual expected)
    (check-real-close (vec2-x actual) (vec2-x expected))
    (check-real-close (vec2-y actual) (vec2-y expected)))

  ;; The matrix convention is [a b; c d] acting on column vectors.
  (define shear
    (linear2 1 1
             0 1))
  (check-equal? (linear2-determinant shear) 1)
  (check-equal? (linear2-apply-vector shear (vec2 2 3))
                (vec2 5 3))
  (check-equal?
   (linear2-compose shear identity-linear2)
   shear)
  (check-equal?
   (make-linear2 2 3 5 7)
   (linear2 2 3 5 7))

  ;; Composition uses ordinary matrix multiplication in the same row order.
  (define outer-linear (linear2 2 3 5 7))
  (define inner-linear (linear2 11 13 17 19))
  (check-equal?
   (linear2-compose outer-linear inner-linear)
   (linear2 73 83 174 198))
  (check-equal?
   (linear2-invert outer-linear)
   (linear2 -7 3 5 -2))
  (check-false (linear2-invert (linear2 1 2 2 4)))

  (define translated-shear
    (affine2 1 1 2
             0 1 -1))
  (check-equal? (affine2-apply-point translated-shear (vec2 2 1))
                (vec2 5 0))
  (check-equal?
   (affine2-compose translated-shear identity-affine2)
   translated-shear)
  (define outer-affine
    (affine2 2 3 29
             5 7 31))
  (define inner-affine
    (affine2 11 13 23
             17 19 29))
  (check-equal?
   (affine2-compose outer-affine inner-affine)
   (affine2 73 83 162
            174 198 349))
  (check-equal?
   (affine2-invert translated-shear)
   (affine2 1 -1 -3
            0 1 1))
  (check-equal? (affine2-translation translated-shear) (vec2 2 -1))
  (check-equal? (affine2-h translated-shear) 2)
  (check-equal? (affine2-k translated-shear) -1)

  ;; Existing decomposed transforms convert exactly to the new representation.
  (define old-transform
    (make-affine-transform #:translation (vec2 3 -2)
                           #:rotation (/ pi 2)
                           #:scale (vec2 2 3)))
  (check-equal?
   (affine2-apply-point (affine-transform->affine2 old-transform)
                        (vec2 1 2))
   (affine-transform-apply-point old-transform (vec2 1 2)))

  (define square
    (polygon (list (vec2 -1 -1)
                   (vec2 1 -1)
                   (vec2 1 1)
                   (vec2 -1 1))
             #:id 'square #:fill "gold" #:stroke-width 2))
  (define diagram
    (group (list square) #:id 'diagram #:center (vec2 2 1)))

  ;; A direct wrapper has the mapped semantic reference point and a transformed
  ;; Pict box. A unit shear doubles the square group's horizontal extent while
  ;; preserving its vertical extent.
  (define mapped-diagram
    (affine-map diagram
                (make-affine2 #:linear shear)))
  (check-true (affine-map-visual? mapped-diagram))
  (check-equal? (visual-id mapped-diagram) 'diagram)
  (check-equal? (visual-position mapped-diagram) (vec2 3 1))
  (define original-pict
    (visual->pict diagram default-camera))
  (define mapped-pict
    (visual->pict mapped-diagram default-camera))
  (check-equal? (pict-width mapped-pict)
                (* 2 (pict-width original-pict)))
  (check-equal? (pict-height mapped-pict)
                (pict-height original-pict))

  ;; A scene starts with its exact ordinary Visual, uses a map wrapper for
  ;; interior/end samples, and interpolates the request from identity.
  (define affine-scene
    (scene-wait
     (scene-play
      (scene-add (make-scene) diagram)
      (apply-affine 'diagram translated-shear)
      #:duration 2)
     1))
  (check-equal? (scene-visual-at affine-scene 'diagram 0) diagram)
  (define middle
    (scene-visual-at affine-scene 'diagram 1))
  (check-true (affine-map-visual? middle))
  ;; At half progress: [1 1/2; 0 1] and translation (1, -1/2).
  (check-vec2-close (visual-position middle) (vec2 7/2 1/2))
  (define endpoint
    (scene-visual-at affine-scene 'diagram 2))
  (check-true (affine-map-visual? endpoint))
  (check-equal? (visual-position endpoint) (vec2 5 0))
  (check-not-false
   (scene-frame->bitmap affine-scene 2 #:fps 1))

  ;; A second map composes after the first rather than mapping a rasterized
  ;; output. The final map sends (2,1) to (-5,0).
  (define reflected
    (scene-wait
     (scene-play affine-scene
                 (apply-matrix 'diagram (make-linear2 -1 0 0 1))
                 #:duration 1)
     1))
  (check-equal?
   (visual-position (scene-visual-at reflected 'diagram 4))
   (vec2 -5 0))

  ;; SCENE-DK rebases a world map through the enclosing diagram transform.
  ;; The addressed child becomes a semantic wrapper, retains its path, and can
  ;; be restyled in the same play clip after the parent-affine request.
  (define nested
    (scene-wait
     (scene-play
      (scene-add (make-scene) diagram)
      (apply-affine '(diagram square) translated-shear)
      (fill-color-to '(diagram square) "red")
      #:duration 1)
     1))
  (define nested-local
    (scene-visual-at nested '(diagram square) 1))
  (check-true (affine-map-visual? nested-local))
  (check-equal? (visual-fill-color nested-local) "red")
  (define nested-world
    (scene-state-resolved-world-ref
     (scene-sample nested 1)
     '(diagram square)))
  (check-true (affine-map-visual? nested-world))
  (check-equal? (visual-position nested-world) (vec2 5 0))
  (check-not-false (scene-frame->bitmap nested 1 #:fps 1))

  ;; A child request after a mapped parent is still expressed in world
  ;; coordinates.  Its local wrapper is rebased through the parent's semantic
  ;; affine map, so the result is g(f((2,1))) = (7,-1), not a map applied to
  ;; rasterized parent pixels.
  (define parent-then-child
    (scene-wait
     (scene-play
      (scene-play
       (scene-add (make-scene) diagram)
       (apply-affine 'diagram translated-shear)
       #:duration 1)
      (apply-affine '(diagram square) translated-shear)
      #:duration 1)
     1))
  (define parent-then-child-world
    (scene-state-resolved-world-ref
     (scene-sample parent-then-child 2)
     '(diagram square)))
  (check-true (affine-map-visual? parent-then-child-world))
  (check-equal? (visual-position parent-then-child-world) (vec2 7 -1))
  (check-not-false (scene-frame->bitmap parent-then-child 2 #:fps 1))

  ;; Same-target map and decomposed motion still conflict within one clip.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (scene-add (make-scene) diagram)
                 (apply-affine 'diagram translated-shear)
                 (move-to 'diagram origin)))))
