#lang racket/base

;;;
;;; Frame Renderer
;;;

;; Samples scenes into picts and bitmaps at deterministic frame times.
;;
;; This module performs no filesystem or process effects. PNG output and video
;; encoding belong in separate effect modules. When no static camera override
;; is supplied, each frame uses the camera stored in the scene timeline.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in pict pict->bitmap)
         "camera.rkt"
         "pict-adapter.rkt"
         "scene.rkt")

;; Exports
(provide scene->pict
         scene-frame-count
         frame-index->time
         scene-frame->bitmap)


;;;
;;; Scene Sampling
;;;

; scene->pict : scene? real?
;               [#:camera (or/c camera? false/c)]
;               [#:renderers (listof pict-renderer?)]
;               [#:supersample exact-positive-integer?]
;               -> pict?
;;   Converts the scene state at time using its camera or a static override.
;;   supersample increases raster resolution without changing the visible world.
(define (scene->pict scene time
                     #:camera [camera #f]
                     #:renderers [renderers default-pict-renderers]
                     #:supersample [supersample 1])
  (check-supersample 'scene->pict supersample)
  (cond
    [(not camera)
     (define-values (state sampled-camera)
       (scene-sample-with-camera scene time))
     (scene-state->pict state
                        #:camera (camera-with-supersampling sampled-camera supersample)
                        #:renderers renderers)]
    [(camera? camera)
     (scene-state->pict (scene-sample scene time)
                        #:camera (camera-with-supersampling camera supersample)
                        #:renderers renderers)]
    [else
     (raise-argument-error
      'scene->pict
      "(or/c camera? false/c)"
      camera)]))

; scene-frame-count : scene? [#:fps exact-positive-integer?]
;                     -> exact-nonnegative-integer?
;;   Returns the number of sampled frames needed for scene.
(define (scene-frame-count scene #:fps [fps 30])
  (unless (scene? scene)
    (raise-argument-error 'scene-frame-count "scene?" scene))
  (check-fps 'scene-frame-count fps)
  (define count
    (ceiling (* (scene-duration scene) fps)))
  (if (exact-integer? count)
      count
      (inexact->exact count)))

; frame-index->time : exact-nonnegative-integer?
;                     [#:fps exact-positive-integer?]
;                     -> nonnegative-real?
;;   Converts a zero-based frame index to its exact sample time.
(define (frame-index->time frame-index #:fps [fps 30])
  (check-fps 'frame-index->time fps)
  (unless (exact-nonnegative-integer? frame-index)
    (raise-argument-error
     'frame-index->time
     "exact-nonnegative-integer?"
     frame-index))
  (/ frame-index fps))

; scene-frame->bitmap : scene? exact-nonnegative-integer?
;                       [#:fps exact-positive-integer?]
;                       [#:camera (or/c camera? false/c)]
;                       [#:renderers (listof pict-renderer?)]
;                       [#:supersample exact-positive-integer?]
;                       -> bitmap%
;;   Converts one in-range scene frame using its camera or a static override.
(define (scene-frame->bitmap scene frame-index
                             #:fps [fps 30]
                             #:camera [camera #f]
                             #:renderers [renderers default-pict-renderers]
                             #:supersample [supersample 1])
  (define frame-count
    (scene-frame-count scene #:fps fps))
  (unless (and (exact-nonnegative-integer? frame-index)
               (< frame-index frame-count))
    (raise-arguments-error
     'scene-frame->bitmap
     "frame index is outside the scene"
     "frame-index" frame-index
     "frame-count" frame-count))
  (pict->bitmap
   (scene->pict scene
                (frame-index->time frame-index #:fps fps)
                #:camera camera
                #:renderers renderers
                #:supersample supersample)
   ;; Unlike 'aligned, 'smoothed does not adjust an animated Visual's
   ;; fractional pixel position to the device grid.  Cairo still antialiases
   ;; vector edges, while motion remains spatially continuous.
   'smoothed))


;;;
;;; Validation
;;;

; check-fps : symbol? any/c -> void?
;;   Raises an argument error unless fps is a positive exact integer.
(define (check-fps who fps)
  (unless (exact-positive-integer? fps)
    (raise-argument-error who "exact-positive-integer?" fps)))

; check-supersample : symbol? any/c -> void?
;;   Raises unless supersample is an integral raster-resolution multiplier.
(define (check-supersample who supersample)
  (unless (exact-positive-integer? supersample)
    (raise-argument-error who "exact-positive-integer?" supersample)))

; camera-with-supersampling : camera? exact-positive-integer? -> camera?
;;   Multiplies only camera raster dimensions. World-space geometry, camera
;;   view, and styling are unchanged, permitting clean later downsampling.
(define (camera-with-supersampling camera supersample)
  (if (= supersample 1)
      camera
      (make-camera #:width (* supersample (camera-width camera))
                   #:height (* supersample (camera-height camera))
                   #:world-width (camera-world-width camera)
                   #:center (camera-center camera)
                   #:background (camera-background camera))))
