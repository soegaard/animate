#lang racket/base

;;;
;;; SCENE-AJ Penalized Topology-Changing Morph Rendering Tests
;;;

;; Compares forced correspondence with penalty-driven local death+birth and
;; checks fixed frame dimensions, exact final state, and deterministic PNG output.

(require racket/class
         racket/file
         rackunit
         "../main.rkt")

(module+ test
  (define (bitmap->argb-bytes bitmap)
    (define width (send bitmap get-width))
    (define height (send bitmap get-height))
    (define pixels (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  (define source
    (polyline-path (list (vec2 -8 0) (vec2 -6 0))))
  (define destination
    (polyline-path (list (vec2 6 0) (vec2 8 0))))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 6))
  (define camera
    (make-camera #:width 360
                 #:height 240
                 #:world-width 22
                 #:background "white"))
  (define base-scene
    (scene-add (make-scene #:camera camera) panel))
  (define forced-scene
    (scene-play
     base-scene
     (morph-to-topology-changing panel destination #:sample-count 8)
     #:duration 2))
  (define penalized-scene
    (scene-play
     base-scene
     (morph-to-topology-changing
      panel
      destination
      #:sample-count 8
      #:birth-penalty 2
      #:death-penalty 2)
     #:duration 2))

  (for ([frame-index (in-range (scene-frame-count penalized-scene #:fps 2))])
    (define bitmap
      (scene-frame->bitmap penalized-scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 360)
    (check-equal? (send bitmap get-height) 240))

  ;; At the midpoint the forced policy sweeps one line through the center, while
  ;; the penalized policy contains a dying local slot and a separately born slot.
  (check-equal?
   (length
    (path-geometry-subpaths
     (path-visual-path
      (scene-state-ref (scene-sample forced-scene 1) 'panel))))
   1)
  (check-equal?
   (length
    (path-geometry-subpaths
     (path-visual-path
      (scene-state-ref (scene-sample penalized-scene 1) 'panel))))
   2)
  (check-false
   (equal?
    (bitmap->argb-bytes
     (scene-frame->bitmap forced-scene 2 #:fps 2))
    (bitmap->argb-bytes
     (scene-frame->bitmap penalized-scene 2 #:fps 2))))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample penalized-scene 2) 'panel))
   destination)

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-aj-~a" 'directory))
  (dynamic-wind
    void
    (lambda ()
      (define first-paths
        (render-frames! penalized-scene temporary-directory #:fps 2))
      (define first-pass
        (for/list ([path (in-list first-paths)])
          (file->bytes path)))
      (define second-paths
        (render-frames! penalized-scene temporary-directory #:fps 2))
      (check-equal?
       first-pass
       (for/list ([path (in-list second-paths)])
         (file->bytes path))))
    (lambda ()
      (delete-directory/files temporary-directory))))
