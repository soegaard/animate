#lang racket/base

;;;
;;; SCENE-I Rendering Tests
;;;

;; Tests rendering of normalized line and cubic path morphs, frame sampling,
;; exact endpoints, and deterministic PNG output.


;;;
;;; Imports
;;;

(require rackunit
         racket/file
         (only-in pict pict-height pict-width)
         "../main.rkt"
         "../render.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 240
                 #:height 160
                 #:world-width 24))

  ; triangle-path : path-geometry?
  ;;   Gives a closed three-edge line path.
  (define triangle-path
    (polygon-path
     (list (vec2 -3 -1)
           (vec2 3 -1)
           (vec2 0 2))))

  ; rectangle-path : path-geometry?
  ;;   Gives an incompatible closed four-edge line path.
  (define rectangle-path
    (polygon-path
     (list (vec2 -3 -2)
           (vec2 3 -2)
           (vec2 3 2)
           (vec2 -3 2))))

  (define-values (normalized-triangle normalized-rectangle)
    (path-geometry-normalize-for-morph triangle-path rectangle-path))

  ; panel : path-visual?
  ;;   Gives the source polygon as a filled Visual.
  (define panel
    (make-path-visual triangle-path
                      #:id 'panel
                      #:center (vec2 0 2)
                      #:fill "cornflowerblue"
                      #:stroke "navy"
                      #:stroke-width 2))

  ; midpoint-panel : path-visual?
  ;;   Gives panel with normalized halfway geometry.
  (define midpoint-panel
    (path-visual-with-path
     panel
     (path-geometry-lerp normalized-triangle
                         normalized-rectangle
                         1/2)))

  ; endpoint-panel : path-visual?
  ;;   Gives panel with the exact destination path.
  (define endpoint-panel
    (path-visual-with-path panel rectangle-path))

  ; source-panel-pict : pict?
  ;;   Gives the rendered source polygon.
  (define source-panel-pict
    (visual->pict panel test-camera))

  ; midpoint-panel-pict : pict?
  ;;   Gives the rendered normalized midpoint polygon.
  (define midpoint-panel-pict
    (visual->pict midpoint-panel test-camera))

  ; endpoint-panel-pict : pict?
  ;;   Gives the rendered destination polygon.
  (define endpoint-panel-pict
    (visual->pict endpoint-panel test-camera))

  (check-true (positive? (pict-width source-panel-pict)))
  (check-true (positive? (pict-height source-panel-pict)))
  (check-true (positive? (pict-width midpoint-panel-pict)))
  (check-true (positive? (pict-height midpoint-panel-pict)))
  (check-true (positive? (pict-width endpoint-panel-pict)))
  (check-true (positive? (pict-height endpoint-panel-pict)))
  ;; Both shapes extend two world units from the local anchor in the
  ;; vertical direction. The anchor-centered renderer therefore gives them
  ;; equal Pict heights even though their semantic bounds differ.
  (check-equal? (pict-height source-panel-pict)
                (pict-height endpoint-panel-pict))

  ;; A straight line can morph into a two-segment cubic wave after the source
  ;; line is cubicized and split.

  ; line-path : path-geometry?
  ;;   Gives one open straight segment.
  (define line-path
    (polyline-path
     (list (vec2 -3 0)
           (vec2 3 0))))

  ; wave-path : path-geometry?
  ;;   Gives an incompatible two-segment cubic wave.
  (define wave-path
    (cubic-bezier-path
     (vec2 -3 0)
     (list
      (cubic-bezier-path-segment (vec2 -2 2)
                                 (vec2 -1 2)
                                 origin)
      (cubic-bezier-path-segment (vec2 1 -2)
                                 (vec2 2 -2)
                                 (vec2 3 0)))))

  ; wave : path-visual?
  ;;   Gives the straight source line as an open Visual.
  (define wave
    (make-path-visual line-path
                      #:id 'wave
                      #:center (vec2 0 -3)
                      #:stroke "crimson"
                      #:stroke-width 4))

  ; normalized-scene : scene?
  ;;   Gives simultaneous normalized polygon and curve morphs with a hold.
  (define normalized-scene
    (scene-wait
     (scene-play
      (scene-add (make-scene) panel wave)
      (morph-to-normalized panel rectangle-path)
      (rotate-by panel 1/4)
      (morph-to-normalized wave wave-path)
      (scale-to wave (vec2 4/3 3/4))
      #:duration 1)
     1/4))

  ; sampled-wave : path-visual?
  ;;   Gives the wave halfway through normalized interpolation.
  (define sampled-wave
    (scene-state-ref (scene-sample normalized-scene 1/2)
                     'wave))

  (check-equal? (length (path-subpath-segments
                         (car (path-geometry-subpaths
                               (path-visual-path sampled-wave)))))
                2)
  (check-true
   (andmap cubic-bezier-path-segment?
           (path-subpath-segments
            (car (path-geometry-subpaths
                  (path-visual-path sampled-wave))))))
  (check-not-false
   (visual->pict sampled-wave test-camera))

  (check-equal? (scene-frame-count normalized-scene #:fps 4)
                5)
  (check-not-false
   (scene-frame->bitmap normalized-scene
                        0
                        #:fps 4
                        #:camera test-camera))
  (check-not-false
   (scene-frame->bitmap normalized-scene
                        2
                        #:fps 4
                        #:camera test-camera))
  (check-not-false
   (scene-frame->bitmap normalized-scene
                        4
                        #:fps 4
                        #:camera test-camera))

  ; temporary-directory : path?
  ;;   Gives the isolated output directory for normalized-morph PNG tests.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-i~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      (define frame-paths
        (render-frames! normalized-scene
                        temporary-directory
                        #:fps 4
                        #:camera test-camera))
      (check-equal? (length frame-paths)
                    5)
      (define start-bytes
        (file->bytes
         (build-path temporary-directory "frame-000000.png")))
      (define midpoint-bytes
        (file->bytes
         (build-path temporary-directory "frame-000002.png")))
      (define endpoint-bytes
        (file->bytes
         (build-path temporary-directory "frame-000004.png")))
      (check-false (equal? start-bytes midpoint-bytes))
      (check-false (equal? midpoint-bytes endpoint-bytes))
      (render-frames! normalized-scene
                      temporary-directory
                      #:fps 4
                      #:camera test-camera)
      (check-equal?
       start-bytes
       (file->bytes
        (build-path temporary-directory "frame-000000.png")))
      (check-equal?
       midpoint-bytes
       (file->bytes
        (build-path temporary-directory "frame-000002.png")))
      (check-equal?
       endpoint-bytes
       (file->bytes
        (build-path temporary-directory "frame-000004.png"))))
    (lambda ()
      (delete-directory/files temporary-directory))))
