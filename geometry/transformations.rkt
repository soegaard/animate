#lang racket/base

;; Euclidean similarities. This is geometry, not a Visual animation API.
;; The restricted representation cannot turn a circle into an ellipse:
;; (x,y) |-> (a*x - parity*b*y + tx, b*x + parity*a*y + ty).
(require racket/list (only-in racket/math pi) "private/math.rkt")
(provide (struct-out geometry-vector) vector-between degrees
         transformation? transformation-scale transformation-orientation
         identity-transform translation rotation reflection dilation
         compose-transform inverse-transform transform
         translate rotate reflect dilate transformable?)

(struct geometry-vector (x y) #:transparent
  #:property prop:geometry-type 'Vector
  #:guard (lambda (x y who)
            (unless (and (finite-real? x) (finite-real? y))
              (geometry-error who "expected finite vector components"))
            (values x y)))
(define (vector-between a b)
  (unless (and (point? a) (point? b)) (geometry-error 'vector-between "expected two points"))
  (geometry-vector (- (point-x b) (point-x a)) (- (point-y b) (point-y a))))
(define (degrees x)
  (unless (finite-real? x) (geometry-error 'degrees "expected a finite angle in degrees"))
  (* pi (/ x 180)))
(struct similarity (a b parity tx ty) #:transparent
  #:property prop:geometry-type 'Transform
  #:guard
  (lambda (a b parity tx ty who)
    (unless (and (andmap finite-real? (list a b tx ty)) (memv parity '(1 -1))
                 (not (and (zero? a) (zero? b)))
                 (finite-real? (+ (* a a) (* b b)))
                 (> (+ (* a a) (* b b)) 0))
      (geometry-error 'transformation "expected a finite, nonsingular similarity"))
    (values a b parity tx ty)))
(define transformation? similarity?)
(define (identity-transform) (similarity 1 0 1 0 0))
(define (check-transform t who)
  (unless (transformation? t) (geometry-error who "expected a Transform")))
(define (transformation-scale t)
  (check-transform t 'transformation-scale)
  (sqrt (+ (* (similarity-a t) (similarity-a t)) (* (similarity-b t) (similarity-b t)))))
(define (transformation-orientation t)
  (check-transform t 'transformation-orientation)
  (similarity-parity t))
(define (map-point t p)
  (define a (similarity-a t)) (define b (similarity-b t)) (define e (similarity-parity t))
  (point (+ (* a (point-x p)) (* (- e) b (point-y p)) (similarity-tx t))
         (+ (* b (point-x p)) (* e a (point-y p)) (similarity-ty t))))
(define (translation v)
  (unless (geometry-vector? v) (geometry-error 'translation "expected a Vector"))
  (similarity 1 0 1 (geometry-vector-x v) (geometry-vector-y v)))
(define (about center a b parity)
  (unless (point? center) (geometry-error 'transformation "expected a Point as centre"))
  (define linear (similarity a b parity 0 0))
  (define image (map-point linear center))
  (similarity a b parity (- (point-x center) (point-x image)) (- (point-y center) (point-y image))))
(define (rotation center theta)
  (unless (finite-real? theta) (geometry-error 'rotation "expected finite radians; use (degrees n) for degrees"))
  (about center (cos theta) (sin theta) 1))
(define (reflection axis)
  (unless (line? axis) (geometry-error 'reflection "expected a Line, not a segment or ray"))
  (define u (point- (line-b axis) (line-a axis)))
  (define x (point-x u)) (define y (point-y u))
  (define d (+ (* x x) (* y y)))
  (unless (and (finite-real? d) (> d 0)) (geometry-error 'reflection "axis direction is numerically degenerate"))
  (about (line-a axis) (/ (- (* x x) (* y y)) d) (/ (* 2 x y) d) -1))
(define (dilation center factor)
  (unless (and (finite-real? factor) (not (zero? factor)))
    (geometry-error 'dilation "scale must be finite and nonzero; negative scales are allowed"))
  (about center factor 0 1))
;; Mathematical composition: (compose-transform T S) applies S, then T.
(define (compose-two t s)
  (define a (similarity-a t)) (define b (similarity-b t)) (define e (similarity-parity t))
  (define c (similarity-a s)) (define d (* e (similarity-b s)))
  (define offset (map-point t (point (similarity-tx s) (similarity-ty s))))
  (similarity (- (* a c) (* b d)) (+ (* a d) (* b c)) (* e (similarity-parity s))
              (point-x offset) (point-y offset)))
(define (compose-transform . ts)
  (for ([t (in-list ts)]) (check-transform t 'compose-transform))
  (foldr compose-two (identity-transform) ts))
(define (inverse-transform t)
  (check-transform t 'inverse-transform)
  (define a (similarity-a t)) (define b (similarity-b t)) (define e (similarity-parity t))
  (define d (+ (* a a) (* b b)))
  (define linear (similarity (/ a d) (/ (* (- e) b) d) e 0 0))
  (define offset (map-point linear (point (- (similarity-tx t)) (- (similarity-ty t)))))
  (similarity (similarity-a linear) (similarity-b linear) e (point-x offset) (point-y offset)))
(define (transformable? v)
  (or (point? v) (curve? v) (angle-spec? v) (relation? v) (marker? v)))
(define (transform t v)
  (check-transform t 'transform)
  (define (go x) (transform t x))
  (cond
    [(point? v) (map-point t v)]
    [(line? v) (line (go (line-a v)) (go (line-b v)))]
    [(segment? v) (segment (go (segment-a v)) (go (segment-b v)))]
    [(ray? v) (ray (go (ray-a v)) (go (ray-b v)))]
    [(circle? v) (circle (go (circle-center v)) (go (circle-through v)))]
    [(angle-spec? v) (angle-spec (go (angle-spec-a v)) (go (angle-spec-b v)) (go (angle-spec-c v)))]
    [(perpendicular-relation? v)
     (perpendicular-relation (go (perpendicular-relation-first v)) (go (perpendicular-relation-second v))
                             (and (perpendicular-relation-at v) (go (perpendicular-relation-at v))))]
    [(parallel-relation? v) (parallel-relation (go (parallel-relation-first v)) (go (parallel-relation-second v)))]
    [(equal-length-relation? v) (equal-length-relation (map go (equal-length-relation-segments v)))]
    [(equal-angle-relation? v) (equal-angle-relation (map go (equal-angle-relation-angles v)))]
    [(collinear-relation? v) (collinear-relation (map go (collinear-relation-points v)))]
    [(midpoint-of-relation? v) (midpoint-of-relation (go (midpoint-of-relation-point v)) (go (midpoint-of-relation-segment v)))]
    [(perpendicular-marker? v)
     (perpendicular-marker (go (perpendicular-marker-first v)) (go (perpendicular-marker-second v)) (go (perpendicular-marker-at v)))]
    [(parallel-marker? v) (parallel-marker (go (parallel-marker-first v)) (go (parallel-marker-second v)))]
    [(equal-length-marker? v) (equal-length-marker (map go (equal-length-marker-segments v)))]
    [(angle-marker? v) (angle-marker (go (angle-marker-angle v)))]
    [(equal-angle-marker? v) (equal-angle-marker (map go (equal-angle-marker-angles v)))]
    [(midpoint-marker? v) (midpoint-marker (go (midpoint-marker-point v)) (go (midpoint-marker-segment v)))]
    [else (geometry-error 'transform "expected Point, Line, Segment, Ray, Circle, Angle, Relation or Marker")]))
(define (translate object v) (transform (translation v) object))
(define (rotate object center theta) (transform (rotation center theta) object))
(define (reflect object axis) (transform (reflection axis) object))
(define (dilate object center factor) (transform (dilation center factor) object))
