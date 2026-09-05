#lang racket/base
(require "../experimental.rkt")

;;;
;;; SCENE-AX Dependency-Driven Derived Geometry Rendering Tests
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
    (make-camera #:width 260 #:height 180 #:world-width 12 #:background "white"))

  ;; The source is an ordinary animated Visual. The halo depends on the source,
  ;; and the tag depends on the halo, making rendering exercise a three-level
  ;; state/dependency chain. Drawing order deliberately places both dependents
  ;; before their source.
  (define source
    (circle #:id 'source
            #:center (vec2 -3 0)
            #:radius 3/5
            #:fill "royalblue"
            #:stroke "navy"
            #:stroke-width 3))
  (define halo
    (derived-visual
     (circle #:id 'halo
             #:center origin
             #:radius 1
             #:fill #f
             #:stroke "gold"
             #:stroke-width 4)
     (lambda (context template)
       (visual-with-position
        template
        (visual-position (derived-context-visual-ref context 'source))))))
  (define tag
    (derived-visual
     (rectangle #:id 'tag
                #:center origin
                #:width 6/5
                #:height 3/5
                #:fill "tomato"
                #:stroke "darkred"
                #:stroke-width 2)
     (lambda (context template)
       (visual-with-position
        template
        (vec2+ (visual-position (derived-context-visual-ref context 'halo))
               (vec2 0 3/2))))))

  (define base
    (scene-add (make-scene #:camera camera) halo tag source))
  (define animated
    (scene-play base (move-to 'source (vec2 3 0)) #:duration 2))

  (define start-bitmap (pict->bitmap (scene->pict animated 0) 'aligned))
  (define mid-bitmap (pict->bitmap (scene->pict animated 1) 'aligned))
  (define end-bitmap (pict->bitmap (scene->pict animated 2) 'aligned))
  (for ([bitmap (in-list (list start-bitmap mid-bitmap end-bitmap))])
    (check-equal? (send bitmap get-width) 260)
    (check-equal? (send bitmap get-height) 180))
  (define start-bytes (bitmap->argb-bytes start-bitmap))
  (define mid-bytes (bitmap->argb-bytes mid-bitmap))
  (define end-bytes (bitmap->argb-bytes end-bitmap))
  (check-false (bytes=? start-bytes mid-bytes))
  (check-false (bytes=? mid-bytes end-bytes))
  (check-false (bytes=? start-bytes end-bytes))

  ;; Repeated rendering remains deterministic even though dependencies are
  ;; resolved recursively. Memoization is local to one traversal only.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-ax-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define first-paths
        (render-frames! animated temporary-directory #:fps 4))
      (define first-pass
        (for/list ([path (in-list first-paths)])
          (file->bytes path)))
      (define second-paths
        (render-frames! animated temporary-directory #:fps 4))
      (check-equal?
       first-pass
       (for/list ([path (in-list second-paths)])
         (file->bytes path))))
    (lambda ()
      (delete-directory/files temporary-directory))))
