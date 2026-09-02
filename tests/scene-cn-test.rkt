#lang racket/base

;;;
;;; SCENE-CN Dynamic Endpoint Geometry Tests
;;;

(require rackunit
         racket/class
         (only-in pict pict->bitmap)
         "../main.rkt")

(define (bitmap->argb-bytes bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define result (make-bytes (* width height 4)))
  (send bitmap get-argb-pixels 0 0 width height result)
  result)

(define (scene-bytes scene time)
  (bitmap->argb-bytes
   (pict->bitmap (scene->pict scene time) 'aligned)))

(module+ test
  (define camera
    (make-camera #:width 240 #:height 160 #:world-width 20 #:background "white"))
  (define A
    (circle #:id 'A #:center (vec2 -2 0) #:radius 1/5
            #:fill "navy" #:stroke #f #:stroke-width 0))
  (define B
    (parameter 'B (vec2 2 0)))
  (define edge
    (arrow-between 'A B #:id 'edge #:stroke "crimson" #:stroke-width 3))

  ;; Centre references and point-valued parameters stay fully inside the pure
  ;; derived-Visual architecture, so another derived definition can use their
  ;; concrete output at any arbitrary scene sample.
  (check-true (derived-visual? edge))
  (check-false (dynamic-endpoint-visual? edge))
  (define moving-edge
    (scene-play
     (scene-add
      (scene-set-value (make-scene #:camera camera) B)
      A edge)
     (move-to 'A (vec2 0 2))
     (value-to B (vec2 4 2))
     #:duration 2))
  (define middle-edge
    (scene-visual-at moving-edge 'edge 1))
  (check-true (arrow-visual? middle-edge))
  (check-equal? (arrow-visual-start middle-edge) (vec2 -1 1))
  (check-equal? (arrow-visual-end middle-edge) (vec2 3 1))

  ;; segment-between is intentionally the finite-segment spelling of the same
  ;; relationship. ray-from normalizes its live direction to a fixed length.
  (define segment
    (segment-between (vec2 -1 -1) (vec2 1 -1) #:id 'segment))
  (check-true (derived-visual? segment))
  (define ray
    (ray-from (vec2 0 0) (vec2 3 4) #:id 'ray #:length 10))
  (define ray-scene (scene-add (make-scene #:camera camera) ray))
  (define resolved-ray (scene-ref ray-scene 'ray))
  (check-equal? (arrow-visual-start resolved-ray) origin)
  (check-equal? (arrow-visual-end resolved-ray) (vec2 6 8))

  ;; An edge or corner endpoint is renderer-aware. Its target's live measured
  ;; right edge coincides pixel-for-pixel with an explicitly authored segment.
  (define box
    (rectangle #:id 'box #:center origin #:width 2 #:height 1
               #:fill "aliceblue" #:stroke #f #:stroke-width 0))
  (define anchored-segment
    (line-between (anchor-of 'box 'right) (vec2 3 0)
                  #:id 'anchored-segment #:stroke "darkgreen" #:stroke-width 3))
  (check-true (dynamic-endpoint-visual? anchored-segment))
  (check-true (dynamic-endpoint-visual-has-renderer-anchors? anchored-segment))
  (define anchored-scene
    (scene-wait
     (scene-add (make-scene #:camera camera) box anchored-segment)
     1))
  (define explicit-scene
    (scene-wait
     (scene-add
      (make-scene #:camera camera)
      box
      (line (vec2 1 0) (vec2 3 0)
            #:id 'anchored-segment #:stroke "darkgreen" #:stroke-width 3))
     1))
  (check-true (bytes=? (scene-bytes anchored-scene 0)
                       (scene-bytes explicit-scene 0)))
  ;; The right anchor is remeasured after ordinary same-clip movement and
  ;; scaling; it is not a construction-time point snapshot.
  (define moving-anchored-scene
    (scene-play anchored-scene
                (move-to 'box (vec2 2 0))
                (scale-to 'box 2)
                #:duration 1))
  (define explicit-anchored-middle
    (scene-wait
     (scene-add
      (make-scene #:camera camera)
      (rectangle #:id 'box #:center (vec2 1 0) #:width 2 #:height 1
                 #:scale 3/2 #:fill "aliceblue" #:stroke #f #:stroke-width 0)
      (line (vec2 5/2 0) (vec2 3 0)
            #:id 'anchored-segment #:stroke "darkgreen" #:stroke-width 3))
     1))
  (check-true (bytes=? (scene-bytes moving-anchored-scene 3/2)
                       (scene-bytes explicit-anchored-middle 0)))
  ;; Re-rendering an arbitrary sample has no frame-history dependency.
  (check-true (bytes=? (scene-bytes moving-anchored-scene 3/2)
                       (scene-bytes moving-anchored-scene 3/2)))

  ;; API validation is immediate where possible and dynamic endpoint errors are
  ;; explicit at the sampled state that creates the bad geometry.
  (check-exn exn:fail:contract?
             (lambda () (anchor-of 'A 'diagonal)))
  (check-exn exn:fail:contract?
             (lambda () (line-between 'A (vec2 1 0) #:id 'A)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene->pict
      (scene-add (make-scene #:camera camera)
                 (ray-from origin origin #:id 'bad-ray))
      0)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene->pict
      (scene-add
       (scene-set-value (make-scene #:camera camera) (parameter 'bad-value 1))
       (line-between (parameter 'bad-value 1) (vec2 2 0) #:id 'bad-line))
      0))))
