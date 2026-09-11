#lang racket/base

;; Shared marker geometry for painting and annotation collision tests. No Pict.
(require racket/list (only-in racket/math pi) "math.rkt" "data.rkt" "reveal.rkt")
(provide (struct-out marker-placement) marker-placement-candidates marker-strokes
         marker-label-anchor marker-family marker-members marker-style-type)
(struct marker-placement (position quadrant radius) #:transparent)
(define (unit-vector v)
  (define n (norm v))
  (when (zero? n) (geometry-error 'marker "zero direction"))
  (point* v (/ 1 n)))
(define (direction c) (unit-vector (point- (curve-end c) (curve-start c))))
(define (left v) (point (- (point-y v)) (point-x v)))
(define (marker-style-type m)
  (cond [(perpendicular-marker? m) 'right-angle-marker]
        [(or (equal-length-marker? m) (midpoint-marker? m)) 'length-marker]
        [(parallel-marker? m) 'parallel-marker]
        [else 'angle-marker]))
(define (marker-family m)
  (cond [(or (equal-length-marker? m) (midpoint-marker? m)) 'length]
        [(parallel-marker? m) 'parallel]
        [(or (angle-marker? m) (equal-angle-marker? m)) 'angle]
        [else #f]))
(define (marker-members m)
  (cond [(equal-length-marker? m) (equal-length-marker-segments m)]
        [(midpoint-marker? m)
         (define s (midpoint-marker-segment m)) (define p (midpoint-marker-point m))
         (list (segment (segment-a s) p) (segment p (segment-b s)))]
        [(parallel-marker? m) (list (parallel-marker-first m) (parallel-marker-second m))]
        [(angle-marker? m) (list (angle-marker-angle m))]
        [(equal-angle-marker? m) (equal-angle-marker-angles m)]
        [else '()]))
(define (square-directions value quadrant)
  (define u (direction (perpendicular-marker-first value)))
  (define v0 (direction (perpendicular-marker-second value)))
  ;; Quadrants are relative to first object's direction and its left side.
  (define v (if (< (cross u v0) 0) (point* v0 -1) v0))
  (values (point* u (if (memq quadrant '(1 4)) 1 -1))
          (point* v (if (memq quadrant '(1 2)) 1 -1))))
(define (marker-placement-candidates value style view hints)
  (define t (hash-ref hints 'marker-position #f))
  (define q (hash-ref hints 'marker-quadrant #f))
  (define r (hash-ref hints 'marker-radius #f))
  (define radius (hash-ref style 'radius))
  (cond
    [(perpendicular-marker? value)
     (define at (perpendicular-marker-at value))
     (define size (hash-ref style 'size))
     (define placements
       (for/list ([quadrant (in-list (if q (list q) '(1 2 4 3)))]
                  #:when
                  (let-values ([(u v) (square-directions value quadrant)])
                    (and (on (point+ at (point* u size)) (perpendicular-marker-first value))
                         (on (point+ at (point* v size)) (perpendicular-marker-second value)))))
         (marker-placement 0.5 quadrant radius)))
     (when (null? placements)
       (geometry-error 'marker-layout "right-angle marker cannot fit on the specified arms at this size/quadrant"))
     placements]
    [(memq (marker-family value) '(length parallel))
     (for/list ([position (in-list (if t (list t) '(0.5 0.4 0.6 0.3 0.7)))])
       (marker-placement position 1 radius))]
    [else
     (for/list ([radius* (in-list (if r (list r) (list radius (* 1.3 radius) (* 1.6 radius))))])
       (marker-placement 0.5 1 radius*))]))
(define (visible-linear-pair c view)
  (cond [(segment? c) (list (segment-a c) (segment-b c))]
        [else
         (define center (geometry-view-center view))
         (define hw (/ (geometry-view-width view) 2))
         (define hh (/ hw (geometry-view-aspect view)))
         (clip-linear c (- (point-x center) hw) (+ (point-x center) hw)
                        (- (point-y center) hh) (+ (point-y center) hh))]))
(define (ticks s size spacing count position)
  (define u (direction s)) (define v (left u))
  (define center (interpolate-point (segment-a s) (segment-b s) position))
  (for/list ([i (in-range count)])
    (define mid (point+ center (point* u (* spacing (- i (/ (sub1 count) 2))))))
    ;; Keep the accepted 20% shorter ticks, independent of the square's size.
    (list (point+ mid (point* v (* -0.4 size)))
          (point+ mid (point* v (* 0.4 size))))))
(define (marker-strokes value style placement count view [progress 1])
  (define size (hash-ref style 'size))
  (define spacing (hash-ref style 'spacing))
  (define t (marker-placement-position placement))
  (define p (max 0 (min 1 progress)))
  (define full
    (cond
      [(perpendicular-marker? value)
       (define at (perpendicular-marker-at value))
       (define-values (u v) (square-directions value (marker-placement-quadrant placement)))
       (list (list (point+ at (point* u size))
                   (point+ at (point* (point+ u v) size))
                   (point+ at (point* v size))))]
      [(memq (marker-family value) '(length))
       (append-map (lambda (s) (ticks s size spacing count t)) (marker-members value))]
      [(parallel-marker? value)
       (define reference (direction (parallel-marker-first value)))
       (append-map
        (lambda (c)
          (define ends (visible-linear-pair c view))
          (cond [(not (= (length ends) 2)) '()]
                [else
                 (define u0 (direction c))
                 ;; Match arrow direction even if the second segment is reversed.
                 (define u (if (< (dot u0 reference) 0) (point* u0 -1) u0))
                 (define v (left u))
                 (define center (interpolate-point (car ends) (cadr ends) t))
                 (for/list ([i (in-range count)])
                   (define mid (point+ center (point* u (* spacing (- i (/ (sub1 count) 2))))))
                   (list (point+ mid (point+ (point* u (* -0.35 size)) (point* v (* 0.35 size))))
                         (point+ mid (point* u (* 0.45 size)))
                         (point+ mid (point+ (point* u (* -0.35 size)) (point* v (* -0.35 size))))))]))
        (marker-members value))]
      [else
       (append-map
        (lambda (spec)
          (define u (point- (angle-spec-a spec) (angle-spec-b spec)))
          (for/list ([i (in-range count)])
            (reveal-arc (angle-spec-b spec) (+ (marker-placement-radius placement) (* i spacing))
                        (atan (point-y u) (point-x u)) (angle-sweep spec) #f)))
        (marker-members value))]))
  (if (zero? p) '()
      (for/list ([stroke (in-list full)])
        (if (reveal-arc? stroke)
            (struct-copy reveal-arc stroke [sweep (* p (reveal-arc-sweep stroke))])
            (polyline-prefix stroke p)))))
(define (marker-label-anchor value style placement count view)
  (cond
    [(memq (marker-family value) '(angle))
     (define spec (car (marker-members value)))
     (define u (point- (angle-spec-a spec) (angle-spec-b spec)))
     (define theta (+ (atan (point-y u) (point-x u)) (/ (angle-sweep spec) 2)))
     (define radius (+ (marker-placement-radius placement) (* (sub1 count) (hash-ref style 'spacing))))
     (point+ (angle-spec-b spec) (point (* radius (cos theta)) (* radius (sin theta))))]
    [else
     (define strokes (marker-strokes value style placement count view))
     (define points (append-map reveal-stroke-points strokes))
     (if (null? points) (geometry-view-center view)
         (point* (foldl point+ (point 0 0) points) (/ 1 (length points))))]))
