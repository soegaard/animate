#lang racket/base

;; Pure, random-access reveal geometry. Geometry is constructed before clipping:
;; an offscreen endpoint must not silently become the viewport edge.
(require racket/list (only-in racket/math pi) "math.rkt" "data.rkt")
(provide default-reveal-mode reveal-mode-valid? resolve-reveal-mode
         (struct-out reveal-arc) reveal-arc-points
         polyline-prefix curve-reveal-strokes reveal-stroke-points)

(struct reveal-arc (center radius start sweep closed?) #:transparent)
(define (unit x) (max 0 (min 1 x)))
(define (default-reveal-mode kind)
  (case kind
    [(Point) 'pop] [(Segment Ray) 'from-start] [(Line) 'from-center]
    [(Circle) 'bidirectional] [(Marker) 'draw]
    [else 'fade]))
(define (reveal-mode-valid? kind mode)
  (and (symbol? mode)
       (or (memq mode '(auto fade))
           (case kind
             [(Point) (eq? mode 'pop)]
             [(Segment) (memq mode '(from-start from-end from-center))]
             [(Ray) (eq? mode 'from-start)]
             [(Line) (eq? mode 'from-center)]
             [(Circle) (memq mode '(bidirectional clockwise counterclockwise))]
             [(Marker) (eq? mode 'draw)]
             [else #f])) #t))
(define (resolve-reveal-mode program id kind)
  (define mode
    (for/fold ([mode 'auto]) ([rule (in-list (geometry-program-reveals program))]
                             #:when (eq? id (car rule))) (cadr rule)))
  (if (eq? mode 'auto) (default-reveal-mode kind) mode))

;; Exact endpoint interpolation by accumulated arclength; duplicate vertices are
;; harmless. Empty at t=0 and precisely the full input at t=1.
(define (polyline-prefix points progress)
  (define p (unit progress))
  (cond [(or (zero? p) (< (length points) 2)) '()]
        [(= p 1) points]
        [else
         (define total
           (for/sum ([a (in-list points)] [b (in-list (cdr points))]) (distance a b)))
         (let loop ([rest points] [left (* p total)] [out (list (car points))])
           (cond [(or (null? (cdr rest)) (<= left 0)) (reverse out)]
                 [else
                  (define a (car rest)) (define b (cadr rest))
                  (define d (distance a b))
                  (cond [(zero? d) (loop (cdr rest) left out)]
                        [(>= left d) (loop (cdr rest) (- left d) (cons b out))]
                        [else (reverse (cons (interpolate-point a b (/ left d)) out))])]))]))
(define (reveal-arc-points arc)
  ;; Fixed maximum angular step, including exact start/end. Used for collision
  ;; tests and dashed strokes; solid arcs are native cubic Beziers in the adapter.
  (define count (max 1 (inexact->exact (ceiling (* 128 (/ (abs (reveal-arc-sweep arc)) pi))))))
  (for/list ([i (in-range (add1 count))])
    (define theta (+ (reveal-arc-start arc) (* (reveal-arc-sweep arc) (/ i count))))
    (point+ (reveal-arc-center arc)
            (point (* (reveal-arc-radius arc) (cos theta))
                   (* (reveal-arc-radius arc) (sin theta))))))
(define (reveal-stroke-points stroke)
  (if (reveal-arc? stroke) (reveal-arc-points stroke) stroke))
(define (bounds view)
  (define c (geometry-view-center view))
  (define hw (/ (geometry-view-width view) 2))
  (define hh (/ hw (geometry-view-aspect view)))
  (values (- (point-x c) hw) (+ (point-x c) hw)
          (- (point-y c) hh) (+ (point-y c) hh)))
(define (clipped-edge a b view)
  (define-values (xmin xmax ymin ymax) (bounds view))
  (if (distinct? a b)
      (let ([ends (clip-linear (segment a b) xmin xmax ymin ymax)])
        (if (and (= (length ends) 2) (distinct? (car ends) (cadr ends)))
            (list ends) '()))
      '()))
(define (curve-reveal-strokes value view progress [mode 'auto])
  (define kind (geometry-kind value))
  (unless (and (curve? value) (geometry-view? view) (finite-real? progress)
               (reveal-mode-valid? kind mode))
    (geometry-error 'curve-reveal-strokes "invalid curve, view, progress or reveal mode"))
  (define effective (if (eq? mode 'auto) (default-reveal-mode kind) mode))
  (define p (if (eq? effective 'fade) 1 (unit progress)))
  (cond
    [(zero? p) '()]
    [(circle? value)
     (define center (circle-center value))
     (define v (point- (circle-through value) center))
     (define theta (atan (point-y v) (point-x v)))
     (define r (circle-radius value))
     (case effective
       [(clockwise) (list (reveal-arc center r theta (* -2 pi p) (= p 1)))]
       [(counterclockwise fade) (list (reveal-arc center r theta (* 2 pi p) (= p 1)))]
       [else
        ;; Two independent fronts start at the defining circumference point.
        ;; Keeping this split at p=1 also keeps dash phase stable.
        (list (reveal-arc center r theta (* pi p) #f)
              (reveal-arc center r theta (* -1 pi p) #f))])]
    [(segment? value)
     (define a (segment-a value)) (define b (segment-b value))
     (case effective
       [(from-end) (clipped-edge b (interpolate-point b a p) view)]
       [(from-center)
        (define m (midpoint a b))
        (append (clipped-edge m (interpolate-point m a p) view)
                (clipped-edge m (interpolate-point m b p) view))]
       [else (clipped-edge a (interpolate-point a b p) view)])]
    [else
     (define-values (xmin xmax ymin ymax) (bounds view))
     (define ends (clip-linear value xmin xmax ymin ymax))
     (cond [(or (not (= (length ends) 2)) (not (distinct? (car ends) (cadr ends)))) '()]
           [(ray? value)
            (clipped-edge (ray-a value) (interpolate-point (ray-a value) (cadr ends) p) view)]
           [else
            ;; Clamp an offscreen defining midpoint onto the visible interval.
            ;; Otherwise a line can temporarily be drawn backwards outside it.
            (define a (car ends)) (define b (cadr ends))
            (define v (point- b a))
            (define m0 (midpoint (line-a value) (line-b value)))
            (define t (unit (/ (dot (point- m0 a) v) (dot v v))))
            (define m (interpolate-point a b t))
            (append (clipped-edge m (interpolate-point m a p) view)
                    (clipped-edge m (interpolate-point m b p) view))])]))
