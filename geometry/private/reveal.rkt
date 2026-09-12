#lang racket/base

;; Pure, random-access reveal geometry. Geometry is constructed before clipping:
;; an offscreen endpoint must not silently become the viewport edge.
(require racket/list racket/match (only-in racket/math pi)
         "math.rkt" "data.rkt" "evaluate.rkt")
(provide default-reveal-mode reveal-mode-valid? resolve-reveal-mode
         resolve-circle-reveal resolve-compass-source
         (struct-out reveal-arc) reveal-arc-points
         (struct-out compass-source) (struct-out compass-reveal-state)
         compass-draw-end compass-offset-end compass-source-attention-end
         compass-transport-end compass-target-attention-end
         compass-review-pickup-progress compass-review-source-attention-progress
         compass-review-transport-progress compass-review-target-attention-progress
         compass-review-sweep-progress
         compass-circle-reveal
         polyline-prefix curve-reveal-strokes reveal-stroke-points)

(struct reveal-arc (center radius start sweep closed?) #:transparent)
;; A compass source is the visible geometric measure whose length is transported.
;; Its endpoints are frozen world points, not mutable references to scene objects.
(struct compass-source (a b) #:transparent)
;; Circle strokes and guide strokes are separate so the native adapter can style
;; the transient guide independently of the mathematical circle.
(struct compass-reveal-state (circle-strokes guide-strokes guide-opacity guide-attention) #:transparent)

(define (unit x) (max 0 (min 1 x)))
(define (smooth x)
  (define u (unit x))
  (* u u (- 3 (* 2 u))))
(define (sqr x) (* x x))

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
             [(Circle) (memq mode '(bidirectional clockwise counterclockwise compass))]
             [(Marker) (eq? mode 'draw)]
             [else #f])) #t))

(define (configured-reveal-mode program id)
  (for/fold ([mode 'auto]) ([rule (in-list (geometry-program-reveals program))]
                           #:when (eq? id (car rule)))
    (cadr rule)))

(define (resolve-reveal-mode program id kind [compass-source #f])
  (define mode (configured-reveal-mode program id))
  (if (eq? mode 'auto)
      (if (and (eq? kind 'Circle) compass-source)
          'compass
          (default-reveal-mode kind))
      mode))

;; Follow caller aliases and helper argument/result aliases without evaluating
;; arbitrary arithmetic.  Radius provenance is deliberately conservative: only
;; an actual segment length or point-to-point distance is considered a visible
;; measure that can be picked up by the compass guide.
(define (program-node-table program)
  (for/hash ([node (in-list (geometry-program-nodes program))])
    (values (geometry-node-id node) node)))

(define (trace-node-expression table expression [seen '()])
  (cond
    [(and (symbol? expression) (hash-has-key? table expression))
     (when (memq expression seen)
       (geometry-error 'compass-reveal "cyclic provenance through ~a" expression))
     (trace-node-expression table
                            (geometry-node-expression (hash-ref table expression))
                            (cons expression seen))]
    [else expression]))

(define (radius-source-from-expression table expression environment [seen '()])
  (cond
    [(and (symbol? expression) (hash-has-key? table expression))
     (when (memq expression seen)
       (geometry-error 'compass-reveal "cyclic radius provenance through ~a" expression))
     (radius-source-from-expression
      table (geometry-node-expression (hash-ref table expression)) environment
      (cons expression seen))]
    [(and (list? expression) (= (length expression) 2) (eq? (car expression) 'length))
     (define value (evaluate-expression (cadr expression) environment))
     (and (segment? value)
          (compass-source (segment-a value) (segment-b value)))]
    [(and (list? expression) (= (length expression) 3) (eq? (car expression) 'distance))
     (define a (evaluate-expression (cadr expression) environment))
     (define b (evaluate-expression (caddr expression) environment))
     (and (point? a) (point? b) (distinct? a b) (compass-source a b))]
    [else #f]))

;; resolve-compass-source : program id environment [#:allow-through? bool]
;;   -> (or/c compass-source? #f)
;; Automatic mode calls this with allow-through? false, so an ordinary
;; (circle O P) keeps its familiar two-front reveal. Explicit [c compass]
;; permits O--P itself to be the picked-up measure.
(define (resolve-compass-source program id environment #:allow-through? [allow-through? #f])
  (unless (and (geometry-program? program) (symbol? id) (hash? environment))
    (geometry-error 'resolve-compass-source "expected a program, circle id and realization environment"))
  (define table (program-node-table program))
  (define node (hash-ref table id #f))
  (unless node (geometry-error 'resolve-compass-source "unknown circle ~a" id))
  (define expression (trace-node-expression table (geometry-node-expression node)))
  (match expression
    [(list 'circle center '#:radius radius-expression)
     (radius-source-from-expression table radius-expression environment)]
    [(list 'circle center through)
     (and allow-through?
          (let ([a (evaluate-expression center environment)]
                [b (evaluate-expression through environment)])
            (and (point? a) (point? b) (distinct? a b)
                 (compass-source a b))))]
    [_ #f]))

;; resolve-circle-reveal : program circle-id environment -> values mode source
;; An explicit compass reveal is strict: a literal/arithmetic radius with no
;; geometric measure is rejected instead of pretending that the synthetic
;; circumference point supplied by circle-with-radius was visible geometry.
(define (resolve-circle-reveal program id environment)
  (define requested (configured-reveal-mode program id))
  (cond
    [(eq? requested 'compass)
     (define source (resolve-compass-source program id environment #:allow-through? #t))
     (unless source
       (geometry-error 'compass-reveal
                       "circle ~a has no segment length, point distance, or through-point to transfer"
                       id))
     (values 'compass source)]
    [(eq? requested 'auto)
     (define source (resolve-compass-source program id environment))
     (if source (values 'compass source) (values 'bidirectional #f))]
    [else (values requested #f)]))

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

(define compass-draw-end 3/40)              ; 0.075
(define compass-offset-end 3/16)            ; 0.1875
(define compass-source-attention-end 23/80) ; 0.2875
(define compass-transport-end 11/20)         ; 0.55
(define compass-target-attention-end 13/20) ; 0.65
(define compass-fade-start 0.88)             ; local sweep progress

;; Review samples target semantic reveal progress, not raw timeline progress.
(define compass-review-pickup-progress 0.06)
(define compass-review-source-attention-progress
  (/ (+ compass-offset-end compass-source-attention-end) 2))
(define compass-review-transport-progress
  (/ (+ compass-source-attention-end compass-transport-end) 2))
(define compass-review-target-attention-progress
  (/ (+ compass-transport-end compass-target-attention-end) 2))
(define compass-review-sweep-progress
  (/ (+ compass-target-attention-end 1) 2))

(define (safe-bounds view)
  (define scale (- 1 (* 2 (geometry-view-margin view))))
  (define hw (* 1/2 scale (geometry-view-width view)))
  (define hh (/ hw (geometry-view-aspect view)))
  (define c (geometry-view-center view))
  (values (- (point-x c) hw) (+ (point-x c) hw)
          (- (point-y c) hh) (+ (point-y c) hh)))

(define (overflow value low high)
  (cond [(< value low) (- low value)]
        [(> value high) (- value high)]
        [else 0]))

(define (orientation-score center anchor theta0 r view caption-band)
  ;; Prefer an early sweep that stays well inside the safe frame and above the
  ;; caption band. A small travel penalty keeps the shorter-transport preference
  ;; whenever both orientations are similarly legible.
  (define travel-penalty (* 0.2 (distance anchor center)))
  (cond
    [(not view) (- travel-penalty)]
    [else
     (define-values (xmin xmax ymin ymax) (safe-bounds view))
     (define pad (* 0.04 (geometry-view-width view)))
     (define usable-ymin (+ ymin (max 0 caption-band) (* 0.2 pad)))
     (define penalty
       (for/sum ([q (in-list (list 0 0.08 0.16 0.24 0.32))])
         (define theta (+ theta0 (* 2 pi q)))
         (define p (point+ center (point (* r (cos theta)) (* r (sin theta)))))
         (define ox (overflow (point-x p) (+ xmin pad) (- xmax pad)))
         (define oy (overflow (point-y p) usable-ymin (- ymax pad)))
         (+ (* 8 (sqr ox)) (* 12 (sqr oy)))))
     (- 0 penalty travel-penalty)]))

(define (choose-compass-carrier center r source-a source-b [view #f] [caption-band 0])
  (define (candidate anchor tip)
    (define vector (point- tip anchor))
    (values anchor tip vector
            (orientation-score center anchor
                               (atan (point-y vector) (point-x vector))
                               r view caption-band)))
  (define-values (anchor-1 tip-1 vector-1 score-1) (candidate source-a source-b))
  (define-values (anchor-2 tip-2 vector-2 score-2) (candidate source-b source-a))
  (if (> score-2 score-1)
      (values anchor-2 tip-2 vector-2)
      (values anchor-1 tip-1 vector-1)))

(define (carrier-offset-distance r view)
  ;; A visible but modest lift: roughly 18% of the copied measure, with a
  ;; view-relative floor/ceiling so very short or very long measures still read.
  (if view
      (let ([w (geometry-view-width view)])
        (max (* 0.015 w) (min (* 0.035 w) (* 0.18 r))))
      (* 0.18 r)))

(define (carrier-offset-score anchor tip offset center view caption-band)
  ;; Prefer a parallel lift that stays in the usable frame, away from the
  ;; caption band, and does not gratuitously lengthen the following transport.
  (define a (point+ anchor offset))
  (define b (point+ tip offset))
  (define midpoint* (midpoint a b))
  (define travel (* 0.08 (distance a center)))
  (cond
    [(not view) (- travel)]
    [else
     (define-values (xmin xmax ymin ymax) (safe-bounds view))
     (define pad (* 0.025 (geometry-view-width view)))
     (define usable-ymin (+ ymin (max 0 caption-band) (* 0.25 pad)))
     (define penalty
       (for/sum ([p (in-list (list a midpoint* b))])
         (+ (* 14 (sqr (overflow (point-x p) (+ xmin pad) (- xmax pad))))
            (* 18 (sqr (overflow (point-y p) usable-ymin (- ymax pad)))))))
     (- 0 penalty travel)]))

(define (choose-carrier-offset anchor tip source-vector center r view caption-band)
  (define n (norm source-vector))
  (define unit-normal
    (point (/ (- (point-y source-vector)) n)
           (/ (point-x source-vector) n)))
  (define d (carrier-offset-distance r view))
  (define plus (point* unit-normal d))
  (define minus (point* unit-normal (- d)))
  (if (> (carrier-offset-score anchor tip minus center view caption-band)
         (carrier-offset-score anchor tip plus center view caption-band))
      minus
      plus))

(define (pulse q)
  ;; Same single-pulse rhythm used by attention effects: zero at the boundaries,
  ;; strongest in the middle. The native adapter renders it as a soft halo.
  (define u (unit q))
  (sqr (sin (* pi u))))

;; compass-circle-reveal : circle? compass-source? real? -> compass-reveal-state?
;;
;; The temporary carrier is deliberately more explicit than the mathematical
;; Circle node. It is a presentation-only copy of the source measure:
;;
;;  1. draw the movable segment directly over the source;
;;  2. lift it a small distance onto a parallel line;
;;  3. pulse a glow to signal that the copied length is now movable;
;;  4. transport it rigidly to the new circle centre;
;;  5. pulse the glow again after arrival; and
;;  6. rotate it counterclockwise while its free endpoint traces the circle.
;;
;; All phases are random-access functions of progress; no mutable per-frame state
;; is introduced. The guide fades only near the end of the final sweep.
(define (compass-circle-reveal circle source progress #:view [view #f] #:caption-band [caption-band 0])
  (unless (and (circle? circle) (compass-source? source) (finite-real? progress)
               (or (not view) (geometry-view? view))
               (finite-real? caption-band) (>= caption-band 0))
    (geometry-error 'compass-circle-reveal
                    "expected a circle, compass source, finite progress, optional view and nonnegative caption band"))
  (define center (circle-center circle))
  (define r (circle-radius circle))
  (define source-a (compass-source-a source))
  (define source-b (compass-source-b source))
  (define-values (anchor tip source-vector)
    (choose-compass-carrier center r source-a source-b view caption-band))
  (define source-length (norm source-vector))
  (unless (<= (abs (- source-length r)) (* 1e-8 (max 1 source-length r)))
    (geometry-error 'compass-circle-reveal
                    "source measure ~a does not match circle radius ~a" source-length r))
  (define offset
    (choose-carrier-offset anchor tip source-vector center r view caption-band))
  (define lifted-anchor (point+ anchor offset))
  (define lifted-tip (point+ tip offset))
  (define p (unit progress))
  (cond
    [(zero? p) (compass-reveal-state '() '() 0 0)]
    [(<= p compass-draw-end)
     (define q (/ p compass-draw-end))
     (define guide (polyline-prefix (list anchor tip) q))
     (compass-reveal-state '() (if (>= (length guide) 2) (list guide) '()) 1 0)]
    [(<= p compass-offset-end)
     (define q (smooth (/ (- p compass-draw-end)
                          (- compass-offset-end compass-draw-end))))
     (define delta (point* offset q))
     (compass-reveal-state
      '() (list (list (point+ anchor delta) (point+ tip delta))) 1 0)]
    [(<= p compass-source-attention-end)
     (define q (/ (- p compass-offset-end)
                  (- compass-source-attention-end compass-offset-end)))
     (compass-reveal-state '() (list (list lifted-anchor lifted-tip)) 1 (pulse q))]
    [(<= p compass-transport-end)
     (define q (smooth (/ (- p compass-source-attention-end)
                          (- compass-transport-end compass-source-attention-end))))
     (define delta (point* (point- center lifted-anchor) q))
     (compass-reveal-state
      '()
      (list (list (point+ lifted-anchor delta) (point+ lifted-tip delta)))
      1 0)]
    [(<= p compass-target-attention-end)
     (define q (/ (- p compass-transport-end)
                  (- compass-target-attention-end compass-transport-end)))
     (compass-reveal-state
      '() (list (list center (point+ center source-vector))) 1 (pulse q))]
    [else
     (define q (unit (/ (- p compass-target-attention-end)
                        (- 1 compass-target-attention-end))))
     (define theta0 (atan (point-y source-vector) (point-x source-vector)))
     (define theta (+ theta0 (* 2 pi q)))
     (define moving-tip
       (point+ center (point (* r (cos theta)) (* r (sin theta)))))
     (define circle-strokes
       (if (zero? q) '()
           (list (reveal-arc center r theta0 (* 2 pi q) (= q 1)))))
     (define guide-opacity
       (if (<= q compass-fade-start) 1
           (- 1 (unit (/ (- q compass-fade-start) (- 1 compass-fade-start))))))
     (compass-reveal-state circle-strokes (list (list center moving-tip)) guide-opacity 0)]))

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
       [(counterclockwise fade compass) (list (reveal-arc center r theta (* 2 pi p) (= p 1)))]
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
