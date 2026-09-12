#lang racket/base

;; Pure Euclidean geometry. No animate, GUI, renderer, or mutable scene state.
;; Coordinates and distances are local world units, not pixels.
(require racket/list (only-in racket/math pi))
(provide (struct-out point) (struct-out line) (struct-out segment)
         (struct-out ray) (struct-out circle)
         (struct-out angle-spec)
         (struct-out perpendicular-relation) (struct-out parallel-relation)
         (struct-out equal-length-relation) (struct-out equal-angle-relation)
         (struct-out collinear-relation) (struct-out midpoint-of-relation)
         (struct-out perpendicular-marker) (struct-out parallel-marker)
         (struct-out equal-length-marker) (struct-out angle-marker)
         (struct-out equal-angle-marker) (struct-out midpoint-marker)
         (struct-out exn:fail:geometry) geometry-error finite-real? prop:geometry-type
         point+ point- point* dot cross norm distance midpoint circle-radius
         distinct? noncollinear? on same-point? geometry-kind curve? marker? relation?
         marker-anchor-points marker-style-kind relation-holds? relation->marker
         perpendicular-at? parallel-curves? equal-segments? equal-angles?
         collinear-points? midpoint-of? angle-measure angle-directions angle-sweep
         curve-start curve-end intersections intersection clip-linear
         circle-points interpolate-point circle-with-radius
         start-point end-point angle-first angle-vertex angle-last side-of?)

;; exn:fail:geometry carries the operation/construction and a diagnostic payload.
(struct exn:fail:geometry exn:fail (who details) #:transparent)
(define (geometry-error who fmt . args)
  (raise (exn:fail:geometry
          (format "~a: ~a" who (apply format fmt args))
          (current-continuation-marks) who args)))
(define (finite-real? x)
  (and (real? x) (= x x) (< -inf.0 x +inf.0)))
(define epsilon 1e-10)
(define (near-zero? x scale)
  (<= (abs x) (* epsilon (max 1e-300 (abs scale)))))

;; point: x and y, in that order, in local Cartesian world coordinates.
(struct point (x y) #:transparent
  #:guard (lambda (x y who)
            (unless (and (finite-real? x) (finite-real? y))
              (geometry-error who "expected finite coordinates; received ~e, ~e" x y))
            (values x y)))
(define (check-pair a b who)
  (unless (and (point? a) (point? b))
    (geometry-error who "expected two points; received ~e and ~e" a b))
  (when (and (= (point-x a) (point-x b)) (= (point-y a) (point-y b)))
    (geometry-error who "defining points must be distinct"))
  (values a b))
