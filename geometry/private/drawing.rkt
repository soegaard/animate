#lang racket/base

;; Pure preparation of visible polylines and stable label anchors. The final
;; solid circle path uses native cubic Beziers in the animate adapter instead.
(require racket/list (only-in racket/math pi)
         "math.rkt" "data.rkt" "../layout.rkt" "../theme.rkt")
(provide curve-polyline clipped-polylines dash-polylines label-positions
         object-style-overrides display-label)

(define (object-style-overrides program id)
  (append-map cdr (filter (lambda (s) (eq? (car s) id)) (geometry-program-styles program))))
(define (display-label id)
  ;; Helper-local identifiers remain unique internally; viewers see just C, D,
  ;; etc. The two copies can have their labels suppressed independently.
  (define parts (regexp-split #rx"/" (symbol->string id)))
  (last parts))
(define (curve-polyline value view progress)
  (define p (max 0 (min 1 progress)))
  (cond [(zero? p) '()]
        [(circle? value) (circle-points value p)]
        [else
         (define-values (xmin xmax ymin ymax) (view-bounds view))
         (define ends (clip-linear value xmin xmax ymin ymax))
         (cond [(null? ends) '()]
               [(or (segment? value) (ray? value))
                (list (car ends) (interpolate-point (car ends) (cadr ends) p))]
               [else
                ;; A line grows from its defining pair rather than appearing
                ;; to originate at an arbitrary off-screen infinity.
                (define a (curve-start value))
                (define b (curve-end value))
                (define mid (midpoint a b))
                (list (interpolate-point mid (car ends) p)
                      (interpolate-point mid (cadr ends) p))])]))

;; Clip consecutive polyline edges and rejoin consecutive retained pieces.
(define (clipped-polylines points view)
  (define-values (xmin xmax ymin ymax) (view-bounds view))
  (define runs '())
  (define run '())
  (define (finish!)
    (when (>= (length run) 2) (set! runs (cons (reverse run) runs)))
    (set! run '()))
  (for ([p (in-list points)] [q (in-list (if (null? points) '() (cdr points)))])
    (define ends (if (distinct? p q) (clip-linear (segment p q) xmin xmax ymin ymax) '()))
    (cond [(or (null? ends) (not (distinct? (car ends) (cadr ends)))) (finish!)]
          [(and (pair? run) (same-point? (car run) (car ends) (geometry-view-width view)))
           (set! run (cons (cadr ends) run))]
          [else (finish!) (set! run (list (cadr ends) (car ends)))]))
  (finish!)
  (reverse runs))

;; dash-polylines : point-list dash-pattern world-per-cosmetic-unit -> polylines
;; Pattern distances are cosmetic backend lengths, converted at the explicitly
;; supplied camera. Alternating on/off runs preserve phase across all edges.
(define (dash-polylines points pattern world-per-unit)
  (cond [(or (null? points) (null? (cdr points))) '()]
        [(eq? pattern 'solid) (list points)]
        [else
         (define lengths (map (lambda (x) (* world-per-unit x)) pattern))
         (define index 0)
         (define remaining (car lengths))
         (define runs '())
         (define run '())
         (define (finish!)
           (when (>= (length run) 2) (set! runs (cons (reverse run) runs)))
           (set! run '()))
         (for ([a (in-list points)] [b (in-list (cdr points))])
           (let walk ([p a])
             (define edge-length (distance p b))
             (when (> edge-length 1e-12)
               (define amount (min edge-length remaining))
               (define q (interpolate-point p b (/ amount edge-length)))
               (when (even? index)
                 (when (null? run) (set! run (list p)))
                 (set! run (cons q run)))
               (set! remaining (- remaining amount))
               (when (<= remaining 1e-12)
                 (finish!)
                 (set! index (modulo (add1 index) (length lengths)))
                 (set! remaining (list-ref lengths index)))
               (when (< amount edge-length) (walk q)))))
         (finish!)
         (reverse runs)]))

(define (distance-to-curve p c)
  (cond [(circle? c) (abs (- (distance p (circle-center c)) (circle-radius c)))]
        [else
         (define a (curve-start c))
         (define v (point- (curve-end c) a))
         (define t (/ (dot (point- p a) v) (dot v v)))
         (define u (cond [(segment? c) (max 0 (min 1 t))] [(ray? c) (max 0 t)] [else t]))
         (distance p (point+ a (point* v u)))]))

;; Label placement is solved once against the complete relevant diagram. It is
;; an eight-direction heuristic with approximate font boxes, not a font-metric
;; solver. A label may be explicitly placed via the adapter's #:labels hash.
(define (label-positions realization theme #:labels [overrides (hash)])
  (define program (geometry-realization-program realization))
  (define env (geometry-realization-values realization))
  (define view (geometry-realization-view realization))
  (define ids (construction-visible-ids program))
  (define visible-values (for/list ([id (in-list ids)]) (hash-ref env id)))
  (define curves (filter curve? visible-values))
  (define (label-targets action)
    (case (geometry-action-kind action)
      [(show-label) (geometry-action-targets action)]
      [(together) (append-map label-targets (geometry-action-payload action))]
      [(expanded) (append-map (lambda (s) (append-map label-targets (geometry-step-actions s)))
                              (geometry-action-payload action))]
      [else '()]))
  (define named-labels
    (append (append-map label-targets (geometry-program-initial program))
            (append-map (lambda (s) (append-map label-targets (geometry-step-actions s)))
                        (geometry-program-steps program))))
  (define (anchor value)
    (cond [(point? value) value]
          [(marker? value) (if (null? (marker-anchor-points value)) (point 0 0) (car (marker-anchor-points value)))]
          [(circle? value) (circle-through value)]
          [(segment? value) (midpoint (segment-a value) (segment-b value))]
          [(ray? value) (ray-a value)]
          [else
           (define-values (xmin xmax ymin ymax) (view-bounds view))
           (define ends (clip-linear value xmin xmax ymin ymax))
           (if (null? ends) (midpoint (curve-start value) (curve-end value))
               (midpoint (car ends) (cadr ends)))]))
  (define points (filter point? visible-values))
  (define boxes '())
  (define (overlap? a b)
    (and (< (list-ref a 0) (list-ref b 1)) (< (list-ref b 0) (list-ref a 1))
         (< (list-ref a 2) (list-ref b 3)) (< (list-ref b 2) (list-ref a 3))))
  (unless (hash? overrides) (geometry-error 'label-positions "#:labels must be a hash"))
  (for ([(id p) (in-hash overrides)])
    (unless (and (hash-has-key? env id) (or (point? (hash-ref env id)) (curve? (hash-ref env id))) (point? p))
      (geometry-error 'label-positions "label override must name geometry and supply a point: ~a" id)))
  (for/hash ([node (in-list (geometry-program-nodes program))]
             #:when (and (memq (geometry-node-id node) ids)
                         (or (eq? (geometry-node-type node) 'Point)
                             (memq (geometry-node-id node) named-labels))))
    (define id (geometry-node-id node))
    (define p (anchor (hash-ref env id)))
    (define style (resolve-geometry-style theme (geometry-node-type node) 'normal (object-style-overrides program id)))
    (define size (hash-ref style 'font-size))
    (define half-width (* 0.34 size (max 1 (string-length (display-label id)))))
    (define half-height (* 0.6 size))
    (define offset (+ (hash-ref style 'radius) (hash-ref style 'offset) half-height))
    (define (box q) (list (- (point-x q) half-width) (+ (point-x q) half-width)
                         (- (point-y q) half-height) (+ (point-y q) half-height)))
    (define candidates
      (for/list ([angle (in-list (list (* pi 1/4) (* pi 3/4) (* pi 7/4) (* pi 5/4)
                                     0 pi (* pi 1/2) (* pi 3/2)))])
        (point+ p (point (* offset (cos angle)) (* offset (sin angle))))))
    (define (cost q)
      (+ (if (point-in-view? q view (max half-width half-height)) 0 10000)
         (* 1000 (count (lambda (b) (overlap? b (box q))) boxes))
         (for/sum ([x (in-list points)]) (/ 0.04 (+ 0.001 (sqr (distance q x)))))
         (for/sum ([c (in-list curves)]) (/ 0.02 (+ 0.003 (sqr (distance-to-curve q c)))))))
    (define selected (hash-ref overrides id (lambda () (argmin cost candidates))))
    (set! boxes (cons (box selected) boxes))
    (values id selected)))
(define (sqr x) (* x x))
