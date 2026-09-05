#lang racket/base

;;;
;;; SCENE-AE Automatic Open-Path Morph Correspondence Rendering Tests
;;;

;; Tests adapter integration, exact endpoint rendering, fixed frame dimensions,
;; and deterministic repeated PNG output for automatically directed open morphs.


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
    (cubic-bezier-path
     (vec2 -5 -2)
     (list
      (cubic-bezier-path-segment
       (vec2 -4 3)
       (vec2 -1 3)
       (vec2 0 1))
      (cubic-bezier-path-segment
       (vec2 2 -3)
       (vec2 4 -2)
       (vec2 5 2)))))
  (define canonical-destination
    (cubic-bezier-path
     (vec2 -5 2)
     (list
      (cubic-bezier-path-segment
       (vec2 -3 4)
       (vec2 -1 -2)
       (vec2 0 -1))
      (cubic-bezier-path-segment
       (vec2 2 3)
       (vec2 4 4)
       (vec2 5 1)))))
  (define destination
    (path-geometry-reverse canonical-destination))
  (define panel
    (make-path-visual source
                      #:id 'panel
                      #:stroke "navy"
                      #:stroke-width 4))
  (define camera
    (make-camera #:width 300
                 #:height 200
                 #:world-width 14
                 #:background "white"))
  (define scene
    (scene-play
     (scene-add (make-scene #:camera camera) panel)
     (morph-to-open-aligned panel destination)
     #:duration 2))

  ;; Every sampled frame keeps the requested fixed pixel dimensions.
  (for ([frame-index (in-range (scene-frame-count scene #:fps 2))])
    (define bitmap
      (scene-frame->bitmap scene frame-index #:fps 2))
    (check-equal? (send bitmap get-width) 300)
    (check-equal? (send bitmap get-height) 200))

  ;; Exact progress one preserves the caller's stored reversed representation.
  (check-eq?
   (path-visual-path
    (scene-state-ref (scene-sample scene 2) 'panel))
   destination)

  ;; Repeated semantic sampling and bitmap conversion are deterministic.
  (check-equal?
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2))
   (bitmap->argb-bytes (scene-frame->bitmap scene 2 #:fps 2)))

  ;; Public PNG output remains byte-for-byte deterministic.
  (define temporary-directory
    (make-temporary-file "visual-animation-scene-ae-~a" 'directory))
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
