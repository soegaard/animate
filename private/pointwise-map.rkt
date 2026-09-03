#lang racket/base

;;;
;;; Pointwise World-Space Maps
;;;

;; Turns geometric leaves of an ordinary Visual tree into sampled paths in
;; world coordinates, then applies a point map to every sample. Sampling before
;; mapping is intentional: mapping only Bézier control points would leave a
;; straight grid line straight under, for example, z -> z^2.

(require racket/list
         racket/math
         "affine-map-visual.rkt"
         "affine-transform.rkt"
         "arrow-visual.rkt"
         "axes-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

(provide pointwise-map-visual
         pointwise-jacobian
         pointwise-jacobian-determinant
         pointwise-orientation
         inverse-map-mesh)

;; pointwise-map-visual : visual? (-> vec2? vec2?) finite-real?
;;                        [#:samples exact-positive-integer?]
;;                        [#:adaptive? boolean?]
;;                        [#:tolerance positive-finite-real?]
;;                        [#:max-depth exact-nonnegative-integer?]
;;                        [#:discontinuities (or/c 'split 'error)] -> visual?
;; Produces an ordinary world-coordinate Visual tree. Path, circle, and
;; rectangle leaves are sampled and point-mapped; other affine leaves remain
;; legible and retain their original world placement. Progress is an explicit
;; straight-line blend between each source point and its mapped point.
(define (pointwise-map-visual visual map-point progress
                              #:samples [samples 24]
                              #:adaptive? [adaptive? #t]
                              #:tolerance [tolerance 1/32]
                              #:max-depth [max-depth 8]
                              #:discontinuities [discontinuity-mode 'split])
  (unless (visual? visual)
    (raise-argument-error 'pointwise-map-visual "visual?" visual))
  (check-point-map 'pointwise-map-visual map-point)
  (unless (and (finite-real? progress) (<= 0 progress 1))
    (raise-argument-error 'pointwise-map-visual
                          "finite real in the closed interval [0, 1]"
                          progress))
  (unless (and (exact-integer? samples) (positive? samples))
    (raise-argument-error 'pointwise-map-visual "positive exact integer" samples))
  (unless (boolean? adaptive?)
    (raise-argument-error 'pointwise-map-visual "boolean?" adaptive?))
  (check-positive-finite-real 'pointwise-map-visual "tolerance" tolerance)
  (unless (and (exact-integer? max-depth) (not (negative? max-depth)))
    (raise-argument-error
     'pointwise-map-visual "exact nonnegative integer" max-depth))
  (unless (memq discontinuity-mode '(split error))
    (raise-argument-error
     'pointwise-map-visual "(or/c 'split 'error)" discontinuity-mode))
  (map-visual-tree visual map-point progress samples adaptive? tolerance max-depth
                   discontinuity-mode identity-affine2 1))

(define (map-visual-tree visual map-point progress samples adaptive? tolerance max-depth
                         discontinuity-mode parent-map parent-opacity)
  (unless (affine-visual? visual)
    (raise-arguments-error 'apply-pointwise "an affine Visual tree" "visual" visual))
  (define-values (content local-map wrapper-opacity)
    (affine-map-visual-content+map visual))
  (define world-map
    (affine2-compose parent-map local-map))
  (define world-opacity
    (* parent-opacity
       (if (affine-map-visual? visual)
           (* wrapper-opacity
              (if (opacity-visual? content) (visual-opacity content) 1))
           (if (opacity-visual? visual) (visual-opacity visual) 1))))
  (cond
    [(group-visual? content)
     ;; Preserve hierarchy and identities, while folding placement into leaves.
     ;; This keeps visual paths addressable after a world-space map.
     (group
      (for/list ([child (in-list (group-visual-children content))])
        (map-visual-tree child map-point progress samples adaptive? tolerance max-depth
                         discontinuity-mode world-map world-opacity))
      #:id (visual-id content))]
    [(path-visual? content)
     (mapped-path-leaf content (path-visual-path content)
                       map-point progress samples adaptive? tolerance max-depth
                       discontinuity-mode world-map world-opacity)]
    [(axes-visual? content)
     (mapped-styled-path-leaf
      (visual-id content)
      (axes-visual-path-geometry content)
      #f (axes-visual-stroke content) (axes-visual-stroke-width content)
      map-point progress samples adaptive? tolerance max-depth discontinuity-mode
      world-map world-opacity)]
    [(arrow-visual? content)
     (mapped-styled-path-leaf
      (visual-id content)
      (arrow-visual-path-geometry content)
      #f (arrow-visual-stroke content) (arrow-visual-stroke-width content)
      map-point progress samples adaptive? tolerance max-depth discontinuity-mode
      world-map world-opacity)]
    [(circle-visual? content)
     (mapped-path-leaf content (circle-path (circle-visual-radius content))
                       map-point progress samples adaptive? tolerance max-depth
                       discontinuity-mode world-map world-opacity)]
    [(rectangle-visual? content)
     (mapped-path-leaf content
                       (rectangle-path (rectangle-visual-width content)
                                       (rectangle-visual-height content))
                       map-point progress samples adaptive? tolerance max-depth
                       discontinuity-mode world-map world-opacity)]
    [else
     ;; Text, images, and custom affine leaves have no exposed vector outline.
     ;; Keep them legible at their original world placement instead of silently
     ;; dropping them or pretending they were geometrically deformed.
     (world-place-visual content world-map world-opacity)]))

(define (world-place-visual visual map opacity)
  (define transformed (affine-map visual map))
  (if (opacity-visual? transformed)
      (visual-with-opacity transformed opacity)
      transformed))

(define (mapped-path-leaf visual geometry map-point progress samples adaptive? tolerance max-depth
                          discontinuity-mode world-map world-opacity)
  (mapped-styled-path-leaf
   (visual-id visual) geometry
   (visual-fill-color visual) (visual-stroke-color visual)
   (visual-stroke-width visual)
   map-point progress samples adaptive? tolerance max-depth discontinuity-mode
   world-map world-opacity))

(define (mapped-styled-path-leaf id geometry fill stroke stroke-width
                                 map-point progress samples adaptive? tolerance max-depth
                                 discontinuity-mode world-map world-opacity)
  (define world-geometry
    (path-geometry-map-points
     geometry
     (lambda (point)
       (affine2-apply-point world-map point))))
  (define blended-geometry
    (if adaptive?
        (adaptive-mapped-path-geometry
         world-geometry map-point progress samples tolerance max-depth
         discontinuity-mode)
        (path-geometry-map-points
         (sample-path-geometry world-geometry samples)
         (lambda (point)
           (vec2-lerp point
                      (checked-map-result 'apply-pointwise map-point point)
                      progress)))))
  (make-path-visual blended-geometry
                    #:id id
                    #:opacity world-opacity
                    #:fill fill #:stroke stroke #:stroke-width stroke-width))


;;;
;;; Adaptive Mapping and Discontinuity Splitting
;;;

;; Each retained sample keeps both its source and mapped locations. This makes
;; interpolation at an interior animation progress a direct, deterministic
;; pointwise blend, while a failed map result becomes a subpath break rather
;; than a spurious segment drawn across a pole.
(struct mapped-sample (source mapped)
  #:transparent)

(define (adaptive-mapped-path-geometry geometry map-point progress samples tolerance
                                        max-depth discontinuity-mode)
  (path-geometry
   (append-map
    (lambda (subpath)
      (adaptive-map-subpath subpath map-point progress samples tolerance max-depth
                            discontinuity-mode))
    (path-geometry-subpaths geometry))))

(define (adaptive-map-subpath subpath map-point progress samples tolerance max-depth
                              discontinuity-mode)
  (define start (path-subpath-start subpath))
  (define-values (fragments final-point)
    (for/fold ([all-fragments '()] [segment-start start])
              ([segment (in-list (path-subpath-segments subpath))])
      (define segment-end (path-segment-end segment))
      (define-values (next-fragments ignored)
        (for/fold ([fragments all-fragments] [previous segment-start])
                  ([index (in-range 1 (add1 samples))])
          (define next
            (path-segment-point segment segment-start (/ index samples)))
          (values
           (append-mapped-fragments
            fragments
            (adaptive-map-interval
             (lambda (fraction)
               (path-segment-point segment segment-start fraction))
             (/ (sub1 index) samples)
             (/ index samples)
             map-point progress tolerance max-depth discontinuity-mode))
           next)))
      (values next-fragments segment-end)))
  ;; `closed?` supplies a final geometric edge even when the input stores no
  ;; explicit final return segment. It must be sampled before mapping as well.
  (define closed-fragments
    (if (and (path-subpath-closed? subpath)
             (not (vec2=? final-point start)))
        (for/fold ([fragments fragments]) ([index (in-range 1 (add1 samples))])
          (append-mapped-fragments
           fragments
           (adaptive-map-interval
            (lambda (fraction) (vec2-lerp final-point start fraction))
            (/ (sub1 index) samples)
            (/ index samples)
            map-point progress tolerance max-depth discontinuity-mode)))
        fragments))
  (mapped-fragments->subpaths closed-fragments (path-subpath-closed? subpath)))

(define (adaptive-map-interval point-at from to map-point progress tolerance
                               max-depth discontinuity-mode)
  (define source-from (point-at from))
  (define source-to (point-at to))
  (define mapped-from
    (map-result 'apply-pointwise map-point source-from discontinuity-mode))
  (define mapped-to
    (map-result 'apply-pointwise map-point source-to discontinuity-mode))
  (let refine ([left-parameter from]
               [left-source source-from]
               [left-mapped mapped-from]
               [right-parameter to]
               [right-source source-to]
               [right-mapped mapped-to]
               [depth 0])
    (define middle-parameter (/ (+ left-parameter right-parameter) 2))
    (define middle-source (point-at middle-parameter))
    (define middle-mapped
      (map-result 'apply-pointwise map-point middle-source discontinuity-mode))
    (cond
      [(and left-mapped middle-mapped right-mapped
            (or (>= depth max-depth)
                (<= (mapped-chord-deviation left-mapped middle-mapped right-mapped)
                    tolerance)))
       (list
        (list (mapped-sample left-source
                             (vec2-lerp left-source left-mapped progress))
              (mapped-sample right-source
                             (vec2-lerp right-source right-mapped progress))))]
      [(>= depth max-depth)
       ;; A failed or unresolved interval contributes no edge. Its valid
       ;; neighbours, if any, remain separate fragments instead of bridging a
       ;; discontinuity with a long artificial chord.
      '()]
      [else
       ;; Join adjacent refined leaves when their boundary is a valid common
       ;; sample. `append` alone would turn every adaptive leaf into a visible
       ;; path break; append-mapped-fragments preserves breaks only at failed
       ;; map samples such as poles or domain boundaries.
       (append-mapped-fragments
        (refine left-parameter left-source left-mapped
                middle-parameter middle-source middle-mapped (add1 depth))
        (refine middle-parameter middle-source middle-mapped
                right-parameter right-source right-mapped (add1 depth)))])))

(define (append-mapped-fragments accumulated incoming)
  (cond
    [(null? accumulated) incoming]
    [(null? incoming) accumulated]
    [else
     (define previous (last accumulated))
     (define next (car incoming))
     (if (and (pair? previous) (pair? next)
              (same-mapped-sample? (last previous) (car next)))
         (append (drop-right accumulated 1)
                 (list (append previous (cdr next)))
                 (cdr incoming))
         (append accumulated incoming))]))

(define (same-mapped-sample? first second)
  (and (vec2=? (mapped-sample-source first) (mapped-sample-source second))
       (vec2=? (mapped-sample-mapped first) (mapped-sample-mapped second))))

(define (mapped-fragments->subpaths fragments originally-closed?)
  (for/list ([fragment (in-list fragments)]
             #:when (>= (length fragment) 2))
    (define first (car fragment))
    (define last-sample (last fragment))
    (define closes?
      (and originally-closed?
           (vec2=? (mapped-sample-source first)
                    (mapped-sample-source last-sample))
           (vec2=? (mapped-sample-mapped first)
                    (mapped-sample-mapped last-sample))))
    (define normalized
      (if closes? (drop-right fragment 1) fragment))
    (path-subpath
     (mapped-sample-mapped (car normalized))
     (for/list ([sample (in-list (cdr normalized))])
       (line-path-segment (mapped-sample-mapped sample)))
     closes?)))

(define (mapped-chord-deviation left middle right)
  (point-distance middle (vec2-scale 1/2 (vec2+ left right))))

(define (map-result who map-point point discontinuity-mode)
  (define (attempt)
    (define result (map-point point))
    (unless (vec2? result)
      (raise-arguments-error who "the point map must return a vec2"
                             "point" point "result" result))
    result)
  (if (eq? discontinuity-mode 'split)
      (with-handlers ([exn:fail? (lambda (_exception) #f)])
        (attempt))
      (attempt)))


;;;
;;; Differential and Inverse-Mesh Helpers
;;;

;; A centred finite difference keeps Jacobian inspection in the same pure
;; point-map vocabulary as deformation. It is deliberately a query, not a
;; renderer-dependent visual effect.
(define (pointwise-jacobian map-point point #:step [step 1/1000])
  (check-point-map 'pointwise-jacobian map-point)
  (unless (vec2? point)
    (raise-argument-error 'pointwise-jacobian "vec2?" point))
  (check-positive-finite-real 'pointwise-jacobian "step" step)
  (define x-plus (map-result 'pointwise-jacobian map-point
                             (vec2+ point (vec2 step 0)) 'error))
  (define x-minus (map-result 'pointwise-jacobian map-point
                              (vec2- point (vec2 step 0)) 'error))
  (define y-plus (map-result 'pointwise-jacobian map-point
                             (vec2+ point (vec2 0 step)) 'error))
  (define y-minus (map-result 'pointwise-jacobian map-point
                              (vec2- point (vec2 0 step)) 'error))
  (define divisor (* 2 step))
  (linear2 (/ (- (vec2-x x-plus) (vec2-x x-minus)) divisor)
           (/ (- (vec2-x y-plus) (vec2-x y-minus)) divisor)
           (/ (- (vec2-y x-plus) (vec2-y x-minus)) divisor)
           (/ (- (vec2-y y-plus) (vec2-y y-minus)) divisor)))

(define (pointwise-jacobian-determinant map-point point #:step [step 1/1000])
  (linear2-determinant (pointwise-jacobian map-point point #:step step)))

(define (pointwise-orientation map-point point
                               #:step [step 1/1000]
                               #:tolerance [tolerance 1e-8])
  (check-positive-finite-real 'pointwise-orientation "tolerance" tolerance)
  (define determinant
    (pointwise-jacobian-determinant map-point point #:step step))
  (cond
    [(> determinant tolerance) 'preserving]
    [(< determinant (- tolerance)) 'reversing]
    [else 'singular]))

;; inverse-map-mesh : (-> vec2? vec2?) #:id symbol? ... -> group-visual?
;; Builds a regular target-space mesh, maps it through an author-supplied
;; inverse, and returns ordinary adaptive path geometry. It is useful when a
;; forward map has no simple analytic grid image but a usable inverse is known.
(define (inverse-map-mesh inverse-map
                          #:id id
                          #:x-min [x-min -3]
                          #:x-max [x-max 3]
                          #:y-min [y-min -2]
                          #:y-max [y-max 2]
                          #:x-count [x-count 7]
                          #:y-count [y-count 5]
                          #:samples [samples 12]
                          #:tolerance [tolerance 1/32]
                          #:max-depth [max-depth 8]
                          #:stroke [stroke "mediumpurple"]
                          #:stroke-width [stroke-width 2])
  (check-point-map 'inverse-map-mesh inverse-map)
  (unless (symbol? id)
    (raise-argument-error 'inverse-map-mesh "symbol?" id))
  (for ([value (in-list (list x-min x-max y-min y-max))])
    (unless (finite-real? value)
      (raise-argument-error 'inverse-map-mesh "finite real bound" value)))
  (unless (< x-min x-max)
    (raise-arguments-error 'inverse-map-mesh "x-min smaller than x-max"
                           "x-min" x-min "x-max" x-max))
  (unless (< y-min y-max)
    (raise-arguments-error 'inverse-map-mesh "y-min smaller than y-max"
                           "y-min" y-min "y-max" y-max))
  (for ([count (in-list (list x-count y-count))])
    (unless (and (exact-integer? count) (>= count 2))
      (raise-argument-error 'inverse-map-mesh "exact integer at least 2" count)))
  (unless (and (finite-real? stroke-width) (not (negative? stroke-width)))
    (raise-argument-error 'inverse-map-mesh "nonnegative finite real?" stroke-width))
  (define (x-at index) (real-lerp x-min x-max (/ index (sub1 x-count))))
  (define (y-at index) (real-lerp y-min y-max (/ index (sub1 y-count))))
  (define target-mesh
    (group
     (append
      (for/list ([index (in-range x-count)])
        (line (vec2 (x-at index) y-min) (vec2 (x-at index) y-max)
              #:id (mesh-child-id 'vertical index)
              #:stroke stroke #:stroke-width stroke-width))
      (for/list ([index (in-range y-count)])
        (line (vec2 x-min (y-at index)) (vec2 x-max (y-at index))
              #:id (mesh-child-id 'horizontal index)
              #:stroke stroke #:stroke-width stroke-width)))
     #:id id))
  (pointwise-map-visual target-mesh inverse-map 1
                         #:samples samples #:adaptive? #t
                         #:tolerance tolerance #:max-depth max-depth
                         #:discontinuities 'split))

(define (mesh-child-id direction index)
  (string->symbol
   (string-append "inverse-mesh-" (symbol->string direction) "-"
                  (number->string index))))


;; Converts every original segment to `samples` straight pieces. It preserves
;; separate subpaths and closure, which keeps fills and holes meaningful.
(define (sample-path-geometry geometry samples)
  (path-geometry
   (for/list ([subpath (in-list (path-geometry-subpaths geometry))])
     (sample-subpath subpath samples))))

(define (sample-subpath subpath samples)
  (define start (path-subpath-start subpath))
  (define-values (points ignored-final)
    (for/fold ([collected (list start)] [segment-start start])
              ([segment (in-list (path-subpath-segments subpath))])
      (define end (path-segment-end segment))
      (values
       (append collected
               (for/list ([index (in-range 1 (add1 samples))])
                 (path-segment-point segment segment-start (/ index samples))))
       end)))
  ;; A closed path can contain an explicit final return to its start. The
  ;; `closed?` flag already supplies that edge, so omit the duplicate endpoint.
  (define normalized-points
    (if (and (path-subpath-closed? subpath)
             (pair? (cdr points))
             (vec2=? (last points) start))
        (drop-right points 1)
        points))
  (path-subpath
   (car normalized-points)
   (for/list ([point (in-list (cdr normalized-points))])
     (line-path-segment point))
   (path-subpath-closed? subpath)))

(define (path-segment-end segment)
  (cond
    [(line-path-segment? segment) (line-path-segment-end segment)]
    [(cubic-bezier-path-segment? segment) (cubic-bezier-path-segment-end segment)]
    [else (raise-argument-error 'sample-path-geometry "path segment" segment)]))

(define (path-segment-point segment start t)
  (cond
    [(line-path-segment? segment)
     (vec2-lerp start (line-path-segment-end segment) t)]
    [(cubic-bezier-path-segment? segment)
     (define one-minus-t (- 1 t))
     (define control1 (cubic-bezier-path-segment-control1 segment))
     (define control2 (cubic-bezier-path-segment-control2 segment))
     (define end (cubic-bezier-path-segment-end segment))
     (vec2+
      (vec2+
       (vec2-scale (* one-minus-t one-minus-t one-minus-t) start)
       (vec2-scale (* 3 one-minus-t one-minus-t t) control1))
      (vec2+
       (vec2-scale (* 3 one-minus-t t t) control2)
       (vec2-scale (* t t t) end)))]
    [else (raise-argument-error 'sample-path-geometry "path segment" segment)]))

;; Four cubic arcs, converted to straight samples immediately before mapping.
(define (circle-path radius)
  (define k (* radius 0.5522847498307936))
  (path-geometry
   (list
    (path-subpath
     (vec2 radius 0)
     (list
      (cubic-bezier-path-segment (vec2 radius k) (vec2 k radius) (vec2 0 radius))
      (cubic-bezier-path-segment (vec2 (- k) radius) (vec2 (- radius) k)
                                 (vec2 (- radius) 0))
      (cubic-bezier-path-segment (vec2 (- radius) (- k)) (vec2 (- k) (- radius))
                                 (vec2 0 (- radius)))
      (cubic-bezier-path-segment (vec2 k (- radius)) (vec2 radius (- k))
                                 (vec2 radius 0)))
     #t))))

(define (rectangle-path width height)
  (define half-width (/ width 2))
  (define half-height (/ height 2))
  (polygon-path
   (list (vec2 (- half-width) (- half-height))
         (vec2 half-width (- half-height))
         (vec2 half-width half-height)
         (vec2 (- half-width) half-height))))

(define (check-point-map who map-point)
  (unless (and (procedure? map-point) (procedure-arity-includes? map-point 1))
    (raise-argument-error who "(procedure-arity-includes/c 1)" map-point)))

(define (checked-map-result who map-point point)
  (define result (map-point point))
  (unless (vec2? result)
    (raise-arguments-error who "the point map must return a vec2"
                           "point" point "result" result))
  result)

(define (vec2=? left right)
  (and (= (vec2-x left) (vec2-x right))
       (= (vec2-y left) (vec2-y right))))

(define (point-distance first second)
  (define displacement (vec2- second first))
  (sqrt (+ (sqr (vec2-x displacement))
           (sqr (vec2-y displacement)))))

(define (check-positive-finite-real who field value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite real?" field value)))
