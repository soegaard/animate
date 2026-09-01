#lang racket/base

;;;
;;; SCENE-B Model Tests
;;;

;; Tests the rectangle Visual and mixed-type timeline behavior without loading
;; the Pict backend directly.


;;;
;;; Imports
;;;

(require rackunit
         "../main.rkt")


(module+ test
  ; panel : rectangle-visual?
  ;;   Gives the canonical rectangle Visual used by the model tests.
  (define panel
    (rectangle #:id 'panel
               #:center (vec2 -3 0)
               #:width 2
               #:height 1
               #:fill "goldenrod"
               #:stroke "saddlebrown"
               #:stroke-width 3))

  ; token : circle-visual?
  ;;   Gives the canonical circle Visual used by the mixed-type tests.
  (define token
    (circle #:id 'token
            #:center (vec2 3 0)
            #:radius 1/2
            #:fill "dodgerblue"))

  ;; Rectangle construction exposes semantic dimensions and shared position.
  (check-true (rectangle-visual? panel))
  (check-eq? (visual-id panel) 'panel)
  (check-equal? (visual-position panel) (vec2 -3 0))
  (check-equal? (rectangle-visual-width panel) 2)
  (check-equal? (rectangle-visual-height panel) 1)
  (check-equal? (rectangle-visual-fill panel) "goldenrod")
  (check-equal? (rectangle-visual-stroke panel) "saddlebrown")
  (check-equal? (rectangle-visual-stroke-width panel) 3)

  ;; Immutable repositioning preserves identity, geometry, and style.

  ; moved-panel : rectangle-visual?
  ;;   Gives panel with only its reference position replaced.
  (define moved-panel
    (visual-with-position panel (vec2 1 2)))
  (check-true (rectangle-visual? moved-panel))
  (check-eq? (visual-id moved-panel) 'panel)
  (check-equal? (visual-position moved-panel) (vec2 1 2))
  (check-equal? (rectangle-visual-width moved-panel) 2)
  (check-equal? (rectangle-visual-height moved-panel) 1)
  (check-equal? (rectangle-visual-fill moved-panel) "goldenrod")
  (check-equal? (rectangle-visual-stroke moved-panel) "saddlebrown")
  (check-equal? (rectangle-visual-stroke-width moved-panel) 3)
  (check-equal? (visual-position panel) (vec2 -3 0))

  ;; Rectangle dimensions and cosmetic stroke width are validated eagerly.
  (check-exn exn:fail:contract?
             (lambda ()
               (rectangle #:id 'bad-width #:width 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (rectangle #:id 'bad-height #:height -1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (rectangle #:id 'bad-width #:width +inf.0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (rectangle #:id 'bad-stroke #:stroke-width -1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (rectangle #:id "not-a-symbol")))

  ;; Mixed Visual types share one significant back-to-front drawing order.

  ; mixed-scene : scene?
  ;;   Gives a scene with the rectangle behind the circle.
  (define mixed-scene
    (scene-add (make-scene) panel token))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-current-state mixed-scene)))
   '(panel token))

  ;; The existing movement animation works through the semantic Visual protocol.

  ; moving-panel-scene : scene?
  ;;   Gives a one-second rectangle movement.
  (define moving-panel-scene
    (scene-play mixed-scene
                (move-to panel (vec2 3 0))
                #:duration 1))

  ; panel-midpoint : rectangle-visual?
  ;;   Gives the rectangle sampled halfway through its movement.
  (define panel-midpoint
    (scene-state-ref (scene-sample moving-panel-scene 1/2)
                     'panel))
  (check-true (rectangle-visual? panel-midpoint))
  (check-eq? (visual-id panel-midpoint) 'panel)
  (check-equal? (visual-position panel-midpoint) origin)
  (check-equal? (rectangle-visual-width panel-midpoint) 2)
  (check-equal? (rectangle-visual-height panel-midpoint) 1)
  (check-equal? (visual-position
                 (scene-state-ref
                  (scene-sample moving-panel-scene 1/2)
                  'token))
                (vec2 3 0))

  ;; Circle and rectangle animations can run concurrently in one play clip.

  ; crossing-scene : scene?
  ;;   Gives two mixed Visual types crossing over two seconds.
  (define crossing-scene
    (scene-play mixed-scene
                (move-to panel (vec2 3 0))
                (move-to token (vec2 -3 0))
                #:duration 2))

  ; crossing-midpoint : scene-state?
  ;;   Gives the state where both Visual reference positions meet at the origin.
  (define crossing-midpoint
    (scene-sample crossing-scene 1))
  (check-equal?
   (visual-position (scene-state-ref crossing-midpoint 'panel))
   origin)
  (check-equal?
   (visual-position (scene-state-ref crossing-midpoint 'token))
   origin)
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order crossing-midpoint))
   '(panel token))

  ;; Removal remains model-level and works uniformly for the new Visual type.

  ; without-panel : scene?
  ;;   Gives mixed-scene after removing the rectangle by identity.
  (define without-panel
    (scene-remove mixed-scene 'panel))
  (check-equal?
   (map visual-id
        (scene-state-visuals-in-drawing-order
         (scene-current-state without-panel)))
   '(token)))
