#lang racket/base

;;;
;;; SCENE-E Rendering Tests
;;;

;; Tests Pict conversion and deterministic PNG output for open and closed path
;; Visuals under translation, rotation, and non-uniform scale.


;;;
;;; Imports
;;;

(require rackunit
         racket/file
         (only-in pict pict-height pict-width)
         (only-in racket/math pi)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 160
                 #:height 90
                 #:world-width 16))

  ;; Open and closed straight paths render with symmetric anchor-centered
  ;; bounds and cosmetic stroke padding.

  ; horizontal-line : path-visual?
  ;;   Gives a four-world-unit horizontal line with a two-pixel stroke.
  (define horizontal-line
    (line (vec2 -2 0)
          (vec2 2 0)
          #:id 'horizontal-line
          #:stroke-width 2))

  ; horizontal-pict : pict?
  ;;   Gives horizontal-line rendered at ten pixels per world unit.
  (define horizontal-pict
    (visual->pict horizontal-line test-camera))
  (check-equal? (pict-width horizontal-pict) 42)
  (check-equal? (pict-height horizontal-pict) 2)

  ; vertical-line : path-visual?
  ;;   Gives the same line rotated counter-clockwise by one quarter turn.
  (define vertical-line
    (line (vec2 -2 0)
          (vec2 2 0)
          #:id 'vertical-line
          #:rotation (/ pi 2)
          #:stroke-width 2))

  ; vertical-pict : pict?
  ;;   Gives vertical-line after semantic rotation and bounds calculation.
  (define vertical-pict
    (visual->pict vertical-line test-camera))
  (check-= (pict-width vertical-pict) 2 1e-8)
  (check-= (pict-height vertical-pict) 42 1e-8)

  ; square : path-visual?
  ;;   Gives a filled two-by-two polygon centered at the origin.
  (define square
    (polygon (list (vec2 -1 -1)
                   (vec2 1 -1)
                   (vec2 1 1)
                   (vec2 -1 1))
             #:id 'square
             #:fill "goldenrod"
             #:stroke "saddlebrown"
             #:stroke-width 2))

  ; square-pict : pict?
  ;;   Gives square rendered with one pixel of padding on every side.
  (define square-pict
    (visual->pict square test-camera))
  (check-equal? (pict-width square-pict) 22)
  (check-equal? (pict-height square-pict) 22)

  ; scaled-square : path-visual?
  ;;   Gives square with double x scale and half y scale.
  (define scaled-square
    (visual-with-scale square (vec2 2 1/2)))

  ; scaled-square-pict : pict?
  ;;   Gives scaled-square after semantic point transformation.
  (define scaled-square-pict
    (visual->pict scaled-square test-camera))
  (check-equal? (pict-width scaled-square-pict) 42)
  (check-equal? (pict-height scaled-square-pict) 12)

  ;; Empty path geometry is renderable and useful as a future creation
  ;; endpoint.

  ; empty-visual : path-visual?
  ;;   Gives a semantic path Visual with no subpaths.
  (define empty-visual
    (make-path-visual empty-path-geometry
                      #:id 'empty))

  ; empty-pict : pict?
  ;;   Gives the transparent placeholder for empty path geometry.
  (define empty-pict
    (visual->pict empty-visual test-camera))
  (check-equal? (pict-width empty-pict) 1)
  (check-equal? (pict-height empty-pict) 1)

  ; point-only-visual : path-visual?
  ;;   Gives a nonempty path Visual with one point and no segments.
  (define point-only-visual
    (make-path-visual
     (path-geometry
      (list (path-subpath origin '() #f)))
     #:id 'point-only
     #:stroke-width 4))

  ; point-only-pict : pict?
  ;;   Gives an anchor-centered Pict for point-only-visual.
  (define point-only-pict
    (visual->pict point-only-visual test-camera))
  (check-equal? (pict-width point-only-pict) 4)
  (check-equal? (pict-height point-only-pict) 4)

  ;; Multiple subpaths render through one path Visual. Closed subpaths are
  ;; filled together and open subpaths are stroked separately.

  ; compound-geometry : path-geometry?
  ;;   Gives one closed triangle and one open horizontal segment.
  (define compound-geometry
    (path-geometry
     (append
      (path-geometry-subpaths
       (polygon-path (list (vec2 -1 -1)
                           (vec2 1 -1)
                           (vec2 0 1))))
      (path-geometry-subpaths
       (polyline-path (list (vec2 -2 0)
                            (vec2 2 0)))))))

  ; compound-visual : path-visual?
  ;;   Gives styled compound-geometry centered at the origin.
  (define compound-visual
    (make-path-visual compound-geometry
                      #:id 'compound
                      #:fill "lightblue"
                      #:stroke "navy"
                      #:stroke-width 2))
  (check-equal? (pict-width
                 (visual->pict compound-visual test-camera))
                42)
  (check-equal? (pict-height
                 (visual->pict compound-visual test-camera))
                22)

  ;; Scene-level rendering keeps the camera frame size and drawing order.

  ; path-scene : scene?
  ;;   Gives a line over a polygon at the same reference position.
  (define path-scene
    (scene-add (make-scene)
               square
               horizontal-line))
  (check-equal? (pict-width
                 (scene->pict path-scene
                              0
                              #:camera test-camera))
                160)
  (check-equal? (pict-height
                 (scene->pict path-scene
                              0
                              #:camera test-camera))
                90)

  ;; Path transform animation propagates through bitmap and PNG adapters.

  ; animated-scene : scene?
  ;;   Gives a short path transform followed by a visible endpoint wait.
  (define animated-scene
    (scene-wait
     (scene-play
      (scene-add (make-scene) square horizontal-line)
      (move-to square (vec2 2 0))
      (rotate-by square (/ pi 2))
      (scale-to square (vec2 1/2 3/2))
      (move-to horizontal-line (vec2 -2 0))
      (rotate-by horizontal-line (/ pi 2))
      #:duration 1/5)
     1/10))
  (check-equal? (scene-frame-count animated-scene #:fps 10)
                3)
  (check-not-false
   (scene-frame->bitmap animated-scene
                        0
                        #:fps 10
                        #:camera test-camera))
  (check-not-false
   (scene-frame->bitmap animated-scene
                        2
                        #:fps 10
                        #:camera test-camera))

  ; temporary-directory : path?
  ;;   Gives the isolated output directory for path PNG tests.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-e~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define frame-paths
        (render-frames! animated-scene
                        temporary-directory
                        #:fps 10
                        #:camera test-camera))
      (check-equal? (length frame-paths) 3)
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000000.png")))
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000002.png")))
      (check-false
       (bytes=?
        (file->bytes
         (build-path temporary-directory "frame-000000.png"))
        (file->bytes
         (build-path temporary-directory "frame-000002.png"))))
      (define first-run-last-frame
        (file->bytes
         (build-path temporary-directory "frame-000002.png")))
      (render-frames! animated-scene
                      temporary-directory
                      #:fps 10
                      #:camera test-camera)
      (check-equal?
       first-run-last-frame
       (file->bytes
        (build-path temporary-directory "frame-000002.png"))))
    (lambda ()
      (delete-directory/files temporary-directory))))
