#lang racket/base

;;;
;;; Camera Framing
;;;

;; Converts renderer-aware layout boxes into deterministic camera-fit requests.
;;
;; This module belongs at the Pict-adapter boundary because fitting text,
;; formulas, groups, and custom Visuals requires their rendered dimensions.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "camera-animation.rkt"
         "camera.rkt"
         "frame-space.rkt"
         "geometry.rkt"
         "pict-renderer.rkt"
         "relative-layout.rkt"
         "scene-state.rkt"
         "scene.rkt"
         "shape-pict-renderers.rkt"
         "visual-model.rkt")

;; Exports
(provide camera-fit-layout-box
         camera-fit-visuals
         camera-fit-scene)


;;;
;;; Layout-Box Fitting
;;;

; camera-fit-layout-box : layout-box?
;                         [#:camera camera?]
;                         [#:padding nonnegative-real?]
;                         -> camera-fit-request?
;;   Creates a request that fits box inside the camera with equal-side padding.
(define (camera-fit-layout-box box
                               #:camera [camera default-camera]
                               #:padding [padding 1/2])
  (unless (layout-box? box)
    (raise-argument-error 'camera-fit-layout-box "layout-box?" box))
  (unless (camera? camera)
    (raise-argument-error 'camera-fit-layout-box "camera?" camera))
  (check-camera-fit-padding 'camera-fit-layout-box padding)
  (define box-width
    (layout-box-width box))
  (define box-height
    (layout-box-height box))
  (unless (and (finite-real? box-width)
               (finite-real? box-height))
    (raise-arguments-error
     'camera-fit-layout-box
     "the layout-box dimensions must remain finite"
     "layout-box" box
     "layout-box-width" box-width
     "layout-box-height" box-height))
  (define padded-width
    (+ box-width (* 2 padding)))
  (define padded-height
    (+ box-height (* 2 padding)))
  (unless (and (finite-real? padded-width)
               (finite-real? padded-height))
    (raise-arguments-error
     'camera-fit-layout-box
     "the padded layout-box dimensions must remain finite"
     "layout-box" box
     "padding" padding
     "padded-width" padded-width
     "padded-height" padded-height))
  (define frame-aspect
    (/ (camera-width camera)
       (camera-height camera)))
  (define fitted-world-width
    (max padded-width
         (* padded-height frame-aspect)))
  (unless (and (finite-real? fitted-world-width)
               (positive? fitted-world-width))
    (raise-arguments-error
     'camera-fit-layout-box
     "the fitted camera width must be positive and finite"
     "layout-box" box
     "padding" padding
     "result" fitted-world-width))
  (define center
    (vec2 (+ (layout-box-left box) (/ box-width 2))
          (+ (layout-box-bottom box) (/ box-height 2))))
  (make-camera-fit-request center fitted-world-width))


;;;
;;; Visual Fitting
;;;

; camera-fit-visuals : (and/c (listof visual?) pair?)
;                      [#:camera camera?]
;                      [#:renderers (listof pict-renderer?)]
;                      [#:padding nonnegative-real?]
;                      -> camera-fit-request?
;;   Creates a request that fits the union of the supplied rendered Visuals.
(define (camera-fit-visuals visuals
                            #:camera [camera default-camera]
                            #:renderers [renderers default-pict-renderers]
                            #:padding [padding 1/2])
  (check-nonempty-world-visual-list 'camera-fit-visuals visuals)
  (define box
    (visuals-layout-box visuals
                        #:camera camera
                        #:renderers renderers))
  (camera-fit-layout-box box
                         #:camera camera
                         #:padding padding))

; camera-fit-scene : scene?
;                    [#:targets
;                     (or/c false/c
;                           (and/c
;                            (listof (or/c visual? symbol?))
;                            pair?))]
;                    [#:renderers (listof pict-renderer?)]
;                    [#:padding nonnegative-real?]
;                    -> camera-fit-request?
;;   Creates a request that fits current top-level scene targets or all Visuals.
(define (camera-fit-scene scn
                          #:targets [targets #f]
                          #:renderers [renderers default-pict-renderers]
                          #:padding [padding 1/2])
  (unless (scene? scn)
    (raise-argument-error 'camera-fit-scene "scene?" scn))
  (define state
    (scene-current-state scn))
  (define visuals
    (cond
      [(not targets)
       (filter (lambda (visual)
                 (not (frame-space-visual? visual)))
               (scene-state-resolved-visuals-in-drawing-order state))]
      [else
       (check-camera-fit-targets 'camera-fit-scene targets)
       (define resolved
         (for/list ([target (in-list targets)])
           (scene-state-resolved-ref state target)))
       (for ([visual (in-list resolved)])
         (when (frame-space-visual? visual)
           (raise-arguments-error
            'camera-fit-scene
            "camera fitting accepts only world-space Visual targets"
            "visual-id" (visual-id visual))))
       resolved]))
  (when (null? visuals)
    (raise-arguments-error
     'camera-fit-scene
     "the current scene has no top-level world-space Visuals to fit"
     "scene" scn))
  (camera-fit-visuals visuals
                      #:camera (scene-current-camera scn)
                      #:renderers renderers
                      #:padding padding))


;;;
;;; Validation
;;;

; check-camera-fit-padding : symbol? any/c -> void?
;;   Raises an argument error unless padding is nonnegative and finite.
(define (check-camera-fit-padding who padding)
  (unless (and (finite-real? padding)
               (not (negative? padding)))
    (raise-argument-error who "nonnegative finite real?" padding)))


; check-camera-fit-targets : symbol? any/c -> void?
;;   Raises an argument error unless value is a nonempty Visual/id target list.
(define (check-camera-fit-targets who value)
  (unless (and (list? value)
               (pair? value)
               (andmap (lambda (target)
                         (or (visual? target)
                             (symbol? target)))
                       value))
    (raise-argument-error
     who
     "#f or a nonempty list of Visuals or symbols"
     value)))

; check-nonempty-world-visual-list : symbol? any/c -> void?
;;   Raises unless value is a nonempty list containing only world Visuals.
(define (check-nonempty-world-visual-list who value)
  (unless (and (list? value)
               (pair? value)
               (andmap visual? value))
    (raise-argument-error
     who
     "nonempty list of Visuals"
     value))
  (define frame-visual
    (for/first ([visual (in-list value)]
                #:when (frame-space-visual? visual))
      visual))
  (when frame-visual
    (raise-arguments-error
     who
     "camera fitting accepts only world-space Visuals"
     "visual-id" (visual-id frame-visual))))
