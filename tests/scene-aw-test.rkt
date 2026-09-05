#lang racket/base
(require "../experimental.rkt")

;;;
;;; SCENE-AW Pure Derived Visual Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define dot-template
    (circle #:id 'dot
            #:center origin
            #:radius 1
            #:fill "royalblue"
            #:stroke "navy"
            #:stroke-width 3))
  (define dot-definition
    (derived-visual
     dot-template
     (lambda (context template)
       (unless (and (derived-context? context)
                    (derived-context-value-has? context 'x)
                    (not (derived-context-value-has? context 'missing)))
         (error 'dot-resolver "unexpected derived context"))
       (visual-with-position
        template
        (vec2 (derived-context-value-ref context 'x) 0)))))

  (check-true (derived-visual? dot-definition))
  (check-true (visual? dot-definition))
  (check-equal? (visual-position dot-definition) origin)
  (define positioned-definition
    (visual-with-position dot-definition (vec2 1 2)))
  (check-true (derived-visual? positioned-definition))
  (check-equal? (visual-id positioned-definition) 'dot)
  (check-equal? (visual-position positioned-definition) (vec2 1 2))
  (check-exn exn:fail:contract?
             (lambda () (derived-visual 42 (lambda (context template) template))))
  (check-exn exn:fail:contract?
             (lambda () (derived-visual dot-template (lambda (context) context))))
  (check-exn
   exn:fail?
   (lambda ()
     (derived-visual
      dot-definition
      (lambda (context template) template))))

  (define base
    (scene-add
     (scene-set-value (make-scene) 'x 0)
     dot-definition))
  (define base-state (scene-current-state base))

  ;; scene-state-ref retains the persistent definition; resolved lookup evaluates
  ;; it from this immutable state's named scalar values.
  (check-true (derived-visual? (scene-state-ref base-state 'dot)))
  (define resolved-base
    (scene-state-resolved-ref base-state 'dot))
  (check-true (circle-visual? resolved-base))
  (check-equal? (visual-id resolved-base) 'dot)
  (check-equal? (visual-position resolved-base) origin)

  ;; Ordinary Visuals pass through resolved lookup unchanged and drawing order
  ;; remains significant after resolution.
  (define guide
    (line (vec2 -4 -2) (vec2 4 -2) #:id 'guide #:stroke "gray"))
  (define with-guide (scene-add base guide))
  (define resolved-visuals
    (scene-state-resolved-visuals-in-drawing-order
     (scene-current-state with-guide)))
  (check-equal? (map visual-id resolved-visuals) '(dot guide))
  (check-true (circle-visual? (car resolved-visuals)))
  (check-eq? (cadr resolved-visuals)
             (scene-state-ref (scene-current-state with-guide) 'guide))

  ;; Scalar animation now drives concrete Visual geometry directly at arbitrary
  ;; scene times without mutating or replacing the stored derived definition.
  (define animated
    (scene-play base (value-to 'x 6) #:duration 3))
  (for ([sample (in-list '((0 0) (1 2) (3/2 3) (3 6)))])
    (define time (car sample))
    (define expected-x (cadr sample))
    (define state (scene-sample animated time))
    (check-true (derived-visual? (scene-state-ref state 'dot)))
    (check-equal?
     (visual-position (scene-state-resolved-ref state 'dot))
     (vec2 expected-x 0)))
  (check-equal? (visual-position
                 (scene-state-resolved-ref
                  (scene-current-state animated)
                  'dot))
                (vec2 6 0))

  ;; Composition semantics belong to the scalar leaf; the derived Visual simply
  ;; reflects the sampled immutable value state.
  (define successive
    (scene-play
     base
     (succession
      (value-to 'x 4)
      (value-to 'x -2))
     #:duration 4))
  (check-equal? (visual-position
                 (scene-state-resolved-ref (scene-sample successive 1) 'dot))
                (vec2 2 0))
  (check-equal? (visual-position
                 (scene-state-resolved-ref (scene-sample successive 2) 'dot))
                (vec2 4 0))
  (check-equal? (visual-position
                 (scene-state-resolved-ref (scene-sample successive 3) 'dot))
                (vec2 1 0))
  (check-equal? (visual-position
                 (scene-state-resolved-ref (scene-sample successive 4) 'dot))
                (vec2 -2 0))

  ;; Scene-aware path-source lookup also resolves a derived path at the request
  ;; start state rather than using its persistent template geometry.
  (define route-definition
    (derived-visual
     (line (vec2 -2 0) (vec2 2 0) #:id 'route #:stroke "gray")
     (lambda (context template)
       (define y (derived-context-value-ref context 'route-y))
       (line (vec2 -2 y) (vec2 2 y)
             #:id (visual-id template)
             #:stroke "gray"))))
  (define rider
    (circle #:id 'rider #:center (vec2 -2 0) #:radius 1/4 #:fill "black"))
  (define route-scene
    (scene-add
     (scene-add
      (scene-set-value (make-scene) 'route-y 2)
      route-definition)
     rider))
  (define routed
    (scene-play route-scene
                (move-along-path 'rider route-definition)
                #:duration 2))
  (check-equal? (visual-position (scene-state-ref (scene-sample routed 0) 'rider))
                (vec2 -2 2))
  (check-equal? (visual-position (scene-state-ref (scene-sample routed 2) 'rider))
                (vec2 2 2))

  ;; camera-follow resolves derived targets against the same sampled scalar state.
  (define followed
    (scene-play
     base
     (value-to 'x 4)
     (camera-follow 'dot)
     #:duration 4))
  (check-equal? (camera-center (scene-camera-at followed 0)) origin)
  (check-equal? (camera-center (scene-camera-at followed 2)) (vec2 2 0))
  (check-equal? (camera-center (scene-camera-at followed 4)) (vec2 4 0))

  ;; Camera fitting resolves current derived geometry rather than measuring the
  ;; unresolved definition. Playing that request centers the camera on the
  ;; derived endpoint position, not on the template's origin.
  (define fit-request
    (camera-fit-scene animated #:targets '(dot)))
  (check-true (camera-fit-request? fit-request))
  (define fitted
    (scene-play animated fit-request #:duration 1))
  (check-equal? (camera-center (scene-current-camera fitted)) (vec2 6 0))

  ;; Direct animation of a derived Visual is rejected: callers animate the
  ;; scalar sources instead of layering imperative mutations over a resolver.
  (check-exn
   (lambda (e)
     (and (exn:fail? e)
          (regexp-match? #rx"derived Visuals" (exn-message e))))
   (lambda ()
     (scene-play base (move-to 'dot (vec2 10 0)) #:duration 1)))

  ;; Resolver results are validated when concrete state is requested.
  (define bad-result
    (derived-visual
     (circle #:id 'bad #:radius 1)
     (lambda (context template) 17)))
  (define bad-id
    (derived-visual
     (circle #:id 'bad-id #:radius 1)
     (lambda (context template)
       (circle #:id 'other #:radius 1))))
  (define nested-result
    (derived-visual
     (circle #:id 'nested #:radius 1)
     (lambda (context template)
       (derived-visual
        template
        (lambda (inner-context inner-template) inner-template)))))
  (for ([definition (in-list (list bad-result bad-id nested-result))])
    (define bad-scene (scene-add (scene-set-value (make-scene) 'x 0) definition))
    (check-exn exn:fail?
               (lambda ()
                 (scene-state-resolved-ref
                  (scene-current-state bad-scene)
                  (visual-id definition)))))

  ;; Missing scalar dependencies fail through the read-only derived context.
  (define needs-y
    (derived-visual
     (circle #:id 'needs-y #:radius 1)
     (lambda (context template)
       (visual-with-position
        template
        (vec2 (derived-context-value-ref context 'y) 0)))))
  (define missing-scene (scene-add (make-scene) needs-y))
  (check-exn exn:fail?
             (lambda ()
               (scene-state-resolved-ref
                (scene-current-state missing-scene)
                'needs-y)))

  ;; Derived Visuals are still ordinary top-level identities for insertion,
  ;; removal, and the shared Visual/scalar namespace.
  (check-exn exn:fail?
             (lambda ()
               (scene-set-value base 'dot 1)))
  (define removed (scene-remove base 'dot))
  (check-false (scene-state-has? (scene-current-state removed) 'dot)))
