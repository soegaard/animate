#lang racket/base

;; Whole-construction deterministic realization and semantic-anchor fitting.
;; This is deliberately a finite candidate search, not a complete solver.
(require racket/list racket/match (only-in racket/math pi)
         "private/math.rkt" "private/data.rkt" "private/compiler.rkt"
         "private/evaluate.rkt")
(provide make-geometry-view realize-construction construction-ref
         construction-dependencies construction-visible-ids
         realization-anchor-points view-bounds point-in-view?)

(define (make-geometry-view #:center [center (point 0 0)] #:world-width [width 12]
                           #:aspect [aspect (/ 16 9)] #:margin [margin 0.1])
  (unless (and (point? center) (finite-real? width) (> width 0)
               (finite-real? aspect) (> aspect 0)
               (finite-real? margin) (<= 0 margin) (< margin 0.45))
    (geometry-error 'make-geometry-view "invalid centre, width, aspect or margin"))
  (geometry-view center width aspect margin))
(define (view-bounds v [safe? #f])
  (define scale (if safe? (- 1 (* 2 (geometry-view-margin v))) 1))
  (define hw (* 1/2 scale (geometry-view-width v)))
  (define hh (/ hw (geometry-view-aspect v)))
  (define c (geometry-view-center v))
  (values (- (point-x c) hw) (+ (point-x c) hw) (- (point-y c) hh) (+ (point-y c) hh)))
(define (point-in-view? p view [padding 0])
  (define-values (xmin xmax ymin ymax) (view-bounds view #t))
  (and (<= (+ xmin padding) (point-x p) (- xmax padding))
       (<= (+ ymin padding) (point-y p) (- ymax padding))))
(define (construction-ref realization id)
  (hash-ref (geometry-realization-values realization) id
            (lambda () (geometry-error 'construction-ref "no geometry named ~a" id))))
(define (construction-dependencies program)
  (for/hash ([n (in-list (geometry-program-nodes program))])
    (values (geometry-node-id n) (expression-references (geometry-node-expression n)))))

;; Important geometry is that shown at any time, not just in the final frame.
(define (construction-visible-ids program)
  (define initial-ids
    (for/list ([n (in-list (geometry-program-nodes program))] #:when (geometry-node-given? n))
      (geometry-node-id n)))
  (define initial-visible
    (for/fold ([ids initial-ids]) ([a (in-list (geometry-program-initial program))])
      (case (geometry-action-kind a)
        [(hide) (filter (lambda (id) (not (memq id (geometry-action-targets a)))) ids)]
        [(show) (append ids (geometry-action-targets a))]
        [else ids])))
  (define (action-visible a)
    (case (geometry-action-kind a)
      [(reveal show) (geometry-action-targets a)]
      [(together) (append-map action-visible (geometry-action-payload a))]
      [(expanded) (append-map step-visible (geometry-action-payload a))]
      [else '()]))
  (define (step-visible s) (append-map action-visible (geometry-step-actions s)))
  (remove-duplicates (append initial-visible (append-map step-visible (geometry-program-steps program)))))

(define (value-anchors value)
  (cond [(point? value) (list value)]
        [(segment? value) (list (segment-a value) (segment-b value))]
        [(ray? value) (list (ray-a value))]
        [(circle? value) (list (circle-center value) (circle-through value))]
        [(marker? value) (marker-anchor-points value)]
        [else '()]))
(define (anchor-points program environment)
  (define mentioned
    (append (construction-visible-ids program)
            (append-map (lambda (l) (if (memq (car l) '(focus keep-visible)) (cdr l) '()))
                        (geometry-program-layout program))))
  (define points
    (remove-duplicates
     (append-map (lambda (id) (value-anchors (hash-ref environment id))) mentioned) equal?))
  (if (>= (length points) 2) points
      (let ([fallback
             (append-map
              (lambda (id)
                (define value (hash-ref environment id))
                (if (line? value) (list (line-a value) (line-b value)) '())) mentioned)])
        (remove-duplicates (append points fallback (if (and (null? points) (null? fallback))
                                                       (list (point -1 0) (point 1 0)) '())) equal?))))
(define (realization-anchor-points realization)
  (anchor-points (geometry-realization-program realization) (geometry-realization-values realization)))
(define (fit-view points aspect margin padding)
  (define xs (map point-x points))
  (define ys (map point-y points))
  (define xmin (apply min xs)) (define xmax (apply max xs))
  (define ymin (apply min ys)) (define ymax (apply max ys))
  (define width (/ (max 2 (+ (- xmax xmin) (* 2 padding))
                        (* aspect (+ (- ymax ymin) (* 2 padding))))
                   (- 1 (* 2 margin))))
  (make-geometry-view #:center (point (/ (+ xmin xmax) 2) (/ (+ ymin ymax) 2))
                      #:world-width (* width (+ 1 1e-10)) #:aspect aspect #:margin margin))

(define primes '#(2 3 5 7 11 13 17 19 23 29 31 37 41 43 47 53))
(define (halton index dimension)
  (define base (vector-ref primes (modulo dimension (vector-length primes))))
  (let loop ([i (+ index 1)] [f (/ 1 base)] [answer 0])
    (if (zero? i) answer (loop (quotient i base) (/ f base) (+ answer (* f (remainder i base)))))))
(define (sample-domain curve except candidate dimension scale)
  (define h (halton candidate dimension))
  (cond
    [(circle? curve)
     (define theta (* 2 pi (+ h 1/7)))
     (define r (circle-radius curve))
     (point+ (circle-center curve) (point (* r (cos theta)) (* r (sin theta))))]
    [(segment? curve) (interpolate-point (segment-a curve) (segment-b curve) (+ 1/10 (* 4/5 h)))]
    [(ray? curve)
     (define unit (point* (point- (ray-b curve) (ray-a curve))
                          (/ 1 (distance (ray-a curve) (ray-b curve)))))
     (point+ (ray-a curve) (point* unit (* scale (+ 1/20 (* 1/3 h)))))]
    [else
     (define a (line-a curve)) (define b (line-b curve))
     (define unit (point* (point- b a) (/ 1 (distance a b))))
     (define anchor (if (and except (on except curve)) except (midpoint a b)))
     (define direction (if (even? (+ candidate dimension)) -1 1))
     (define amount (if (= candidate 0) (* scale 1/8) (* scale (+ 1/20 (* 1/6 h)))))
     (point+ anchor (point* unit (* direction amount)))]))
(define (domain-data expression environment)
  (define domain (cadr expression))
  (values (evaluate-expression (cadr domain) environment)
          (and (= (length domain) 4) (evaluate-expression (cadddr domain) environment))))
(define (check-choice! value curve except who)
  (unless (and (point? value) (on value curve))
    (geometry-error who "chosen point does not lie on its required curve"))
  (when (and except (same-point? value except
                                 (if (circle? curve) (circle-radius curve)
                                     (distance (curve-start curve) (curve-end curve)))))
    (geometry-error who "chosen point is the excluded point")))

(define (realize-construction program #:view [fixed-view #f]
                             #:aspect [aspect (/ 16 9)] #:margin [margin 0.1]
                             #:padding [padding 0.45] #:samples [samples 256]
                             #:givens [given-values (hash)] #:choices [choice-values (hash)])
  (unless (geometry-program? program) (geometry-error 'realize-construction "expected a geometry-program"))
  (unless (and (exact-positive-integer? samples) (hash? given-values) (hash? choice-values)
               (finite-real? padding) (>= padding 0))
    (geometry-error 'realize-construction "invalid samples, overrides or padding"))
  (define reference-view (or fixed-view (make-geometry-view #:aspect aspect #:margin margin)))
  (unless (geometry-view? reference-view) (geometry-error 'realize-construction "invalid view"))
  (define name (geometry-program-name program))
  (define nodes (geometry-program-nodes program))
  (define node-table (for/hash ([n (in-list nodes)]) (values (geometry-node-id n) n)))
  (for ([(id value) (in-hash given-values)])
    (define n (hash-ref node-table id (lambda () (geometry-error name "unknown given override ~a" id))))
    (unless (geometry-node-given? n) (geometry-error name "~a is not a given" id))
    (unless (eq? (geometry-kind value) (geometry-node-type n)) (geometry-error name "wrong type for given ~a" id)))
  (define pins
    (for/fold ([pins (hash)]) ([l (in-list (geometry-program-layout program))] #:when (eq? (car l) 'pin))
      (when (hash-has-key? pins (cadr l)) (geometry-error name "duplicate pin for ~a" (cadr l)))
      (hash-set pins (cadr l) (apply point (cdaddr l)))))
  (for ([(id value) (in-hash choice-values)])
    (define n (hash-ref node-table id (lambda () (geometry-error name "unknown choice override ~a" id))))
    (unless (and (pair? (geometry-node-expression n)) (eq? (car (geometry-node-expression n)) 'choose))
      (geometry-error name "~a is not a choose binding" id))
    (unless (point? value) (geometry-error name "choice override ~a must be a point" id)))
  (for ([(id value) (in-hash pins)])
    (when (or (hash-has-key? given-values id) (hash-has-key? choice-values id))
      (geometry-error name "~a has both a layout pin and an explicit override" id)))
  (define free-nodes
    (filter (lambda (n) (define e (geometry-node-expression n))
              (and (or (equal? e '(point)) (and (pair? e) (eq? (car e) 'choose)))
                   (not (hash-has-key? pins (geometry-node-id n)))
                   (not (hash-has-key? given-values (geometry-node-id n)))
                   (not (hash-has-key? choice-values (geometry-node-id n))))) nodes))
  (define count (if (null? free-nodes) 1 samples))
  (define rejections (make-hash))
  (define valid-count 0)
  (define best #f)
  (define best-score +inf.0)
  (define best-index #f)
  (define (evaluate-candidate candidate)
    (define environment (hash))
    (define selected (hash))
    (define pending (geometry-program-checks program))
    (define dimension 0)
    (define (check-ready!)
      (set! pending
            (for/list ([c (in-list pending)]
                       #:unless
                       (and (andmap (lambda (id) (hash-has-key? environment id))
                                    (expression-references (geometry-check-expression c)))
                            (begin
                              (unless (relation-truthy? (evaluate-expression (geometry-check-expression c) environment))
                                (geometry-error (geometry-check-origin c) "precondition failed: ~e"
                                                (geometry-check-expression c)))
                              #t))) c)))
    (for ([n (in-list nodes)])
      (define id (geometry-node-id n))
      (define e (geometry-node-expression n))
      (define free? (equal? e '(point)))
      (define choose? (and (pair? e) (eq? (car e) 'choose)))
      (define explicit (or (hash-ref pins id #f) (hash-ref given-values id #f) (hash-ref choice-values id #f)))
      (define value
        (cond
          [choose?
           (define-values (curve except) (domain-data e environment))
           (define value (or explicit (sample-domain curve except candidate dimension (geometry-view-width reference-view))))
           (check-choice! value curve except (geometry-node-origin n)) value]
          [explicit explicit]
          [free?
           ;; Incidence-constrained free givens can be sampled on an already
           ;; realized named curve. More general constraints are rejection-tested.
           (define incidence
             (for/first ([c (in-list (geometry-program-checks program))]
                         #:when (match (geometry-check-expression c)
                                  [(list 'on p (? symbol? curve)) (and (eq? p id) (hash-has-key? environment curve))]
                                  [_ #f])) (geometry-check-expression c)))
           (cond [incidence (sample-domain (hash-ref environment (caddr incidence)) #f candidate dimension
                                           (geometry-view-width reference-view))]
                 [(= candidate 0)
                  (case (modulo dimension 4)
                    [(0) (point -1.8 -0.3)] [(1) (point 1.8 0.3)]
                    [(2) (point -0.2 2.4)] [else (point 0.7 -2.2)])]
                 [else
                  (define width (geometry-view-width reference-view))
                  (define center (geometry-view-center reference-view))
                  (point+ center
                          (point (* width 0.28 (- (* 2 (halton candidate (* 2 dimension))) 1))
                                 (* (/ width (geometry-view-aspect reference-view)) 0.28
                                    (- (* 2 (halton candidate (+ 1 (* 2 dimension)))) 1))))])]
          [else (evaluate-expression e environment)]))
      (when (or free? choose?)
        (set! selected (hash-set selected id value))
        (set! dimension (add1 dimension)))
      (set! environment (hash-set environment id value))
      (check-ready!))
    (unless (null? pending) (geometry-error name "unresolved mathematical preconditions"))
    (for ([l (in-list (geometry-program-layout program))] #:when (eq? (car l) 'constrain))
      (unless (evaluate-expression (cadr l) environment) (geometry-error name "layout constraint failed: ~e" (cadr l))))
    (for ([a (in-list (geometry-program-assertions program))])
      (unless (relation-truthy? (evaluate-expression (geometry-check-expression a) environment))
        (geometry-error (geometry-check-origin a) "assertion failed: ~e"
                        (geometry-check-expression a))))
    (define anchors (anchor-points program environment))
    (define view (or fixed-view (fit-view anchors aspect margin padding)))
    (unless (andmap (lambda (p) (point-in-view? p view padding)) anchors)
      (geometry-error name "important points and their padding do not fit the fixed view"))
    (define preference-score
      (for/sum ([l (in-list (geometry-program-layout program))] #:when (eq? (car l) 'prefer))
        (define target (evaluate-expression (caddr l) environment))
        (define actual (evaluate-expression (cadr l) environment))
        (define weight (if (= (length l) 4) (cadddr l) 1))
        (* weight (sqr (/ (- actual target) (max 1 (abs target)))))))
    (define focus-points
      (append-map (lambda (l) (if (eq? (car l) 'focus)
                                  (append-map (lambda (id) (value-anchors (hash-ref environment id))) (cdr l)) '()))
                  (geometry-program-layout program)))
    (define focus-score
      (if (null? focus-points) 0
          (let ([center (point* (foldl point+ (point 0 0) focus-points) (/ 1 (length focus-points)))])
            (* 0.2 (sqr (/ (distance center (geometry-view-center view)) (geometry-view-width view)))))))
    (define separation-score
      (for*/sum ([i (in-range (length anchors))] [j (in-range (+ i 1) (length anchors))])
        (define d (/ (distance (list-ref anchors i) (list-ref anchors j)) (geometry-view-width view)))
        (if (and (> d 1e-9) (< d 0.04)) (sqr (/ (- 0.04 d) 0.04)) 0)))
    (define score (+ preference-score focus-score separation-score
                     (* 0.002 (sqr (- (geometry-view-width view) (geometry-view-width reference-view))))))
    (values environment selected view score))
  (for ([candidate (in-range count)])
    (with-handlers ([exn:fail:geometry?
                     (lambda (e) (hash-update! rejections (exn-message e) add1 0))])
      (define-values (environment selected view score) (evaluate-candidate candidate))
      (set! valid-count (add1 valid-count))
      ;; Strict comparison gives a deterministic first-candidate tie-break.
      (when (< score best-score)
        (set! best-score score) (set! best-index candidate)
        (set! best (list environment selected view)))))
  (unless best
    (geometry-error name "no valid layout among ~a deterministic candidates. First diagnostic: ~a. Use layout pin, explicit givens/choices, a wider view, or more samples."
                    count (if (zero? (hash-count rejections)) "no candidate" (car (sort (hash-keys rejections) string<?)))))
  (geometry-realization
   program (car best) (caddr best) (cadr best)
   (hash 'search-method 'deterministic-finite-candidates 'candidates-tested count
         'valid-candidates valid-count 'selected-candidate best-index 'score best-score
         'rejections (make-immutable-hash (hash->list rejections))
         'important-ids (construction-visible-ids program))))

(define (sqr x) (* x x))
