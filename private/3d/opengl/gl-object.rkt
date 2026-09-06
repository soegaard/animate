#lang racket/base

;;;
;;; Context-Generation-Aware GL Resource Wrappers
;;;

(require racket/runtime-path
         "context-identity.rkt")

(provide (struct-out gl-resource)
         (struct-out gl-resource-context)
         (struct-out gl-context-identity)
         make-gl-resource-context
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
;; OpenGL renderer has been selected under GRacket.  `token` is compared by
;; identity so generation zero from two distinct hosts can never validate.

(struct gl-resource-context (current-identity)
  #:transparent
  #:guard
  (lambda (current-identity who)
    (unless (gl-context-identity? current-identity)
      (raise-argument-error who "gl-context-identity?" current-identity))
    current-identity))

; make-gl-resource-context : exact-nonnegative-integer? -> gl-resource-context?
;; Creates a unique fake context used by headless lifecycle tests.
(define (make-gl-resource-context generation)
  (unless (exact-nonnegative-integer? generation)
    (raise-argument-error 'make-gl-resource-context "exact-nonnegative-integer?" generation))
  (gl-resource-context (gl-context-identity (gensym 'animate-fake-gl-context)
                                             generation)))

(define-runtime-path context-host-module "context-host.rkt")

(define (context-host-procedure name)
  (dynamic-require context-host-module name))

(define (context-identity who context)
  (cond [(gl-resource-context? context)
         (gl-resource-context-current-identity context)]
        [else
         (define host? (context-host-procedure 'gl-context-host?))
         (unless (host? context)
           (raise-argument-error who
                                 "gl-resource-context? or gl-context-host?"
                                 context))
         ((context-host-procedure 'gl-context-host-identity) context)]))

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
(struct gl-resource (context-identity id byte-size deleted? label delete)
  #:mutable
  #:transparent
  #:guard
  (lambda (context-identity id byte-size deleted? label delete who)
    (unless (gl-context-identity? context-identity)
      (raise-argument-error who "gl-context-identity?" context-identity))
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
    (values context-identity id byte-size deleted? (string->immutable-string label) delete)))

(struct gl-buffer gl-resource () #:transparent)
(struct gl-vertex-array gl-resource () #:transparent)
(struct gl-shader gl-resource () #:transparent)
(struct gl-program gl-resource () #:transparent)
(struct gl-texture gl-resource () #:transparent)
(struct gl-renderbuffer gl-resource () #:transparent)
(struct gl-framebuffer gl-resource () #:transparent)

; gl-resource-generation : gl-resource? -> exact-nonnegative-integer?
;; Kept as a compact diagnostic accessor; ownership checks use the full token.
(define (gl-resource-generation resource)
  (unless (gl-resource? resource)
    (raise-argument-error 'gl-resource-generation "gl-resource?" resource))
  (gl-context-identity-generation (gl-resource-context-identity resource)))

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
  (define identity (context-identity 'gl-resource-check-current! context))
  (unless (and (eq? (gl-context-identity-token (gl-resource-context-identity resource))
                   (gl-context-identity-token identity))
               (= (gl-context-identity-generation (gl-resource-context-identity resource))
                  (gl-context-identity-generation identity)))
    (raise-arguments-error 'gl-resource-check-current!
                           "a resource from the current OpenGL context identity"
                           "resource-generation" (gl-resource-generation resource)
                           "context-generation" (gl-context-identity-generation identity)
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
