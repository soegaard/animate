#lang racket/base

;;;
;;; Deterministic Local-Mesh Bounding-Volume Hierarchies
;;;

;; A BVH is an acceleration structure, never semantic scene state.  It is
;; cached weakly by immutable geometry fingerprint and stores only local
;; coordinates, allowing each inspected instance to retain its own world
;; transform.

(require racket/list
         "bounds3.rkt"
         "mesh3d.rkt"
         "ray-plane.rkt"
         "vec3.rkt")

(provide mesh3d-bvh
         mesh3d-bvh?
         bvh3d-node?
         bvh3d-leaf?
         bvh3d-bounds
         bvh3d-triangle-indices
         bvh3d-ray-candidates)

(struct bvh3d-node (bounds left right) #:transparent)
(struct bvh3d-leaf (bounds triangle-indices) #:transparent)

(define (mesh3d-bvh? value)
  (or (bvh3d-node? value) (bvh3d-leaf? value)))

;; The first table makes a repeat request for the same mesh constant-time. Its
;; value retains the structural key while that mesh remains live. The second
;; table then shares the same immutable tree between separately constructed but
;; equal indexed geometry, without making either authored mesh reachability a
;; semantic concern. Once neither mesh entry retains a key, both weak tables
;; may release it and its acceleration tree.
(struct bvh-cache-entry (fingerprint tree) #:transparent)
(define mesh-bvh-cache (make-weak-hasheq))
(define geometry-bvh-cache (make-weak-hash))
(define leaf-size 8)

;; mesh3d-bvh : mesh3d? -> (or/c bvh3d-node? bvh3d-leaf?)
;; Builds once per immutable geometry fingerprint. Construction is deterministic:
;; longest centroid axis, stable median, then original triangle index.
(define (mesh3d-bvh mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-bvh "mesh3d?" mesh))
  (bvh-cache-entry-tree
   (hash-ref! mesh-bvh-cache mesh
             (lambda ()
               (define fingerprint (mesh3d-geometry-fingerprint mesh))
               (bvh-cache-entry
                fingerprint
                (hash-ref! geometry-bvh-cache fingerprint
                           (lambda ()
                             (build-bvh mesh
                                        (for/list
                                            ([index
                                              (in-range
                                               (vector-length
                                                (mesh3d-triangles mesh)))])
                                          index)))))))))

(define (mesh3d-geometry-fingerprint mesh)
  ;; Colour, normals, material, and wireframe intent never affect geometric
  ;; intersection. Keep only the immutable indexed positions/topology so a
  ;; styling-only mesh replacement reuses the exact same local acceleration.
  (vector (mesh3d-vertices mesh) (mesh3d-triangles mesh)))

(define (bvh3d-bounds tree)
  (cond [(bvh3d-node? tree) (bvh3d-node-bounds tree)]
        [(bvh3d-leaf? tree) (bvh3d-leaf-bounds tree)]
        [else (raise-argument-error 'bvh3d-bounds "bvh3d node or leaf" tree)]))

(define (bvh3d-triangle-indices tree)
  (cond [(bvh3d-leaf? tree) (bvh3d-leaf-triangle-indices tree)]
        [(bvh3d-node? tree)
         (append (bvh3d-triangle-indices (bvh3d-node-left tree))
                 (bvh3d-triangle-indices (bvh3d-node-right tree)))]
        [else (raise-argument-error 'bvh3d-triangle-indices "bvh3d node or leaf" tree)]))

;; bvh3d-ray-candidates : bvh3d? ray3? -> (listof exact-nonnegative-integer?)
;; Returns local triangle indices in deterministic traversal order. Exact
;; triangle testing remains the caller's responsibility.
(define (bvh3d-ray-candidates tree ray)
  (unless (or (bvh3d-node? tree) (bvh3d-leaf? tree))
    (raise-argument-error 'bvh3d-ray-candidates "bvh3d node or leaf" tree))
  (unless (ray3? ray)
    (raise-argument-error 'bvh3d-ray-candidates "ray3?" ray))
  (define (walk current)
    (cond [(not (ray3-intersect-aabb ray (bvh3d-bounds current))) '()]
          [(bvh3d-leaf? current) (bvh3d-leaf-triangle-indices current)]
          [else
           (define left (bvh3d-node-left current))
           (define right (bvh3d-node-right current))
           (define left-hit (ray3-intersect-aabb ray (bvh3d-bounds left)))
           (define right-hit (ray3-intersect-aabb ray (bvh3d-bounds right)))
           (cond [(and left-hit right-hit)
                  (if (<= (ray3-aabb-hit-entry left-hit) (ray3-aabb-hit-entry right-hit))
                      (append (walk left) (walk right))
                      (append (walk right) (walk left)))]
                 [left-hit (walk left)]
                 [right-hit (walk right)]
                 [else '()])]))
  (walk tree))

(define (build-bvh mesh indices)
  (define bounds (indices-bounds mesh indices))
  (if (<= (length indices) leaf-size)
      (bvh3d-leaf bounds indices)
      (let* ([axis (longest-axis (indices-centroid-bounds mesh indices))]
             [ordered
              (sort indices
                    (lambda (first second)
                      (define first-coordinate (triangle-centroid-coordinate mesh first axis))
                      (define second-coordinate (triangle-centroid-coordinate mesh second axis))
                      (or (< first-coordinate second-coordinate)
                          (and (= first-coordinate second-coordinate)
                               (< first second)))))]
             [middle (quotient (length ordered) 2)])
        (bvh3d-node bounds
                    (build-bvh mesh (take ordered middle))
                    (build-bvh mesh (drop ordered middle))))))

(define (indices-bounds mesh indices)
  (for/fold ([result aabb3-empty]) ([index (in-list indices)])
    (aabb3-union result (triangle-bounds mesh index))))

(define (indices-centroid-bounds mesh indices)
  (aabb3-from-points
   (for/list ([index (in-list indices)]) (triangle-centroid mesh index))))

(define (triangle-bounds mesh index)
  (aabb3-from-points (triangle-points mesh index)))

(define (triangle-centroid mesh index)
  (define points (triangle-points mesh index))
  (vec3-scale 1/3 (vec3+ (first points) (vec3+ (second points) (third points)))))

(define (triangle-centroid-coordinate mesh index axis)
  (component-at (triangle-centroid mesh index) axis))

(define (triangle-points mesh index)
  (define triangle (vector-ref (mesh3d-triangles mesh) index))
  (for/list ([vertex-index (in-vector triangle)])
    (vector-ref (mesh3d-vertices mesh) vertex-index)))

(define (longest-axis bounds)
  (define size (aabb3-size bounds))
  ;; Stable x, then y, then z tie order.
  (cond [(and (>= (vec3-x size) (vec3-y size))
              (>= (vec3-x size) (vec3-z size))) 0]
        [(>= (vec3-y size) (vec3-z size)) 1]
        [else 2]))

(define (component-at point axis)
  (case axis [(0) (vec3-x point)] [(1) (vec3-y point)] [else (vec3-z point)]))
