#lang racket/base

;;; SCENE-3D-T3 set layer: canonical prepared streamline collections.

(require rackunit
         "../3d.rkt")

(define policy
  (streamline-sample-policy3d #:maximum-chord-error 0
                              #:maximum-turn-angle 0
                              #:maximum-segment-length 1/4
                              #:minimum-segment-length 1/10000))

(define termination
  (trajectory-termination3d #:time-limit 1))

(module+ test
  ;; An independent collection retains the seed-set declaration order, even
  ;; when it is eligible for parallel preparation.
  (define ordered-seeds
    (explicit-seeds3d (list (vec3 0 2 0) (vec3 0 0 0) (vec3 0 -2 0))))
  (define independent
    (prepare-streamlines3d
     (lambda (_x _y _z) x-axis3) ordered-seeds
     #:solver (fixed-rk4-solver3d #:step-size 1/4)
     #:termination termination #:sample-policy policy #:parallel? #t))
  (check-true (prepared-streamline-set3d? independent))
  (check-eq? (prepared-streamline-set3d-seeds independent) ordered-seeds)
  (define independent-lines (prepared-streamline-set3d-streamlines independent))
  (check-equal? (vector-length independent-lines) 3)
  (check-equal? (for/list ([line (in-vector independent-lines)])
                  (prepared-streamline3d-seed line))
                (vector->list (seed-set3d-points ordered-seeds)))
  (define independent-diagnostics (prepared-streamline-set3d-diagnostics independent))
  (check-equal? (streamline-set-diagnostics3d-seed-count independent-diagnostics) 3)
  (check-equal? (streamline-set-diagnostics3d-accepted-seed-count independent-diagnostics) 3)
  (check-equal? (streamline-set-diagnostics3d-rejected-seed-count independent-diagnostics) 0)
  (check-equal? (streamline-set-diagnostics3d-parallel-mode independent-diagnostics)
                'threaded)
  (check-true
   (group3d?
    (adaptive-streamline-set3d independent #:id 'independent
                                #:style (stroke3d #:width 2))))

  ;; Disabling independent scheduling does not change the numerical output or
  ;; canonical child order; the diagnostic records the deliberately serial mode.
  (define serial
    (prepare-streamlines3d
     (lambda (_x _y _z) x-axis3) ordered-seeds
     #:solver (fixed-rk4-solver3d #:step-size 1/4)
     #:termination termination #:sample-policy policy #:parallel? #f))
  (check-equal? (prepared-streamline-set3d-streamlines serial) independent-lines)
  (check-equal? (streamline-set-diagnostics3d-parallel-mode
                 (prepared-streamline-set3d-diagnostics serial))
                'serial)

  ;; Separation processes the original seed order. A second seed already too
  ;; near the first accepted line is rejected rather than silently reordered.
  (define near-seeds
    (explicit-seeds3d (list origin3 (vec3 0 1/2 0) (vec3 0 2 0))))
  (define separated
    (prepare-streamlines3d
     (lambda (_x _y _z) x-axis3) near-seeds
     #:solver (fixed-rk4-solver3d #:step-size 1/4)
     #:termination termination #:sample-policy policy #:separation 1 #:parallel? #t))
  (define separated-diagnostics (prepared-streamline-set3d-diagnostics separated))
  (check-equal? (vector-length (prepared-streamline-set3d-streamlines separated)) 2)
  (check-equal? (streamline-set-diagnostics3d-accepted-seed-count separated-diagnostics) 2)
  (check-equal? (streamline-set-diagnostics3d-rejected-seed-count separated-diagnostics) 1)
  (check-equal? (streamline-set-diagnostics3d-minimum-separation separated-diagnostics) 1)
  (check-equal? (streamline-set-diagnostics3d-parallel-mode separated-diagnostics)
                'ordered-separation)

  ;; A later line may approach an earlier one only until the separation event;
  ;; its stored endpoint stays roughly one world unit from the horizontal line.
  (define approach-seeds (explicit-seeds3d (list origin3 (vec3 0 2 0))))
  (define approaching
    (prepare-streamlines3d
     (lambda (_x y _z) (if (zero? y) x-axis3 (vec3 0 -1 0)))
     approach-seeds #:solver (fixed-rk4-solver3d #:step-size 1/8)
     #:termination (trajectory-termination3d #:time-limit 3)
     #:sample-policy policy #:separation 1))
  (define approaching-lines (prepared-streamline-set3d-streamlines approaching))
  (check-equal? (vector-length approaching-lines) 2)
  (define approach-last
    (let ([samples (prepared-streamline3d-curve-samples
                    (vector-ref approaching-lines 1))])
      (vector-ref samples (sub1 (vector-length samples)))))
  (check-= (vec3-y approach-last) 1 1e-6)
  (check-not-false
   (member 'terminal-event
           (streamline-set-diagnostics3d-termination-reasons
            (prepared-streamline-set3d-diagnostics approaching)))))
