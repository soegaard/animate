#lang racket/base

;;;
;;; SCENE-AU Unified Style Rendering Tests
;;;

(require racket/class
         racket/file
         rackunit
         (only-in pict pict->bitmap)
         "../main.rkt")

(module+ test
  (define (bitmap->argb-bytes bitmap)
    (define width (send bitmap get-width))
    (define height (send bitmap get-height))
    (define pixels (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  (define camera
    (make-camera #:width 320
                 #:height 180
                 #:world-width 12
                 #:background "white"))
  (define disk
    (circle #:id 'disk
            #:center (vec2 -3 0)
            #:radius 1
            #:fill "red"
            #:stroke "black"
            #:stroke-width 2
            #:opacity 1))
  (define scene
    (scene-play
     (scene-add (make-scene #:camera camera) disk)
     (animation-group
      (style-to disk
                #:fill "blue"
                #:stroke "gold"
                #:stroke-width 10
                #:opacity 1/2)
      (move-to disk (vec2 3 0)))
     #:duration 2))

  ;; Unified style reaches the existing semantic render adapters without a new
  ;; renderer-specific animation path, and dimensions remain invariant.
  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 320)
    (check-equal? (send bitmap get-height) 180))

  (define start-bytes
    (bitmap->argb-bytes (pict->bitmap (scene->pict scene 0) 'aligned)))
  (define mid-bytes
    (bitmap->argb-bytes (pict->bitmap (scene->pict scene 1) 'aligned)))
  (define end-bytes
    (bitmap->argb-bytes (pict->bitmap (scene->pict scene 2) 'aligned)))
  (check-false (equal? start-bytes mid-bytes))
  (check-false (equal? mid-bytes end-bytes))

  (define mid-visual
    (scene-state-ref (scene-sample scene 1) 'disk))
  (check-equal? (visual-position mid-visual) origin)
  (check-equal? (visual-fill-color mid-visual)
                (rgba-color 255/2 0 255/2 1))
  (check-equal? (visual-stroke-color mid-visual)
                (rgba-color 255/2 215/2 0 1))
  (check-equal? (visual-stroke-width mid-visual) 6)
  (check-equal? (visual-opacity mid-visual) 3/4)

  ;; Exact scene-time endpoint storage remains the primitive endpoint storage.
  (define end-visual
    (scene-state-ref (scene-sample scene 2) 'disk))
  (check-equal? (visual-fill-color end-visual) "blue")
  (check-equal? (visual-stroke-color end-visual) "gold")
  (check-equal? (visual-stroke-width end-visual) 10)
  (check-equal? (visual-opacity end-visual) 1/2)

  ;; Repeated frame rendering remains byte-for-byte deterministic.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-au-~a" 'directory))
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
