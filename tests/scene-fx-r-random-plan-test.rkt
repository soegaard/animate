#lang racket/base

;;;
;;; Corrective keyed random-plan tests
;;;

(require racket/list
         rackunit
         "../main.rkt"
         "../private/effect-random.rkt")

(module+ test
  ;; Golden coordinates freeze the published version-one mixer independently
  ;; of effect construction and of the host's word size/random generator.
  (check-equal? (effect-random-u64 1 0 'confetti 0 'x-position)
                994061044842182134)
  (check-equal? (effect-random-u64 1 17 'confetti 4 'rotation)
                5962283629059086623)
  (check-equal? (effect-random-u64 1 -7 'camera-shake 3 'y-position)
                4552792621259479819)
  (check-equal? (effect-random-bounded-integer 1 17 'confetti 4 'color-index 7)
                0)

  ;; Coordinates are named independent substreams, not consecutive draws.
  (check-not-equal?
   (effect-random-u64 1 17 'confetti 4 'x-position)
   (effect-random-u64 1 17 'confetti 4 'rotation))
  (check-equal?
   (effect-random-u64 1 17 'confetti 4 'x-position)
   (effect-random-u64 1 17 'confetti 4 'x-position))

  ;; Plan construction never consumes the process-global generator.
  (random-seed 9182)
  (define expected-next (random))
  (random-seed 9182)
  (void (effect-random-u64 1 27 'confetti 2 'rotation))
  (void (shuffled-order #:seed 27))
  (check-equal? (random) expected-next)

  ;; The Fisher--Yates plan remains a deterministic permutation for several
  ;; representative counts and is independent of when it is resolved.
  (for ([count '(0 1 2 7 32)])
    (define plan-a (resolve-animation-order (shuffled-order #:seed 91) count))
    (define plan-b (resolve-animation-order (shuffled-order #:seed 91) count))
    (check-equal? plan-a plan-b)
    (check-equal? (sort (vector->list plan-a) <) (range count))))
