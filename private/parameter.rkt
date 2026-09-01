#lang racket/base

;;;
;;; Scene Parameters
;;;

;; Defines an immutable convenience handle for one named scene value. A scene
;; parameter is not a Racket dynamic parameter: it identifies value state in an
;; immutable scene timeline and provides its initial semantic value.

(require "interpolation.rkt")

(provide parameter
         scene-parameter?
         parameter-id
         parameter-initial-value
         parameter-target-id)

;; scene-parameter represents one reusable named scene-value declaration.
;;  - id             symbol?        stable identity in the scene namespace.
;;  - initial-value  interpolable?  initial semantic value when installed.
(struct scene-parameter (id initial-value)
  #:transparent
  #:guard
  (lambda (id initial-value who)
    (unless (symbol? id)
      (raise-argument-error who "symbol?" id))
    (unless (interpolable? initial-value)
      (raise-argument-error who "interpolable?" initial-value))
    (values id initial-value)))

; parameter : symbol? interpolable? -> scene-parameter?
;;   Constructs one immutable scene parameter declaration.
(define (parameter id initial-value)
  (scene-parameter id initial-value))

; parameter-id : scene-parameter? -> symbol?
;;   Returns the stable scene identity of value.
(define (parameter-id value)
  (unless (scene-parameter? value)
    (raise-argument-error 'parameter-id "scene-parameter?" value))
  (scene-parameter-id value))

; parameter-initial-value : scene-parameter? -> interpolable?
;;   Returns the initial semantic value installed by scene-set-value's shorthand.
(define (parameter-initial-value value)
  (unless (scene-parameter? value)
    (raise-argument-error 'parameter-initial-value "scene-parameter?" value))
  (scene-parameter-initial-value value))

; parameter-target-id : (or/c symbol? scene-parameter?) symbol? -> symbol?
;;   Converts a public value target to its stable scene identity.
(define (parameter-target-id target who)
  (unless (symbol? who)
    (raise-argument-error 'parameter-target-id "symbol?" who))
  (cond
    [(symbol? target)
     target]
    [(scene-parameter? target)
     (scene-parameter-id target)]
    [else
     (raise-argument-error who "(or/c symbol? scene-parameter?)" target)]))
