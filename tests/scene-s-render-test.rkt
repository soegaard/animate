#lang racket/base

;;;
;;; SCENE-S Parametric Curve and Data Plot Rendering Tests
;;;

;; Tests shared path rendering, smooth cubic interpolation, clipping bounds,
;; scene composition, frame counts, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/file
         rackunit
         (only-in pict
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

  ; coordinate-axes : axes-visual?
  ;;   Gives four-by-four axes without tips for predictable local bounds.
  (define coordinate-axes
    (axes #:id 'coordinate-axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 4
          #:y-length 4
          #:stroke "navy"
          #:stroke-width 0
          #:tick-size 0
          #:x-tip? #f
          #:y-tip? #f))

  ; straight-parametric : path-visual?
  ;;   Gives one line-equivalent smooth cubic across two world units.
  (define straight-parametric
    (parametric-curve
     coordinate-axes
     (lambda (parameter)
       (vec2 parameter parameter))
     #:id 'straight-parametric
     #:parameter-range (parameter-range -1 1)
     #:sample-count 2
     #:clip? #f
     #:interpolation 'smooth
     #:stroke-width 0))

  ; straight-pict : pict?
  ;;   Gives the ordinary path renderer output for straight-parametric.
  (define straight-pict
    (visual->pict straight-parametric test-camera))

  ;; Two world units become twenty pixels. The path renderer adds one pixel of
  ;; symmetric safety padding at every side.
  (check-equal? (pict-width straight-pict) 22)
  (check-equal? (pict-height straight-pict) 22)

  ; data-points : (listof vec2?)
  ;;   Gives a visible zigzag for linear-versus-smooth rendering checks.
  (define data-points
    (list (vec2 -2 -1)
          (vec2 -1 1)
          (vec2 0 -1)
          (vec2 1 1)
          (vec2 2 -1)))

  ; linear-data : path-visual?
  ;;   Gives a piecewise-linear data plot.
  (define linear-data
    (data-plot coordinate-axes
               data-points
               #:id 'linear-data
               #:clip? #f
               #:interpolation 'linear
               #:stroke "crimson"
               #:stroke-width 2))

  ; smooth-data : path-visual?
  ;;   Gives a cubic interpolation through the same ordered points.
  (define smooth-data
    (data-plot coordinate-axes
               data-points
               #:id 'smooth-data
               #:clip? #f
               #:interpolation 'smooth
               #:stroke "seagreen"
               #:stroke-width 2))

  ; linear-data-pict : pict?
  ;;   Gives the linear data plot's local Pict.
  (define linear-data-pict
    (visual->pict linear-data test-camera))

  ; smooth-data-pict : pict?
  ;;   Gives the smooth data plot's local Pict.
  (define smooth-data-pict
    (visual->pict smooth-data test-camera))

  (check-true (positive? (pict-width linear-data-pict)))
  (check-true (positive? (pict-height linear-data-pict)))
  (check-true (positive? (pict-width smooth-data-pict)))
  (check-true (positive? (pict-height smooth-data-pict)))

  ;; Smooth clipping keeps all cubic controls in the visible axes rectangle.
  ; clipped-smooth-data : path-visual?
  ;;   Gives a smooth clipped plot whose local Pict remains inside the axes box.
  (define clipped-smooth-data
    (data-plot coordinate-axes
               (list (vec2 -3 0)
                     (vec2 -1 2)
                     (vec2 1 -2)
                     (vec2 3 0))
               #:id 'clipped-smooth-data
               #:interpolation 'smooth
               #:stroke-width 0))

  ; clipped-smooth-pict : pict?
  ;;   Gives the complete clipped smooth data Pict.
  (define clipped-smooth-pict
    (visual->pict clipped-smooth-data test-camera))

  (check-true (<= (pict-width clipped-smooth-pict) 42))
  (check-true (<= (pict-height clipped-smooth-pict) 42))

  ;; Parametric and data plots use ordinary path Create while axes fade in.
  ; entrance : scene?
  ;;   Introduces axes and draws two coordinate curves over three halves seconds.
  (define entrance
    (scene-play (make-scene)
                (fade-in coordinate-axes)
                (create straight-parametric)
                (create smooth-data)
                #:duration 3/2))

  ; animation : scene?
  ;;   Holds the complete diagram for another half second.
  (define animation
    (scene-wait entrance 1/2))

  (check-equal? (scene-frame-count animation #:fps 4) 8)

  ; start-pict : pict?
  ;;   Gives the first scene frame.
  (define start-pict
    (scene->pict animation
                 0
                 #:camera test-camera))

  ; middle-pict : pict?
  ;;   Gives an interior reveal frame.
  (define middle-pict
    (scene->pict animation
                 3/4
                 #:camera test-camera))

  ; end-pict : pict?
  ;;   Gives the exact structural endpoint.
  (define end-pict
    (scene->pict animation
                 3/2
                 #:camera test-camera))

  (check-equal? (pict-width start-pict) 300)
  (check-equal? (pict-height start-pict) 180)
  (check-equal? (pict-width middle-pict) 300)
  (check-equal? (pict-height middle-pict) 180)
  (check-equal? (pict-width end-pict) 300)
  (check-equal? (pict-height end-pict) 180)

  ; temporary-root : path?
  ;;   Gives an isolated directory root for deterministic PNG comparisons.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-s~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; first-paths : (listof path?)
      ;;   Gives the first complete rendering of the plot animation.
      (define first-paths
        (render-frames! animation
                        (build-path temporary-root "first")
                        #:fps 4
                        #:camera test-camera))

      ; second-paths : (listof path?)
      ;;   Gives the repeated rendering of the same semantic animation.
      (define second-paths
        (render-frames! animation
                        (build-path temporary-root "second")
                        #:fps 4
                        #:camera test-camera))

      (check-equal? (length first-paths) 8)
      (check-equal? (length second-paths) 8)
      (check-equal? (map file->bytes first-paths)
                    (map file->bytes second-paths))
      (check-false
       (equal? (file->bytes (car first-paths))
               (file->bytes (car (reverse first-paths)))))

      ;; Linear and smooth interpolation render different curve geometry.
      ; linear-only-paths : (listof path?)
      ;;   Gives one rendered frame containing the linear data plot.
      (define linear-only-paths
        (render-frames!
         (scene-wait (scene-add (make-scene) linear-data) 1/4)
         (build-path temporary-root "linear-only")
         #:fps 4
         #:camera test-camera))

      ; smooth-only-paths : (listof path?)
      ;;   Gives one rendered frame containing the smooth data plot.
      (define smooth-only-paths
        (render-frames!
         (scene-wait (scene-add (make-scene) smooth-data) 1/4)
         (build-path temporary-root "smooth-only")
         #:fps 4
         #:camera test-camera))

      (check-equal? (length linear-only-paths) 1)
      (check-equal? (length smooth-only-paths) 1)
      (check-false
       (equal? (file->bytes (car linear-only-paths))
               (file->bytes (car smooth-only-paths)))))
    (lambda ()
      (delete-directory/files temporary-root))))
