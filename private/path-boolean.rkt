#lang racket/base

;;;
;;; SCENE-DY: General Boolean Path Geometry
;;;

;; Boolean operations are performed on a renderer-independent, polygonal
;; approximation of closed path contours. Each contour is checked for self
;; intersections and decomposed deterministically into convex triangles. The
;; public operations consequently support concave and compound paths while the
;; clipping kernel remains a small convex Sutherland-Hodgman implementation.
;;
;; The result is reconstructed from the boundary of its disjoint partition.
;; That prevents the internal triangulation from appearing as stroked seams.
;; Opposite-winding boundary loops represent holes and work with the existing
;; odd-even path renderer.

(require racket/list
         (only-in racket/math pi)
         "clipped-visual.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

(provide path-union
         path-intersection
         path-difference
         path-xor
         cutout
         clip-to
         mask-with)


;;;
;;; Public operations
;;;

;; The Pict/SVG path renderers use odd-even filling, so it is the default. The
;; nonzero mode lets deliberately oriented, nested contours encode holes. It
;; currently requires those contour boundaries not to cross.

(define (path-union first second
                    #:curve-samples [curve-samples 16]
                    #:fill-rule [fill-rule 'odd-even])
  (define-values (first-pieces second-pieces)
    (boolean-operands 'path-union first second curve-samples fill-rule))
  (pieces->geometry (pieces-union first-pieces second-pieces)))

(define (path-intersection first second
                           #:curve-samples [curve-samples 16]
                           #:fill-rule [fill-rule 'odd-even])
  (define-values (first-pieces second-pieces)
    (boolean-operands 'path-intersection first second curve-samples fill-rule))
  (pieces->geometry (pieces-intersection first-pieces second-pieces)))

(define (path-difference first second
                        #:curve-samples [curve-samples 16]
                        #:fill-rule [fill-rule 'odd-even])
  (define-values (first-pieces second-pieces)
    (boolean-operands 'path-difference first second curve-samples fill-rule))
  (pieces->geometry (pieces-difference first-pieces second-pieces)))

(define (path-xor first second
                  #:curve-samples [curve-samples 16]
                  #:fill-rule [fill-rule 'odd-even])
  (define-values (first-pieces second-pieces)
    (boolean-operands 'path-xor first second curve-samples fill-rule))
  (pieces->geometry (pieces-xor first-pieces second-pieces)))

(define (cutout outer inner
                #:curve-samples [curve-samples 16]
                #:fill-rule [fill-rule 'odd-even])
  (path-difference outer inner
                   #:curve-samples curve-samples
                   #:fill-rule fill-rule))

;; Geometric clipping and masking have the same binary region semantics: only
;; subject material covered by the clip/mask remains. Paint-aware visual masks
;; will build on this operation in SCENE-EC.
(define (clip-to subject clip
                 #:id [id #f]
                 #:center [center origin]
                 #:rotation [rotation 0]
                 #:scale [scale 1]
                 #:opacity [opacity 1]
                 #:curve-samples [curve-samples 16]
                 #:fill-rule [fill-rule 'odd-even])
  (cond [(and (path-geometry? subject) (path-geometry? clip))
         (path-intersection subject clip
                            #:curve-samples curve-samples
                            #:fill-rule fill-rule)]
        [(and (visual? subject) (affine-visual? subject)
              (path-geometry? clip))
         (clip-visual subject clip
                      #:id (or id (derived-clip-id subject 'clip))
                      #:center center #:rotation rotation #:scale scale
                      #:opacity opacity)]
        [else
         (raise-arguments-error
          'clip-to
          "expected two path geometries, or an affine Visual and a path geometry"
          "subject" subject "clip" clip)]))

(define (mask-with subject mask
                   #:id [id #f]
                   #:center [center origin]
                   #:rotation [rotation 0]
                   #:scale [scale 1]
                   #:opacity [opacity 1]
                   #:curve-samples [curve-samples 16]
                   #:fill-rule [fill-rule 'odd-even])
  (cond [(and (path-geometry? subject) (path-geometry? mask))
         (path-intersection subject mask
                            #:curve-samples curve-samples
                            #:fill-rule fill-rule)]
        [(and (visual? subject) (affine-visual? subject)
              (path-geometry? mask))
         (clip-visual subject mask
                      #:id (or id (derived-clip-id subject 'mask))
                      #:center center #:rotation rotation #:scale scale
                      #:opacity opacity)]
        [else
         (raise-arguments-error
          'mask-with
          "expected two path geometries, or an affine Visual and a path geometry"
          "subject" subject "mask" mask)]))

(define (derived-clip-id visual kind)
  (string->symbol (format "~a-~a" (visual-id visual) kind)))


;;;
;;; Operand preparation and fill rules
;;;

(define numerical-epsilon 1e-9)

(define (boolean-operands who first second curve-samples fill-rule)
  (values (geometry->filled-pieces who "first" first curve-samples fill-rule)
          (geometry->filled-pieces who "second" second curve-samples fill-rule)))

(define (geometry->filled-pieces who field geometry curve-samples fill-rule)
  (check-path-geometry who field geometry)
  (check-curve-samples who curve-samples)
  (check-fill-rule who fill-rule)
  (define subpaths (path-geometry-subpaths geometry))
  (when (ormap (lambda (subpath) (not (path-subpath-closed? subpath))) subpaths)
    (raise-arguments-error who
                           "Boolean operands must contain only closed subpaths"
                           field geometry))
  (define polygons
    (append-map
     (lambda (subpath)
       (subpath->polygons who field subpath curve-samples fill-rule))
     subpaths))
  (case fill-rule
    [(odd-even)
     ;; XORing contours is exactly the renderer's even-odd interpretation.
     (for/fold ([pieces '()]) ([polygon (in-list polygons)])
       (pieces-xor pieces (polygon->triangles polygon)))]
    [(nonzero) (nonzero-pieces who field polygons)]))

(define (check-path-geometry who field value)
  (unless (path-geometry? value)
    (raise-arguments-error who "expected path geometry" field value)))

(define (check-curve-samples who value)
  (unless (and (exact-integer? value) (positive? value))
    (raise-arguments-error who
                           "curve-samples must be an exact positive integer"
                           "curve-samples" value)))

(define (check-fill-rule who value)
  (unless (memq value '(odd-even nonzero))
    (raise-arguments-error who
                           "fill-rule must be 'odd-even or 'nonzero"
                           "fill-rule" value)))

(define (subpath->polygons who field subpath curve-samples fill-rule)
  (define polygon
    (normalize-polygon (subpath->sampled-points subpath curve-samples)))
  (unless (>= (length polygon) 3)
    (raise-arguments-error who
                           "each closed contour must have at least three distinct points"
                           field subpath))
  (cond [(simple-polygon? polygon)
         (unless (polygon-has-area? polygon)
           (raise-arguments-error who
                                  "each closed contour must enclose a nonzero area"
                                  field subpath))
         (list polygon)]
        [(eq? fill-rule 'odd-even)
         (polygonize-even-odd-contour who field polygon)]
        [else
         (raise-arguments-error
          who
          "nonzero filling does not yet repair a self-intersecting contour; split it into simple closed subpaths"
          field subpath)]))

(define (subpath->sampled-points subpath curve-samples)
  (define-values (reverse-points _last-point)
    (for/fold ([reverse-points (list (path-subpath-start subpath))]
               [current-point (path-subpath-start subpath)])
              ([segment (in-list (path-subpath-segments subpath))])
      (define segment-points
        (cond [(line-path-segment? segment)
               (list (line-path-segment-end segment))]
              [(cubic-bezier-path-segment? segment)
               (for/list ([index (in-range 1 (add1 curve-samples))])
                 (cubic-point current-point segment (/ index curve-samples)))]))
      (values (append (reverse segment-points) reverse-points)
              (segment-end-point segment))))
  (reverse reverse-points))

(define (segment-end-point segment)
  (cond [(line-path-segment? segment) (line-path-segment-end segment)]
        [(cubic-bezier-path-segment? segment)
         (cubic-bezier-path-segment-end segment)]))

(define (cubic-point start segment progress)
  (define complement (- 1 progress))
  (define (blend selector)
    (+ (* complement complement complement (selector start))
       (* 3 complement complement progress
          (selector (cubic-bezier-path-segment-control1 segment)))
       (* 3 complement progress progress
          (selector (cubic-bezier-path-segment-control2 segment)))
       (* progress progress progress
          (selector (cubic-bezier-path-segment-end segment)))))
  (vec2 (blend vec2-x) (blend vec2-y)))

;; Repair an even-odd self crossing by building the planar arrangement induced
;; by its segments.  Each proper crossing splits both source edges; walking
;; half-edges then yields every bounded face. A face is kept precisely when a
;; point in it has odd parity in the original contour. This handles familiar
;; bow ties and multi-loop scribbles without introducing a mutable clipping
;; backend. Touching or overlapping segments are deliberately not repaired:
;; they have ambiguous zero-area topology and should be supplied as separate
;; simple contours instead.
(define (polygonize-even-odd-contour who field polygon)
  (define source-edges (polygon->edges polygon))
  (define intersections-by-edge
    (for/vector ([edge (in-list source-edges)])
      (list (directed-edge-start edge) (directed-edge-end edge))))
  (for* ([first-index (in-range (length source-edges))]
         [second-index (in-range (add1 first-index) (length source-edges))]
         #:unless (adjacent-edge-indices? first-index second-index
                                         (length source-edges)))
    (define first-edge (list-ref source-edges first-index))
    (define second-edge (list-ref source-edges second-index))
    (when (segments-intersect? (directed-edge-start first-edge)
                              (directed-edge-end first-edge)
                              (directed-edge-start second-edge)
                              (directed-edge-end second-edge))
      (define crossing
        (proper-segment-intersection first-edge second-edge))
      (unless crossing
        (raise-arguments-error
         who
         "self-touching or overlapping contours cannot be repaired; use simple contours that meet only at proper crossings"
         field polygon))
      (vector-set! intersections-by-edge first-index
                   (cons crossing (vector-ref intersections-by-edge first-index)))
      (vector-set! intersections-by-edge second-index
                   (cons crossing (vector-ref intersections-by-edge second-index)))))
  (define atomic-edges
    (append-map
     (lambda (index)
       (split-edge-at-points (list-ref source-edges index)
                             (vector-ref intersections-by-edge index)))
     (range (length source-edges))))
  (define half-edges
    (append atomic-edges
            (map (lambda (edge)
                   (directed-edge (directed-edge-end edge)
                                  (directed-edge-start edge)))
                 atomic-edges)))
  (define faces (arrangement-faces who field half-edges))
  (define selected
    (filter (lambda (face)
              (and (positive? (polygon-signed-area face))
                   (point-in-polygon? (point-in-face face) polygon)))
            faces))
  (unless (pair? selected)
    (raise-arguments-error who
                           "the self-intersecting contour has no odd-even filled face"
                           field polygon))
  selected)

(define (proper-segment-intersection first-edge second-edge)
  (define start (directed-edge-start first-edge))
  (define direction (vec2- (directed-edge-end first-edge) start))
  (define clip-start (directed-edge-start second-edge))
  (define clip-direction
    (vec2- (directed-edge-end second-edge) clip-start))
  (define denominator (cross-product direction clip-direction))
  (cond [(near-zero? denominator) #f]
        [else
         (define progress
           (/ (cross-product (vec2- clip-start start) clip-direction)
              denominator))
         (define clip-progress
           (/ (cross-product (vec2- clip-start start) direction)
              denominator))
         (and (> progress numerical-epsilon)
              (< progress (- 1 numerical-epsilon))
              (> clip-progress numerical-epsilon)
              (< clip-progress (- 1 numerical-epsilon))
              (vec2+ start (vec2-scale progress direction)))]))

(define (arrangement-faces who field half-edges)
  (let loop ([remaining half-edges] [reverse-faces '()])
    (cond [(null? remaining) (reverse reverse-faces)]
          [else
           (define initial (car remaining))
           (define-values (face unused)
             (walk-arrangement-face who field initial half-edges (cdr remaining)))
           (loop unused
                 (if (polygon-has-area? face)
                     (cons face reverse-faces)
                     reverse-faces))])))

(define (walk-arrangement-face who field initial all-half-edges remaining)
  (define start (directed-edge-start initial))
  (let loop ([current initial]
             [reverse-points (list start)]
             [unused remaining]
             [fuel (add1 (length all-half-edges))])
    (define current-end (directed-edge-end current))
    (define next-edge
      (next-left-face-edge current all-half-edges))
    (cond [(and (points-close? current-end start) (equal? next-edge initial))
           (values (normalize-polygon (reverse reverse-points)) unused)]
          [(zero? fuel)
           (raise-arguments-error who
                                  "could not reconstruct a self-intersection face"
                                  field initial)]
          [(not (member next-edge unused))
           (raise-arguments-error who
                                  "self-intersection faces overlap unexpectedly"
                                  field initial)]
          [else
           (loop next-edge
                 (cons current-end reverse-points)
                 (remove next-edge unused)
                 (sub1 fuel))])))

;; For a directed edge u→v, the face on its left leaves v by taking the first
;; non-backtracking outgoing half-edge clockwise from v→u.
(define (next-left-face-edge edge half-edges)
  (define vertex (directed-edge-end edge))
  (define reverse-direction
    (vec2- (directed-edge-start edge) vertex))
  (define candidates
    (filter (lambda (candidate)
              (and (points-close? (directed-edge-start candidate) vertex)
                   (not (points-close? (directed-edge-end candidate)
                                       (directed-edge-start edge)))))
            half-edges))
  (and (pair? candidates)
       (argmin (lambda (candidate)
                 (clockwise-turn
                  reverse-direction
                  (vec2- (directed-edge-end candidate) vertex)))
               candidates)))

(define (clockwise-turn first second)
  (define signed-angle
    (atan (cross-product first second)
          (+ (* (vec2-x first) (vec2-x second))
             (* (vec2-y first) (vec2-y second)))))
  (if (positive? signed-angle)
      (- (* 2 pi) signed-angle)
      (- signed-angle)))

(define (point-in-face face)
  ;; An ear's barycentre is guaranteed to lie in the simple face, unlike the
  ;; ordinary polygon centroid which can lie outside a concave face.
  (define ear (car (polygon->triangles face)))
  (vec2 (/ (+ (vec2-x (first ear))
              (vec2-x (second ear))
              (vec2-x (third ear)))
           3)
        (/ (+ (vec2-y (first ear))
              (vec2-y (second ear))
              (vec2-y (third ear)))
           3)))

;; Build the nonzero-filled region by following the winding number through a
;; nesting tree. This is complete for the ordinary compound-path case (outer
;; contour, holes, islands); crossing contours require an arrangement solver.
(define (nonzero-pieces who field polygons)
  (when (polygons-have-crossing-boundaries? polygons)
    (raise-arguments-error
     who
     "the nonzero fill rule currently requires nonintersecting contour boundaries; use 'odd-even for overlapping contours"
     field polygons))
  (define ordered
    (sort polygons > #:key (lambda (polygon) (abs (polygon-signed-area polygon)))))
  (define-values (result _records)
    (for/fold ([pieces '()] [records '()]) ([polygon (in-list ordered)])
      (define parent (smallest-containing-record records (car polygon)))
      (define prior-winding (if parent (second parent) 0))
      (define orientation
        (if (positive? (polygon-signed-area polygon)) 1 -1))
      (define next-winding (+ prior-winding orientation))
      (define triangle-pieces (polygon->triangles polygon))
      (define next-pieces
        (cond [(and (zero? prior-winding) (not (zero? next-winding)))
               (pieces-union pieces triangle-pieces)]
              [(and (not (zero? prior-winding)) (zero? next-winding))
               (pieces-difference pieces triangle-pieces)]
              [else pieces]))
      (values next-pieces (cons (list polygon next-winding) records))))
  result)

(define (smallest-containing-record records point)
  (for/fold ([best #f]) ([record (in-list records)]
                            #:when (point-in-polygon? point (first record)))
    (if (or (not best)
            (< (abs (polygon-signed-area (first record)))
               (abs (polygon-signed-area (first best)))))
        record
        best)))


;;;
;;; General region operations on disjoint convex pieces
;;;

(define (pieces-union first second)
  (append first (pieces-difference second first)))

(define (pieces-intersection first second)
  (append-map
   (lambda (subject)
     (filter polygon-has-area?
             (for/list ([clip (in-list second)])
               (convex-intersection subject clip))))
   first))

(define (pieces-difference first second)
  (for/fold ([pieces first]) ([clip (in-list second)])
    (append-map (lambda (subject) (convex-difference subject clip)) pieces)))

(define (pieces-xor first second)
  (append (pieces-difference first second)
          (pieces-difference second first)))

;; Deterministic ear clipping. The preparatory simplicity check and removal of
;; collinear vertices mean failure is an explicit numerical-degeneracy error.
(define (polygon->triangles polygon)
  (define ccw-polygon
    (if (negative? (polygon-signed-area polygon)) (reverse polygon) polygon))
  (let loop ([vertices ccw-polygon] [reverse-triangles '()])
    (cond [(= (length vertices) 3)
           (reverse (cons vertices reverse-triangles))]
          [else
           (define ear-index (find-ear-index vertices))
           (unless ear-index
             (raise-arguments-error
              'path-boolean
              "could not triangulate a simple contour; the contour is numerically degenerate"
              "contour" polygon))
           (define previous
             (list-ref vertices (modulo (sub1 ear-index) (length vertices))))
           (define point (list-ref vertices ear-index))
           (define next
             (list-ref vertices (modulo (add1 ear-index) (length vertices))))
           (loop (remove-at vertices ear-index)
                 (cons (list previous point next) reverse-triangles))])))

(define (find-ear-index vertices)
  (for/or ([index (in-range (length vertices))])
    (define previous (list-ref vertices (modulo (sub1 index) (length vertices))))
    (define point (list-ref vertices index))
    (define next (list-ref vertices (modulo (add1 index) (length vertices))))
    (and (> (cross-product (vec2- point previous) (vec2- next point))
            numerical-epsilon)
         (not (for/or ([other-index (in-range (length vertices))]
                       #:unless (or (= other-index index)
                                    (= other-index (modulo (sub1 index)
                                                            (length vertices)))
                                    (= other-index (modulo (add1 index)
                                                            (length vertices)))))
                (point-in-triangle? (list-ref vertices other-index)
                                    previous point next)))
         index)))

(define (remove-at values index)
  (append (take values index) (drop values (add1 index))))

(define (point-in-triangle? point first second third)
  (and (>= (cross-product (vec2- second first) (vec2- point first))
           (- numerical-epsilon))
       (>= (cross-product (vec2- third second) (vec2- point second))
           (- numerical-epsilon))
       (>= (cross-product (vec2- first third) (vec2- point third))
           (- numerical-epsilon))))


;;;
;;; Convex clipping kernel
;;;

(define (convex-intersection subject clip)
  (for/fold ([result subject])
            ([edge-start (in-list clip)]
             [edge-end (in-list (polygon-next-points clip))])
    (if (null? result)
        '()
        (clip-polygon result edge-start edge-end #t))))

(define (convex-difference subject clip)
  (define-values (_inside result)
    (for/fold ([inside-pieces (list subject)] [outside-pieces '()])
              ([edge-start (in-list clip)]
               [edge-end (in-list (polygon-next-points clip))])
      (define next-inside
        (append-map
         (lambda (polygon)
           (filter polygon-has-area?
                   (list (clip-polygon polygon edge-start edge-end #t))))
         inside-pieces))
      (define new-outside
        (append-map
         (lambda (polygon)
           (filter polygon-has-area?
                   (list (clip-polygon polygon edge-start edge-end #f))))
         inside-pieces))
      (values next-inside (append outside-pieces new-outside))))
  result)

(define (clip-polygon polygon edge-start edge-end keep-left?)
  (cond [(null? polygon) '()]
        [else
         (define previous (last-point polygon))
         (define previous-inside?
           (edge-inside? edge-start edge-end previous keep-left?))
         (define-values (reverse-result _final-point _final-inside?)
           (for/fold ([reverse-result '()]
                      [previous previous]
                      [previous-inside? previous-inside?])
                     ([current (in-list polygon)])
             (define current-inside?
               (edge-inside? edge-start edge-end current keep-left?))
             (define additions
               (cond [(and previous-inside? current-inside?) (list current)]
                     [(and previous-inside? (not current-inside?))
                      (list (segment-edge-intersection previous current
                                                       edge-start edge-end))]
                     [(and (not previous-inside?) current-inside?)
                      (list (segment-edge-intersection previous current
                                                       edge-start edge-end)
                            current)]
                     [else '()]))
             (values (append (reverse additions) reverse-result)
                     current current-inside?)))
         (normalize-polygon (reverse reverse-result))]))

(define (edge-inside? edge-start edge-end point keep-left?)
  (define side
    (cross-product (vec2- edge-end edge-start) (vec2- point edge-start)))
  (if keep-left?
      (>= side (- numerical-epsilon))
      (<= side numerical-epsilon)))

(define (segment-edge-intersection segment-start segment-end edge-start edge-end)
  (define direction (vec2- segment-end segment-start))
  (define edge-direction (vec2- edge-end edge-start))
  (define denominator (cross-product direction edge-direction))
  (if (near-zero? denominator)
      segment-end
      (vec2+ segment-start
             (vec2-scale
              (/ (cross-product (vec2- edge-start segment-start) edge-direction)
                 denominator)
              direction))))


;;;
;;; Exterior reconstruction
;;;

(struct directed-edge (start end) #:transparent)

(define (pieces->geometry pieces)
  (path-geometry
   (for/list ([polygon (in-list (boundary-loops pieces))])
     (path-subpath (car polygon)
                   (for/list ([point (in-list (cdr polygon))])
                     (line-path-segment point))
                   #t))))

(define (boundary-loops pieces)
  (define edges
    (append-map polygon->edges (filter polygon-has-area? pieces)))
  (define points
    (deduplicate-points
     (append-map (lambda (edge)
                   (list (directed-edge-start edge) (directed-edge-end edge)))
                 edges)))
  (define atomic-edges
    (append-map (lambda (edge) (split-edge-at-points edge points)) edges))
  (stitch-boundary-edges (cancel-opposite-edges atomic-edges)))

(define (polygon->edges polygon)
  (for/list ([start (in-list polygon)]
             [end (in-list (polygon-next-points polygon))])
    (directed-edge start end)))

(define (split-edge-at-points edge points)
  (define start (directed-edge-start edge))
  (define end (directed-edge-end edge))
  (define direction (vec2- end start))
  (define length-squared
    (+ (* (vec2-x direction) (vec2-x direction))
       (* (vec2-y direction) (vec2-y direction))))
  (define ordered
    (sort (deduplicate-points
           (filter (lambda (point) (point-on-segment? point start end)) points))
          <
          #:key (lambda (point)
                  (/ (+ (* (- (vec2-x point) (vec2-x start)) (vec2-x direction))
                        (* (- (vec2-y point) (vec2-y start)) (vec2-y direction)))
                     length-squared))))
  (for/list ([first (in-list ordered)] [second (in-list (cdr ordered))]
             #:unless (points-close? first second))
    (directed-edge first second)))

(define (cancel-opposite-edges edges)
  (for/fold ([remaining '()]) ([edge (in-list edges)])
    (define opposite
      (for/first ([candidate (in-list remaining)]
                  #:when (and (points-close? (directed-edge-start edge)
                                      (directed-edge-end candidate))
                              (points-close? (directed-edge-end edge)
                                      (directed-edge-start candidate))))
        candidate))
    (if opposite (remove opposite remaining) (cons edge remaining))))

(define (stitch-boundary-edges edges)
  (let loop ([remaining edges] [reverse-loops '()])
    (cond [(null? remaining) (reverse reverse-loops)]
          [else
           (define initial (car remaining))
           (define-values (loop-points after-loop)
             (stitch-one-loop initial (cdr remaining)))
           (loop after-loop
                 (if (polygon-has-area? loop-points)
                     (cons loop-points reverse-loops)
                     reverse-loops))])))

(define (stitch-one-loop initial remaining)
  (define start (directed-edge-start initial))
  (let loop ([current (directed-edge-end initial)]
             [reverse-points (list (directed-edge-end initial)
                                   (directed-edge-start initial))]
             [unused remaining]
             [fuel (add1 (length remaining))])
    (cond [(points-close? current start)
           (values (normalize-polygon (reverse reverse-points)) unused)]
          [(zero? fuel)
           (raise-arguments-error
            'path-boolean "could not reconstruct a closed Boolean boundary"
            "edge" initial)]
          [else
           (define next-edge
             (for/first ([edge (in-list unused)]
                         #:when (points-close? (directed-edge-start edge) current))
               edge))
           (unless next-edge
             (raise-arguments-error
              'path-boolean "Boolean boundary has an unpaired edge"
              "edge" initial))
           (loop (directed-edge-end next-edge)
                 (cons (directed-edge-end next-edge) reverse-points)
                 (remove next-edge unused)
                 (sub1 fuel))])))


;;;
;;; Polygon helpers and validation
;;;

(define (normalize-polygon points)
  (define deduplicated
    (let loop ([remaining points] [reverse-result '()])
      (cond [(null? remaining) (reverse reverse-result)]
            [(and (pair? reverse-result)
                  (points-close? (car remaining) (car reverse-result)))
             (loop (cdr remaining) reverse-result)]
            [else (loop (cdr remaining) (cons (car remaining) reverse-result))])))
  (define unclosed
    (if (and (pair? deduplicated)
             (points-close? (car deduplicated) (last-point deduplicated)))
        (drop-last-point deduplicated)
        deduplicated))
  (let remove-collinear ([polygon unclosed])
    (cond [(< (length polygon) 3) polygon]
          [else
           (define filtered
             (for/list ([previous (in-list (cons (last-point polygon)
                                                  (drop-last-point polygon)))]
                        [point (in-list polygon)]
                        [next (in-list (polygon-next-points polygon))]
                        #:unless (and (near-zero?
                                       (cross-product (vec2- point previous)
                                                      (vec2- next point)))
                                      (point-on-segment? point previous next)))
               point))
           (if (= (length filtered) (length polygon))
               filtered
               (remove-collinear filtered))])))

(define (polygon-has-area? polygon)
  (and (>= (length polygon) 3)
       (not (near-zero? (polygon-signed-area polygon)))))

(define (polygon-signed-area polygon)
  (/ (for/sum ([point (in-list polygon)]
               [next-point (in-list (polygon-next-points polygon))])
       (- (* (vec2-x point) (vec2-y next-point))
          (* (vec2-y point) (vec2-x next-point))))
     2))

(define (polygon-next-points polygon)
  (if (null? polygon) '() (append (cdr polygon) (list (car polygon)))))

(define (simple-polygon? polygon)
  (and (polygon-has-area? polygon)
       (for*/and ([first-index (in-range (length polygon))]
                  [second-index (in-range (add1 first-index) (length polygon))])
         (or (adjacent-edge-indices? first-index second-index (length polygon))
             (not (segments-intersect?
                   (list-ref polygon first-index)
                   (list-ref polygon (modulo (add1 first-index) (length polygon)))
                   (list-ref polygon second-index)
                   (list-ref polygon (modulo (add1 second-index) (length polygon)))))))))

(define (adjacent-edge-indices? first second count)
  (or (= (add1 first) second)
      (and (zero? first) (= second (sub1 count)))))

(define (polygons-have-crossing-boundaries? polygons)
  (for/or ([first (in-list polygons)] [first-index (in-naturals)])
    (for/or ([second (in-list polygons)] [second-index (in-naturals)]
             #:when (< first-index second-index))
      (polygons-boundaries-intersect? first second))))

(define (polygons-boundaries-intersect? first second)
  (for/or ([first-start (in-list first)]
           [first-end (in-list (polygon-next-points first))])
    (for/or ([second-start (in-list second)]
             [second-end (in-list (polygon-next-points second))])
      (segments-intersect? first-start first-end second-start second-end))))

(define (segments-intersect? first-start first-end second-start second-end)
  (define first-side-start
    (cross-product (vec2- first-end first-start) (vec2- second-start first-start)))
  (define first-side-end
    (cross-product (vec2- first-end first-start) (vec2- second-end first-start)))
  (define second-side-start
    (cross-product (vec2- second-end second-start) (vec2- first-start second-start)))
  (define second-side-end
    (cross-product (vec2- second-end second-start) (vec2- first-end second-start)))
  (and (<= (* first-side-start first-side-end) numerical-epsilon)
       (<= (* second-side-start second-side-end) numerical-epsilon)
       (bounding-boxes-overlap? first-start first-end second-start second-end)))

(define (bounding-boxes-overlap? first-start first-end second-start second-end)
  (and (<= (- (min (vec2-x first-start) (vec2-x first-end)) numerical-epsilon)
           (+ (max (vec2-x second-start) (vec2-x second-end)) numerical-epsilon))
       (<= (- (min (vec2-x second-start) (vec2-x second-end)) numerical-epsilon)
           (+ (max (vec2-x first-start) (vec2-x first-end)) numerical-epsilon))
       (<= (- (min (vec2-y first-start) (vec2-y first-end)) numerical-epsilon)
           (+ (max (vec2-y second-start) (vec2-y second-end)) numerical-epsilon))
       (<= (- (min (vec2-y second-start) (vec2-y second-end)) numerical-epsilon)
           (+ (max (vec2-y first-start) (vec2-y first-end)) numerical-epsilon))))

(define (point-in-polygon? point polygon)
  (odd? (for/sum ([first (in-list polygon)]
                  [second (in-list (polygon-next-points polygon))])
          (if (and (not (eq? (> (vec2-y first) (vec2-y point))
                              (> (vec2-y second) (vec2-y point))))
                   (< (vec2-x point)
                      (+ (vec2-x first)
                         (* (/ (- (vec2-y point) (vec2-y first))
                               (- (vec2-y second) (vec2-y first)))
                            (- (vec2-x second) (vec2-x first))))))
              1 0))))

(define (point-on-segment? point start end)
  (and (near-zero? (cross-product (vec2- end start) (vec2- point start)))
       (<= (- (min (vec2-x start) (vec2-x end)) numerical-epsilon)
           (vec2-x point)
           (+ (max (vec2-x start) (vec2-x end)) numerical-epsilon))
       (<= (- (min (vec2-y start) (vec2-y end)) numerical-epsilon)
           (vec2-y point)
           (+ (max (vec2-y start) (vec2-y end)) numerical-epsilon))))

(define (deduplicate-points points)
  (reverse
   (for/fold ([result '()]) ([point (in-list points)])
     (if (ormap (lambda (previous) (points-close? point previous)) result)
         result
         (cons point result)))))

(define (drop-last-point points) (reverse (cdr (reverse points))))

(define (points-close? first second)
  (and (near-zero? (- (vec2-x first) (vec2-x second)))
       (near-zero? (- (vec2-y first) (vec2-y second)))))

(define (near-zero? value) (<= (abs value) numerical-epsilon))

(define (cross-product first second)
  (- (* (vec2-x first) (vec2-y second))
     (* (vec2-y first) (vec2-x second))))

(define (last-point points) (car (reverse points)))
