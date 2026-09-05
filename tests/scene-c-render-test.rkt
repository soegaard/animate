#lang racket/base

;;;
;;; SCENE-C Rendering Tests
;;;

;; Tests transformed built-in Pict rendering and deterministic PNG output.


;;;
;;; Imports
;;;

(require rackunit
         racket/file
         (only-in pict pict-height pict-width)
         (only-in racket/math pi)
         "../main.rkt"
         "../render.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 160
                 #:height 90
                 #:world-width 16))

  ;; Non-uniform scale changes local geometry before Pict conversion.

  ; scaled-rectangle : rectangle-visual?
  ;;   Gives a rectangle scaled twice in x and one half in y.
  (define scaled-rectangle
    (rectangle #:id 'scaled-rectangle
               #:width 4
               #:height 2
               #:scale (vec2 2 1/2)))

  ; scaled-rectangle-pict : pict?
  ;;   Gives scaled-rectangle rendered without rotation.
  (define scaled-rectangle-pict
    (visual->pict scaled-rectangle test-camera))
  (check-equal? (pict-width scaled-rectangle-pict) 80)
  (check-equal? (pict-height scaled-rectangle-pict) 10)

  ; rotated-rectangle : rectangle-visual?
  ;;   Gives scaled-rectangle rotated by a quarter turn.
  (define rotated-rectangle
    (visual-with-rotation scaled-rectangle (/ pi 2)))

  ; rotated-rectangle-pict : pict?
  ;;   Gives the quarter-turned rectangle Pict.
  (define rotated-rectangle-pict
    (visual->pict rotated-rectangle test-camera))
  (check-= (pict-width rotated-rectangle-pict) 10 1e-8)
  (check-= (pict-height rotated-rectangle-pict) 80 1e-8)

  ;; A non-uniformly scaled circle renders as an ellipse and can rotate.

  ; scaled-circle : circle-visual?
  ;;   Gives a circle stretched twice in x.
  (define scaled-circle
    (circle #:id 'scaled-circle
            #:radius 1
            #:scale (vec2 2 1)))

  ; scaled-circle-pict : pict?
  ;;   Gives scaled-circle rendered as a horizontal ellipse.
  (define scaled-circle-pict
    (visual->pict scaled-circle test-camera))
  (check-equal? (pict-width scaled-circle-pict) 40)
  (check-equal? (pict-height scaled-circle-pict) 20)

  ; rotated-circle-pict : pict?
  ;;   Gives the stretched circle after a quarter turn.
  (define rotated-circle-pict
    (visual->pict
     (visual-with-rotation scaled-circle (/ pi 2))
     test-camera))
  (check-= (pict-width rotated-circle-pict) 20 1e-8)
  (check-= (pict-height rotated-circle-pict) 40 1e-8)

  ;; Uniform circles ignore rotation because their rendered geometry is invariant.

  ; uniform-circle-pict : pict?
  ;;   Gives a rotated uniform circle without an inflated bounding box.
  (define uniform-circle-pict
    (visual->pict
     (circle #:id 'uniform-circle
             #:radius 1
             #:rotation (/ pi 4))
     test-camera))
  (check-equal? (pict-width uniform-circle-pict) 20)
  (check-equal? (pict-height uniform-circle-pict) 20)

  ;; Combined transform animation propagates through bitmap and PNG rendering.

  ; animated-panel : rectangle-visual?
  ;;   Gives the rectangle used by frame-output tests.
  (define animated-panel
    (rectangle #:id 'animated-panel
               #:center (vec2 -2 0)
               #:width 3
               #:height 1
               #:fill "goldenrod"
               #:stroke "saddlebrown"
               #:stroke-width 3))

  ; transform-scene : scene?
  ;;   Gives a one-second combined transform followed by an endpoint wait.
  (define transform-scene
    (scene-wait
     (scene-play
      (scene-add (make-scene) animated-panel)
      (move-to animated-panel (vec2 2 0))
      (rotate-by animated-panel (/ pi 2))
      (scale-to animated-panel (vec2 1/2 2))
      #:duration 1)
     1/10))
  (check-equal? (scene-frame-count transform-scene #:fps 10)
                11)
  (check-not-false
   (scene-frame->bitmap transform-scene
                        10
                        #:fps 10
                        #:camera test-camera))

  ; temporary-directory : path?
  ;;   Gives the isolated output directory for transformed PNG tests.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-c~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define frame-paths
        (render-frames! transform-scene
                        temporary-directory
                        #:fps 10
                        #:camera test-camera))
      (check-equal? (length frame-paths) 11)
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000000.png")))
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000010.png")))
      (define first-frame
        (file->bytes
         (build-path temporary-directory "frame-000000.png")))
      (define last-frame
        (file->bytes
         (build-path temporary-directory "frame-000010.png")))
      (check-false (bytes=? first-frame last-frame))

      ;; Re-rendering the same transformed scene is byte-identical.
      (render-frames! transform-scene
                      temporary-directory
                      #:fps 10
                      #:camera test-camera)
      (check-equal?
       last-frame
       (file->bytes
        (build-path temporary-directory "frame-000010.png"))))
    (lambda ()
      (delete-directory/files temporary-directory))))
