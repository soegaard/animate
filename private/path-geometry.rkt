#lang racket/base

;;;
;;; Path Geometry
;;;

;; Defines immutable two-dimensional paths made from ordered line and cubic
;; Bézier segments.
;;
;; Path data is semantic model state. This module contains no Pict, bitmap,
;; filesystem, process, browser, or JavaScript dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "geometry.rkt")

;; Exports
(provide (struct-out line-path-segment)
         (struct-out cubic-bezier-path-segment)
         (struct-out path-subpath)
         (struct-out path-geometry)
         path-segment?
         empty-path-geometry
         path-geometry-empty?
         path-subpath-points
         path-geometry-subpath-points
         path-geometry-map-points
         path-geometry-translate
         path-geometry-reverse
         path-geometry->cubic
         path-geometry-morph-normalizable?
         path-geometry-align-for-morph
         path-geometry-align-open-for-morph
         path-geometry-align-open-compound-for-morph
         path-geometry-align-mixed-compound-for-morph
         path-geometry-prepare-topology-changing-morph
         path-geometry-align-compound-for-morph
         path-geometry-normalize-for-morph
         path-geometry-morph-compatible?
         path-geometry-lerp
         path-geometry-bounds
         path-geometry-center
         path-subpath-length
         path-geometry-length
         path-geometry-point-at
         path-geometry-tangent-at
         path-geometry-normal-at
         path-geometry-offset
         path-geometry-partial
         path-geometry-cycle-start
         polyline-path
         polygon-path
         cubic-bezier-path)


;;;
;;; Data Representation
;;;

(struct line-path-segment (end)
  #:transparent
  #:guard
  (lambda (end who)
    (unless (vec2? end)
      (raise-argument-error who "vec2?" end))
    end))

;; line-path-segment represents one straight segment in a subpath.
;;  - end  vec2?  endpoint in the subpath's local coordinate system.

(struct cubic-bezier-path-segment (control1 control2 end)
  #:transparent
  #:guard
  (lambda (control1 control2 end who)
    (unless (vec2? control1)
      (raise-argument-error who "vec2?" control1))
    (unless (vec2? control2)
      (raise-argument-error who "vec2?" control2))
    (unless (vec2? end)
      (raise-argument-error who "vec2?" end))
    (values control1 control2 end)))

;; cubic-bezier-path-segment represents one cubic Bézier segment.
;;  - control1  vec2?  first local control point after the segment start.
;;  - control2  vec2?  second local control point before the endpoint.
;;  - end       vec2?  endpoint in the subpath's local coordinate system.

(struct path-subpath (start segments closed?)
  #:transparent
  #:guard
  (lambda (start segments closed? who)
    (unless (vec2? start)
      (raise-argument-error who "vec2?" start))
    (unless (and (list? segments)
                 (andmap path-segment? segments))
      (raise-argument-error
       who
       "list of supported path segments"
       segments))
    (unless (boolean? closed?)
      (raise-argument-error who "boolean?" closed?))
    (values start segments closed?)))

;; path-subpath represents one ordered connected figure.
;;  - start     vec2?                   first local point.
;;  - segments  (listof path-segment?)  segments in traversal order.
;;                                     Ordering is significant.
;;  - closed?   boolean?                whether the last point reconnects to
;;                                     start when stroked and filled.

(struct path-geometry (subpaths)
  #:transparent
  #:guard
  (lambda (subpaths who)
    (unless (and (list? subpaths)
                 (andmap path-subpath? subpaths))
      (raise-argument-error who "list of path-subpath values" subpaths))
    subpaths))

;; path-geometry represents zero or more ordered subpaths.
;;  - subpaths  (listof path-subpath?)  subpaths in traversal and fill order.
;;                                      Ordering is significant.


;;;
;;; Predicates and Constants
;;;

; path-segment? : any/c -> boolean?
;;   Reports whether value is a supported semantic path segment.
(define (path-segment? value)
  (or (line-path-segment? value)
      (cubic-bezier-path-segment? value)))

