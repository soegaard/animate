#lang racket/base

;;;
;;; SCENE-H Rendering Tests
;;;

;; Tests rendered line and cubic path morphs, midpoint bounds, frame sampling,
;; and deterministic PNG output.


;;;
;;; Imports
;;;

(require rackunit
         racket/file
         (only-in pict pict-height pict-width)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 200
                 #:height 120
                 #:world-width 20))

  ; square-path : path-geometry?
  ;;   Gives one centered four-by-two closed line path.
  (define square-path
    (polygon-path
     (list (vec2 -2 -1)
           (vec2 2 -1)
           (vec2 2 1)
           (vec2 -2 1))))

  ; diamond-path : path-geometry?
  ;;   Gives one compatible six-by-four closed line path.
  (define diamond-path
    (polygon-path
     (list (vec2 0 -2)
           (vec2 3 0)
           (vec2 0 2)
           (vec2 -3 0))))

  ; panel : path-visual?
  ;;   Gives the source line path as a filled Visual.
  (define panel
    (make-path-visual square-path
                      #:id 'panel
                      #:center (vec2 0 2)
                      #:fill "cornflowerblue"
                      #:stroke "navy"
                      #:stroke-width 2))

  ; midpoint-panel : path-visual?
  ;;   Gives panel with halfway-interpolated line geometry.
  (define midpoint-panel
    (path-visual-with-path
     panel
     (path-geometry-lerp square-path diamond-path 1/2)))

  ; endpoint-panel : path-visual?
  ;;   Gives panel with its complete destination geometry.
  (define endpoint-panel
    (path-visual-with-path panel diamond-path))

  ; source-panel-pict : pict?
  ;;   Gives the rendered source line geometry.
  (define source-panel-pict
    (visual->pict panel test-camera))

  ; midpoint-panel-pict : pict?
  ;;   Gives the rendered midpoint line geometry.
  (define midpoint-panel-pict
    (visual->pict midpoint-panel test-camera))

  ; endpoint-panel-pict : pict?
  ;;   Gives the rendered destination line geometry.
  (define endpoint-panel-pict
    (visual->pict endpoint-panel test-camera))

  (check-= (pict-width source-panel-pict) 42 1e-8)
  (check-= (pict-height source-panel-pict) 22 1e-8)
  (check-= (pict-width midpoint-panel-pict) 52 1e-8)
  (check-= (pict-height midpoint-panel-pict) 32 1e-8)
  (check-= (pict-width endpoint-panel-pict) 62 1e-8)
  (check-= (pict-height endpoint-panel-pict) 42 1e-8)

  ;; Cubic morphing preserves cubic segments for direct curve rendering.

  ; wave-from-path : path-geometry?
  ;;   Gives a two-segment cubic wave.
  (define wave-from-path
    (cubic-bezier-path
     (vec2 -3 0)
     (list
      (cubic-bezier-path-segment (vec2 -2 2)
                                 (vec2 -1 2)
                                 origin)
      (cubic-bezier-path-segment (vec2 1 -2)
                                 (vec2 2 -2)
                                 (vec2 3 0)))))

  ; wave-to-path : path-geometry?
  ;;   Gives a compatible two-segment cubic arch.
  (define wave-to-path
    (cubic-bezier-path
     (vec2 -3 -1)
     (list
      (cubic-bezier-path-segment (vec2 -2 -1)
                                 (vec2 -1 3)
                                 (vec2 0 3))
      (cubic-bezier-path-segment (vec2 1 3)
                                 (vec2 2 -1)
                                 (vec2 3 -1)))))

  ; wave : path-visual?
  ;;   Gives the source cubic path as an open Visual.
  (define wave
    (make-path-visual wave-from-path
                      #:id 'wave
                      #:center (vec2 0 -3)
                      #:stroke "crimson"
                      #:stroke-width 3))

  ; midpoint-wave : path-visual?
  ;;   Gives wave with halfway-interpolated cubic geometry.
  (define midpoint-wave
    (path-visual-with-path
     wave
     (path-geometry-lerp wave-from-path wave-to-path 1/2)))

  (check-true
   (cubic-bezier-path-segment?
    (car
     (path-subpath-segments
      (car
       (path-geometry-subpaths
        (path-visual-path midpoint-wave)))))))
  (check-not-false
   (visual->pict midpoint-wave test-camera))

  ;; One timeline morphs both paths simultaneously and holds the complete
  ;; destination for one quarter second.

  ; morph-scene : scene?
  ;;   Gives simultaneous line and cubic path morphs.
  (define morph-scene
    (scene-wait
     (scene-play
      (scene-add (make-scene) panel wave)
      (morph-to panel diamond-path)
      (morph-to wave wave-to-path)
      #:duration 1)
     1/4))

  (check-equal? (scene-frame-count morph-scene #:fps 4)
                5)
  (check-not-false
   (scene-frame->bitmap morph-scene
                        0
                        #:fps 4
                        #:camera test-camera))
  (check-not-false
   (scene-frame->bitmap morph-scene
                        2
                        #:fps 4
                        #:camera test-camera))
  (check-not-false
   (scene-frame->bitmap morph-scene
                        4
                        #:fps 4
                        #:camera test-camera))

  ; temporary-directory : path?
  ;;   Gives the isolated output directory for morph PNG tests.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-h~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      (define frame-paths
        (render-frames! morph-scene
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
      (render-frames! morph-scene
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
