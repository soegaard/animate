#lang racket/base
(require "../experimental.rkt")

;;;
;;; SCENE-AY Interpolable Scene Value Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  ;; The protocol accepts the current renderer-independent semantic value kinds
  ;; and preserves callers' endpoint representations exactly.
  (define scalar-start 1.0)
  (define scalar-end 5.0)
  (check-true (interpolable? scalar-start))
  (check-true (interpolable? (vec2 0 0)))
  (check-true (interpolable? (rgb-color 10 20 30)))
  (check-false (interpolable? "not a semantic value"))
  (check-eq? (interpolate-value scalar-start scalar-end 0) scalar-start)
  (check-eq? (interpolate-value scalar-start scalar-end 1) scalar-end)
  (check-equal? (interpolate-value scalar-start scalar-end 1/4) 2.0)

  (define vector-start (vec2 0 0))
  (define vector-end (vec2 4 2))
  (check-eq? (interpolate-value vector-start vector-end 0) vector-start)
  (check-eq? (interpolate-value vector-start vector-end 1) vector-end)
  (check-equal? (interpolate-value vector-start vector-end 1/4)
                (vec2 1 1/2))

  (define color-start (rgba-color 0 20 40 1))
  (define color-end (rgba-color 100 120 140 1/2))
  (check-eq? (interpolate-value color-start color-end 0) color-start)
  (check-eq? (interpolate-value color-start color-end 1) color-end)
  (check-equal? (interpolate-value color-start color-end 1/2)
                (rgba-color 50 70 90 3/4))

  ;; A value is generic scene state: vector animation shares all ordinary
  ;; scheduling behavior with the prior scalar API.
  (define vector-base
    (scene-set-value (make-scene) 'center vector-start))
  (check-eq? (scene-current-value vector-base 'center) vector-start)
  (define vector-scene
    (scene-play vector-base (value-to 'center vector-end) #:duration 4))
  (check-eq? (scene-value-at vector-scene 'center 0) vector-start)
  (check-equal? (scene-value-at vector-scene 'center 1)
                (vec2 1 1/2))
  (check-equal? (scene-value-at vector-scene 'center 2)
                (vec2 2 1))
  (check-eq? (scene-current-value vector-scene 'center) vector-end)

  ;; Derived Visuals receive the semantic value directly rather than rebuilding
  ;; a point from independently animated scalar coordinates.
  (define follower
    (derived-visual
     (circle #:id 'follower #:radius 1 #:fill "blue")
     (lambda (context template)
       (visual-with-position
        template
        (derived-context-value-ref context 'center)))))
  (define derived-scene
    (scene-play
     (scene-add vector-base follower)
     (value-to 'center vector-end)
     #:duration 4))
  (check-equal?
   (visual-position
    (scene-state-resolved-ref (scene-sample derived-scene 2) 'follower))
   (vec2 2 1))

  ;; Requests remain independently valid before their start state is known;
  ;; incompatible values fail deterministically during scene compilation.
  (check-true (value-to-request? (value-to 'center color-end)))
  (check-exn exn:fail?
             (lambda ()
               (scene-play vector-base (value-to 'center color-end))))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-set-value (make-scene) 'bad "unsupported")))
  (check-exn exn:fail:contract?
             (lambda ()
               (value-to 'center "unsupported")))
  (check-exn exn:fail:contract?
             (lambda ()
               (interpolate-value vector-start vector-end 2))))
