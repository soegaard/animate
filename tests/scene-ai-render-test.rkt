#lang racket/base

;;;
;;; SCENE-AI Explicit Birth/Death Anchor Rendering Tests
;;;

;; Tests rendered custom-anchor interpolation, fixed dimensions, exact final
;; representation, and deterministic repeated public PNG output.

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

  (define matched-source
    (polyline-path
     (list (vec2 -8 3) (vec2 -4 5) (vec2 0 3))))
  (define dying-source
    (polyline-path
     (list (vec2 -8 -4) (vec2 -4 -6) (vec2 0 -4))))
  (define matched-destination
    (path-geometry-reverse
     (cubic-bezier-path
      (vec2 -8 2)
      (list
       (cubic-bezier-path-segment
        (vec2 -5 6) (vec2 -1 5) (vec2 1 2))))))
  (define born-destination
    (polygon-path
     (list (vec2 3 -5) (vec2 8 -5) (vec2 9 -1)
           (vec2 6 1) (vec2 3 -1))))
  (define source (combine-paths matched-source dying-source))
  (define destination (combine-paths matched-destination born-destination))
  (define anchor origin)

  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 5))
  (define marker
    (point-marker #:id 'anchor
                  #:center anchor
                  #:shape 'diamond
                  #:size 2/5
                  #:fill "firebrick"
                  #:stroke "firebrick"
                  #:stroke-width 1))
  (define camera
    (make-camera #:width 360
                 #:height 280
                 #:world-width 24
                 #:background "white"))
  (define scene
    (scene-play
     (scene-add (make-scene #:camera camera) panel marker)
     (morph-to-topology-changing
      panel
      destination
      #:sample-count 24
      #:birth-anchor anchor
      #:death-anchor anchor)
     #:duration 2))
  (define default-scene
    (scene-play
     (scene-add (make-scene #:camera camera) panel marker)
     (morph-to-topology-changing panel destination #:sample-count 24)
     #:duration 2))

  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 360)
    (check-equal? (send bitmap get-height) 280))

  ;; The midpoint contains one dying open slot and one born closed slot, both
  ;; seeded at the same explicit local anchor.
  (define midpoint-path
    (path-visual-path
     (scene-state-ref (scene-sample scene 1) 'panel)))
  (check-equal? (length (path-geometry-subpaths midpoint-path)) 3)
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample scene 2) 'panel))
   destination)

  ;; The explicit hub materially changes the interior rendered geometry from
  ;; SCENE-AH's default per-subpath bounds-center seeds.
  (check-false
   (equal?
    (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2))
    (bitmap->argb-bytes (scene-frame->bitmap default-scene 2 #:fps 2))))

  (check-equal?
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2))
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2)))

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-ai-~a" 'directory))
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
