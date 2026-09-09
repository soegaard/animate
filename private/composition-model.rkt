#lang racket/base

;;;
;;; Immutable composition request values
;;;

;; This module deliberately contains only data definitions.  In particular it
;; does not require scene.rkt, animation.rkt, or a renderer.  Keeping the
;; transparent values here lets effect recipes construct ordinary compositions
;; without a dynamic import back into the scene compiler.

(require "geometry.rkt")

(provide (struct-out timed-animation-request)
         (struct-out succession-animation-request)
         (struct-out animation-group-animation-request)
         (struct-out lagged-start-animation-request)
         (struct-out style-to-animation-request)
         (struct-out deferred-map-request)
         (struct-out cycle-animation-request)
         composition-succession
         composition-animation-group
         composition-lagged-start)

(struct timed-animation-request (request start duration easing)
  #:transparent)

(struct succession-animation-request (requests)
  #:transparent)

(struct animation-group-animation-request (requests)
  #:transparent)

(struct lagged-start-animation-request (requests lag-ratio)
  #:transparent)

(struct style-to-animation-request (requests)
  #:transparent)

;; The scene compiler resolves the target sequence at the mapped operation's
;; local start. `template` is intentionally opaque to this pure model module:
;; request-template.rkt owns instantiation and serializability diagnostics.
(struct deferred-map-request (target-sequence template topology lag-ratio order delay-plan)
  #:transparent)

;; A cycle remains explicit until its local-start validation has run. It then
;; lowers to an ordinary succession, retaining all existing duration scaling.
(struct cycle-animation-request (requests kind)
  #:transparent)

;; These constructors intentionally validate only representation invariants.
;; Scene-level admissibility (Visual, scalar, and camera request protocols) is
;; checked by scene.rkt at the public scheduling boundary.
(define (composition-succession requests)
  (unless (and (list? requests) (pair? requests))
    (raise-argument-error 'composition-succession "nonempty list?" requests))
  (succession-animation-request (for/list ([request (in-list requests)]) request)))

(define (composition-animation-group requests)
  (unless (and (list? requests) (pair? requests))
    (raise-argument-error 'composition-animation-group "nonempty list?" requests))
  (animation-group-animation-request
   (for/list ([request (in-list requests)]) request)))

(define (composition-lagged-start requests lag-ratio)
  (unless (and (list? requests) (pair? requests))
    (raise-argument-error 'composition-lagged-start "nonempty list?" requests))
  (unless (and (finite-real? lag-ratio)
               (not (negative? lag-ratio)))
    (raise-argument-error
     'composition-lagged-start "nonnegative finite real?" lag-ratio))
  (lagged-start-animation-request
   (for/list ([request (in-list requests)]) request)
   lag-ratio))
