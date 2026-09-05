#lang racket/base

;;;
;;; SCENE-AH Topology-Changing Morph Rendering Tests
;;;

;; Tests rendered birth/death interpolation, fixed frame dimensions, exact
;; endpoint state, and deterministic repeated public PNG output.

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

  (define source-loop
    (polygon-path
     (list (vec2 -7 -2) (vec2 -3 -2) (vec2 -3 2) (vec2 -7 2))))
  (define source-open-match
    (cubic-bezier-path
     (vec2 0 2)
     (list
      (cubic-bezier-path-segment
       (vec2 2 5) (vec2 6 4) (vec2 8 1)))))
  (define source-open-death
    (polyline-path
     (list (vec2 0 -4) (vec2 3 -6) (vec2 7 -4))))
  (define source
    (combine-paths source-loop source-open-match source-open-death))

  (define destination-loop
    (path-geometry-cycle-start
     (path-geometry-reverse
      (polygon-path
       (list (vec2 -8 -2) (vec2 -5 -4) (vec2 -2 -1)
             (vec2 -3 3) (vec2 -7 3))))
     1/5))
  (define destination-open-match
    (path-geometry-reverse
     (cubic-bezier-path
      (vec2 0 1)
      (list
       (cubic-bezier-path-segment
        (vec2 2 5) (vec2 6 6) (vec2 9 2))))))
  (define destination-loop-birth
    (polygon-path
     (list (vec2 2 -5) (vec2 5 -6) (vec2 8 -4)
           (vec2 7 -1) (vec2 3 -1))))
  (define destination
    (combine-paths
     destination-open-match
     destination-loop-birth
     destination-loop))

  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define scene
    (scene-play
     (scene-add
      (make-scene
       #:camera (make-camera #:width 360
                             #:height 280
                             #:world-width 24
                             #:background "white"))
      panel)
     (morph-to-topology-changing panel destination #:sample-count 24)
     #:duration 2))

  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 360)
    (check-equal? (send bitmap get-height) 280))

  ;; The midpoint has four interior slots: two real matches, one dying open
  ;; subpath, and one born closed subpath.
  (check-equal?
   (length
    (path-geometry-subpaths
     (path-visual-path
      (scene-state-ref (scene-sample scene 1) 'panel))))
   4)
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample scene 2) 'panel))
   destination)

  (check-equal?
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2))
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2)))

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-ah-~a" 'directory))
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