; empty-path-geometry : path-geometry?
;;   Gives path geometry containing no subpaths.
(define empty-path-geometry
  (path-geometry '()))

; path-geometry-empty? : path-geometry? -> boolean?
;;   Reports whether geometry contains no subpaths.
(define (path-geometry-empty? geometry)
  (check-path-geometry 'path-geometry-empty? geometry)
  (null? (path-geometry-subpaths geometry)))


;;;
;;; Point Access
;;;

; path-subpath-points : path-subpath? -> (listof vec2?)
;;   Returns the start and segment endpoints in traversal order.
(define (path-subpath-points subpath)
  (check-path-subpath 'path-subpath-points subpath)
  (cons (path-subpath-start subpath)
        (for/list ([segment (in-list (path-subpath-segments subpath))])
          (path-segment-end segment))))

; path-geometry-subpath-points : path-geometry?
;                                -> (listof (listof vec2?))
;;   Returns one traversal-ordered endpoint list for each subpath.
(define (path-geometry-subpath-points geometry)
  (check-path-geometry 'path-geometry-subpath-points geometry)
  (for/list ([subpath (in-list (path-geometry-subpaths geometry))])
    (path-subpath-points subpath)))

; path-segment-end : path-segment? -> vec2?
;;   Returns the endpoint of segment.
(define (path-segment-end segment)
  (cond
    [(line-path-segment? segment)
     (line-path-segment-end segment)]
    [(cubic-bezier-path-segment? segment)
     (cubic-bezier-path-segment-end segment)]
    [else
     (raise-argument-error
      'path-segment-end
      "supported path segment"
      segment)]))


;;;
;;; Point Mapping
;;;

; path-geometry-map-points : path-geometry? (-> vec2? vec2?)
;                            -> path-geometry?
;;   Applies transform-point to every stored point while preserving structure.
(define (path-geometry-map-points geometry transform-point)
  (check-path-geometry 'path-geometry-map-points geometry)
  (unless (and (procedure? transform-point)
               (procedure-arity-includes? transform-point 1))
    (raise-argument-error
     'path-geometry-map-points
     "(procedure-arity-includes/c 1)"
     transform-point))
  (define (map-point point)
    (define result
      (transform-point point))
    (unless (vec2? result)
      (raise-arguments-error
       'path-geometry-map-points
       "the point transformation must return a vec2"
       "point" point
       "result" result))
    result)
  (path-geometry
   (for/list ([subpath (in-list (path-geometry-subpaths geometry))])
     (path-subpath
      (map-point (path-subpath-start subpath))
      (for/list ([segment (in-list (path-subpath-segments subpath))])
        (map-path-segment-points segment map-point))
      (path-subpath-closed? subpath)))))

; path-geometry-translate : path-geometry? vec2? -> path-geometry?
;;   Returns geometry with every local point shifted by displacement.
(define (path-geometry-translate geometry displacement)
  (check-path-geometry 'path-geometry-translate geometry)
  (unless (vec2? displacement)
    (raise-argument-error 'path-geometry-translate "vec2?" displacement))
  (path-geometry-map-points
   geometry
   (lambda (point)
     (vec2+ point displacement))))

; path-geometry-reverse : path-geometry? -> path-geometry?
;;   Returns geometry with every subpath traversed in the opposite direction.
;;   Open subpaths start at their former endpoint. Closed subpaths keep their
;;   stored start point so total arc-length fractions reverse as f -> 1-f.
(define (path-geometry-reverse geometry)
  (check-path-geometry 'path-geometry-reverse geometry)
  (path-geometry
   (for/list ([subpath (in-list (path-geometry-subpaths geometry))])
     (path-subpath-reverse-traversal subpath))))

; path-subpath-reverse-traversal : path-subpath? -> path-subpath?
;;   Reverses one subpath while preserving its exact line/cubic geometry.
(define (path-subpath-reverse-traversal subpath)
  (define start
    (path-subpath-start subpath))
  (define-values (pieces final-point)
    (path-subpath-explicit-pieces subpath))
  (define closed?
    (path-subpath-closed? subpath))
  (define reverse-start
    (if closed? start final-point))
  (define reversed-explicit
    (for/list ([piece (in-list (reverse pieces))])
      (reverse-path-piece piece)))
  (define reversed-segments
    (if (and closed?
             (not (vec2-coordinate=? final-point start)))
        ;; The original implicit closing line is the first edge in reverse
        ;; traversal. Materialize it so the closed path can keep the same
        ;; stored start point. The final synthetic close is then zero length.
        (cons (line-path-segment final-point)
              reversed-explicit)
        reversed-explicit))
  (path-subpath reverse-start reversed-segments closed?))

; path-subpath-explicit-pieces : path-subpath?
;                                -> (values (listof path-piece?) vec2?)
;;   Returns explicit segments paired with their starts and the final endpoint.
(define (path-subpath-explicit-pieces subpath)
  (for/fold ([reversed-pieces '()]
             [current-point (path-subpath-start subpath)]
             #:result (values (reverse reversed-pieces) current-point))
            ([segment (in-list (path-subpath-segments subpath))])
    (values (cons (path-piece current-point segment)
                  reversed-pieces)
            (path-segment-end segment))))

; reverse-path-piece : path-piece? -> path-segment?
;;   Reverses one explicit line or cubic piece.
(define (reverse-path-piece piece)
  (define start
    (path-piece-start piece))
  (define segment
    (path-piece-segment piece))
  (cond
    [(line-path-segment? segment)
     (line-path-segment start)]
    [(cubic-bezier-path-segment? segment)
     (cubic-bezier-path-segment
      (cubic-bezier-path-segment-control2 segment)
      (cubic-bezier-path-segment-control1 segment)
      start)]
    [else
     (raise-argument-error
      'path-geometry-reverse
      "supported path segment"
      segment)]))

; vec2-coordinate=? : vec2? vec2? -> boolean?
;;   Reports coordinate equality without requiring identical numeric exactness.
(define (vec2-coordinate=? left right)
  (and (= (vec2-x left) (vec2-x right))
       (= (vec2-y left) (vec2-y right))))

; map-path-segment-points : path-segment? (-> vec2? vec2?) -> path-segment?
;;   Maps every point stored by one supported segment.
(define (map-path-segment-points segment transform-point)
  (cond
    [(line-path-segment? segment)
     (line-path-segment
      (transform-point (line-path-segment-end segment)))]
    [(cubic-bezier-path-segment? segment)
     (cubic-bezier-path-segment
      (transform-point
       (cubic-bezier-path-segment-control1 segment))
      (transform-point
       (cubic-bezier-path-segment-control2 segment))
      (transform-point
       (cubic-bezier-path-segment-end segment)))]
    [else
     (raise-argument-error
      'map-path-segment-points
      "supported path segment"
      segment)]))


;;;
;;; Path Morph Normalization
;;;

; path-geometry->cubic : path-geometry? -> path-geometry?
;;   Converts every stored line segment to an equivalent cubic segment.
(define (path-geometry->cubic geometry)
  (check-path-geometry 'path-geometry->cubic geometry)
  (define original-subpaths
    (path-geometry-subpaths geometry))
  (define cubic-subpaths
    (for/list ([subpath (in-list original-subpaths)])
      (path-subpath->cubic subpath)))
  (if (same-objects-in-order? original-subpaths cubic-subpaths)
      geometry
      (path-geometry cubic-subpaths)))

; path-geometry-morph-normalizable? : path-geometry? path-geometry? -> boolean?
;;   Reports whether two paths can be normalized by cubic conversion and splitting.
(define (path-geometry-morph-normalizable? from to)
  (check-path-geometry 'path-geometry-morph-normalizable? from)
  (check-path-geometry 'path-geometry-morph-normalizable? to)
  (not (path-geometry-normalization-problem from to)))

; path-geometry-align-for-morph : path-geometry? path-geometry?
;                                  [#:allow-reverse? boolean?]
;                                  [#:sample-count exact-integer?]
;                                  -> path-geometry?
;;   Aligns one closed destination loop to a source by phase and direction.
(define (path-geometry-align-for-morph source destination
                                       #:allow-reverse? [allow-reverse? #t]
                                       #:sample-count [sample-count 64])
  (check-path-geometry 'path-geometry-align-for-morph source)
  (check-path-geometry 'path-geometry-align-for-morph destination)
  (check-morph-alignment-options
   'path-geometry-align-for-morph
   allow-reverse?
   sample-count)
  (check-morph-alignment-loop
   'path-geometry-align-for-morph
   "source"
   source)
  (check-morph-alignment-loop
   'path-geometry-align-for-morph
   "destination"
   destination)
  (define-values (aligned-destination _score)
    (align-validated-closed-loop-for-morph
     source
     destination
     allow-reverse?
     sample-count))
  aligned-destination)

; path-geometry-align-open-for-morph : path-geometry? path-geometry?
;                                       [#:allow-reverse? boolean?]
;                                       [#:sample-count exact-integer?]
;                                       -> path-geometry?
;;   Aligns one open destination path to a source by endpoint direction.
(define (path-geometry-align-open-for-morph source destination
                                            #:allow-reverse? [allow-reverse? #t]
                                            #:sample-count [sample-count 64])
  (check-path-geometry 'path-geometry-align-open-for-morph source)
  (check-path-geometry 'path-geometry-align-open-for-morph destination)
  (check-morph-alignment-options
   'path-geometry-align-open-for-morph
   allow-reverse?
   sample-count)
  (check-morph-alignment-open-path
   'path-geometry-align-open-for-morph
   "source"
   source)
  (check-morph-alignment-open-path
   'path-geometry-align-open-for-morph
   "destination"
   destination)
  (define-values (aligned-destination _score)
    (align-open-path-from-samples
     (open-path-alignment-samples source sample-count)
     destination
     allow-reverse?
     sample-count))
  aligned-destination)

; path-geometry-align-open-compound-for-morph : path-geometry? path-geometry?
;                                                [#:allow-reverse? boolean?]
;                                                [#:sample-count exact-integer?]
;                                                -> path-geometry?
;;   Globally pairs equal-count open subpaths, then aligns endpoint direction.
(define (path-geometry-align-open-compound-for-morph
         source
         destination
         #:allow-reverse? [allow-reverse? #t]
         #:sample-count [sample-count 64])
  (check-path-geometry 'path-geometry-align-open-compound-for-morph source)
  (check-path-geometry 'path-geometry-align-open-compound-for-morph destination)
  (check-morph-alignment-options
   'path-geometry-align-open-compound-for-morph
   allow-reverse?
   sample-count)
  (define source-subpaths
    (path-geometry-subpaths source))
  (define destination-subpaths
    (path-geometry-subpaths destination))
  (unless (= (length source-subpaths)
             (length destination-subpaths))
    (raise-arguments-error
     'path-geometry-align-open-compound-for-morph
     "automatic open-compound morph alignment requires equal subpath counts"
     "source-subpath-count" (length source-subpaths)
     "destination-subpath-count" (length destination-subpaths)))
  (when (null? source-subpaths)
    (raise-arguments-error
     'path-geometry-align-open-compound-for-morph
     "automatic open-compound morph alignment requires at least one open subpath"
     "source" source
     "destination" destination))
  (for ([subpath (in-list source-subpaths)]
        [index (in-naturals)])
    (check-morph-alignment-open-subpath
     'path-geometry-align-open-compound-for-morph
     "source"
     index
     subpath))
  (for ([subpath (in-list destination-subpaths)]
        [index (in-naturals)])
    (check-morph-alignment-open-subpath
     'path-geometry-align-open-compound-for-morph
     "destination"
     index
     subpath))
  (define candidate-matrix
    (for/vector ([source-subpath (in-list source-subpaths)])
      (define source-path
        (path-geometry (list source-subpath)))
      (define source-samples
        (open-path-alignment-samples source-path sample-count))
      (for/vector ([destination-subpath (in-list destination-subpaths)])
        (define destination-path
          (path-geometry (list destination-subpath)))
        (define-values (aligned-path selected-score)
          (align-open-path-from-samples
           source-samples
           destination-path
           allow-reverse?
           sample-count))
        (compound-subpath-candidate
         (car (path-geometry-subpaths aligned-path))
         selected-score))))
  (define assignment
    (minimum-cost-subpath-assignment candidate-matrix))
  (define aligned-subpaths
    (for/list ([source-index (in-range (vector-length assignment))])
      (define destination-index
        (vector-ref assignment source-index))
      (compound-subpath-candidate-subpath
       (vector-ref
        (vector-ref candidate-matrix source-index)
        destination-index))))
  (if (same-objects-in-order? destination-subpaths aligned-subpaths)
      destination
      (path-geometry aligned-subpaths)))

; path-geometry-align-mixed-compound-for-morph : path-geometry? path-geometry?
;                                                 [#:allow-reverse? boolean?]
;                                                 [#:sample-count exact-integer?]
;                                                 -> path-geometry?
;;   Globally pairs equal-count topology classes, then aligns each subpath.
(define (path-geometry-align-mixed-compound-for-morph
         source
         destination
         #:allow-reverse? [allow-reverse? #t]
         #:sample-count [sample-count 64])
  (check-path-geometry 'path-geometry-align-mixed-compound-for-morph source)
  (check-path-geometry 'path-geometry-align-mixed-compound-for-morph destination)
  (check-morph-alignment-options
   'path-geometry-align-mixed-compound-for-morph
   allow-reverse?
   sample-count)
  (define source-subpaths
    (path-geometry-subpaths source))
  (define destination-subpaths
    (path-geometry-subpaths destination))
  (when (null? source-subpaths)
    (raise-arguments-error
     'path-geometry-align-mixed-compound-for-morph
     "automatic mixed-compound morph alignment requires at least one subpath"
     "source" source
     "destination" destination))
  (for ([subpath (in-list source-subpaths)]
        [index (in-naturals)])
    (check-morph-alignment-mixed-subpath
     'path-geometry-align-mixed-compound-for-morph
     "source"
     index
     subpath))
  (for ([subpath (in-list destination-subpaths)]
        [index (in-naturals)])
    (check-morph-alignment-mixed-subpath
     'path-geometry-align-mixed-compound-for-morph
     "destination"
     index
     subpath))
  (define source-open-indexes
    (subpath-indexes-with-closure source-subpaths #f))
  (define source-closed-indexes
    (subpath-indexes-with-closure source-subpaths #t))
  (define destination-open-indexes
    (subpath-indexes-with-closure destination-subpaths #f))
  (define destination-closed-indexes
    (subpath-indexes-with-closure destination-subpaths #t))
  (unless (and (= (length source-open-indexes)
                  (length destination-open-indexes))
               (= (length source-closed-indexes)
                  (length destination-closed-indexes)))
    (raise-arguments-error
     'path-geometry-align-mixed-compound-for-morph
     "automatic mixed-compound morph alignment requires matching open and closed subpath counts"
     "source-open-count" (length source-open-indexes)
     "destination-open-count" (length destination-open-indexes)
     "source-closed-count" (length source-closed-indexes)
     "destination-closed-count" (length destination-closed-indexes)))
  (define aligned-by-source
    (make-vector (length source-subpaths) #f))
  (align-mixed-subpath-class!
   aligned-by-source
   source-subpaths
   destination-subpaths
   source-open-indexes
   destination-open-indexes
   #f
   allow-reverse?
   sample-count)
  (align-mixed-subpath-class!
   aligned-by-source
   source-subpaths
   destination-subpaths
   source-closed-indexes
   destination-closed-indexes
   #t
   allow-reverse?
   sample-count)
  (define aligned-subpaths
    (vector->list aligned-by-source))
  (if (same-objects-in-order? destination-subpaths aligned-subpaths)
      destination
      (path-geometry aligned-subpaths)))

; path-geometry-prepare-topology-changing-morph : path-geometry? path-geometry?
;                                                   [#:allow-reverse? boolean?]
;                                                   [#:sample-count exact-integer?]
;                                                   [#:birth-anchor (or/c 'bounds-center vec2?)]
;                                                   [#:death-anchor (or/c 'bounds-center vec2?)]
;                                                   [#:birth-anchor-map hash?]
;                                                   [#:death-anchor-map hash?]
;                                                   [#:birth-penalty (or/c 'forced nonnegative-finite-real?)]
;                                                   [#:death-penalty (or/c 'forced nonnegative-finite-real?)]
;                                                   [#:birth-penalty-map hash?]
;                                                   [#:death-penalty-map hash?]
;                                                   [#:match-penalty-map hash?]
;                                                   -> (values path-geometry?
;                                                              path-geometry?)
;;   Pairs matching topology classes and adds deterministic birth/death seeds.
;;   Numeric penalties additionally permit voluntary death+birth replacement.
(define (path-geometry-prepare-topology-changing-morph
         source
         destination
         #:allow-reverse? [allow-reverse? #t]
         #:sample-count [sample-count 64]
         #:birth-anchor [birth-anchor 'bounds-center]
         #:death-anchor [death-anchor 'bounds-center]
         #:birth-anchor-map [birth-anchor-map #hash()]
         #:death-anchor-map [death-anchor-map #hash()]
         #:birth-penalty [birth-penalty 'forced]
         #:death-penalty [death-penalty 'forced]
         #:birth-penalty-map [birth-penalty-map #hash()]
         #:death-penalty-map [death-penalty-map #hash()]
         #:match-penalty-map [match-penalty-map #hash()])
  (check-path-geometry 'path-geometry-prepare-topology-changing-morph source)
  (check-path-geometry 'path-geometry-prepare-topology-changing-morph destination)
  (check-morph-alignment-options
   'path-geometry-prepare-topology-changing-morph
   allow-reverse?
   sample-count)
  (check-topology-morph-anchor
   'path-geometry-prepare-topology-changing-morph
   "#:birth-anchor"
   birth-anchor)
  (check-topology-morph-anchor
   'path-geometry-prepare-topology-changing-morph
   "#:death-anchor"
   death-anchor)
  (check-topology-morph-penalties
   'path-geometry-prepare-topology-changing-morph
   birth-penalty
   death-penalty)
  (define source-subpaths
    (path-geometry-subpaths source))
  (define destination-subpaths
    (path-geometry-subpaths destination))
  (define normalized-birth-anchor-map
    (normalize-topology-morph-anchor-map
     'path-geometry-prepare-topology-changing-morph
     "#:birth-anchor-map"
     birth-anchor-map
     (length destination-subpaths)))
  (define normalized-death-anchor-map
    (normalize-topology-morph-anchor-map
     'path-geometry-prepare-topology-changing-morph
     "#:death-anchor-map"
     death-anchor-map
     (length source-subpaths)))
  (define normalized-birth-penalty-map
    (normalize-topology-morph-penalty-map
     'path-geometry-prepare-topology-changing-morph
     "#:birth-penalty-map"
     birth-penalty-map
     (length destination-subpaths)))
  (define normalized-death-penalty-map
    (normalize-topology-morph-penalty-map
     'path-geometry-prepare-topology-changing-morph
     "#:death-penalty-map"
     death-penalty-map
     (length source-subpaths)))
  (define normalized-match-penalty-map
    (normalize-topology-morph-match-penalty-map
     'path-geometry-prepare-topology-changing-morph
     "#:match-penalty-map"
     match-penalty-map
     source-subpaths
     destination-subpaths))
  (check-topology-morph-penalty-map-mode
   'path-geometry-prepare-topology-changing-morph
   birth-penalty
   death-penalty
   normalized-birth-penalty-map
   normalized-death-penalty-map)
  (for ([subpath (in-list source-subpaths)]
        [index (in-naturals)])
    (check-morph-alignment-mixed-subpath
     'path-geometry-prepare-topology-changing-morph
     "source"
     index
     subpath))
  (for ([subpath (in-list destination-subpaths)]
        [index (in-naturals)])
    (check-morph-alignment-mixed-subpath
     'path-geometry-prepare-topology-changing-morph
     "destination"
     index
     subpath))
  (define source-open-indexes
    (subpath-indexes-with-closure source-subpaths #f))
  (define source-closed-indexes
    (subpath-indexes-with-closure source-subpaths #t))
  (define destination-open-indexes
    (subpath-indexes-with-closure destination-subpaths #f))
  (define destination-closed-indexes
    (subpath-indexes-with-closure destination-subpaths #t))
  (define forced-only?
    (eq? birth-penalty 'forced))
  (define matching-topology-counts?
    (and (= (length source-open-indexes)
            (length destination-open-indexes))
         (= (length source-closed-indexes)
            (length destination-closed-indexes))))
  (cond
    [(and (null? source-subpaths) (null? destination-subpaths))
     (values source destination)]
    [(and forced-only?
          matching-topology-counts?
          (zero? (hash-count normalized-match-penalty-map)))
     ;; The default SCENE-AH/AI policy reduces exactly to SCENE-AG when no
     ;; topology-class count difference forces a birth or death.
     (values
      source
      (path-geometry-align-mixed-compound-for-morph
       source
       destination
       #:allow-reverse? allow-reverse?
       #:sample-count sample-count))]
    [else
     (define class-pair-procedure
       (if forced-only?
           topology-changing-class-pairs
           penalized-topology-changing-class-pairs))
     (define (class-pairs source-indexes destination-indexes closed?)
       (if forced-only?
           (class-pair-procedure
            source-subpaths
            destination-subpaths
            source-indexes
            destination-indexes
            closed?
            allow-reverse?
            sample-count
            birth-anchor
            death-anchor
            normalized-birth-anchor-map
            normalized-death-anchor-map
            normalized-match-penalty-map)
           (class-pair-procedure
            source-subpaths
            destination-subpaths
            source-indexes
            destination-indexes
            closed?
            allow-reverse?
            sample-count
            birth-anchor
            death-anchor
            normalized-birth-anchor-map
            normalized-death-anchor-map
            birth-penalty
            death-penalty
            normalized-birth-penalty-map
            normalized-death-penalty-map
            normalized-match-penalty-map)))
     (define class-pairs*
       (append
        (class-pairs
         source-open-indexes
         destination-open-indexes
         #f)
        (class-pairs
         source-closed-indexes
         destination-closed-indexes
         #t)))
     ;; Existing source slots retain source order. Birth-only slots are appended
     ;; in caller destination order so the result is deterministic across classes.
     (define source-slot-pairs
       (make-vector (length source-subpaths) #f))
     (define birth-slot-pairs
       (make-vector (length destination-subpaths) #f))
     (for ([pair (in-list class-pairs*)])
       (define source-index
         (topology-morph-pair-source-index pair))
       (define destination-index
         (topology-morph-pair-destination-index pair))
       (if source-index
           (vector-set! source-slot-pairs source-index pair)
           (vector-set! birth-slot-pairs destination-index pair)))
     (define ordered-pairs
       (append
        (vector->list source-slot-pairs)
        (for/list ([pair (in-vector birth-slot-pairs)]
                   #:when pair)
          pair)))
     (define prepared-source-subpaths
       (for/list ([pair (in-list ordered-pairs)])
         (topology-morph-pair-source pair)))
     (define prepared-destination-subpaths
       (for/list ([pair (in-list ordered-pairs)])
         (topology-morph-pair-destination pair)))
     (values
      (path-geometry-with-subpaths source prepared-source-subpaths)
      (path-geometry-with-subpaths destination prepared-destination-subpaths))]))

(struct topology-morph-pair
  (source destination source-index destination-index)
  #:transparent)

;; topology-morph-pair represents one interior morph slot. A missing source index
;; is a birth and a missing destination index is a death. The stored subpaths are
;; always concrete, because missing sides are replaced by degenerate seeds.

; topology-changing-class-pairs : (listof path-subpath?) (listof path-subpath?)
;                                 (listof exact-integer?)
;                                 (listof exact-integer?) boolean? boolean?
;                                 exact-integer? (or/c 'bounds-center vec2?)
;                                 (or/c 'bounds-center vec2?) hash? hash? hash?
;                                 -> (listof topology-morph-pair?)
;;   Solves one rectangular topology-class assignment by zero-cost dummy padding.
(define (topology-changing-class-pairs source-subpaths
                                       destination-subpaths
                                       source-indexes
                                       destination-indexes
                                       closed?
                                       allow-reverse?
                                       sample-count
                                       birth-anchor
                                       death-anchor
                                       birth-anchor-map
                                       death-anchor-map
                                       match-penalty-map)
  (define source-count (length source-indexes))
  (define destination-count (length destination-indexes))
  (define size (max source-count destination-count))
  (cond
    [(zero? size)
     '()]
    [else
     (define candidate-matrix
       (for/vector ([source-class-index (in-range size)])
         (define real-source?
           (< source-class-index source-count))
         (define source-subpath
           (and real-source?
                (list-ref source-subpaths
                          (list-ref source-indexes source-class-index))))
         (define source-samples
           (and real-source?
                (let ([source-path (path-geometry (list source-subpath))])
                  (if closed?
                      (closed-loop-alignment-samples source-path sample-count)
                      (open-path-alignment-samples source-path sample-count)))))
         (for/vector ([destination-class-index (in-range size)])
           (define real-destination?
             (< destination-class-index destination-count))
           (cond
             [(and real-source? real-destination?)
              (define destination-subpath
                (list-ref destination-subpaths
                          (list-ref destination-indexes
                                    destination-class-index)))
              (define destination-path
                (path-geometry (list destination-subpath)))
              (define-values (aligned-path score)
                (if closed?
                    (align-closed-loop-from-samples
                     source-samples
                     destination-path
                     allow-reverse?
                     sample-count)
                    (align-open-path-from-samples
                     source-samples
                     destination-path
                     allow-reverse?
                     sample-count)))
              (define source-index
                (list-ref source-indexes source-class-index))
              (define destination-index
                (list-ref destination-indexes destination-class-index))
              (compound-subpath-candidate
               (car (path-geometry-subpaths aligned-path))
               (+ score
                  (topology-morph-match-penalty-for-indexes
                   match-penalty-map
                   source-index
                   destination-index)))]
             [else
              ;; The class-count difference fixes exactly how many dummy slots
              ;; exist. Zero dummy cost therefore chooses the lowest-cost real
              ;; subset without inventing an arbitrary birth/death penalty.
              (compound-subpath-candidate #f 0)]))))
     (define assignment
       (minimum-cost-subpath-assignment candidate-matrix))
     (for/list ([source-class-index (in-range size)])
       (define destination-class-index
         (vector-ref assignment source-class-index))
       (define real-source?
         (< source-class-index source-count))
       (define real-destination?
         (< destination-class-index destination-count))
       (cond
         [(and real-source? real-destination?)
          (define source-index
            (list-ref source-indexes source-class-index))
          (define destination-index
            (list-ref destination-indexes destination-class-index))
          (define source-subpath
            (list-ref source-subpaths source-index))
          (define aligned-destination
            (compound-subpath-candidate-subpath
             (vector-ref
              (vector-ref candidate-matrix source-class-index)
              destination-class-index)))
          (topology-morph-pair
           source-subpath aligned-destination source-index destination-index)]
         [real-source?
          (define source-index
            (list-ref source-indexes source-class-index))
          (define source-subpath
            (list-ref source-subpaths source-index))
          (topology-morph-pair
           source-subpath
           (path-subpath-degenerate-seed
            source-subpath
            (topology-morph-anchor-position-for-index
             death-anchor
             death-anchor-map
             source-index
             source-subpath))
           source-index
           #f)]
         [real-destination?
          (define destination-index
            (list-ref destination-indexes destination-class-index))
          (define destination-subpath
            (list-ref destination-subpaths destination-index))
          (topology-morph-pair
           (path-subpath-degenerate-seed
            destination-subpath
            (topology-morph-anchor-position-for-index
             birth-anchor
             birth-anchor-map
             destination-index
             destination-subpath))
           destination-subpath
           #f
           destination-index)]
         [else
          (raise-arguments-error
           'path-geometry-prepare-topology-changing-morph
           "internal assignment paired two dummy subpaths"
           "source-class-index" source-class-index
           "destination-class-index" destination-class-index)]))]))


(struct penalized-topology-candidate (subpath score topology-changes)
  #:transparent)

;; penalized-topology-candidate stores one augmented-assignment edge. Real
;; source/destination matches have zero topology changes; a birth or death has
;; one. Exact primary-cost ties therefore prefer fewer synthetic slots.

; penalized-topology-changing-class-pairs : (listof path-subpath?)
;                                             (listof path-subpath?)
;                                             (listof exact-integer?)
;                                             (listof exact-integer?)
;                                             boolean? boolean? exact-integer?
;                                             (or/c 'bounds-center vec2?)
;                                             (or/c 'bounds-center vec2?)
;                                             hash? hash?
;                                             nonnegative-finite-real?
;                                             nonnegative-finite-real?
;                                             hash? hash? hash?
;                                             -> (listof topology-morph-pair?)
;;   Solves optional real-match rejection with explicit birth/death costs.
(define (penalized-topology-changing-class-pairs source-subpaths
                                                 destination-subpaths
                                                 source-indexes
                                                 destination-indexes
                                                 closed?
                                                 allow-reverse?
                                                 sample-count
                                                 birth-anchor
                                                 death-anchor
                                                 birth-anchor-map
                                                 death-anchor-map
                                                 birth-penalty
                                                 death-penalty
                                                 birth-penalty-map
                                                 death-penalty-map
                                                 match-penalty-map)
  (define source-count (length source-indexes))
  (define destination-count (length destination-indexes))
  ;; The augmented square matrix contains one real row for every source plus
  ;; one birth row for every destination, and one real destination column plus
  ;; one death column for every source. Dummy rows/columns are interchangeable;
  ;; caller-visible ordering is reconstructed from the real indexes below.
  (define size (+ source-count destination-count))
  (cond
    [(zero? size)
     '()]
    [else
     (define candidate-matrix
       (for/vector ([row-index (in-range size)])
         (define real-source?
           (< row-index source-count))
         (define source-subpath
           (and real-source?
                (list-ref source-subpaths
                          (list-ref source-indexes row-index))))
         (define source-samples
           (and real-source?
                (let ([source-path (path-geometry (list source-subpath))])
                  (if closed?
                      (closed-loop-alignment-samples source-path sample-count)
                      (open-path-alignment-samples source-path sample-count)))))
         (for/vector ([column-index (in-range size)])
           (define real-destination?
             (< column-index destination-count))
           (cond
             [(and real-source? real-destination?)
              (define destination-subpath
                (list-ref destination-subpaths
                          (list-ref destination-indexes column-index)))
              (define destination-path
                (path-geometry (list destination-subpath)))
              (define-values (aligned-path score)
                (if closed?
                    (align-closed-loop-from-samples
                     source-samples
                     destination-path
                     allow-reverse?
                     sample-count)
                    (align-open-path-from-samples
                     source-samples
                     destination-path
                     allow-reverse?
                     sample-count)))
              (define source-index
                (list-ref source-indexes row-index))
              (define destination-index
                (list-ref destination-indexes column-index))
              (penalized-topology-candidate
               (car (path-geometry-subpaths aligned-path))
               (+ score
                  (topology-morph-match-penalty-for-indexes
                   match-penalty-map
                   source-index
                   destination-index))
               0)]
             [real-source?
              ;; Death costs are keyed by the original source subpath index,
              ;; independent of class-local row order or assignment reordering.
              (define source-index
                (list-ref source-indexes row-index))
              (penalized-topology-candidate
               #f
               (topology-morph-penalty-for-index
                death-penalty
                death-penalty-map
                source-index)
               1)]
             [real-destination?
              ;; Birth costs are keyed by the original destination subpath index,
              ;; independent of class-local column order or assignment reordering.
              (define destination-index
                (list-ref destination-indexes column-index))
              (penalized-topology-candidate
               (list-ref destination-subpaths destination-index)
               (topology-morph-penalty-for-index
                birth-penalty
                birth-penalty-map
                destination-index)
               1)]
             [else
              ;; Unused birth rows pair with unused death columns at zero cost.
              (penalized-topology-candidate #f 0 0)]))))
     (define assignment
       (minimum-penalized-subpath-assignment candidate-matrix))
     (define source-pairs
       (for/list ([source-class-index (in-range source-count)])
         (define column-index
           (vector-ref assignment source-class-index))
         (define source-index
           (list-ref source-indexes source-class-index))
         (define source-subpath
           (list-ref source-subpaths source-index))
         (cond
           [(< column-index destination-count)
            (define destination-index
              (list-ref destination-indexes column-index))
            (define aligned-destination
              (penalized-topology-candidate-subpath
               (vector-ref
                (vector-ref candidate-matrix source-class-index)
                column-index)))
            (topology-morph-pair
             source-subpath aligned-destination source-index destination-index)]
           [else
            (topology-morph-pair
             source-subpath
             (path-subpath-degenerate-seed
              source-subpath
              (topology-morph-anchor-position-for-index
               death-anchor
               death-anchor-map
               source-index
               source-subpath))
             source-index
             #f)])))
     (define birth-pairs
       (for/list ([row-index (in-range source-count size)]
                  #:when (< (vector-ref assignment row-index)
                            destination-count))
         (define destination-class-index
           (vector-ref assignment row-index))
         (define destination-index
           (list-ref destination-indexes destination-class-index))
         (define destination-subpath
           (list-ref destination-subpaths destination-index))
         (topology-morph-pair
          (path-subpath-degenerate-seed
           destination-subpath
           (topology-morph-anchor-position-for-index
            birth-anchor
            birth-anchor-map
            destination-index
            destination-subpath))
          destination-subpath
          #f
          destination-index)))
     (append source-pairs birth-pairs)]))

(struct assignment-lex-cost (score topology-changes)
  #:transparent)

;; assignment-lex-cost is an internal ordered additive cost. Primary score is
;; the geometric/penalty objective. topology-changes is a secondary objective so
;; exact score ties prefer real correspondence over unnecessary death+birth.

(define assignment-lex-zero
  (assignment-lex-cost 0 0))

(define assignment-lex-infinity
  (assignment-lex-cost +inf.0 +inf.0))

; assignment-lex-finite? : assignment-lex-cost? -> boolean?
(define (assignment-lex-finite? cost)
  (finite-real? (assignment-lex-cost-score cost)))

; assignment-lex+ : assignment-lex-cost? assignment-lex-cost?
;                   -> assignment-lex-cost?
(define (assignment-lex+ left right)
  (if (and (assignment-lex-finite? left)
           (assignment-lex-finite? right))
      (assignment-lex-cost
       (+ (assignment-lex-cost-score left)
          (assignment-lex-cost-score right))
       (+ (assignment-lex-cost-topology-changes left)
          (assignment-lex-cost-topology-changes right)))
      assignment-lex-infinity))

; assignment-lex- : assignment-lex-cost? assignment-lex-cost?
;                   -> assignment-lex-cost?
(define (assignment-lex- left right)
  (cond
    [(not (assignment-lex-finite? left))
     assignment-lex-infinity]
    [(not (assignment-lex-finite? right))
     (error 'minimum-penalized-subpath-assignment
            "internal infinite assignment potential")]
    [else
     (assignment-lex-cost
      (- (assignment-lex-cost-score left)
         (assignment-lex-cost-score right))
      (- (assignment-lex-cost-topology-changes left)
         (assignment-lex-cost-topology-changes right)))]))

; assignment-lex<? : assignment-lex-cost? assignment-lex-cost? -> boolean?
(define (assignment-lex<? left right)
  (cond
    [(not (assignment-lex-finite? right))
     (assignment-lex-finite? left)]
    [(not (assignment-lex-finite? left))
     #f]
    [else
     (define left-score (assignment-lex-cost-score left))
     (define right-score (assignment-lex-cost-score right))
     (or (< left-score right-score)
         (and (= left-score right-score)
              (< (assignment-lex-cost-topology-changes left)
                 (assignment-lex-cost-topology-changes right))))]))

; assignment-lex=? : assignment-lex-cost? assignment-lex-cost? -> boolean?
(define (assignment-lex=? left right)
  (cond
    [(and (not (assignment-lex-finite? left))
          (not (assignment-lex-finite? right)))
     #t]
    [(or (not (assignment-lex-finite? left))
         (not (assignment-lex-finite? right)))
     #f]
    [else
     (and (= (assignment-lex-cost-score left)
             (assignment-lex-cost-score right))
          (= (assignment-lex-cost-topology-changes left)
             (assignment-lex-cost-topology-changes right)))]))

; penalized-candidate-cost : penalized-topology-candidate? -> assignment-lex-cost?
(define (penalized-candidate-cost candidate)
  (assignment-lex-cost
   (penalized-topology-candidate-score candidate)
   (penalized-topology-candidate-topology-changes candidate)))

; minimum-penalized-subpath-assignment :
;   (vectorof (vectorof penalized-topology-candidate?))
;   -> (vectorof exact-nonnegative-integer?)
;;   Hungarian assignment over lexicographic score/change costs.
(define (minimum-penalized-subpath-assignment candidate-matrix)
  (define size
    (vector-length candidate-matrix))
  (define row-potential
    (make-vector (add1 size) assignment-lex-zero))
  (define column-potential
    (make-vector (add1 size) assignment-lex-zero))
  (define column-row (make-vector (add1 size) 0))
  (define predecessor (make-vector (add1 size) 0))
  (define assignment (make-vector size 0))
  (for ([row (in-range 1 (add1 size))])
    (define minimum-reduced-cost
      (make-vector (add1 size) assignment-lex-infinity))
    (define used-column? (make-vector (add1 size) #f))
    (vector-set! column-row 0 row)
    (let search ([column 0])
      (define active-row
        (vector-ref column-row column))
      (define next-column 0)
      (define delta assignment-lex-infinity)
      (vector-set! used-column? column #t)
      (for ([candidate-column (in-range 1 (add1 size))]
            #:unless (vector-ref used-column? candidate-column))
        (define candidate
          (vector-ref
           (vector-ref candidate-matrix (sub1 active-row))
           (sub1 candidate-column)))
        (define reduced-cost
          (assignment-lex-
           (assignment-lex-
            (penalized-candidate-cost candidate)
            (vector-ref row-potential active-row))
           (vector-ref column-potential candidate-column)))
        (when (assignment-lex<?
               reduced-cost
               (vector-ref minimum-reduced-cost candidate-column))
          (vector-set! minimum-reduced-cost candidate-column reduced-cost)
          (vector-set! predecessor candidate-column column))
        (let* ([current-minimum
                (vector-ref minimum-reduced-cost candidate-column)]
               [candidate-free?
                (zero? (vector-ref column-row candidate-column))]
               [next-free?
                (and (positive? next-column)
                     (zero? (vector-ref column-row next-column)))])
          (when (or (assignment-lex<? current-minimum delta)
                    (and (assignment-lex=? current-minimum delta)
                         (or (zero? next-column)
                             (and candidate-free? (not next-free?))
                             (and (eq? candidate-free? next-free?)
                                  (< candidate-column next-column)))))
            (set! delta current-minimum)
            (set! next-column candidate-column))))
      (for ([candidate-column (in-range 0 (add1 size))])
        (cond
          [(vector-ref used-column? candidate-column)
           (define matched-row
             (vector-ref column-row candidate-column))
           (vector-set!
            row-potential
            matched-row
            (assignment-lex+
             (vector-ref row-potential matched-row)
             delta))
           (vector-set!
            column-potential
            candidate-column
            (assignment-lex-
             (vector-ref column-potential candidate-column)
             delta))]
          [(positive? candidate-column)
           (vector-set!
            minimum-reduced-cost
            candidate-column
            (assignment-lex-
             (vector-ref minimum-reduced-cost candidate-column)
             delta))]))
      (if (zero? (vector-ref column-row next-column))
          (let augment ([current-column next-column])
            (define previous-column
              (vector-ref predecessor current-column))
            (vector-set!
             column-row
             current-column
             (vector-ref column-row previous-column))
            (unless (zero? previous-column)
              (augment previous-column)))
          (search next-column))))
  (for ([column (in-range 1 (add1 size))])
    (define row
      (vector-ref column-row column))
    (vector-set! assignment (sub1 row) (sub1 column)))
  assignment)

; topology-morph-anchor-position : (or/c 'bounds-center vec2?) path-subpath?
;                                  -> vec2?
;;   Resolves a declarative local birth/death anchor for one real subpath.
(define (topology-morph-anchor-position anchor subpath)
  (if (vec2? anchor)
      anchor
      (path-geometry-center (path-geometry (list subpath)))))

; topology-morph-anchor-position-for-index :
;   (or/c 'bounds-center vec2?) hash? exact-nonnegative-integer? path-subpath?
;   -> vec2?
;;   Resolves a sparse per-subpath override, falling back to the shared anchor.
(define (topology-morph-anchor-position-for-index
         shared-anchor anchor-map subpath-index subpath)
  (topology-morph-anchor-position
   (hash-ref anchor-map subpath-index shared-anchor)
   subpath))

; path-subpath-degenerate-seed : path-subpath? vec2? -> path-subpath?
;;   Collapses one real subpath to a one-segment seed at an explicit local point.
(define (path-subpath-degenerate-seed subpath anchor)
  (path-subpath anchor
                (list (line-path-segment anchor))
                (path-subpath-closed? subpath)))

; check-topology-morph-anchor : symbol? string? any/c -> void?
;;   Raises unless value is the default bounds-center marker or a finite vec2.
(define (check-topology-morph-anchor who field value)
  (unless (or (eq? value 'bounds-center)
              (vec2? value))
    (raise-arguments-error
     who
     "expected a topology morph anchor"
     field value
     "expected" "'bounds-center or vec2?")))

; normalize-topology-morph-anchor-map : symbol? string? any/c
;                                      exact-nonnegative-integer? -> hash?
;;   Validates and snapshots sparse endpoint-index overrides with equal? keys.
(define (normalize-topology-morph-anchor-map who field value subpath-count)
  (unless (hash? value)
    (raise-arguments-error
     who
     "expected a topology morph anchor map"
     field value
     "expected" "hash?"))
  (for/fold ([result #hash()])
            ([(subpath-index anchor) (in-hash value)])
    (unless (exact-nonnegative-integer? subpath-index)
      (raise-arguments-error
       who
       "expected nonnegative exact-integer anchor-map keys"
       field value
       "key" subpath-index))
    (unless (< subpath-index subpath-count)
      (raise-arguments-error
       who
       "anchor-map key is outside the corresponding path's subpath range"
       field value
       "key" subpath-index
       "subpath-count" subpath-count))
    (check-topology-morph-anchor who field anchor)
    (when (hash-has-key? result subpath-index)
      (raise-arguments-error
       who
       "anchor-map contains duplicate numeric keys under equal? lookup"
       field value
       "key" subpath-index))
    (hash-set result subpath-index anchor)))


; topology-morph-penalty-for-index :
;   nonnegative-finite-real? hash? exact-nonnegative-integer?
;   -> nonnegative-finite-real?
;;   Resolves a sparse per-subpath cost override, falling back to the shared cost.
(define (topology-morph-penalty-for-index shared-penalty penalty-map subpath-index)
  (hash-ref penalty-map subpath-index shared-penalty))

; topology-morph-match-penalty-for-indexes :
;   hash? exact-nonnegative-integer? exact-nonnegative-integer?
;   -> nonnegative-finite-real?
;;   Resolves a sparse additive penalty for one real source/destination edge.
(define (topology-morph-match-penalty-for-indexes
         match-penalty-map source-index destination-index)
  (hash-ref match-penalty-map (cons source-index destination-index) 0))

; normalize-topology-morph-match-penalty-map : symbol? string? any/c
;                                             (listof path-subpath?)
;                                             (listof path-subpath?) -> hash?
;;   Validates/snapshots original-index pair penalties for real same-topology edges.
(define (normalize-topology-morph-match-penalty-map
         who field value source-subpaths destination-subpaths)
  (unless (hash? value)
    (raise-arguments-error
     who
     "expected a topology morph match-penalty map"
     field value
     "expected" "hash?"))
  (for/fold ([result #hash()])
            ([(pair-key penalty) (in-hash value)])
    (unless (and (pair? pair-key)
                 (exact-nonnegative-integer? (car pair-key))
                 (exact-nonnegative-integer? (cdr pair-key)))
      (raise-arguments-error
       who
       "expected match-penalty-map keys of the form (cons source-index destination-index)"
       field value
       "key" pair-key))
    (define source-index (car pair-key))
    (define destination-index (cdr pair-key))
    (unless (< source-index (length source-subpaths))
      (raise-arguments-error
       who
       "match-penalty-map source index is outside the source subpath range"
       field value
       "key" pair-key
       "source-subpath-count" (length source-subpaths)))
    (unless (< destination-index (length destination-subpaths))
      (raise-arguments-error
       who
       "match-penalty-map destination index is outside the destination subpath range"
       field value
       "key" pair-key
       "destination-subpath-count" (length destination-subpaths)))
    (unless (eq? (path-subpath-closed? (list-ref source-subpaths source-index))
                 (path-subpath-closed? (list-ref destination-subpaths destination-index)))
      (raise-arguments-error
       who
       "match-penalty-map key names an impossible open/closed correspondence"
       field value
       "key" pair-key))
    (unless (and (finite-real? penalty)
                 (>= penalty 0))
      (raise-arguments-error
       who
       "expected finite nonnegative match-penalty-map values"
       field value
       "key" pair-key
       "value" penalty))
    (define normalized-key (cons source-index destination-index))
    (when (hash-has-key? result normalized-key)
      (raise-arguments-error
       who
       "match-penalty-map contains duplicate pair keys under equal? lookup"
       field value
       "key" pair-key))
    (hash-set result normalized-key penalty)))

; normalize-topology-morph-penalty-map : symbol? string? any/c
;                                       exact-nonnegative-integer? -> hash?
;;   Validates and snapshots sparse endpoint-index numeric penalty overrides.
(define (normalize-topology-morph-penalty-map who field value subpath-count)
  (unless (hash? value)
    (raise-arguments-error
     who
     "expected a topology morph penalty map"
     field value
     "expected" "hash?"))
  (for/fold ([result #hash()])
            ([(subpath-index penalty) (in-hash value)])
    (unless (exact-nonnegative-integer? subpath-index)
      (raise-arguments-error
       who
       "expected nonnegative exact-integer penalty-map keys"
       field value
       "key" subpath-index))
    (unless (< subpath-index subpath-count)
      (raise-arguments-error
       who
       "penalty-map key is outside the corresponding path's subpath range"
       field value
       "key" subpath-index
       "subpath-count" subpath-count))
    (unless (and (finite-real? penalty)
                 (>= penalty 0))
      (raise-arguments-error
       who
       "expected finite nonnegative penalty-map values"
       field value
       "key" subpath-index
       "value" penalty))
    (when (hash-has-key? result subpath-index)
      (raise-arguments-error
       who
       "penalty-map contains duplicate numeric keys under equal? lookup"
       field value
       "key" subpath-index))
    (hash-set result subpath-index penalty)))

; check-topology-morph-penalty-map-mode :
;   symbol? any/c any/c hash? hash? -> void?
;;   Per-subpath cost overrides are meaningful only in numeric penalty mode.
(define (check-topology-morph-penalty-map-mode
         who birth-penalty death-penalty birth-penalty-map death-penalty-map)
  (when (and (eq? birth-penalty 'forced)
             (or (positive? (hash-count birth-penalty-map))
                 (positive? (hash-count death-penalty-map))))
    (raise-arguments-error
     who
     "per-subpath penalty maps require numeric birth/death penalty mode"
     "#:birth-penalty" birth-penalty
     "#:death-penalty" death-penalty
     "#:birth-penalty-map" birth-penalty-map
     "#:death-penalty-map" death-penalty-map)))

; check-topology-morph-penalties : symbol? any/c any/c -> void?
;;   Accepts the default forced-only policy or two finite nonnegative costs.
(define (check-topology-morph-penalties who birth-penalty death-penalty)
  (define (numeric-penalty? value)
    (and (finite-real? value)
         (>= value 0)))
  (unless (or (and (eq? birth-penalty 'forced)
                   (eq? death-penalty 'forced))
              (and (numeric-penalty? birth-penalty)
                   (numeric-penalty? death-penalty)))
    (raise-arguments-error
     who
     "expected both birth/death penalties to use the same policy mode"
     "#:birth-penalty" birth-penalty
     "#:death-penalty" death-penalty
     "expected" "both 'forced, or both nonnegative finite real numbers")))

; subpath-indexes-with-closure : (listof path-subpath?) boolean?
;                                -> (listof exact-nonnegative-integer?)
;;   Returns indexes whose subpaths have the requested closure class.
(define (subpath-indexes-with-closure subpaths closed?)
  (for/list ([subpath (in-list subpaths)]
             [index (in-naturals)]
             #:when (eq? (path-subpath-closed? subpath) closed?))
    index))

; align-mixed-subpath-class! : vector? (listof path-subpath?)
;                              (listof path-subpath?) (listof exact-integer?)
;                              (listof exact-integer?) boolean? boolean?
;                              exact-integer? -> void?
;;   Globally assigns one topology class and writes results in source order.
(define (align-mixed-subpath-class! aligned-by-source
                                    source-subpaths
                                    destination-subpaths
                                    source-indexes
                                    destination-indexes
                                    closed?
                                    allow-reverse?
                                    sample-count)
  (unless (null? source-indexes)
    (define candidate-matrix
      (for/vector ([source-index (in-list source-indexes)])
        (define source-subpath
          (list-ref source-subpaths source-index))
        (define source-path
          (path-geometry (list source-subpath)))
        (define source-samples
          (if closed?
              (closed-loop-alignment-samples source-path sample-count)
              (open-path-alignment-samples source-path sample-count)))
        (for/vector ([destination-index (in-list destination-indexes)])
          (define destination-subpath
            (list-ref destination-subpaths destination-index))
          (define destination-path
            (path-geometry (list destination-subpath)))
          (define-values (aligned-path score)
            (if closed?
                (align-closed-loop-from-samples
                 source-samples
                 destination-path
                 allow-reverse?
                 sample-count)
                (align-open-path-from-samples
                 source-samples
                 destination-path
                 allow-reverse?
                 sample-count)))
          (compound-subpath-candidate
           (car (path-geometry-subpaths aligned-path))
           score))))
    (define assignment
      (minimum-cost-subpath-assignment candidate-matrix))
    (for ([source-class-index (in-range (vector-length assignment))])
      (define source-index
        (list-ref source-indexes source-class-index))
      (define destination-class-index
        (vector-ref assignment source-class-index))
      (vector-set!
       aligned-by-source
       source-index
       (compound-subpath-candidate-subpath
        (vector-ref
         (vector-ref candidate-matrix source-class-index)
         destination-class-index)))))
  (void))

; path-geometry-align-compound-for-morph : path-geometry? path-geometry?
;                                           [#:allow-reverse? boolean?]
;                                           [#:sample-count exact-integer?]
;                                           -> path-geometry?
;;   Globally pairs equal-count closed subpaths, then aligns each loop.
(define (path-geometry-align-compound-for-morph
         source
         destination
         #:allow-reverse? [allow-reverse? #t]
         #:sample-count [sample-count 64])
  (check-path-geometry 'path-geometry-align-compound-for-morph source)
  (check-path-geometry 'path-geometry-align-compound-for-morph destination)
  (check-morph-alignment-options
   'path-geometry-align-compound-for-morph
   allow-reverse?
   sample-count)
  (define source-subpaths
    (path-geometry-subpaths source))
  (define destination-subpaths
    (path-geometry-subpaths destination))
  (unless (= (length source-subpaths)
             (length destination-subpaths))
    (raise-arguments-error
     'path-geometry-align-compound-for-morph
     "automatic compound morph alignment requires equal subpath counts"
     "source-subpath-count" (length source-subpaths)
     "destination-subpath-count" (length destination-subpaths)))
  (when (null? source-subpaths)
    (raise-arguments-error
     'path-geometry-align-compound-for-morph
     "automatic compound morph alignment requires at least one closed subpath"
     "source" source
     "destination" destination))
  (for ([subpath (in-list source-subpaths)]
        [index (in-naturals)])
    (check-morph-alignment-subpath
     'path-geometry-align-compound-for-morph
     "source"
     index
     subpath))
  (for ([subpath (in-list destination-subpaths)]
        [index (in-naturals)])
    (check-morph-alignment-subpath
     'path-geometry-align-compound-for-morph
     "destination"
     index
     subpath))
  (define candidate-matrix
    (for/vector ([source-subpath (in-list source-subpaths)])
      (define source-loop
        (path-geometry (list source-subpath)))
      (define source-samples
        (closed-loop-alignment-samples source-loop sample-count))
      (for/vector ([destination-subpath (in-list destination-subpaths)])
        (define destination-loop
          (path-geometry (list destination-subpath)))
        (define-values (aligned-loop score)
          (align-closed-loop-from-samples
           source-samples
           destination-loop
           allow-reverse?
           sample-count))
        (compound-subpath-candidate
         (car (path-geometry-subpaths aligned-loop))
         score))))
  (define assignment
    (minimum-cost-subpath-assignment candidate-matrix))
  (define aligned-subpaths
    (for/list ([source-index (in-range (vector-length assignment))])
      (define destination-index
        (vector-ref assignment source-index))
      (compound-subpath-candidate-subpath
       (vector-ref
        (vector-ref candidate-matrix source-index)
        destination-index))))
  (if (same-objects-in-order? destination-subpaths aligned-subpaths)
      destination
      (path-geometry aligned-subpaths)))

(struct compound-subpath-candidate (subpath score)
  #:transparent)

;; compound-subpath-candidate caches one aligned destination subpath plus
;; the mean point-distance score used by deterministic global pairing.

; check-morph-alignment-options : symbol? any/c any/c -> void?
;;   Validates the common deterministic alignment options.
(define (check-morph-alignment-options who allow-reverse? sample-count)
  (unless (boolean? allow-reverse?)
    (raise-argument-error who "boolean?" allow-reverse?))
  (unless (and (exact-integer? sample-count)
               (>= sample-count 8))
    (raise-argument-error
     who
     "exact integer greater than or equal to 8"
     sample-count)))

; align-open-path-from-samples : (listof pair?) path-geometry? boolean?
;                                exact-integer?
;                                -> (values path-geometry? nonnegative-real?)
;;   Applies SCENE-AE's endpoint-direction rule against cached source samples.
(define (align-open-path-from-samples source-samples
                                      destination
                                      allow-reverse?
                                      sample-count)
  (define forward-score
    (open-path-alignment-score
     source-samples destination sample-count))
  (cond
    [allow-reverse?
     (define reversed-destination
       (path-geometry-reverse destination))
     (define reverse-score
       (open-path-alignment-score
        source-samples reversed-destination sample-count))
     ;; Equal scores deliberately prefer the caller's stored forward traversal.
     (if (< reverse-score forward-score)
         (values reversed-destination reverse-score)
         (values destination forward-score))]
    [else
     (values destination forward-score)]))

; align-validated-closed-loop-for-morph : path-geometry? path-geometry?
;                                         boolean? exact-integer?
;                                         -> (values path-geometry?
;                                                    nonnegative-real?)
;;   Aligns two already-validated one-loop paths and returns its score.
(define (align-validated-closed-loop-for-morph source
                                               destination
                                               allow-reverse?
                                               sample-count)
  (align-closed-loop-from-samples
   (closed-loop-alignment-samples source sample-count)
   destination
   allow-reverse?
   sample-count))

; closed-loop-alignment-samples : path-geometry? exact-integer? -> (listof pair?)
;;   Measures one validated source loop once at deterministic score fractions.
(define (closed-loop-alignment-samples source sample-count)
  (define measured-source
    (make-measured-closed-loop source))
  (for/list ([index (in-range sample-count)])
    (define fraction
      (/ index sample-count))
    (cons fraction
          (measured-closed-loop-point-at measured-source fraction))))

; align-closed-loop-from-samples : (listof pair?) path-geometry? boolean?
;                                  exact-integer?
;                                  -> (values path-geometry? nonnegative-real?)
;;   Aligns one destination loop against cached source samples.
(define (align-closed-loop-from-samples source-samples
                                        destination
                                        allow-reverse?
                                        sample-count)
  (define-values (forward-phase forward-score)
    (closed-loop-best-alignment-phase
     source-samples
     destination
     sample-count))
  (define-values (selected-destination selected-phase selected-score)
    (cond
      [allow-reverse?
       (define reversed-destination
         (path-geometry-reverse destination))
       (define-values (reverse-phase reverse-score)
         (closed-loop-best-alignment-phase
          source-samples
          reversed-destination
          sample-count))
       ;; Equal scores deliberately prefer forward traversal so symmetric loops
       ;; do not reverse merely because both correspondences are equivalent.
       (if (< reverse-score forward-score)
           (values reversed-destination reverse-phase reverse-score)
           (values destination forward-phase forward-score))]
      [else
       (values destination forward-phase forward-score)]))
  (values
   (if (zero? selected-phase)
       selected-destination
       (path-geometry-cycle-start selected-destination selected-phase))
   selected-score))

; minimum-cost-subpath-assignment : (vectorof (vectorof compound-subpath-candidate?))
;                                   -> (vectorof exact-nonnegative-integer?)
;;   Solves the square minimum-cost assignment with deterministic index ties.
(define (minimum-cost-subpath-assignment candidate-matrix)
  (define size
    (vector-length candidate-matrix))
  ;; Hungarian potentials use one-based row/column indexes and column zero as
  ;; the augmenting-path sentinel. Ascending scans make exact ties repeatable.
  (define row-potential (make-vector (add1 size) 0))
  (define column-potential (make-vector (add1 size) 0))
  (define column-row (make-vector (add1 size) 0))
  (define predecessor (make-vector (add1 size) 0))
  (define assignment (make-vector size 0))
  (for ([row (in-range 1 (add1 size))])
    (define minimum-reduced-cost (make-vector (add1 size) +inf.0))
    (define used-column? (make-vector (add1 size) #f))
    (vector-set! column-row 0 row)
    (let search ([column 0])
      (define active-row
        (vector-ref column-row column))
      (define next-column 0)
      (define delta +inf.0)
      (vector-set! used-column? column #t)
      (for ([candidate-column (in-range 1 (add1 size))]
            #:unless (vector-ref used-column? candidate-column))
        (define candidate
          (vector-ref
           (vector-ref candidate-matrix (sub1 active-row))
           (sub1 candidate-column)))
        (define reduced-cost
          (- (compound-subpath-candidate-score candidate)
             (vector-ref row-potential active-row)
             (vector-ref column-potential candidate-column)))
        (when (< reduced-cost
                 (vector-ref minimum-reduced-cost candidate-column))
          (vector-set! minimum-reduced-cost candidate-column reduced-cost)
          (vector-set! predecessor candidate-column column))
        (let* ([current-minimum
                (vector-ref minimum-reduced-cost candidate-column)]
               [candidate-free?
                (zero? (vector-ref column-row candidate-column))]
               [next-free?
                (and (positive? next-column)
                     (zero? (vector-ref column-row next-column)))])
          (when (or (< current-minimum delta)
                    (and (= current-minimum delta)
                         (or (zero? next-column)
                             (and candidate-free? (not next-free?))
                             (and (eq? candidate-free? next-free?)
                                  (< candidate-column next-column)))))
            (set! delta current-minimum)
            (set! next-column candidate-column))))
      (for ([candidate-column (in-range 0 (add1 size))])
        (cond
          [(vector-ref used-column? candidate-column)
           (define matched-row
             (vector-ref column-row candidate-column))
           (vector-set! row-potential
                        matched-row
                        (+ (vector-ref row-potential matched-row) delta))
           (vector-set! column-potential
                        candidate-column
                        (- (vector-ref column-potential candidate-column) delta))]
          [(positive? candidate-column)
           (vector-set! minimum-reduced-cost
                        candidate-column
                        (- (vector-ref minimum-reduced-cost candidate-column)
                           delta))]))
      (if (zero? (vector-ref column-row next-column))
          (let augment ([current-column next-column])
            (define previous-column
              (vector-ref predecessor current-column))
            (vector-set! column-row
                         current-column
                         (vector-ref column-row previous-column))
            (unless (zero? previous-column)
              (augment previous-column)))
          (search next-column))))
  (for ([column (in-range 1 (add1 size))])
    (define row
      (vector-ref column-row column))
    (vector-set! assignment (sub1 row) (sub1 column)))
  assignment)

; check-morph-alignment-open-path : symbol? string? path-geometry? -> void?
;;   Requires one finite positive open path for endpoint correspondence.
(define (check-morph-alignment-open-path who field-name geometry)
  (define subpaths
    (path-geometry-subpaths geometry))
  (unless (= (length subpaths) 1)
    (raise-arguments-error
     who
     "automatic open-path morph alignment requires exactly one subpath in each path"
     field-name geometry
     "subpath-count" (length subpaths)))
  (define subpath
    (car subpaths))
  (when (path-subpath-closed? subpath)
    (raise-arguments-error
     who
     "automatic open-path morph alignment requires open source and destination paths"
     field-name geometry
     "subpath" subpath))
  (define total-length
    (path-subpath-length subpath))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     who
     "automatic open-path morph alignment requires positive finite path lengths"
     field-name geometry
     "path-length" total-length))
  (void))

; check-morph-alignment-loop : symbol? string? path-geometry? -> void?
;;   Requires one finite positive closed loop for automatic correspondence.
(define (check-morph-alignment-loop who field-name geometry)
  (define subpaths
    (path-geometry-subpaths geometry))
  (unless (= (length subpaths) 1)
    (raise-arguments-error
     who
     "automatic morph alignment requires exactly one subpath in each path"
     field-name geometry
     "subpath-count" (length subpaths)))
  (define subpath
    (car subpaths))
  (unless (path-subpath-closed? subpath)
    (raise-arguments-error
     who
     "automatic morph alignment requires closed source and destination loops"
     field-name geometry
     "subpath" subpath))
  (define total-length
    (path-subpath-length subpath))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     who
     "automatic morph alignment requires positive finite loop lengths"
     field-name geometry
     "path-length" total-length))
  (void))

; check-morph-alignment-mixed-subpath : symbol? string?
;                                       exact-nonnegative-integer?
;                                       path-subpath? -> void?
;;   Requires one positive finite subpath while preserving its closure class.
(define (check-morph-alignment-mixed-subpath who field-name index subpath)
  (define total-length
    (path-subpath-length subpath))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     who
     "automatic mixed-compound morph alignment requires positive finite subpath lengths"
     field-name subpath
     "subpath-index" index
     "path-length" total-length))
  (void))

; check-morph-alignment-open-subpath : symbol? string? exact-nonnegative-integer?
;                                      path-subpath? -> void?
;;   Requires one positive finite open subpath for compound correspondence.
(define (check-morph-alignment-open-subpath who field-name index subpath)
  (when (path-subpath-closed? subpath)
    (raise-arguments-error
     who
     "automatic open-compound morph alignment requires open subpaths"
     field-name subpath
     "subpath-index" index))
  (define total-length
    (path-subpath-length subpath))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     who
     "automatic open-compound morph alignment requires positive finite subpath lengths"
     field-name subpath
     "subpath-index" index
     "path-length" total-length))
  (void))

; check-morph-alignment-subpath : symbol? string? exact-nonnegative-integer?
;                                 path-subpath? -> void?
;;   Requires one positive finite closed subpath for compound correspondence.
(define (check-morph-alignment-subpath who field-name index subpath)
  (unless (path-subpath-closed? subpath)
    (raise-arguments-error
     who
     "automatic compound morph alignment requires closed subpaths"
     field-name subpath
     "subpath-index" index))
  (define total-length
    (path-subpath-length subpath))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     who
     "automatic compound morph alignment requires positive finite subpath lengths"
     field-name subpath
     "subpath-index" index
     "path-length" total-length))
  (void))

(struct measured-open-path (edges total-length)
  #:transparent)

;; measured-open-path caches the positive traversal edges of one open path.

; make-measured-open-path : path-geometry? -> measured-open-path?
;;   Measures one already-validated positive open path exactly once.
(define (make-measured-open-path geometry)
  (define subpath
    (car (path-geometry-subpaths geometry)))
  (define edges
    (for/list ([edge (in-list (path-subpath-edges subpath))]
               #:when (positive? (path-edge-length edge)))
      edge))
  (measured-open-path
   edges
   (for/sum ([edge (in-list edges)])
     (path-edge-length edge))))

; measured-open-path-point-at : measured-open-path? finite-real? -> vec2?
;;   Samples one total-arc-length fraction using cached edge data.
(define (measured-open-path-point-at measured fraction)
  (define edges
    (measured-open-path-edges measured))
  (define total-length
    (measured-open-path-total-length measured))
  (define first-edge (car edges))
  (define last-edge (car (reverse edges)))
  (cond
    [(zero? fraction)
     (path-edge-start first-edge)]
    [(= fraction 1)
     (path-segment-end (path-edge-segment last-edge))]
    [else
     (define target-distance
       (* fraction total-length))
     (let loop ([remaining edges]
                [offset 0])
       (cond
         [(null? remaining)
          (path-segment-end (path-edge-segment last-edge))]
         [else
          (define edge (car remaining))
          (define next-offset
            (+ offset (path-edge-length edge)))
          (if (<= target-distance next-offset)
              (path-edge-point-at-distance
               edge
               (- target-distance offset))
              (loop (cdr remaining) next-offset))]))]))

; open-path-alignment-samples : path-geometry? exact-integer? -> (listof pair?)
;;   Measures one validated source path at deterministic inclusive fractions.
(define (open-path-alignment-samples source sample-count)
  (define measured-source
    (make-measured-open-path source))
  (for/list ([index (in-range sample-count)])
    (define fraction
      (/ index (sub1 sample-count)))
    (cons fraction
          (measured-open-path-point-at measured-source fraction))))

; open-path-alignment-score : (listof pair?) path-geometry? exact-integer?
;                             -> nonnegative-real?
;;   Measures mean point distance for one stored open-path traversal direction.
(define (open-path-alignment-score source-samples destination sample-count)
  (define measured-destination
    (make-measured-open-path destination))
  (for/sum ([sample (in-list source-samples)])
    (/ (vec2-distance
        (cdr sample)
        (measured-open-path-point-at
         measured-destination
         (car sample)))
       sample-count)))

(struct measured-closed-loop (edges total-length)
  #:transparent)

;; measured-closed-loop caches the positive edges and total length of one loop.
;; Keeping path-edge arc samples here avoids rebuilding adaptive cubic tables
;; for every candidate phase and every correspondence sample.

; make-measured-closed-loop : path-geometry? -> measured-closed-loop?
;;   Measures one already-validated positive closed loop exactly once.
(define (make-measured-closed-loop geometry)
  (define subpath
    (car (path-geometry-subpaths geometry)))
  (define edges
    (for/list ([edge (in-list (path-subpath-edges subpath))]
               #:when (positive? (path-edge-length edge)))
      edge))
  (measured-closed-loop
   edges
   (for/sum ([edge (in-list edges)])
     (path-edge-length edge))))

; measured-closed-loop-point-at : measured-closed-loop? finite-real? -> vec2?
;;   Samples one half-open cyclic arc-length fraction using cached edge data.
(define (measured-closed-loop-point-at measured fraction)
  (define edges
    (measured-closed-loop-edges measured))
  (define total-length
    (measured-closed-loop-total-length measured))
  (cond
    [(zero? fraction)
     (path-edge-start (car edges))]
    [else
     (define target-distance
       (* fraction total-length))
     (let loop ([remaining edges]
                [offset 0])
       (cond
         [(null? remaining)
          ;; Rounding at the end of the half-open interval may leave a target
          ;; infinitesimally beyond the accumulated total. A closed loop ends
          ;; at the same geometric point at which it begins.
          (path-segment-end
           (path-edge-segment (car (reverse edges))))]
         [else
          (define edge
            (car remaining))
          (define next-offset
            (+ offset (path-edge-length edge)))
          (if (<= target-distance next-offset)
              (path-edge-point-at-distance
               edge
               (- target-distance offset))
              (loop (cdr remaining) next-offset))]))]))

; closed-loop-best-alignment-phase : (listof (cons/c finite-real? vec2?))
;                                    path-geometry? exact-integer?
;                                    -> (values finite-real?
;                                               nonnegative-real?)
;;   Finds a deterministic low-distance cyclic phase for one traversal order.
(define (closed-loop-best-alignment-phase source-samples
                                          destination
                                          sample-count)
  (define measured-destination
    (make-measured-closed-loop destination))
  (define coarse-phases
    (remove-duplicate-real-values
     (append
      (for/list ([index (in-range sample-count)])
        (/ index sample-count))
      (closed-loop-edge-boundary-fractions measured-destination))))
  (define-values (coarse-phase coarse-score)
    (best-alignment-phase-from-candidates
     source-samples
     measured-destination
     sample-count
     coarse-phases
     0
     +inf.0))
  ;; Refine locally around the best global coarse candidate. The fixed number
  ;; of rounds is deterministic and independent of rendering or machine time.
  (let loop ([best-phase coarse-phase]
             [best-score coarse-score]
             [radius (/ 1 sample-count)]
             [round 0])
    (cond
      [(= round 8)
       (values best-phase best-score)]
      [else
       (define step
         (/ radius 4))
       (define candidates
         (for/list ([offset (in-range -4 5)])
           (cyclic-unit-fraction
            (+ best-phase (* offset step)))))
       (define-values (next-phase next-score)
         (best-alignment-phase-from-candidates
          source-samples
          measured-destination
          sample-count
          candidates
          best-phase
          best-score))
       (loop next-phase next-score step (add1 round))])))

; best-alignment-phase-from-candidates : (listof pair?) measured-closed-loop?
;                                        exact-integer? (listof finite-real?)
;                                        finite-real? nonnegative-real?
;                                        -> (values finite-real?
;                                                   nonnegative-real?)
;;   Selects the lowest-score phase, breaking exact ties toward smaller phase.
(define (best-alignment-phase-from-candidates source-samples
                                              measured-destination
                                              sample-count
                                              candidates
                                              initial-phase
                                              initial-score)
  (for/fold ([best-phase initial-phase]
             [best-score initial-score])
            ([phase (in-list candidates)])
    (define score
      (closed-loop-alignment-score
       source-samples
       measured-destination
       sample-count
       phase))
    (if (or (< score best-score)
            (and (= score best-score)
                 (< phase best-phase)))
        (values phase score)
        (values best-phase best-score))))

; closed-loop-alignment-score : (listof pair?) measured-closed-loop?
;                               exact-integer? finite-real?
;                               -> nonnegative-real?
;;   Measures mean point distance at corresponding total-arc-length samples.
(define (closed-loop-alignment-score source-samples
                                     measured-destination
                                     sample-count
                                     phase)
  (for/sum ([sample (in-list source-samples)])
    (define source-fraction
      (car sample))
    (define destination-fraction
      (cyclic-unit-fraction (+ source-fraction phase)))
    (/ (vec2-distance
        (cdr sample)
        (measured-closed-loop-point-at
         measured-destination
         destination-fraction))
       sample-count)))

; closed-loop-edge-boundary-fractions : measured-closed-loop?
;                                       -> (listof finite-real?)
;;   Returns every positive-edge start phase for one measured closed loop.
(define (closed-loop-edge-boundary-fractions measured)
  (define edges
    (measured-closed-loop-edges measured))
  (define total-length
    (measured-closed-loop-total-length measured))
  (define-values (reversed-fractions _distance)
    (for/fold ([reversed-fractions '()]
               [distance 0])
              ([edge (in-list edges)])
      (values (cons (/ distance total-length) reversed-fractions)
              (+ distance (path-edge-length edge)))))
  (reverse reversed-fractions))

; cyclic-unit-fraction : finite-real? -> finite-real?
;;   Wraps a finite real onto the half-open unit interval [0,1).
(define (cyclic-unit-fraction value)
  (define wrapped
    (- value (floor value)))
  (if (= wrapped 1) 0 wrapped))

; remove-duplicate-real-values : (listof finite-real?) -> (listof finite-real?)
;;   Preserves first occurrence order while removing exact duplicate phases.
(define (remove-duplicate-real-values values)
  (let loop ([remaining values]
             [seen '()]
             [reversed-result '()])
    (cond
      [(null? remaining)
       (reverse reversed-result)]
      [(for/or ([seen-value (in-list seen)])
         (= (car remaining) seen-value))
       (loop (cdr remaining) seen reversed-result)]
      [else
       (loop (cdr remaining)
             (cons (car remaining) seen)
             (cons (car remaining) reversed-result))])))

; path-geometry-normalize-for-morph : path-geometry? path-geometry?
;                                      -> (values path-geometry?
;                                                 path-geometry?)
;;   Converts and refines two paths to corresponding cubic morph structure.
(define (path-geometry-normalize-for-morph from to)
  (check-path-geometry 'path-geometry-normalize-for-morph from)
  (check-path-geometry 'path-geometry-normalize-for-morph to)
  (define problem
    (path-geometry-normalization-problem from to))
  (when problem
    (raise-arguments-error
     'path-geometry-normalize-for-morph
     "path geometries cannot be normalized by cubic conversion and splitting"
     "problem" (path-normalization-problem->string problem)
     "from" from
     "to" to))
  (define cubic-from
    (path-geometry->cubic from))
  (define cubic-to
    (path-geometry->cubic to))
  (define-values (from-subpaths to-subpaths)
    (normalize-corresponding-subpaths
     (path-geometry-subpaths cubic-from)
     (path-geometry-subpaths cubic-to)))
  (values (path-geometry-with-subpaths cubic-from from-subpaths)
          (path-geometry-with-subpaths cubic-to to-subpaths)))

(struct path-normalization-problem
  (kind subpath-index from-value to-value)
  #:transparent)

;; path-normalization-problem describes the first unsupported path difference.
;;  - kind           symbol?                         mismatch category.
;;  - subpath-index  (or/c exact-nonnegative-integer? #f)
;;                                                   affected subpath index.
;;  - from-value     any/c                           source structural value.
;;  - to-value       any/c                           destination structural value.

; path-geometry-normalization-problem : path-geometry? path-geometry?
;                                       -> (or/c path-normalization-problem?
;                                                false/c)
;;   Returns the first difference unsupported by limited path normalization.
(define (path-geometry-normalization-problem from to)
  (define from-subpaths
    (path-geometry-subpaths from))
  (define to-subpaths
    (path-geometry-subpaths to))
  (cond
    [(not (= (length from-subpaths)
             (length to-subpaths)))
     (path-normalization-problem 'subpath-count
                                 #f
                                 (length from-subpaths)
                                 (length to-subpaths))]
    [else
     (for/or ([from-subpath (in-list from-subpaths)]
              [to-subpath (in-list to-subpaths)]
              [subpath-index (in-naturals)])
       (path-subpath-normalization-problem from-subpath
                                           to-subpath
                                           subpath-index))]))

; path-subpath-normalization-problem : path-subpath? path-subpath?
;                                      exact-nonnegative-integer?
;                                      -> (or/c path-normalization-problem?
;                                               false/c)
;;   Returns the first unsupported difference between corresponding subpaths.
(define (path-subpath-normalization-problem from to subpath-index)
  (define from-segment-count
    (length (path-subpath-segments from)))
  (define to-segment-count
    (length (path-subpath-segments to)))
  (cond
    [(not (eq? (path-subpath-closed? from)
               (path-subpath-closed? to)))
     (path-normalization-problem 'closure
                                 subpath-index
                                 (path-subpath-closed? from)
                                 (path-subpath-closed? to))]
    [(not (eq? (zero? from-segment-count)
               (zero? to-segment-count)))
     (path-normalization-problem 'segment-presence
                                 subpath-index
                                 from-segment-count
                                 to-segment-count)]
    [else
     #f]))

; path-normalization-problem->string : path-normalization-problem? -> string?
;;   Converts one normalization problem to a concise diagnostic sentence.
(define (path-normalization-problem->string problem)
  (case (path-normalization-problem-kind problem)
    [(subpath-count)
     (format "different subpath counts: ~a and ~a"
             (path-normalization-problem-from-value problem)
             (path-normalization-problem-to-value problem))]
    [(closure)
     (format "subpath ~a has different closure values: ~a and ~a"
             (path-normalization-problem-subpath-index problem)
             (path-normalization-problem-from-value problem)
             (path-normalization-problem-to-value problem))]
    [(segment-presence)
     (format "subpath ~a pairs a point-only subpath with ~a stored segments"
             (path-normalization-problem-subpath-index problem)
             (max (path-normalization-problem-from-value problem)
                  (path-normalization-problem-to-value problem)))]
    [else
     "unknown path normalization problem"]))

; path-subpath->cubic : path-subpath? -> path-subpath?
;;   Converts the stored segments of one subpath to cubic segments.
(define (path-subpath->cubic subpath)
  (define original-segments
    (path-subpath-segments subpath))
  (define-values (reversed-segments _final-point changed?)
    (for/fold ([reversed-segments '()]
               [current-point (path-subpath-start subpath)]
               [changed? #f])
              ([segment (in-list original-segments)])
      (define cubic-segment
        (path-segment->cubic current-point segment))
      (values (cons cubic-segment reversed-segments)
              (path-segment-end segment)
              (or changed?
                  (not (eq? cubic-segment segment))))))
  (if changed?
      (path-subpath (path-subpath-start subpath)
                    (reverse reversed-segments)
                    (path-subpath-closed? subpath))
      subpath))

; path-segment->cubic : vec2? path-segment? -> cubic-bezier-path-segment?
;;   Converts one line or cubic segment to an equivalent cubic segment.
(define (path-segment->cubic start segment)
  (cond
    [(line-path-segment? segment)
     (define end
       (line-path-segment-end segment))
     (cubic-bezier-path-segment
      (vec2-lerp start end 1/3)
      (vec2-lerp start end 2/3)
      end)]
    [(cubic-bezier-path-segment? segment)
     segment]
    [else
     (raise-argument-error
      'path-segment->cubic
      "supported path segment"
      segment)]))

; normalize-corresponding-subpaths : (listof path-subpath?)
;                                    (listof path-subpath?)
;                                    -> (values (listof path-subpath?)
;                                               (listof path-subpath?))
;;   Gives each corresponding nonempty cubic subpath the same segment count.
(define (normalize-corresponding-subpaths from-subpaths to-subpaths)
  (define-values (reversed-from reversed-to)
    (for/fold ([reversed-from '()]
               [reversed-to '()])
              ([from-subpath (in-list from-subpaths)]
               [to-subpath (in-list to-subpaths)])
      (define target-count
        (max (length (path-subpath-segments from-subpath))
             (length (path-subpath-segments to-subpath))))
      (values
       (cons (path-subpath-normalize-segment-count from-subpath target-count)
             reversed-from)
       (cons (path-subpath-normalize-segment-count to-subpath target-count)
             reversed-to))))
  (values (reverse reversed-from)
          (reverse reversed-to)))

; path-subpath-normalize-segment-count : path-subpath?
;                                        exact-nonnegative-integer?
;                                        -> path-subpath?
;;   Splits the longest current cubic until subpath has target-count segments.
(define (path-subpath-normalize-segment-count subpath target-count)
  (define segments
    (path-subpath-segments subpath))
  (cond
    [(= (length segments) target-count)
     subpath]
    [else
     (define curves
       (path-subpath->cubic-curves subpath))
     (define normalized-curves
       (let loop ([current-curves curves])
         (if (= (length current-curves) target-count)
             current-curves
             (loop (split-longest-cubic-curve current-curves)))))
     (path-subpath
      (path-subpath-start subpath)
      (for/list ([curve (in-list normalized-curves)])
        (cubic-curve->segment curve))
      (path-subpath-closed? subpath))]))

; path-subpath->cubic-curves : path-subpath? -> (listof cubic-curve?)
;;   Adds each cubic segment's implicit start point.
(define (path-subpath->cubic-curves subpath)
  (define-values (reversed-curves _final-point)
    (for/fold ([reversed-curves '()]
               [current-point (path-subpath-start subpath)])
              ([segment (in-list (path-subpath-segments subpath))])
      (unless (cubic-bezier-path-segment? segment)
        (raise-arguments-error
         'path-geometry-normalize-for-morph
         "normalization expected cubic segments after conversion"
         "segment" segment))
      (values (cons (segment->cubic-curve current-point segment)
                    reversed-curves)
              (cubic-bezier-path-segment-end segment))))
  (reverse reversed-curves))

; split-longest-cubic-curve : (and/c pair? (listof cubic-curve?))
;                             -> (listof cubic-curve?)
;;   Splits the longest curve at one half, resolving length ties by order.
(define (split-longest-cubic-curve curves)
  (define target-index
    (longest-cubic-curve-index curves))
  (let loop ([remaining curves]
             [index 0]
             [reversed-prefix '()])
    (cond
      [(null? remaining)
       (raise-arguments-error
        'path-geometry-normalize-for-morph
        "could not find the selected cubic segment"
        "segment-index" target-index)]
      [(= index target-index)
       (define-values (left right)
         (split-cubic-curve (car remaining) 1/2))
       (append (reverse reversed-prefix)
               (list left right)
               (cdr remaining))]
      [else
       (loop (cdr remaining)
             (add1 index)
             (cons (car remaining) reversed-prefix))])))

; longest-cubic-curve-index : (and/c pair? (listof cubic-curve?))
;                             -> exact-nonnegative-integer?
;;   Returns the earliest index having the greatest approximate arc length.
(define (longest-cubic-curve-index curves)
  (define-values (first-length _first-samples)
    (cubic-curve-arc-samples (car curves)))
  (define-values (best-index _best-length)
    (for/fold ([best-index 0]
               [best-length first-length])
              ([curve (in-list (cdr curves))]
               [index (in-naturals 1)])
      (define-values (curve-length _samples)
        (cubic-curve-arc-samples curve))
      (if (> curve-length best-length)
          (values index curve-length)
          (values best-index best-length))))
  best-index)

; path-geometry-with-subpaths : path-geometry? (listof path-subpath?)
;                               -> path-geometry?
;;   Reuses geometry when subpaths are the same objects in the same order.
(define (path-geometry-with-subpaths geometry subpaths)
  (if (same-objects-in-order? (path-geometry-subpaths geometry)
                              subpaths)
      geometry
      (path-geometry subpaths)))

; same-objects-in-order? : list? list? -> boolean?
;;   Reports whether two lists contain the same objects in the same order.
(define (same-objects-in-order? left right)
  (and (= (length left) (length right))
       (for/and ([left-value (in-list left)]
                 [right-value (in-list right)])
         (eq? left-value right-value))))


;;;
;;; Path Morphing
;;;

; path-geometry-morph-compatible? : path-geometry? path-geometry? -> boolean?
;;   Reports whether two paths have corresponding morph structure.
(define (path-geometry-morph-compatible? from to)
  (check-path-geometry 'path-geometry-morph-compatible? from)
  (check-path-geometry 'path-geometry-morph-compatible? to)
  (not (path-geometry-morph-problem from to)))

; path-geometry-lerp : path-geometry? path-geometry? unit-real?
;                      -> path-geometry?
;;   Interpolates every corresponding stored point of compatible paths.
(define (path-geometry-lerp from to progress)
  (check-path-geometry 'path-geometry-lerp from)
  (check-path-geometry 'path-geometry-lerp to)
  (unless (and (finite-real? progress)
               (<= 0 progress 1))
    (raise-argument-error
     'path-geometry-lerp
     "finite real in the closed unit interval"
     progress))
  (define problem
    (path-geometry-morph-problem from to))
  (when problem
    (raise-arguments-error
     'path-geometry-lerp
     "path geometries must have corresponding morph structure"
     "problem" (path-morph-problem->string problem)
     "from" from
     "to" to))
  (cond
    [(zero? progress)
     from]
    [(= progress 1)
     to]
    [else
     (path-geometry
      (for/list ([from-subpath
                  (in-list (path-geometry-subpaths from))]
                 [to-subpath
                  (in-list (path-geometry-subpaths to))])
        (path-subpath-lerp from-subpath to-subpath progress)))]))

(struct path-morph-problem (kind subpath-index segment-index from-value to-value)
  #:transparent)

;; path-morph-problem describes the first structural mismatch between paths.
;;  - kind           symbol?                         mismatch category.
;;  - subpath-index  (or/c exact-nonnegative-integer? #f)
;;                                                   affected subpath index.
;;  - segment-index  (or/c exact-nonnegative-integer? #f)
;;                                                   affected segment index.
;;  - from-value     any/c                           source structural value.
;;  - to-value       any/c                           destination structural value.

; path-geometry-morph-problem : path-geometry? path-geometry?
;                               -> (or/c path-morph-problem? false/c)
;;   Returns the first deterministic structural mismatch between paths.
(define (path-geometry-morph-problem from to)
  (define from-subpaths
    (path-geometry-subpaths from))
  (define to-subpaths
    (path-geometry-subpaths to))
  (cond
    [(not (= (length from-subpaths)
             (length to-subpaths)))
     (path-morph-problem 'subpath-count
                         #f
                         #f
                         (length from-subpaths)
                         (length to-subpaths))]
    [else
     (for/or ([from-subpath (in-list from-subpaths)]
              [to-subpath (in-list to-subpaths)]
              [subpath-index (in-naturals)])
       (path-subpath-morph-problem from-subpath
                                   to-subpath
                                   subpath-index))]))

; path-subpath-morph-problem : path-subpath? path-subpath?
;                              exact-nonnegative-integer?
;                              -> (or/c path-morph-problem? false/c)
;;   Returns the first structural mismatch between two corresponding subpaths.
(define (path-subpath-morph-problem from to subpath-index)
  (define from-segments
    (path-subpath-segments from))
  (define to-segments
    (path-subpath-segments to))
  (cond
    [(not (eq? (path-subpath-closed? from)
               (path-subpath-closed? to)))
     (path-morph-problem 'closure
                         subpath-index
                         #f
                         (path-subpath-closed? from)
                         (path-subpath-closed? to))]
    [(not (= (length from-segments)
             (length to-segments)))
     (path-morph-problem 'segment-count
                         subpath-index
                         #f
                         (length from-segments)
                         (length to-segments))]
    [else
     (for/or ([from-segment (in-list from-segments)]
              [to-segment (in-list to-segments)]
              [segment-index (in-naturals)])
       (define from-kind
         (path-segment-kind from-segment))
       (define to-kind
         (path-segment-kind to-segment))
       (and (not (eq? from-kind to-kind))
            (path-morph-problem 'segment-kind
                                subpath-index
                                segment-index
                                from-kind
                                to-kind)))]))

; path-subpath-lerp : path-subpath? path-subpath? unit-real?
;                     -> path-subpath?
;;   Interpolates one pair of structurally compatible subpaths.
(define (path-subpath-lerp from to progress)
  (path-subpath
   (vec2-lerp (path-subpath-start from)
              (path-subpath-start to)
              progress)
   (for/list ([from-segment (in-list (path-subpath-segments from))]
              [to-segment (in-list (path-subpath-segments to))])
     (path-segment-lerp from-segment to-segment progress))
   (path-subpath-closed? from)))

; path-segment-lerp : path-segment? path-segment? unit-real?
;                     -> path-segment?
;;   Interpolates one pair of corresponding same-kind segments.
(define (path-segment-lerp from to progress)
  (cond
    [(and (line-path-segment? from)
          (line-path-segment? to))
     (line-path-segment
      (vec2-lerp (line-path-segment-end from)
                 (line-path-segment-end to)
                 progress))]
    [(and (cubic-bezier-path-segment? from)
          (cubic-bezier-path-segment? to))
     (cubic-bezier-path-segment
      (vec2-lerp (cubic-bezier-path-segment-control1 from)
                 (cubic-bezier-path-segment-control1 to)
                 progress)
      (vec2-lerp (cubic-bezier-path-segment-control2 from)
                 (cubic-bezier-path-segment-control2 to)
                 progress)
      (vec2-lerp (cubic-bezier-path-segment-end from)
                 (cubic-bezier-path-segment-end to)
                 progress))]
    [else
     (raise-arguments-error
      'path-geometry-lerp
      "corresponding segments must have the same kind"
      "from segment" from
      "to segment" to)]))

; path-segment-kind : path-segment? -> symbol?
;;   Returns the structural kind used for path morph compatibility.
(define (path-segment-kind segment)
  (cond
    [(line-path-segment? segment)
     'line]
    [(cubic-bezier-path-segment? segment)
     'cubic-bezier]
    [else
     (raise-argument-error
      'path-segment-kind
      "supported path segment"
      segment)]))

; path-morph-problem->string : path-morph-problem? -> string?
;;   Converts one compatibility problem to a concise diagnostic sentence.
(define (path-morph-problem->string problem)
  (case (path-morph-problem-kind problem)
    [(subpath-count)
     (format "different subpath counts: ~a and ~a"
             (path-morph-problem-from-value problem)
             (path-morph-problem-to-value problem))]
    [(closure)
     (format "subpath ~a has different closure values: ~a and ~a"
             (path-morph-problem-subpath-index problem)
             (path-morph-problem-from-value problem)
             (path-morph-problem-to-value problem))]
    [(segment-count)
     (format "subpath ~a has different segment counts: ~a and ~a"
             (path-morph-problem-subpath-index problem)
             (path-morph-problem-from-value problem)
             (path-morph-problem-to-value problem))]
    [(segment-kind)
     (format "subpath ~a segment ~a has different kinds: ~a and ~a"
             (path-morph-problem-subpath-index problem)
             (path-morph-problem-segment-index problem)
             (path-morph-problem-from-value problem)
             (path-morph-problem-to-value problem))]
    [else
     "unknown path morph compatibility problem"]))


;;;
;;; Bounds
;;;

; path-geometry-bounds : path-geometry?
;                        -> (values finite-real?
;                                   finite-real?
;                                   finite-real?
;                                   finite-real?)
;;   Returns the tight axis-aligned bounds of all path segments.
(define (path-geometry-bounds geometry)
  (check-path-geometry 'path-geometry-bounds geometry)
  (define points
    (path-geometry-bound-points geometry))
  (when (null? points)
    (raise-arguments-error
     'path-geometry-bounds
     "empty path geometry has no bounds"
     "geometry" geometry))
  (define first-point
    (car points))
  (for/fold ([minimum-x (vec2-x first-point)]
             [minimum-y (vec2-y first-point)]
             [maximum-x (vec2-x first-point)]
             [maximum-y (vec2-y first-point)])
            ([point (in-list (cdr points))])
    (values (min minimum-x (vec2-x point))
            (min minimum-y (vec2-y point))
            (max maximum-x (vec2-x point))
            (max maximum-y (vec2-y point)))))

; path-geometry-center : path-geometry? -> vec2?
;;   Returns the center of geometry's axis-aligned bounds.
(define (path-geometry-center geometry)
  (define-values (minimum-x minimum-y maximum-x maximum-y)
    (path-geometry-bounds geometry))
  (vec2 (/ (+ minimum-x maximum-x) 2)
        (/ (+ minimum-y maximum-y) 2)))

; path-geometry-bound-points : path-geometry? -> (listof vec2?)
;;   Returns endpoints and interior extrema needed for exact segment bounds.
(define (path-geometry-bound-points geometry)
  (for*/list ([subpath (in-list (path-geometry-subpaths geometry))]
              [point (in-list (path-subpath-bound-points subpath))])
    point))

; path-subpath-bound-points : path-subpath? -> (listof vec2?)
;;   Returns the points needed to bound one subpath.
(define (path-subpath-bound-points subpath)
  (define-values (reversed-points _current-point)
    (for/fold ([reversed-points (list (path-subpath-start subpath))]
               [current-point (path-subpath-start subpath)])
              ([segment (in-list (path-subpath-segments subpath))])
      (define segment-points
        (path-segment-bound-points current-point segment))
      (values
       (for/fold ([points reversed-points])
                 ([point (in-list segment-points)])
         (cons point points))
       (path-segment-end segment))))
  (reverse reversed-points))

; path-segment-bound-points : vec2? path-segment? -> (listof vec2?)
;;   Returns a segment endpoint and any interior coordinate extrema.
(define (path-segment-bound-points start segment)
  (cond
    [(line-path-segment? segment)
     (list (line-path-segment-end segment))]
    [(cubic-bezier-path-segment? segment)
     (define curve
       (segment->cubic-curve start segment))
     (cons
      (cubic-curve-end curve)
      (for/list ([parameter
                  (in-list (cubic-curve-extrema-parameters curve))])
        (cubic-curve-point curve parameter)))]
    [else
     (raise-argument-error
      'path-segment-bound-points
      "supported path segment"
      segment)]))

; cubic-curve-extrema-parameters : cubic-curve? -> (listof finite-real?)
;;   Returns interior parameters where an x or y derivative is zero.
(define (cubic-curve-extrema-parameters curve)
  (append
   (cubic-coordinate-extrema-parameters
    (vec2-x (cubic-curve-start curve))
    (vec2-x (cubic-curve-control1 curve))
    (vec2-x (cubic-curve-control2 curve))
    (vec2-x (cubic-curve-end curve)))
   (cubic-coordinate-extrema-parameters
    (vec2-y (cubic-curve-start curve))
    (vec2-y (cubic-curve-control1 curve))
    (vec2-y (cubic-curve-control2 curve))
    (vec2-y (cubic-curve-end curve)))))

; cubic-coordinate-extrema-parameters : finite-real? finite-real?
;                                       finite-real? finite-real?
;                                       -> (listof finite-real?)
;;   Solves one normalized cubic-coordinate derivative on the open interval.
(define (cubic-coordinate-extrema-parameters p0 p1 p2 p3)
  (define scale
    (max (abs p0) (abs p1) (abs p2) (abs p3)))
  (cond
    [(zero? scale)
     '()]
    [else
     (define q0 (/ p0 scale))
     (define q1 (/ p1 scale))
     (define q2 (/ p2 scale))
     (define q3 (/ p3 scale))
     (define a
       (+ (- q0) (* 3 q1) (* -3 q2) q3))
     (define b
       (* 2 (+ q0 (* -2 q1) q2)))
     (define c
       (- q1 q0))
     (quadratic-roots-in-open-unit-interval a b c)]))

; quadratic-roots-in-open-unit-interval : finite-real? finite-real?
;                                         finite-real?
;                                         -> (listof finite-real?)
;;   Returns real roots of a*t^2+b*t+c that lie strictly between zero and one.
(define (quadratic-roots-in-open-unit-interval a b c)
  (define candidates
    (cond
      [(zero? a)
       (if (zero? b)
           '()
           (list (/ (- c) b)))]
      [else
       (define discriminant
         (- (* b b) (* 4 a c)))
       (cond
         [(negative? discriminant)
          '()]
         [(zero? discriminant)
          (list (/ (- b) (* 2 a)))]
         [else
          (define root
            (sqrt discriminant))
          (list (/ (+ (- b) root) (* 2 a))
                (/ (- (- b) root) (* 2 a)))])]))
  (for/list ([parameter (in-list candidates)]
             #:when (and (finite-real? parameter)
                         (< 0 parameter 1)))
    parameter))


;;;
;;; Cubic Bézier Helpers
;;;

(struct cubic-curve (start control1 control2 end)
  #:transparent)

;; cubic-curve represents one complete local cubic Bézier curve.
;;  - start     vec2?  curve start point.
;;  - control1  vec2?  first control point.
;;  - control2  vec2?  second control point.
;;  - end       vec2?  curve endpoint.

; segment->cubic-curve : vec2? cubic-bezier-path-segment? -> cubic-curve?
;;   Combines a segment's implicit start with its stored curve points.
(define (segment->cubic-curve start segment)
  (cubic-curve
   start
   (cubic-bezier-path-segment-control1 segment)
   (cubic-bezier-path-segment-control2 segment)
   (cubic-bezier-path-segment-end segment)))

; cubic-curve->segment : cubic-curve? -> cubic-bezier-path-segment?
;;   Removes a cubic curve's start point to make a path segment.
(define (cubic-curve->segment curve)
  (cubic-bezier-path-segment
   (cubic-curve-control1 curve)
   (cubic-curve-control2 curve)
   (cubic-curve-end curve)))

; cubic-curve-point : cubic-curve? finite-real? -> vec2?
;;   Evaluates curve with the de Casteljau construction.
(define (cubic-curve-point curve parameter)
  (define p01
    (vec2-lerp (cubic-curve-start curve)
               (cubic-curve-control1 curve)
               parameter))
  (define p12
    (vec2-lerp (cubic-curve-control1 curve)
               (cubic-curve-control2 curve)
               parameter))
  (define p23
    (vec2-lerp (cubic-curve-control2 curve)
               (cubic-curve-end curve)
               parameter))
  (define p012
    (vec2-lerp p01 p12 parameter))
  (define p123
    (vec2-lerp p12 p23 parameter))
  (vec2-lerp p012 p123 parameter))

; cubic-curve-unit-tangent : cubic-curve? finite-real? -> vec2?
;;   Returns a deterministic forward unit tangent, including stationary points.
(define (cubic-curve-unit-tangent curve parameter)
  (define one-minus-parameter
    (- 1 parameter))
  (define first-leg
    (vec2-
     (cubic-curve-control1 curve)
     (cubic-curve-start curve)))
  (define second-leg
    (vec2-
     (cubic-curve-control2 curve)
     (cubic-curve-control1 curve)))
  (define third-leg
    (vec2-
     (cubic-curve-end curve)
     (cubic-curve-control2 curve)))
  ;; The common factor 3 in the cubic derivative is irrelevant after
  ;; normalization and is omitted to avoid unnecessary numeric growth.
  (define derivative
    (vec2+
     (vec2-scale (* one-minus-parameter one-minus-parameter)
                 first-leg)
     (vec2+
      (vec2-scale (* 2 one-minus-parameter parameter)
                  second-leg)
      (vec2-scale (* parameter parameter)
                  third-leg))))
  (cond
    [(vec2-nonzero? derivative)
     (vec2-unit-direction derivative 'path-geometry-tangent-at)]
    [else
     ;; A cubic may have a zero derivative at an endpoint or cusp while still
     ;; having positive arc length. Prefer the forward one-sided direction;
     ;; fall back to the incoming direction at the final endpoint. The probe
     ;; sequence is deterministic and remains semantic rather than renderer
     ;; dependent.
     (define point
       (cubic-curve-point curve parameter))
     (define forward-direction
       (cubic-curve-probe-direction curve parameter point #t))
     (define backward-direction
       (and (not forward-direction)
            (cubic-curve-probe-direction curve parameter point #f)))
     (define direction
       (or forward-direction backward-direction))
     (unless direction
       (raise-arguments-error
        'path-geometry-tangent-at
        "the selected cubic point has no defined traversal direction"
        "parameter" parameter
        "curve" curve))
     (vec2-unit-direction direction 'path-geometry-tangent-at)]))

; cubic-curve-probe-direction : cubic-curve? finite-real? vec2? boolean?
;                               -> (or/c vec2? false/c)
;;   Finds the nearest deterministic nonzero one-sided curve displacement.
(define (cubic-curve-probe-direction curve parameter point forward?)
  (let loop ([steps cubic-tangent-probe-steps])
    (cond
      [(null? steps)
       #f]
      [else
       (define step
         (car steps))
       (define probe-parameter
         (if forward?
             (min 1 (+ parameter step))
             (max 0 (- parameter step))))
       (cond
         [(= probe-parameter parameter)
          #f]
         [else
          (define probe-point
            (cubic-curve-point curve probe-parameter))
          (define displacement
            (if forward?
                (vec2- probe-point point)
                (vec2- point probe-point)))
          (if (vec2-nonzero? displacement)
              displacement
              (loop (cdr steps)))])])))

; vec2-nonzero? : vec2? -> boolean?
;;   Reports whether value has at least one nonzero component.
(define (vec2-nonzero? value)
  (or (not (zero? (vec2-x value)))
      (not (zero? (vec2-y value)))))

; vec2-unit-direction : vec2? symbol? -> vec2?
;;   Normalizes a finite nonzero vector without squaring large raw components.
(define (vec2-unit-direction value who)
  (define scale
    (max (abs (vec2-x value))
         (abs (vec2-y value))))
  (unless (positive? scale)
    (raise-arguments-error
     who
     "a path tangent requires a nonzero direction"
     "direction" value))
  (define scaled-x
    (/ (vec2-x value) scale))
  (define scaled-y
    (/ (vec2-y value) scale))
  (define magnitude
    (sqrt (+ (* scaled-x scaled-x)
             (* scaled-y scaled-y))))
  (vec2 (/ scaled-x magnitude)
        (/ scaled-y magnitude)))

; split-cubic-curve : cubic-curve? finite-real?
;                     -> (values cubic-curve? cubic-curve?)
;;   Splits curve at parameter with de Casteljau subdivision.
(define (split-cubic-curve curve parameter)
  (define p01
    (vec2-lerp (cubic-curve-start curve)
               (cubic-curve-control1 curve)
               parameter))
  (define p12
    (vec2-lerp (cubic-curve-control1 curve)
               (cubic-curve-control2 curve)
               parameter))
  (define p23
    (vec2-lerp (cubic-curve-control2 curve)
               (cubic-curve-end curve)
               parameter))
  (define p012
    (vec2-lerp p01 p12 parameter))
  (define p123
    (vec2-lerp p12 p23 parameter))
  (define midpoint
    (vec2-lerp p012 p123 parameter))
  (values
   (cubic-curve (cubic-curve-start curve)
                p01
                p012
                midpoint)
   (cubic-curve midpoint
                p123
                p23
                (cubic-curve-end curve))))

; cubic-curve-subcurve : cubic-curve? finite-real? finite-real?
;                        -> cubic-curve?
;;   Extracts the parameter interval from start through end.
(define (cubic-curve-subcurve curve start end)
  (cond
    [(and (zero? start) (= end 1))
     curve]
    [(zero? start)
     (define-values (left _right)
       (split-cubic-curve curve end))
     left]
    [(= end 1)
     (define-values (_left right)
       (split-cubic-curve curve start))
     right]
    [else
     (define-values (left _right)
       (split-cubic-curve curve end))
     (define-values (_prefix selected)
       (split-cubic-curve left (/ start end)))
     selected]))


;;;
;;; Path Length and Partial Extraction
;;;

(struct curve-leaf (parameter point length)
  #:transparent)

;; curve-leaf represents one terminal adaptive-subdivision interval.
;;  - parameter  finite-real?      interval end parameter.
;;  - point      vec2?             interval endpoint.
;;  - length     nonnegative-real? estimated interval arc length.

(struct curve-arc-sample (parameter point distance)
  #:transparent)

;; curve-arc-sample represents one cumulative curve-length table entry.
;;  - parameter  finite-real?      curve parameter in increasing order.
;;  - point      vec2?             point at parameter.
;;  - distance   nonnegative-real? approximate distance from the curve start.

(struct path-edge (start segment length arc-samples)
  #:transparent)

;; path-edge represents one directed traversal edge.
;;  - start        vec2?                         edge start point.
;;  - segment      path-segment?                 semantic edge segment.
;;  - length       nonnegative-real?             local arc length.
;;  - arc-samples  (or/c #f (listof curve-arc-sample?))
;;                                               cubic inverse-length table.

(struct path-piece (start segment)
  #:transparent)

;; path-piece represents one selected positive-length edge interval.
;;  - start    vec2?          selected interval start point.
;;  - segment  path-segment?  segment ending the selected interval.

(struct offset-line-edge (start end tangent offset-start offset-end)
  #:transparent)

;; offset-line-edge caches one positive original line and its shifted endpoints.

(struct offset-vertex-join (entry segments exit)
  #:transparent)

;; offset-vertex-join represents the connection from one shifted edge to the next.
;;  - entry     vec2?                   endpoint reached by the incoming edge.
;;  - segments  (listof path-segment?)  explicit connector pieces.
;;  - exit      vec2?                   start point of the outgoing edge.

; cubic-length-relative-tolerance : positive-real?
;;   Gives the scale-relative adaptive curve-length tolerance.
(define cubic-length-relative-tolerance
  1e-8)

; cubic-length-absolute-tolerance : positive-real?
;;   Gives the minimum adaptive curve-length tolerance in local units.
(define cubic-length-absolute-tolerance
  1e-10)

; cubic-length-maximum-depth : exact-nonnegative-integer?
;;   Gives the maximum number of binary curve subdivisions.
(define cubic-length-maximum-depth
  20)

; cubic-tangent-probe-steps : (listof positive-real?)
;;   Gives deterministic parameter offsets for stationary tangent fallback.
(define cubic-tangent-probe-steps
  '(1/1048576 1/65536 1/4096 1/256 1/16 1))

; path-subpath-length : path-subpath? -> nonnegative-real?
;;   Returns the total local arc length of subpath.
(define (path-subpath-length subpath)
  (check-path-subpath 'path-subpath-length subpath)
  (for/sum ([edge (in-list (path-subpath-edges subpath))])
    (path-edge-length edge)))

; path-geometry-length : path-geometry? -> nonnegative-real?
;;   Returns the sum of subpath lengths in significant traversal order.
(define (path-geometry-length geometry)
  (check-path-geometry 'path-geometry-length geometry)
  (for/sum ([subpath (in-list (path-geometry-subpaths geometry))])
    (path-subpath-length subpath)))

; path-geometry-point-at : path-geometry? finite-real? -> vec2?
;;   Returns the point at one total arc-length fraction of geometry.
(define (path-geometry-point-at geometry fraction)
  (check-path-geometry 'path-geometry-point-at geometry)
  (check-path-fraction 'path-geometry-point-at "fraction" fraction)
  (define edges
    (for*/list ([subpath (in-list (path-geometry-subpaths geometry))]
                [edge (in-list (path-subpath-edges subpath))])
      edge))
  (define total-length
    (for/sum ([edge (in-list edges)])
      (path-edge-length edge)))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     'path-geometry-point-at
     "the path's total length must be positive and finite"
     "path-length" total-length
     "geometry" geometry))
  (define first-positive-edge
    (for/first ([edge (in-list edges)]
                #:when (positive? (path-edge-length edge)))
      edge))
  (define last-positive-edge
    (for/fold ([last-edge #f])
              ([edge (in-list edges)])
      (if (positive? (path-edge-length edge))
          edge
          last-edge)))
  (cond
    [(zero? fraction)
     (path-edge-start first-positive-edge)]
    [(= fraction 1)
     (path-segment-end
      (path-edge-segment last-positive-edge))]
    [else
     (define target-distance
       (* fraction total-length))
     (let loop ([remaining edges]
                [offset 0])
       (cond
         [(null? remaining)
          (path-segment-end
           (path-edge-segment last-positive-edge))]
         [else
          (define edge
            (car remaining))
          (define edge-length
            (path-edge-length edge))
          (define next-offset
            (+ offset edge-length))
          (cond
            [(zero? edge-length)
             (loop (cdr remaining) next-offset)]
            [(<= target-distance next-offset)
             (path-edge-point-at-distance
              edge
              (- target-distance offset))]
            [else
             (loop (cdr remaining) next-offset)])]))]))

; path-geometry-tangent-at : path-geometry? finite-real? -> vec2?
;;   Returns the forward unit tangent at one total arc-length fraction.
(define (path-geometry-tangent-at geometry fraction)
  (check-path-geometry 'path-geometry-tangent-at geometry)
  (check-path-fraction 'path-geometry-tangent-at "fraction" fraction)
  (define edges
    (for*/list ([subpath (in-list (path-geometry-subpaths geometry))]
                [edge (in-list (path-subpath-edges subpath))])
      edge))
  (define total-length
    (for/sum ([edge (in-list edges)])
      (path-edge-length edge)))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     'path-geometry-tangent-at
     "the path's total length must be positive and finite"
     "path-length" total-length
     "geometry" geometry))
  (define first-positive-edge
    (for/first ([edge (in-list edges)]
                #:when (positive? (path-edge-length edge)))
      edge))
  (define last-positive-edge
    (for/fold ([last-edge #f])
              ([edge (in-list edges)])
      (if (positive? (path-edge-length edge))
          edge
          last-edge)))
  (cond
    [(zero? fraction)
     (path-edge-tangent-at-distance first-positive-edge 0)]
    [(= fraction 1)
     (path-edge-tangent-at-distance
      last-positive-edge
      (path-edge-length last-positive-edge))]
    [else
     (define target-distance
       (* fraction total-length))
     (let loop ([remaining edges]
                [offset 0])
       (cond
         [(null? remaining)
          (path-edge-tangent-at-distance
           last-positive-edge
           (path-edge-length last-positive-edge))]
         [else
          (define edge
            (car remaining))
          (define edge-length
            (path-edge-length edge))
          (define next-offset
            (+ offset edge-length))
          (cond
            [(zero? edge-length)
             (loop (cdr remaining) next-offset)]
            [(<= target-distance next-offset)
             (path-edge-tangent-at-distance
              edge
              (- target-distance offset))]
            [else
             (loop (cdr remaining) next-offset)])]))]))

; path-geometry-normal-at : path-geometry? finite-real? -> vec2?
;;   Returns the left unit normal at one total arc-length fraction.
(define (path-geometry-normal-at geometry fraction)
  (define tangent
    (path-geometry-tangent-at geometry fraction))
  (vec2 (- (vec2-y tangent))
        (vec2-x tangent)))

; path-geometry-offset : path-geometry? finite-real?
;                        [#:join (or/c 'miter 'bevel 'round)]
;                        [#:miter-limit finite-real?]
;                        -> path-geometry?
;;   Returns a continuous signed parallel offset for straight-segment subpaths.
;;   Positive distance is to the left of stored traversal direction.
(define (path-geometry-offset geometry distance
                              #:join [join 'miter]
                              #:miter-limit [miter-limit 4])
  (check-path-geometry 'path-geometry-offset geometry)
  (unless (finite-real? distance)
    (raise-argument-error 'path-geometry-offset "finite real?" distance))
  (check-path-offset-join 'path-geometry-offset join)
  (unless (and (finite-real? miter-limit)
               (>= miter-limit 1))
    (raise-argument-error
     'path-geometry-offset
     "finite real greater than or equal to 1"
     miter-limit))
  (cond
    [(zero? distance)
     geometry]
    [else
     (path-geometry
      (for/list ([subpath (in-list (path-geometry-subpaths geometry))]
                 [subpath-index (in-naturals)])
        (path-subpath-offset-lines
         subpath
         distance
         join
         miter-limit
         subpath-index)))]))

; path-subpath-offset-lines : path-subpath? finite-real? symbol? finite-real?
;                             exact-nonnegative-integer? -> path-subpath?
;;   Offsets one line-only subpath and resolves every interior corner.
(define (path-subpath-offset-lines subpath
                                   distance
                                   join
                                   miter-limit
                                   subpath-index)
  (define edges
    (for/list ([edge (in-list (path-subpath-edges subpath))]
               [edge-index (in-naturals)])
      (define segment
        (path-edge-segment edge))
      (unless (line-path-segment? segment)
        (raise-arguments-error
         'path-geometry-offset
         "nonzero joined offsets currently require line-only path geometry"
         "subpath-index" subpath-index
         "segment-index" edge-index
         "segment" segment))
      (unless (positive? (path-edge-length edge))
        (raise-arguments-error
         'path-geometry-offset
         "nonzero joined offsets require every traversed line edge to have positive length"
         "subpath-index" subpath-index
         "edge-index" edge-index
         "edge" edge))
      (define tangent
        (vec2-unit-direction
         (vec2- (line-path-segment-end segment)
                (path-edge-start edge))
         'path-geometry-offset))
      (define normal
        (left-normal tangent))
      (offset-line-edge
       (path-edge-start edge)
       (line-path-segment-end segment)
       tangent
       (vec2+ (path-edge-start edge)
              (vec2-scale distance normal))
       (vec2+ (line-path-segment-end segment)
              (vec2-scale distance normal)))))
  (unless (pair? edges)
    (raise-arguments-error
     'path-geometry-offset
     "nonzero joined offsets require at least one positive line edge per subpath"
     "subpath-index" subpath-index
     "subpath" subpath))
  (if (path-subpath-closed? subpath)
      (closed-offset-subpath edges distance join miter-limit subpath-index)
      (open-offset-subpath edges distance join miter-limit subpath-index)))

; open-offset-subpath : (nonempty-listof offset-line-edge?) finite-real?
;                       symbol? finite-real? exact-nonnegative-integer?
;                       -> path-subpath?
;;   Builds one open continuous joined offset path.
(define (open-offset-subpath edges distance join miter-limit subpath-index)
  (define edge-count
    (length edges))
  (define joins
    (for/list ([incoming (in-list edges)]
               [outgoing (in-list (cdr edges))]
               [vertex-index (in-naturals 1)])
      (make-offset-vertex-join incoming
                               outgoing
                               distance
                               join
                               miter-limit
                               subpath-index
                               vertex-index)))
  (define start
    (offset-line-edge-offset-start (car edges)))
  (define-values (segments _current)
    (for/fold ([segments '()]
               [current start])
              ([edge (in-list edges)]
               [edge-index (in-naturals)])
      (define last-edge?
        (= edge-index (sub1 edge-count)))
      (define selected-join
        (and (not last-edge?)
             (list-ref joins edge-index)))
      (define edge-end
        (if selected-join
            (offset-vertex-join-entry selected-join)
            (offset-line-edge-offset-end edge)))
      (define edge-segments
        (append-segment-if-needed
         segments
         current
         (line-path-segment edge-end)))
      (if selected-join
          (values (append edge-segments
                          (offset-vertex-join-segments selected-join))
                  (offset-vertex-join-exit selected-join))
          (values edge-segments edge-end))))
  (path-subpath start segments #f))

; closed-offset-subpath : (nonempty-listof offset-line-edge?) finite-real?
;                         symbol? finite-real? exact-nonnegative-integer?
;                         -> path-subpath?
;;   Builds one cyclic joined offset path including the join at the stored start.
(define (closed-offset-subpath edges distance join miter-limit subpath-index)
  (define edge-count
    (length edges))
  (define joins
    (for/list ([vertex-index (in-range edge-count)])
      (define incoming
        (list-ref edges (modulo (sub1 vertex-index) edge-count)))
      (define outgoing
        (list-ref edges vertex-index))
      (make-offset-vertex-join incoming
                               outgoing
                               distance
                               join
                               miter-limit
                               subpath-index
                               vertex-index)))
  (define start
    (offset-vertex-join-exit (car joins)))
  (define-values (segments _current)
    (for/fold ([segments '()]
               [current start])
              ([edge (in-list edges)]
               [edge-index (in-naturals)])
      (define next-join
        (list-ref joins (modulo (add1 edge-index) edge-count)))
      (define edge-end
        (offset-vertex-join-entry next-join))
      (define edge-segments
        (append-segment-if-needed
         segments
         current
         (line-path-segment edge-end)))
      (values (append edge-segments
                      (offset-vertex-join-segments next-join))
              (offset-vertex-join-exit next-join))))
  (path-subpath start segments #t))

; append-segment-if-needed : (listof path-segment?) vec2? path-segment?
;                            -> (listof path-segment?)
;;   Appends segment unless it is a zero-length line from current.
(define (append-segment-if-needed segments current segment)
  (cond
    [(and (line-path-segment? segment)
          (equal? current (line-path-segment-end segment)))
     segments]
    [else
     (append segments (list segment))]))

; make-offset-vertex-join : offset-line-edge? offset-line-edge? finite-real?
;                           symbol? finite-real? exact-nonnegative-integer?
;                           exact-nonnegative-integer?
;                           -> offset-vertex-join?
;;   Resolves one vertex using inside-intersection plus the selected outside join.
(define (make-offset-vertex-join incoming
                                 outgoing
                                 distance
                                 join
                                 miter-limit
                                 subpath-index
                                 vertex-index)
  (define incoming-tangent
    (offset-line-edge-tangent incoming))
  (define outgoing-tangent
    (offset-line-edge-tangent outgoing))
  (define turn-cross
    (vec2-cross incoming-tangent outgoing-tangent))
  (define turn-dot
    (vec2-dot incoming-tangent outgoing-tangent))
  (define incoming-end
    (offset-line-edge-offset-end incoming))
  (define outgoing-start
    (offset-line-edge-offset-start outgoing))
  (define vertex
    (offset-line-edge-end incoming))
  (cond
    [(near-zero? turn-cross)
     (cond
       [(positive? turn-dot)
        (define common
          (vec2-lerp incoming-end outgoing-start 1/2))
        (offset-vertex-join common '() common)]
       [else
        (raise-arguments-error
         'path-geometry-offset
         "a 180-degree reversal has no unique joined parallel offset"
         "subpath-index" subpath-index
         "vertex-index" vertex-index
         "vertex" vertex)])]
    [else
     (define intersection
       (offset-line-intersection incoming outgoing))
     (define outside-corner?
       (< (* turn-cross distance) 0))
     (cond
       [(not outside-corner?)
        ;; The selected side is inside the turn. The two parallel lines meet at
        ;; their natural intersection; applying an outside stroke-join policy
        ;; here would reverse the path tangent.
        (offset-vertex-join intersection '() intersection)]
       [(eq? join 'bevel)
        (bevel-offset-join incoming-end outgoing-start)]
       [(eq? join 'round)
        (round-offset-join vertex
                           incoming-end
                           outgoing-start
                           turn-cross
                           turn-dot)]
       [else
        (define miter-ratio
          (/ (vec2-distance vertex intersection)
             (abs distance)))
        (if (<= miter-ratio miter-limit)
            (offset-vertex-join intersection '() intersection)
            (bevel-offset-join incoming-end outgoing-start))])]))

; bevel-offset-join : vec2? vec2? -> offset-vertex-join?
;;   Connects adjacent outside offset lines by one straight chord.
(define (bevel-offset-join entry exit)
  (offset-vertex-join
   entry
   (if (equal? entry exit)
       '()
       (list (line-path-segment exit)))
   exit))

; round-offset-join : vec2? vec2? vec2? finite-real? finite-real?
;                     -> offset-vertex-join?
;;   Connects an outside corner with one or more <=90-degree cubic arc pieces.
(define (round-offset-join center entry exit turn-cross turn-dot)
  (define radius
    (vec2-distance center entry))
  (define sweep
    (atan turn-cross turn-dot))
  (define segment-count
    (max 1
         (inexact->exact
          (ceiling (/ (abs sweep) (atan 1 0))))))
  (define delta
    (/ sweep segment-count))
  (define start-vector
    (vec2- entry center))
  (define start-angle
    (atan (vec2-y start-vector)
          (vec2-x start-vector)))
  (define k
    (* 4/3
       (/ (sin (/ delta 4))
          (cos (/ delta 4)))))
  (define segments
    (let loop ([index 0]
               [current entry]
               [reversed-segments '()])
      (cond
        [(= index segment-count)
         (reverse reversed-segments)]
        [else
         (define angle
           (+ start-angle (* index delta)))
         (define next-angle
           (+ angle delta))
         (define endpoint
           (if (= index (sub1 segment-count))
               exit
               (vec2+ center
                      (vec2 (* radius (cos next-angle))
                            (* radius (sin next-angle))))))
         (define tangent-at-start
           (vec2 (- (sin angle))
                 (cos angle)))
         (define tangent-at-end
           (vec2 (- (sin next-angle))
                 (cos next-angle)))
         (define control1
           (vec2+ current
                  (vec2-scale (* k radius)
                              tangent-at-start)))
         (define control2
           (vec2- endpoint
                  (vec2-scale (* k radius)
                              tangent-at-end)))
         (loop (add1 index)
               endpoint
               (cons (cubic-bezier-path-segment
                      control1
                      control2
                      endpoint)
                     reversed-segments))])))
  (offset-vertex-join entry segments exit))

; offset-line-intersection : offset-line-edge? offset-line-edge? -> vec2?
;;   Intersects the two infinite directed offset lines at a nonparallel vertex.
(define (offset-line-intersection incoming outgoing)
  (define first-point
    (offset-line-edge-offset-end incoming))
  (define second-point
    (offset-line-edge-offset-start outgoing))
  (define first-direction
    (offset-line-edge-tangent incoming))
  (define second-direction
    (offset-line-edge-tangent outgoing))
  (define denominator
    (vec2-cross first-direction second-direction))
  (define displacement
    (vec2- second-point first-point))
  (define first-parameter
    (/ (vec2-cross displacement second-direction)
       denominator))
  (vec2+ first-point
         (vec2-scale first-parameter first-direction)))

; left-normal : vec2? -> vec2?
;;   Rotates one unit tangent a quarter-turn counter-clockwise.
(define (left-normal tangent)
  (vec2 (- (vec2-y tangent))
        (vec2-x tangent)))

; vec2-cross : vec2? vec2? -> finite-real?
;;   Returns the scalar two-dimensional cross product.
(define (vec2-cross left right)
  (- (* (vec2-x left) (vec2-y right))
     (* (vec2-y left) (vec2-x right))))

; vec2-dot : vec2? vec2? -> finite-real?
;;   Returns the Euclidean dot product.
(define (vec2-dot left right)
  (+ (* (vec2-x left) (vec2-x right))
     (* (vec2-y left) (vec2-y right))))

; near-zero? : finite-real? -> boolean?
;;   Treats only floating roundoff around parallel unit vectors as zero.
(define (near-zero? value)
  (<= (abs value) 1e-12))

; check-path-offset-join : symbol? any/c -> void?
;;   Validates one public joined-offset policy.
(define (check-path-offset-join who join)
  (unless (memq join '(miter bevel round))
    (raise-argument-error
     who
     "(or/c 'miter 'bevel 'round)"
     join)))

; path-edge-point-at-distance : path-edge? real? -> vec2?
;;   Returns one point on edge using the same arc-length model as extraction.
(define (path-edge-point-at-distance edge distance)
  (define edge-length
    (path-edge-length edge))
  (define segment
    (path-edge-segment edge))
  (cond
    [(<= distance 0)
     (path-edge-start edge)]
    [(>= distance edge-length)
     (path-segment-end segment)]
    [(line-path-segment? segment)
     (vec2-lerp (path-edge-start edge)
                (line-path-segment-end segment)
                (/ distance edge-length))]
    [(cubic-bezier-path-segment? segment)
     (define parameter
       (curve-arc-distance->parameter
        (path-edge-arc-samples edge)
        distance
        'path-geometry-point-at))
     (cubic-curve-point
      (segment->cubic-curve (path-edge-start edge) segment)
      parameter)]
    [else
     (raise-argument-error
      'path-edge-point-at-distance
      "supported path segment"
      segment)]))

; path-edge-tangent-at-distance : path-edge? real? -> vec2?
;;   Returns the forward unit tangent at one distance on a positive edge.
(define (path-edge-tangent-at-distance edge distance)
  (define edge-length
    (path-edge-length edge))
  (unless (positive? edge-length)
    (raise-arguments-error
     'path-geometry-tangent-at
     "the selected path edge must have positive length"
     "edge-length" edge-length
     "edge" edge))
  (define segment
    (path-edge-segment edge))
  (cond
    [(line-path-segment? segment)
     (vec2-unit-direction
      (vec2- (line-path-segment-end segment)
             (path-edge-start edge))
      'path-geometry-tangent-at)]
    [(cubic-bezier-path-segment? segment)
     (define parameter
       (cond
         [(<= distance 0) 0]
         [(>= distance edge-length) 1]
         [else
          (curve-arc-distance->parameter
           (path-edge-arc-samples edge)
           distance
           'path-geometry-tangent-at)]))
     (cubic-curve-unit-tangent
      (segment->cubic-curve (path-edge-start edge) segment)
      parameter)]
    [else
     (raise-argument-error
      'path-edge-tangent-at-distance
      "supported path segment"
      segment)]))

; path-geometry-partial : path-geometry? finite-real? finite-real?
;                         -> path-geometry?
;;   Extracts the arc-length interval between start and end fractions.
(define (path-geometry-partial geometry start end)
  (check-path-geometry 'path-geometry-partial geometry)
  (check-path-fraction 'path-geometry-partial "start" start)
  (check-path-fraction 'path-geometry-partial "end" end)
  (when (> start end)
    (raise-arguments-error
     'path-geometry-partial
     "the start fraction must not be greater than the end fraction"
     "start" start
     "end" end))
  (cond
    [(= start end)
     empty-path-geometry]
    [(and (zero? start)
          (= end 1))
     geometry]
    [else
     (define total-length
       (path-geometry-length geometry))
     (unless (finite-real? total-length)
       (raise-arguments-error
        'path-geometry-partial
        "the path's total length must be finite"
        "path-length" total-length
        "geometry" geometry))
     (if (zero? total-length)
         empty-path-geometry
         (path-geometry
          (path-geometry-partial-subpaths
           geometry
           (* start total-length)
           (* end total-length))))]))

; path-geometry-cycle-start : path-geometry? finite-real? -> path-geometry?
;;   Moves the stored start of one closed loop to an arc-length fraction.
;;   The loop's geometry and forward traversal are preserved cyclically.
(define (path-geometry-cycle-start geometry fraction)
  (check-path-geometry 'path-geometry-cycle-start geometry)
  (check-path-fraction 'path-geometry-cycle-start "fraction" fraction)
  (define subpaths
    (path-geometry-subpaths geometry))
  (unless (= (length subpaths) 1)
    (raise-arguments-error
     'path-geometry-cycle-start
     "cyclic start adjustment requires exactly one subpath"
     "subpath-count" (length subpaths)
     "geometry" geometry))
  (define subpath
    (car subpaths))
  (unless (path-subpath-closed? subpath)
    (raise-arguments-error
     'path-geometry-cycle-start
     "cyclic start adjustment requires a closed subpath"
     "subpath" subpath))
  (define total-length
    (path-subpath-length subpath))
  (unless (and (finite-real? total-length)
               (positive? total-length))
    (raise-arguments-error
     'path-geometry-cycle-start
     "the closed subpath's total length must be positive and finite"
     "path-length" total-length
     "subpath" subpath))
  (cond
    [(or (zero? fraction) (= fraction 1))
     geometry]
    [else
     ;; Rotate the measured edge sequence directly. Only the edge containing
     ;; the requested phase is split; every untouched semantic segment is
     ;; reused exactly. This avoids perturbing stored vertices through repeated
     ;; cumulative-distance subtraction when a phase lies inside one edge.
     (path-geometry
      (list
       (path-subpath-cycle-start-at-distance
        subpath
        (* fraction total-length))))]))

; path-subpath-cycle-start-at-distance : path-subpath? positive-real?
;                                        -> path-subpath?
;;   Rotates one positive-length closed traversal at target-distance.
(define (path-subpath-cycle-start-at-distance subpath target-distance)
  (define edges
    (for/list ([edge (in-list (path-subpath-edges subpath))]
               #:when (positive? (path-edge-length edge)))
      edge))
  (define-values (before selected after local-distance)
    (cycle-edge-location edges target-distance))
  (define selected-length
    (path-edge-length selected))
  (define pieces
    (cond
      [(zero? local-distance)
       (append (map path-edge->piece (cons selected after))
               (map path-edge->piece before))]
      [(= local-distance selected-length)
       (append (map path-edge->piece after)
               (map path-edge->piece before)
               (list (path-edge->piece selected)))]
      [else
       (append
        (list
         (path-edge-partial-piece selected
                                  local-distance
                                  selected-length))
        (map path-edge->piece after)
        (map path-edge->piece before)
        (list
         (path-edge-partial-piece selected
                                  0
                                  local-distance)))]))
  (closed-cycle-pieces->subpath pieces))

; cycle-edge-location : (listof path-edge?) positive-real?
;                       -> (values (listof path-edge?)
;                                  path-edge?
;                                  (listof path-edge?)
;                                  nonnegative-real?)
;;   Locates a cyclic phase while preserving original edge objects and order.
(define (cycle-edge-location edges target-distance)
  (let loop ([before-reversed '()]
             [remaining edges]
             [offset 0])
    (cond
      [(null? remaining)
       (raise-arguments-error
        'path-geometry-cycle-start
        "the cyclic start distance could not be located"
        "target-distance" target-distance)]
      [else
       (define edge
         (car remaining))
       (define edge-length
         (path-edge-length edge))
       (define next-offset
         (+ offset edge-length))
       (if (<= target-distance next-offset)
           (values (reverse before-reversed)
                   edge
                   (cdr remaining)
                   ;; Clamp subtraction noise at exact measured boundaries.
                   (max 0
                        (min edge-length
                             (- target-distance offset))))
           (loop (cons edge before-reversed)
                 (cdr remaining)
                 next-offset))])))

; path-edge->piece : path-edge? -> path-piece?
;;   Reuses one complete measured edge without reconstructing its endpoint.
(define (path-edge->piece edge)
  (path-piece (path-edge-start edge)
              (path-edge-segment edge)))

; closed-cycle-pieces->subpath : (nonempty-listof path-piece?) -> path-subpath?
;;   Converts one complete rotated traversal back to closed path storage.
;;   A final straight edge to the new start is represented by close rather than
;;   by an explicit duplicate edge, matching the canonical polygon form.
(define (closed-cycle-pieces->subpath pieces)
  (define start
    (path-piece-start (car pieces)))
  (define segments
    (map path-piece-segment pieces))
  (define reversed-segments
    (reverse segments))
  (define final-segment
    (car reversed-segments))
  (define canonical-segments
    (if (and (line-path-segment? final-segment)
             (vec2-coordinate=?
              (line-path-segment-end final-segment)
              start))
        (reverse (cdr reversed-segments))
        segments))
  (path-subpath start canonical-segments #t))

; path-geometry-partial-subpaths : path-geometry? real? real?
;                                  -> (listof path-subpath?)
;;   Extracts a distance interval while preserving selected subpath order.
(define (path-geometry-partial-subpaths geometry start-distance end-distance)
  (define-values (reversed-subpaths _offset)
    (for/fold ([reversed-subpaths '()]
               [offset 0])
              ([subpath (in-list (path-geometry-subpaths geometry))])
      (define subpath-length
        (path-subpath-length subpath))
      (define next-offset
        (+ offset subpath-length))
      (define overlap-start
        (max start-distance offset))
      (define overlap-end
        (min end-distance next-offset))
      (define partial-subpath
        (and (< overlap-start overlap-end)
             (path-subpath-partial-by-distance
              subpath
              (- overlap-start offset)
              (- overlap-end offset)
              subpath-length)))
      (values (if partial-subpath
                  (cons partial-subpath reversed-subpaths)
                  reversed-subpaths)
              next-offset)))
  (reverse reversed-subpaths))

; path-subpath-partial-by-distance : path-subpath? real? real? real?
;                                    -> (or/c path-subpath? false/c)
;;   Extracts one positive-length distance interval from subpath.
(define (path-subpath-partial-by-distance subpath
                                          start-distance
                                          end-distance
                                          total-length)
  (cond
    [(and (zero? start-distance)
          (= end-distance total-length))
     subpath]
    [else
     (define pieces
       (path-edges-partial-pieces
        (path-subpath-edges subpath)
        start-distance
        end-distance))
     (and (pair? pieces)
          (path-subpath
           (path-piece-start (car pieces))
           (for/list ([piece (in-list pieces)])
             (path-piece-segment piece))
           #f))]))

; path-edges-partial-pieces : (listof path-edge?) real? real?
;                             -> (listof path-piece?)
;;   Returns positive-length segment pieces for an ordered distance interval.
(define (path-edges-partial-pieces edges start-distance end-distance)
  (define-values (reversed-pieces _offset)
    (for/fold ([reversed-pieces '()]
               [offset 0])
              ([edge (in-list edges)])
      (define edge-length
        (path-edge-length edge))
      (define next-offset
        (+ offset edge-length))
      (define overlap-start
        (max start-distance offset))
      (define overlap-end
        (min end-distance next-offset))
      (values
       (if (or (zero? edge-length)
               (not (< overlap-start overlap-end)))
           reversed-pieces
           (cons
            (path-edge-partial-piece
             edge
             (- overlap-start offset)
             (- overlap-end offset))
            reversed-pieces))
       next-offset)))
  (reverse reversed-pieces))

; path-edge-partial-piece : path-edge? real? real? -> path-piece?
;;   Extracts a positive-length local interval from one edge.
(define (path-edge-partial-piece edge start-distance end-distance)
  (define edge-length
    (path-edge-length edge))
  (define segment
    (path-edge-segment edge))
  (cond
    [(and (zero? start-distance)
          (= end-distance edge-length))
     (path-piece (path-edge-start edge) segment)]
    [(line-path-segment? segment)
     (define start-parameter
       (/ start-distance edge-length))
     (define end-parameter
       (/ end-distance edge-length))
     (path-piece
      (vec2-lerp (path-edge-start edge)
                 (line-path-segment-end segment)
                 start-parameter)
      (line-path-segment
       (vec2-lerp (path-edge-start edge)
                  (line-path-segment-end segment)
                  end-parameter)))]
    [(cubic-bezier-path-segment? segment)
     (define samples
       (path-edge-arc-samples edge))
     (define start-parameter
       (curve-arc-distance->parameter samples start-distance))
     (define end-parameter
       (curve-arc-distance->parameter samples end-distance))
     (define selected
       (cubic-curve-subcurve
        (segment->cubic-curve (path-edge-start edge) segment)
        start-parameter
        end-parameter))
     (path-piece (cubic-curve-start selected)
                 (cubic-curve->segment selected))]
    [else
     (raise-argument-error
      'path-edge-partial-piece
      "supported path segment"
      segment)]))

; path-subpath-edges : path-subpath? -> (listof path-edge?)
;;   Returns explicit directed edges in significant traversal order.
(define (path-subpath-edges subpath)
  (define-values (reversed-edges final-point)
    (for/fold ([reversed-edges '()]
               [current-point (path-subpath-start subpath)])
              ([segment (in-list (path-subpath-segments subpath))])
      (values (cons (make-path-edge current-point segment)
                    reversed-edges)
              (path-segment-end segment))))
  (define open-edges
    (reverse reversed-edges))
  (if (path-subpath-closed? subpath)
      (append open-edges
              (list
               (make-path-edge
                final-point
                (line-path-segment
                 (path-subpath-start subpath)))))
      open-edges))

; make-path-edge : vec2? path-segment? -> path-edge?
;;   Creates a measured traversal edge for one semantic segment.
(define (make-path-edge start segment)
  (cond
    [(line-path-segment? segment)
     (path-edge start
                segment
                (vec2-distance start
                               (line-path-segment-end segment))
                #f)]
    [(cubic-bezier-path-segment? segment)
     (define-values (length samples)
       (cubic-curve-arc-samples
        (segment->cubic-curve start segment)))
     (path-edge start segment length samples)]
    [else
     (raise-argument-error
      'make-path-edge
      "supported path segment"
      segment)]))

; cubic-curve-arc-samples : cubic-curve?
;                           -> (values nonnegative-real?
;                                      (or/c #f
;                                            (listof curve-arc-sample?)))
;;   Builds a deterministic adaptive table for curve length and inversion.
(define (cubic-curve-arc-samples curve)
  (define polygon-length
    (cubic-curve-control-polygon-length curve))
  (cond
    [(not (finite-real? polygon-length))
     (values +inf.0 #f)]
    [else
     (define tolerance
       (max cubic-length-absolute-tolerance
            (* cubic-length-relative-tolerance polygon-length)))
     (define leaves
       (flatten-cubic-curve curve 0 1 tolerance 0))
     (define samples
       (curve-leaves->arc-samples curve leaves))
     (values (curve-arc-sample-distance (car (reverse samples)))
             samples)]))

; flatten-cubic-curve : cubic-curve? finite-real? finite-real?
;                       positive-real? exact-nonnegative-integer?
;                       -> (listof curve-leaf?)
;;   Subdivides curve until each leaf's polygon and chord lengths are close.
(define (flatten-cubic-curve curve
                             start-parameter
                             end-parameter
                             tolerance
                             depth)
  (define polygon-length
    (cubic-curve-control-polygon-length curve))
  (define chord-length
    (vec2-distance (cubic-curve-start curve)
                   (cubic-curve-end curve)))
  (define gap
    (max 0 (- polygon-length chord-length)))
  (cond
    [(or (>= depth cubic-length-maximum-depth)
         (<= gap tolerance))
     (list
      (curve-leaf end-parameter
                  (cubic-curve-end curve)
                  (/ (+ polygon-length chord-length) 2)))]
    [else
     (define midpoint-parameter
       (/ (+ start-parameter end-parameter) 2))
     (define-values (left right)
       (split-cubic-curve curve 1/2))
     (append
      (flatten-cubic-curve left
                           start-parameter
                           midpoint-parameter
                           tolerance
                           (add1 depth))
      (flatten-cubic-curve right
                           midpoint-parameter
                           end-parameter
                           tolerance
                           (add1 depth)))]))

; curve-leaves->arc-samples : cubic-curve? (listof curve-leaf?)
;                             -> (listof curve-arc-sample?)
;;   Converts leaf lengths to an ordered cumulative arc-length table.
(define (curve-leaves->arc-samples curve leaves)
  (define-values (reversed-samples _distance)
    (for/fold ([reversed-samples
                (list (curve-arc-sample
                       0
                       (cubic-curve-start curve)
                       0))]
               [distance 0])
              ([leaf (in-list leaves)])
      (define next-distance
        (+ distance (curve-leaf-length leaf)))
      (values
       (cons (curve-arc-sample
              (curve-leaf-parameter leaf)
              (curve-leaf-point leaf)
              next-distance)
             reversed-samples)
       next-distance)))
  (reverse reversed-samples))

; curve-arc-distance->parameter : (listof curve-arc-sample?) real? [symbol?]
;                                 -> finite-real?
;;   Approximates the parameter at a distance using one arc-length table.
(define (curve-arc-distance->parameter samples distance
                                       [who 'path-geometry-partial])
  (unless (pair? samples)
    (raise-arguments-error
     who
     "a finite cubic curve must have an arc-length table"
     "arc-samples" samples))
  (define total-distance
    (curve-arc-sample-distance (car (reverse samples))))
  (cond
    [(<= distance 0)
     0]
    [(>= distance total-distance)
     1]
    [else
     (let loop ([previous (car samples)]
                [remaining (cdr samples)])
       (define current
         (car remaining))
       (if (<= distance (curve-arc-sample-distance current))
           (let ([interval-length
                  (- (curve-arc-sample-distance current)
                     (curve-arc-sample-distance previous))])
             (if (zero? interval-length)
                 (curve-arc-sample-parameter current)
                 (real-lerp
                  (curve-arc-sample-parameter previous)
                  (curve-arc-sample-parameter current)
                  (/ (- distance
                        (curve-arc-sample-distance previous))
                     interval-length))))
           (loop current (cdr remaining))))]))

; cubic-curve-control-polygon-length : cubic-curve? -> nonnegative-real?
;;   Returns the sum of the three control-polygon edge lengths.
(define (cubic-curve-control-polygon-length curve)
  (+ (vec2-distance (cubic-curve-start curve)
                    (cubic-curve-control1 curve))
     (vec2-distance (cubic-curve-control1 curve)
                    (cubic-curve-control2 curve))
     (vec2-distance (cubic-curve-control2 curve)
                    (cubic-curve-end curve))))

; vec2-distance : vec2? vec2? -> nonnegative-real?
;;   Returns the Euclidean distance between two points without avoidable overflow.
(define (vec2-distance start end)
  (define delta-x
    (abs (- (vec2-x end)
            (vec2-x start))))
  (define delta-y
    (abs (- (vec2-y end)
            (vec2-y start))))
  (define scale
    (max delta-x delta-y))
  (cond
    [(zero? scale)
     0]
    [(not (finite-real? scale))
     +inf.0]
    [else
     (define normalized-x
       (/ delta-x scale))
     (define normalized-y
       (/ delta-y scale))
     (* scale
        (sqrt (+ (* normalized-x normalized-x)
                 (* normalized-y normalized-y))))]))

; check-path-fraction : symbol? string? any/c -> void?
;;   Raises an argument error unless value lies in the closed unit interval.
(define (check-path-fraction who field-name value)
  (unless (and (finite-real? value)
               (<= 0 value 1))
    (raise-arguments-error
     who
     "path fractions must be finite reals in the closed unit interval"
     field-name value)))


;;;
;;; Path Construction
;;;

; polyline-path : (listof vec2?) -> path-geometry?
;;   Creates one open straight-segment subpath from at least two points.
(define (polyline-path points)
  (check-point-list 'polyline-path points 2)
  (path-geometry
   (list (points->path-subpath points #f))))

; polygon-path : (listof vec2?) -> path-geometry?
;;   Creates one closed straight-segment subpath from at least three points.
(define (polygon-path points)
  (check-point-list 'polygon-path points 3)
  (path-geometry
   (list (points->path-subpath points #t))))

; cubic-bezier-path : vec2? (listof cubic-bezier-path-segment?)
;                     [#:closed? boolean?]
;                     -> path-geometry?
;;   Creates one subpath from a start point and ordered cubic segments.
(define (cubic-bezier-path start segments #:closed? [closed? #f])
  (unless (vec2? start)
    (raise-argument-error 'cubic-bezier-path "vec2?" start))
  (unless (and (pair? segments)
               (list? segments)
               (andmap cubic-bezier-path-segment? segments))
    (raise-argument-error
     'cubic-bezier-path
     "nonempty list of cubic-bezier-path-segment values"
     segments))
  (unless (boolean? closed?)
    (raise-argument-error 'cubic-bezier-path "boolean?" closed?))
  (path-geometry
   (list (path-subpath start segments closed?))))

; points->path-subpath : (listof vec2?) boolean? -> path-subpath?
;;   Converts a validated point list to one straight-segment subpath.
(define (points->path-subpath points closed?)
  (path-subpath
   (car points)
   (for/list ([point (in-list (cdr points))])
     (line-path-segment point))
   closed?))


;;;
;;; Validation
;;;

; check-path-geometry : symbol? any/c -> void?
;;   Raises an argument error unless value is path geometry.
(define (check-path-geometry who value)
  (unless (path-geometry? value)
    (raise-argument-error who "path-geometry?" value)))

; check-path-subpath : symbol? any/c -> void?
;;   Raises an argument error unless value is a path subpath.
(define (check-path-subpath who value)
  (unless (path-subpath? value)
    (raise-argument-error who "path-subpath?" value)))

; check-point-list : symbol? any/c exact-positive-integer? -> void?
;;   Raises an argument error unless points is a long-enough vec2 list.
(define (check-point-list who points minimum-count)
  (unless (and (list? points)
               (andmap vec2? points)
               (>= (length points) minimum-count))
    (raise-arguments-error
     who
     "expected an ordered list containing enough vec2 points"
     "minimum point count" minimum-count
     "points" points)))
