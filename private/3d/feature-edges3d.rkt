#lang racket/base

;;;
;;; Camera-Prepared Mesh Feature Edges
;;;

;; The adjacency table is camera-independent, but a crease after a nonuniform
;; transform and a silhouette from a particular camera are not.  This module
;; performs that deliberately late, stable classification.  Hash tables are
;; used only to resolve authored explicit-edge membership; output follows the
;; adjacency or authored edge order.

(require racket/list
         racket/math
         "affine3.rkt"
         "camera3d.rkt"
         "edge-adjacency3d.rkt"
         "edge-style3d.rkt"
         "linear3.rkt"
         "mesh3d.rkt"
         "vec3.rkt")

(provide (struct-out prepared-feature-edge3d)
         select-feature-edges3d)

(struct prepared-feature-edge3d (from to edge-index kind) #:transparent)

; select-feature-edges3d : mesh3d? affine3? linear3? camera3d? edge-style3d?
;                          -> (listof prepared-feature-edge3d?)
;; The returned endpoints are world positions, in a deterministic source edge
;; order.  `kind` records the strongest reason selected for diagnostics and
;; inspection: explicit, boundary, crease, or silhouette.
(define (select-feature-edges3d mesh world-transform normal-transform camera style)
  (unless (mesh3d? mesh)
    (raise-argument-error 'select-feature-edges3d "mesh3d?" mesh))
  (unless (affine3? world-transform)
    (raise-argument-error 'select-feature-edges3d "affine3?" world-transform))
  (unless (linear3? normal-transform)
    (raise-argument-error 'select-feature-edges3d "linear3?" normal-transform))
  (unless (camera3d? camera)
    (raise-argument-error 'select-feature-edges3d "camera3d?" camera))
  (unless (edge-style3d? style)
    (raise-argument-error 'select-feature-edges3d "edge-style3d?" style))
  (define vertices (mesh3d-vertices mesh))
  (define adjacency (mesh3d-edge-adjacency mesh))
  (define explicit-keys
    (for/hash ([edge (in-vector (mesh3d-edges mesh))])
      (values (edge-key (vector-ref edge 0) (vector-ref edge 1)) #t)))
  (for/list ([row (in-vector adjacency)]
             [edge-index (in-naturals)]
             #:do [(define edge (edge-adjacency3d-edge row))
                   (define first-index (vector-ref edge 0))
                   (define second-index (vector-ref edge 1))
                   (define incidences (edge-adjacency3d-incidences row))
                   (define kinds
                     (edge-kinds mesh vertices world-transform normal-transform camera
                                 incidences explicit-keys first-index second-index
                                 (edge-style3d-crease-angle style)))]
             #:when (selection-matches? (edge-style3d-edges style) kinds))
    (prepared-feature-edge3d
     (affine3-apply-point world-transform (vector-ref vertices first-index))
     (affine3-apply-point world-transform (vector-ref vertices second-index))
     edge-index
     (primary-kind kinds))))

(define (selection-matches? selection kinds)
  (case selection
    [(all) #t]
    [(explicit) (memq 'explicit kinds)]
    [(boundary) (memq 'boundary kinds)]
    [(crease) (memq 'crease kinds)]
    [(silhouette) (memq 'silhouette kinds)]
    [(feature) (or (memq 'boundary kinds) (memq 'crease kinds) (memq 'silhouette kinds))]))

(define (primary-kind kinds)
  (cond [(memq 'boundary kinds) 'boundary]
        [(memq 'silhouette kinds) 'silhouette]
        [(memq 'crease kinds) 'crease]
        [(memq 'explicit kinds) 'explicit]
        [else 'all]))

(define (edge-kinds mesh vertices world-transform normal-transform camera incidences
                    explicit-keys first-index second-index crease-angle)
  (define kinds
    (if (hash-ref explicit-keys (edge-key first-index second-index) #f)
        '(explicit)
        '()))
  (define count (vector-length incidences))
  (cond [(= count 1) (cons 'boundary kinds)]
        [(= count 2)
         (define first-face (face-info mesh vertices world-transform normal-transform
                                       (edge-incidence3d-triangle-index (vector-ref incidences 0))))
         (define second-face (face-info mesh vertices world-transform normal-transform
                                        (edge-incidence3d-triangle-index (vector-ref incidences 1))))
         (cond [(or (not first-face) (not second-face)) kinds]
               [else
                (define first-normal (car first-face))
                (define second-normal (car second-face))
                (define cosine (max -1 (min 1 (vec3-dot first-normal second-normal))))
                (define angle (acos cosine))
                (define first-front? (front-facing? first-normal (cdr first-face) camera))
                (define second-front? (front-facing? second-normal (cdr second-face) camera))
                (append (if (> angle crease-angle) '(crease) '())
                        (if (not (eq? first-front? second-front?)) '(silhouette) '())
                        kinds)])]
        ;; A non-manifold edge is represented exactly once.  Its face
        ;; classification is ambiguous, therefore only `all` and `explicit`
        ;; select it; diagnostics can report the source topology separately.
        [else kinds]))

(define (face-info mesh vertices world-transform normal-transform triangle-index)
  (define triangle (vector-ref (mesh3d-triangles mesh) triangle-index))
  (define first (affine3-apply-point world-transform (vector-ref vertices (vector-ref triangle 0))))
  (define second (affine3-apply-point world-transform (vector-ref vertices (vector-ref triangle 1))))
  (define third (affine3-apply-point world-transform (vector-ref vertices (vector-ref triangle 2))))
  ;; Apply the normal transform to the local normal.  Computing the world
  ;; cross-product directly would be equivalent only for a nonsingular map,
  ;; and would make the intended nonuniform-scale rule less explicit.
  (define local-first (vector-ref vertices (vector-ref triangle 0)))
  (define local-second (vector-ref vertices (vector-ref triangle 1)))
  (define local-third (vector-ref vertices (vector-ref triangle 2)))
  (define local-normal (vec3-cross (vec3- local-second local-first)
                                  (vec3- local-third local-first)))
  (cond [(zero? (vec3-length local-normal)) #f]
        [else
         (cons (vec3-normalize (linear3-apply-vector normal-transform local-normal))
               (vec3-scale (/ 1 3) (vec3+ first (vec3+ second third))))]))

(define (front-facing? normal centroid camera)
  ;; A face points toward the camera when its outward normal has a positive
  ;; dot product with the direction from the face to the eye.
  (positive? (vec3-dot normal (vec3- (camera3d-position camera) centroid))))

(define (edge-key first second)
  (cons (min first second) (max first second)))
