#lang racket/base

;; Pure evaluation of the checked expression algebra. Free inputs and choices
;; are supplied by the realization pass; this module never chooses randomly.
(require racket/list "math.rkt")
(provide evaluate-expression relation-truthy?)

(define (eval-angle expression environment)
  (define values (map (lambda (x) (evaluate-expression x environment)) (cdr expression)))
  (unless (and (= (length values) 3) (andmap point? values))
    (geometry-error 'angle "angle expects three points"))
  (define a (list-ref values 0))
  (define b (list-ref values 1))
  (define c (list-ref values 2))
  (when (or (not (distinct? a b)) (not (distinct? c b)))
    (geometry-error 'angle "angle rays must have positive length"))
  (angle-spec a b c))

(define (linear-object? x) (or (line? x) (segment? x) (ray? x)))
(define (relation-truthy? v)
  (cond [(boolean? v) v]
        [(relation? v) (relation-holds? v)]
        [else (geometry-error 'assert "expected a Boolean or relation, received ~e" v)]))

(define (eval-perpendicular expression environment)
  (define args (cdr expression))
  (define a (evaluate-expression (car args) environment))
  (define b (evaluate-expression (cadr args) environment))
  (unless (and (linear-object? a) (linear-object? b))
    (geometry-error 'perpendicular "perpendicular expects linear objects"))
  (define at
    (cond [(= (length args) 2)
           (define pts (with-handlers ([exn:fail:geometry? (lambda (_) '())])
                         (intersections a b)))
           (and (= (length pts) 1) (car pts))]
          [(and (= (length args) 4) (eq? (caddr args) '#:at))
           (evaluate-expression (cadddr args) environment)]
          [else (geometry-error 'perpendicular "expected optional #:at point")]))
  (define rel (perpendicular-relation a b at))
  rel)

(define (eval-parallel expression environment)
  (define curves (map (lambda (x) (evaluate-expression x environment)) (cdr expression)))
  (unless (and (= (length curves) 2) (andmap linear-object? curves))
    (geometry-error 'parallel "parallel expects two linear objects"))
  (define rel (parallel-relation (car curves) (cadr curves)))
  rel)

(define (eval-equal-length expression environment)
  (define segments (map (lambda (x) (evaluate-expression x environment)) (cdr expression)))
  (unless (and (>= (length segments) 2) (andmap segment? segments))
    (geometry-error 'equal-length "equal-length expects at least two segments"))
  (define rel (equal-length-relation segments))
  rel)

(define (eval-equal-angle expression environment)
  (define angles (map (lambda (x) (evaluate-expression x environment)) (cdr expression)))
  (unless (and (>= (length angles) 2) (andmap angle-spec? angles))
    (geometry-error 'equal-angle "equal-angle expects at least two angle specifications"))
  (define rel (equal-angle-relation angles))
  rel)

(define (eval-collinear expression environment)
  (define points (map (lambda (x) (evaluate-expression x environment)) (cdr expression)))
  (unless (and (>= (length points) 3) (andmap point? points))
    (geometry-error 'collinear "collinear expects at least three points"))
  (define rel (collinear-relation points))
  rel)

(define (eval-midpoint-of expression environment)
  (define values (map (lambda (x) (evaluate-expression x environment)) (cdr expression)))
  (unless (and (= (length values) 2) (point? (car values)) (segment? (cadr values)))
    (geometry-error 'midpoint-of "midpoint-of expects a point and a segment"))
  (define rel (midpoint-of-relation (car values) (cadr values)))
  rel)

(define (evaluate-expression expression environment)
  (define (ev x) (evaluate-expression x environment))
  (define result
    (cond
      [(or (finite-real? expression) (boolean? expression)) expression]
      [(symbol? expression)
       (hash-ref environment expression
                 (lambda () (geometry-error 'evaluate "unrealized reference ~a" expression)))]
      [else
       (define op (car expression))
       (define args (cdr expression))
       (case op
         [(quote) (car args)]
         [(point)
          (when (null? args) (geometry-error 'point "a free point must be a named given"))
          (apply point (map ev args))]
         [(line) (apply line (map ev args))]
         [(segment) (apply segment (map ev args))]
         [(ray) (apply ray (map ev args))]
         [(circle)
          (if (and (= (length args) 3) (eq? (cadr args) '#:radius))
              (circle-with-radius (ev (car args)) (ev (caddr args)))
              (apply circle (map ev args)))]
         [(start-point) (start-point (ev (car args)))]
         [(end-point) (end-point (ev (car args)))]
         [(angle-first) (angle-first (ev (car args)))]
         [(angle-vertex) (angle-vertex (ev (car args)))]
         [(angle-last) (angle-last (ev (car args)))]
         [(side-of?) (apply side-of? (map ev args))]
         [(marker)
          (define rel (ev (car args)))
          (cond [(angle-spec? rel) (angle-marker rel)]
                [(relation? rel) (relation->marker rel)]
                [(marker? rel) rel]
                [else (geometry-error 'marker "expected an angle or relation")])]
         [(angle) (eval-angle expression environment)]
         [(perpendicular) (eval-perpendicular expression environment)]
         [(parallel) (eval-parallel expression environment)]
         [(equal-length) (eval-equal-length expression environment)]
         [(equal-angle) (eval-equal-angle expression environment)]
         [(collinear) (eval-collinear expression environment)]
         [(midpoint-of) (eval-midpoint-of expression environment)]
         [(distance) (apply distance (map ev args))]
         [(midpoint) (apply midpoint (map ev args))]
         [(center) (circle-center (ev (car args)))]
         [(length) (define s (ev (car args))) (distance (segment-a s) (segment-b s))]
         [(intersections) (apply intersections (map ev args))]
         [(intersection)
          (define a (ev (car args)))
          (define b (ev (cadr args)))
          (define options
            (let loop ([xs (cddr args)] [options (hash)])
              (cond [(null? xs) options]
                    [(eq? (car xs) '#:side-of)
                     (loop (cdddr xs) (hash-set (hash-set options 'reference (ev (cadr xs)))
                                               'side (ev (caddr xs))))]
                    [else (loop (cddr xs) (hash-set options (car xs) (ev (cadr xs))))])))
          (intersection a b (hash-ref options 'side 'left)
                        #:side-of (hash-ref options 'reference #f)
                        #:other-than (hash-ref options '#:other-than #f)
                        #:near (hash-ref options '#:near #f)
                        #:far-from (hash-ref options '#:far-from #f))]
         [(expect-points)
          (define points (ev (cadr args)))
          (unless (= (length points) (car args))
            (geometry-error 'intersections "binding expects ~a points, but this realization has ~a"
                            (car args) (length points)))
          points]
         [(select-point) (list-ref (ev (car args)) (cadr args))]
         [(distinct?) (apply distinct? (map ev args))]
         [(noncollinear?) (apply noncollinear? (map ev args))]
         [(on) (apply on (map ev args))]
         [(and) (andmap (lambda (e) (relation-truthy? (ev e))) args)]
         [(or) (ormap (lambda (e) (relation-truthy? (ev e))) args)]
         [(not) (not (relation-truthy? (ev (car args))))]
         [(+) (apply + (map ev args))]
         [(-) (apply - (map ev args))]
         [(*) (apply * (map ev args))]
         [(/)
          (define numbers (map ev args))
          (when (ormap zero? (if (= (length numbers) 1) numbers (cdr numbers)))
            (geometry-error 'evaluate "division by zero in ~e" expression))
          (apply / numbers)]
         [(=) (apply = (map ev args))]
         [(<) (apply < (map ev args))]
         [(>) (apply > (map ev args))]
         [(<=) (apply <= (map ev args))]
         [(>=) (apply >= (map ev args))]
         [(choose point-on input) (geometry-error op "this expression needs a realization context")]
         [else (geometry-error 'evaluate "unsupported operator ~a" op)])]))
  (when (and (number? result) (not (finite-real? result)))
    (geometry-error 'evaluate "non-finite numeric result in ~e" expression))
  result)
