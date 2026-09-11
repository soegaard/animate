#lang racket/base

;; Pure evaluation of the checked expression algebra. Free inputs and choices
;; are supplied by the realization pass; this module never chooses randomly.
(require racket/list "math.rkt")
(provide evaluate-expression)


(define (eval-angle expression environment)
  (define values (map (lambda (x) (evaluate-expression x environment)) (cdr expression)))
  (unless (and (= (length values) 3) (andmap point? values))
    (geometry-error 'angle "angle expects three points"))
  (define a (list-ref values 0))
  (define b (list-ref values 1))
  (define c (list-ref values 2))
  (when (or (same-point? a b 1) (same-point? c b 1))
    (geometry-error 'angle "angle rays must have positive length"))
  (angle-spec a b c))
(define (eval-perpendicular expression environment)
  (define args (cdr expression))
  (define a (evaluate-expression (car args) environment))
  (define b (evaluate-expression (cadr args) environment))
  (unless (and (or (line? a) (segment? a) (ray? a)) (or (line? b) (segment? b) (ray? b)))
    (geometry-error 'perpendicular "perpendicular expects linear objects"))
  (define at
    (cond [(= (length args) 2)
           (define pts (intersections a b))
           (unless (= (length pts) 1)
             (geometry-error 'perpendicular "cannot infer unique intersection; use #:at"))
           (car pts)]
          [(and (= (length args) 4) (eq? (caddr args) '#:at))
           (evaluate-expression (cadddr args) environment)]
          [else (geometry-error 'perpendicular "expected optional #:at point")]))
  (unless (perpendicular-at? a b at)
    (geometry-error 'perpendicular "relation does not hold at ~e" at))
  (perpendicular-marker a b at))
(define (eval-equal-length expression environment)
  (define segments (map (lambda (x) (evaluate-expression x environment)) (cdr expression)))
  (unless (and (>= (length segments) 2) (andmap segment? segments))
    (geometry-error 'equal-length "equal-length expects at least two segments"))
  (unless (equal-segments? segments)
    (geometry-error 'equal-length "relation does not hold"))
  (equal-length-marker segments))
(define (eval-equal-angle expression environment)
  (define angles (map (lambda (x) (evaluate-expression x environment)) (cdr expression)))
  (unless (and (>= (length angles) 2) (andmap angle-spec? angles))
    (geometry-error 'equal-angle "equal-angle expects at least two angle specifications"))
  (unless (equal-angles? angles)
    (geometry-error 'equal-angle "relation does not hold"))
  (equal-angle-marker angles))

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
         [(circle) (apply circle (map ev args))]
         [(marker)
          (define rel (ev (car args)))
          (cond [(angle-spec? rel) (angle-marker rel)]
                [(marker? rel) rel]
                [else (geometry-error 'marker "expected an angle or marker relation")])]
         [(angle) (eval-angle expression environment)]
         [(perpendicular) (eval-perpendicular expression environment)]
         [(equal-length) (eval-equal-length expression environment)]
         [(equal-angle) (eval-equal-angle expression environment)]
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
         [(and) (andmap ev args)]
         [(or) (ormap ev args)]
         [(not) (not (ev (car args)))]
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
