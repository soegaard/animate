#lang racket/base

;;;
;;; Deferred mapped-request templates
;;;

;; A procedure-backed template is deliberately marked nonserializable. The
;; transparent named form leaves room for project/worker serializable recipes
;; without pretending that arbitrary closures can be written to a project file.

(require "target-sequence.rkt")

(provide request-template
         request-template?
         request-template-name
         request-template-procedure
         request-template-serializable?
         named-request-template
         procedure-request-template
         current-request-template-resolver
         instantiate-request-template)

(struct request-template (name procedure serializable?)
  #:transparent
  #:guard
  (lambda (name procedure serializable? who)
    (unless (symbol? name)
      (raise-argument-error who "symbol? as template name" name))
    (unless (boolean? serializable?)
      (raise-argument-error who "boolean? as serializable?" serializable?))
    (cond
      [serializable?
       (unless (not procedure)
         (raise-arguments-error
          who
          "a named serializable template without an embedded procedure"
          "procedure" procedure))]
      [else
       (unless (procedure? procedure)
         (raise-argument-error who "procedure?" procedure))])
    (values name procedure serializable?)))

(define (named-request-template name)
  (request-template name #f #t))

(define (procedure-request-template procedure #:name [name 'procedure-template])
  (request-template name procedure #f))

;; A project/worker implementation may parameterize this resolver to map a
;; transparent named template to its trusted registered implementation. Keeping
;; the resolver outside a request value is what makes the value itself
;; serializable rather than smuggling an arbitrary closure into project data.
;; The resolver receives the template name and immutable compile context and
;; must return a one-argument target-ref procedure.
(define current-request-template-resolver (make-parameter #f))

(define (instantiate-request-template template target context)
  (unless (target-ref? target)
    (raise-argument-error 'instantiate-request-template "target-ref?" target))
  (define procedure
    (cond [(request-template? template)
           (or (request-template-procedure template)
               (let ([resolver (current-request-template-resolver)])
                 (unless (procedure? resolver)
                   (raise-arguments-error
                    'instantiate-request-template
                    "a registered resolver for a named serializable template"
                    "template-name" (request-template-name template)
                    "compile-context" context))
                 (resolver (request-template-name template) context)))]
          [(procedure? template) template]
          [else
           (raise-argument-error
            'instantiate-request-template "request-template? or procedure?" template)]))
  (unless (procedure? procedure)
    (raise-arguments-error
     'instantiate-request-template
     "a registered template implementation procedure"
     "template" template
     "resolved-implementation" procedure))
  (unless (procedure-arity-includes? procedure 1)
    (raise-arguments-error
     'instantiate-request-template
     "a template procedure accepting one target-ref"
     "template" template))
  (with-handlers ([exn:fail?
                   (lambda (exception)
                     (raise-arguments-error
                      'instantiate-request-template
                      "mapped request template raised an exception"
                      "source-index" (target-ref-source-index target)
                      "scheduled-index" (target-ref-scheduled-index target)
                      "resolved-path" (target-ref-path target)
                      "target-ref" target
                      "exception-message" (exn-message exception)))])
    (procedure target)))
