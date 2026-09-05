#lang racket/base

;;;
;;; SCENE-AQ Lagged-Start Rendering Tests
;;;

(require racket/class
         racket/file
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

  (define left
    (circle #:id 'left
            #:radius 3/5
            #:center (vec2 -5 2)
            #:fill "royalblue"))
  (define middle
    (rectangle #:id 'middle
               #:width 6/5
               #:height 6/5
               #:center (vec2 -5 0)
               #:fill "seagreen"))
  (define right
    (circle #:id 'right
            #:radius 3/5
            #:center (vec2 -5 -2)
            #:fill "tomato"))
  (define camera
    (make-camera #:width 360
                 #:height 220
                 #:world-width 14
                 #:background "white"))
  ;; D=4, n=3, r=1/2 -> two-second children starting at 0, 1, and 2.
  (define scene
    (scene-play
     (scene-add (make-scene #:camera camera) left middle right)
     (lagged-start (move-to left (vec2 4 2))
                   (move-to middle (vec2 4 0))
                   (move-to right (vec2 4 -2))
                   #:lag-ratio 1/2)
     #:duration 4))

  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 360)
    (check-equal? (send bitmap get-height) 220))

  ;; Consecutive half-second samples change pixels while the staggered starts
  ;; enter and leave their active intervals. The exact semantic endpoint is held.
  (define sampled-bytes
    (for/list ([frame-index (in-range 8)])
      (bitmap->argb-bytes
       (scene-frame->bitmap scene frame-index #:fps 2))))
  (for ([left-bytes (in-list sampled-bytes)]
        [right-bytes (in-list (cdr sampled-bytes))])
    (check-false (equal? left-bytes right-bytes)))
  (check-equal? (visual-position
                 (scene-state-ref (scene-sample scene 4) 'left))
                (vec2 4 2))
  (check-equal? (visual-position
                 (scene-state-ref (scene-sample scene 4) 'middle))
                (vec2 4 0))
  (check-equal? (visual-position
                 (scene-state-ref (scene-sample scene 4) 'right))
                (vec2 4 -2))

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-aq-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define first-paths
        (render-frames! scene temporary-directory #:fps 2))
      (define first-pass
        (for/list ([path (in-list first-paths)])
          (file->bytes path)))
      (define second-paths
        (render-frames! scene temporary-directory #:fps 2))
      (check-equal?
       first-pass
       (for/list ([path (in-list second-paths)])
         (file->bytes path))))
    (lambda ()
      (delete-directory/files temporary-directory))))
