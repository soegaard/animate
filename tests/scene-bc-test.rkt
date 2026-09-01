#lang racket/base

;;;
;;; SCENE-BC Group-Child Animation Tests
;;;

(require rackunit
         "../main.rkt")

(module+ test
  (define marker
    (circle #:id 'marker #:center origin #:radius 1 #:fill "blue"))
  (define label
    (rectangle #:id 'label #:center (vec2 0 1) #:width 1 #:height 1 #:fill "gold"))
  (define nested
    (group (list label) #:id 'nested))
  (define scatter
    (group (list marker nested) #:id 'scatter))
  (define base
    (scene-add (make-scene) scatter))

  ;; Paths use the existing composition scheduler. Each child is updated in its
  ;; own local group coordinates and its ancestor groups are rebuilt immutably.
  (define animated
    (scene-play
     base
     (animation-group
      (move-to '(scatter marker) (vec2 4 0))
      (fill-color-to '(scatter marker) "red")
      (fade-to '(scatter nested label) 1/2))
     #:duration 2))
  (define midpoint (scene-sample animated 1))
  (check-equal? (visual-position (scene-state-ref midpoint '(scatter marker)))
                (vec2 2 0))
  (check-equal? (visual-fill-color (scene-state-ref midpoint '(scatter marker)))
                (rgba-color 255/2 0 255/2 1))
  (check-equal? (visual-opacity (scene-state-ref midpoint '(scatter nested label)))
                3/4)
  (check-equal? (visual-position (scene-state-ref (scene-current-state animated)
                                                   '(scatter marker)))
                (vec2 4 0))
  (check-equal? (visual-fill-color
                 (scene-state-ref (scene-current-state animated) '(scatter marker)))
                "red")

  ;; Equal paths are equal scheduler targets even when callers construct two
  ;; separate list values. Different child paths remain independently animatable.
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"same animation component" (exn-message error))))
   (lambda ()
     (scene-play
      base
      (animation-group
       (move-to (list 'scatter 'marker) (vec2 1 0))
       (move-to (list 'scatter 'marker) (vec2 2 0)))
      #:duration 1)))
  (define independent
    (scene-play
     base
     (animation-group
      (move-to '(scatter marker) (vec2 2 0))
      (move-to '(scatter nested label) (vec2 0 3)))
     #:duration 1))
  (check-equal? (visual-position
                 (scene-state-ref (scene-current-state independent)
                                  '(scatter marker)))
                (vec2 2 0))
  (check-equal? (visual-position
                 (scene-state-ref (scene-current-state independent)
                                  '(scatter nested label)))
                (vec2 0 3))

  ;; Removal-capable child animations remove only their addressed leaf.
  (define removed
    (scene-play base (fade-out '(scatter marker)) #:duration 1))
  (check-false (scene-state-has? (scene-current-state removed) '(scatter marker)))
  (check-true (scene-state-has? (scene-current-state removed) '(scatter nested label))))
