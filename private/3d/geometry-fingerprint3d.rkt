#lang racket/base

;;;
;;; Canonical Spatial Geometry Identity
;;;

;; Defines a camera-, transform-, and material-independent identity for an
;; indexed mesh.  The encoding is deliberately explicit rather than relying on
;; a hash-table print order or mutable object identity: renderer caches and
;; cross-process diagnostics must describe equal authored geometry equally.


;;;
;;; Imports and Exports
;;;

(require file/sha1
         (only-in racket/port call-with-output-bytes)
         "mesh3d.rkt"
         "vec3.rkt")

(provide (struct-out geometry-key3d)
         mesh3d-geometry-canonical-bytes
         mesh3d-geometry-key
         mesh3d-semantic-geometry=?)


;;;
;;; Geometry Keys
;;;

(struct geometry-key3d (digest byte-length vertex-count triangle-count edge-count)
  #:transparent)

;; geometry-key3d represents a non-security SHA-1 digest of one canonical
;; mesh encoding.  Counts and byte length make an accidental digest collision
;; diagnosable before an implementation treats two resources as interchangeable.


;;;
;;; Canonical Encoding
;;;

; mesh3d-geometry-canonical-bytes : mesh3d? -> immutable-bytes?
;;   Encodes positions, topology, normals, and per-vertex colours in declared order.
(define (mesh3d-geometry-canonical-bytes mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-geometry-canonical-bytes "mesh3d?" mesh))
  (bytes->immutable-bytes
   (call-with-output-bytes
    (lambda (out)
      ;; Writing this datum gives exact and inexact Racket numbers their stable
      ;; readable encodings.  It is intentionally a format boundary, not a
      ;; serialisation promise for arbitrary authored values.
      (write
       (list 'animate-geometry3d-v1
             (for/list ([vertex (in-vector (mesh3d-vertices mesh))])
               (list (vec3-x vertex) (vec3-y vertex) (vec3-z vertex)))
             (for/list ([triangle (in-vector (mesh3d-triangles mesh))])
               (vector->list triangle))
             (for/list ([edge (in-vector (mesh3d-edges mesh))])
               (vector->list edge))
             (and (mesh3d-normals mesh)
                  (for/list ([normal (in-vector (mesh3d-normals mesh))])
                    (list (vec3-x normal) (vec3-y normal) (vec3-z normal))))
             (and (mesh3d-colors mesh)
                  (vector->list (mesh3d-colors mesh))))
       out)))))

; mesh3d-geometry-key : mesh3d? -> geometry-key3d?
;;   Gives a stable semantic-geometry cache key that excludes style and placement.
(define (mesh3d-geometry-key mesh)
  (unless (mesh3d? mesh)
    (raise-argument-error 'mesh3d-geometry-key "mesh3d?" mesh))
  (define bytes (mesh3d-geometry-canonical-bytes mesh))
  (geometry-key3d (bytes->immutable-bytes (sha1-bytes bytes))
                  (bytes-length bytes)
                  (vector-length (mesh3d-vertices mesh))
                  (vector-length (mesh3d-triangles mesh))
                  (vector-length (mesh3d-edges mesh))))

; mesh3d-semantic-geometry=? : mesh3d? mesh3d? -> boolean?
;;   Compares exactly the mesh fields that participate in a geometry key.
(define (mesh3d-semantic-geometry=? first second)
  (unless (mesh3d? first)
    (raise-argument-error 'mesh3d-semantic-geometry=? "mesh3d?" first))
  (unless (mesh3d? second)
    (raise-argument-error 'mesh3d-semantic-geometry=? "mesh3d?" second))
  (and (equal? (mesh3d-vertices first) (mesh3d-vertices second))
       (equal? (mesh3d-triangles first) (mesh3d-triangles second))
       (equal? (mesh3d-edges first) (mesh3d-edges second))
       (equal? (mesh3d-normals first) (mesh3d-normals second))
       (equal? (mesh3d-colors first) (mesh3d-colors second))))
