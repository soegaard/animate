#lang racket/base

;; Visual lowering of already prepared trajectory data.  Sampling invokes only
;; `ode-trajectory3d-position`, whose prepared branch is dense retained data.

(require "../geometry.rkt" "ode-flow3d.rkt" "tube3d.rkt" "vec3.rkt")

(provide trajectory-samples3d trajectory-tube3d)

(define (trajectory-samples3d trajectory #:count [count 64])
  (unless (prepared-trajectory3d? trajectory)
    (raise-argument-error 'trajectory-samples3d "prepared-trajectory3d?" trajectory))
  (unless (and (exact-integer? count) (>= count 2))
    (raise-argument-error 'trajectory-samples3d "exact integer at least 2 as #:count" count))
  (define range (ode-trajectory3d-time-range trajectory))
  (define start (car range)) (define end (cdr range))
  (vector->immutable-vector
   (list->vector
    (for/list ([index (in-range count)])
      (ode-trajectory3d-position trajectory
                                 (+ start (* (- end start) (/ index (sub1 count)))))))))

(define (trajectory-tube3d trajectory
                           #:id [id 'trajectory-tube]
                           #:radius [radius 1/20]
                           #:sides [sides 12]
                           #:samples [samples 64]
                           #:caps? [caps? #t]
                           #:style [style #f])
  (unless (symbol? id) (raise-argument-error 'trajectory-tube3d "symbol? as #:id" id))
  (define result
    (tube3d (trajectory-samples3d trajectory #:count samples)
            #:id id #:radius radius #:sides sides #:caps? caps?))
  ;; Existing tubes encode material via the ordinary mesh lowering path.  The
  ;; optional style hook is reserved for the future ribbon/bundle API rather
  ;; than being silently ignored.
  (when style (raise-argument-error 'trajectory-tube3d "#f as #:style (not yet supported)" style))
  result)
