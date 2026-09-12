#lang racket/base

;; Deterministic whole-timeline label/marker placement. The pure core uses
;; conservative font boxes; the Animate adapter supplies its real text metrics.
;; Layout considers co-visibility, not invisible geometry from another gallery
;; plate. It never runs while sampling a frame.
(require racket/list (only-in racket/math pi)
         "private/math.rkt" "private/data.rkt" "private/drawing.rkt"
         "private/reveal.rkt" "private/marker-shapes.rkt" "theme.rkt" "layout.rkt")
(provide (struct-out annotation-plan) prepare-geometry-annotations
         geometry-visibility-masks annotation-hints annotation-text
         allocate-marker-counts)
(struct annotation-plan (labels marker-placements marker-counts texts label-boxes warnings metrics) #:transparent)
(struct candidate (value boxes edges preference) #:transparent)
(define hint-keys '(label-side label-at label-text marker-quadrant marker-position marker-radius))
(define (annotation-hints program id)
  (for/fold ([h (hash)]) ([rule (in-list (geometry-program-layout program))]
                        #:when (and (memq (car rule) hint-keys) (eq? (cadr rule) id)))
    (define v (caddr rule))
    (hash-set h (car rule)
              (case (car rule) [(label-side) (cadr v)]
                [(label-at) (apply point (cdr v))] [else v]))))
(define (annotation-text program id)
  (hash-ref (annotation-hints program id) 'label-text (lambda () (display-label id))))
(define (geometry-visibility-masks timeline)
  (define object-masks (hash)) (define label-masks (hash))
  (define snapshots
    (append (list (list (geometry-timeline-initial timeline)))
            (for/list ([event (in-list (geometry-timeline-events timeline))])
              (list (geometry-event-before event) (geometry-event-after event)))
            (list (list (geometry-timeline-final timeline)))))
  (for ([states (in-list snapshots)] [index (in-naturals)])
    (define bit (arithmetic-shift 1 index))
    (for ([state (in-list states)])
      (for ([(id p) (in-hash state)] #:when (presentation-shown? p))
        (set! object-masks (hash-set object-masks id (bitwise-ior bit (hash-ref object-masks id 0))))
        (when (presentation-label? p)
          (set! label-masks (hash-set label-masks id (bitwise-ior bit (hash-ref label-masks id 0))))))))
  (values object-masks label-masks))
(define (overlap-time? a b) (not (zero? (bitwise-and a b))))
(define (same-direction? u v)
  (define scale (* (norm u) (norm v)))
  (and (> scale 0) (> (dot u v) 0) (<= (abs (cross u v)) (* 1e-9 scale))))
(define (same-member? a b)
  (cond [(and (segment? a) (segment? b))
         (or (equal? a b) (and (equal? (segment-a a) (segment-b b))
                               (equal? (segment-b a) (segment-a b))))]
        [(and (angle-spec? a) (angle-spec? b))
         (define vertex (angle-spec-b a))
         (define other (angle-spec-b b))
         (define u (point- (angle-spec-a a) vertex))
         (define v (point- (angle-spec-c a) vertex))
         (define x (point- (angle-spec-a b) other))
         (define y (point- (angle-spec-c b) other))
         (and (equal? vertex other)
              (or (and (same-direction? u x) (same-direction? v y))
                  (and (same-direction? u y) (same-direction? v x))))]
        [(and (line? a) (line? b))
         (and (on (line-a a) b) (on (line-b a) b))]
        [else (equal? a b)]))
(define (allocate-marker-counts nodes env masks)
  (define marked (filter (lambda (n) (and (eq? (geometry-node-type n) 'Marker)
                                          (hash-has-key? masks (geometry-node-id n))
                                          (marker-family (hash-ref env (geometry-node-id n))))) nodes))
  (define ids (map geometry-node-id marked))
  (define (connected? a b)
    (define va (hash-ref env a)) (define vb (hash-ref env b))
    (and (eq? (marker-family va) (marker-family vb))
         (ormap (lambda (member-a) (member member-a (marker-members vb) same-member?))
                (marker-members va))))
  ;; Connected components preserve source order; aliases/overlapping equality
  ;; declarations cannot accidentally receive conflicting notation.
  (define groups
    (let loop ([left ids] [groups '()])
      (if (null? left) (reverse groups)
          (let grow ([group (list (car left))] [remaining (cdr left)])
            (define added (filter (lambda (id) (ormap (lambda (other) (connected? id other)) group)) remaining))
            (if (null? added)
                (loop remaining (cons group groups))
                (grow (append group added) (filter (lambda (id) (not (memq id added))) remaining)))))))
  (define chosen '()) (define table (hash))
  (for ([group (in-list groups)])
    (define family (marker-family (hash-ref env (car group))))
    (define mask (for/fold ([mask 0]) ([id (in-list group)]) (bitwise-ior mask (hash-ref masks id 0))))
    (define forbidden
      (for/list ([old (in-list chosen)] #:when (and (eq? family (car old)) (overlap-time? mask (cadr old))))
        (caddr old)))
    ;; A single angle arc is an indicator, not a fresh inequality class.
    ;; If connected to an equality group it inherits that group's pattern.
    (define equality-group? (ormap (lambda (id) (not (angle-marker? (hash-ref env id)))) group))
    (define count (if equality-group?
                       (let loop ([n 1]) (if (memq n forbidden) (loop (add1 n)) n))
                       1))
    (when equality-group? (set! chosen (cons (list family mask count) chosen)))
    (for ([id (in-list group)]) (set! table (hash-set table id count))))
  table)

;; Rectangles are (xmin xmax ymin ymax), in world units.
(define (box p hw hh)
  (list (- (point-x p) hw) (+ (point-x p) hw) (- (point-y p) hh) (+ (point-y p) hh)))
(define (expand-box b d)
  (list (- (car b) d) (+ (cadr b) d) (- (caddr b) d) (+ (cadddr b) d)))
(define (box-overlap? a b)
  (and (< (car a) (cadr b)) (< (car b) (cadr a))
       (< (caddr a) (cadddr b)) (< (caddr b) (cadddr a))))
(define (box-contains? outer inner)
  (and (<= (car outer) (car inner)) (<= (cadr inner) (cadr outer))
       (<= (caddr outer) (caddr inner)) (<= (cadddr inner) (cadddr outer))))
(define (curve-crosses-box? c b)
  (cond [(circle? c)
         (define center (circle-center c)) (define r (circle-radius c))
         (define near (point (max (car b) (min (cadr b) (point-x center)))
                             (max (caddr b) (min (cadddr b) (point-y center)))))
         (define far-distance
           (apply max (for*/list ([x (in-list (take b 2))] [y (in-list (drop b 2))])
                        (distance center (point x y)))))
         (and (<= (distance center near) r) (>= far-distance r))]
        [else (pair? (clip-linear c (car b) (cadr b) (caddr b) (cadddr b)))]))
(define (edge-box e gap)
  (define a (car e)) (define b (cadr e))
  (list (- (min (point-x a) (point-x b)) gap) (+ (max (point-x a) (point-x b)) gap)
        (- (min (point-y a) (point-y b)) gap) (+ (max (point-y a) (point-y b)) gap)))
(define (strokes->edges strokes)
  (append-map
   (lambda (stroke)
     (define ps (reveal-stroke-points stroke))
     (for/list ([a (in-list ps)] [b (in-list (if (null? ps) '() (cdr ps)))] #:when (distinct? a b))
       (list a b))) strokes))
(define (candidate-overlap? a b gap)
  (cond
    [(and (null? (candidate-edges a)) (null? (candidate-edges b)))
     (for*/or ([x (in-list (candidate-boxes a))] [y (in-list (candidate-boxes b))])
       (box-overlap? (expand-box x gap) y))]
    [(null? (candidate-edges a))
     (for*/or ([x (in-list (candidate-boxes a))] [e (in-list (candidate-edges b))])
       (curve-crosses-box? (segment (car e) (cadr e)) (expand-box x gap)))]
    [(null? (candidate-edges b)) (candidate-overlap? b a gap)]
    [else
     (for*/or ([ea (in-list (candidate-edges a))] [eb (in-list (candidate-edges b))])
       ;; Conservative stroke rectangles: no expensive or unstable exact solver.
       (and (box-overlap? (edge-box ea gap) (edge-box eb gap))
            (curve-crosses-box? (segment (car ea) (cadr ea)) (edge-box eb gap))))]))
(define sides
  (list (cons 'above (point 0 1)) (cons 'below (point 0 -1))
        (cons 'left (point -1 0)) (cons 'right (point 1 0))
        (cons 'above-right (point (sqrt 0.5) (sqrt 0.5)))
        (cons 'above-left (point (- (sqrt 0.5)) (sqrt 0.5)))
        (cons 'below-right (point (sqrt 0.5) (- (sqrt 0.5))))
        (cons 'below-left (point (- (sqrt 0.5)) (- (sqrt 0.5))))))
(define (fallback-measure text style)
  (values (* 0.72 (hash-ref style 'font-size) (max 1 (string-length text)))
          (* 1.25 (hash-ref style 'font-size))))

(define (prepare-geometry-annotations timeline #:labels [overrides (hash)]
                                      #:measure-label [measure fallback-measure]
                                      #:metrics [metrics 'estimated]
                                      #:caption-height [caption-height 0]
                                      #:world-per-pixel [world-per-pixel 0.01])
  (unless (and (geometry-timeline? timeline) (hash? overrides) (procedure? measure)
               (finite-real? caption-height) (>= caption-height 0)
               (finite-real? world-per-pixel) (> world-per-pixel 0))
    (geometry-error 'prepare-geometry-annotations "invalid timeline, labels, measurer or dimensions"))
  (define realization (geometry-timeline-realization timeline))
  (define program (geometry-realization-program realization))
  (define theme (geometry-timeline-theme timeline))
  (define env (geometry-realization-values realization))
  (define view (geometry-realization-view realization))
  (define-values (masks label-masks) (geometry-visibility-masks timeline))
  (define nodes (filter (lambda (n) (and (hash-has-key? masks (geometry-node-id n))
                                        (memq (geometry-node-type n) '(Point Segment Ray Line Circle Marker))))
                        (geometry-program-nodes program)))
  (define ids (map geometry-node-id nodes))
  (define marker-ids (filter (lambda (id) (marker? (hash-ref env id))) ids))
  (define label-ids (filter (lambda (id) (hash-has-key? label-masks id)) ids))
  (for ([(id pos) (in-hash overrides)])
    (unless (and (hash-has-key? env id) (point? pos)
                 (let ([v (hash-ref env id)]) (or (point? v) (curve? v) (marker? v))))
      (geometry-error 'prepare-geometry-annotations "label override needs a drawable name and point: ~e" id)))
  (define hints (for/hash ([id (in-list ids)]) (values id (annotation-hints program id))))
  (define texts (for/hash ([id (in-list label-ids)]) (values id (annotation-text program id))))
  (define styles
    (for/hash ([n (in-list nodes)])
      (define id (geometry-node-id n))
      (define v (hash-ref env id))
      (define kind (if (marker? v) (marker-style-type v) (geometry-node-type n)))
      (define local (object-style-overrides program id))
      (values id (list (resolve-geometry-style theme kind 'normal local)
                      (resolve-geometry-style theme kind 'deemphasized local)
                      (resolve-geometry-style theme kind 'normal local #:highlight? #t)
                      (resolve-geometry-style theme kind 'deemphasized local #:highlight? #t)))))
  (define (style id) (car (hash-ref styles id)))
  (define counts (allocate-marker-counts nodes env masks))
  (define-values (xmin xmax ymin ymax) (view-bounds view #t))
  (define-values (_x0 _x1 view-ymin _y1) (view-bounds view))
  (define safe (list xmin xmax (max ymin (+ view-ymin caption-height)) ymax))
  (define gap (max 0.035 (* 2 world-per-pixel)))
  (define dimensions
    (for/hash ([id (in-list label-ids)])
      (define sizes
        (for/list ([s (in-list (hash-ref styles id))])
          (define-values (w h) (measure (hash-ref texts id) s))
          (unless (and (finite-real? w) (finite-real? h) (>= w 0) (> h 0))
            (geometry-error 'prepare-geometry-annotations "invalid measured label extent for ~a" id))
          ;; A small ink margin protects italic overhang and antialiasing.
          (cons (+ w (* 2 gap)) (+ h gap))))
      (values id (cons (/ (apply max (map car sizes)) 2) (/ (apply max (map cdr sizes)) 2)))))
  (define placements (hash))
  (define selection (hash))
  (define marker-candidates
    (for/hash ([id (in-list marker-ids)])
      (define value (hash-ref env id)) (define h (hash-ref hints id))
      (when (and (hash-has-key? h 'marker-quadrant) (not (perpendicular-marker? value)))
        (geometry-error 'marker-layout "marker-quadrant requires a right-angle marker: ~a" id))
      (when (and (hash-has-key? h 'marker-position) (not (memq (marker-family value) '(length parallel))))
        (geometry-error 'marker-layout "marker-position requires ticks or parallel arrows: ~a" id))
      (when (and (hash-has-key? h 'marker-radius) (not (eq? (marker-family value) 'angle)))
        (geometry-error 'marker-layout "marker-radius requires an angle marker: ~a" id))
      (define candidates
        (for/list ([p (in-list (marker-placement-candidates value (style id) view h))] [rank (in-naturals)])
          ;; Reserve the union of normal and highlighted dimensions, without
          ;; changing the actual right-angle size to solve a collision.
          (define edges
            (append-map (lambda (s) (strokes->edges (marker-strokes value s p (hash-ref counts id 1) view)))
                        (hash-ref styles id)))
          (candidate p (map (lambda (edge) (edge-box edge gap)) edges) edges (* 0.02 rank))))
      (set! placements (hash-set placements id (candidate-value (car candidates))))
      (values id candidates)))
  (define (label-anchor id)
    (define value (hash-ref env id))
    (cond [(point? value) value]
          [(marker? value) (marker-label-anchor value (style id) (hash-ref placements id)
                                                (hash-ref counts id 1) view)]
          [(circle? value) (circle-through value)]
          [(segment? value) (midpoint (segment-a value) (segment-b value))]
          [(ray? value) (ray-a value)]
          [else
           (define-values (x0 x1 y0 y1) (view-bounds view))
           (define ends (clip-linear value x0 x1 y0 y1))
           (if (null? ends) (midpoint (curve-start value) (curve-end value))
               (midpoint (car ends) (cadr ends)))]))
  (define (label-candidates id)
    (define s (style id)) (define h (hash-ref hints id))
    (define anchor (label-anchor id))
    (define size (hash-ref dimensions id)) (define hw (car size)) (define hh (cdr size))
    (define pin (hash-ref overrides id (hash-ref h 'label-at #f)))
    (cond [pin (list (candidate pin (list (box pin hw hh)) '() 0))]
          [(and (marker? (hash-ref env id))
                (eq? (marker-family (hash-ref env id)) 'angle)
                (eq? (hash-ref h 'label-side 'auto) 'auto))
           ;; The label of an angle must stay in that angular sector. Generic
           ;; compass directions can put alpha on the other side of the vertex.
           ;; Move radially along the bisector; pins/explicit side hints remain
           ;; escape hatches. Reserve enough room for the measured ink box.
           (define spec (car (marker-members (hash-ref env id))))
           (define vertex (angle-spec-b spec))
           (define offset (point- anchor vertex))
           (define radial (norm offset))
           (define direction (point* offset (/ 1 radial)))
           (define support (+ (* (abs (point-x direction)) hw) (* (abs (point-y direction)) hh)))
           (for/list ([ring (in-list '(1 1.6 2.3 3.5 5))])
             (define pos (point+ vertex (point* direction (+ radial support (* ring (max gap (hash-ref s 'offset)))))))
             (candidate pos (list (box pos hw hh)) '() (* 0.1 (sub1 ring))))]
          [else
           (define side (hash-ref h 'label-side 'auto))
           (define point-radius (if (point? (hash-ref env id))
                                    (apply max (map (lambda (s) (hash-ref s 'radius)) (hash-ref styles id))) 0))
           (for*/list ([ring (in-list '(1 1.6 2.3))] [sd (in-list sides)])
             (define d (cdr sd))
             (define support (+ (* (abs (point-x d)) hw) (* (abs (point-y d)) hh)))
             (define amount (+ support point-radius (* ring (max gap (hash-ref s 'offset)))))
             (define pos (point+ anchor (point* d amount)))
             (candidate pos (list (box pos hw hh)) '()
                        (+ (* 0.1 (sub1 ring))
                           (if (or (eq? side 'auto) (eq? side (car sd))) 0 150))))]))
  (define (mask key)
    (hash-ref (if (eq? (car key) 'label) label-masks masks) (cdr key) 0))
  (define (cost key c)
    (define id (cdr key))
    (define label? (eq? (car key) 'label))
    (define temporal (mask key))
    (define final-state (geometry-timeline-final timeline))
    (define (in-final? object)
      (define p (hash-ref final-state object #f))
      (and p (presentation-shown? p)))
    (+ (candidate-preference c)
       (* 100000 (count (lambda (b) (not (box-contains? safe b))) (candidate-boxes c)))
       (for/sum ([(other chosen) (in-hash selection)]
                  #:when (and (not (equal? key other)) (overlap-time? temporal (mask other))))
         (if (candidate-overlap? c chosen gap) 10000 0))
       (for/sum ([other (in-list ids)]
                  #:when (and (or label? (not (eq? id other))) (overlap-time? temporal (hash-ref masks other 0))))
         (define value (hash-ref env other))
         (cond [(point? value)
                (define radius (apply max (map (lambda (s) (hash-ref s 'radius)) (hash-ref styles other))))
                (define other-box (box value (+ radius gap) (+ radius gap)))
                (if (ormap (lambda (b) (box-overlap? b other-box)) (candidate-boxes c)) 3000 0)]
               [(and label? (curve? value))
                (define padding (+ gap (* 0.5 world-per-pixel (hash-ref (style other) 'stroke-width))))
                (if (ormap (lambda (b) (curve-crosses-box? value (expand-box b padding))) (candidate-boxes c))
                    ;; Do not spoil the final diagram merely to avoid a
                    ;; short-lived construction circle. Final curves still
                    ;; outrank a preferred label direction.
                    (if (and (in-final? id) (in-final? other)) 1000 100)
                    0)]
               [else 0]))))
  (define (choose! key cs)
    (define best (argmin (lambda (c) (cost key c)) cs))
    (set! selection (hash-set selection key best))
    (when (eq? (car key) 'marker)
      (set! placements (hash-set placements (cdr key) (candidate-value best)))))
  ;; Register explicit label pins first, so square quadrants/other labels avoid
  ;; them rather than asking the author to move a fixed annotation.
  (for ([id (in-list label-ids)] #:when (or (hash-has-key? overrides id) (hash-has-key? (hash-ref hints id) 'label-at)))
    (choose! (cons 'label id) (label-candidates id)))
  (for ([pass (in-range 3)])
    (for ([id (in-list marker-ids)]) (choose! (cons 'marker id) (hash-ref marker-candidates id)))
    (for ([id (in-list label-ids)]) (choose! (cons 'label id) (label-candidates id))))
  (define labels (for/hash ([id (in-list label-ids)])
                   (values id (candidate-value (hash-ref selection (cons 'label id))))))
  (define boxes (for/hash ([id (in-list label-ids)])
                  (values id (car (candidate-boxes (hash-ref selection (cons 'label id)))))))
  (define keys (append (map (lambda (id) (cons 'marker id)) marker-ids)
                       (map (lambda (id) (cons 'label id)) label-ids)))
  (define warnings
    (append
     (for/list ([key (in-list keys)]
                #:when (ormap (lambda (b) (not (box-contains? safe b))) (candidate-boxes (hash-ref selection key))))
       (list 'outside-safe-area key))
     (for*/list ([i (in-range (length keys))] [j (in-range (add1 i) (length keys))]
                  #:when (let ([a (list-ref keys i)] [b (list-ref keys j)])
                           (and (overlap-time? (mask a) (mask b))
                                (candidate-overlap? (hash-ref selection a) (hash-ref selection b) gap))))
       (list 'annotation-overlap (list-ref keys i) (list-ref keys j)))
     (for*/list ([id (in-list label-ids)] [other (in-list ids)]
                  #:when
                  (and (overlap-time? (hash-ref label-masks id 0) (hash-ref masks other 0))
                       (let ([value (hash-ref env other)] [b (hash-ref boxes id)])
                         (cond [(point? value)
                                (box-overlap? b (box value (+ gap (hash-ref (style other) 'radius))
                                                       (+ gap (hash-ref (style other) 'radius))))]
                               [(curve? value) (curve-crosses-box? value (expand-box b gap))]
                               [else #f]))))
       (list 'label-geometry-overlap id other))))
  (annotation-plan labels placements counts texts boxes warnings metrics))
