#lang racket/base

;;;
;;; SCENE-AR Duration-Scaled Composition Rendering Tests
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

  (define top
    (circle #:id 'top
            #:radius 3/5
            #:center (vec2 -5 2)
            #:fill "royalblue"))
  (define middle
    (rectangle #:id 'middle
               #:width 6/5
               #:height 6/5
               #:center (vec2 -5 0)
               #:fill "seagreen"))
  (define bottom
    (circle #:id 'bottom
            #:radius 3/5
            #:center (vec2 -5 -2)
            #:fill "tomato"))
  (define camera
    (make-camera #:width 360
                 #:height 220
                 #:world-width 14
                 #:background "white"))

  ;; Direct spans 1,2,1 in D=4 become one-, two-, and one-second sequence
  ;; intervals. The rendered motion therefore changes at each half-second frame.
  (define scene
    (scene-play
     (scene-add (make-scene #:camera camera) top middle bottom)
     (succession
      (move-to top (vec2 4 2))
      (timed (move-to middle (vec2 4 0)) #:duration 2)
      (move-to bottom (vec2 4 -2)))
     #:duration 4))

  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 360)
    (check-equal? (send bitmap get-height) 220))

  (check-equal? (visual-position
                 (scene-state-ref (scene-sample scene 1) 'top))
                (vec2 4 2))
  (check-equal? (visual-position
                 (scene-state-ref (scene-sample scene 2) 'middle))
                (vec2 -1/2 0))
  (check-equal? (visual-position
                 (scene-state-ref (scene-sample scene 3) 'middle))
                (vec2 4 0))
  (check-equal? (visual-position
                 (scene-state-ref (scene-sample scene 7/2) 'bottom))
                (vec2 -1/2 -2))
  (check-equal? (visual-position
                 (scene-state-ref (scene-sample scene 4) 'bottom))
                (vec2 4 -2))

  (define sampled-bytes
    (for/list ([frame-index (in-range 8)])
      (bitmap->argb-bytes
       (scene-frame->bitmap scene frame-index #:fps 2))))
  (for ([left-bytes (in-list sampled-bytes)]
        [right-bytes (in-list (cdr sampled-bytes))])
    (check-false (equal? left-bytes right-bytes)))

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-ar-~a" 'directory))
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
