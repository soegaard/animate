#lang racket/base

;;;
;;; SCENE-AM Per-Pair Match Penalty Rendering Tests
;;;

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

  (define (combine-paths . geometries)
    (path-geometry
     (apply append
            (for/list ([geometry (in-list geometries)])
              (path-geometry-subpaths geometry)))))

  (define source
    (combine-paths
     (cubic-bezier-path
      (vec2 -5 3)
      (list (cubic-bezier-path-segment
             (vec2 -2 5) (vec2 2 5) (vec2 5 3))))
     (cubic-bezier-path
      (vec2 -5 -3)
      (list (cubic-bezier-path-segment
             (vec2 -2 -5) (vec2 2 -5) (vec2 5 -3))))))
  ;; The final rendered set is identical to the source. With no pair penalty the
  ;; morph is therefore visually stationary; penalizing source 0 -> destination
  ;; 0 forces the two real subpaths to exchange correspondence in the interior.
  (define destination
    (combine-paths
     (cubic-bezier-path
      (vec2 -5 3)
      (list (cubic-bezier-path-segment
             (vec2 -2 5) (vec2 2 5) (vec2 5 3))))
     (cubic-bezier-path
      (vec2 -5 -3)
      (list (cubic-bezier-path-segment
             (vec2 -2 -5) (vec2 2 -5) (vec2 5 -3))))))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "seagreen"
                      #:stroke-width 6))
  (define camera
    (make-camera #:width 360
                 #:height 260
                 #:world-width 16
                 #:background "white"))
  (define base-scene
    (scene-add (make-scene #:camera camera) panel))
  (define default-scene
    (scene-play
     base-scene
     (morph-to-topology-changing panel destination #:sample-count 16)
     #:duration 2))
  (define mapped-scene
    (scene-play
     base-scene
     (morph-to-topology-changing
      panel destination
      #:sample-count 16
      #:match-penalty-map (hash (cons 0 0) 1000))
     #:duration 2))

  (for ([frame-index (in-range (scene-frame-count mapped-scene #:fps 2))])
    (define bitmap (scene-frame->bitmap mapped-scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 360)
    (check-equal? (send bitmap get-height) 260))

  (check-false
   (equal?
    (bitmap->argb-bytes (scene-frame->bitmap default-scene 2 #:fps 2))
    (bitmap->argb-bytes (scene-frame->bitmap mapped-scene 2 #:fps 2))))
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample mapped-scene 2) 'panel))
   destination)

  (define temporary-directory
    (make-temporary-file "visual-animation-scene-am-~a" 'directory))
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
