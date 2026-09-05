#lang racket/base
(require "../experimental.rkt")

;;;
;;; SCENE-BB Nested Visual Addressing Tests
;;;

(require rackunit
         "../main.rkt"
         "../private/scene-state.rkt")

(module+ test
  (define marker
    (circle #:id 'marker #:center (vec2 1 0) #:radius 1 #:fill "blue"))
  (define label
    (rectangle #:id 'label #:center (vec2 0 1) #:width 1 #:height 1 #:fill "gold"))
  (define annotation
    (group (list label) #:id 'annotation))
  (define scatter
    (group (list marker annotation) #:id 'scatter))
  (define state
    (scene-current-state (scene-add (make-scene) scatter)))

  ;; Paths are nonempty ordered symbol identities. Their local leaf is returned
  ;; without changing the existing top-level symbol API.
  (check-true (visual-path? '(scatter marker)))
  (check-false (visual-path? '()))
  (check-false (visual-path? '(scatter 1)))
  (check-true (scene-state-has? state '(scatter marker)))
  (check-true (scene-state-has? state '(scatter annotation label)))
  (check-false (scene-state-has? state '(scatter missing)))
  (check-equal? (scene-state-ref state '(scatter marker)) marker)
  (check-equal? (scene-state-resolved-ref state '(scatter annotation label)) label)
  (check-equal? (scene-ref (scene-add (make-scene) scatter) '(scatter marker))
                marker)
  (check-exn exn:fail?
             (lambda () (scene-state-ref state '(scatter marker missing))))

  ;; Immutable nested replacement rebuilds ancestors and leaves unrelated
  ;; children and the top-level drawing order intact.
  (define updated
    (scene-state-update state
                        '(scatter annotation label)
                        (visual-with-position label (vec2 3 4))))
  (check-equal?
   (visual-position (scene-state-ref updated '(scatter annotation label)))
   (vec2 3 4))
  (check-equal? (scene-state-ref updated '(scatter marker)) marker)
  (check-equal? (map visual-id (scene-state-visuals-in-drawing-order updated))
                '(scatter))
  (check-exn exn:fail?
             (lambda ()
               (scene-state-update state
                                   '(scatter marker)
                                   (circle #:id 'different #:radius 1))))

  ;; A derived resolver can depend on a nested concrete Visual through the same
  ;; sampled-state resolver.
  (define follower
    (derived-visual
     (circle #:id 'follower #:radius 1 #:fill "red")
     (lambda (context template)
       (visual-with-position
        template
        (visual-position
         (derived-context-visual-ref context '(scatter marker)))))))
  (define dependency-state
    (scene-current-state
     (scene-add (scene-add (make-scene) scatter) follower)))
  (check-equal?
   (visual-position (scene-state-resolved-ref dependency-state 'follower))
   (vec2 1 0)))
