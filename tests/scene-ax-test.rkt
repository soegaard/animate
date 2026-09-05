#lang racket/base
(require "../experimental.rkt")

;;;
;;; SCENE-AX Dependency-Driven Derived Geometry Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; A derived Visual may read an ordinary top-level Visual even when that
  ;; dependency appears later in drawing order.
  (define anchor
    (circle #:id 'anchor
            #:center (vec2 2 1)
            #:radius 1/2
            #:fill "black"))
  (define follower
    (derived-visual
     (rectangle #:id 'follower
                #:center origin
                #:width 1
                #:height 1
                #:fill "gold")
     (lambda (context template)
       (unless (and (derived-context-visual-has? context 'anchor)
                    (not (derived-context-visual-has? context 'missing)))
         (error 'follower-resolver "unexpected Visual dependency context"))
       (define anchor-visual
         (derived-context-visual-ref context 'anchor))
       (visual-with-position
        template
        (vec2+ (visual-position anchor-visual) (vec2 1 0))))))
  (define ordinary-dependency-scene
    (scene-add (make-scene) follower anchor))
  (define ordinary-state
    (scene-current-state ordinary-dependency-scene))
  (check-true (derived-visual? (scene-state-ref ordinary-state 'follower)))
  (check-equal?
   (visual-position (scene-state-resolved-ref ordinary-state 'follower))
   (vec2 3 1))
  (check-equal?
   (map visual-id
        (scene-state-resolved-visuals-in-drawing-order ordinary-state))
   '(follower anchor))

  ;; An ordinary animation request may drive a derived dependent directly. No
  ;; mirrored scalar tracker is required.
  (define moved-anchor-scene
    (scene-play ordinary-dependency-scene
                (move-to 'anchor (vec2 6 1))
                #:duration 2))
  (check-equal?
   (visual-position
    (scene-state-resolved-ref (scene-sample moved-anchor-scene 1) 'follower))
   (vec2 5 1))
  (check-equal?
   (visual-position
    (scene-state-resolved-ref (scene-sample moved-anchor-scene 2) 'follower))
   (vec2 7 1))

  ;; Derived dependencies resolve recursively and remain independent of drawing
  ;; order. The source is deliberately frontmost even though earlier definitions
  ;; depend on it.
  (define source
    (derived-visual
     (circle #:id 'source
             #:center origin
             #:radius 1/2
             #:fill "royalblue")
     (lambda (context template)
       (visual-with-position
        template
        (vec2 (derived-context-value-ref context 'x) 0)))))
  (define middle
    (derived-visual
     (circle #:id 'middle
             #:center origin
             #:radius 1/3
             #:fill "tomato")
     (lambda (context template)
       (define source-visual
         (derived-context-visual-ref context 'source))
       (visual-with-position
        template
        (vec2+ (visual-position source-visual) (vec2 0 2))))))
  (define tail
    (derived-visual
     (circle #:id 'tail
             #:center origin
             #:radius 1/4
             #:fill "green")
     (lambda (context template)
       (define middle-visual
         (derived-context-visual-ref context 'middle))
       (visual-with-position
        template
        (vec2+ (visual-position middle-visual) (vec2 1 0))))))
  (define chain-base
    (scene-add
     (scene-set-value (make-scene) 'x -2)
     tail
     middle
     source))
  (define chain-state
    (scene-current-state chain-base))
  (check-equal?
   (visual-position (scene-state-resolved-ref chain-state 'source))
   (vec2 -2 0))
  (check-equal?
   (visual-position (scene-state-resolved-ref chain-state 'middle))
   (vec2 -2 2))
  (check-equal?
   (visual-position (scene-state-resolved-ref chain-state 'tail))
   (vec2 -1 2))
  (define chain-resolved
    (scene-state-resolved-visuals-in-drawing-order chain-state))
  (check-equal? (map visual-id chain-resolved) '(tail middle source))
  (check-equal? (map visual-position chain-resolved)
                (list (vec2 -1 2) (vec2 -2 2) (vec2 -2 0)))

  ;; Animated scalars propagate through the whole dependency chain at arbitrary
  ;; scene times without replacing any stored derived definition.
  (define chain-animated
    (scene-play chain-base (value-to 'x 4) #:duration 3))
  (for ([sample (in-list
                 (list (list 0 -2)
                       (list 3/2 1)
                       (list 3 4)))])
    (define time (car sample))
    (define x (cadr sample))
    (define state (scene-sample chain-animated time))
    (check-true (derived-visual? (scene-state-ref state 'tail)))
    (check-equal?
     (visual-position (scene-state-resolved-ref state 'source))
     (vec2 x 0))
    (check-equal?
     (visual-position (scene-state-resolved-ref state 'middle))
     (vec2 x 2))
    (check-equal?
     (visual-position (scene-state-resolved-ref state 'tail))
     (vec2 (+ x 1) 2)))

  ;; A diamond graph may read the same derived dependency along more than one
  ;; path. The final node sees concrete resolved Visuals on both branches.
  (define left
    (derived-visual
     (circle #:id 'left #:radius 1/5)
     (lambda (context template)
       (visual-with-position
        template
        (vec2+ (visual-position
                (derived-context-visual-ref context 'source))
               (vec2 -1 1))))))
  (define right
    (derived-visual
     (circle #:id 'right #:radius 1/5)
     (lambda (context template)
       (visual-with-position
        template
        (vec2+ (visual-position
                (derived-context-visual-ref context 'source))
               (vec2 1 1))))))
  (define apex
    (derived-visual
     (circle #:id 'apex #:radius 1/4)
     (lambda (context template)
       (define left-position
         (visual-position (derived-context-visual-ref context 'left)))
       (define right-position
         (visual-position (derived-context-visual-ref context 'right)))
       (visual-with-position
        template
        (vec2 (/ (+ (vec2-x left-position) (vec2-x right-position)) 2)
              (+ 1 (/ (+ (vec2-y left-position) (vec2-y right-position)) 2)))))))
  (define diamond
    (scene-add
     (scene-set-value (make-scene) 'x 3)
     apex left right source))
  (check-equal?
   (visual-position
    (scene-state-resolved-ref (scene-current-state diamond) 'apex))
   (vec2 3 2))

  ;; Visual presence is top-level only. Scalar IDs and nested/nonexistent
  ;; identities are not reported as Visual dependencies.
  (define presence-probe
    (derived-visual
     (circle #:id 'presence #:radius 1/4)
     (lambda (context template)
       (unless (and (derived-context-value-has? context 'x)
                    (not (derived-context-visual-has? context 'x))
                    (derived-context-visual-has? context 'source)
                    (derived-context-visual-has? context 'cluster)
                    (not (derived-context-visual-has? context 'nested-child))
                    (not (derived-context-visual-has? context 'no-such-visual)))
         (error 'presence-probe "unexpected dependency presence result"))
       template)))
  (define cluster
    (group (list (circle #:id 'nested-child #:radius 1/5))
           #:id 'cluster))
  (define presence-scene
    (scene-add
     (scene-set-value (make-scene) 'x 0)
     presence-probe source cluster))
  (check-true
   (circle-visual?
    (scene-state-resolved-ref (scene-current-state presence-scene) 'presence)))

  ;; Missing Visual dependencies fail when resolution is requested.
  (define needs-missing
    (derived-visual
     (circle #:id 'needs-missing #:radius 1/4)
     (lambda (context template)
       (define dependency
         (derived-context-visual-ref context 'absent))
       (visual-with-position template (visual-position dependency)))))
  (define missing-scene
    (scene-add (make-scene) needs-missing))
  (check-exn
   (lambda (e)
     (and (exn:fail? e)
          (regexp-match? #rx"not present" (exn-message e))))
   (lambda ()
     (scene-state-resolved-ref (scene-current-state missing-scene)
                               'needs-missing)))

  ;; Self-dependencies and longer cycles are rejected deterministically instead
  ;; of recursing until the host stack overflows.
  (define self-cycle
    (derived-visual
     (circle #:id 'self-cycle #:radius 1/4)
     (lambda (context template)
       (define self
         (derived-context-visual-ref context 'self-cycle))
       (visual-with-position template (visual-position self)))))
  (define self-cycle-scene
    (scene-add (make-scene) self-cycle))
  (check-exn
   (lambda (e)
     (and (exn:fail? e)
          (regexp-match? #rx"dependency cycle" (exn-message e))))
   (lambda ()
     (scene-state-resolved-ref (scene-current-state self-cycle-scene)
                               'self-cycle)))

  (define cycle-a
    (derived-visual
     (circle #:id 'cycle-a #:radius 1/4)
     (lambda (context template)
       (visual-with-position
        template
        (visual-position (derived-context-visual-ref context 'cycle-b))))))
  (define cycle-b
    (derived-visual
     (circle #:id 'cycle-b #:radius 1/4)
     (lambda (context template)
       (visual-with-position
        template
        (visual-position (derived-context-visual-ref context 'cycle-a))))))
  (define cycle-scene
    (scene-add (make-scene) cycle-a cycle-b))
  (for ([resolve (in-list
                  (list
                   (lambda ()
                     (scene-state-resolved-ref
                      (scene-current-state cycle-scene)
                      'cycle-a))
                   (lambda ()
                     (scene-state-resolved-visuals-in-drawing-order
                      (scene-current-state cycle-scene)))))])
    (check-exn
     (lambda (e)
       (and (exn:fail? e)
            (regexp-match? #rx"dependency cycle" (exn-message e))))
     resolve))

  ;; Removing a dependency invalidates future resolutions rather than retaining
  ;; a stale concrete result from an earlier resolution traversal.
  (define previously-resolved
    (scene-state-resolved-ref (scene-current-state chain-base) 'tail))
  (check-equal? (visual-position previously-resolved) (vec2 -1 2))
  (define without-source
    (scene-remove chain-base 'source))
  (check-exn exn:fail?
             (lambda ()
               (scene-state-resolved-ref
                (scene-current-state without-source)
                'tail)))

  ;; Existing scene-aware consumers automatically see recursively resolved
  ;; dependencies. camera-follow tracks the tail's world motion.
  (define followed
    (scene-play
     chain-base
     (value-to 'x 2)
     (camera-follow 'tail)
     #:duration 2))
  (check-equal? (camera-center (scene-camera-at followed 0)) origin)
  (check-equal? (camera-center (scene-camera-at followed 1)) (vec2 2 0))
  (check-equal? (camera-center (scene-camera-at followed 2)) (vec2 4 0))

  ;; Camera fitting sees the recursively resolved endpoint geometry as well.
  (define fitted
    (scene-play
     chain-animated
     (camera-fit-scene chain-animated #:targets '(tail))
     #:duration 1))
  (check-equal? (camera-center (scene-current-camera fitted)) (vec2 5 2)))
