#lang racket/base

;;;
;;; SCENE-AD Automatic Compound Morph Correspondence Rendering Tests
;;;

;; Tests compound aligned-morph rendering, exact endpoint state, fixed frame
;; dimensions, and deterministic repeated public PNG output.

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

  (define outer-source
    (polygon-path
     (list (vec2 -5 -3)
           (vec2 4 -4)
           (vec2 6 1)
           (vec2 2 5)
           (vec2 -4 4)
           (vec2 -6 0))))
  (define inner-source
    (polygon-path
     (list (vec2 -2 -1)
           (vec2 0 -2)
           (vec2 2 0)
           (vec2 0 2))))
  (define source
    (combine-paths outer-source inner-source))

  (define outer-destination
    (polygon-path
     (list (vec2 -6 -2)
           (vec2 3 -5)
           (vec2 7 0)
           (vec2 3 5)
           (vec2 -3 5)
           (vec2 -7 1))))
  (define inner-destination
    (polygon-path
     (list (vec2 -2 0)
           (vec2 0 -5/2)
           (vec2 5/2 0)
           (vec2 0 2))))
  ;; Reverse storage order and independently disturb loop direction/phase.
  (define destination
    (combine-paths
     (path-geometry-cycle-start
      (path-geometry-reverse inner-destination) 1/3)
     (path-geometry-cycle-start outer-destination 2/5)))

  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:fill "lightsteelblue"
                      #:stroke "navy"
                      #:stroke-width 4))
  (define scene
    (scene-play
     (scene-add
      (make-scene
       #:camera (make-camera #:width 320
                             #:height 240
                             #:world-width 18
                             #:background "white"))
      panel)
     (morph-to-compound-aligned panel destination #:sample-count 16)
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
    (make-temporary-file "visual-animation-scene-ad-~a" 'directory))
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
