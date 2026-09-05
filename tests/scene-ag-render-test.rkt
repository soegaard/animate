#lang racket/base

;;;
;;; SCENE-AG Mixed-Topology Compound Morph Correspondence Rendering Tests
;;;

;; Tests topology-aware aligned-morph rendering, exact endpoint state, fixed
;; frame dimensions, and deterministic repeated public PNG output.

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

  (define (combine-paths . geometries)
    (path-geometry
     (apply append
            (for/list ([geometry (in-list geometries)])
              (path-geometry-subpaths geometry)))))

  (define open-left
    (cubic-bezier-path
     (vec2 -8 -2)
     (list
      (cubic-bezier-path-segment
       (vec2 -7 3)
       (vec2 -5 3)
       (vec2 -4 -1)))))
  (define closed-left
    (polygon-path
     (list (vec2 -3 -3) (vec2 0 -3) (vec2 0 0) (vec2 -3 0))))
  (define open-right
    (polyline-path
     (list (vec2 2 2) (vec2 4 -2) (vec2 7 1))))
  (define closed-right
    (polygon-path
     (list (vec2 4 3) (vec2 7 3) (vec2 8 5) (vec2 5 6))))
  (define source
    (combine-paths open-left closed-left open-right closed-right))
  (define destination
    (combine-paths
     (path-geometry-reverse open-right)
     (path-geometry-cycle-start (path-geometry-reverse closed-right) 1/3)
     (path-geometry-reverse open-left)
     (path-geometry-cycle-start (path-geometry-reverse closed-left) 1/4)))

  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "navy"
                      #:stroke-width 5))
  (define scene
    (scene-play
     (scene-add
      (make-scene
       #:camera (make-camera #:width 320
                             #:height 240
                             #:world-width 22
                             #:background "white"))
      panel)
     (morph-to-mixed-compound-aligned panel destination #:sample-count 24)
     #:duration 2))

  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 320)
    (check-equal? (send bitmap get-height) 240))

  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample scene 2) 'panel))
   destination)

  (check-equal?
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2))
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2)))

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-ag-~a" 'directory))
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
