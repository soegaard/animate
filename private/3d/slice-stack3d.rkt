#lang racket/base

;;;
;;; Deterministic Stacks of Plane Sections
;;;

(require "../geometry.rkt"
         "clipping3d.rkt"
         "curve3d.rkt"
         "mesh3d.rkt"
         "ray-plane.rkt"
         "spatial-group.rkt"
         "spatial-visual.rkt"
         "tube-style3d.rkt"
         "vec3.rkt")

(provide slice-stack3d)

; slice-stack3d : mesh3d? ... -> group3d?
;; Returns sections in increasing signed-distance order along `#:normal`.
;; Every child is present even if its plane misses the mesh, so paths do not
;; appear or disappear as an animated stack passes through an object.
(define (slice-stack3d mesh
                       #:normal normal
                       #:range range
                       #:count count
                       #:style [style (tube-style3d #:radius 1/80 #:sides 8 #:color "goldenrod")]
                       #:id [id 'slice-stack])
  (unless (mesh3d? mesh)
    (raise-argument-error 'slice-stack3d "mesh3d?" mesh))
  (unless (and (vec3? normal) (positive? (vec3-length normal)))
    (raise-argument-error 'slice-stack3d "nonzero vec3? normal" normal))
  (define-values (start end) (check-range 'slice-stack3d range))
  (unless (exact-positive-integer? count)
    (raise-argument-error 'slice-stack3d "exact positive count" count))
  (unless (tube-style3d? style)
    (raise-argument-error 'slice-stack3d "tube-style3d?" style))
  (unless (symbol? id)
    (raise-argument-error 'slice-stack3d "symbol?" id))
  (define unit (vec3-normalize normal))
  (group3d
   (for/list ([index (in-range count)])
     (define position
       (if (= count 1)
           (/ (+ start end) 2)
           (+ start (* (/ index (sub1 count)) (- end start)))))
     (section-curve3d
      mesh (plane3 (vec3-scale position unit) unit)
      #:id (string->symbol (format "~a-~a" id index))
      #:style style))
   #:id id))

(define (check-range who range)
  (unless (and (list? range) (= (length range) 2)
               (andmap finite-real? range) (< (car range) (cadr range)))
    (raise-argument-error who "ascending list of two finite reals" range))
  (values (car range) (cadr range)))
