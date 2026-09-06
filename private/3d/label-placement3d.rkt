#lang racket/base

;;;
;;; Declarative Screen-Space Label Placement Policy
;;;

(require "../geometry.rkt")

(provide (struct-out label-placement3d)
         (struct-out leader-style3d)
         default-label-placement3d)

(struct label-placement3d
  (preferred distance candidates keep-inside? avoid-overlap? avoid stability-weight leader-threshold)
  #:transparent
  #:guard
  (lambda (preferred distance candidates keep-inside? avoid-overlap? avoid stability-weight leader-threshold who)
    (unless (and (list? preferred) (pair? preferred) (andmap direction? preferred))
      (raise-argument-error who "nonempty list of compass directions" preferred))
    (for ([value (in-list (list distance leader-threshold))])
      (unless (and (finite-real? value) (>= value 0))
        (raise-argument-error who "nonnegative finite pixel distance" value)))
    (unless (and (exact-positive-integer? candidates) (<= candidates 8))
      (raise-argument-error who "exact positive candidate count at most 8" candidates))
    (unless (and (boolean? keep-inside?) (boolean? avoid-overlap?) (list? avoid)
                 (and (finite-real? stability-weight) (>= stability-weight 0)))
      (raise-argument-error who "valid label placement options"
                            (list keep-inside? avoid-overlap? avoid stability-weight)))
    (values preferred distance candidates keep-inside? avoid-overlap? avoid stability-weight leader-threshold)))

;; A leader remains renderer-neutral author data.  The final 2D compositor
;; draws it, rather than introducing a miniature 3D mesh that would blur text
;; layout or need a separate depth policy.  `nearest` attaches at the edge of
;; the label box closest to the anchor; `center` starts at its centre.
(struct leader-style3d (attachment elbow? minimum-length)
  #:transparent
  #:guard
  (lambda (attachment elbow? minimum-length who)
    (unless (memq attachment '(nearest center))
      (raise-argument-error who "(or/c 'nearest 'center) attachment" attachment))
    (unless (boolean? elbow?)
      (raise-argument-error who "boolean? elbow?" elbow?))
    (unless (and (finite-real? minimum-length) (>= minimum-length 0))
      (raise-argument-error who "nonnegative finite pixel minimum length" minimum-length))
    (values attachment elbow? minimum-length)))

(define (direction? value) (memq value '(north north-east east south-east south south-west west north-west)))

(define default-label-placement3d
  (label-placement3d '(north-east east north) 10 8 #t #t '() 1 12))
