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
         "ode-flow.rkt"
         "pict-adapter.rkt"
         "scene-frame-grid.rkt"
         "scene.rkt"
         "3d/label-layout-preparation3d.rkt"
         "3d/ode-flow3d.rkt")

;; Exports
(provide scene->pict
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
     (scene-state->prepared-pict
      state
      (camera-with-supersampling sampled-camera supersample)
      renderers #f)]
    [(camera? camera)
     (scene-state->prepared-pict
      (scene-sample scene time)
      (camera-with-supersampling camera supersample)
      renderers #f)]
    [else
     (raise-argument-error
      'scene->pict
      "(or/c camera? false/c)"
      camera)]))

;; Prepares every semantic ODE particle in this one immutable scene state
;; before adapters resolve visual relations.  This is the direct single-frame
;; counterpart of the batch preparation used by the PNG renderer.
(define (scene-state->prepared-pict state camera renderers prepared-layout)
  (define (render-with-3d-samples)
    (if (ode3d-frame-samples-active?)
        (scene-state->pict state #:camera camera #:renderers renderers
                            #:prepared-label-layout prepared-layout)
        (call-with-ode3d-frame-samples
         (prepare-ode3d-frame-samples (list state))
         (lambda ()
           (scene-state->pict state #:camera camera #:renderers renderers
                               #:prepared-label-layout prepared-layout)))))
  (if (ode-frame-samples-active?)
      (render-with-3d-samples)
      (call-with-ode-frame-samples
       (prepare-ode-frame-samples (list state))
       render-with-3d-samples)))

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
                             #:supersample [supersample 1]
                             #:prepared-label-layout [prepared-layout #f])
  (check-supersample 'scene-frame->bitmap supersample)
  (unless (or (not camera) (camera? camera))
    (raise-argument-error
     'scene-frame->bitmap
     "(or/c camera? false/c) as #:camera"
     camera))
  (define frame-count
    (scene-frame-count scene #:fps fps))
  (unless (and (exact-nonnegative-integer? frame-index)
               (< frame-index frame-count))
    (raise-arguments-error
     'scene-frame->bitmap
     "frame index is outside the scene"
     "frame-index" frame-index
    "frame-count" frame-count))
  (unless (or (not prepared-layout) (prepared-label-layout3d? prepared-layout))
    (raise-argument-error
     'scene-frame->bitmap
     "#f or prepared-label-layout3d? as #:prepared-label-layout"
     prepared-layout))
  (define time (frame-index->time frame-index #:fps fps))
  (define-values (state sampled-camera)
    (if camera
        (values (scene-sample scene time) camera)
        (scene-sample-with-camera scene time)))
  (pict->bitmap
   (scene-state->prepared-pict
    state
    (camera-with-supersampling sampled-camera supersample)
    renderers
    (and prepared-layout
         (prepared-label-layout3d-ref prepared-layout frame-index)))
   ;; Unlike 'aligned, 'smoothed does not adjust an animated Visual's
   ;; fractional pixel position to the device grid.  Cairo still antialiases
   ;; vector edges, while motion remains spatially continuous.
   'smoothed))


;;;
;;; Validation
;;;

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
