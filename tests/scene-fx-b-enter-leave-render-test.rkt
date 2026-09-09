#lang racket/base

;;;
;;; FX-B Entrance and Exit Render Tests
;;;

(require racket/class
         rackunit
         "../main.rkt"
         "../render.rkt")

(module+ test
  (define (bitmap->argb-bytes bitmap)
    (define width (send bitmap get-width))
    (define height (send bitmap get-height))
    (define pixels (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  (define card
    (rectangle #:id 'card #:width 2 #:height 1
               #:center (vec2 2 0) #:opacity 4/5
               #:fill "gold" #:stroke "sienna" #:stroke-width 3))
  (define camera
    (make-camera #:width 320 #:height 200 #:world-width 10 #:background "white"))
  (define entered
    (scene-play
     (make-scene #:camera camera)
     (enter card #:translation-offset (vec2 -2 0) #:scale-factor 1/2)
     #:duration 2))
  (define exited
    (scene-play
     (scene-add (make-scene #:camera camera) card)
     (leave 'card #:translation-offset (vec2 2 0) #:scale-factor 1/2)
     #:duration 2))

  ;; Interior frames are visibly distinct, and rendering in a shuffled index
  ;; order is identical to the corresponding direct requests.
  (define entry-frames
    (for/hash ([frame-index (in-list '(0 1 2 3))])
      (values frame-index
              (bitmap->argb-bytes
               (scene-frame->bitmap entered frame-index #:fps 2)))))
  (check-false (equal? (hash-ref entry-frames 0) (hash-ref entry-frames 1)))
  (check-false (equal? (hash-ref entry-frames 1) (hash-ref entry-frames 2)))
  (for ([frame-index (in-list '(3 0 2 1))])
    (check-equal?
     (bitmap->argb-bytes (scene-frame->bitmap entered frame-index #:fps 2))
     (hash-ref entry-frames frame-index)))
  (check-false
   (equal?
    (bitmap->argb-bytes (scene-frame->bitmap exited 0 #:fps 2))
    (bitmap->argb-bytes (scene-frame->bitmap exited 2 #:fps 2)))))
