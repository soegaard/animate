#lang racket/base

;;;
;;; Immutable Prepared Label Layout Tables
;;;

(require racket/list
         "../camera.rkt"
         "../pict-adapter.rkt"
         "../pict-renderer.rkt"
         "../render-color-context.rkt"
         "../scene-frame-grid.rkt"
         "../scene.rkt"
         "label-layout3d.rkt")

(provide (struct-out prepared-label-layout3d)
         prepare-label-layout3d
         prepare-scene-label-layout3d
         prepared-label-layout3d-ref)

(struct prepared-label-layout3d (frames layouts switch-penalty movement-penalty) #:transparent)

;; Frame data is a list of (cons exact-frame-index items).  Direct layout stays
;; the semantic fallback; preparation freezes only the supplied finite frame
;; grid and is consequently safe for parallel rendering.  For labels present
;; throughout the grid, preparation chooses a deterministic minimum-cost
;; candidate trajectory.  Labels which appear or disappear retain their direct
;; layout in those frames instead of inventing history across a discontinuity.
(define (prepare-label-layout3d frame-data #:width width #:height height
                                #:switch-penalty [switch-penalty 0]
                                #:movement-penalty [movement-penalty 0])
  (unless (and (list? frame-data) (andmap pair? frame-data))
    (raise-argument-error 'prepare-label-layout3d "list of frame/index item pairs" frame-data))
  (unless (and (real? switch-penalty) (>= switch-penalty 0)
               (real? movement-penalty) (>= movement-penalty 0))
    (raise-argument-error 'prepare-label-layout3d "nonnegative penalties" (vector switch-penalty movement-penalty)))
  (define sorted (sort frame-data < #:key car))
  (when (for/or ([earlier (in-list sorted)] [later (in-list (cdr sorted))])
          (= (car earlier) (car later)))
    (raise-arguments-error 'prepare-label-layout3d
                           "distinct frame indexes"
                           "frame-data" frame-data))
  (define direct-layouts
    (for/list ([entry (in-list sorted)])
      (layout-labels3d (cdr entry) #:width width #:height height)))
  (define direct-placement-lists
    (map label-layout3d-placements direct-layouts))
  (define common-ids
    (if (null? direct-placement-lists)
        '()
        (filter
         (lambda (id)
           (for/and ([placements (in-list direct-placement-lists)])
             (member id (map label-layout-candidate3d-item-id placements))))
         (map label-layout-candidate3d-item-id (car direct-placement-lists)))))
  ;; Each vector entry maps a label ID to its prepared selected candidate.
  ;; The vector is mutable only while this constructor builds the final
  ;; immutable layouts; neither the cache nor a renderer observes it.
  (define selections (make-vector (length direct-layouts) #hasheq()))
  (for ([id (in-list common-ids)])
    (define candidate-frames
      (for/list ([layout (in-list direct-layouts)])
        (filter (lambda (candidate) (eq? (label-layout-candidate3d-item-id candidate) id))
                (label-layout3d-candidates layout))))
    (for ([candidate (in-list (best-candidate-trajectory
                               candidate-frames switch-penalty movement-penalty))]
          [index (in-naturals)])
      (vector-set! selections index
                   (hash-set (vector-ref selections index) id candidate))))
  (define prepared-layouts
    (for/list ([layout (in-list direct-layouts)] [selection (in-vector selections)])
      (label-layout3d
       (for/list ([direct (in-list (label-layout3d-placements layout))])
         (hash-ref selection (label-layout-candidate3d-item-id direct) direct))
       (label-layout3d-candidates layout)
       (hasheq 'mode 'prepared
               'item-count (length (label-layout3d-placements layout))
               'viewport (vector width height)
               'switch-penalty switch-penalty
               'movement-penalty movement-penalty))))
  (prepared-label-layout3d
   (vector->immutable-vector (list->vector (map car sorted)))
   (vector->immutable-vector (list->vector prepared-layouts))
   switch-penalty movement-penalty))

(define (prepared-label-layout3d-ref prepared frame)
  (unless (prepared-label-layout3d? prepared)
    (raise-argument-error 'prepared-label-layout3d-ref "prepared-label-layout3d?" prepared))
  (define index (index-of (vector->list (prepared-label-layout3d-frames prepared)) frame))
  (and index (vector-ref (prepared-label-layout3d-layouts prepared) index)))

;; prepare-scene-label-layout3d : scene? #:frames (listof exact-nonnegative-integer?)
;;                                [#:view (or/c #f symbol?)] ...
;;                                -> prepared-label-layout3d?
;; Samples a declared frame grid, resolves projected anchors, and measures the
;; concrete 2D templates before renderer workers start.  The result is an
;; immutable source-frame table: rendering frame 90 never depends on whether
;; frame 89 was rendered or previewed.  `#:view` prepares only one viewport's
;; stable label slots; labels in other viewports retain direct layout.
;;
;; The baseline used for measurement intentionally makes no occlusion or
;; visibility query.  Project preparation therefore does not create a renderer
;; frame artifact or require a live OpenGL context.  Final composition still
;; performs visibility from the exact artifact it renders for that frame.
(define (prepare-scene-label-layout3d scn
                                      #:frames frames
                                      #:view [view-id #f]
                                      #:fps [fps 30]
                                      #:camera [camera #f]
                                      #:renderers [renderers default-pict-renderers]
                                      #:supersample [supersample 1]
                                      #:theme [theme #f]
                                      #:switch-penalty [switch-penalty 0]
                                      #:movement-penalty [movement-penalty 0])
  (unless (scene? scn)
    (raise-argument-error 'prepare-scene-label-layout3d "scene?" scn))
  (unless (and (list? frames) (andmap exact-nonnegative-integer? frames))
    (raise-argument-error
     'prepare-scene-label-layout3d
     "list of exact nonnegative frame indices"
     frames))
  (unless (or (not view-id) (symbol? view-id))
    (raise-argument-error 'prepare-scene-label-layout3d "#f or symbol? as #:view" view-id))
  (unless (exact-positive-integer? fps)
    (raise-argument-error 'prepare-scene-label-layout3d "exact-positive-integer? as #:fps" fps))
  (unless (or (not camera) (camera? camera))
    (raise-argument-error 'prepare-scene-label-layout3d "#f or camera? as #:camera" camera))
  (check-pict-renderer-list 'prepare-scene-label-layout3d renderers)
  (unless (exact-positive-integer? supersample)
    (raise-argument-error
     'prepare-scene-label-layout3d
     "exact-positive-integer? as #:supersample"
     supersample))
  ;; Capture the selected theme once before measurements begin.  A label's
  ;; rendered bounds may depend on a token-coloured template; a prepared table
  ;; must therefore never be measured under a later ambient theme.
  (define color-context
    (if theme
        (make-render-color-context theme)
        (current-or-default-render-color-context)))
  (define available (scene-frame-count scn #:fps fps))
  (unless (andmap (lambda (frame) (< frame available)) frames)
    (raise-arguments-error
     'prepare-scene-label-layout3d
     "frame indices within the scene"
     "frames" frames
     "frame-count" available))
  (define measurements
    (for/list ([frame (in-list frames)])
      (define time (frame-index->time frame #:fps fps))
      (define-values (state sampled-camera)
        (if camera
            (values (scene-sample scn time) camera)
            (scene-sample-with-camera scn time)))
      (define render-camera
        (camera-with-supersampling sampled-camera supersample))
      (list frame
            (scene-projected-label-layout-items3d
             state render-camera renderers #:view view-id
             #:color-context color-context)
            render-camera)))
  ;; Direction choices live in screen space.  A trajectory can only be reused
  ;; with one viewport size, so reject a camera timeline that changes it rather
  ;; than silently mixing incompatible pixel boxes in one prepared table.
  (define layout-camera
    (if (null? measurements)
        (camera-with-supersampling (or camera (scene-current-camera scn)) supersample)
        (caddr (car measurements))))
  (unless (for/and ([measurement (in-list measurements)])
            (and (= (camera-width layout-camera) (camera-width (caddr measurement)))
                 (= (camera-height layout-camera) (camera-height (caddr measurement)))))
    (raise-arguments-error
     'prepare-scene-label-layout3d
     "one fixed output viewport across prepared frames"
     "frames" frames))
  (prepare-label-layout3d
   (for/list ([measurement (in-list measurements)])
     (cons (car measurement) (cadr measurement)))
   #:width (camera-width layout-camera)
   #:height (camera-height layout-camera)
   #:switch-penalty switch-penalty
   #:movement-penalty movement-penalty))

;; Same contract as the frame renderer: increase raster dimensions only.  The
;; world camera, authored transforms, and label offsets remain unchanged.
(define (camera-with-supersampling camera supersample)
  (if (= supersample 1)
      camera
      (make-camera #:width (* supersample (camera-width camera))
                   #:height (* supersample (camera-height camera))
                   #:world-width (camera-world-width camera)
                   #:center (camera-center camera)
                   #:background (camera-background camera))))

;; Returns one candidate for each frame. Candidate vectors remain in the
;; source order emitted by `layout-labels3d`, so equal-cost choices resolve
;; without hash or worker-order dependence.
(define (best-candidate-trajectory candidate-frames switch-penalty movement-penalty)
  (cond [(null? candidate-frames) '()]
        [else
         (define initial
           (for/list ([candidate (in-list (car candidate-frames))])
             (cons (label-layout-candidate3d-cost candidate) #f)))
         (define states
           (let loop ([remaining (cdr candidate-frames)]
                      [previous-candidates (car candidate-frames)]
                      [previous-states initial]
                      [reversed-states (list initial)])
             (cond [(null? remaining) (reverse reversed-states)]
                   [else
                    (define candidates (car remaining))
                    (define current
                      (for/list ([candidate (in-list candidates)])
                        (best-predecessor candidate previous-candidates previous-states
                                          switch-penalty movement-penalty)))
                    (loop (cdr remaining) candidates current
                          (cons current reversed-states))])))
         (define final-states (last states))
         (define final-index
           (best-state-index final-states))
         (let loop ([frame-index (sub1 (length candidate-frames))]
                    [candidate-index final-index]
                    [reversed '()])
           (define candidate
             (list-ref (list-ref candidate-frames frame-index) candidate-index))
           (define predecessor (cdr (list-ref (list-ref states frame-index) candidate-index)))
           (define next (cons candidate reversed))
           (if (zero? frame-index)
               next
               (loop (sub1 frame-index) predecessor next)))]))

;; A state is `(cons total-cost predecessor-index)`.  Selecting a predecessor
;; by its original index is the specified final tie-break after equal costs.
(define (best-predecessor candidate previous-candidates previous-states
                          switch-penalty movement-penalty)
  (for/fold ([best #f]) ([previous (in-list previous-candidates)]
                         [state (in-list previous-states)]
                         [index (in-naturals)])
    (define penalty
      (+ (if (eq? (label-layout-candidate3d-direction candidate)
                   (label-layout-candidate3d-direction previous))
             0 switch-penalty)
         (* movement-penalty (candidate-distance candidate previous))))
    (define choice (cons (+ (car state) (label-layout-candidate3d-cost candidate) penalty) index))
    (if (or (not best)
            (< (car choice) (car best))
            (and (= (car choice) (car best)) (< (cdr choice) (cdr best))))
        choice
        best)))

(define (best-state-index states)
  (for/fold ([best-index 0])
            ([state (in-list (cdr states))] [index (in-naturals 1)])
    (if (< (car state) (car (list-ref states best-index)))
        index
        best-index)))

(define (candidate-distance first second)
  (define first-box (label-layout-candidate3d-box first))
  (define second-box (label-layout-candidate3d-box second))
  (define dx
    (- (+ (vector-ref first-box 0) (/ (vector-ref first-box 2) 2))
       (+ (vector-ref second-box 0) (/ (vector-ref second-box 2) 2))))
  (define dy
    (- (+ (vector-ref first-box 1) (/ (vector-ref first-box 3) 2))
       (+ (vector-ref second-box 1) (/ (vector-ref second-box 3) 2))))
  (sqrt (+ (* dx dx) (* dy dy))))
