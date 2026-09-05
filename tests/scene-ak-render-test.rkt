#lang racket/base

;;;
;;; SCENE-AK Per-Subpath Anchor Map Rendering Tests
;;;

;; Verifies that two independently anchored birth/death slots differ from the
;; shared-anchor fallback, preserve fixed dimensions/exact endpoints, and emit
;; deterministic repeated PNG output through the public renderer API.

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
     (polyline-path (list (vec2 -9 3) (vec2 -6 5) (vec2 -3 3)))
     (polyline-path (list (vec2 3 3) (vec2 6 5) (vec2 9 3)))))
  (define destination
    (combine-paths
     (polygon-path
      (list (vec2 -9 -5) (vec2 -6 -6) (vec2 -3 -4) (vec2 -5 -1)))
     (polygon-path
      (list (vec2 3 -5) (vec2 6 -6) (vec2 9 -4) (vec2 7 -1)))))
  (define left-anchor (vec2 -6 0))
  (define right-anchor (vec2 6 0))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define left-marker
    (point-marker #:id 'left-anchor
                  #:center left-anchor
                  #:shape 'diamond
                  #:size 2/5
                  #:fill "firebrick"
                  #:stroke "firebrick"))
  (define right-marker
    (point-marker #:id 'right-anchor
                  #:center right-anchor
                  #:shape 'diamond
                  #:size 2/5
                  #:fill "navy"
                  #:stroke "navy"))
  (define camera
    (make-camera #:width 360
                 #:height 280
                 #:world-width 24
                 #:background "white"))
  (define base-scene
    (scene-add (make-scene #:camera camera) panel left-marker right-marker))
  (define mapped-scene
    (scene-play
     base-scene
     (morph-to-topology-changing
      panel
      destination
      #:birth-anchor origin
      #:death-anchor origin
      #:birth-anchor-map (hash 0 left-anchor 1 right-anchor)
      #:death-anchor-map (hash 0 left-anchor 1 right-anchor))
     #:duration 2))
  (define shared-scene
    (scene-play
     base-scene
     (morph-to-topology-changing
      panel
      destination
      #:birth-anchor origin
      #:death-anchor origin)
     #:duration 2))

  (for ([frame-index (in-range (scene-frame-count mapped-scene #:fps 2))])
    (define bitmap (scene-frame->bitmap mapped-scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 360)
    (check-equal? (send bitmap get-height) 280))

  ;; Two source deaths plus two destination births yield four interior slots.
  (check-equal?
   (length
    (path-geometry-subpaths
     (path-visual-path
      (scene-state-ref (scene-sample mapped-scene 1) 'panel))))
   4)
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample mapped-scene 2) 'panel))
   destination)

  ;; Per-subpath map placement materially differs from one shared central hub.
  (check-false
   (equal?
    (bitmap->argb-bytes (scene-frame->bitmap mapped-scene 2 #:fps 2))
    (bitmap->argb-bytes (scene-frame->bitmap shared-scene 2 #:fps 2))))
  (check-equal?
   (bitmap->argb-bytes (scene-frame->bitmap mapped-scene 2 #:fps 2))
   (bitmap->argb-bytes (scene-frame->bitmap mapped-scene 2 #:fps 2)))

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-ak-~a" 'directory))
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
