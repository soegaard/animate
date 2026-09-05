#lang racket/base

;;;
;;; SCENE-AC Automatic Morph Correspondence Rendering Tests
;;;

;; Tests adapter integration, exact endpoint rendering, fixed frame dimensions,
;; and deterministic repeated PNG output for automatically aligned loop morphs.


;;;
;;; Imports
;;;

(require racket/class
         racket/file
         rackunit
         "../main.rkt"
         "../render.rkt")


(module+ test
  ; bitmap->argb-bytes : bitmap% -> bytes?
  ;;   Returns exact rendered pixels for deterministic comparisons.
  (define (bitmap->argb-bytes bitmap)
    (define width
      (send bitmap get-width))
    (define height
      (send bitmap get-height))
    (define pixels
      (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  (define source
    (polygon-path
     (list (vec2 -4 -1)
           (vec2 -2 2)
           (vec2 1 3)
           (vec2 4 1)
           (vec2 3 -2)
           (vec2 -1 -3))))
  (define destination
    (polygon-path
     (list (vec2 4 2)
           (vec2 4 -1)
           (vec2 0 -5/2)
           (vec2 -7/2 -3/2)
           (vec2 -5/2 3/2)
           (vec2 0 7/2))))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:fill "cornflowerblue"
                      #:stroke "navy"
                      #:stroke-width 4))
  (define camera
    (make-camera #:width 300
                 #:height 200
                 #:world-width 12
                 #:background "white"))
  (define scene
    (scene-play
     (scene-add (make-scene #:camera camera) panel)
     (morph-to-aligned panel destination)
     #:duration 2))

  ;; Every sampled frame keeps the requested fixed pixel dimensions and renders
  ;; through the ordinary path backend. scene-frame->bitmap consumes frame
  ;; indices, not scene times, so sample a small valid frame lattice directly.
  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap
      (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 300)
    (check-equal? (send bitmap get-height) 200))

  ;; Exact progress one renders the exact requested destination representation.
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample scene 2) 'panel))
   destination)

  ;; Repeated semantic sampling and bitmap conversion are deterministic.
  (check-equal?
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2))
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2)))

  ;; Repeated public PNG rendering is byte-for-byte deterministic as well.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-ac-~a" 'directory))
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
