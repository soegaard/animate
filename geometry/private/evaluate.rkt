#lang racket/base

;; Pure evaluation of the checked expression algebra. Free inputs and choices
;; are supplied by the realization pass; this module never chooses randomly.
(require racket/list "math.rkt")
(provide evaluate-expression)

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
