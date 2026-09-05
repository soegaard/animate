#lang racket/base

;;;
;;; SCENE-AL Per-Subpath Penalty Map Rendering Tests
;;;

;; Compares shared AJ costs against original-index cost overrides, checks fixed
;; dimensions/exact endpoints, and verifies deterministic repeated PNG output.

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

  (define source
    (combine-paths
     (polyline-path (list (vec2 -8 3) (vec2 -6 3)))
     (polyline-path (list (vec2 -8 -3) (vec2 -6 -3)))))
  ;; Deliberately store bottom first, top second.
  (define destination
    (combine-paths
     (polyline-path (list (vec2 6 -3) (vec2 8 -3)))
     (polyline-path (list (vec2 6 3) (vec2 8 3)))))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 6))
  (define camera
    (make-camera #:width 360
                 #:height 260
                 #:world-width 22
                 #:background "white"))
  (define base-scene
    (scene-add (make-scene #:camera camera) panel))
  (define shared-scene
    (scene-play
     base-scene
     (morph-to-topology-changing
      panel destination
      #:sample-count 8
      #:birth-penalty 2
      #:death-penalty 2)
     #:duration 2))
  (define mapped-scene
    (scene-play
     base-scene
     (morph-to-topology-changing
      panel destination
      #:sample-count 8
      #:birth-penalty 2
      #:death-penalty 2
      #:birth-penalty-map (hash 1 20)
      #:death-penalty-map (hash 0 20))
     #:duration 2))

  (for ([frame-index (in-range (scene-frame-count mapped-scene #:fps 2))])
    (define bitmap (scene-frame->bitmap mapped-scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 360)
    (check-equal? (send bitmap get-height) 260))

  ;; Shared low costs replace both pairs (four slots); the sparse cost maps keep
  ;; the top real pair and replace only the bottom (three slots).
  (check-equal?
   (length
    (path-geometry-subpaths
     (path-visual-path
      (scene-state-ref (scene-sample shared-scene 1) 'panel))))
   4)
  (check-equal?
   (length
    (path-geometry-subpaths
     (path-visual-path
      (scene-state-ref (scene-sample mapped-scene 1) 'panel))))
   3)
  (check-false
   (equal?
    (bitmap->argb-bytes (scene-frame->bitmap shared-scene 2 #:fps 2))
    (bitmap->argb-bytes (scene-frame->bitmap mapped-scene 2 #:fps 2))))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample mapped-scene 2) 'panel))
   destination)

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-al-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define first-paths
        (render-frames! mapped-scene temporary-directory #:fps 2))
      (define first-pass
        (for/list ([path (in-list first-paths)])
          (file->bytes path)))
      (define second-paths
        (render-frames! mapped-scene temporary-directory #:fps 2))
      (check-equal?
       first-pass
       (for/list ([path (in-list second-paths)])
         (file->bytes path))))
    (lambda ()
      (delete-directory/files temporary-directory))))
