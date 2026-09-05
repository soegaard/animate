#lang racket/base

;;;
;;; SCENE-EL-1 Relation Visual Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; A relation carries explicit, inspectable dependencies while resolving from
  ;; the same immutable sampled-state context as an existing derived Visual.
  (define anchor
    (circle #:id 'anchor #:center (vec2 2 1) #:radius 1/2 #:fill "navy"))
  (define follower
    (relation-visual
     (circle #:id 'follower #:center origin #:radius 1/4 #:fill "gold")
     #:depends-on
     (list (visual-dependency 'anchor)
           (value-dependency 'offset))
     #:cache-key 'follower-position
     (lambda (context template)
       (check-true (relation-context? context))
       (check-true (relation-context-visual-has? context 'anchor))
       (check-true (relation-context-value-has? context 'offset))
       (define position
         (relation-context-position context 'anchor))
       (visual-with-position
        template
        (vec2+ position
               (vec2 (relation-context-value-ref context 'offset) 0))))))

  ;; A resolver may inspect its use record during resolution (for diagnostics),
  ;; but cannot mutate the sampled scene state.  The extra declaration is
  ;; allowed and reported as unused rather than rejected.
  (define observed-context #f)
  (define inspected
    (relation-visual
     (circle #:id 'inspected #:radius 1/8 #:fill "gray")
     #:depends-on (list (value-dependency 'offset) (value-dependency 'unused))
     (lambda (context template)
       (set! observed-context context)
       (relation-context-value-ref context 'offset)
       template)))

  (check-true (relation-visual? follower))
  (check-true (visual? follower))
  (check-equal? (relation-visual-dependencies follower)
                (list (visual-dependency 'anchor)
                      (value-dependency 'offset)))
  (check-eq? (relation-visual-phase follower) 'semantic)
  (check-eq? (relation-visual-structure follower) 'root-only)
  (check-eq? (relation-visual-space follower) 'world)
  (check-eq? (relation-visual-cache-key follower) 'follower-position)

  ;; Definitions remain stored.  Resolved lookup computes concrete geometry at
  ;; the requested time and draws normally through scene-state resolution.
  (define base
    (scene-add
     (scene-add
      (scene-set-value
       (scene-set-value (make-scene) 'offset 1)
       'unused 0)
      follower inspected)
     anchor))
  (define base-state (scene-current-state base))
  (check-true (relation-visual? (scene-state-ref base-state 'follower)))
  (check-equal?
   (visual-position (scene-state-resolved-ref base-state 'follower))
   (vec2 3 1))
  (void (scene-state-resolved-ref base-state 'inspected))
  (check-equal? (relation-context-used-dependencies observed-context)
                (list (value-dependency 'offset)))
  (check-equal? (relation-context-unused-dependencies observed-context)
                (list (value-dependency 'unused)))
  (define dependency-graph (scene-relation-dependency-graph base-state))
  (check-equal?
   (hash-ref dependency-graph '(follower))
   (list (visual-dependency 'anchor) (value-dependency 'offset)))
  (check-equal? (scene-validate-relations base-state) dependency-graph)
  ;; Inspection is deterministic and does not execute the relation closures.
  ;; A generic resolver with a caller-provided key is explicitly cacheable;
  ;; one without a key is reported as non-persistently-cacheable.
  (define relation-reports (scene-relation-report base-state))
  (check-equal? (map relation-resolution-report-path relation-reports)
                (list '(follower) '(inspected)))
  (check-equal? (map relation-resolution-report-order relation-reports)
                '(0 1))
  (check-eq? (relation-resolution-report-cacheability
              (car relation-reports))
             'explicit-key)
  (check-eq? (relation-resolution-report-cacheability
              (cadr relation-reports))
             'disabled)
  (check-not-false
   (pair? (relation-resolution-report-warnings
           (cadr relation-reports))))
  (check-equal?
   (relation-resolution-report-path
    (scene-relation-report base-state 'follower))
   '(follower))
  ;; The static report deliberately does not execute arbitrary author code.
  ;; The explicitly requested sampled report does, and records exactly the
  ;; declared entries read through the checked relation context.
  (define sampled-follower-report
    (scene-relation-sample-report base-state 'follower))
  (check-equal? (relation-resolution-report-used-dependencies sampled-follower-report)
                (list (visual-dependency 'anchor)
                      (value-dependency 'offset)))
  (check-equal? (relation-resolution-report-unused-dependencies sampled-follower-report)
                '())

  ;; Both an ordinary Visual and a semantic value may animate independently;
  ;; every queried sample is computed directly from its immutable state.
  (define animated
    (scene-play
     base
     (move-to 'anchor (vec2 6 1))
     (value-to 'offset 3)
     #:duration 2))
  (check-equal?
   (visual-position
    (scene-state-resolved-ref (scene-sample animated 1) 'follower))
   (vec2 6 1))
  (check-equal?
   (visual-position
    (scene-state-resolved-ref (scene-sample animated 2) 'follower))
   (vec2 9 1))

  ;; A relation's resolver-local geometry continues to follow its dependencies
  ;; while ordinary animation updates the independent outer envelope.
  (define independently-moved
    (scene-play base (move-to 'follower (vec2 8 0)) #:duration 1))
  (check-equal?
   (visual-position
    (scene-state-resolved-ref
     (scene-current-state independently-moved) 'follower))
   (vec2 11 1))

  ;; Semantic reads cannot silently grow a relation's declared graph.
  (define undeclared
    (relation-visual
     (circle #:id 'undeclared #:radius 1/8)
     #:depends-on (list (value-dependency 'offset))
     (lambda (context template)
       (relation-context-visual-ref context 'anchor)
       template)))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"relation.*undeclared" (exn-message error))
          (regexp-match? #rx"read Visual" (exn-message error))))
   (lambda ()
     (scene-state-resolved-ref
      (scene-current-state (scene-add base undeclared))
      'undeclared)))

  ;; Static validation diagnoses absent declarations and reports full paths for
  ;; deterministic explicit relation cycles before an animation is rendered.
  (define missing-declaration
    (relation-visual
     (circle #:id 'missing-declaration #:radius 1/8)
     #:depends-on (list (visual-dependency '(not-here child)))
     (lambda (_context template) template)))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"missing Visual path" (exn-message error))))
   (lambda ()
     (scene-validate-relations
      (scene-current-state (scene-add base missing-declaration)))))
  (define left
    (relation-visual
     (circle #:id 'left #:radius 1/8)
     #:depends-on (list (visual-dependency 'right))
     (lambda (context template)
       (relation-context-visual-ref context 'right)
       template)))
  (define right
    (relation-visual
     (circle #:id 'right #:radius 1/8)
     #:depends-on (list (visual-dependency 'left))
     (lambda (context template)
       (relation-context-visual-ref context 'left)
       template)))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"relation dependency cycle" (exn-message error))
          (regexp-match? #rx"left" (exn-message error))
          (regexp-match? #rx"right" (exn-message error))))
   (lambda ()
     (scene-validate-relations
      (scene-current-state (scene-add (make-scene) left right)))))

  ;; Fixed relations retain stable child paths; root-only relations deliberately
  ;; do not leak a resolver-produced group's transient children as targets.
  (define measurement-template
    (group
     (list (line (vec2 -1 0) (vec2 1 0) #:id 'brace #:stroke "gold")
           (plain-text "length" #:id 'label #:center (vec2 0 -1)
                       #:font-size 1/5))
     #:id 'measurement))
  (define fixed-measurement
    (relation-visual
     measurement-template
     #:structure 'fixed
     (lambda (_context template)
       (visual-with-position template (vec2 1 0)))))
  (define fixed-state
    (scene-current-state (scene-add (make-scene) fixed-measurement)))
  (check-equal?
   (visual-id (scene-state-resolved-ref fixed-state '(measurement label)))
   'label)
  (define root-only-measurement
    (relation-visual
     measurement-template
     (lambda (_context template) template)))
  (define root-only-state
    (scene-current-state (scene-add (make-scene) root-only-measurement)))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"root-only relation" (exn-message error))))
   (lambda ()
     (scene-state-resolved-ref root-only-state '(measurement label))))
  (define invalid-fixed
    (relation-visual
     measurement-template
     #:structure 'fixed
     (lambda (_context _template)
       (group
        (list (line (vec2 -1 0) (vec2 1 0) #:id 'different))
        #:id 'measurement))))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"fixed relation result" (exn-message error))))
   (lambda ()
     (scene-state-resolved-ref
      (scene-current-state (scene-add (make-scene) invalid-fixed))
      'measurement)))

  ;; All ordinary envelope controls apply after resolution. The local resolver
  ;; remains pure and unaware of the concurrent move/rotate/scale/fade.
  (define enveloped
    (relation-visual
     (circle #:id 'enveloped #:radius 1/4 #:fill "tomato")
     (lambda (_context template) template)))
  (define envelope-scene
    (scene-play
     (scene-add (make-scene) enveloped)
     (move-to 'enveloped (vec2 2 3))
     (rotate-to 'enveloped 1/4)
     (scale-to 'enveloped 2)
     (fill-color-to 'enveloped "gold")
     (stroke-color-to 'enveloped "purple")
     (stroke-width-to 'enveloped 5)
     (fade-to 'enveloped 1/2)
     #:duration 1))
  (define envelope-end
    (scene-state-resolved-ref (scene-current-state envelope-scene) 'enveloped))
  (check-equal? (visual-position envelope-end) (vec2 2 3))
  (check-equal? (visual-rotation envelope-end) 1/4)
  (check-equal? (visual-scale envelope-end) (vec2 2 2))
  (check-equal? (visual-opacity envelope-end) 1/2)
  (check-equal? (visual-fill-color envelope-end) "gold")
  (check-equal? (visual-stroke-color envelope-end) "purple")
  (check-equal? (visual-stroke-width envelope-end) 5)

  ;; Create/uncreate do not capture the relation's compilation-time line.
  ;; Instead each sampled frame resolves the current endpoint value and reveals
  ;; the appropriate prefix of that current path.  The completed create keeps
  ;; the relation definition, so later samples continue to follow its input.
  (define dynamic-segment
    (relation-visual
     (line origin (vec2 1 0) #:id 'dynamic-segment #:stroke "gold")
     #:depends-on (list (value-dependency 'segment-end))
     (lambda (context _template)
       (line origin
             (relation-context-value-ref context 'segment-end)
             #:id 'dynamic-segment #:stroke "gold"))))
  (define create-segment-scene
    (scene-play
     (scene-set-value (make-scene) 'segment-end (vec2 0 0))
     (value-to 'segment-end (vec2 4 0))
     (create dynamic-segment)
     #:duration 2
     #:easing linear))
  (define create-middle
    (scene-state-resolved-ref
     (scene-sample create-segment-scene 1)
     'dynamic-segment))
  ;; At t=1 the endpoint has moved to (2,0), and the half reveal therefore
  ;; has length one—not the zero-length path present at compilation time.
  (check-equal? (path-geometry-length (path-visual-path create-middle)) 1)
  (check-true
   (relation-visual?
    (scene-state-ref (scene-current-state create-segment-scene)
                     'dynamic-segment)))
  (check-equal?
   (path-geometry-length
    (path-visual-path
     (scene-state-resolved-ref
      (scene-current-state create-segment-scene)
      'dynamic-segment)))
   4)

  (define uncreate-segment-scene
    (scene-play
     (scene-set-value
      (scene-add (make-scene) dynamic-segment)
      'segment-end (vec2 4 0))
     (value-to 'segment-end (vec2 6 0))
     (uncreate 'dynamic-segment)
     #:duration 2
     #:easing linear))
  (define uncreate-middle
    (scene-state-resolved-ref
     (scene-sample uncreate-segment-scene 1)
     'dynamic-segment))
  ;; At t=1 the complete path is length five and the reverse reveal retains
  ;; half of that current path.
  (check-equal? (path-geometry-length (path-visual-path uncreate-middle)) 5/2)
  (check-false
   (scene-state-has? (scene-current-state uncreate-segment-scene)
                     'dynamic-segment)))
