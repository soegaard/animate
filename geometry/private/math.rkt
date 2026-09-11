#lang racket/base

;; Pure Euclidean geometry. No animate, GUI, renderer, or mutable scene state.
;; Coordinates and distances are local world units, not pixels.
(require racket/list (only-in racket/math pi))
(provide (struct-out point) (struct-out line) (struct-out segment)
         (struct-out ray) (struct-out circle)
         (struct-out exn:fail:geometry) geometry-error finite-real?
         point+ point- point* dot cross norm distance midpoint circle-radius
         distinct? noncollinear? on same-point? geometry-kind curve?
         curve-start curve-end intersections intersection clip-linear
         circle-points interpolate-point)

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
(define (geometry-kind v)
  (cond [(point? v) 'Point] [(line? v) 'Line] [(segment? v) 'Segment]
        [(ray? v) 'Ray] [(circle? v) 'Circle]
        [(finite-real? v) 'Number]
        [else (geometry-error 'geometry-kind "not a supported geometry value: ~e" v)]))
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
