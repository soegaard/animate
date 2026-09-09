#lang racket/base

;;;
;;; Float32 Geometry Packing
;;;

(require racket/list
         ffi/vector
         "../../color-style.rkt"
         "../../render-color-context.rkt"
         "../compiled-view3d.rkt"
         "../mesh3d.rkt"
         "../vec3.rkt"
         "matrix-pack.rkt")

(provide (struct-out gl-packed-geometry)
         pack-compiled-geometry3d
         packed-geometry-appearance-key
         packed-geometry-variant-for
         gl-packed-geometry-byte-size)

;; The layout is intentionally fixed and shared by smooth and flat resources:
;; position (3×f32), normal (3×f32), colour (4×f32).
(struct gl-packed-geometry
  (key variant vertices indices vertex-count index-count has-vertex-colors? byte-size)
  #:transparent)

(define floats-per-vertex 10)
(define bytes-per-float 4)

(define (packed-geometry-variant-for mesh shading)
  (unless (mesh3d? mesh)
    (raise-argument-error 'packed-geometry-variant-for "mesh3d?" mesh))
  (unless (memq shading '(flat smooth unlit))
    (raise-argument-error 'packed-geometry-variant-for "supported shading symbol" shading))
  (if (and (eq? shading 'smooth) (mesh3d-normals mesh))
      'smooth-indexed
      'flat-expanded))

(define (colour-components colour color-context)
  (define resolved (resolve-color-in-context colour color-context))
  (list (/ (rgba-color-red resolved) 255.0)
        (/ (rgba-color-green resolved) 255.0)
        (/ (rgba-color-blue resolved) 255.0)
        (rgba-color-alpha resolved)))

(define white-components (list 1.0 1.0 1.0 1.0))
(define fallback-normal (vec3 0 0 1))

(define (vertex-components point normal colour)
  (append (list (vec3-x point) (vec3-y point) (vec3-z point)
                (vec3-x normal) (vec3-y normal) (vec3-z normal))
          colour))

;; Per-vertex colour is interleaved with position and normal in this first GL
;; layout.  Its resolved appearance therefore becomes part of the VBO key;
;; positions, indices and normals retain their original compiled-geometry key
;; and are unaffected by a material-only theme change.
(define (packed-geometry-appearance-key geometry color-context)
  (unless (compiled-geometry3d? geometry)
    (raise-argument-error 'packed-geometry-appearance-key "compiled-geometry3d?" geometry))
  (unless (render-color-context? color-context)
    (raise-argument-error 'packed-geometry-appearance-key "render-color-context?" color-context))
  (define mesh (compiled-geometry3d-mesh geometry))
  (if (mesh3d-colors mesh)
      (vector-immutable
       (compiled-geometry3d-key geometry)
       'vertex-colours
       (render-color-context-appearance-fingerprint color-context))
      (compiled-geometry3d-key geometry)))

; pack-compiled-geometry3d : compiled-geometry3d? variant
;                            [#:color-context render-color-context?]
;                            -> gl-packed-geometry?
;; The packed resource contains only immutable geometry attributes.  Material,
;; object transform, camera, light, and opacity remain uniforms/instances and
;; therefore cannot cause an upload cache miss.
(define (pack-compiled-geometry3d geometry variant
                                  #:color-context
                                  [color-context (current-or-default-render-color-context)])
  (unless (compiled-geometry3d? geometry)
    (raise-argument-error 'pack-compiled-geometry3d "compiled-geometry3d?" geometry))
  (unless (memq variant '(smooth-indexed flat-expanded))
    (raise-argument-error 'pack-compiled-geometry3d
                          "'smooth-indexed or 'flat-expanded" variant))
  (define mesh (compiled-geometry3d-mesh geometry))
  (define vertices (mesh3d-vertices mesh))
  (define normals (mesh3d-normals mesh))
  (define colours (mesh3d-colors mesh))
  (define has-colours? (and colours #t))
  (define triangle-count (vector-length (mesh3d-triangles mesh)))
  (cond
    [(eq? variant 'smooth-indexed)
     (unless normals
       (raise-arguments-error 'pack-compiled-geometry3d
                              "vertex normals for smooth indexed packing"
                          "geometry-key" (compiled-geometry3d-key geometry)))
  (unless (render-color-context? color-context)
    (raise-argument-error 'pack-compiled-geometry3d "render-color-context?" color-context))
     (define packed-values
       (append*
        (for/list ([point (in-vector vertices)] [normal (in-vector normals)]
                   [index (in-naturals)])
          (vertex-components point normal
                             (if colours
                                 (colour-components (vector-ref colours index) color-context)
                                 white-components)))))
     (define indices
       (apply u32vector
              (append*
               (for/list ([triangle (in-vector (mesh3d-triangles mesh))])
                 (vector->list triangle)))))
     (define packed (apply f32vector (map finite-real->float32 packed-values)))
     (gl-packed-geometry (packed-geometry-appearance-key geometry color-context) variant packed indices
                         (vector-length vertices) (* triangle-count 3) has-colours?
                         (+ (* bytes-per-float (f32vector-length packed))
                            (* 4 (u32vector-length indices))))]
    [else
     ;; Flat normals need their own triangle-expanded stream.  This is a
     ;; distinct cache variant; no geometry shader is involved.
     (define face-normals (compiled-geometry3d-face-normals geometry))
     (define packed-values
       (append*
        (for/list ([triangle (in-vector (mesh3d-triangles mesh))]
                   [face-normal (in-vector face-normals)])
          (append*
           (for/list ([index (in-vector triangle)])
             (vertex-components
              (vector-ref vertices index)
              ;; Degenerate faces are diagnosed by the mesh-analysis layer.
              ;; Their zero area prevents rasterization; this finite fallback
              ;; simply keeps resource packing total and deterministic.
              (or face-normal fallback-normal)
              (if colours
                  (colour-components (vector-ref colours index) color-context)
                  white-components)))))))
     (define packed (apply f32vector (map finite-real->float32 packed-values)))
     (gl-packed-geometry (packed-geometry-appearance-key geometry color-context) variant packed #f
                         (* triangle-count 3) 0 has-colours?
                         (* bytes-per-float (f32vector-length packed)))]))
