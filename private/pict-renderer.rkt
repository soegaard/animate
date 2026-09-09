#lang racket/base

;;;
;;; Pict Renderer Protocol
;;;

;; Defines the adapter-specific protocol used to render semantic Visual values.
;;
;; Renderer selection is explicit and deterministic. No process-global renderer
;; registry is mutated when a new Visual type is added.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/generic
         (only-in pict pict?)
         "camera.rkt"
         "visual-model.rkt")

;; Exports
(provide gen:pict-renderer
         pict-renderer?
         pict-renderer-supports?
         pict-renderer-render
         prop:pict-renderer-cache-identity
         pict-renderer-cache-identity
         pict-renderer-list?
         check-pict-renderer-list
         find-supporting-pict-renderer
         render-visual-with-pict-renderer
         render-visual-with-pict-renderers)


;;;
;;; Renderer Protocol
;;;

; pict-renderer-supports? : pict-renderer? visual? -> boolean?
;;   Reports whether renderer supports visual.
;
; pict-renderer-render : pict-renderer? visual? camera? -> pict?
;;   Converts a supported visual to a pict for camera.
(define-generics pict-renderer
  (pict-renderer-supports? pict-renderer visual)
  (pict-renderer-render pict-renderer visual camera))

;; A renderer can opt into persistent section caching by declaring immutable
;; appearance data. The protocol intentionally has no fallback based on a
;; printed structure or closure: unknown semantics make a section renderable
;; but not persistently reusable.
(define-values (prop:pict-renderer-cache-identity
                pict-renderer-cache-identity-property?
                pict-renderer-cache-identity-property-ref)
  (make-struct-type-property 'pict-renderer-cache-identity))

; pict-renderer-cache-identity : pict-renderer? -> (or/c immutable-datum? #f)
;; Returns a renderer's declared pixel-appearance identity, or #f when its
;; semantics are opaque and section caching must be disabled.
(define (pict-renderer-cache-identity renderer)
  (unless (pict-renderer? renderer)
    (raise-argument-error 'pict-renderer-cache-identity "pict-renderer?" renderer))
  (cond
    [(not (pict-renderer-cache-identity-property? renderer)) #f]
    [else
     (define descriptor
       (pict-renderer-cache-identity-property-ref renderer))
     (define identity
       (if (procedure? descriptor) (descriptor renderer) descriptor))
     (unless (or (not identity) (cache-identity-datum? identity))
       (raise-arguments-error
        'pict-renderer-cache-identity
        "#f or an immutable datum containing only primitive values"
        "renderer" renderer
        "identity" identity))
     identity]))

(define (cache-identity-datum? value)
  (cond [(or (null? value) (boolean? value) (symbol? value) (keyword? value)
             (char? value) (number? value)) #t]
        [(string? value) (immutable? value)]
        [(bytes? value) (immutable? value)]
        [(pair? value)
         (and (cache-identity-datum? (car value))
              (cache-identity-datum? (cdr value)))]
        [(vector? value)
         (and (immutable? value)
              (for/and ([item (in-vector value)]) (cache-identity-datum? item)))]
        [(hash? value)
         (and (immutable? value)
              (for/and ([(key item) (in-hash value)])
                (and (cache-identity-datum? key) (cache-identity-datum? item))))]
        [else #f]))


;;;
;;; Renderer Selection
;;;

; pict-renderer-list? : any/c -> boolean?
;;   Reports whether value is a list of Pict renderer implementations.
(define (pict-renderer-list? value)
  (and (list? value)
       (andmap pict-renderer? value)))

; render-visual-with-pict-renderers : visual? camera? (listof pict-renderer?)
;                                     -> pict?
;;   Renders visual with the first supporting renderer in significant order.
(define (render-visual-with-pict-renderers visual camera renderers)
  (unless (visual? visual)
    (raise-argument-error
     'render-visual-with-pict-renderers
     "visual?"
     visual))
  (unless (camera? camera)
    (raise-argument-error
     'render-visual-with-pict-renderers
     "camera?"
     camera))
  (check-pict-renderer-list
   'render-visual-with-pict-renderers
   renderers)
  (define renderer
    (find-supporting-pict-renderer visual renderers))
  (unless renderer
    (raise-arguments-error
     'render-visual-with-pict-renderers
     "no Pict renderer supports the Visual"
     "visual" visual))
  (render-visual-with-pict-renderer renderer visual camera))

; render-visual-with-pict-renderer : pict-renderer? visual? camera? -> pict?
;;   Renders visual with one already selected Pict renderer.
(define (render-visual-with-pict-renderer renderer visual camera)
  (unless (pict-renderer? renderer)
    (raise-argument-error
     'render-visual-with-pict-renderer
     "pict-renderer?"
     renderer))
  (unless (visual? visual)
    (raise-argument-error
     'render-visual-with-pict-renderer
     "visual?"
     visual))
  (unless (camera? camera)
    (raise-argument-error
     'render-visual-with-pict-renderer
     "camera?"
     camera))
  (define result
    (pict-renderer-render renderer visual camera))
  (unless (pict? result)
    (raise-arguments-error
     'render-visual-with-pict-renderer
     "a Pict renderer must return a pict"
     "renderer" renderer
     "visual" visual
     "result" result))
  result)

; find-supporting-pict-renderer : visual? (listof pict-renderer?)
;                                 -> (or/c pict-renderer? false/c)
;;   Finds the first renderer that explicitly supports visual.
(define (find-supporting-pict-renderer visual renderers)
  (let loop ([remaining renderers])
    (cond
      [(null? remaining)
       #f]
      [else
       (define renderer
         (car remaining))
       (define supports?
         (pict-renderer-supports? renderer visual))
       (unless (boolean? supports?)
         (raise-arguments-error
          'find-supporting-pict-renderer
          "a Pict renderer support method must return a boolean"
          "renderer" renderer
          "visual" visual
          "result" supports?))
       (if supports?
           renderer
           (loop (cdr remaining)))])))


;;;
;;; Validation
;;;

; check-pict-renderer-list : symbol? any/c -> void?
;;   Raises an argument error unless renderers is a Pict renderer list.
(define (check-pict-renderer-list who renderers)
  (unless (pict-renderer-list? renderers)
    (raise-argument-error
     who
     "(listof pict-renderer?)"
     renderers)))
