#lang racket/base

;;;
;;; SCENE-AW Pure Derived Visual Rendering Tests
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
    (make-camera #:width 240 #:height 160 #:world-width 10 #:background "white"))
  (define reactive-dot
    (derived-visual
     (circle #:id 'dot
             #:center (vec2 -3 0)
             #:radius 1
             #:fill "royalblue"
             #:stroke "navy"
             #:stroke-width 3)
     (lambda (context template)
       (visual-with-position
        template
        (vec2 (derived-context-value-ref context 'x) 0)))))
  (define base
    (scene-add
     (scene-set-value (make-scene #:camera camera) 'x -3)
     reactive-dot))
  (check-exn exn:fail?
             (lambda () (visual->pict reactive-dot camera)))
  (define animated
    (scene-play base (value-to 'x 3) #:duration 2))

  ;; The same scalar machinery that was non-rendering in AV now drives a pure
  ;; resolved Visual at render time.
  (define start-bitmap (pict->bitmap (scene->pict animated 0) 'aligned))
  (define mid-bitmap (pict->bitmap (scene->pict animated 1) 'aligned))
  (define end-bitmap (pict->bitmap (scene->pict animated 2) 'aligned))
  (for ([bitmap (in-list (list start-bitmap mid-bitmap end-bitmap))])
    (check-equal? (send bitmap get-width) 240)
    (check-equal? (send bitmap get-height) 160))
  (define start-bytes (bitmap->argb-bytes start-bitmap))
  (define mid-bytes (bitmap->argb-bytes mid-bitmap))
  (define end-bytes (bitmap->argb-bytes end-bitmap))
  (check-false (bytes=? start-bytes mid-bytes))
  (check-false (bytes=? mid-bytes end-bytes))
  (check-false (bytes=? start-bytes end-bytes))

  ;; camera-follow can follow the resolved derived target. With no other world
  ;; content, keeping the dot at its initial frame position yields identical
  ;; start/end pixels while the semantic world position and camera both move.
  (define followed
    (scene-play
     base
     (value-to 'x 3)
     (camera-follow 'dot)
     #:duration 2))
  (check-equal? (visual-position
                 (scene-state-resolved-ref (scene-sample followed 1) 'dot))
                origin)
  (check-equal? (camera-center (scene-camera-at followed 1)) (vec2 3 0))
  (check-equal? (visual-position
                 (scene-state-resolved-ref (scene-sample followed 2) 'dot))
                (vec2 3 0))
  (check-equal? (camera-center (scene-camera-at followed 2)) (vec2 6 0))
  (check-equal?
   (bitmap->argb-bytes (pict->bitmap (scene->pict followed 0) 'aligned))
   (bitmap->argb-bytes (pict->bitmap (scene->pict followed 2) 'aligned)))

  ;; Repeated frame rendering remains byte-identical because derivation is pure
  ;; state sampling, not frame-order mutation.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-aw-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define first-paths
        (render-frames! animated temporary-directory #:fps 3))
      (define first-pass
        (for/list ([path (in-list first-paths)])
          (file->bytes path)))
      (define second-paths
        (render-frames! animated temporary-directory #:fps 3))
      (check-equal? first-pass
                    (for/list ([path (in-list second-paths)])
                      (file->bytes path))))
    (lambda ()
      (delete-directory/files temporary-directory))))
