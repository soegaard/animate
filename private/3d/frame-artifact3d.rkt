#lang racket/base

;;;
;;; Immutable Renderer Frame Artifacts
;;;

;; One frame artifact is the common result consumed by viewport composition,
;; label occlusion, picking diagnostics, and future annotation layout. It never
;; owns native resources; backends may omit attachments they cannot provide.

(require "camera3d.rkt"
         "vec3.rkt")

(provide (struct-out renderer3d-frame-artifact)
         renderer3d-frame-depth-at
         renderer3d-frame-object-at
         renderer3d-frame-project)

(struct renderer3d-frame-artifact
  (width height straight-argb depth-snapshot object-id-snapshot camera diagnostics)
  #:transparent)

; renderer3d-frame-depth-at : renderer3d-frame-artifact? integer? integer? -> (or/c #f real?)
;; Returns one top-down view depth only when the backend requested/provided it.
(define (renderer3d-frame-depth-at artifact x y)
  (unless (renderer3d-frame-artifact? artifact)
    (raise-argument-error 'renderer3d-frame-depth-at "renderer3d-frame-artifact?" artifact))
  (unless (and (exact-nonnegative-integer? x) (< x (renderer3d-frame-artifact-width artifact))
               (exact-nonnegative-integer? y) (< y (renderer3d-frame-artifact-height artifact)))
    (raise-argument-error 'renderer3d-frame-depth-at "in-bounds pixel coordinates" (vector x y)))
  (define values (renderer3d-frame-artifact-depth-snapshot artifact))
  (and values (vector-ref values (+ x (* y (renderer3d-frame-artifact-width artifact))))))

; renderer3d-frame-object-at : renderer3d-frame-artifact? integer? integer? -> (or/c #f any/c)
;; Returns a backend-neutral object/source token when object-id was requested.
(define (renderer3d-frame-object-at artifact x y)
  (unless (renderer3d-frame-artifact? artifact)
    (raise-argument-error 'renderer3d-frame-object-at "renderer3d-frame-artifact?" artifact))
  (unless (and (exact-nonnegative-integer? x) (< x (renderer3d-frame-artifact-width artifact))
               (exact-nonnegative-integer? y) (< y (renderer3d-frame-artifact-height artifact)))
    (raise-argument-error 'renderer3d-frame-object-at "in-bounds pixel coordinates" (vector x y)))
  (define values (renderer3d-frame-artifact-object-id-snapshot artifact))
  (and values (vector-ref values (+ x (* y (renderer3d-frame-artifact-width artifact))))))

; renderer3d-frame-project : renderer3d-frame-artifact? vec3? -> (or/c #f vec2?)
;; Projects through the exact camera and aspect ratio used for this artifact.
(define (renderer3d-frame-project artifact point)
  (unless (renderer3d-frame-artifact? artifact)
    (raise-argument-error 'renderer3d-frame-project "renderer3d-frame-artifact?" artifact))
  (unless (vec3? point)
    (raise-argument-error 'renderer3d-frame-project "vec3?" point))
  (camera3d-project (renderer3d-frame-artifact-camera artifact) point
                    #:aspect (/ (renderer3d-frame-artifact-width artifact)
                                (renderer3d-frame-artifact-height artifact))))
