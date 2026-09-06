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

;; The first release retains a renderer-neutral leader descriptor. A 2D line is
;; produced by the Pict adapter rather than a miniature 3D mesh.
(struct leader-style3d (attachment elbow? minimum-length) #:transparent)

(define (direction? value) (memq value '(north north-east east south-east south south-west west north-west)))

(define default-label-placement3d
  (label-placement3d '(north-east east north) 10 8 #t #t '() 1 12))
