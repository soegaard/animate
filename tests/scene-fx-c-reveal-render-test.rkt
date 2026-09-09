#lang racket/base

;;;
;;; FX-C2/C3 Hard-Clip Reveal Render Tests
;;;

(require racket/class
         rackunit
         (only-in pict pict->bitmap)
         "../main.rkt"
         "../render.rkt")

(define (bitmap->argb-bytes bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* width height 4)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  pixels)

(module+ test
  (define camera
    (make-camera #:width 240 #:height 160 #:world-width 8 #:background "white"))
  (define card
    (rectangle #:id 'card #:width 4 #:height 2 #:fill "gold" #:stroke #f))
  (define front (linear-reveal-front (vec2 1 0) #:padding 0))
  (define blank-scene (make-scene #:camera camera))
  (define blank (scene-wait blank-scene 1))
  (define entering
    (scene-play blank-scene (reveal-in card front) #:duration 2))
  (define leaving
    (scene-play (scene-add blank-scene card) (reveal-out 'card front) #:duration 2))
  (define (scene-bytes scene time)
    (bitmap->argb-bytes (pict->bitmap (scene->pict scene time) 'aligned)))
  (define blank-bytes (scene-bytes blank 0))

  ;; The empty entry clip is visually blank, the interior hard clip is distinct
  ;; from both endpoints, and the exact endpoint has restored normal content.
  (define entry-start (scene-bytes entering 0))
  (define entry-half (scene-bytes entering 1))
  (define entry-end (scene-bytes entering 2))
  (check-equal? entry-start blank-bytes)
  (check-not-equal? entry-half blank-bytes)
  (check-not-equal? entry-half entry-end)
  (check-not-equal? entry-end blank-bytes)

  ;; Reverse clipping keeps the source visible at time zero, changes the
  ;; interior image, and removes it exactly at completion.
  (define leave-start (scene-bytes leaving 0))
  (define leave-half (scene-bytes leaving 1))
  (define leave-end (scene-bytes leaving 2))
  (check-equal? leave-start entry-end)
  (check-not-equal? leave-half leave-start)
  (check-equal? leave-end blank-bytes)

  ;; Rendering queried frame times out of order must be byte-for-byte stable.
  (define reference
    (for/hash ([index (in-list '(0 1 2))])
      (values index (scene-bytes entering index))))
  (for ([index (in-list '(2 0 1 2 1 0))])
    (check-equal?
     (scene-bytes entering index)
     (hash-ref reference index))))
