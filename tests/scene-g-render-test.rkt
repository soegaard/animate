#lang racket/base

;;;
;;; SCENE-G Rendering Tests
;;;

;; Tests cubic Bézier Pict rendering, tight curve bounds, sharp closed-path
;; joins, round open-path caps, curve reveal, and deterministic PNG output.


;;;
;;; Imports
;;;

(require rackunit
         racket/file
         (only-in pict pict-height pict-width)
         "../main.rkt"
         "../render.rkt"
         (submod "../private/shape-pict-renderers.rkt" test-support))


(module+ test
  ; test-camera : camera?
  ;;   Gives a camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 160
                 #:height 90
                 #:world-width 16))

  ;; Closed path corners use miter joins instead of the round join that caused
  ;; the visible upper-right corner artifact in the SCENE-F example.

  (define-values (closed-cap closed-join)
    (closed-path-pen-cap-and-join))
  (check-equal? closed-cap 'butt)
  (check-equal? closed-join 'miter)

  (define-values (open-cap open-join)
    (open-path-pen-cap-and-join))
  (check-equal? open-cap 'round)
  (check-equal? open-join 'miter)

  ;; Tight cubic bounds ignore control-point overshoot that the curve itself
  ;; never reaches.

  ; arch-path : path-geometry?
  ;;   Gives a two-unit-wide cubic whose true height is three halves.
  (define arch-path
    (cubic-bezier-path
     (vec2 -1 0)
     (list
      (cubic-bezier-path-segment (vec2 -1 2)
                                 (vec2 1 2)
                                 (vec2 1 0)))))

  ; arch-visual : path-visual?
  ;;   Gives arch-path with a two-pixel cosmetic stroke.
  (define arch-visual
    (make-path-visual arch-path
                      #:id 'arch
                      #:stroke "navy"
                      #:stroke-width 2))

  ; arch-pict : pict?
  ;;   Gives arch-visual rendered using tight curve bounds.
  (define arch-pict
    (visual->pict arch-visual test-camera))

  (check-= (pict-width arch-pict)
           22
           1e-8)
  (check-= (pict-height arch-pict)
           32
           1e-8)

  ; scaled-arch-visual : path-visual?
  ;;   Gives arch-visual with double x scale and half y scale.
  (define scaled-arch-visual
    (visual-with-scale arch-visual (vec2 2 1/2)))

  ; scaled-arch-pict : pict?
  ;;   Gives the transformed cubic Pict.
  (define scaled-arch-pict
    (visual->pict scaled-arch-visual test-camera))

  (check-= (pict-width scaled-arch-pict)
           42
           1e-8)
  (check-= (pict-height scaled-arch-pict)
           17
           1e-8)

  ;; A compound path can mix lines and cubic curves in one subpath.

  ; mixed-path : path-geometry?
  ;;   Gives one line and one cubic segment in traversal order.
  (define mixed-path
    (path-geometry
     (list
      (path-subpath (vec2 -2 0)
                    (list
                     (line-path-segment (vec2 -1 0))
                     (cubic-bezier-path-segment (vec2 -1 2)
                                                (vec2 1 2)
                                                (vec2 2 0)))
                    #f))))

  ; mixed-visual : path-visual?
  ;;   Gives a styled Visual for mixed-path.
  (define mixed-visual
    (make-path-visual mixed-path
                      #:id 'mixed
                      #:stroke "crimson"
                      #:stroke-width 2))

  (check-not-false
   (visual->pict mixed-visual test-camera))

  ;; Create renders a cubic prefix at intermediate samples and the complete
  ;; curve during the endpoint wait.

  ; reveal-path : path-geometry?
  ;;   Gives a four-unit-wide symmetric cubic from the origin.
  (define reveal-path
    (cubic-bezier-path
     origin
     (list
      (cubic-bezier-path-segment (vec2 0 2)
                                 (vec2 4 2)
                                 (vec2 4 0)))))

  ; reveal-visual : path-visual?
  ;;   Gives reveal-path as a path Visual.
  (define reveal-visual
    (make-path-visual reveal-path
                      #:id 'reveal
                      #:stroke "darkgreen"
                      #:stroke-width 2))

  ; reveal-scene : scene?
  ;;   Gives one second of creation and a quarter-second endpoint hold.
  (define reveal-scene
    (scene-wait
     (scene-play (make-scene)
                 (create reveal-visual)
                 #:duration 1)
     1/4))

  ; midpoint-visual : path-visual?
  ;;   Gives the first half of reveal-visual by local arc length.
  (define midpoint-visual
    (scene-state-ref (scene-sample reveal-scene 1/2)
                     'reveal))

  ; midpoint-pict : pict?
  ;;   Gives the rendered cubic prefix.
  (define midpoint-pict
    (visual->pict midpoint-visual test-camera))

  ; endpoint-pict : pict?
  ;;   Gives the complete rendered cubic during the wait clip.
  (define endpoint-pict
    (visual->pict
     (scene-state-ref (scene-sample reveal-scene 1)
                      'reveal)
     test-camera))

  (check-= (pict-width midpoint-pict)
           42
           1e-6)
  (check-= (pict-height midpoint-pict)
           32
           1e-6)
  (check-= (pict-width endpoint-pict)
           82
           1e-8)
  (check-= (pict-height endpoint-pict)
           32
           1e-8)

  ;; Bitmap and PNG adapters preserve deterministic curve rendering.

  (check-equal? (scene-frame-count reveal-scene #:fps 4)
                5)
  (check-not-false
   (scene-frame->bitmap reveal-scene
                        2
                        #:fps 4
                        #:camera test-camera))

  ; temporary-directory : path?
  ;;   Gives the isolated output directory for cubic PNG tests.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-g~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      (define frame-paths
        (render-frames! reveal-scene
                        temporary-directory
                        #:fps 4
                        #:camera test-camera))
      (check-equal? (length frame-paths)
                    5)
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000002.png")))
      (define first-run-midpoint
        (file->bytes
         (build-path temporary-directory "frame-000002.png")))
      (define first-run-endpoint
        (file->bytes
         (build-path temporary-directory "frame-000004.png")))
      (render-frames! reveal-scene
                      temporary-directory
                      #:fps 4
                      #:camera test-camera)
      (check-equal?
       first-run-midpoint
       (file->bytes
        (build-path temporary-directory "frame-000002.png")))
      (check-equal?
       first-run-endpoint
       (file->bytes
        (build-path temporary-directory "frame-000004.png"))))
    (lambda ()
      (delete-directory/files temporary-directory))))
