#lang racket/base

;;;
;;; SCENE-K Model Tests
;;;

;; Tests semantic groups, significant child order, identity invariants, nested
;; uniform transforms, opacity inheritance data, and group timeline animation.


;;;
;;; Imports
;;;

(require rackunit
         (only-in racket/math pi)
         (only-in "../private/group-visual.rkt"
                  group-visual-resolved-children)
         "../main.rkt")


(module+ test
  ; check-real-close : real? real? -> void?
  ;;   Checks two real values with a small absolute tolerance.
  (define (check-real-close actual expected)
    (check-= actual expected 1e-10))

  ; check-vec2-close : vec2? vec2? -> void?
  ;;   Checks two vectors component by component with a small tolerance.
  (define (check-vec2-close actual expected)
    (check-real-close (vec2-x actual) (vec2-x expected))
    (check-real-close (vec2-y actual) (vec2-y expected)))

  ; sampled-visual : scene? real? symbol? -> visual?
  ;;   Returns one top-level Visual from a sampled scene.
  (define (sampled-visual scene time id)
    (scene-state-ref (scene-sample scene time) id))

  ;; A group stores affine children in significant back-to-front order. Child
  ;; coordinates are local to the group.

  ; back-circle : circle-visual?
  ;;   Gives the back child of the primary test group.
  (define back-circle
    (circle #:id 'back-circle
            #:center (vec2 -2 0)
            #:scale 1/2
            #:opacity 3/4
            #:radius 1
            #:fill "gold"))

  ; front-panel : rectangle-visual?
  ;;   Gives the front child of the primary test group.
  (define front-panel
    (rectangle #:id 'front-panel
               #:center (vec2 2 0)
               #:rotation 1/4
               #:scale (vec2 2 1/2)
               #:width 2
               #:height 1
               #:fill "cornflowerblue"))

  ; pair : group-visual?
  ;;   Gives a translated, uniformly scaled semantic group.
  (define pair
    (group (list back-circle front-panel)
           #:id 'pair
           #:center (vec2 5 -1)
           #:scale 2
           #:opacity 2/3))

  (check-true (visual? pair))
  (check-true (affine-visual? pair))
  (check-true (opacity-visual? pair))
  (check-true (group-visual? pair))
  (check-equal? (visual-id pair) 'pair)
  (check-equal? (visual-position pair) (vec2 5 -1))
  (check-equal? (visual-rotation pair) 0)
  (check-equal? (visual-scale pair) (vec2 2 2))
  (check-equal? (visual-opacity pair) 2/3)
  (check-equal? (group-visual-children pair)
                (list back-circle front-panel))

  ;; Immutable group updates preserve the other semantic fields.

  ; moved-pair : group-visual?
  ;;   Gives pair with only its reference position replaced.
  (define moved-pair
    (visual-with-position pair (vec2 -4 3)))

  ; rotated-pair : group-visual?
  ;;   Gives pair with only its rotation replaced.
  (define rotated-pair
    (visual-with-rotation pair 3/4))

  ; scaled-pair : group-visual?
  ;;   Gives pair with only its uniform scale replaced.
  (define scaled-pair
    (visual-with-scale pair 3))

  ; faded-pair : group-visual?
  ;;   Gives pair with only its opacity replaced.
  (define faded-pair
    (visual-with-opacity pair 1/4))

  (check-equal? (group-visual-children moved-pair)
                (group-visual-children pair))
  (check-equal? (group-visual-children rotated-pair)
                (group-visual-children pair))
  (check-equal? (group-visual-children scaled-pair)
                (group-visual-children pair))
  (check-equal? (group-visual-children faded-pair)
                (group-visual-children pair))
  (check-equal? (visual-position moved-pair) (vec2 -4 3))
  (check-equal? (visual-rotation rotated-pair) 3/4)
  (check-equal? (visual-scale scaled-pair) (vec2 3 3))
  (check-equal? (visual-opacity faded-pair) 1/4)
  (check-equal? (visual-id moved-pair) 'pair)

  ; replacement-child : circle-visual?
  ;;   Gives one replacement child for immutable child-list testing.
  (define replacement-child
    (circle #:id 'replacement #:center origin))

  ; replaced-pair : group-visual?
  ;;   Gives pair with a new one-child drawing order.
  (define replaced-pair
    (group-visual-with-children pair (list replacement-child)))

  (check-equal? (group-visual-children replaced-pair)
                (list replacement-child))
  (check-equal? (visual-id replaced-pair) 'pair)
  (check-equal? (visual-position replaced-pair) (vec2 5 -1))
  (check-equal? (visual-scale replaced-pair) (vec2 2 2))
  (check-equal? (visual-opacity replaced-pair) 2/3)
  (check-equal? (group-visual-children pair)
                (list back-circle front-panel))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (group-visual-with-children
      pair
      (list back-circle
            (circle #:id 'back-circle)))))

  ;; Resolving children inherits scale and rotation but not the group's
  ;; containing-system translation. Child opacity and style remain unchanged.

  ; resolved-children : (listof affine-visual?)
  ;;   Gives pair's children after inheriting its local transform.
  (define resolved-children
    (group-visual-resolved-children pair))

  ; resolved-circle : circle-visual?
  ;;   Gives the resolved back child.
  (define resolved-circle
    (car resolved-children))

  ; resolved-panel : rectangle-visual?
  ;;   Gives the resolved front child.
  (define resolved-panel
    (cadr resolved-children))

  (check-equal? (visual-position resolved-circle) (vec2 -4 0))
  (check-equal? (visual-scale resolved-circle) (vec2 1 1))
  (check-equal? (visual-rotation resolved-circle) 0)
  (check-equal? (visual-opacity resolved-circle) 3/4)
  (check-equal? (visual-position resolved-panel) (vec2 4 0))
  (check-equal? (visual-scale resolved-panel) (vec2 4 1))
  (check-equal? (visual-rotation resolved-panel) 1/4)
  (check-equal? (visual-position pair) (vec2 5 -1))

  ; quarter-turn-group : group-visual?
  ;;   Gives one group used to verify rotation of child positions.
  (define quarter-turn-group
    (group (list (circle #:id 'turn-child
                         #:center (vec2 2 0)))
           #:id 'turn-group
           #:rotation (/ pi 2)
           #:scale 3))

  ; turned-child : circle-visual?
  ;;   Gives the child after inherited quarter-turn rotation and scale.
  (define turned-child
    (car (group-visual-resolved-children quarter-turn-group)))

  (check-vec2-close (visual-position turned-child) (vec2 0 6))
  (check-real-close (visual-rotation turned-child) (/ pi 2))
  (check-equal? (visual-scale turned-child) (vec2 3 3))

  ;; Nested groups retain hierarchy and compose uniform transforms exactly.

  ; nested-leaf : circle-visual?
  ;;   Gives the deepest child in a nested group.
  (define nested-leaf
    (circle #:id 'nested-leaf
            #:center (vec2 1 0)
            #:scale (vec2 2 1)))

  ; inner-group : group-visual?
  ;;   Gives a local group translated one unit and scaled by two.
  (define inner-group
    (group (list nested-leaf)
           #:id 'inner-group
           #:center (vec2 1 0)
           #:scale 2))

  ; outer-group : group-visual?
  ;;   Gives a parent group scaled by three.
  (define outer-group
    (group (list inner-group)
           #:id 'outer-group
           #:scale 3))

  ; resolved-inner : group-visual?
  ;;   Gives inner-group after inheriting outer-group's transform.
  (define resolved-inner
    (car (group-visual-resolved-children outer-group)))

  ; resolved-leaf : circle-visual?
  ;;   Gives nested-leaf after inheriting the resolved inner transform.
  (define resolved-leaf
    (car (group-visual-resolved-children resolved-inner)))

  (check-equal? (visual-position resolved-inner) (vec2 3 0))
  (check-equal? (visual-scale resolved-inner) (vec2 6 6))
  (check-equal? (visual-position resolved-leaf) (vec2 6 0))
  (check-equal? (visual-scale resolved-leaf) (vec2 12 6))

  ;; Empty groups are valid semantic composites.

  ; empty-group : group-visual?
  ;;   Gives an empty group at the origin.
  (define empty-group
    (group '() #:id 'empty-group))

  (check-true (group-visual? empty-group))
  (check-equal? (group-visual-children empty-group) '())
  (check-equal? (group-visual-resolved-children empty-group) '())

  ;; Group trees require affine children and unique descendant identities.

  (struct position-marker (id position)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (position-marker-id marker))
     (define (visual-position marker)
       (position-marker-position marker))
     (define (visual-with-position marker position)
       (struct-copy position-marker marker [position position]))])

  ;; position-marker represents a non-affine custom Visual.
  ;;  - id        symbol?  stable Visual identity.
  ;;  - position  vec2?    reference position.

  (check-exn exn:fail:contract?
             (lambda ()
               (group (list (position-marker 'marker origin))
                      #:id 'invalid-group)))
  (check-exn exn:fail:contract?
             (lambda ()
               (group (list back-circle)
                      #:id 'back-circle)))
  (check-exn exn:fail:contract?
             (lambda ()
               (group (list back-circle
                            (circle #:id 'back-circle))
                      #:id 'duplicate-group)))
  (check-exn exn:fail:contract?
             (lambda ()
               (group (list inner-group
                            (circle #:id 'nested-leaf))
                      #:id 'duplicate-tree)))
  (check-exn exn:fail:contract?
             (lambda ()
               (group 42 #:id 'not-a-list)))
  (check-equal?
   (visual-scale
    (group '() #:id 'uniform-vector-scale #:scale (vec2 2 2)))
   (vec2 2 2))
  (check-exn exn:fail:contract?
             (lambda ()
               (group '() #:id 'bad-scale #:scale (vec2 2 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (visual-with-scale pair (vec2 2 1))))

  ;; A well-behaved third-party affine Visual can participate as a child.

  (struct affine-marker (id transform)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (affine-marker-id marker))
     (define (visual-position marker)
       (affine-transform-translation
        (affine-marker-transform marker)))
     (define (visual-with-position marker position)
       (struct-copy affine-marker marker
                    [transform
                     (affine-transform-with-translation
                      (affine-marker-transform marker)
                      position)]))]
    #:methods gen:affine-visual
    [(define (visual-transform marker)
       (affine-marker-transform marker))
     (define (visual-with-transform marker transform)
       (struct-copy affine-marker marker [transform transform]))])

  ;; affine-marker represents a custom affine child Visual.
  ;;  - id         symbol?             stable Visual identity.
  ;;  - transform  affine-transform?   complete local transform.

  ; custom-marker : affine-marker?
  ;;   Gives one custom affine child.
  (define custom-marker
    (affine-marker
     'custom-marker
     (make-affine-transform #:translation (vec2 1 -2)
                            #:rotation 1/3
                            #:scale (vec2 2 3))))

  ; custom-group : group-visual?
  ;;   Gives a group containing the custom affine child.
  (define custom-group
    (group (list custom-marker)
           #:id 'custom-group
           #:scale 2))

  ; resolved-custom-marker : affine-marker?
  ;;   Gives the custom child after inherited uniform scaling.
  (define resolved-custom-marker
    (car (group-visual-resolved-children custom-group)))

  (check-equal? (visual-position resolved-custom-marker) (vec2 2 -4))
  (check-equal? (visual-rotation resolved-custom-marker) 1/3)
  (check-equal? (visual-scale resolved-custom-marker) (vec2 4 6))

  ;; Group boundaries reject malformed custom affine implementations.

  (struct inconsistent-marker (id position transform)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (inconsistent-marker-id marker))
     (define (visual-position marker)
       (inconsistent-marker-position marker))
     (define (visual-with-position marker position)
       (struct-copy inconsistent-marker marker [position position]))]
    #:methods gen:affine-visual
    [(define (visual-transform marker)
       (inconsistent-marker-transform marker))
     (define (visual-with-transform marker transform)
       (struct-copy inconsistent-marker marker [transform transform]))])

  ;; inconsistent-marker can report a position different from its translation.

  (check-exn
   exn:fail:contract?
   (lambda ()
     (group
      (list
       (inconsistent-marker
        'inconsistent
        (vec2 9 9)
        identity-affine-transform))
      #:id 'inconsistent-group)))

  (struct refusing-marker (id transform)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (refusing-marker-id marker))
     (define (visual-position marker)
       (affine-transform-translation
        (refusing-marker-transform marker)))
     (define (visual-with-position marker position)
       (struct-copy refusing-marker marker
                    [transform
                     (affine-transform-with-translation
                      (refusing-marker-transform marker)
                      position)]))]
    #:methods gen:affine-visual
    [(define (visual-transform marker)
       (refusing-marker-transform marker))
     (define (visual-with-transform marker _transform)
       marker)])

  ;; refusing-marker ignores complete transform replacements.

  (define refusing-group
    (group (list (refusing-marker 'refusing identity-affine-transform))
           #:id 'refusing-group
           #:scale 2))

  (check-exn exn:fail:contract?
             (lambda ()
               (group-visual-resolved-children refusing-group)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (define refusing-top-level
       (refusing-marker 'refusing-top-level identity-affine-transform))
     (scene-play
      (scene-add (make-scene) refusing-top-level)
      (scale-to refusing-top-level 2)
      #:duration 1)))

  ;; Scene state treats the group as one top-level Visual. Nested children keep
  ;; semantic identities but are not direct scene-state targets in SCENE-K.

  ; group-state : scene-state?
  ;;   Gives a state containing only pair as one top-level Visual.
  (define group-state
    (scene-current-state
     (scene-add (make-scene) pair)))

  (check-equal? (scene-state-count group-state) 1)
  (check-true (scene-state-has? group-state 'pair))
  (check-false (scene-state-has? group-state 'back-circle))
  (check-equal? (scene-state-visuals-in-drawing-order group-state)
                (list pair))

  ;; Existing affine and opacity requests animate a group as one Visual.

  ; animated-group-scene : scene?
  ;;   Moves, rotates, uniformly scales, and fades pair simultaneously.
  (define animated-group-scene
    (scene-play (scene-add (make-scene) pair)
                (move-to pair (vec2 -3 2))
                (rotate-to pair 1)
                (scale-to pair 4)
                (fade-to pair 1/3)
                #:duration 2))

  ; midpoint-group : group-visual?
  ;;   Gives pair at the midpoint of all four component animations.
  (define midpoint-group
    (sampled-visual animated-group-scene 1 'pair))

  (check-equal? (visual-position midpoint-group) (vec2 1 1/2))
  (check-equal? (visual-rotation midpoint-group) 1/2)
  (check-equal? (visual-scale midpoint-group) (vec2 3 3))
  (check-equal? (visual-opacity midpoint-group) 1/2)
  (check-equal? (group-visual-children midpoint-group)
                (group-visual-children pair))

  ;; Non-uniform group scale requests fail during scene-play compilation rather
  ;; than later during arbitrary-time sampling.

  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (scene-add (make-scene) pair)
                 (scale-to pair (vec2 2 1))
                 #:duration 1)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play (scene-add (make-scene) pair)
                 (scale-by pair (vec2 2 1))
                 #:duration 1)))

  ;; Groups can enter and leave through the existing fade operations.

  ; entering-group : group-visual?
  ;;   Gives an absent group with a non-unit final opacity.
  (define entering-group
    (group (list (circle #:id 'entering-child))
           #:id 'entering-group
           #:center (vec2 -2 0)
           #:opacity 3/4))

  ; fade-group-in-scene : scene?
  ;;   Introduces and moves a complete group.
  (define fade-group-in-scene
    (scene-play (make-scene)
                (move-to entering-group (vec2 2 0))
                (fade-in entering-group)
                #:duration 1))

  (check-equal? (visual-opacity
                 (sampled-visual fade-group-in-scene 0 'entering-group))
                0)
  (check-equal? (visual-position
                 (sampled-visual fade-group-in-scene 1/2 'entering-group))
                origin)
  (check-equal? (visual-opacity
                 (sampled-visual fade-group-in-scene 1/2 'entering-group))
                3/8)
  (check-equal? (visual-opacity
                 (sampled-visual fade-group-in-scene 1 'entering-group))
                3/4)

  ; fade-group-out-scene : scene?
  ;;   Removes pair through opacity animation.
  (define fade-group-out-scene
    (scene-play (scene-add (make-scene) pair)
                (fade-out pair)
                #:duration 1))

  (check-true
   (scene-state-has? (scene-sample fade-group-out-scene 1/2) 'pair))
  (check-false
   (scene-state-has? (scene-sample fade-group-out-scene 1) 'pair)))
