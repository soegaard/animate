#lang racket/base

;;;
;;; SCENE-BH Bitmap Image Visual Tests
;;;

(require racket/class
         racket/file
         rackunit
         (only-in pict pict-height pict-width)
         (only-in racket/draw bitmap%)
         "../main.rkt")

(module+ test
  (define source-path
    (make-temporary-file "animate-image~a.png"))
  (dynamic-wind
    void
    (lambda ()
      (define source-bitmap
        (make-object bitmap% 4 2))
      (check-true (send source-bitmap save-file source-path 'png))
      (define visual
        (image source-path
               #:id 'sample-image
               #:center (vec2 1 2)
               #:width 2
               #:height 1))
      (check-true (image-visual? visual))
      (check-equal? (visual-id visual) 'sample-image)
      (check-equal? (visual-position visual) (vec2 1 2))
      (check-equal? (image-visual-width visual) 2)
      (check-equal? (image-visual-height visual) 1)
      (check-true (immutable? (image-visual-source visual)))
      (define viewport
        (make-camera #:width 100 #:height 50 #:world-width 10))
      ;; Renderer dimensions use declared world geometry, not source pixels.
      (define rendered
        (visual->pict visual viewport))
      (check-equal? (pict-width rendered) 20)
      (check-equal? (pict-height rendered) 10)
      (define animated
        (scene-play
         (scene-add (make-scene) visual)
         (move-to visual (vec2 5 -1))
         (scale-to visual (vec2 2 1/2))
         (fade-to visual 1/2)
         #:duration 2))
      (define midpoint
        (scene-visual-at animated 'sample-image 1))
      (check-equal? (visual-position midpoint) (vec2 3 1/2))
      (check-equal? (visual-scale midpoint) (vec2 3/2 3/4))
      (check-equal? (visual-opacity midpoint) 3/4)
      ;; Ordinary scene rendering and camera placement accept image Visuals.
      (check-equal? (send (scene-frame->bitmap animated 0 #:fps 1 #:camera viewport)
                          get-width)
                    100)
      (check-exn exn:fail:contract?
                 (lambda ()
                   (image source-path #:id 'bad #:width 0 #:height 1)))
      (check-exn exn:fail:contract?
                 (lambda ()
                   (image 42 #:id 'bad #:width 1 #:height 1))))
    (lambda ()
      (when (file-exists? source-path)
        (delete-file source-path)))))
