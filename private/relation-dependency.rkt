#lang racket/base

;;;
;;; Relation Dependency Descriptions
;;;

;; These immutable descriptors make a relation's inputs inspectable without
;; guessing whether a symbol denotes a scalar scene value or a Visual path.
;; EL-1 records them.  EL-2 will validate actual context reads against them.

(require "parameter.rkt"
         "visual-model.rkt"
         "visual-selection.rkt")

(provide relation-dependency?
         (struct-out value-dependency)
         (struct-out visual-dependency)
         (struct-out anchor-dependency)
         (struct-out selection-dependency))

(define (value-target? value)
  (or (symbol? value) (scene-parameter? value)))

(define (visual-target? value)
  (with-handlers ([exn:fail? (lambda (_error) #f)])
    (visual-target-path value 'visual-dependency)
    #t))

(struct value-dependency (target)
  #:transparent
  #:guard
  (lambda (target who)
    (unless (value-target? target)
      (raise-argument-error who "(or/c symbol? scene-parameter?)" target))
    target))

(struct visual-dependency (target)
  #:transparent
  #:guard
  (lambda (target who)
    (unless (visual-target? target)
      (raise-argument-error
       who
       "(or/c visual? symbol? visual-path?)"
       target))
    target))

(struct anchor-dependency (target anchor)
  #:transparent
  #:guard
  (lambda (target anchor who)
    (unless (visual-target? target)
      (raise-argument-error
       who
       "(or/c visual? symbol? visual-path?) as the target"
       target))
    (unless (symbol? anchor)
      (raise-argument-error who "symbol? as the anchor" anchor))
    (values target anchor)))

(struct selection-dependency (selection)
  #:transparent
  #:guard
  (lambda (selection who)
    (unless (visual-selection? selection)
      (raise-argument-error who "visual-selection?" selection))
    selection))

(define (relation-dependency? value)
  (or (value-dependency? value)
      (visual-dependency? value)
      (anchor-dependency? value)
      (selection-dependency? value)))
