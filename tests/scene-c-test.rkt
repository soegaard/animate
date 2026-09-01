#lang racket/base

;;;
;;; SCENE-C Model Tests
;;;

;; Tests semantic affine transforms and transform-component animation without
;; loading the Pict, filesystem, or process adapters.


;;;
;;; Imports
;;;

(require rackunit
         (only-in racket/math pi)
         "../private/affine-transform.rkt"
         "../private/animation.rkt"
         "../private/geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")


(module+ test
  ;; Scale values are explicit, positive, and normalized to two components.
  (check-true (scale-factor? 2))
  (check-true (scale-factor? (vec2 2 1/2)))
  (check-false (scale-factor? 0))
  (check-false (scale-factor? -1))
  (check-false (scale-factor? (vec2 1 0)))
  (check-equal? (scale-factor->vec2 3)
                (vec2 3 3))

  ;; Affine transforms apply scale, rotation, and translation in fixed order.

  ; exact-transform : affine-transform?
  ;;   Gives an exact transform with no rotation.
  (define exact-transform
    (make-affine-transform #:translation (vec2 1 2)
                           #:scale (vec2 2 3)))
  (check-equal? (affine-transform-apply-vector exact-transform
                                                (vec2 4 5))
                (vec2 8 15))
  (check-equal? (affine-transform-apply-point exact-transform
                                               (vec2 4 5))
                (vec2 9 17))

  ; quarter-turn : affine-transform?
  ;;   Gives a positive mathematical quarter-turn.
  (define quarter-turn
    (make-affine-transform #:rotation (/ pi 2)))

  ; quarter-turn-result : vec2?
  ;;   Gives the rotated unit x vector.
  (define quarter-turn-result
    (affine-transform-apply-vector quarter-turn (vec2 1 0)))
  (check-= (vec2-x quarter-turn-result) 0 1e-10)
  (check-= (vec2-y quarter-turn-result) 1 1e-10)

  ;; Transform interpolation preserves exact component arithmetic where possible.

  ; transform-end : affine-transform?
  ;;   Gives the endpoint used by the interpolation test.
  (define transform-end
    (make-affine-transform #:translation (vec2 4 2)
                           #:rotation 2
                           #:scale (vec2 3 1/2)))

  ; transform-midpoint : affine-transform?
  ;;   Gives the exact componentwise midpoint of identity and transform-end.
  (define transform-midpoint
    (affine-transform-lerp identity-affine-transform
                           transform-end
                           1/2))
  (check-equal? (affine-transform-translation transform-midpoint)
                (vec2 2 1))
  (check-equal? (affine-transform-rotation transform-midpoint)
                1)
  (check-equal? (affine-transform-scale transform-midpoint)
                (vec2 2 3/4))
  (check-exn exn:fail:contract?
             (lambda ()
               (affine-transform-lerp identity-affine-transform
                                      transform-end
                                      3/2)))

  ;; Built-in Visuals expose immutable affine-transform operations.

  ; panel : rectangle-visual?
  ;;   Gives a statically transformed rectangle.
  (define panel
    (rectangle #:id 'panel
               #:center (vec2 -3 0)
               #:rotation 1/2
               #:scale (vec2 2 3)
               #:width 2
               #:height 1))
  (check-true (affine-visual? panel))
  (check-eq? (visual-id panel) 'panel)
  (check-equal? (visual-position panel) (vec2 -3 0))
  (check-equal? (visual-rotation panel) 1/2)
  (check-equal? (visual-scale panel) (vec2 2 3))

  ; moved-panel : rectangle-visual?
  ;;   Gives panel with only its translation replaced.
  (define moved-panel
    (visual-with-position panel (vec2 1 2)))
  (check-equal? (visual-position moved-panel) (vec2 1 2))
  (check-equal? (visual-rotation moved-panel) 1/2)
  (check-equal? (visual-scale moved-panel) (vec2 2 3))

  ; rotated-panel : rectangle-visual?
  ;;   Gives panel with only its rotation replaced.
  (define rotated-panel
    (visual-with-rotation panel 3/2))
  (check-equal? (visual-position rotated-panel) (vec2 -3 0))
  (check-equal? (visual-rotation rotated-panel) 3/2)
  (check-equal? (visual-scale rotated-panel) (vec2 2 3))

  ; scaled-panel : rectangle-visual?
  ;;   Gives panel with only its scale replaced.
  (define scaled-panel
    (visual-with-scale panel 1/2))
  (check-equal? (visual-position scaled-panel) (vec2 -3 0))
  (check-equal? (visual-rotation scaled-panel) 1/2)
  (check-equal? (visual-scale scaled-panel) (vec2 1/2 1/2))

  ;; Invalid affine data is rejected before scene compilation or rendering.
  (check-exn exn:fail:contract?
             (lambda ()
               (make-affine-transform #:rotation +inf.0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (make-affine-transform #:scale 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (circle #:id 'bad-scale #:scale (vec2 -1 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (rectangle #:id 'bad-rotation #:rotation +nan.0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (scale-to panel 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (rotate-by panel +inf.0)))

  ;; Disjoint transform components may animate concurrently on one Visual.

  ; animated-panel : rectangle-visual?
  ;;   Gives the untransformed rectangle used by timeline tests.
  (define animated-panel
    (rectangle #:id 'animated-panel
               #:center (vec2 -3 0)
               #:width 2
               #:height 1))

  ; transform-scene : scene?
  ;;   Moves, rotates, and scales animated-panel in one two-second clip.
  (define transform-scene
    (scene-play
     (scene-add (make-scene) animated-panel)
     (move-to animated-panel (vec2 3 0))
     (rotate-by animated-panel 2)
     (scale-to animated-panel (vec2 2 1/2))
     #:duration 2))

  ; transformed-panel-at : nonnegative-real? -> rectangle-visual?
  ;;   Returns animated-panel sampled at time.
  (define (transformed-panel-at time)
    (scene-state-ref (scene-sample transform-scene time)
                     'animated-panel))

  ; transform-mid-visual : rectangle-visual?
  ;;   Gives animated-panel halfway through the combined clip.
  (define transform-mid-visual
    (transformed-panel-at 1))
  (check-equal? (visual-position transform-mid-visual)
                origin)
  (check-equal? (visual-rotation transform-mid-visual)
                1)
  (check-equal? (visual-scale transform-mid-visual)
                (vec2 3/2 3/4))

  ; transform-end-visual : rectangle-visual?
  ;;   Gives animated-panel at the combined clip endpoint.
  (define transform-end-visual
    (transformed-panel-at 2))
  (check-eq? (visual-id transform-end-visual)
             'animated-panel)
  (check-equal? (visual-position transform-end-visual)
                (vec2 3 0))
  (check-equal? (visual-rotation transform-end-visual)
                2)
  (check-equal? (visual-scale transform-end-visual)
                (vec2 2 1/2))

  ;; Relative requests compile from the current state of each later clip.

  ; relative-scene : scene?
  ;;   Adds a second clip with absolute rotation and relative scale.
  (define relative-scene
    (scene-play transform-scene
                (rotate-to 'animated-panel -1)
                (scale-by 'animated-panel (vec2 1/2 2))
                #:duration 1))

  ; relative-mid-visual : rectangle-visual?
  ;;   Gives animated-panel halfway through the second clip.
  (define relative-mid-visual
    (scene-state-ref (scene-sample relative-scene 5/2)
                     'animated-panel))
  (check-equal? (visual-position relative-mid-visual)
                (vec2 3 0))
  (check-equal? (visual-rotation relative-mid-visual)
                1/2)
  (check-equal? (visual-scale relative-mid-visual)
                (vec2 3/2 3/4))

  ; relative-end-visual : rectangle-visual?
  ;;   Gives animated-panel at the second clip endpoint.
  (define relative-end-visual
    (scene-state-ref (scene-sample relative-scene 3)
                     'animated-panel))
  (check-equal? (visual-rotation relative-end-visual)
                -1)
  (check-equal? (visual-scale relative-end-visual)
                (vec2 1 1))

  ;; Duplicate requests for one component remain ambiguous and are rejected.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) animated-panel)
      (move-to animated-panel origin)
      (move-to 'animated-panel (vec2 1 0)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) animated-panel)
      (rotate-to animated-panel 1)
      (rotate-by animated-panel 1))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) animated-panel)
      (scale-to animated-panel 2)
      (scale-by animated-panel 1/2))))

  ;; Third-party Visuals can opt into the affine protocol independently.

  (struct affine-marker (id transform)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (affine-marker-id marker))
     (define (visual-position marker)
       (affine-transform-translation
        (affine-marker-transform marker)))
     (define (visual-with-position marker position)
       (unless (vec2? position)
         (raise-argument-error 'visual-with-position "vec2?" position))
       (struct-copy affine-marker marker
                    [transform
                     (affine-transform-with-translation
                      (affine-marker-transform marker)
                      position)]))]
    #:methods gen:affine-visual
    [(define (visual-transform marker)
       (affine-marker-transform marker))
     (define (visual-with-transform marker transform)
       (unless (affine-transform? transform)
         (raise-argument-error
          'visual-with-transform
          "affine-transform?"
          transform))
       (struct-copy affine-marker marker [transform transform]))])

  ;; affine-marker is a test-only Visual implementing both semantic protocols.
  ;;  - id         symbol?             stable Visual identity.
  ;;  - transform  affine-transform?   complete decomposed transform.

  ; marker : affine-marker?
  ;;   Gives the third-party affine Visual used by extension tests.
  (define marker
    (affine-marker 'marker identity-affine-transform))

  ; marker-scene : scene?
  ;;   Gives a combined transform animation for the third-party Visual.
  (define marker-scene
    (scene-play
     (scene-add (make-scene) marker)
     (move-to marker (vec2 2 1))
     (rotate-to marker 1)
     (scale-by marker (vec2 2 3))
     #:duration 1))

  ; transformed-marker : affine-marker?
  ;;   Gives marker at the combined animation endpoint.
  (define transformed-marker
    (scene-state-ref (scene-sample marker-scene 1) 'marker))
  (check-equal? (visual-position transformed-marker)
                (vec2 2 1))
  (check-equal? (visual-rotation transformed-marker)
                1)
  (check-equal? (visual-scale transformed-marker)
                (vec2 2 3))

  ;; Legacy third-party Visuals remain movable without implementing transforms.

  (struct legacy-visual (id position)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual)
       (legacy-visual-id visual))
     (define (visual-position visual)
       (legacy-visual-position visual))
     (define (visual-with-position visual position)
       (unless (vec2? position)
         (raise-argument-error 'visual-with-position "vec2?" position))
       (struct-copy legacy-visual visual [position position]))])

  ;; legacy-visual implements the SCENE-A position protocol only.
  ;;  - id        symbol?  stable Visual identity.
  ;;  - position  vec2?    reference position in world coordinates.

  ; legacy : legacy-visual?
  ;;   Gives the non-affine Visual used by compatibility tests.
  (define legacy
    (legacy-visual 'legacy origin))
  (check-false (affine-visual? legacy))

  ; legacy-move : scene?
  ;;   Gives a valid translation of a legacy Visual.
  (define legacy-move
    (scene-play
     (scene-add (make-scene) legacy)
     (move-to legacy (vec2 2 0))))
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample legacy-move 1)
                     'legacy))
   (vec2 2 0))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) legacy)
      (rotate-by legacy 1))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene) legacy)
      (scale-to legacy 2)))))
