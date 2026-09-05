#lang racket/base

;;;
;;; SCENE-AV Animated Scalar Value Rendering Tests
;;;

(require racket/class
         racket/file
         rackunit
         (only-in pict pict->bitmap)
         "../main.rkt"
         "../render.rkt")

(module+ test
  (define (bitmap->argb-bytes bitmap)
    (define width (send bitmap get-width))
    (define height (send bitmap get-height))
    (define pixels (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  (define camera
    (make-camera #:width 240 #:height 160 #:world-width 10 #:background "white"))
  (define dot
    (circle #:id 'dot #:center origin #:radius 1 #:fill "blue"))
  (define base
    (scene-set-value (scene-add (make-scene #:camera camera) dot) 'alpha 0))

  ;; Scalar state is deliberately non-rendering in AV: changing only a value
  ;; leaves pixels unchanged while semantic sampling changes deterministically.
  (define value-only
    (scene-play base (value-to 'alpha 10) #:duration 2))
  (check-equal? (scene-value-at value-only 'alpha 1) 5)
  (define start-bytes
    (bitmap->argb-bytes (pict->bitmap (scene->pict value-only 0) 'aligned)))
  (define mid-bytes
    (bitmap->argb-bytes (pict->bitmap (scene->pict value-only 1) 'aligned)))
  (define end-bytes
    (bitmap->argb-bytes (pict->bitmap (scene->pict value-only 2) 'aligned)))
  (check-equal? start-bytes mid-bytes)
  (check-equal? mid-bytes end-bytes)

  ;; Scalar and Visual animation share the same timeline without changing frame
  ;; geometry or deterministic frame output.
  (define mixed
    (scene-play
     base
     (animation-group
      (value-to 'alpha 10)
      (move-to 'dot (vec2 3 0)))
     #:duration 2))
  (for ([frame-index (in-range (scene-frame-count mixed #:fps 2))])
    (define bitmap (scene-frame->bitmap mixed frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 240)
    (check-equal? (send bitmap get-height) 160))
  (check-equal? (scene-value-at mixed 'alpha 1) 5)
  (check-equal? (visual-position (scene-state-ref (scene-sample mixed 1) 'dot))
                (vec2 3/2 0))

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-av-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define first-paths (render-frames! mixed temporary-directory #:fps 2))
      (define first-pass (for/list ([path (in-list first-paths)]) (file->bytes path)))
      (define second-paths (render-frames! mixed temporary-directory #:fps 2))
      (check-equal? first-pass
                    (for/list ([path (in-list second-paths)]) (file->bytes path))))
    (lambda ()
      (delete-directory/files temporary-directory))))
