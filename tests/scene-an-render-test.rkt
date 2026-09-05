#lang racket/base

;;;
;;; SCENE-AN Local Visual Timing Rendering Tests
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

  (define dot
    (circle #:id 'dot
            #:radius 1
            #:center (vec2 -4 0)
            #:fill "seagreen"))
  (define camera
    (make-camera #:width 360
                 #:height 220
                 #:world-width 14
                 #:background "white"))
  (define scene
    (scene-play
     (scene-add (make-scene #:camera camera) dot)
     (timed (move-to dot (vec2 4 0)) #:start 1 #:duration 1)
     #:duration 3))

  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 360)
    (check-equal? (send bitmap get-height) 220))

  ;; Frames before the local start are byte-identical. The interior differs, and
  ;; the endpoint remains held for the rest of the enclosing play clip.
  (define frame-0
    (bitmap->argb-bytes (scene-frame->bitmap scene 0 #:fps 2)))
  (define frame-1
    (bitmap->argb-bytes (scene-frame->bitmap scene 1 #:fps 2)))
  (define frame-2
    (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2)))
  (define frame-3
    (bitmap->argb-bytes (scene-frame->bitmap scene 3 #:fps 2)))
  (define frame-4
    (bitmap->argb-bytes (scene-frame->bitmap scene 4 #:fps 2)))
  (define frame-5
    (bitmap->argb-bytes (scene-frame->bitmap scene 5 #:fps 2)))
  (check-equal? frame-0 frame-1)
  (check-equal? frame-1 frame-2)
  (check-false (equal? frame-2 frame-3))
  (check-false (equal? frame-3 frame-4))
  (check-equal? frame-4 frame-5)
  (check-equal?
   (visual-position (scene-state-ref (scene-sample scene 3) 'dot))
   (vec2 4 0))

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-an-~a" 'directory))
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
