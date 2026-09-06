#lang racket/base

;;;
;;; Context-Generation-Aware GL Resource Wrappers
;;;

(require racket/runtime-path)

(provide (struct-out gl-resource)
         (struct-out gl-resource-context)
         (struct-out gl-buffer)
         (struct-out gl-vertex-array)
         (struct-out gl-shader)
         (struct-out gl-program)
         (struct-out gl-texture)
         (struct-out gl-renderbuffer)
         (struct-out gl-framebuffer)
         gl-resource-live?
         gl-resource-check-current!
         gl-resource-delete-current!
         gl-resource-delete!)

;; The resource state machine is deliberately independent of racket/gui/base.
;; This lightweight token is used by fake-GL unit tests; production calls pass
;; the real context host, which is resolved lazily below only after an explicit
;; OpenGL renderer has been selected under GRacket.
(struct gl-resource-context (generation)
  #:transparent
  #:guard
  (lambda (generation who)
    (unless (exact-nonnegative-integer? generation)
      (raise-argument-error who "exact-nonnegative-integer?" generation))
    generation))

(define-runtime-path context-host-module "context-host.rkt")

(define (context-host-procedure name)
  (dynamic-require context-host-module name))

(define (context-generation who context)
  (cond [(gl-resource-context? context)
         (gl-resource-context-generation context)]
        [else
         (define host? (context-host-procedure 'gl-context-host?))
         (unless (host? context)
           (raise-argument-error who
                                 "gl-resource-context? or gl-context-host?"
                                 context))
         ((context-host-procedure 'gl-context-host-generation) context)]))

(define (context-call who context thunk)
  (cond [(gl-resource-context? context)
         (raise-arguments-error who "a live OpenGL context host"
                                "context" context)]
        [else
         (define host? (context-host-procedure 'gl-context-host?))
         (unless (host? context)
           (raise-argument-error who
                                 "gl-resource-context? or gl-context-host?"
                                 context))
         ((context-host-procedure 'gl-context-host-call) context thunk)]))

;; `delete` is a backend-private function of one GLuint.  It is not exposed by
;; an authoring value and is deliberately supplied by the central GL API layer.
(struct gl-resource (generation id byte-size deleted? label delete)
  #:mutable
  #:transparent
  #:guard
  (lambda (generation id byte-size deleted? label delete who)
    (unless (exact-nonnegative-integer? generation)
      (raise-argument-error who "exact-nonnegative-integer?" generation))
    (unless (exact-nonnegative-integer? id)
      (raise-argument-error who "exact-nonnegative-integer?" id))
    (unless (exact-nonnegative-integer? byte-size)
      (raise-argument-error who "exact-nonnegative-integer?" byte-size))
    (unless (boolean? deleted?)
      (raise-argument-error who "boolean?" deleted?))
    (unless (string? label)
      (raise-argument-error who "string?" label))
    (unless (procedure? delete)
      (raise-argument-error who "procedure?" delete))
    (values generation id byte-size deleted? (string->immutable-string label) delete)))

(struct gl-buffer gl-resource () #:transparent)
(struct gl-vertex-array gl-resource () #:transparent)
(struct gl-shader gl-resource () #:transparent)
(struct gl-program gl-resource () #:transparent)
(struct gl-texture gl-resource () #:transparent)
(struct gl-renderbuffer gl-resource () #:transparent)
(struct gl-framebuffer gl-resource () #:transparent)

(define (gl-resource-live? resource)
  (unless (gl-resource? resource)
    (raise-argument-error 'gl-resource-live? "gl-resource?" resource))
  (not (gl-resource-deleted? resource)))

; gl-resource-check-current! : gl-resource? (or/c gl-resource-context? gl-context-host?) -> void?
(define (gl-resource-check-current! resource context)
  (unless (gl-resource? resource)
    (raise-argument-error 'gl-resource-check-current! "gl-resource?" resource))
  (when (gl-resource-deleted? resource)
    (raise-arguments-error 'gl-resource-check-current! "a live OpenGL resource"
                           "resource" resource))
  (define generation (context-generation 'gl-resource-check-current! context))
  (unless (= (gl-resource-generation resource) generation)
    (raise-arguments-error 'gl-resource-check-current!
                           "a resource from the current OpenGL context generation"
                           "resource-generation" (gl-resource-generation resource)
                           "context-generation" generation
                           "resource-label" (gl-resource-label resource)))
  (void))

; gl-resource-delete! : gl-resource? (or/c gl-resource-context? gl-context-host?) -> boolean?
;; Returns #t exactly when it deleted a live resource.  Double deletion is
;; intentional no-op behaviour, so cleanup after partial construction is safe.
(define (gl-resource-delete-current! resource context)
  (unless (gl-resource? resource)
    (raise-argument-error 'gl-resource-delete-current! "gl-resource?" resource))
  (cond [(gl-resource-deleted? resource) #f]
        [else
         (gl-resource-check-current! resource context)
         ((gl-resource-delete resource) (gl-resource-id resource))
         (set-gl-resource-deleted?! resource #t)
         #t]))

(define (gl-resource-delete! resource context)
  (unless (gl-resource? resource)
    (raise-argument-error 'gl-resource-delete! "gl-resource?" resource))
  (context-call 'gl-resource-delete! context
                (lambda () (gl-resource-delete-current! resource context))))
