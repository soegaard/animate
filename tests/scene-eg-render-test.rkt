#lang racket/base

;; SCENE-EG-2 production-render parity.  The preview worker must sample the
;; same semantic scene path as scene-frame->bitmap, including camera motion,
;; structured paint, nested transforms, and a live camera inset.

(require racket/async-channel
         racket/class
         rackunit
         "../main.rkt"
         "../preview.rkt")

(define (bitmap->argb-bytes bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  pixels)

(define (await-preview-bitmap events)
  (let loop ()
    (define event
      (or (sync/timeout 5 events)
          (error 'scene-eg-render-test "timed out waiting for preview bitmap")))
    (if (eq? (preview-event-kind event) 'frame-ready)
        (preview-event-bitmap event)
        (loop))))

(module+ test
  (define camera
    (make-camera #:width 240 #:height 135 #:world-width 6 #:background "white"))
  (define inset-camera
    (make-camera #:width 120 #:height 68 #:world-width 2 #:background "ivory"))
  (define dot
    (circle #:id 'dot #:center (vec2 -1 0) #:radius 1/3
            #:fill "tomato" #:stroke "firebrick" #:stroke-width 2))
  (define painted-panel
    (rectangle #:id 'painted-panel #:center (vec2 0 -1)
               #:width 3 #:height 1
               #:fill (linear-gradient
                       (vec2 -3/2 0) (vec2 3/2 0)
                       (list (paint-stop 0 "deepskyblue")
                             (paint-stop 1 "mediumpurple")))
               #:stroke #f))
  (define nested
    (group (list painted-panel) #:id 'nested #:rotation 1/12))
  (define inset
    (camera-view #:id 'inset #:targets '(dot nested)
                 #:camera inset-camera #:frame-camera camera
                 #:at (vec2 2 1) #:width 2 #:clip 'rounded))
  (define animated
    (scene-play
     (scene-add (make-scene #:camera camera) dot nested inset)
     (move-to 'dot (vec2 1 0))
     (camera-pan-to (vec2 1/2 0))
     #:duration 1))

  (define events (make-async-channel))
  (define preview
    (open-preview-controller animated #:fps 2 #:pixel-scale 1 #:prefetch 0
                             #:on-event (lambda (event) (async-channel-put events event))))
  (define preview-frame-zero (await-preview-bitmap events))
  (check-equal? (bitmap->argb-bytes preview-frame-zero)
                (bitmap->argb-bytes (scene-frame->bitmap animated 0 #:fps 2)))
  (void (preview-seek-frame! preview 1))
  (define preview-frame-one (await-preview-bitmap events))
  (check-equal? (bitmap->argb-bytes preview-frame-one)
                (bitmap->argb-bytes (scene-frame->bitmap animated 1 #:fps 2)))
  (preview-close! preview))
