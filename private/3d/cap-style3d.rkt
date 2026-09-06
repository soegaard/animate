#lang racket/base

(require "../geometry.rkt"
         "material3d.rkt")

(provide (struct-out cap-style3d) default-cap-style3d)

;; Cap style deliberately contains no renderer state.  Offset is a local-world
;; distance used only by section fills to avoid coincident z fighting.
(struct cap-style3d (material offset) #:transparent
  #:guard
  (lambda (material offset who)
    (unless (material3d? material) (raise-argument-error who "material3d?" material))
    (unless (finite-real? offset)
      (raise-argument-error who "finite real?" offset))
    (values material offset)))

(define default-cap-style3d
  (cap-style3d (material3d #:color "goldenrod" #:shading 'flat) 0))
