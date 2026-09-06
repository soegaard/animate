#lang racket/base

;;;
;;; Direct-Time Surface Animation Requests
;;;

;; Surface reveals and morphs retain source grids at compilation, then derive
;; their frame at the requested timeline time.  No request stores or reads an
;; earlier rendered surface.


;;;
;;; Imports and Exports
;;;

(require "parametric-surface3d.rkt"
         "spatial-path.rkt")

(provide reveal-surface-u
         reveal-surface-u-request?
         reveal-surface-v
         reveal-surface-v-request?
         transform-surface3d
         transform-surface3d-request?
         spatial-surface-animation-request?
         spatial-surface-compiled-animation?
         reveal-surface-request-target-path
         reveal-surface-request-axis
         transform-surface3d-request-target-path
         transform-surface3d-request-destination
         (struct-out reveal-surface-animation)
         (struct-out surface-transform-animation))


;;;
;;; Requests
;;;

(struct reveal-surface-request (target-path axis) #:transparent)
(struct transform-surface3d-request (target-path destination) #:transparent)

; reveal-surface-u : spatial-path? -> reveal-surface-u-request?
;;   Reveals an existing surface from its minimum u boundary.
(define (reveal-surface-u target-path)
  (check-path 'reveal-surface-u target-path)
  (reveal-surface-request target-path 'u))

; reveal-surface-v : spatial-path? -> reveal-surface-v-request?
;;   Reveals an existing surface from its minimum v boundary.
(define (reveal-surface-v target-path)
  (check-path 'reveal-surface-v target-path)
  (reveal-surface-request target-path 'v))

; transform-surface3d : spatial-path? surface3d? -> transform-surface3d-request?
;;   Morphs one existing surface to an equal-topology destination surface.
(define (transform-surface3d target-path destination)
  (check-path 'transform-surface3d target-path)
  (unless (surface3d? destination)
    (raise-argument-error 'transform-surface3d "surface3d?" destination))
  (transform-surface3d-request target-path destination))


;;;
;;; Compiled Values
;;;

(struct reveal-surface-animation (target-path surface axis) #:transparent)
(struct surface-transform-animation (target-path source destination) #:transparent)


;;;
;;; Predicates
;;;

(define (reveal-surface-u-request? value)
  (and (reveal-surface-request? value) (eq? (reveal-surface-request-axis value) 'u)))

(define (reveal-surface-v-request? value)
  (and (reveal-surface-request? value) (eq? (reveal-surface-request-axis value) 'v)))

(define (spatial-surface-animation-request? value)
  (or (reveal-surface-request? value) (transform-surface3d-request? value)))

(define (spatial-surface-compiled-animation? value)
  (or (reveal-surface-animation? value) (surface-transform-animation? value)))

(define (check-path who value)
  (unless (and (spatial-path? value) (pair? (cdr value)))
    (raise-argument-error who "view-rooted nonempty spatial path" value)))
