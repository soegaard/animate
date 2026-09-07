#lang racket/base

;;; SCENE-3D-U0: immutable semantic mesh-part identities

(require rackunit
         racket/list
         "../3d.rkt"
         "../private/3d/spatial-map3d.rkt")

(define vertices
  (vector origin3 (vec3 1 0 0) (vec3 0 1 0)))

(define (named-triangle id prefix)
  (mesh3d #:id id
          #:vertices vertices
          #:triangles (vector (vector 0 1 2))
          #:vertex-ids (vector (string->symbol (format "~a-v0" prefix))
                               (string->symbol (format "~a-v1" prefix))
                               (string->symbol (format "~a-v2" prefix)))
          ;; Derived edges follow triangle-side encounter order: 01, 12, 02.
          #:edge-ids (vector (string->symbol (format "~a-e01" prefix))
                             (string->symbol (format "~a-e12" prefix))
                             (string->symbol (format "~a-e02" prefix)))
          #:face-ids (vector (string->symbol (format "~a-front" prefix)))))

(module+ test
  (define named (named-triangle 'named 'left))
  (check-equal? (mesh3d-vertex-ids named) '#(left-v0 left-v1 left-v2))
  (check-equal? (mesh3d-edge-ids named) '#(left-e01 left-e12 left-e02))
  (check-equal? (mesh3d-face-ids named) '#(left-front))
  (check-eq? (mesh3d-vertex-id named 1) 'left-v1)
  (check-eq? (mesh3d-edge-id named 2) 'left-e02)
  (check-eq? (mesh3d-face-id named 0) 'left-front)

  ;; Omitted names retain their exact stable source indices rather than a
  ;; manufactured spelling that could be mistaken for an author declaration.
  (define anonymous
    (mesh3d #:id 'anonymous #:vertices vertices #:triangles (vector (vector 0 1 2))))
  (check-false (mesh3d-vertex-ids anonymous))
  (check-equal? (mesh3d-vertex-id anonymous 2) 2)
  (check-equal? (mesh3d-edge-id anonymous 1) 1)
  (check-equal? (mesh3d-face-id anonymous 0) 0)
  (check-exn exn:fail? (lambda () (mesh3d-face-id anonymous 1)))

  ;; A name is unique within its part kind, while kind remains part of every
  ;; access path. Thus `corner` may honestly name one vertex and one face.
  (define cross-kind
    (mesh3d #:id 'cross-kind #:vertices vertices #:triangles (vector (vector 0 1 2))
            #:vertex-ids '#(corner right top)
            #:face-ids '#(corner)))
  (check-eq? (mesh3d-vertex-id cross-kind 0) 'corner)
  (check-eq? (mesh3d-face-id cross-kind 0) 'corner)
  (check-exn exn:fail?
             (lambda ()
               (mesh3d #:id 'bad #:vertices vertices #:triangles (vector (vector 0 1 2))
                       #:vertex-ids '#(duplicate duplicate other))))
  (check-exn exn:fail?
             (lambda ()
               (mesh3d #:id 'bad #:vertices vertices #:triangles (vector (vector 0 1 2))
                       #:edge-ids '#(one two))))
  (check-exn exn:fail?
             (lambda ()
               (mesh3d #:id 'bad #:vertices vertices #:triangles (vector (vector 0 1 2))
                       #:face-ids '#("not-a-symbol"))))

  ;; Semantics deliberately sit above immutable render geometry. A GPU cache
  ;; shares the same geometry key; authoring/matching sees distinct keys.
  (check-equal? (mesh3d-geometry-key named) (mesh3d-geometry-key anonymous))
  (check-false (equal? (mesh3d-semantic-key named)
                       (mesh3d-semantic-key anonymous)))
  (check-eq? (mesh3d-semantic-key3d-provenance-schema
              (mesh3d-semantic-key named))
             'mesh3d-semantic-v1)

  ;; Operations whose parts remain one-to-one preserve all three vectors.
  (for ([derived
         (in-list
          (list (mesh3d-transform named (make-transform3 #:translation (vec3 2 0 0)))
                (mesh3d-reverse-winding named)
                (mesh3d-smooth-normals named)
                (mesh3d-wireframe named)
                (let-values ([(oriented _report) (mesh3d-orient-consistently named)])
                  oriented)))])
    (check-equal? (mesh3d-vertex-ids derived) (mesh3d-vertex-ids named))
    (check-equal? (mesh3d-edge-ids derived) (mesh3d-edge-ids named))
    (check-equal? (mesh3d-face-ids derived) (mesh3d-face-ids named)))

  ;; Flat normals split each shared vertex into separate face corners, so only
  ;; the unmodified one-to-one triangle identity remains meaningful.
  (define flat (mesh3d-flat-normals named))
  (check-false (mesh3d-vertex-ids flat))
  (check-false (mesh3d-edge-ids flat))
  (check-equal? (mesh3d-face-ids flat) (mesh3d-face-ids named))

  ;; Pointwise mapping retains exactly the source vertices/faces that remain.
  ;; Its derived-edge table is a new representation, so edge IDs are absent.
  (define pointwise
    (pointwise-map-mesh3d named identity-affine3 identity-affine3
                          (lambda (point) (vec3+ point (vec3 2 0 0)))))
  (check-equal? (mesh3d-vertex-ids pointwise) (mesh3d-vertex-ids named))
  (check-equal? (mesh3d-face-ids pointwise) (mesh3d-face-ids named))
  (check-false (mesh3d-edge-ids pointwise))

  ;; A slice retains untouched source parts and derives new part IDs from the
  ;; source edge/face that produced them. Repeating an unchanged slice keeps
  ;; every original vector exactly.
  (define unchanged
    (slice-mesh3d named (plane3 (vec3 -1 0 0) x-axis3) #:keep 'positive))
  ;; Slicing retains existing parts but its canonical polygon traversal can
  ;; reorder the indexed storage.
  (check-equal? (sort (vector->list (mesh3d-vertex-ids unchanged)) symbol<?)
                (sort (vector->list (mesh3d-vertex-ids named)) symbol<?))
  (check-equal? (sort (vector->list (mesh3d-edge-ids unchanged)) symbol<?)
                (sort (vector->list (mesh3d-edge-ids named)) symbol<?))
  (check-equal? (mesh3d-face-ids unchanged) (mesh3d-face-ids named))
  (define sliced
    (slice-mesh3d named (plane3 (vec3 1/2 0 0) x-axis3) #:keep 'positive))
  (check-not-false (member 'left-v1 (vector->list (mesh3d-vertex-ids sliced))))
  (check-true (for/and ([part-id (in-vector (mesh3d-vertex-ids sliced))])
                (symbol? part-id)))
  (check-false (equal? (mesh3d-face-ids sliced) (mesh3d-face-ids named)))

  ;; Merge keeps an unambiguous supplied namespace, and refuses a collision
  ;; rather than minting a hidden namespace that authors cannot address.
  (define right (named-triangle 'right 'right))
  (define merged (mesh3d-merge (list named right) #:id 'merged))
  (check-equal? (mesh3d-vertex-ids merged)
                '#(left-v0 left-v1 left-v2 right-v0 right-v1 right-v2))
  (check-equal? (mesh3d-face-ids merged) '#(left-front right-front))
  (check-exn exn:fail?
             (lambda () (mesh3d-merge (list named named) #:id 'ambiguous)))

  ;; Exact welding preserves a complete, agreeing namespace. When an operation
  ;; later contributes unnamed geometry (such as a cap), only those part kinds
  ;; with complete provenance stay annotated.
  (define welded (mesh3d-weld (list named) #:id 'welded))
  (check-equal? (mesh3d-vertex-ids welded) (mesh3d-vertex-ids named))
  (check-equal? (mesh3d-edge-ids welded) (mesh3d-edge-ids named))
  (check-equal? (mesh3d-face-ids welded) (mesh3d-face-ids named)))
