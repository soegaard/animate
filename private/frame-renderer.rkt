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
         "render-color-context.rkt"
         "render-typography-context.rkt"
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
;               [#:theme color-theme?]
;               [#:typography typography-theme?]
;               -> pict?
;;   Converts the scene state at time using its camera or a static override.
;;   supersample increases raster resolution without changing the visible world.
(define (scene->pict scene time
                     #:camera [camera #f]
                     #:renderers [renderers default-pict-renderers]
                     #:supersample [supersample 1]
                     #:theme [theme #f]
                     #:color-context [color-context #f]
                     #:typography [typography #f]
                     #:typography-context [typography-context #f])
  (check-supersample 'scene->pict supersample)
  (define selected-color-context
    (select-frame-render-color-context 'scene->pict theme color-context))
  (define selected-typography-context
    (select-frame-render-typography-context
     'scene->pict typography typography-context))
  (cond
    [(not camera)
     (define-values (state sampled-camera)
       (scene-sample-with-camera scene time))
     (scene-state->prepared-pict
      state
      (camera-with-supersampling sampled-camera supersample)
      renderers #f selected-color-context selected-typography-context)]
    [(camera? camera)
     (scene-state->prepared-pict
      (scene-sample scene time)
      (camera-with-supersampling camera supersample)
      renderers #f selected-color-context selected-typography-context)]
    [else
     (raise-argument-error
      'scene->pict
      "(or/c camera? false/c)"
      camera)]))

;; Prepares every semantic ODE particle in this one immutable scene state
;; before adapters resolve visual relations.  This is the direct single-frame
;; counterpart of the batch preparation used by the PNG renderer.
(define (scene-state->prepared-pict state camera renderers prepared-layout
                                    color-context typography-context)
  (define (render-with-3d-samples)
    (if (ode3d-frame-samples-active?)
        (scene-state->pict state #:camera camera #:renderers renderers
                            #:color-context color-context
                            #:typography-context typography-context
                            #:prepared-label-layout prepared-layout)
        (call-with-ode3d-frame-samples
         (prepare-ode3d-frame-samples (list state))
         (lambda ()
           (scene-state->pict state #:camera camera #:renderers renderers
                               #:color-context color-context
                               #:typography-context typography-context
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
;                       [#:theme color-theme?]
;                       [#:typography typography-theme?]
;                       -> bitmap%
;;   Converts one in-range scene frame using its camera or a static override.
(define (scene-frame->bitmap scene frame-index
                             #:fps [fps 30]
                             #:camera [camera #f]
                             #:renderers [renderers default-pict-renderers]
                             #:supersample [supersample 1]
                             #:theme [theme #f]
                             #:color-context [color-context #f]
                             #:typography [typography #f]
                             #:typography-context [typography-context #f]
                             #:prepared-label-layout [prepared-layout #f])
  (check-supersample 'scene-frame->bitmap supersample)
  (define selected-color-context
    (select-frame-render-color-context
     'scene-frame->bitmap theme color-context))
  (define selected-typography-context
    (select-frame-render-typography-context
     'scene-frame->bitmap typography typography-context))
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
         (prepared-label-layout3d-ref prepared-layout frame-index))
    selected-color-context
    selected-typography-context)
   ;; Unlike 'aligned, 'smoothed does not adjust an animated Visual's
   ;; fractional pixel position to the device grid.  Cairo still antialiases
   ;; vector edges, while motion remains spatially continuous.
   'smoothed))


;;;
;;; Validation
;;;

;; select-frame-render-color-context : symbol? any/c any/c
;;                                      -> render-color-context?
;; Chooses the immutable context for a frame boundary.  This private helper
;; parallels the adapter's lower-level selector so `scene->pict` and
;; `scene-frame->bitmap` have the same unambiguous `#:theme` contract.
(define (select-frame-render-color-context who theme color-context)
  (when (and theme color-context)
    (raise-arguments-error
     who
     "at most one of #:theme or #:color-context"
     "theme" theme
     "color-context" color-context))
  (cond
    [color-context
     (unless (render-color-context? color-context)
       (raise-argument-error who "render-color-context? as #:color-context"
                             color-context))
     color-context]
    [theme (make-render-color-context theme)]
    [else (current-or-default-render-color-context)]))

;; The frame entry points keep color and typography selections separate: a
;; typography theme changes text roles, whereas `#:theme` remains the existing
;; color-theme argument for source compatibility.
(define (select-frame-render-typography-context who typography typography-context)
  (when (and typography typography-context)
    (raise-arguments-error
     who
     "at most one of #:typography or #:typography-context"
     "typography" typography
     "typography-context" typography-context))
  (cond
    [typography-context
     (unless (render-typography-context? typography-context)
       (raise-argument-error who
                             "render-typography-context? as #:typography-context"
                             typography-context))
     typography-context]
    [typography (make-render-typography-context typography)]
    [else (current-or-default-render-typography-context)]))

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
