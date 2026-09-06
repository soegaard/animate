#lang racket/base

;;;
;;; Semantic Two-Sided Mesh Cuts and Deterministic Cap Meshes
;;;

(require racket/list
         "../geometry.rkt"
         "cap-style3d.rkt"
         "clipping3d.rkt"
         "material3d.rkt"
         "mesh3d.rkt"
         "plane-basis3d.rkt"
         "ray-plane.rkt"
         "section-settings3d.rkt"
         "spatial-visual.rkt"
         "vec3.rkt")

(provide cut-mesh3d
         (struct-out mesh-cut3d-result)
         cap-section3d)

(struct mesh-cut3d-result
  (positive negative section positive-cap negative-cap diagnostics)
  #:transparent)

; cut-mesh3d : mesh3d? (or/c plane3? clip-plane3d?) ... -> mesh-cut3d-result?
;; Computes both retained half-spaces from exactly one immutable source mesh.
;; The cap fields remain separate on purpose: callers can layer, style, pick,
;; or merge them explicitly without losing provenance of the exposed surface.
(define (cut-mesh3d mesh plane-or-clip
                    #:settings [settings (section3d-settings-for-bounds (mesh3d-local-bounds mesh))]
                    #:positive-id [positive-id (string->symbol (format "~a-positive" (spatial-id mesh)))]
                    #:negative-id [negative-id (string->symbol (format "~a-negative" (spatial-id mesh)))]
                    #:cap [cap #f])
  (unless (mesh3d? mesh) (raise-argument-error 'cut-mesh3d "mesh3d?" mesh))
  (unless (section3d-settings? settings)
    (raise-argument-error 'cut-mesh3d "section3d-settings?" settings))
  (unless (and (symbol? positive-id) (symbol? negative-id))
    (raise-argument-error 'cut-mesh3d "symbol identifiers" (list positive-id negative-id)))
  (unless (or (not cap) (cap-style3d? cap))
    (raise-argument-error 'cut-mesh3d "#f or cap-style3d?" cap))
  (define plane (if (clip-plane3d? plane-or-clip)
                    (clip-plane3d-plane plane-or-clip)
                    plane-or-clip))
  (unless (plane3? plane) (raise-argument-error 'cut-mesh3d "plane3? or clip-plane3d?" plane-or-clip))
  (define section (section-by-plane3d mesh plane #:settings settings))
  (define positive (slice-mesh3d mesh plane #:id positive-id #:keep 'positive #:settings settings))
  (define negative (slice-mesh3d mesh plane #:id negative-id #:keep 'negative #:settings settings))
  (define positive-cap
    (and cap
         (spatial-with-transform
          (cap-section3d section #:side 'positive #:id (string->symbol (format "~a-cap" positive-id))
                         #:style cap)
          (spatial-transform mesh))))
  (define negative-cap
    (and cap
         (spatial-with-transform
          (cap-section3d section #:side 'negative #:id (string->symbol (format "~a-cap" negative-id))
                         #:style cap)
          (spatial-transform mesh))))
  (mesh-cut3d-result
   positive negative section positive-cap negative-cap
   (hasheq 'settings settings
           'source-id (spatial-id mesh)
           'positive-triangle-count (vector-length (mesh3d-triangles positive))
           'negative-triangle-count (vector-length (mesh3d-triangles negative))
           'capped? (and cap #t)
           'cap-limit "simple concave loops are triangulated; nested section loops (cap holes) are diagnosed")))

; cap-section3d : section3d? #:side ... -> (or/c #f mesh3d?)
;; Produces flat cap geometry for every closed, simple, non-nested component.
;; Open chains do not manufacture a false surface.  The cap is purposely a
;; separate mesh so original smooth side normals cannot be overwritten.
(define (cap-section3d section #:side [side 'positive]
                       #:id [id 'section-cap]
                       #:style [style default-cap-style3d])
  (unless (section3d? section) (raise-argument-error 'cap-section3d "section3d?" section))
  (unless (memq side '(positive negative))
    (raise-argument-error 'cap-section3d "positive or negative side" side))
  (unless (symbol? id) (raise-argument-error 'cap-section3d "symbol?" id))
  (unless (cap-style3d? style) (raise-argument-error 'cap-section3d "cap-style3d?" style))
  (define loops (section3d-loops section))
  (cond [(null? loops) #f]
        [else
         (when (nested-section-loops? (section3d-basis section) loops)
           (raise-arguments-error 'cap-section3d
                                  "a section without nested loops; cap holes are not implemented"
                                  "section" section))
         (define vertices-reversed '())
         (define normals-reversed '())
         (define triangles-reversed '())
         (define next-index 0)
         (define basis (section3d-basis section))
         ;; The positive kept side exposes the removed negative half-space.
         (define normal (vec3-scale (if (eq? side 'positive) -1 1)
                                    (plane3-normal (section3d-plane section))))
         (define offset (vec3-scale (cap-style3d-offset style) normal))
         (for ([loop (in-list loops)])
           (define ordered (canonical-counterclockwise-loop basis loop))
           (define local-triangles (triangulate-simple-loop basis ordered))
           (define base next-index)
           (set! next-index (+ next-index (length ordered)))
           (for ([point (in-list ordered)])
             (set! vertices-reversed (cons (vec3+ point offset) vertices-reversed))
             (set! normals-reversed (cons normal normals-reversed)))
           (for ([triangle (in-list local-triangles)])
             ;; A CCW plane-basis triangle faces the plane normal.  The
             ;; positive retained half must expose the opposite normal.
             (define indices
               (vector (+ base (vector-ref triangle 0))
                       (+ base (vector-ref triangle 1))
                       (+ base (vector-ref triangle 2))))
             (set! triangles-reversed
                   (cons (if (eq? side 'positive)
                             (vector (vector-ref indices 0)
                                     (vector-ref indices 2)
                                     (vector-ref indices 1))
                             indices)
                         triangles-reversed))))
         (mesh3d #:id id
                 #:vertices (list->vector (reverse vertices-reversed))
                 #:triangles (list->vector (reverse triangles-reversed))
                 #:normals (list->vector (reverse normals-reversed))
                 #:material (cap-style3d-material style))]))

;; An ear-clipping input is a cyclic list of the original point indexes.  The
;; public section points stay in 3D; all robustness decisions take place in a
;; stable section-plane coordinate system.
(struct cap-corner (index point coordinates) #:transparent)

(define (canonical-counterclockwise-loop basis loop)
  (unless (>= (length loop) 3)
    (raise-arguments-error 'cap-section3d "a closed component with at least three points"
                           "loop" loop))
  (define ccw
    (if (negative? (plane-basis3d-signed-area basis loop)) (reverse loop) loop))
  ;; A section graph may choose a different starting node after harmless mesh
  ;; reindexing.  Rotate at the lexicographically least plane point so cap
  ;; vertex/triangle order remains deterministic.
  (define start
    (for/fold ([best 0]) ([point (in-list (cdr ccw))] [index (in-naturals 1)])
      (if (coordinates<? (plane-basis3d-project basis point)
                         (plane-basis3d-project basis (list-ref ccw best)))
          index
          best)))
  (append (drop ccw start) (take ccw start)))

(define (triangulate-simple-loop basis points)
  (define corners
    (for/list ([point (in-list points)] [index (in-naturals)])
      (cap-corner index point (plane-basis3d-project basis point))))
  (define (clip current triangles-reversed)
    (cond [(= (length current) 3)
           (reverse
            (cons (vector (cap-corner-index (first current))
                          (cap-corner-index (second current))
                          (cap-corner-index (third current)))
                  triangles-reversed))]
          [else
           (define ear-index
             (for/first ([index (in-range (length current))]
                         #:when (ear? current index))
               index))
           (cond [ear-index
                  (define previous (list-ref current (modulo (sub1 ear-index) (length current))))
                  (define corner (list-ref current ear-index))
                  (define next (list-ref current (modulo (add1 ear-index) (length current))))
                  (clip (remove-at current ear-index)
                        (cons (vector (cap-corner-index previous)
                                      (cap-corner-index corner)
                                      (cap-corner-index next))
                              triangles-reversed))]
                 ;; Collinear corners have no area and must not make an
                 ;; otherwise valid concave contour appear untriangulable.
                 [(for/first ([index (in-range (length current))]
                              #:when (collinear-corner? current index))
                    index)
                  => (lambda (index) (clip (remove-at current index) triangles-reversed))]
                 [else
                  (raise-arguments-error 'cap-section3d
                                         "a simple non-self-intersecting section loop"
                                         "reason" "no deterministic ear found"
                                         "points" points)])]))
  (clip corners '()))

(define (ear? corners index)
  (define count (length corners))
  (define previous (list-ref corners (modulo (sub1 index) count)))
  (define corner (list-ref corners index))
  (define next (list-ref corners (modulo (add1 index) count)))
  (and (positive? (cross2 (cap-corner-coordinates previous)
                          (cap-corner-coordinates corner)
                          (cap-corner-coordinates next)))
       (not
        (for/or ([other (in-list corners)] [other-index (in-naturals)]
                 #:unless (or (= other-index (modulo (sub1 index) count))
                              (= other-index index)
                              (= other-index (modulo (add1 index) count))))
          (point-in-triangle? (cap-corner-coordinates other)
                              (cap-corner-coordinates previous)
                              (cap-corner-coordinates corner)
                              (cap-corner-coordinates next))))))

(define (collinear-corner? corners index)
  (define count (length corners))
  (zero? (cross2 (cap-corner-coordinates (list-ref corners (modulo (sub1 index) count)))
                 (cap-corner-coordinates (list-ref corners index))
                 (cap-corner-coordinates (list-ref corners (modulo (add1 index) count))))))

(define (cross2 first second third)
  (- (* (- (vector-ref second 0) (vector-ref first 0))
        (- (vector-ref third 1) (vector-ref first 1)))
     (* (- (vector-ref second 1) (vector-ref first 1))
        (- (vector-ref third 0) (vector-ref first 0)))))

(define (point-in-triangle? point first second third)
  (and (not (negative? (cross2 first second point)))
       (not (negative? (cross2 second third point)))
       (not (negative? (cross2 third first point)))))

(define (remove-at values index)
  (append (take values index) (drop values (add1 index))))

(define (coordinates<? first second)
  (or (< (vector-ref first 0) (vector-ref second 0))
      (and (= (vector-ref first 0) (vector-ref second 0))
           (< (vector-ref first 1) (vector-ref second 1)))))

(define (nested-section-loops? basis loops)
  (for/or ([loop (in-list loops)])
    (define point (plane-basis3d-project basis (car loop)))
    (for/or ([other (in-list loops)] #:unless (eq? loop other))
      (point-in-polygon? point
                         (for/list ([other-point (in-list other)])
                           (plane-basis3d-project basis other-point))))))

(define (point-in-polygon? point polygon)
  (for/fold ([inside? #f])
            ([first (in-list polygon)]
             [second (in-list (append (cdr polygon) (list (car polygon))))])
    (define first-y (vector-ref first 1))
    (define second-y (vector-ref second 1))
    (define crosses? (not (eq? (> first-y (vector-ref point 1))
                               (> second-y (vector-ref point 1)))))
    (define x-at-y
      (if (= first-y second-y)
          +inf.0
          (+ (vector-ref first 0)
             (* (- (vector-ref point 1) first-y)
                (/ (- (vector-ref second 0) (vector-ref first 0))
                   (- second-y first-y))))))
    (if (and crosses? (< (vector-ref point 0) x-at-y))
        (not inside?)
        inside?)))
