#lang racket/base

;;;
;;; SCENE-A Rendering Tests
;;;

;; Tests pict conversion, deterministic frame sampling, and PNG filesystem
;; output separately from the pure model tests.


;;;
;;; Imports
;;;

(require rackunit
         racket/file
         (only-in pict pict-height pict-width)
         "../main.rkt"
         "../render.rkt")


(module+ test
  ; moving-circle : circle-visual?
  ;;   Gives the canonical Visual used by the rendering tests.
  (define moving-circle
    (circle #:id 'moving-circle
            #:center (vec2 -3 0)
            #:radius 3/4))

  ; demo : scene?
  ;;   Gives the canonical one-second move followed by a half-second wait.
  (define demo
    (scene-wait
     (scene-play
      (scene-add (make-scene) moving-circle)
      (move-to moving-circle (vec2 3 0))
      #:duration 1)
     1/2))

  ; test-camera : camera?
  ;;   Gives a small fixed camera for fast deterministic PNG tests.
  (define test-camera
    (make-camera #:width 160
                 #:height 90
                 #:world-width 14))

  ;; Pict conversion preserves the fixed camera dimensions.

  ; first-pict : pict?
  ;;   Gives the first sampled scene pict at test-camera dimensions.
  (define first-pict
    (scene->pict demo 0 #:camera test-camera))
  (check-equal? (pict-width first-pict) 160)
  (check-equal? (pict-height first-pict) 90)

  ;; Frame count and frame-index conversion use exact deterministic times.
  (check-equal? (scene-frame-count demo #:fps 30) 45)
  (check-equal? (frame-index->time 44 #:fps 30) 22/15)

  ;; Filesystem effects are tested in an isolated temporary directory.

  ; temporary-directory : path?
  ;;   Gives the isolated output directory for PNG tests.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-a~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define stale-frame
        (build-path temporary-directory "frame-999999.png"))
      (define long-stale-frame
        (build-path temporary-directory "frame-1000000.png"))
      (define unrelated-file
        (build-path temporary-directory "notes.txt"))
      (call-with-output-file stale-frame
        (lambda (out)
          (display "stale" out))
        #:exists 'truncate)
      (call-with-output-file long-stale-frame
        (lambda (out)
          (display "stale" out))
        #:exists 'truncate)
      (call-with-output-file unrelated-file
        (lambda (out)
          (display "keep" out))
        #:exists 'truncate)

      (define first-render
        (render-frames! demo
                        temporary-directory
                        #:fps 30
                        #:camera test-camera))
      (check-equal? (length first-render) 45)
      (check-false (file-exists? stale-frame))
      (check-false (file-exists? long-stale-frame))
      (check-true (file-exists? unrelated-file))
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000000.png")))
      (check-true
       (file-exists?
        (build-path temporary-directory "frame-000044.png")))

      (define first-frame-bytes
        (file->bytes
         (build-path temporary-directory "frame-000000.png")))
      (define last-frame-bytes
        (file->bytes
         (build-path temporary-directory "frame-000044.png")))
      (check-false (bytes=? first-frame-bytes last-frame-bytes))

      ;; Re-rendering the same scene reproduces the same PNG bytes.
      (define second-render
        (render-frames! demo
                        temporary-directory
                        #:fps 30
                        #:camera test-camera))
      (check-equal? (length second-render) 45)
      (check-equal?
       first-frame-bytes
       (file->bytes
        (build-path temporary-directory "frame-000000.png"))))
    (lambda ()
      (delete-directory/files temporary-directory))))
