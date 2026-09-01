#lang racket/base

;;;
;;; SCENE-AF Automatic Open-Compound Morph Correspondence Rendering Tests
;;;

;; Tests open-compound aligned-morph rendering, exact endpoint state, fixed frame
;; dimensions, and deterministic repeated public PNG output.

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

  (define left-source
    (cubic-bezier-path
     (vec2 -7 -2)
     (list
      (cubic-bezier-path-segment
       (vec2 -6 3)
       (vec2 -4 3)
       (vec2 -3 -1)))))
  (define right-source
    (cubic-bezier-path
     (vec2 2 2)
     (list
      (cubic-bezier-path-segment
       (vec2 4 -3)
       (vec2 6 -2)
       (vec2 7 2)))))
  (define source
    (combine-paths left-source right-source))

  (define left-destination
    (cubic-bezier-path
     (vec2 -7 1)
     (list
      (cubic-bezier-path-segment
       (vec2 -6 -3)
       (vec2 -4 -2)
       (vec2 -2 2)))))
  (define right-destination
    (cubic-bezier-path
     (vec2 2 -2)
     (list
      (cubic-bezier-path-segment
       (vec2 3 3)
       (vec2 6 4)
       (vec2 7 0)))))
  ;; Store right first and reverse both directions on purpose.
  (define destination
    (combine-paths
     (path-geometry-reverse right-destination)
     (path-geometry-reverse left-destination)))

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
                             #:world-width 20
                             #:background "white"))
      panel)
     (morph-to-open-compound-aligned panel destination #:sample-count 24)
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
    (make-temporary-file "visual-animation-scene-af-~a" 'directory))
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
