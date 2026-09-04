#lang racket/base

;;;
;;; SCENE-ED Live Mathematical Annotation Tests
;;;

(require rackunit
         racket/class
         (only-in pict pict->bitmap)
         "../main.rkt")

(module+ test
  (define camera
    (make-camera #:width 320 #:height 180 #:world-width 12 #:background "white"))

  ;; Literal points retain the established immediate semantic paths/groups.
  (check-true
   (path-visual?
    (angle-between (vec2 1 0) origin (vec2 0 1) #:id 'literal-angle)))
  (check-true
   (path-visual?
    (right-angle-between (vec2 1 0) origin (vec2 0 1)
                         #:id 'literal-right-angle)))
  (check-true
   (path-visual?
    (brace-between origin (vec2 2 0) #:id 'literal-brace)))
  (check-true
   (group-visual?
    (brace-label origin (vec2 2 0) "base" #:id 'literal-brace-label)))
  (check-true
   (group-visual?
    (curved-arrow-between origin (vec2 2 0) #:id 'literal-curved-arrow)))

  ;; Centre references and point-valued parameters remain regular pure derived
  ;; Visuals. Sampling a later state rebuilds the concrete annotation from the
  ;; new values rather than moving a path snapshot.
  (define vertex
    (parameter 'vertex origin))
  (define parameter-angle
    (angle-between (vec2 2 0) vertex (vec2 0 2)
                   #:id 'parameter-angle #:radius 1/2))
  (define parameter-right-angle
    (right-angle-between (vec2 2 0) vertex (vec2 0 2)
                         #:id 'parameter-right-angle #:size 1/2))
  (define parameter-arrow
    (curved-arrow-between vertex (vec2 2 1) #:id 'parameter-arrow))
  (check-true (derived-visual? parameter-angle))
  (check-true (derived-visual? parameter-right-angle))
  (check-true (derived-visual? parameter-arrow))
  (define parameter-scene
    (scene-play
     (scene-add
      (scene-set-value (make-scene #:camera camera) vertex origin)
      parameter-angle parameter-right-angle parameter-arrow)
     (value-to vertex (vec2 1 1))
     #:duration 2))
  (define angle-at-start
    (scene-visual-at parameter-scene 'parameter-angle 0))
  (define angle-at-end
    (scene-visual-at parameter-scene 'parameter-angle 2))
  (check-true (path-visual? angle-at-start))
  (check-true (path-visual? angle-at-end))
  (check-not-equal? (path-visual-path angle-at-start)
                    (path-visual-path angle-at-end))
  (check-true
   (group-visual?
    (scene-visual-at parameter-scene 'parameter-arrow 1)))

  ;; Non-centre anchors wait for renderer measurement. A live brace label and
  ;; curved arrow can share this protocol and remain renderable after the
  ;; target circles move and scale in the same clip.
  (define left
    (circle #:id 'left #:center (vec2 -2 0) #:radius 1/3
            #:fill "aliceblue" #:stroke "navy" #:stroke-width 2))
  (define right
    (circle #:id 'right #:center (vec2 2 0) #:radius 1/3
            #:fill "aliceblue" #:stroke "navy" #:stroke-width 2))
  (define anchored-brace
    (brace-label (anchor-of 'left 'bottom #:offset (vec2 0 -1/10))
                 (anchor-of 'right 'bottom #:offset (vec2 0 -1/10))
                 "span" #:id 'anchored-brace #:offset -1/8))
  (define anchored-arrow
    (curved-arrow-between (anchor-of 'left 'top)
                          (anchor-of 'right 'top)
                          #:id 'anchored-arrow #:angle -1))
  (check-true (dynamic-endpoint-visual? anchored-brace))
  (check-true (dynamic-endpoint-visual? anchored-arrow))
  (check-true (dynamic-endpoint-visual-has-renderer-anchors? anchored-brace))
  (check-true (dynamic-endpoint-visual-has-renderer-anchors? anchored-arrow))
  (define anchored-scene
    (scene-play
     (scene-add (make-scene #:camera camera)
                anchored-brace anchored-arrow left right)
     (move-to 'left (vec2 -3 1/2))
     (move-to 'right (vec2 3 1/2))
     (scale-to 'right 3/2)
     #:duration 2))
  (check-not-false (pict->bitmap (scene->pict anchored-scene 0) 'aligned))
  (check-not-false (pict->bitmap (scene->pict anchored-scene 1) 'aligned))
  (check-not-false (pict->bitmap (scene->pict anchored-scene 2) 'aligned))

  ;; Targeting an annotation with one of its own endpoints would make the
  ;; dependency graph cyclic, and is rejected at construction time.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (brace-between 'left (vec2 1 0) #:id 'left))))
