#lang racket/base

;;;
;;; Implicit Curves and Contours
;;;

;; Samples one scalar field with deterministic marching squares. The resulting
;; path geometry contains no callback or renderer state.

(require racket/list
         "axes-visual.rkt"
         "geometry.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

(provide sample-implicit-path
         implicit-curve)

; sample-implicit-path : axes-visual? (procedure-arity-includes/c 2)
;                       [#:level finite-real?]
;                       [#:x-count exact-integer-at-least-2?]
;                       [#:y-count exact-integer-at-least-2?]
;                       -> path-geometry?
;; Samples one scalar level set into axes-local contour segments.
(define (sample-implicit-path axes field
                              #:level [level 0]
                              #:x-count [x-count 65]
                              #:y-count [y-count 65])
  (check-implicit-arguments 'sample-implicit-path axes field level x-count y-count)
  (define xs (implicit-grid-values axes 'x x-count))
  (define ys (implicit-grid-values axes 'y y-count))
  (define samples
    (for/list ([y (in-list ys)])
      (for/list ([x (in-list xs)])
        (implicit-sample field x y))))
  (define raw-subpaths
    (remove-duplicates
     (apply append
      (for*/list ([row-index (in-range (sub1 y-count))]
                  [column-index (in-range (sub1 x-count))])
        (implicit-cell->subpaths
         axes
         level
         (list (list-ref xs column-index)
               (list-ref ys row-index)
               (list-ref (list-ref samples row-index) column-index))
         (list (list-ref xs (add1 column-index))
               (list-ref ys row-index)
               (list-ref (list-ref samples row-index) (add1 column-index)))
         (list (list-ref xs (add1 column-index))
               (list-ref ys (add1 row-index))
               (list-ref (list-ref samples (add1 row-index)) (add1 column-index)))
         (list (list-ref xs column-index)
               (list-ref ys (add1 row-index))
               (list-ref (list-ref samples (add1 row-index)) column-index)))))))
  ;; Each cell independently produces one or two short segments. Joining them
  ;; here makes a contour one connected path (and a closed level set a closed
  ;; subpath), rather than a collection of visually identical cell edges.
  (path-geometry
   (contour-segments->subpaths
    (remove-duplicates
     (for/list ([subpath (in-list raw-subpaths)])
       (subpath->contour-segment subpath))))))

; implicit-curve : axes-visual? (procedure-arity-includes/c 2)
;                  #:id symbol?
;                  [#:level finite-real?]
;                  [#:x-count exact-integer-at-least-2?]
;                  [#:y-count exact-integer-at-least-2?]
;                  [#:opacity opacity?]
;                  [#:stroke color-spec?]
;                  [#:stroke-width nonnegative-finite-real?]
;                  -> path-visual?
;; Creates a styled snapshot Visual for one sampled implicit contour.
(define (implicit-curve axes field
                        #:id id
                        #:level [level 0]
                        #:x-count [x-count 65]
                        #:y-count [y-count 65]
                        #:opacity [opacity 1]
                        #:stroke [stroke "darkorange"]
                        #:stroke-width [stroke-width 2])
  (unless (symbol? id)
    (raise-argument-error 'implicit-curve "symbol?" id))
  (unless (opacity? opacity)
    (raise-argument-error 'implicit-curve "finite real in [0, 1]" opacity))
  (unless (and (finite-real? stroke-width) (not (negative? stroke-width)))
    (raise-argument-error 'implicit-curve "nonnegative finite real?" stroke-width))
  (define path
    (sample-implicit-path axes field #:level level #:x-count x-count #:y-count y-count))
  (make-path-visual
   path
   #:id id
   #:center (visual-position axes)
   #:rotation (visual-rotation axes)
   #:scale (visual-scale axes)
   #:opacity opacity
   #:fill #f
   #:stroke stroke
   #:stroke-width stroke-width))

; implicit-grid-values : axes-visual? symbol? exact-positive-integer?
;                        -> (listof finite-real?)
(define (implicit-grid-values axes direction count)
  (for/list ([index (in-range count)])
    (case direction
      [(x) (axes-x-interpolate-coordinate axes (/ index (sub1 count)))]
      [(y) (axes-y-interpolate-coordinate axes (/ index (sub1 count)))]
      [else
       (raise-argument-error 'implicit-grid-values "'x or 'y" direction)])))

; implicit-sample : procedure? finite-real? finite-real? -> (or/c finite-real? false/c)
(define (implicit-sample field x y)
  (define results
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'sample-implicit-path
             "the implicit-field procedure raised an exception"
             "x" x "y" y "exception message" (exn-message exception)))])
      (call-with-values (lambda () (field x y)) list)))
  (unless (= (length results) 1)
    (raise-arguments-error
     'sample-implicit-path
     "the implicit-field procedure must return exactly one value"
     "x" x "y" y "result count" (length results)))
  (define result (car results))
  (cond [(finite-real? result) result]
        [(real? result) #f]
        [else
         (raise-arguments-error
          'sample-implicit-path
          "the implicit-field procedure must return a real number"
          "x" x "y" y "result" result)]))

; implicit-cell->subpaths : axes-visual? finite-real? list? list? list? list?
;                           -> (listof path-subpath?)
;; Returns one or two deterministic linear contour segments for a sampled cell.
(define (implicit-cell->subpaths axes level bottom-left bottom-right top-right top-left)
  (if (or (not (third bottom-left))
          (not (third bottom-right))
          (not (third top-right))
          (not (third top-left)))
      '()
      (let* ([edges (list (list bottom-left bottom-right)
                          (list bottom-right top-right)
                          (list top-right top-left)
                          (list top-left bottom-left))]
             [points
              (remove-duplicate-points
               (for/list ([edge (in-list edges)]
                          #:when (edge-crosses-level? edge level))
                 (edge-level-point edge level)))])
        (cond
          [(= (length points) 2)
           (list (implicit-segment-subpath axes (first points) (second points)))]
          [(= (length points) 4)
           (define center-value
             (/ (+ (third bottom-left) (third bottom-right)
                   (third top-right) (third top-left))
                4))
           (if (positive? (- center-value level))
               (list (implicit-segment-subpath axes (first points) (second points))
                     (implicit-segment-subpath axes (third points) (fourth points)))
               (list (implicit-segment-subpath axes (first points) (fourth points))
                     (implicit-segment-subpath axes (second points) (third points))))]
          [else '()]))))

; edge-crosses-level? : (listof list?) finite-real? -> boolean?
(define (edge-crosses-level? edge level)
  (define left (- (third (first edge)) level))
  (define right (- (third (second edge)) level))
  (or (zero? left) (zero? right) (negative? (* left right))))

; edge-level-point : (listof list?) finite-real? -> vec2?
(define (edge-level-point edge level)
  ;; Shared grid edges occur in opposite directions in adjacent cells. Put
  ;; them in one canonical order before interpolating so the two cells compute
  ;; equal endpoint values and can be joined exactly.
  (define first-sample
    (if (implicit-sample<? (first edge) (second edge))
        (first edge)
        (second edge)))
  (define second-sample
    (if (implicit-sample<? (first edge) (second edge))
        (second edge)
        (first edge)))
  (define first-value (- (third first-sample) level))
  (define second-value (- (third second-sample) level))
  (define progress
    (cond [(zero? first-value) 0]
          [(zero? second-value) 1]
          [else (/ (- first-value) (- second-value first-value))]))
  (vec2 (real-lerp (first first-sample) (first second-sample) progress)
        (real-lerp (second first-sample) (second second-sample) progress)))

; remove-duplicate-points : (listof vec2?) -> (listof vec2?)
(define (remove-duplicate-points points)
  (let loop ([remaining points] [seen '()] [result '()])
    (cond [(null? remaining) (reverse result)]
          [(member (car remaining) seen)
           (loop (cdr remaining) seen result)]
          [else
           (loop (cdr remaining) (cons (car remaining) seen)
                 (cons (car remaining) result))])))

; implicit-segment-subpath : axes-visual? vec2? vec2? -> path-subpath?
(define (implicit-segment-subpath axes start end)
  (define (local point)
    (axes-coordinates->local-point axes
                                   (vec2-x point)
                                   (vec2-y point)))
  (path-subpath (local start) (list (line-path-segment (local end))) #f))


;;;
;;; Contour Assembly
;;;

;; A contour-segment is a canonical, undirected local line segment. It is
;; private because the public result is ordinary path geometry.
(struct contour-segment (start end)
  #:transparent)

; subpath->contour-segment : path-subpath? -> contour-segment?
;; Converts one generated single-line subpath to canonical undirected form.
(define (subpath->contour-segment subpath)
  (define start (path-subpath-start subpath))
  (define end
    (line-path-segment-end (first (path-subpath-segments subpath))))
  (if (vec2<? end start)
      (contour-segment end start)
      (contour-segment start end)))

; contour-segments->subpaths : (listof contour-segment?) -> (listof path-subpath?)
;; Connects each deterministic chain. Closed chains use path-subpath's native
;; closure flag, so their stored final segment is never a zero-length duplicate.
(define (contour-segments->subpaths segments)
  (let loop ([remaining (sort segments contour-segment<?)]
             [reversed-subpaths '()])
    (cond
      [(null? remaining)
       (reverse reversed-subpaths)]
      [else
       (define start
         (contour-component-start remaining))
       (define-values (points unused)
         (walk-contour remaining start))
       (define closed?
         (and (pair? points)
              (pair? (cdr points))
              (equal? (first points) (last points))))
       (define stored-points
         (if closed?
             (drop-right points 1)
             points))
       (loop unused
             (cons (contour-points->subpath stored-points closed?)
                   reversed-subpaths))])))

; contour-component-start : (listof contour-segment?) -> vec2?
;; Chooses a stable leaf for open chains, otherwise a stable point on a loop.
(define (contour-component-start segments)
  (define endpoints
    (apply append
           (for/list ([segment (in-list segments)])
             (list (contour-segment-start segment)
                   (contour-segment-end segment)))))
  (define leaves
    (filter (lambda (point)
              (= 1 (contour-point-degree point segments)))
            endpoints))
  (first (sort (if (null? leaves) endpoints leaves) vec2<?)))

; contour-point-degree : vec2? (listof contour-segment?) -> exact-nonnegative-integer?
(define (contour-point-degree point segments)
  (for/sum ([segment (in-list segments)])
    (+ (if (equal? point (contour-segment-start segment)) 1 0)
       (if (equal? point (contour-segment-end segment)) 1 0))))

; walk-contour : (listof contour-segment?) vec2?
;;                -> (values (listof vec2?) (listof contour-segment?))
;; Walks and consumes one connected deterministic chain. Degenerate grid-node
;; crossings can have degree above two; consuming one stable continuation keeps
;; every emitted path valid and leaves any remaining branch for the next walk.
(define (walk-contour segments start)
  (let loop ([current start]
             [available segments]
             [reversed-points (list start)])
    (define incident
      (sort
       (filter (lambda (segment)
                 (or (equal? current (contour-segment-start segment))
                     (equal? current (contour-segment-end segment))))
               available)
       contour-segment<?))
    (cond
      [(null? incident)
       (values (reverse reversed-points) available)]
      [else
       (define segment (first incident))
       (define next
         (if (equal? current (contour-segment-start segment))
             (contour-segment-end segment)
             (contour-segment-start segment)))
       (loop next
             (remove segment available)
             (cons next reversed-points))])))

; contour-points->subpath : (listof vec2?) boolean? -> path-subpath?
(define (contour-points->subpath points closed?)
  (path-subpath
   (first points)
   (for/list ([point (in-list (cdr points))])
     (line-path-segment point))
   closed?))

; contour-segment<? : contour-segment? contour-segment? -> boolean?
(define (contour-segment<? left right)
  (or (vec2<? (contour-segment-start left) (contour-segment-start right))
      (and (equal? (contour-segment-start left) (contour-segment-start right))
           (vec2<? (contour-segment-end left) (contour-segment-end right)))))

; vec2<? : vec2? vec2? -> boolean?
(define (vec2<? left right)
  (or (< (vec2-x left) (vec2-x right))
      (and (= (vec2-x left) (vec2-x right))
           (< (vec2-y left) (vec2-y right)))))

; implicit-sample<? : list? list? -> boolean?
;; Orders a sampled grid point by numeric coordinates, ignoring field value.
(define (implicit-sample<? left right)
  (or (< (first left) (first right))
      (and (= (first left) (first right))
           (< (second left) (second right)))))

; check-implicit-arguments : symbol? any/c any/c any/c any/c -> void?
(define (check-implicit-arguments who axes field level x-count y-count)
  (unless (axes-visual? axes)
    (raise-argument-error who "axes-visual?" axes))
  (unless (and (procedure? field) (procedure-arity-includes? field 2))
    (raise-argument-error who "procedure accepting two arguments" field))
  (unless (finite-real? level)
    (raise-argument-error who "finite real?" level))
  (for ([count (in-list (list x-count y-count))])
    (unless (and (exact-integer? count) (>= count 2))
      (raise-argument-error who "exact integer greater than or equal to 2" count))))
