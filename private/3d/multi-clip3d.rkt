#lang racket/base

;;;
;;; Ordered Render-Only Multi-Plane Clips
;;;

(require "bounds3.rkt"
         "clipping3d.rkt"
         "ray-plane.rkt"
         "spatial-visual.rkt"
         "vec3.rkt")

(provide clip-planes3d clip-box3d)

; clip-planes3d : spatial-visual? (listof clip-plane3d?) #:id symbol? -> clip3d?
;; Nested ordinary clip values retain an ordered semantic half-space sequence;
;; the existing compiler already concatenates parent clips in that order.
(define (clip-planes3d content clips #:id [id (string->symbol (format "~a-clips" (spatial-id content)))])
  (unless (spatial-visual? content) (raise-argument-error 'clip-planes3d "spatial-visual?" content))
  (unless (and (list? clips) (pair? clips) (andmap clip-plane3d? clips))
    (raise-argument-error 'clip-planes3d "nonempty list of clip-plane3d?" clips))
  (unless (symbol? id) (raise-argument-error 'clip-planes3d "symbol?" id))
  (for/fold ([current content]) ([clip (in-list (reverse clips))] [index (in-naturals)])
    (clip3d current clip #:id (if (= index (sub1 (length clips)))
                                  id
                                  (string->symbol (format "~a-plane-~a" id index))))))

; clip-box3d : spatial-visual? aabb3? #:id symbol? -> clip3d?
;; Builds the six inclusive half-spaces of an authored local-axis box.
(define (clip-box3d content bounds #:id [id (string->symbol (format "~a-box-clip" (spatial-id content)))])
  (unless (aabb3? bounds) (raise-argument-error 'clip-box3d "aabb3?" bounds))
  (when (aabb3-empty? bounds) (raise-argument-error 'clip-box3d "nonempty aabb3?" bounds))
  (define low (aabb3-minimum bounds))
  (define high (aabb3-maximum bounds))
  (clip-planes3d
   content
   (list (clip-plane3d (plane3 (vec3 (vec3-x low) 0 0) x-axis3))
         (clip-plane3d (plane3 (vec3 (vec3-x high) 0 0) (vec3 -1 0 0)))
         (clip-plane3d (plane3 (vec3 0 (vec3-y low) 0) y-axis3))
         (clip-plane3d (plane3 (vec3 0 (vec3-y high) 0) (vec3 0 -1 0)))
         (clip-plane3d (plane3 (vec3 0 0 (vec3-z low)) z-axis3))
         (clip-plane3d (plane3 (vec3 0 0 (vec3-z high)) (vec3 0 0 -1))))
   #:id id))
