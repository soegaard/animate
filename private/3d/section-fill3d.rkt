#lang racket/base

;;;
;;; Filled Plane Sections
;;;

;; A section fill is intentionally just separately addressable cap geometry.
;; It does not claim to repair or close its source mesh, and it shares the cap
;; triangulator's explicit current limitation for concave or holed loops.

(require "../geometry.rkt"
         "cap-style3d.rkt"
         "clipping3d.rkt"
         "material3d.rkt"
         "mesh-cut3d.rkt")

(provide section-fill3d)

; section-fill3d : section3d? ... -> (or/c #f mesh3d?)
;; Builds an independently styleable mesh on one side of a retained section.
(define (section-fill3d section
                        #:side [side 'positive]
                        #:material [material (cap-style3d-material default-cap-style3d)]
                        #:offset [offset 0]
                        #:id [id 'section-fill])
  (unless (section3d? section)
    (raise-argument-error 'section-fill3d "section3d?" section))
  (unless (memq side '(positive negative))
    (raise-argument-error 'section-fill3d "positive or negative side" side))
  (unless (material3d? material)
    (raise-argument-error 'section-fill3d "material3d?" material))
  (unless (finite-real? offset)
    (raise-argument-error 'section-fill3d "finite real offset" offset))
  (unless (symbol? id)
    (raise-argument-error 'section-fill3d "symbol?" id))
  (cap-section3d section #:side side #:id id
                 #:style (cap-style3d material offset)))
