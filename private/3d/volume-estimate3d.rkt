#lang racket/base

;;;
;;; Immutable Cross-Section Samples and One-Dimensional Volume Estimates
;;;

;; A prepared table stores every exact section result.  It is therefore safe
;; for parallel render workers and makes a numerical volume approximation
;; auditable rather than hiding fresh plane/mesh work in each frame.

(require "../geometry.rkt"
         "clipping3d.rkt"
         "mesh3d.rkt"
         "ray-plane.rkt"
         "section-measure3d.rkt"
         "section-settings3d.rkt"
         "vec3.rkt")

(provide (struct-out cross-section-sample3d)
         (struct-out prepared-cross-section-function3d)
         (struct-out volume-estimate3d)
         prepare-cross-section-function3d
         volume-by-slices3d)

(struct cross-section-sample3d (position section area centroid diagnostics) #:transparent)
(struct prepared-cross-section-function3d (normal range sampling samples diagnostics) #:transparent)
(struct volume-estimate3d (value terms error-estimate diagnostics) #:transparent)

; prepare-cross-section-function3d : mesh3d? ... -> prepared-cross-section-function3d?
;; `#:sampling 'endpoints` supplies values for trapezoid/Simpson rules;
;; `#:sampling 'midpoints` supplies values for the composite midpoint rule.
(define (prepare-cross-section-function3d mesh
                                          #:normal normal
                                          #:range range
                                          #:samples sample-count
                                          #:sampling [sampling 'endpoints]
                                          #:settings [settings
                                                      (section3d-settings-for-bounds
                                                       (mesh3d-local-bounds mesh))])
  (unless (mesh3d? mesh)
    (raise-argument-error 'prepare-cross-section-function3d "mesh3d?" mesh))
  (unless (and (vec3? normal) (positive? (vec3-length normal)))
    (raise-argument-error 'prepare-cross-section-function3d "nonzero vec3? normal" normal))
  (define-values (start end) (check-range 'prepare-cross-section-function3d range))
  (unless (exact-positive-integer? sample-count)
    (raise-argument-error 'prepare-cross-section-function3d "exact positive #:samples" sample-count))
  (unless (memq sampling '(endpoints midpoints))
    (raise-argument-error 'prepare-cross-section-function3d "endpoints or midpoints sampling" sampling))
  (when (and (eq? sampling 'endpoints) (< sample-count 2))
    (raise-argument-error 'prepare-cross-section-function3d
                          "at least two endpoint samples" sample-count))
  (unless (section3d-settings? settings)
    (raise-argument-error 'prepare-cross-section-function3d "section3d-settings?" settings))
  (define unit (vec3-normalize normal))
  (define step (/ (- end start)
                  (if (eq? sampling 'endpoints) (sub1 sample-count) sample-count)))
  (define samples
    (for/vector ([index (in-range sample-count)])
      (define position
        (+ start (* (+ index (if (eq? sampling 'midpoints) 1/2 0)) step)))
      (define section
        (section-by-plane3d mesh (plane3 (vec3-scale position unit) unit)
                          #:settings settings))
      (define loops (section3d-loops section))
      (cross-section-sample3d
       position section
       (if (null? loops) 0 (section3d-area section))
       (and (pair? loops) (section3d-centroid section))
       (section3d-diagnostics section))))
  (prepared-cross-section-function3d
   unit (vector start end) sampling (vector->immutable-vector samples)
   (hasheq 'sample-count sample-count 'step step 'settings settings)))

; volume-by-slices3d : prepared-cross-section-function3d? ... -> volume-estimate3d?
;; Uses the sampling declaration as part of the semantic contract rather than
;; silently applying an endpoint rule to midpoint data (or conversely).
(define (volume-by-slices3d prepared #:rule [rule 'trapezoid])
  (unless (prepared-cross-section-function3d? prepared)
    (raise-argument-error 'volume-by-slices3d "prepared-cross-section-function3d?" prepared))
  (unless (memq rule '(midpoint trapezoid simpson))
    (raise-argument-error 'volume-by-slices3d "midpoint, trapezoid, or simpson rule" rule))
  (define samples (prepared-cross-section-function3d-samples prepared))
  (define count (vector-length samples))
  (define start (vector-ref (prepared-cross-section-function3d-range prepared) 0))
  (define end (vector-ref (prepared-cross-section-function3d-range prepared) 1))
  (define sampling (prepared-cross-section-function3d-sampling prepared))
  (define areas (for/vector ([sample (in-vector samples)])
                  (cross-section-sample3d-area sample)))
  (define-values (value terms)
    (case rule
      [(midpoint)
       (unless (eq? sampling 'midpoints)
         (raise-arguments-error 'volume-by-slices3d
                                "midpoint-sampled prepared sections for the midpoint rule"
                                "sampling" sampling))
       (define width (/ (- end start) count))
       (values (* width (for/sum ([area (in-vector areas)]) area))
               (for/vector ([area (in-vector areas)]) (* width area)))]
      [(trapezoid)
       (unless (eq? sampling 'endpoints)
         (raise-arguments-error 'volume-by-slices3d
                                "endpoint-sampled prepared sections for the trapezoid rule"
                                "sampling" sampling))
       (define width (/ (- end start) (sub1 count)))
       (define terms
         (for/vector ([area (in-vector areas)] [index (in-naturals)])
           (* width (if (or (zero? index) (= index (sub1 count))) 1/2 1) area)))
       (values (for/sum ([term (in-vector terms)]) term) terms)]
      [else
       (unless (and (eq? sampling 'endpoints) (odd? count))
         (raise-arguments-error 'volume-by-slices3d
                                "an odd number of endpoint samples for Simpson's rule"
                                "sampling" sampling "sample-count" count))
       (define width (/ (- end start) (sub1 count)))
       (define terms
         (for/vector ([area (in-vector areas)] [index (in-naturals)])
           (* (/ width 3)
              (cond [(or (zero? index) (= index (sub1 count))) 1]
                    [(odd? index) 4]
                    [else 2])
              area)))
       (values (for/sum ([term (in-vector terms)]) term) terms)]))
  (volume-estimate3d
   value (vector->immutable-vector terms) #f
   (hasheq 'rule rule 'sampling sampling 'sample-count count
           'range (prepared-cross-section-function3d-range prepared))))

(define (check-range who range)
  (unless (and (list? range) (= (length range) 2)
               (andmap finite-real? range) (< (car range) (cadr range)))
    (raise-argument-error who "ascending list of two finite reals" range))
  (values (car range) (cadr range)))
