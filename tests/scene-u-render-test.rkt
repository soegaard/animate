#lang racket/base

;;;
;;; SCENE-U Camera Rendering Tests
;;;

;; Tests scene-camera rendering, static camera overrides, frame counts, and
;; deterministic PNG output.


;;;
;;; Imports
;;;

(require rackunit
         racket/file
         (only-in pict pict-height pict-width)
         "../main.rkt"
         "../render.rkt")


(module+ test
  ; initial-camera : camera?
  ;;   Gives a small initial camera for fast deterministic rendering tests.
  (define initial-camera
    (make-camera #:width 160
                 #:height 90
                 #:world-width 12
                 #:center origin
                 #:background "white"))

  ; marker : circle-visual?
  ;;   Gives the stationary Visual reframed by camera motion.
  (define marker
    (circle #:id 'marker
            #:center (vec2 3 0)
            #:radius 1/2
            #:fill "crimson"
            #:stroke "navy"
            #:stroke-width 2))

  ; camera-scene : scene?
  ;;   Pans to marker, zooms in by two, and holds the endpoint.
  (define camera-scene
    (scene-wait
     (scene-play
      (scene-add (make-scene #:camera initial-camera)
                 marker)
      (camera-pan-to (vec2 3 0))
      (camera-zoom-by 2)
      #:duration 1)
     1/2))

  ;; Scene rendering uses the sampled camera by default.
  (define start-pict
    (scene->pict camera-scene 0))
  (define end-pict
    (scene->pict camera-scene 1))
  (check-equal? (pict-width start-pict) 160)
  (check-equal? (pict-height start-pict) 90)
  (check-equal? (pict-width end-pict) 160)
  (check-equal? (pict-height end-pict) 90)

  ;; Zoom changes local Pict size while keeping frame dimensions fixed.
  (define start-marker-pict
    (visual->pict marker
                  (scene-camera-at camera-scene 0)))
  (define end-marker-pict
    (visual->pict marker
                  (scene-camera-at camera-scene 1)))
  (check-true (> (pict-width end-marker-pict)
                 (pict-width start-marker-pict)))
  (check-true (> (pict-height end-marker-pict)
                 (pict-height start-marker-pict)))

  ;; A static override replaces the complete scene-camera timeline.
  (define overridden-end-pict
    (scene->pict camera-scene 1 #:camera initial-camera))
  (check-equal? (pict-width overridden-end-pict) 160)
  (check-equal? (pict-height overridden-end-pict) 90)
  (check-exn exn:fail:contract?
             (lambda ()
               (scene->pict camera-scene 0 #:camera 'invalid)))

  ;; Frame count remains determined only by scene duration and fps.
  (check-equal? (scene-frame-count camera-scene #:fps 4) 6)

  ; dynamic-directory : path?
  ;;   Gives isolated output for frames using the scene camera.
  (define dynamic-directory
    (make-temporary-file "visual-animation-scene-u-dynamic~a" 'directory))

  ; static-directory : path?
  ;;   Gives isolated output for frames using a static camera override.
  (define static-directory
    (make-temporary-file "visual-animation-scene-u-static~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      (define dynamic-paths
        (render-frames! camera-scene
                        dynamic-directory
                        #:fps 4))
      (define static-paths
        (render-frames! camera-scene
                        static-directory
                        #:fps 4
                        #:camera initial-camera))
      (check-equal? (length dynamic-paths) 6)
      (check-equal? (length static-paths) 6)

      (define dynamic-first-bytes
        (file->bytes
         (build-path dynamic-directory "frame-000000.png")))
      (define dynamic-last-bytes
        (file->bytes
         (build-path dynamic-directory "frame-000005.png")))
      (define static-first-bytes
        (file->bytes
         (build-path static-directory "frame-000000.png")))
      (define static-last-bytes
        (file->bytes
         (build-path static-directory "frame-000005.png")))

      ;; The moving camera changes a stationary scene.
      (check-false (bytes=? dynamic-first-bytes
                            dynamic-last-bytes))

      ;; A static override makes every stationary-scene frame identical.
      (check-equal? static-first-bytes
                    static-last-bytes)

      ;; Re-rendering the dynamic camera timeline is byte-identical.
      (render-frames! camera-scene
                      dynamic-directory
                      #:fps 4)
      (check-equal?
       dynamic-first-bytes
       (file->bytes
        (build-path dynamic-directory "frame-000000.png")))
      (check-equal?
       dynamic-last-bytes
       (file->bytes
        (build-path dynamic-directory "frame-000005.png"))))
    (lambda ()
      (delete-directory/files dynamic-directory)
      (delete-directory/files static-directory))))
