#lang racket/base

;;;
;;; SCENE-W Camera-Following Tests
;;;

;; Tests clip-local camera following, camera-component conflicts, structural
;; targets, and deterministic interaction with simultaneous zoom.
;;
;; This module intentionally imports no Pict, bitmap, filesystem, or process
;; adapter.


;;;
;;; Imports
;;;

(require rackunit
         "../private/animation.rkt"
         "../private/camera-animation.rkt"
         "../private/camera.rkt"
         "../private/geometry.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives the fixed two-to-one camera used by following tests.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center origin
                 #:background "ivory"))

  ; marker : circle-visual?
  ;;   Gives a marker whose initial frame offset is easy to inspect exactly.
  (define marker
    (circle #:id 'marker
            #:center (vec2 -4 2)
            #:radius 1/2))

  ; base-scene : scene?
  ;;   Gives a scene containing marker and test-camera.
  (define base-scene
    (scene-add (make-scene #:camera test-camera)
               marker))

  ;; Public construction accepts Visuals and ids and rejects other targets.
  (check-true (camera-follow-request?
               (camera-follow marker)))
  (check-true (camera-follow-request?
               (camera-follow 'marker)))
  (check-exn exn:fail:contract?
             (lambda ()
               (camera-follow "marker")))

  ;; Following preserves the target's normalized frame position.
  (define followed-scene
    (scene-play base-scene
                (move-to marker (vec2 4 -2))
                (camera-follow marker)
                #:duration 2))

  (check-equal? (camera-center
                 (scene-camera-at followed-scene 0))
                origin)
  (check-equal? (camera-center
                 (scene-camera-at followed-scene 1))
                (vec2 4 -2))
  (check-equal? (camera-center
                 (scene-camera-at followed-scene 2))
                (vec2 8 -4))
  (check-equal? (camera-world-width
                 (scene-current-camera followed-scene))
                20)

  ;; Simultaneous zoom changes world offsets while preserving pixel offsets.
  (define followed-and-zoomed-scene
    (scene-play base-scene
                (move-to marker (vec2 4 -2))
                (camera-follow 'marker)
                (camera-zoom-by 2)
                #:duration 2))

  (define followed-mid-camera
    (scene-camera-at followed-and-zoomed-scene 1))
  (define followed-end-camera
    (scene-camera-at followed-and-zoomed-scene 2))

  (check-equal? (camera-world-width followed-mid-camera) 15)
  (check-equal? (camera-center followed-mid-camera)
                (vec2 3 -3/2))
  (check-equal? (camera-world-width followed-end-camera) 10)
  (check-equal? (camera-center followed-end-camera)
                (vec2 6 -3))

  ;; The target occupies one fixed pixel position throughout the clip.
  (for ([time (in-list '(0 1 2))])
    (define state
      (scene-sample followed-and-zoomed-scene time))
    (define camera
      (scene-camera-at followed-and-zoomed-scene time))
    (define target-position
      (visual-position
       (scene-state-ref state 'marker)))
    (define-values (pixel-x pixel-y)
      (camera-world->pixel camera target-position))
    (check-equal? pixel-x 60)
    (check-equal? pixel-y 30))

  ;; A stationary off-center target keeps its pixel position during zoom.
  (define stationary-zoom-scene
    (scene-play base-scene
                (camera-follow marker)
                (camera-zoom-by 2)
                #:duration 1))
  (check-equal? (camera-world-width
                 (scene-current-camera stationary-zoom-scene))
                10)
  (check-equal? (camera-center
                 (scene-current-camera stationary-zoom-scene))
                (vec2 -2 1))
  (define stationary-end-position
    (visual-position
     (scene-state-ref (scene-current-state stationary-zoom-scene)
                      'marker)))
  (define-values (stationary-pixel-x stationary-pixel-y)
    (camera-world->pixel (scene-current-camera stationary-zoom-scene)
                         stationary-end-position))
  (check-equal? stationary-pixel-x 60)
  (check-equal? stationary-pixel-y 30)

  ;; Follow and zoom are disjoint; two center requests still conflict.
  (check-not-exn
   (lambda ()
     (scene-play base-scene
                 (camera-follow marker)
                 (camera-zoom-to 8))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play base-scene
                 (camera-follow marker)
                 (camera-pan-to origin))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play base-scene
                 (camera-follow marker)
                 (camera-follow 'marker))))

  ;; Request order does not affect movement, follow, and zoom.
  (define order-a
    (scene-play base-scene
                (move-to marker (vec2 4 -2))
                (camera-follow marker)
                (camera-zoom-to 10)
                #:duration 2))
  (define order-b
    (scene-play base-scene
                (camera-zoom-to 10)
                (camera-follow marker)
                (move-to marker (vec2 4 -2))
                #:duration 2))
  (check-equal? (scene-camera-at order-a 1)
                (scene-camera-at order-b 1))
  (check-equal? (scene-sample order-a 1)
                (scene-sample order-b 1))

  ;; A Visual introduced in the same clip can be followed regardless of order.
  (define introduced-marker
    (circle #:id 'introduced-marker
            #:center (vec2 -2 0)
            #:radius 1/2))
  (define introduced-scene
    (scene-play
     (make-scene #:camera test-camera)
     (camera-follow introduced-marker)
     (move-to introduced-marker (vec2 2 0))
     (fade-in introduced-marker)
     #:duration 1))
  (check-equal? (camera-center
                 (scene-current-camera introduced-scene))
                (vec2 4 0))
  (check-true
   (scene-state-has? (scene-current-state introduced-scene)
                     'introduced-marker))

  ;; Create and uncreate targets retain a followable motion state.
  (define reveal-path
    (line (vec2 -1 0)
          (vec2 1 0)
          #:id 'reveal-path))
  (define created-and-followed-scene
    (scene-play
     (make-scene #:camera test-camera)
     (camera-follow reveal-path)
     (move-to reveal-path (vec2 3 0))
     (create reveal-path)
     #:duration 1))
  (check-equal? (camera-center
                 (scene-current-camera created-and-followed-scene))
                (vec2 3 0))
  (check-true
   (scene-state-has? (scene-current-state created-and-followed-scene)
                     'reveal-path))

  (define uncreated-and-followed-scene
    (scene-play created-and-followed-scene
                (move-to 'reveal-path (vec2 5 0))
                (camera-follow 'reveal-path)
                (uncreate 'reveal-path)
                #:duration 1))
  (check-equal? (camera-center
                 (scene-current-camera uncreated-and-followed-scene))
                (vec2 5 0))
  (check-false
   (scene-state-has? (scene-current-state uncreated-and-followed-scene)
                     'reveal-path))

  ;; A target may be followed through a structural fade-out and then removed.
  (define removed-scene
    (scene-play base-scene
                (move-to marker origin)
                (camera-follow marker)
                (fade-out marker)
                #:duration 1))
  (check-equal? (camera-center
                 (scene-current-camera removed-scene))
                (vec2 4 -2))
  (check-false
   (scene-state-has? (scene-current-state removed-scene)
                     'marker))

  ;; Missing targets fail during clip compilation.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play base-scene
                 (camera-follow 'missing))))

  (struct invalid-position-visual (id)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual)
       (invalid-position-visual-id visual))
     (define (visual-position _visual)
       'not-a-point)
     (define (visual-with-position visual _position)
       visual)])

  ;; invalid-position-visual is a test double with a broken position method.
  ;;  - id  symbol?  stable Visual identity.

  (define invalid-position
    (invalid-position-visual 'invalid-position))
  (define invalid-position-scene
    (scene-add (make-scene #:camera test-camera)
               invalid-position))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play invalid-position-scene
                 (camera-follow invalid-position))))

  ;; Unusual easing affects follow endpoints like ordinary pan and zoom.
  (define frozen-follow-scene
    (scene-play base-scene
                (move-to marker (vec2 4 -2))
                (camera-follow marker)
                #:duration 1
                #:easing (lambda (_progress) 0)))
  (check-equal? (scene-current-camera frozen-follow-scene)
                test-camera)
  (check-equal?
   (visual-position
    (scene-state-ref (scene-current-state frozen-follow-scene)
                     'marker))
   (vec2 -4 2)))
