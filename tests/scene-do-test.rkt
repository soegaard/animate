#lang racket/base

;;;
;;; SCENE-DO — Zoom and Multi-View Cameras
;;;

;; A camera view is a semantic frame-space Visual: it does not duplicate a
;; scene or cache frames, but resolves its ordinary world target at each sample
;; and renders it through a second immutable camera.

(require racket/class
         rackunit
         "../main.rkt")

(module+ test
  (define outer-camera
    (make-camera #:width 400 #:height 200 #:world-width 8 #:background "white"))
  (define inset-camera
    (make-camera #:width 160
                 #:height 90
                 #:world-width 3
                 #:center (vec2 0 0)
                 #:background "ivory"))
  (define dot
    (circle #:id 'dot
            #:center (vec2 -1 0)
            #:radius 1/3
            #:fill "tomato"
            #:stroke "firebrick"
            #:stroke-width 2))
  (define inset
    (camera-view 'dot
                 #:id 'inset
                 #:camera inset-camera
                 #:frame-camera outer-camera
                 #:at (vec2 2 1)
                 #:width 2))

  (check-true (camera-view-visual? inset))
  (check-true (frame-space-visual? inset))
  (check-equal? (camera-view-visual-target inset) 'dot)
  (check-eq? (camera-view-visual-camera inset) inset-camera)
  (check-equal? (camera-view-visual-width inset) 2)
  (check-equal? (frame-space-visual-frame-width inset) 8)

  ;; A direct conversion cannot resolve a live target. Scene rendering can,
  ;; and produces the complete outer-camera bitmap.
  (check-exn exn:fail:contract?
              (lambda () (visual->pict inset outer-camera)))
  (define base
    (scene-add (make-scene #:camera outer-camera) dot inset))
  (define static
    (scene-wait base 1))
  (define base-bitmap
    (scene-frame->bitmap static 0 #:fps 1))
  (check-equal? (send base-bitmap get-width) 400)
  (check-equal? (send base-bitmap get-height) 200)

  ;; The live target moves normally; neither an independent inset scene nor
  ;; mutable sampling history is needed for the second camera to update.
  (define moved
    (scene-play static (move-to 'dot (vec2 1 0)) #:duration 1))
  (check-not-false (scene-frame->bitmap moved 1 #:fps 1))

  ;; The inset is in captured frame coordinates, so an animated outer camera
  ;; does not make it drift with the world content.
  (define panned
    (scene-play static (camera-pan-to (vec2 2 0)) #:duration 1))
  (check-not-false (scene-frame->bitmap panned 1 #:fps 1))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (camera-view (fixed-in-frame dot #:camera outer-camera)
                  #:id 'bad-inset
                  #:camera inset-camera))))
