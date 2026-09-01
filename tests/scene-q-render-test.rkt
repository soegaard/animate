#lang racket/base

;;;
;;; SCENE-Q Arrow and Axes Rendering Tests
;;;

;; Tests default renderer dispatch, semantic tip and tick bounds, custom
;; overrides, renderer-aware labels, group rendering, frames, and PNG output.


;;;
;;; Imports
;;;

(require racket/file
         (only-in racket/math pi)
         rackunit
         (only-in pict
                  filled-rectangle
                  pict-height
                  pict-width)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 300
                 #:height 180
                 #:world-width 30
                 #:background "white"))

  ; horizontal-arrow : arrow-visual?
  ;;   Gives a four-unit arrow with a known triangular tip width.
  (define horizontal-arrow
    (arrow (vec2 -2 0)
           (vec2 2 0)
           #:id 'horizontal-arrow
           #:stroke "crimson"
           #:stroke-width 0
           #:tip-length 1/2
           #:tip-width 2/5))

  ; arrow-pict : pict?
  ;;   Gives the default Pict rendering of horizontal-arrow.
  (define arrow-pict
    (visual->pict horizontal-arrow test-camera))

  ;; The path renderer adds one pixel of symmetric safety padding on each side.
  (check-equal? (pict-width arrow-pict) 42)
  (check-equal? (pict-height arrow-pict) 6)

  ; double-arrow : arrow-visual?
  ;;   Gives the same shaft with a tip at each endpoint.
  (define double-arrow
    (arrow (vec2 -2 0)
           (vec2 2 0)
           #:id 'double-arrow
           #:stroke "seagreen"
           #:stroke-width 0
           #:tip-length 1/2
           #:tip-width 2/5
           #:start-tip? #t
           #:end-tip? #t))

  (check-equal? (pict-width
                 (visual->pict double-arrow test-camera))
                42)
  (check-equal? (pict-height
                 (visual->pict double-arrow test-camera))
                6)

  ; coordinate-axes : axes-visual?
  ;;   Gives four-by-two axes with ticks and maximum-end tips.
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 4
          #:y-length 2
          #:stroke "navy"
          #:stroke-width 0
          #:tick-size 1/5
          #:tip-length 3/10
          #:tip-width 1/5))

  ; axes-pict : pict?
  ;;   Gives the default Pict rendering of coordinate-axes.
  (define axes-pict
    (visual->pict coordinate-axes test-camera))

  (check-equal? (pict-width axes-pict) 42)
  (check-equal? (pict-height axes-pict) 22)

  ; rotated-axes-pict : pict?
  ;;   Gives the same axes after a quarter-turn rotation.
  (define rotated-axes-pict
    (visual->pict
     (visual-with-rotation coordinate-axes (/ pi 2))
     test-camera))

  (check-= (pict-width rotated-axes-pict) 22 1e-8)
  (check-= (pict-height rotated-axes-pict) 42 1e-8)

  ;; Renderer-aware placement uses the complete arrow and axes render boxes.
  ; x-label : text-visual?
  ;;   Gives a text label placed to the right of the axes.
  (define x-label
    (visual-place-right-of
     (plain-text "x"
                 #:id 'x-label
                 #:font-size 2/5)
     coordinate-axes
     #:gap 1/2
     #:camera test-camera))

  ; axes-box : layout-box?
  ;;   Gives the measured axes render box.
  (define axes-box
    (visual-layout-box coordinate-axes
                       #:camera test-camera))

  ; label-box : layout-box?
  ;;   Gives the measured placed-label render box.
  (define label-box
    (visual-layout-box x-label
                       #:camera test-camera))

  (check-= (- (layout-box-left label-box)
              (layout-box-right axes-box))
           1/2
           1e-10)

  ; arrow-label : text-visual?
  ;;   Gives a label above and right-aligned with the arrow.
  (define arrow-label
    (visual-place-above
     (plain-text "v"
                 #:id 'arrow-label
                 #:font-size 2/5)
     horizontal-arrow
     #:gap 1/4
     #:horizontal-alignment 'right
     #:camera test-camera))

  (check-= (- (layout-box-bottom
               (visual-layout-box arrow-label
                                  #:camera test-camera))
              (layout-box-top
               (visual-layout-box horizontal-arrow
                                  #:camera test-camera)))
           1/4
           1e-10)

  ;; A renderer before the defaults can replace the complete axes rendering.
  (struct axes-override-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (axes-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       (filled-rectangle 17 19 #:draw-border? #f))])

  ; override-renderers : (listof pict-renderer?)
  ;;   Gives a complete-axes override before the built-in renderers.
  (define override-renderers
    (cons (axes-override-renderer)
          default-pict-renderers))

  ; override-pict : pict?
  ;;   Gives the custom complete-axes rendering.
  (define override-pict
    (visual->pict coordinate-axes
                  test-camera
                  #:renderers override-renderers))

  (check-equal? (pict-width override-pict) 17)
  (check-equal? (pict-height override-pict) 19)

  ;; Semantic opacity is applied after custom renderer dispatch and keeps size.
  ; transparent-override-pict : pict?
  ;;   Gives the same custom rendering at zero semantic opacity.
  (define transparent-override-pict
    (visual->pict
     (visual-with-opacity coordinate-axes 0)
     test-camera
     #:renderers override-renderers))

  (check-equal? (pict-width transparent-override-pict) 17)
  (check-equal? (pict-height transparent-override-pict) 19)

  ;; Axes, arrows, and labels compose as ordinary affine group children.
  ; diagram : group-visual?
  ;;   Gives one recursively rendered coordinate diagram.
  (define diagram
    (group (list coordinate-axes
                 horizontal-arrow
                 x-label
                 arrow-label)
           #:id 'diagram
           #:center (vec2 -4 1)
           #:rotation -1/12
           #:scale 4/5
           #:opacity 4/5))

  ; local-diagram-pict : pict?
  ;;   Gives the diagram at the local origin for dimension checks.
  (define local-diagram-pict
    (visual->pict
     (visual-with-position diagram origin)
     test-camera))

  (check-true (> (pict-width local-diagram-pict) 42))

  ;; Rotation and the 4/5 group scale can make the complete Pict shorter than
  ;; the untransformed 22-pixel axes box. It must still contain the axes after
  ;; applying the same inherited transform.
  ; transformed-axes-child-pict : pict?
  ;;   Gives the axes with the diagram's inherited rotation and scale.
  (define transformed-axes-child-pict
    (visual->pict
     (visual-with-scale
      (visual-with-rotation coordinate-axes -1/12)
      4/5)
     test-camera))

  (check-true
   (>= (pict-height local-diagram-pict)
       (pict-height transformed-axes-child-pict)))

  ; entrance : scene?
  ;;   Moves, rotates, scales, and fades the complete diagram into place.
  (define entrance
    (scene-play (make-scene)
                (move-to diagram origin)
                (rotate-to diagram 0)
                (scale-to diagram 1)
                (fade-in diagram)
                #:duration 1))

  ; animation : scene?
  ;;   Holds the completed diagram for one quarter second.
  (define animation
    (scene-wait entrance 1/4))

  (check-equal? (scene-frame-count animation #:fps 4) 5)

  ; temporary-root : path?
  ;;   Gives an isolated directory root for deterministic PNG comparisons.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-q~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; first-paths : (listof path?)
      ;;   Gives the first complete rendering of the diagram animation.
      (define first-paths
        (render-frames! animation
                        (build-path temporary-root "first")
                        #:fps 4
                        #:camera test-camera))

      ; second-paths : (listof path?)
      ;;   Gives the second rendering of the same semantic animation.
      (define second-paths
        (render-frames! animation
                        (build-path temporary-root "second")
                        #:fps 4
                        #:camera test-camera))

      (check-equal? (length first-paths) 5)
      (check-equal? (length second-paths) 5)
      (check-equal? (map file->bytes first-paths)
                    (map file->bytes second-paths))
      (check-false
       (equal? (file->bytes (car first-paths))
               (file->bytes (car (reverse first-paths))))))
    (lambda ()
      (delete-directory/files temporary-root))))
