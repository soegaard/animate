#lang racket/base

;;;
;;; Declarative 3D Renderer Capabilities
;;;

;; A renderer capability report is immutable data. It deliberately has no
;; renderer, OpenGL, or scene dependency, so planning, project checks, and a
;; live backend can reason about the same declaration without creating a
;; context or rendering a frame.

(require racket/list
         racket/set)

(provide (struct-out renderer3d-capabilities)
         renderer3d-known-features
         renderer3d-known-limits
         renderer3d-supports?
         renderer3d-capability-limit
         renderer3d-missing-capabilities
         renderer3d-require-capabilities)

;; These are the vocabulary of the V roadmap. A backend advertises only the
;; subset it implements today; naming a capability here is never a claim that
;; every renderer supports it.
(define renderer3d-known-features
  (seteq 'wireframe
         'opaque-triangles
         'perspective
         'orthographic
         'depth-buffer
         'flat-shading
         'smooth-shading
         'transparency
         'clipping-planes
         'screen-strokes
         'linear-depth
         'object-id
         'ambient-light
         'directional-light
         'point-light
         'spot-light
         'specular
         'emission
         'directional-shadow
         'spot-shadow))

(define renderer3d-known-limits
  (seteq 'maximum-directional-lights
         'maximum-point-lights
         'maximum-spot-lights
         'maximum-shadow-lights
         'maximum-clip-planes
         'maximum-shadow-map-size
         'maximum-samples))

;; `transparent-limit-value?` accepts the exact numeric limits used by the
;; current backends and transparent structs for later bounded resources. An
;; opaque struct would hide the information a project diagnostic needs.
(define (transparent-limit-value? value)
  (or (and (number? value) (exact? value))
      (and (struct? value)
           (with-handlers ([exn:fail? (lambda (_error) #f)])
             (define vector (struct->vector value))
             (and (vector? vector)
                  (not (and (= (vector-length vector) 2)
                            (eq? (vector-ref vector 1) '...))))))))

(define (immutable-symbol-set? value)
  (and (set? value)
       (not (set-mutable? value))
       (not (set-weak? value))
       (for/and ([feature (in-set value)]) (symbol? feature))))

(define (immutable-limit-hash? value)
  (and (hash? value)
       (immutable? value)
       (for/and ([(key limit) (in-hash value)])
         (and (symbol? key) (transparent-limit-value? limit)))))

(define (immutable-diagnostic-hash? value)
  (and (hash? value) (immutable? value)))

(struct renderer3d-capabilities (features limits diagnostics)
  #:transparent
  #:guard
  (lambda (features limits diagnostics who)
    (unless (immutable-symbol-set? features)
      (raise-argument-error who "immutable set of symbols" features))
    (unless (immutable-limit-hash? limits)
      (raise-argument-error
       who
       "immutable hash mapping symbols to exact numbers or transparent values"
       limits))
    (unless (immutable-diagnostic-hash? diagnostics)
      (raise-argument-error who "immutable hash? as diagnostics" diagnostics))
    (values features limits diagnostics)))

(define (normalize-features who value)
  (cond [(symbol? value) (list value)]
        [(and (list? value) (andmap symbol? value)) value]
        [(and (set? value) (for/and ([feature (in-set value)]) (symbol? feature)))
         (set->list value)]
        [else
         (raise-argument-error who
                               "symbol?, list of symbols, or set of symbols"
                               value)]))

;; renderer3d-supports? : renderer3d-capabilities? feature-or-features -> boolean?
;; A compound request succeeds only when every requested feature is present.
(define (renderer3d-supports? capabilities features)
  (unless (renderer3d-capabilities? capabilities)
    (raise-argument-error 'renderer3d-supports? "renderer3d-capabilities?" capabilities))
  (for/and ([feature (in-list (normalize-features 'renderer3d-supports? features))])
    (set-member? (renderer3d-capabilities-features capabilities) feature)))

;; renderer3d-capability-limit : renderer3d-capabilities? symbol? [any/c] -> any/c
;; `default` deliberately makes absence observable without conflating it with
;; the exact numeric limit zero.
(define (renderer3d-capability-limit capabilities limit [default #f])
  (unless (renderer3d-capabilities? capabilities)
    (raise-argument-error 'renderer3d-capability-limit
                          "renderer3d-capabilities?" capabilities))
  (unless (symbol? limit)
    (raise-argument-error 'renderer3d-capability-limit "symbol?" limit))
  (hash-ref (renderer3d-capabilities-limits capabilities) limit default))

(define (renderer3d-missing-capabilities capabilities features)
  (unless (renderer3d-capabilities? capabilities)
    (raise-argument-error 'renderer3d-missing-capabilities
                          "renderer3d-capabilities?" capabilities))
  (for/list ([feature (in-list (normalize-features 'renderer3d-missing-capabilities features))]
             #:unless (set-member? (renderer3d-capabilities-features capabilities) feature))
    feature))

;; renderer3d-require-capabilities : renderer3d-capabilities? feature-or-features -> void?
;; Raises one descriptive, deterministic exception before work begins.
(define (renderer3d-require-capabilities capabilities features)
  (unless (renderer3d-capabilities? capabilities)
    (raise-argument-error 'renderer3d-require-capabilities
                          "renderer3d-capabilities?" capabilities))
  (define required (normalize-features 'renderer3d-require-capabilities features))
  (define missing (renderer3d-missing-capabilities capabilities required))
  (unless (null? missing)
    (raise-arguments-error
     'renderer3d-require-capabilities
     "a renderer supporting every required feature"
     "required" required
     "missing" missing
     "available" (sort (set->list (renderer3d-capabilities-features capabilities)) symbol<?)
     "diagnostics" (renderer3d-capabilities-diagnostics capabilities)))
  (void))
