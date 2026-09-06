#lang racket/base

;;;
;;; Screen-space stroke and marker submission
;;;

;; SCENE-3D-O already owns the difficult semantics: clipping, dash phase,
;; cap/join choice, marker size, feature-edge selection and source identity.
;; This module consumes those prepared screen primitives.  It never changes
;; an authoring curve into a GPU-owned semantic value.

(require racket/list
         racket/math
         ffi/vector
         "../../color-style.rkt"
         "../camera3d.rkt"
         "../compiled-view3d.rkt"
         "../marker-raster3d.rkt"
         "../marker3d.rkt"
         "../renderer3d.rkt"
         "../software-renderer3d.rkt"
         "../stroke-raster3d.rkt"
         "../stroke3d.rkt"
         "api.rkt"
         "matrix-pack.rkt"
         "shader-program.rkt")

(provide (struct-out opengl-stroke-batches)
         prepare-opengl-stroke-batches
         gl-draw-stroke-batch/current!)

;; Each vertex is a homogeneous clip coordinate followed by a straight RGBA
;; color. Retaining clip w lets hardware interpolate depth perspective-correctly
;; even though width has already been resolved in screen pixels.
(struct opengl-stroke-batches (hidden visible always hidden-count visible-count always-count)
  #:transparent)

(define floats-per-vertex 8)
(define stroke-circle-sides 16)

(define (prepare-opengl-stroke-batches compiled frame-spec)
  (unless (compiled-view3d? compiled)
    (raise-argument-error 'prepare-opengl-stroke-batches "compiled-view3d?" compiled))
  (unless (frame3d-spec? frame-spec)
    (raise-argument-error 'prepare-opengl-stroke-batches "frame3d-spec?" frame-spec))
  (define camera (frame3d-spec-camera frame-spec))
  (define width (frame3d-spec-width frame-spec))
  (define height (frame3d-spec-height frame-spec))
  (define aspect (/ width height))
  (define strokes
    (append
     (append*
      (for/list ([stroke (in-vector (compiled-view3d-strokes compiled))])
        (prepare-stroke3d-segments
         (compiled-stroke3d-path stroke)
         (compiled-stroke3d-world-transform stroke)
         (compiled-stroke3d-points stroke)
         (compiled-stroke3d-closed? stroke)
         (compiled-stroke3d-style stroke)
         (compiled-stroke3d-opacity stroke)
         (compiled-stroke3d-clip-planes stroke)
         camera aspect width height (compiled-stroke3d-drawing-index stroke)
         #:source-kind (compiled-stroke3d-source-kind stroke)
         #:source-metadata (compiled-stroke3d-source-metadata stroke))))
     ;; Feature/silhouette selection remains one semantic implementation.
     (prepare-edge-overlay-strokes compiled camera aspect width height)))
  (define points
    (filter values
            (for/list ([marker (in-vector (compiled-view3d-point-markers compiled))])
              (prepare-point-marker3d
               (compiled-point-marker3d-path marker)
               (compiled-point-marker3d-position marker)
               (compiled-point-marker3d-world-transform marker)
               (compiled-point-marker3d-style marker)
               (compiled-point-marker3d-opacity marker)
               (compiled-point-marker3d-clip-planes marker)
               camera aspect width height (compiled-point-marker3d-drawing-index marker)))))
  (define arrows
    (filter values
            (for/list ([marker (in-vector (compiled-view3d-arrow-markers compiled))])
              (prepare-arrow-marker3d
               (compiled-arrow-marker3d-path marker)
               (compiled-arrow-marker3d-from marker)
               (compiled-arrow-marker3d-to marker)
               (compiled-arrow-marker3d-world-transform marker)
               (compiled-arrow-marker3d-style marker)
               (compiled-arrow-marker3d-opacity marker)
               (compiled-arrow-marker3d-clip-planes marker)
               camera aspect width height (compiled-arrow-marker3d-drawing-index marker)))))
  (define hidden '())
  (define visible '())
  (define always '())
  (define (append-vertices! mode vertices)
    (case mode
      [(hidden) (set! hidden (append hidden vertices))]
      [(test) (set! visible (append visible vertices))]
      [(always) (set! always (append always vertices))]))
  (for ([segment (in-list strokes)])
    (append-vertices!
     (stroke3d-depth-mode (prepared-stroke-segment3d-style segment))
     (stroke-segment-vertices segment camera width height)))
  (for ([point (in-list points)])
    (append-vertices!
     (point-style3d-depth-mode (prepared-point-marker3d-style point))
     (point-marker-vertices point camera width height)))
  (for ([arrow (in-list arrows)])
    (append-vertices!
     (arrow-style3d-depth-mode (prepared-arrow-marker3d-style arrow))
     (arrow-marker-vertices arrow camera width height)))
  (define (packed values) (apply f32vector (map finite-real->float32 values)))
  (opengl-stroke-batches
   (packed hidden) (packed visible) (packed always)
   (/ (length hidden) floats-per-vertex)
   (/ (length visible) floats-per-vertex)
   (/ (length always) floats-per-vertex)))

(define (color-components color)
  (list (/ (rgba-color-red color) 255.0)
        (/ (rgba-color-green color) 255.0)
        (/ (rgba-color-blue color) 255.0)
        (exact->inexact (rgba-color-alpha color))))

(define (clip-position camera point)
  (gl-matrix4-apply-point
   (camera3d-view-projection-matrix camera 1)
   point))

(define (screen-clip-vertex x y clip width height color)
  (define clip-w (vector-ref clip 3))
  ;; A prepared screen coordinate has a top-left origin; OpenGL NDC has +y
  ;; upward. Multiplication by the original clip w preserves its depth.
  (append (list (* (- (* 2.0 (/ x width)) 1.0) clip-w)
                (* (- 1.0 (* 2.0 (/ y height))) clip-w)
                (vector-ref clip 2)
                clip-w)
          (color-components color)))

(define (stroke-segment-vertices segment camera width height)
  (define x0 (prepared-stroke-segment3d-start-x segment))
  (define y0 (prepared-stroke-segment3d-start-y segment))
  (define x1 (prepared-stroke-segment3d-end-x segment))
  (define y1 (prepared-stroke-segment3d-end-y segment))
  (define dx (- x1 x0))
  (define dy (- y1 y0))
  (define length (sqrt (+ (* dx dx) (* dy dy))))
  (cond [(<= length 1e-12) '()]
        [else
         (define style (prepared-stroke-segment3d-style segment))
         (define half-width (/ (prepared-stroke-segment3d-width segment) 2.0))
         (define unit-x (/ dx length))
         (define unit-y (/ dy length))
         (define extension (if (eq? (stroke3d-cap style) 'square) half-width 0.0))
         (define start-x (- x0 (* extension unit-x)))
         (define start-y (- y0 (* extension unit-y)))
         (define end-x (+ x1 (* extension unit-x)))
         (define end-y (+ y1 (* extension unit-y)))
         (define normal-x (* -1.0 unit-y half-width))
         (define normal-y (* unit-x half-width))
         (define start-clip (clip-position camera (prepared-stroke-segment3d-start-world segment)))
         (define end-clip (clip-position camera (prepared-stroke-segment3d-end-world segment)))
         (define color (prepared-stroke-segment3d-color segment))
         (define a (screen-clip-vertex (+ start-x normal-x) (+ start-y normal-y)
                                       start-clip width height color))
         (define b (screen-clip-vertex (- start-x normal-x) (- start-y normal-y)
                                       start-clip width height color))
         (define c (screen-clip-vertex (+ end-x normal-x) (+ end-y normal-y)
                                       end-clip width height color))
         (define d (screen-clip-vertex (- end-x normal-x) (- end-y normal-y)
                                       end-clip width height color))
         (append a b c b d c
                 (if (eq? (stroke3d-cap style) 'round)
                     (append (disc-vertices x0 y0 half-width start-clip width height color)
                             (disc-vertices x1 y1 half-width end-clip width height color))
                     '()))]))

(define (disc-vertices x y radius clip width height color)
  (append*
   (for/list ([index (in-range stroke-circle-sides)])
     (define angle0 (* 2.0 pi (/ index stroke-circle-sides)))
     (define angle1 (* 2.0 pi (/ (add1 index) stroke-circle-sides)))
     (append (screen-clip-vertex x y clip width height color)
             (screen-clip-vertex (+ x (* radius (cos angle0)))
                                 (+ y (* radius (sin angle0))) clip width height color)
             (screen-clip-vertex (+ x (* radius (cos angle1)))
                                 (+ y (* radius (sin angle1))) clip width height color)))))

(define (point-marker-vertices point camera width height)
  (disc-vertices (prepared-point-marker3d-x point)
                 (prepared-point-marker3d-y point)
                 (prepared-point-marker3d-radius point)
                 (clip-position camera (prepared-point-marker3d-world-position point))
                 width height (prepared-point-marker3d-color point)))

(define (arrow-marker-vertices arrow camera width height)
  (define tip-x (prepared-arrow-marker3d-tip-x arrow))
  (define tip-y (prepared-arrow-marker3d-tip-y arrow))
  (define base-x (prepared-arrow-marker3d-base-x arrow))
  (define base-y (prepared-arrow-marker3d-base-y arrow))
  (define dx (- tip-x base-x))
  (define dy (- tip-y base-y))
  (define length (sqrt (+ (* dx dx) (* dy dy))))
  (if (<= length 1e-12)
      '()
      (let* ([half-width (prepared-arrow-marker3d-half-width arrow)]
             [normal-x (* -1.0 (/ dy length) half-width)]
             [normal-y (* (/ dx length) half-width)]
             [clip (clip-position camera (prepared-arrow-marker3d-tip-world arrow))]
             [color (prepared-arrow-marker3d-color arrow)])
        (append
         (screen-clip-vertex tip-x tip-y clip width height color)
         (screen-clip-vertex (+ base-x normal-x) (+ base-y normal-y) clip width height color)
         (screen-clip-vertex (- base-x normal-x) (- base-y normal-y) clip width height color)))))

;; `gl-draw-stroke-batch/current!` must run inside the owner context. The short
;; dynamic VBO is frame-local: dash clipping and feature edges are camera-
;; dependent, whereas mesh VBOs remain in the retained cache.
(define (gl-draw-stroke-batch/current! program vertices vertex-count mode)
  (unless (gl-shader-program? program)
    (raise-argument-error 'gl-draw-stroke-batch/current! "gl-shader-program?" program))
  (unless (and (f32vector? vertices) (exact-nonnegative-integer? vertex-count))
    (raise-argument-error 'gl-draw-stroke-batch/current!
                          "f32vector and exact-nonnegative vertex count" (vector vertices vertex-count)))
  (when (positive? vertex-count)
    (define vao (u32vector-ref (glGenVertexArrays 1) 0))
    (define buffer (u32vector-ref (glGenBuffers 1) 0))
    (dynamic-wind
     void
     (lambda ()
       (glUseProgram (gl-shader-program-id program))
       (glBindVertexArray vao)
       (glBindBuffer GL_ARRAY_BUFFER buffer)
       (glBufferData GL_ARRAY_BUFFER (* 4 (f32vector-length vertices)) vertices GL_STREAM_DRAW)
       (define stride (* floats-per-vertex 4))
       (glEnableVertexAttribArray 0)
       (glVertexAttribPointer 0 4 GL_FLOAT #f stride 0)
       (glEnableVertexAttribArray 2)
       (glVertexAttribPointer 2 4 GL_FLOAT #f stride (* 4 4))
       (glDisable GL_CULL_FACE)
       (glEnable GL_BLEND)
       (glBlendFunc GL_SRC_ALPHA GL_ONE_MINUS_SRC_ALPHA)
       (glDepthMask #f)
       (case mode
         [(hidden) (glEnable GL_DEPTH_TEST) (glDepthFunc GL_GREATER)]
         [(test) (glEnable GL_DEPTH_TEST) (glDepthFunc GL_LEQUAL)]
         [(always) (glDisable GL_DEPTH_TEST)])
       (when (memq mode '(hidden test))
         (glEnable GL_POLYGON_OFFSET_FILL)
         (glPolygonOffset (if (eq? mode 'hidden) 1.0 -1.0)
                          (if (eq? mode 'hidden) 1.0 -1.0)))
       (glDrawArrays GL_TRIANGLES 0 vertex-count)
       (glDisable GL_POLYGON_OFFSET_FILL)
       (glDepthMask #t)
       (glDisable GL_BLEND)
       (glBindVertexArray 0)
       (glUseProgram 0))
     (lambda ()
       (glDeleteBuffers 1 (u32vector buffer))
       (glDeleteVertexArrays 1 (u32vector vao))))))
