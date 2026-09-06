#lang racket/base

;;;
;;; Spatial Relation Dependency Descriptions
;;;

;; Defines immutable declarations for inputs read by a spatial relation.  The
;; declarations are deliberately distinct from ordinary 2D relation
;; dependencies: spatial paths are resolved inside one owning view3d and a
;; camera is an explicit semantic input rather than an implicit renderer fact.


;;;
;;; Imports and Exports
;;;

(provide spatial-dependency?
         (struct-out spatial-visual-dependency)
         (struct-out spatial-value-dependency)
         (struct-out spatial-camera-dependency))


;;;
;;; Dependency Values
;;;

(define (spatial-path-fragment? value)
  (and (list? value)
       (pair? value)
       (andmap symbol? value)))

(struct spatial-visual-dependency (target)
  #:transparent
  #:guard
  (lambda (target who)
    (unless (spatial-path-fragment? target)
      (raise-argument-error who "nonempty list of symbols" target))
    target))

;; spatial-visual-dependency identifies one path relative to the owning view3d,
;; or an absolute path whose first symbol is that view's identity.

(struct spatial-value-dependency (target)
  #:transparent
  #:guard
  (lambda (target who)
    (unless (symbol? target)
      (raise-argument-error who "symbol?" target))
    target))

;; spatial-value-dependency identifies one immutable scalar scene value.

(struct spatial-camera-dependency (view-id)
  #:transparent
  #:guard
  (lambda (view-id who)
    (unless (symbol? view-id)
      (raise-argument-error who "symbol?" view-id))
    view-id))

;; spatial-camera-dependency identifies the immutable camera of one view3d.


;;;
;;; Predicate
;;;

; spatial-dependency? : any/c -> boolean?
;;   Reports whether value is a declared spatial-relation input.
(define (spatial-dependency? value)
  (or (spatial-visual-dependency? value)
      (spatial-value-dependency? value)
      (spatial-camera-dependency? value)))
