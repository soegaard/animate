#lang racket/base

;; Bounded, index-stable scheduling for independent numerical preparation.
;; The work procedures remain in this Racket process, so they can close over
;; ordinary author values; their mathematical contract must therefore be pure.
;; Results are collected by declaration index rather than completion order.

(require racket/async-channel
         (only-in racket/place processor-count)
         "../preview-cancellation.rkt")

(provide prepare-indexed-work3d)

(struct indexed-work-success3d (index value) #:transparent)
(struct indexed-work-failure3d (index raised) #:transparent)

;; prepare-indexed-work3d : exact-nonnegative-integer? (index -> value)
;;                          #:parallel? boolean? #:cancellation-token ...
;;                       -> (values immutable-vector? symbol?)
;; `threaded` means bounded concurrent Racket threads were used. It does not
;; claim that arbitrary author closures can be serialised to processes or that
;; CPU-bound closures receive a portable multicore speedup.
(define (prepare-indexed-work3d count work
                                #:parallel? [parallel? #t]
                                #:cancellation-token [cancellation-token #f])
  (unless (exact-nonnegative-integer? count)
    (raise-argument-error 'prepare-indexed-work3d "exact-nonnegative-integer?" count))
  (unless (procedure? work)
    (raise-argument-error 'prepare-indexed-work3d "procedure?" work))
  (unless (boolean? parallel?)
    (raise-argument-error 'prepare-indexed-work3d "boolean? as #:parallel?" parallel?))
  (when cancellation-token
    (unless (cancellation-token? cancellation-token)
      (raise-argument-error 'prepare-indexed-work3d
                            "#f or cancellation-token? as #:cancellation-token"
                            cancellation-token))
    (check-cancellation cancellation-token))
  (cond
    [(or (not parallel?) (<= count 1))
     (values
      (vector->immutable-vector
       (for/vector ([index (in-range count)])
         (when cancellation-token (check-cancellation cancellation-token))
         (work index)))
      'serial)]
    [else
     ;; The bounded queue avoids creating one thread per seed for large grids.
     ;; At least two workers make `#:parallel? #t` observable even on a host
     ;; that reports one processor; Racket schedules those cooperatively.
     (define worker-count (min count (max 2 (processor-count))))
     (define jobs (make-async-channel))
     (define outcomes (make-async-channel))
     (define workers
       (for/list ([worker-index (in-range worker-count)])
         (thread
          (lambda ()
            (let loop ()
              (define job (async-channel-get jobs))
              (unless (eq? job 'stop)
                (define outcome
                  (with-handlers ([(lambda (_raised) #t)
                                   (lambda (raised)
                                     (indexed-work-failure3d job raised))])
                    (when cancellation-token (check-cancellation cancellation-token))
                    (indexed-work-success3d job (work job))))
                (async-channel-put outcomes outcome)
                (loop)))))))
     (for ([index (in-range count)])
       (async-channel-put jobs index))
     (for ([worker (in-list workers)])
       (async-channel-put jobs 'stop))
     (define ordered-outcomes (make-vector count #f))
     (for ([ignored (in-range count)])
       (define outcome (async-channel-get outcomes))
       (vector-set! ordered-outcomes
                    (if (indexed-work-success3d? outcome)
                        (indexed-work-success3d-index outcome)
                        (indexed-work-failure3d-index outcome))
                    outcome))
     (for ([worker (in-list workers)])
       (thread-wait worker))
     ;; A serial run would reach the earliest failing seed first. Preserve that
     ;; observable failure order even when another worker completed sooner.
     (define earliest-failure
       (for/first ([outcome (in-vector ordered-outcomes)]
                   #:when (indexed-work-failure3d? outcome))
         outcome))
     (when earliest-failure
       (raise (indexed-work-failure3d-raised earliest-failure)))
     (values
      (vector->immutable-vector
       (for/vector ([outcome (in-vector ordered-outcomes)])
         (indexed-work-success3d-value outcome)))
      'threaded)]))
