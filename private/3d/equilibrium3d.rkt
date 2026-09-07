#lang racket/base

;; Seed-bounded deterministic equilibrium search for an ODE field.

(require racket/list
         "../geometry.rkt"
         "../preview-cancellation.rkt"
         "jacobian3d.rkt"
         "linear3.rkt"
         "ode-flow3d.rkt"
         "seed-set3d.rkt"
         "vec3.rkt")

(provide (struct-out equilibrium-solver3d)
         default-equilibrium-solver3d
         (struct-out equilibrium-seed-result3d)
         (struct-out equilibrium-root3d)
         (struct-out equilibrium-search3d)
         equilibrium-points3d)

(struct equilibrium-solver3d
  (residual-tolerance step-tolerance maximum-iterations damping minimum-damping)
  #:transparent)
(define default-equilibrium-solver3d
  (equilibrium-solver3d 1e-8 1e-10 32 1 1/1024))

;; `root-index` is #f for every unsuccessful seed.  The `status` is one of
;; 'converged, 'singular-jacobian, 'out-of-domain, 'non-finite, 'stalled, or
;; 'iteration-limit, so failure data is never thrown away while merging roots.
(struct equilibrium-seed-result3d
  (seed-index seed status point residual iterations field-evaluations
              jacobian-evaluations root-index)
  #:transparent)
(struct equilibrium-root3d (point seed-index residual member-seed-indices) #:transparent)
(struct equilibrium-search3d (seeds roots seed-results diagnostics) #:transparent)

(define (equilibrium-points3d field seeds
                              #:solver [solver default-equilibrium-solver3d]
                              #:jacobian [derivative #f]
                              #:merge-distance [merge-distance 1e-6]
                              #:domain [domain #f]
                              #:time [time 0]
                              #:cancellation-token [cancellation-token #f])
  (check-solver solver)
  (unless (seed-set3d? seeds) (raise-argument-error 'equilibrium-points3d "seed-set3d?" seeds))
  (unless (and (finite-real? merge-distance) (positive? merge-distance))
    (raise-argument-error 'equilibrium-points3d "positive finite real as #:merge-distance" merge-distance))
  (unless (finite-real? time) (raise-argument-error 'equilibrium-points3d "finite real as #:time" time))
  (when domain
    (unless (and (procedure? domain) (procedure-arity-includes? domain 1))
      (raise-argument-error 'equilibrium-points3d "#f or (vec3? -> boolean?) as #:domain" domain)))
  (when cancellation-token
    (unless (cancellation-token? cancellation-token)
      (raise-argument-error 'equilibrium-points3d
                            "#f or cancellation-token? as #:cancellation-token"
                            cancellation-token))
    (check-cancellation cancellation-token))
  ;; `jacobian3d` validates field, derivative, and domain calls before the
  ;; first Newton update.  Each seed gets its own independent bounded search.
  (define raw-results
    (for/list ([seed (in-vector (seed-set3d-points seeds))] [index (in-naturals)])
      ;; Root slots are independent, but preserve seed-order assembly. A
      ;; cancellation never returns a partially merged root set.
      (when cancellation-token (check-cancellation cancellation-token))
      (search-one field seed index solver derivative domain time cancellation-token)))
  (define roots '())
  (define finalized
    (for/list ([result (in-list raw-results)])
      (if (not (eq? (equilibrium-seed-result3d-status result) 'converged))
          result
          (let* ([point (equilibrium-seed-result3d-point result)]
                 [existing-index
                  (for/first ([root (in-list roots)] [index (in-naturals)]
                              #:when (<= (vec3-distance point (equilibrium-root3d-point root))
                                         merge-distance))
                    index)])
            (if existing-index
                (let ([old (list-ref roots existing-index)])
                  (set! roots
                        (list-set roots existing-index
                                  (equilibrium-root3d
                                   (equilibrium-root3d-point old)
                                   (equilibrium-root3d-seed-index old)
                                   (equilibrium-root3d-residual old)
                                   (vector->immutable-vector
                                    (list->vector
                                     (append (vector->list (equilibrium-root3d-member-seed-indices old))
                                             (list (equilibrium-seed-result3d-seed-index result))))))))
                  (struct-copy equilibrium-seed-result3d result [root-index existing-index]))
                (let ([index (length roots)])
                  (set! roots
                        (append roots
                                (list (equilibrium-root3d
                                       point (equilibrium-seed-result3d-seed-index result)
                                       (equilibrium-seed-result3d-residual result)
                                       (vector (equilibrium-seed-result3d-seed-index result))))))
                  (struct-copy equilibrium-seed-result3d result [root-index index])))))))
  (define result-vector (vector->immutable-vector (list->vector finalized)))
  (define root-vector (vector->immutable-vector (list->vector roots)))
  (equilibrium-search3d
   seeds root-vector result-vector
   (hasheq 'seed-count (seed-set3d-count seeds)
           'converged-count (for/sum ([r (in-list finalized)])
                              (if (eq? (equilibrium-seed-result3d-status r) 'converged) 1 0))
           'root-count (vector-length root-vector)
           'merge-distance merge-distance
           'field-evaluations (for/sum ([r (in-list finalized)])
                                (equilibrium-seed-result3d-field-evaluations r))
           'jacobian-evaluations (for/sum ([r (in-list finalized)])
                                   (equilibrium-seed-result3d-jacobian-evaluations r)))))

(define (search-one field seed index solver derivative domain time cancellation-token)
  (define field-evaluations 0)
  (define jacobian-evaluations 0)
  (define (sample point)
    (set! field-evaluations (add1 field-evaluations))
    (call-field field time point))
  (define (finish status point residual iterations)
    (equilibrium-seed-result3d index seed status point residual iterations
                               field-evaluations jacobian-evaluations #f))
  (with-handlers ([exn:fail:preview-canceled? raise]
                  [exn:fail? (lambda (_) (finish 'non-finite seed +inf.0 0))])
    (cond
    [(and domain (not (domain? domain seed))) (finish 'out-of-domain seed +inf.0 0)]
    [else
     (let loop ([point seed] [residual (sample seed)] [iteration 0])
       (when cancellation-token (check-cancellation cancellation-token))
       (define norm (vec3-length residual))
       (cond [(not (finite-real? norm)) (finish 'non-finite point norm iteration)]
             [(<= norm (equilibrium-solver3d-residual-tolerance solver))
              (finish 'converged point norm iteration)]
             [(>= iteration (equilibrium-solver3d-maximum-iterations solver))
              (finish 'iteration-limit point norm iteration)]
             [else
              (define jac
                (jacobian3d field point #:time time #:derivative derivative #:domain domain))
              (set! jacobian-evaluations
                    (+ jacobian-evaluations (jacobian3d-result-evaluations jac)))
              (define delta
                (with-handlers ([exn:fail? (lambda (_) #f)])
                  (linear3-apply-vector (linear3-invert (jacobian3d-result-matrix jac)) residual)))
              (cond [(not delta) (finish 'singular-jacobian point norm iteration)]
                    [else
                     (define accepted
                       (let damp ([factor (equilibrium-solver3d-damping solver)])
                         (when cancellation-token (check-cancellation cancellation-token))
                         (cond [(< factor (equilibrium-solver3d-minimum-damping solver)) #f]
                               [else
                                (define candidate (vec3- point (vec3-scale factor delta)))
                                (cond [(and domain (not (domain? domain candidate)))
                                       (damp (/ factor 2))]
                                      [else
                                       (define candidate-residual (sample candidate))
                                       (if (< (vec3-length candidate-residual) norm)
                                           (cons candidate candidate-residual)
                                           (damp (/ factor 2)))])])) )
                     (cond [(not accepted) (finish 'stalled point norm iteration)]
                           [else
                            (define next-point (car accepted))
                            (define next-residual (cdr accepted))
                            (if (and (<= (vec3-length (vec3- next-point point))
                                         (equilibrium-solver3d-step-tolerance solver))
                                     (> (vec3-length next-residual)
                                        (equilibrium-solver3d-residual-tolerance solver)))
                                (finish 'stalled next-point (vec3-length next-residual) (add1 iteration))
                                (loop next-point next-residual (add1 iteration)))])])]))])))

(define (call-field field time point)
  (define proc (if (ode-field3d? field) (ode-field3d-procedure field) field))
  (define arity (if (ode-field3d? field) (ode-field3d-arity field)
                    (if (and (procedure? field) (procedure-arity-includes? field 4)) 4 3)))
  (define value (if (= arity 4) (proc time (vec3-x point) (vec3-y point) (vec3-z point))
                    (proc (vec3-x point) (vec3-y point) (vec3-z point))))
  (unless (vec3-finite? value)
    (raise-arguments-error 'equilibrium-points3d "field did not return a finite vec3"
                           "point" point "result" value))
  value)
(define (domain? domain point)
  (define answer (domain point))
  (unless (boolean? answer) (raise-arguments-error 'equilibrium-points3d "domain predicate did not return boolean" "result" answer)) answer)
(define (check-solver value)
  (unless (and (equilibrium-solver3d? value)
               (andmap (lambda (v) (and (finite-real? v) (positive? v)))
                       (list (equilibrium-solver3d-residual-tolerance value)
                             (equilibrium-solver3d-step-tolerance value)
                             (equilibrium-solver3d-damping value)
                             (equilibrium-solver3d-minimum-damping value)))
               (exact-positive-integer? (equilibrium-solver3d-maximum-iterations value))
               (<= (equilibrium-solver3d-minimum-damping value)
                   (equilibrium-solver3d-damping value)))
    (raise-argument-error 'equilibrium-points3d "valid equilibrium-solver3d?" value)))
