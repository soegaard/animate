#lang racket/base

;;;
;;; SCENE-J Model Tests
;;;

;; Tests semantic opacity, the optional opacity-Visual protocol, fade requests,
;; structural introduction and removal, component conflicts, and exact sampling.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(module+ test
  ; exception-message-matches? : regexp? -> (-> any/c boolean?)
  ;;   Creates an exception predicate that checks a contract-error message.
  (define (exception-message-matches? pattern)
    (lambda (exception)
      (and (exn:fail:contract? exception)
           (regexp-match? pattern (exn-message exception)))))

  ; state-visual : scene? real? symbol? -> visual?
  ;;   Returns one Visual from a sampled scene state.
  (define (state-visual scene time id)
    (scene-state-ref (scene-sample scene time) id))

  ; state-opacity : scene? real? symbol? -> opacity?
  ;;   Returns one Visual's opacity at a sampled scene time.
  (define (state-opacity scene time id)
    (visual-opacity (state-visual scene time id)))

  ;; Opacity is a finite real in the closed unit interval.

  (check-true (opacity? 0))
  (check-true (opacity? 1/2))
  (check-true (opacity? 1.0))
  (check-false (opacity? -1/10))
  (check-false (opacity? 11/10))
  (check-false (opacity? +inf.0))
  (check-false (opacity? +nan.0))
  (check-false (opacity? 'opaque))

  ;; Every built-in Visual implements semantic opacity. Immutable replacement
  ;; preserves identity, geometry, affine data, and style.

  ; token : circle-visual?
  ;;   Gives a partially transparent circle.
  (define token
    (circle #:id 'token
            #:center (vec2 -3 1)
            #:rotation 1/4
            #:scale (vec2 2 1/2)
            #:opacity 3/4
            #:radius 2
            #:fill "gold"
            #:stroke "navy"
            #:stroke-width 5))

  ; dim-token : circle-visual?
  ;;   Gives token with only its opacity replaced.
  (define dim-token
    (visual-with-opacity token 1/4))

  (check-true (opacity-visual? token))
  (check-equal? (visual-opacity token) 3/4)
  (check-equal? (visual-opacity dim-token) 1/4)
  (check-equal? (visual-id dim-token) 'token)
  (check-equal? (visual-position dim-token) (vec2 -3 1))
  (check-equal? (visual-rotation dim-token) 1/4)
  (check-equal? (visual-scale dim-token) (vec2 2 1/2))
  (check-equal? (circle-visual-radius dim-token) 2)
  (check-equal? (circle-visual-fill dim-token) "gold")
  (check-equal? (circle-visual-stroke dim-token) "navy")
  (check-equal? (circle-visual-stroke-width dim-token) 5)
  (check-equal? (visual-opacity token) 3/4)

  ; moved-token : circle-visual?
  ;;   Gives token with only its reference position replaced.
  (define moved-token
    (visual-with-position token (vec2 4 -2)))

  ; rotated-token : circle-visual?
  ;;   Gives token with only its rotation replaced.
  (define rotated-token
    (visual-with-rotation token 3/2))

  (check-equal? (visual-opacity moved-token) 3/4)
  (check-equal? (visual-opacity rotated-token) 3/4)

  ; panel : rectangle-visual?
  ;;   Gives a rectangle with default full opacity.
  (define panel
    (rectangle #:id 'panel))

  ; path : path-visual?
  ;;   Gives a partially transparent semantic path.
  (define path
    (line (vec2 -2 0)
          (vec2 2 0)
          #:id 'path
          #:opacity 2/3
          #:stroke "crimson"))

  ; polygon-visual : path-visual?
  ;;   Gives a polygon with explicit opacity.
  (define polygon-visual
    (polygon (list (vec2 -1 -1)
                   (vec2 1 -1)
                   (vec2 0 1))
             #:id 'polygon
             #:opacity 1/3))

  (check-true (opacity-visual? panel))
  (check-true (opacity-visual? path))
  (check-true (opacity-visual? polygon-visual))
  (check-equal? (visual-opacity panel) 1)
  (check-equal? (visual-opacity path) 2/3)
  (check-equal? (visual-opacity polygon-visual) 1/3)
  (check-equal?
   (visual-opacity
    (path-visual-with-path path empty-path-geometry))
   2/3)

  (check-exn exn:fail:contract?
             (lambda ()
               (circle #:id 'bad-circle #:opacity -1/10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (rectangle #:id 'bad-rectangle #:opacity 11/10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (make-path-visual empty-path-geometry
                                 #:id 'bad-path
                                 #:opacity +inf.0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (visual-with-opacity token +nan.0)))

  ;; A third-party Visual can implement opacity without implementing affine
  ;; transforms.

  (struct fading-marker (id position opacity)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (fading-marker-id marker))
     (define (visual-position marker)
       (fading-marker-position marker))
     (define (visual-with-position marker position)
       (struct-copy fading-marker marker [position position]))]
    #:methods gen:opacity-visual
    [(define (visual-opacity marker)
       (fading-marker-opacity marker))
     (define (visual-with-opacity marker opacity)
       (struct-copy fading-marker marker [opacity opacity]))])

  ;; fading-marker represents a position-only Visual with global opacity.
  ;;  - id        symbol?   stable Visual identity.
  ;;  - position  vec2?     world-space reference position.
  ;;  - opacity   opacity?  global rendering opacity.

  ; marker : fading-marker?
  ;;   Gives a third-party opacity Visual.
  (define marker
    (fading-marker 'marker origin 1/2))

  (check-true (visual? marker))
  (check-true (opacity-visual? marker))
  (check-false (affine-visual? marker))
  (check-equal? (visual-opacity marker) 1/2)
  (check-equal? (visual-opacity (visual-with-opacity marker 1/4))
                1/4)

  ;; Public fade constructors validate targets and opacity values.

  (check-true (fade-to-request? (fade-to token 1/2)))
  (check-true (fade-to-request? (fade-to 'token 1/2)))
  (check-true (fade-in-request? (fade-in token)))
  (check-true (fade-out-request? (fade-out token)))
  (check-true (fade-out-request? (fade-out 'token)))
  (check-exn exn:fail:contract?
             (lambda ()
               (fade-to token -1/10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (fade-to panel 11/10)))
  (check-exn exn:fail:contract?
             (lambda ()
               (fade-in 'token)))
  (check-exn exn:fail:contract?
             (lambda ()
               (fade-out 42)))

  ;; fade-to changes only opacity and follows ordinary easing semantics.

  ; fade-to-scene : scene?
  ;;   Fades token from three quarters to one quarter over one second.
  (define fade-to-scene
    (scene-play (scene-add (make-scene) token)
                (fade-to token 1/4)
                #:duration 1))

  (check-equal? (state-opacity fade-to-scene 0 'token) 3/4)
  (check-equal? (state-opacity fade-to-scene 1/2 'token) 1/2)
  (check-equal? (state-opacity fade-to-scene 1 'token) 1/4)
  (check-equal? (visual-position (state-visual fade-to-scene 1/2 'token))
                (vec2 -3 1))
  (check-equal? (visual-scale (state-visual fade-to-scene 1/2 'token))
                (vec2 2 1/2))

  ; frozen-fade-to-scene : scene?
  ;;   Gives a fade-to clip whose easing always returns zero.
  (define frozen-fade-to-scene
    (scene-play (scene-add (make-scene) token)
                (fade-to token 0)
                #:duration 1
                #:easing (lambda (_progress) 0)))

  (check-equal? (state-opacity frozen-fade-to-scene 1/2 'token) 3/4)
  (check-equal? (state-opacity frozen-fade-to-scene 1 'token) 3/4)

  ;; Later opacity clips compile from the current endpoint.

  ; two-fade-scene : scene?
  ;;   Fades token to one half and then to one quarter.
  (define two-fade-scene
    (scene-play
     (scene-play (scene-add (make-scene) token)
                 (fade-to token 1/2)
                 #:duration 1)
     (fade-to 'token 1/4)
     #:duration 1))

  (check-equal? (state-opacity two-fade-scene 1 'token) 1/2)
  (check-equal? (state-opacity two-fade-scene 3/2 'token) 3/8)
  (check-equal? (state-opacity two-fade-scene 2 'token) 1/4)

  ;; fade-in introduces an absent Visual at opacity zero. The structural
  ;; endpoint installs the complete supplied opacity even with unusual easing.

  ; entering-token : circle-visual?
  ;;   Gives an absent circle whose intended final opacity is three quarters.
  (define entering-token
    (circle #:id 'entering-token
            #:center (vec2 -4 0)
            #:rotation 0
            #:scale 1
            #:opacity 3/4
            #:fill "dodgerblue"))

  ; fade-in-scene : scene?
  ;;   Introduces, moves, rotates, and scales one circle simultaneously.
  (define fade-in-scene
    (scene-play (make-scene)
                (move-to entering-token (vec2 4 0))
                (scale-to entering-token 2)
                (fade-in entering-token)
                (rotate-to entering-token 1)
                #:duration 2))

  ; fade-in-start : circle-visual?
  ;;   Gives the invisible structural placeholder at clip start.
  (define fade-in-start
    (state-visual fade-in-scene 0 'entering-token))

  ; fade-in-middle : circle-visual?
  ;;   Gives the Visual halfway through all four components.
  (define fade-in-middle
    (state-visual fade-in-scene 1 'entering-token))

  ; fade-in-end : circle-visual?
  ;;   Gives the complete introduced Visual at the structural endpoint.
  (define fade-in-end
    (state-visual fade-in-scene 2 'entering-token))

  (check-equal? (visual-opacity fade-in-start) 0)
  (check-equal? (visual-position fade-in-start) (vec2 -4 0))
  (check-equal? (visual-opacity fade-in-middle) 3/8)
  (check-equal? (visual-position fade-in-middle) origin)
  (check-equal? (visual-rotation fade-in-middle) 1/2)
  (check-equal? (visual-scale fade-in-middle) (vec2 3/2 3/2))
  (check-equal? (visual-opacity fade-in-end) 3/4)
  (check-equal? (visual-position fade-in-end) (vec2 4 0))
  (check-equal? (visual-rotation fade-in-end) 1)
  (check-equal? (visual-scale fade-in-end) (vec2 2 2))

  ; frozen-fade-in-scene : scene?
  ;;   Gives a fade-in whose interior easing stays at zero.
  (define frozen-fade-in-scene
    (scene-play (make-scene)
                (fade-in entering-token)
                #:duration 1
                #:easing (lambda (_progress) 0)))

  (check-equal? (state-opacity frozen-fade-in-scene 1/2 'entering-token)
                0)
  (check-equal? (state-opacity frozen-fade-in-scene 1 'entering-token)
                3/4)

  ;; Several fade-ins preserve request order in front of existing Visuals.

  ; background : rectangle-visual?
  ;;   Gives a pre-existing backmost Visual.
  (define background
    (rectangle #:id 'background))

  ; first-entering : circle-visual?
  ;;   Gives the first introduced Visual.
  (define first-entering
    (circle #:id 'first-entering))

  ; second-entering : rectangle-visual?
  ;;   Gives the second introduced Visual.
  (define second-entering
    (rectangle #:id 'second-entering))

  ; ordered-fade-in-scene : scene?
  ;;   Introduces two Visuals in request order.
  (define ordered-fade-in-scene
    (scene-play (scene-add (make-scene) background)
                (fade-in first-entering)
                (fade-in second-entering)
                #:duration 1))

  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-sample ordered-fade-in-scene 0)))
   '(background first-entering second-entering))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-sample ordered-fade-in-scene 1)))
   '(background first-entering second-entering))

  (check-exn
   (exception-message-matches? #rx"identity absent from the scene")
   (lambda ()
     (scene-play (scene-add (make-scene) token)
                 (fade-in token))))

  ;; fade-out reaches zero in sampled interiors and removes the Visual at the
  ;; structural endpoint. Removal is independent of unusual easing.

  ; fade-out-scene : scene?
  ;;   Moves and fades token out over two seconds.
  (define fade-out-scene
    (scene-play (scene-add (make-scene) token panel)
                (fade-out token)
                (move-to token (vec2 5 1))
                #:duration 2))

  (check-equal? (state-opacity fade-out-scene 0 'token) 3/4)
  (check-equal? (state-opacity fade-out-scene 1 'token) 3/8)
  (check-equal? (visual-position (state-visual fade-out-scene 1 'token))
                (vec2 1 1))
  (check-false (scene-state-has? (scene-sample fade-out-scene 2)
                                 'token))
  (check-true (scene-state-has? (scene-sample fade-out-scene 2)
                                'panel))

  ; frozen-fade-out-scene : scene?
  ;;   Gives a fade-out whose easing always returns zero.
  (define frozen-fade-out-scene
    (scene-play (scene-add (make-scene) token)
                (fade-out token)
                #:duration 1
                #:easing (lambda (_progress) 0)))

  (check-equal? (state-opacity frozen-fade-out-scene 1/2 'token) 3/4)
  (check-false (scene-state-has? (scene-sample frozen-fade-out-scene 1)
                                 'token))

  ;; Opacity is independent of path geometry. A path can morph while it fades
  ;; in or out. Structural introductions and removals nevertheless conflict
  ;; when two requests try to add or remove the same identity.

  ; source-path : path-geometry?
  ;;   Gives one open straight path.
  (define source-path
    (polyline-path
     (list (vec2 -2 0)
           (vec2 2 0))))

  ; destination-path : path-geometry?
  ;;   Gives one compatible open bent path.
  (define destination-path
    (polyline-path
     (list (vec2 -2 0)
           (vec2 2 2))))

  ; entering-path : path-visual?
  ;;   Gives an absent path Visual for simultaneous fade and morph.
  (define entering-path
    (make-path-visual source-path
                      #:id 'entering-path
                      #:opacity 4/5
                      #:stroke "purple"))

  ; fading-morph-scene : scene?
  ;;   Fades an absent path in while morphing its geometry.
  (define fading-morph-scene
    (scene-play (make-scene)
                (morph-to entering-path destination-path)
                (fade-in entering-path)
                #:duration 1))

  (check-equal? (state-opacity fading-morph-scene 1/2 'entering-path)
                2/5)
  (check-equal?
   (path-visual-path (state-visual fading-morph-scene 1 'entering-path))
   destination-path)

  ; fading-out-morph-scene : scene?
  ;;   Morphs a present path while fading and removing it.
  (define fading-out-morph-scene
    (scene-play (scene-add (make-scene) entering-path)
                (morph-to entering-path destination-path)
                (fade-out entering-path)
                #:duration 1))

  (check-true (scene-state-has? (scene-sample fading-out-morph-scene 1/2)
                                'entering-path))
  (check-false (scene-state-has? (scene-sample fading-out-morph-scene 1)
                                 'entering-path))

  (check-exn
   (exception-message-matches? #rx"opacity")
   (lambda ()
     (scene-play (scene-add (make-scene) token)
                 (fade-to token 1/2)
                 (fade-out token))))
  (check-exn
   (exception-message-matches? #rx"presence")
   (lambda ()
     (scene-play (make-scene)
                 (fade-in entering-path)
                 (create entering-path))))
  (check-exn
   (exception-message-matches? #rx"presence")
   (lambda ()
     (scene-play (scene-add (make-scene) entering-path)
                 (fade-out entering-path)
                 (uncreate entering-path))))

  ;; Missing targets and Visuals without the opacity protocol are rejected at
  ;; scene compilation.

  (struct plain-marker (id position)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (plain-marker-id marker))
     (define (visual-position marker)
       (plain-marker-position marker))
     (define (visual-with-position marker position)
       (struct-copy plain-marker marker [position position]))])

  ;; plain-marker represents a Visual without semantic opacity.
  ;;  - id        symbol?  stable Visual identity.
  ;;  - position  vec2?    world-space reference position.

  ; plain : plain-marker?
  ;;   Gives a Visual that cannot be faded.
  (define plain
    (plain-marker 'plain origin))

  (check-false (opacity-visual? plain))
  (check-exn exn:fail:contract?
             (lambda ()
               (fade-to plain 1/2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (fade-in plain)))
  (check-exn exn:fail:contract?
             (lambda ()
               (fade-out plain)))
  (check-exn
   (exception-message-matches? #rx"opacity Visual")
   (lambda ()
     (scene-play (scene-add (make-scene) plain)
                 (fade-to 'plain 1/2))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play (make-scene)
                           (fade-out 'missing))))

  ;; The library validates custom opacity protocol results at the animation
  ;; boundary.

  (struct invalid-opacity-marker (id position)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (invalid-opacity-marker-id marker))
     (define (visual-position marker)
       (invalid-opacity-marker-position marker))
     (define (visual-with-position marker position)
       (struct-copy invalid-opacity-marker marker [position position]))]
    #:methods gen:opacity-visual
    [(define (visual-opacity _marker)
       2)
     (define (visual-with-opacity marker _opacity)
       marker)])

  ;; invalid-opacity-marker intentionally violates the opacity protocol.
  ;;  - id        symbol?  stable Visual identity.
  ;;  - position  vec2?    world-space reference position.

  ; invalid-opacity : invalid-opacity-marker?
  ;;   Gives a deliberately invalid custom opacity Visual.
  (define invalid-opacity
    (invalid-opacity-marker 'invalid-opacity origin))

  (check-exn
   (exception-message-matches? #rx"must return a finite real")
   (lambda ()
     (fade-in invalid-opacity))))
