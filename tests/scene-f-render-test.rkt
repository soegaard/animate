#lang racket/base

;;;
;;; SCENE-F Rendering Tests
;;;

;; Tests Pict conversion and deterministic PNG output for semantic Create and
;; Uncreate animations.


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
    (make-camera #:width 160
                 #:height 90
                 #:world-width 16))

  ; reveal-visual : path-visual?
  ;;   Gives a four-unit rightward path anchored at the origin.
  (define reveal-visual
    (make-path-visual
     (polyline-path (list origin
                          (vec2 4 0)))
     #:id 'reveal-visual
     #:stroke "crimson"
     #:stroke-width 2))

  ;; Partial path geometry reaches the existing Pict renderer without a
  ;; backend-specific animation representation.

  ; create-scene : scene?
  ;;   Gives one second of creation followed by a quarter-second endpoint hold.
  (define create-scene
    (scene-wait
     (scene-play (make-scene)
                 (create reveal-visual)
                 #:duration 1)
     1/4))

  ; create-start-visual : path-visual?
  ;;   Gives the invisible path Visual at the start of creation.
  (define create-start-visual
    (scene-state-ref (scene-sample create-scene 0)
                     'reveal-visual))

  ; create-midpoint-visual : path-visual?
  ;;   Gives the two-unit visible prefix halfway through creation.
  (define create-midpoint-visual
    (scene-state-ref (scene-sample create-scene 1/2)
                     'reveal-visual))

  ; create-end-visual : path-visual?
  ;;   Gives the complete path during the endpoint wait.
  (define create-end-visual
    (scene-state-ref (scene-sample create-scene 1)
                     'reveal-visual))

  ; create-start-pict : pict?
  ;;   Gives the transparent empty-path Pict at creation start.
  (define create-start-pict
    (visual->pict create-start-visual test-camera))

  ; create-midpoint-pict : pict?
  ;;   Gives the halfway path rendered with cosmetic stroke padding.
  (define create-midpoint-pict
    (visual->pict create-midpoint-visual test-camera))

  ; create-end-pict : pict?
  ;;   Gives the complete path rendered with cosmetic stroke padding.
  (define create-end-pict
    (visual->pict create-end-visual test-camera))

  (check-equal? (pict-width create-start-pict)
                1)
  (check-equal? (pict-height create-start-pict)
                1)
  (check-equal? (pict-width create-midpoint-pict)
                42)
  (check-equal? (pict-height create-midpoint-pict)
                2)
  (check-equal? (pict-width create-end-pict)
                82)
  (check-equal? (pict-height create-end-pict)
                2)

  ;; Scene rendering remains fixed to the camera frame at every reveal point.

  (for ([time (in-list (list 0 1/4 1/2 3/4 1 5/4))])
    (define frame
      (scene->pict create-scene
                   time
                   #:camera test-camera))
    (check-equal? (pict-width frame)
                  160)
    (check-equal? (pict-height frame)
                  90))

  ;; Uncreate uses the same partial-path renderer in reverse and removes the
  ;; Visual before the endpoint wait begins.

  ; uncreate-scene : scene?
  ;;   Gives one second of removal followed by a quarter-second empty hold.
  (define uncreate-scene
    (scene-wait
     (scene-play
      (scene-add (make-scene) reveal-visual)
      (uncreate reveal-visual)
      #:duration 1)
     1/4))

  ; uncreate-midpoint-visual : path-visual?
  ;;   Gives the two-unit visible prefix halfway through removal.
  (define uncreate-midpoint-visual
    (scene-state-ref (scene-sample uncreate-scene 1/2)
                     'reveal-visual))
  (check-equal?
   (pict-width
    (visual->pict uncreate-midpoint-visual test-camera))
   42)
  (check-false
   (scene-state-has? (scene-sample uncreate-scene 1)
                     'reveal-visual))
  (check-false
   (scene-state-has? (scene-sample uncreate-scene 5/4)
                     'reveal-visual))

  ;; Compound and closed paths remain renderable at partial reveal points.

  ; compound-path : path-geometry?
  ;;   Gives a closed triangle followed by an open segment.
  (define compound-path
    (path-geometry
     (append
      (path-geometry-subpaths
       (polygon-path (list origin
                           (vec2 2 0)
                           (vec2 0 2))))
      (path-geometry-subpaths
       (polyline-path (list (vec2 3 0)
                            (vec2 5 0)))))))

  ; compound-visual : path-visual?
  ;;   Gives a styled Visual for compound-path.
  (define compound-visual
    (make-path-visual compound-path
                      #:id 'compound-visual
                      #:fill "lightblue"
                      #:stroke "navy"
                      #:stroke-width 2))

  ; compound-create-scene : scene?
  ;;   Gives a one-second reveal of compound-visual.
  (define compound-create-scene
    (scene-play (make-scene)
                (create compound-visual)))
  (check-not-false
   (visual->pict
    (scene-state-ref (scene-sample compound-create-scene 1/2)
                     'compound-visual)
    test-camera))
  (check-not-false
   (visual->pict
    (scene-state-ref (scene-sample compound-create-scene 1)
                     'compound-visual)
    test-camera))

  ;; PNG output samples an invisible start frame and a complete endpoint frame.

  (check-equal? (scene-frame-count create-scene #:fps 4)
                5)
  (check-equal? (scene-frame-count uncreate-scene #:fps 4)
                5)
  (check-not-false
   (scene-frame->bitmap create-scene
                        0
                        #:fps 4
                        #:camera test-camera))
  (check-not-false
   (scene-frame->bitmap create-scene
                        4
                        #:fps 4
                        #:camera test-camera))

  ; temporary-directory : path?
  ;;   Gives the isolated output directory for reveal PNG tests.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-f~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define frame-paths
        (render-frames! create-scene
                        temporary-directory
                        #:fps 4
                        #:camera test-camera))
      (check-equal? (length frame-paths)
                    5)
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000000.png")))
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000004.png")))
      (check-false
       (bytes=?
        (file->bytes
         (build-path temporary-directory "frame-000000.png"))
        (file->bytes
         (build-path temporary-directory "frame-000004.png"))))
      (define first-run-midpoint-frame
        (file->bytes
         (build-path temporary-directory "frame-000002.png")))
      (define first-run-final-frame
        (file->bytes
         (build-path temporary-directory "frame-000004.png")))
      (render-frames! create-scene
                      temporary-directory
                      #:fps 4
                      #:camera test-camera)
      (check-equal?
       first-run-midpoint-frame
       (file->bytes
        (build-path temporary-directory "frame-000002.png")))
      (check-equal?
       first-run-final-frame
       (file->bytes
        (build-path temporary-directory "frame-000004.png"))))
    (lambda ()
      (delete-directory/files temporary-directory))))
