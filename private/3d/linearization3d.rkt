#lang racket/base

(require "../geometry.rkt"
         "eigensystem3d.rkt"
         "jacobian3d.rkt"
         "point-line-arrow3d.rkt"
         "ray-plane.rkt"
         "spatial-group.rkt"
         "stroke3d.rkt"
         "vec3.rkt")

(provide (struct-out linearization3d)
         linearize3d
         linearization-diagram3d)

(struct linearization3d
  (point jacobian eigenvalues real-directions invariant-planes classification diagnostics)
  #:transparent)

(define (linearize3d field point
                     #:time [time 0]
                     #:jacobian [derivative #f]
                     #:tolerance [tolerance 1e-8])
  (unless (vec3-finite? point) (raise-argument-error 'linearize3d "finite vec3?" point))
  (unless (and (finite-real? tolerance) (positive? tolerance))
    (raise-argument-error 'linearize3d "positive finite real as #:tolerance" tolerance))
  (define jac (jacobian3d field point #:time time #:derivative derivative))
  (define spectrum (eigensystem3d-of (jacobian3d-result-matrix jac) #:tolerance tolerance))
  (define values (eigensystem3d-eigenvalues spectrum))
  (define directions (eigensystem3d-real-directions spectrum))
  ;; A real eigendirection complementary to a complex conjugate pair is the
  ;; normal of that pair's invariant plane.  An absent direction is reported,
  ;; never fabricated from numerically unstable complex algebra.
  (define planes
    (vector->immutable-vector
     (list->vector
      (for/list ([i (in-range (vector-length values))]
                 #:when (> (imag-part (vector-ref values i)) tolerance))
        (define normal-index
          (for/first ([j (in-range (vector-length values))]
                      #:when (and (<= (abs (imag-part (vector-ref values j))) tolerance)
                                  (vector-ref directions j)))
            j))
        (and normal-index (plane3 point (vector-ref directions normal-index)))))))
  (define classification (classify values tolerance (eigensystem3d-diagnostics spectrum)))
  (linearization3d
   point jac values directions planes classification
   (hasheq 'tolerance tolerance
           'eigensystem (eigensystem3d-diagnostics spectrum)
           'jacobian-method (jacobian3d-result-method jac)
           'near-nonhyperbolic?
           (for/or ([value (in-vector values)]) (<= (abs (real-part value)) tolerance)))))

(define (classify values tolerance eigendiagnostics)
  (define reals (for/list ([value (in-vector values)]) (real-part value)))
  (define complex? (for/or ([value (in-vector values)]) (> (abs (imag-part value)) tolerance)))
  (cond [(hash-ref eigendiagnostics 'defective-or-near-defective?) 'indeterminate]
        [(ormap (lambda (x) (<= (abs x) tolerance)) reals)
         (if complex? 'center-like 'nonhyperbolic)]
        [(andmap negative? reals) (if complex? 'spiral-sink 'sink)]
        [(andmap positive? reals) (if complex? 'spiral-source 'source)]
        [else 'saddle]))

;; Lower only retained real eigendirections. Complex invariant planes remain
;; explicit data on the linearization; rendering a finite plane patch would
;; falsely imply a canonical size, so authors can choose their own plane/ring
;; visual around that data.
(define (linearization-diagram3d value
                                 #:id [id 'linearization]
                                 #:stable-style [stable-style (stroke3d #:color "royalblue")]
                                 #:unstable-style [unstable-style (stroke3d #:color "tomato")]
                                 #:center-style [center-style (stroke3d #:color "goldenrod")]
                                 #:scale [scale 1])
  (unless (linearization3d? value) (raise-argument-error 'linearization-diagram3d "linearization3d?" value))
  (unless (symbol? id) (raise-argument-error 'linearization-diagram3d "symbol? as #:id" id))
  (unless (and (finite-real? scale) (positive? scale)) (raise-argument-error 'linearization-diagram3d "positive finite real as #:scale" scale))
  (define tolerance (hash-ref (linearization3d-diagnostics value) 'tolerance))
  (group3d
   (for/list ([direction (in-vector (linearization3d-real-directions value))]
              [eigenvalue (in-vector (linearization3d-eigenvalues value))]
              [index (in-naturals)] #:when direction)
     (define style (cond [(< (real-part eigenvalue) (- tolerance)) stable-style]
                         [(> (real-part eigenvalue) tolerance) unstable-style]
                         [else center-style]))
     (define offset (vec3-scale scale direction))
     (line3d (vec3- (linearization3d-point value) offset)
             (vec3+ (linearization3d-point value) offset)
             #:id (string->symbol (format "eigendirection-~a" index)) #:style style))
   #:id id))