;; Directed defining points a,b. Only line is infinite in both directions.
(struct line (a b) #:transparent #:guard check-pair)
(struct segment (a b) #:transparent #:guard check-pair)
(struct ray (a b) #:transparent #:guard check-pair)
;; circle: its centre followed by the circumference point that defines its radius.
(struct circle (center through) #:transparent #:guard check-pair)

;; Relations are mathematical facts; markers are one drawable presentation of them.
(struct angle-spec (a b c) #:transparent)
(struct perpendicular-relation (first second at) #:transparent)
(struct parallel-relation (first second) #:transparent)
(struct equal-length-relation (segments) #:transparent)
(struct equal-angle-relation (angles) #:transparent)
(struct collinear-relation (points) #:transparent)
(struct midpoint-of-relation (point segment) #:transparent)
(struct perpendicular-marker (first second at) #:transparent)
(struct parallel-marker (first second) #:transparent)
(struct equal-length-marker (segments) #:transparent)
(struct angle-marker (angle) #:transparent)
(struct equal-angle-marker (angles) #:transparent)
(struct midpoint-marker (point segment) #:transparent)

(define (point+ a b) (point (+ (point-x a) (point-x b)) (+ (point-y a) (point-y b))))
(define (point- a b) (point (- (point-x a) (point-x b)) (- (point-y a) (point-y b))))
(define (point* a t) (point (* (point-x a) t) (* (point-y a) t)))
(define (dot a b) (+ (* (point-x a) (point-x b)) (* (point-y a) (point-y b))))
(define (cross a b) (- (* (point-x a) (point-y b)) (* (point-y a) (point-x b))))
(define (norm a) (sqrt (dot a a)))
(define (distance a b) (norm (point- a b)))
(define (midpoint a b) (point* (point+ a b) 1/2))
(define (circle-radius c) (distance (circle-center c) (circle-through c)))
(define (interpolate-point a b t) (point+ a (point* (point- b a) t)))
(define (same-point? a b [scale 1])
  (near-zero? (distance a b) scale))
(define (distinct? a b)
  (not (and (= (point-x a) (point-x b)) (= (point-y a) (point-y b)))))
(define (noncollinear? a b c)
  (define u (point- b a))
  (define v (point- c a))
  (and (distinct? a b) (distinct? a c)
       (not (near-zero? (cross u v) (* (norm u) (norm v))))))
(define-values (prop:geometry-type geometry-typed? geometry-type-ref)
  (make-struct-type-property 'geometry-type))
(define (geometry-kind v)
  (cond [(geometry-typed? v) (geometry-type-ref v)] [(string? v) 'Text] [(point? v) 'Point] [(line? v) 'Line] [(segment? v) 'Segment]
        [(ray? v) 'Ray] [(circle? v) 'Circle] [(marker? v) 'Marker]
        [(relation? v) 'Relation] [(angle-spec? v) 'Angle]
        [(memq v '(left right)) 'Side] [(finite-real? v) 'Number]
        [else (geometry-error 'geometry-kind "not a supported geometry value: ~e" v)]))

(define (relation? v)
  (or (perpendicular-relation? v) (parallel-relation? v)
      (equal-length-relation? v) (equal-angle-relation? v)
      (collinear-relation? v) (midpoint-of-relation? v)))

(define (marker? v)
  (or (perpendicular-marker? v) (parallel-marker? v)
      (equal-length-marker? v) (angle-marker? v)
      (equal-angle-marker? v) (midpoint-marker? v)))
(define (marker-style-kind v)
  (cond [(perpendicular-marker? v) 'marker]
        [(parallel-marker? v) 'marker]
        [(equal-length-marker? v) 'marker]
        [(angle-marker? v) 'marker]
        [(equal-angle-marker? v) 'marker]
        [(midpoint-marker? v) 'marker]
        [else (geometry-error 'marker-style-kind "not a marker value: ~e" v)]))
(define (unit-vector p who)
  (define n (norm p))
  (when (zero? n) (geometry-error who "degenerate direction"))
  (point* p (/ 1 n)))
(define (linear-direction c)
  (unit-vector (point- (curve-end c) (curve-start c)) 'linear-direction))
(define (angle-directions spec)
  (unless (angle-spec? spec) (geometry-error 'angle-directions "expected an angle specification"))
  (define u (point- (angle-spec-a spec) (angle-spec-b spec)))
  (define v (point- (angle-spec-c spec) (angle-spec-b spec)))
  (values (unit-vector u 'angle) (unit-vector v 'angle)))
(define (angle-measure spec)
  (define-values (u v) (angle-directions spec))
  (define theta (atan (cross u v) (dot u v)))
  (abs theta))
(define (angle-sweep spec)
  (define-values (u v) (angle-directions spec))
  (define theta (atan (cross u v) (dot u v)))
  (cond [(> theta pi) (- theta (* 2 pi))]
        [(<= theta (- pi)) (+ theta (* 2 pi))]
        [else theta]))
(define (parallel-curves? a b)
  (unless (and (linear? a) (linear? b))
    (geometry-error 'parallel-curves? "expected two linear objects"))
  (near-zero? (cross (linear-direction a) (linear-direction b)) 1))
(define (collinear-points? points)
  (unless (and (list? points) (>= (length points) 3) (andmap point? points))
    (geometry-error 'collinear-points? "expected at least three points"))
  (define a (car points))
  (define b (for/first ([p (in-list (cdr points))] #:when (distinct? a p)) p))
  (or (not b)
      (let ([u (point- b a)])
        (for/and ([p (in-list (cdr points))])
          (define v (point- p a))
          (near-zero? (cross u v) (* (norm u) (max (norm u) (norm v))))))))
(define (midpoint-of? p s)
  (unless (and (point? p) (segment? s))
    (geometry-error 'midpoint-of? "expected a point and a segment"))
  (and (on p s)
       (let* ([a (segment-a s)] [b (segment-b s)]
              [da (distance p a)] [db (distance p b)]
              [scale (max 1 (distance a b))])
         (near-zero? (- da db) scale))))
(define (relation-holds? relation)
  (cond [(perpendicular-relation? relation)
         (perpendicular-at? (perpendicular-relation-first relation)
                            (perpendicular-relation-second relation)
                            (perpendicular-relation-at relation))]
        [(parallel-relation? relation)
         (parallel-curves? (parallel-relation-first relation)
                           (parallel-relation-second relation))]
        [(equal-length-relation? relation)
         (equal-segments? (equal-length-relation-segments relation))]
        [(equal-angle-relation? relation)
         (equal-angles? (equal-angle-relation-angles relation))]
        [(collinear-relation? relation)
         (collinear-points? (collinear-relation-points relation))]
        [(midpoint-of-relation? relation)
         (midpoint-of? (midpoint-of-relation-point relation)
                       (midpoint-of-relation-segment relation))]
        [else (geometry-error 'relation-holds? "expected a relation value: ~e" relation)]))
(define (relation->marker relation)
  (unless (relation-holds? relation)
    (geometry-error 'marker "relation does not hold: ~e" relation))
  (cond [(perpendicular-relation? relation)
         (perpendicular-marker (perpendicular-relation-first relation)
                               (perpendicular-relation-second relation)
                               (perpendicular-relation-at relation))]
        [(parallel-relation? relation)
         (parallel-marker (parallel-relation-first relation)
                          (parallel-relation-second relation))]
        [(equal-length-relation? relation)
         (equal-length-marker (equal-length-relation-segments relation))]
        [(equal-angle-relation? relation)
         (equal-angle-marker (equal-angle-relation-angles relation))]
        [(midpoint-of-relation? relation)
         (midpoint-marker (midpoint-of-relation-point relation)
                          (midpoint-of-relation-segment relation))]
        [else (geometry-error 'relation->marker "no marker visualization for relation ~e" relation)]))

(define (perpendicular-at? a b p)
  (unless (and (linear? a) (linear? b))
    (geometry-error 'perpendicular-at? "expected two linear objects"))
  (and (point? p) (on p a) (on p b)
       (near-zero? (dot (linear-direction a) (linear-direction b)) 1)))
(define (equal-segments? segments)
  (unless (and (list? segments) (>= (length segments) 2) (andmap segment? segments))
    (geometry-error 'equal-segments? "expected at least two segments"))
  (define base (distance (segment-a (car segments)) (segment-b (car segments))))
  (define scale base)
  (andmap (lambda (s)
            (near-zero? (- (distance (segment-a s) (segment-b s)) base) scale))
          (cdr segments)))
(define (equal-angles? angles)
  (unless (and (list? angles) (>= (length angles) 2) (andmap angle-spec? angles))
    (geometry-error 'equal-angles? "expected at least two angle specifications"))
  (define base (angle-measure (car angles)))
  (define scale (max 1 base))
  (andmap (lambda (a) (near-zero? (- (angle-measure a) base) scale)) (cdr angles)))
(define (marker-anchor-points v)
  (cond [(perpendicular-marker? v) (list (perpendicular-marker-at v))]
        [(parallel-marker? v)
         (list (midpoint (curve-start (parallel-marker-first v)) (curve-end (parallel-marker-first v)))
               (midpoint (curve-start (parallel-marker-second v)) (curve-end (parallel-marker-second v))))]
        [(equal-length-marker? v)
         (map (lambda (s) (midpoint (segment-a s) (segment-b s))) (equal-length-marker-segments v))]
        [(angle-marker? v) (list (angle-spec-b (angle-marker-angle v)))]
        [(equal-angle-marker? v) (map angle-spec-b (equal-angle-marker-angles v))]
        [(midpoint-marker? v) (list (midpoint-marker-point v))]
        [else '()]))

(define (linear? v) (or (line? v) (segment? v) (ray? v)))
(define (curve? v) (or (linear? v) (circle? v)))
(define (curve-start v)
  (cond [(line? v) (line-a v)] [(segment? v) (segment-a v)] [(ray? v) (ray-a v)]
        [else (geometry-error 'curve-start "expected a line, segment or ray")]))
(define (curve-end v)
  (cond [(line? v) (line-b v)] [(segment? v) (segment-b v)] [(ray? v) (ray-b v)]
        [else (geometry-error 'curve-end "expected a line, segment or ray")]))
(define (allowed-parameter? c t)
  (cond [(segment? c) (<= (- epsilon) t (+ 1 epsilon))]
        [(ray? c) (>= t (- epsilon))] [else #t]))
(define (linear-parameter c p)
  (define u (point- (curve-end c) (curve-start c)))
  (/ (dot (point- p (curve-start c)) u) (dot u u)))
(define (on p c)
  (cond
    [(circle? c) (near-zero? (- (distance p (circle-center c)) (circle-radius c))
                            (circle-radius c))]
    [(linear? c)
     (define u (point- (curve-end c) (curve-start c)))
     (define v (point- p (curve-start c)))
     (and (near-zero? (cross u v) (* (norm u) (max (norm u) (norm v))))
          (allowed-parameter? c (linear-parameter c p)))]
    [else (geometry-error 'on "expected a curve; received ~e" c)]))

;; Circle/circle order: first is on the left of the directed centre line c1->c2.
(define (circle-circle c1 c2)
  (define a (circle-center c1))
  (define b (circle-center c2))
  (define r (circle-radius c1))
  (define s (circle-radius c2))
  (define d (distance a b))
  (define scale (max r s d))
  (cond
    [(near-zero? d scale)
     (if (near-zero? (- r s) scale)
         (geometry-error 'intersections "coincident circles have infinitely many intersections")
         '())]
    [(or (> d (+ r s (* epsilon scale)))
         (< d (- (abs (- r s)) (* epsilon scale)))) '()]
    [else
     (define u (point* (point- b a) (/ 1 d)))
     (define x (/ (+ (* r r) (- (* s s)) (* d d)) (* 2 d)))
     (define h2 (- (* r r) (* x x)))
     (define foot (point+ a (point* u x)))
     (cond [(< h2 (- (* epsilon r r))) '()]
           [(near-zero? h2 (* r r)) (list foot)]
           [else
            (define offset (point* (point (- (point-y u)) (point-x u)) (sqrt h2)))
            (list (point+ foot offset) (point- foot offset))])]))

;; Circle/linear order: increasing parameter on the directed linear object.
(define (circle-linear c l)
  (define p (curve-start l))
  (define v (point- (curve-end l) p))
  (define len (norm v))
  (define u (point* v (/ 1 len)))
  (define w (point- (circle-center c) p))
  (define along (dot w u))
  (define across (cross u w))
  (define r (circle-radius c))
  (define h2 (- (* r r) (* across across)))
  (define ts
    (cond [(< h2 (- (* epsilon r r))) '()]
          [(near-zero? h2 (* r r)) (list along)]
          [else (define h (sqrt h2)) (list (- along h) (+ along h))]))
  (for/list ([t (in-list ts)] #:when (allowed-parameter? l (/ t len)))
    (point+ p (point* u t))))

(define (linear-linear l m)
  (define p (curve-start l))
  (define q (curve-start m))
  (define u (point- (curve-end l) p))
  (define v (point- (curve-end m) q))
  (define w (point- q p))
  (define den (cross u v))
  (cond
    [(near-zero? den (* (norm u) (norm v)))
     (cond
       [(not (near-zero? (cross w u) (* (norm u) (max (norm w) (norm u))))) '()]
       [else
        ;; Work on l's parameter axis. Disjoint collinear segments/rays have
        ;; no intersection; touching endpoints have exactly one. Positive
        ;; overlap still denotes infinitely many points, not an arbitrary one.
        (define start (/ (dot w u) (dot u u)))
        (define factor (/ (dot v u) (dot u u)))
        (define low-l (if (line? l) -inf.0 0))
        (define high-l (if (segment? l) 1 +inf.0))
        (define low-m (cond [(line? m) -inf.0]
                            [(segment? m) (min start (+ start factor))]
                            [(positive? factor) start] [else -inf.0]))
        (define high-m (cond [(line? m) +inf.0]
                             [(segment? m) (max start (+ start factor))]
                             [(positive? factor) +inf.0] [else start]))
        (define lo (max low-l low-m))
        (define hi (min high-l high-m))
        (cond [(> lo hi) '()]
              [(and (finite-real? lo) (finite-real? hi) (near-zero? (- hi lo) 1))
               (list (point+ p (point* u (/ (+ lo hi) 2))))]
              [else (geometry-error 'intersections "overlapping linear objects have infinitely many intersections")])])]
    [else
     (define t (/ (cross w v) den))
     (define s (/ (cross w u) den))
     (if (and (allowed-parameter? l t) (allowed-parameter? m s))
         (list (point+ p (point* u t))) '())]))

;; intersections : curve? curve? -> (listof point?)
;; Tangencies return one point. Empty intersections return an empty list.
(define (intersections a b)
  (cond [(and (circle? a) (circle? b)) (circle-circle a b)]
        [(and (circle? a) (linear? b)) (circle-linear a b)]
        [(and (linear? a) (circle? b)) (circle-linear b a)]
        [(and (linear? a) (linear? b)) (linear-linear a b)]
        [else (geometry-error 'intersections "expected two supported curves")]))

;; The optional side argument permits the authored spelling
;; (intersection c1 c2 #:side-of AB 'left), as well as ordinary keyword calls.
(define (intersection a b [side 'left]
                      #:side-of [reference #f]
                      #:other-than [other #f]
                      #:near [near #f]
                      #:far-from [far #f])
  (define scale
    (max 1e-300
         (if (circle? a) (circle-radius a) (distance (curve-start a) (curve-end a)))
         (if (circle? b) (circle-radius b) (distance (curve-start b) (curve-end b)))))
  (define candidates0 (intersections a b))
  (when (and other (not (ormap (lambda (p) (same-point? p other scale)) candidates0)))
    (geometry-error 'intersection "the #:other-than point is not an intersection of these curves"))
  (define candidates1
    (if other (filter (lambda (p) (not (same-point? p other scale))) candidates0) candidates0))
  (define candidates
    (if reference
        (begin
          (unless (memq side '(left right))
            (geometry-error 'intersection "side must be 'left or 'right"))
          (filter
           (lambda (p)
             (define z (cross (point- (curve-end reference) (curve-start reference))
                              (point- p (curve-start reference))))
             (if (eq? side 'left) (> z 0) (< z 0))) candidates1))
        candidates1))
  (define selected
    (cond [(or near far)
           (define anchor (or near far))
           (define sorted (sort candidates (if near < >) #:key (lambda (p) (distance p anchor))))
           (when (and (pair? sorted) (pair? (cdr sorted))
                      (near-zero? (- (distance (car sorted) anchor)
                                     (distance (cadr sorted) anchor)) scale))
             (geometry-error 'intersection "equidistant candidates: selector is ambiguous"))
           (if (null? sorted) '() (list (car sorted)))]
          [else candidates]))
  (unless (= (length selected) 1)
    (geometry-error 'intersection "expected one selected intersection, found ~a" (length selected)))
  (car selected))

;; clip-linear : linear-object xmin xmax ymin ymax -> empty or two endpoints.
;; Slab clipping uses a parameter interval, not a fictitious large line segment.
(define (clip-linear c xmin xmax ymin ymax)
  (define p (curve-start c))
  (define d (point- (curve-end c) p))
  (define initial-low (if (line? c) -inf.0 0))
  (define initial-high (if (segment? c) 1 +inf.0))
  (define bounds
    (for/fold ([interval (cons initial-low initial-high)])
              ([x (in-list (list (point-x p) (point-y p)))]
               [dx (in-list (list (point-x d) (point-y d)))]
               [lo (in-list (list xmin ymin))] [hi (in-list (list xmax ymax))])
      (cond [(not interval) #f]
            [(zero? dx) (and (<= lo x hi) interval)]
            [else
             (define t1 (/ (- lo x) dx))
             (define t2 (/ (- hi x) dx))
             (define low (max (car interval) (min t1 t2)))
             (define high (min (cdr interval) (max t1 t2)))
             (and (<= low high) (cons low high))])))
  (if bounds
      (list (point+ p (point* d (car bounds))) (point+ p (point* d (cdr bounds))))
      '()))

;; A circumference prefix with two fronts, starting at the defining point.
;; The returned polyline is one continuous arc, so there is no seam at the start.
(define (circle-points c progress [resolution 256])
  (define center (circle-center c))
  (define v (point- (circle-through c) center))
  (define theta (atan (point-y v) (point-x v)))
  (define r (circle-radius c))
  (define p (max 0 (min 1 progress)))
  (define count (max 2 (inexact->exact (ceiling (* resolution p)))))
  (for/list ([i (in-range (+ count 1))])
    (define a (+ theta (- (* pi p)) (* 2 pi p (/ i count))))
    (point+ center (point (* r (cos a)) (* r (sin a))))))

;; A transferable-compass circle. This does not construct a centre or a direction.
;; The two-point circle constructor keeps its original through-point meaning.
(define (circle-with-radius center radius)
  (unless (and (point? center) (finite-real? radius) (> radius 0))
    (geometry-error 'circle-with-radius "expected a point and a positive finite radius"))
  (circle center (point+ center (point radius 0))))
(define start-point curve-start)
(define end-point curve-end)
(define angle-first angle-spec-a)
(define angle-vertex angle-spec-b)
(define angle-last angle-spec-c)
(define (side-of? p reference side)
  (unless (and (point? p) (linear? reference) (memq side '(left right)))
    (geometry-error 'side-of? "expected a point, a directed linear object, and left or right"))
  (define u (point- (curve-end reference) (curve-start reference)))
  (define v (point- p (curve-start reference)))
  (define determinant (cross u v))
  (and (not (near-zero? determinant (* (norm u) (max (norm u) (norm v)))))
       (if (eq? side 'left) (> determinant 0) (< determinant 0))))
