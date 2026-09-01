#lang racket/base

;;;
;;; SCENE-U Camera Timeline Tests
;;;

;; Tests pure camera requests, mixed scene clips, and arbitrary-time sampling.
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
  ; visual-update-count : (box/c exact-nonnegative-integer?)
  ;;   Counts test-only Visual updates during timeline sampling.
  (define visual-update-count
    (box 0))

  (struct sampling-probe-visual (id position)
    #:transparent
    #:methods gen:visual
    [(define (visual-id visual)
       (sampling-probe-visual-id visual))
     (define (visual-position visual)
       (sampling-probe-visual-position visual))
     (define (visual-with-position visual position)
       (set-box! visual-update-count
                 (add1 (unbox visual-update-count)))
       (sampling-probe-visual
        (sampling-probe-visual-id visual)
        position))])

  ;; sampling-probe-visual is a test double that records position updates.
  ;;  - id        symbol?  stable Visual identity.
  ;;  - position  vec2?    current semantic reference position.

  ; initial-camera : camera?
  ;;   Gives the fixed frame configuration used by the camera tests.
  (define initial-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 12
                 #:center origin
                 #:background "ivory"))

  ; marker : circle-visual?
  ;;   Gives the Visual animated concurrently with the camera.
  (define marker
    (circle #:id 'marker
            #:center origin
            #:radius 1/2))

  ; base-scene : scene?
  ;;   Gives a zero-duration scene with an explicit initial camera.
  (define base-scene
    (scene-add (make-scene #:camera initial-camera)
               marker))

  ;; A scene stores and samples its initial camera.
  (check-equal? (scene-current-camera base-scene)
                initial-camera)
  (check-equal? (scene-camera-at base-scene 0)
                initial-camera)

  ;; Instantaneous camera replacement changes no duration or clip count.
  (define replacement-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 8
                 #:center (vec2 -2 1)
                 #:background "ivory"))
  (define replaced-scene
    (scene-set-camera base-scene replacement-camera))
  (check-equal? (scene-current-camera replaced-scene)
                replacement-camera)
  (check-equal? (scene-duration replaced-scene) 0)
  (check-equal? (scene-clip-count replaced-scene) 0)
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-set-camera base-scene 'not-a-camera)))

  ;; Request constructors validate their semantic values.
  (check-true (camera-pan-to-request?
               (camera-pan-to (vec2 2 1))))
  (check-true (camera-pan-by-request?
               (camera-pan-by (vec2 -1 2))))
  (check-true (camera-zoom-to-request?
               (camera-zoom-to 6)))
  (check-true (camera-zoom-by-request?
               (camera-zoom-by 2)))
  (check-exn exn:fail:contract?
             (lambda ()
               (camera-pan-to '(2 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (camera-pan-by '(2 1))))
  (check-exn exn:fail:contract?
             (lambda ()
               (camera-zoom-to 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (camera-zoom-by -1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (camera-zoom-by +inf.0)))

  ;; Visual and camera components run concurrently in one play clip.
  (define focus-scene
    (scene-play base-scene
                (move-to marker (vec2 4 0))
                (camera-pan-to (vec2 2 1))
                (camera-zoom-by 2)
                #:duration 2))

  (define focus-mid-camera
    (scene-camera-at focus-scene 1))
  (define focus-end-camera
    (scene-camera-at focus-scene 2))
  (check-equal? (camera-center focus-mid-camera)
                (vec2 1 1/2))
  (check-equal? (camera-world-width focus-mid-camera)
                9)
  (check-equal? (camera-center focus-end-camera)
                (vec2 2 1))
  (check-equal? (camera-world-width focus-end-camera)
                6)
  (check-equal? (camera-width focus-mid-camera) 200)
  (check-equal? (camera-height focus-mid-camera) 100)
  (check-equal? (camera-background focus-mid-camera) "ivory")
  (check-equal?
   (visual-position
    (scene-state-ref (scene-sample focus-scene 1)
                     'marker))
   (vec2 2 0))

  ;; The sampled camera center maps to the fixed frame center.
  (define-values (mid-center-x mid-center-y)
    (camera-world->pixel focus-mid-camera
                         (camera-center focus-mid-camera)))
  (check-equal? mid-center-x 100)
  (check-equal? mid-center-y 50)

  ;; Relative magnification values below one zoom out.
  (define zoomed-out-scene
    (scene-play base-scene
                (camera-zoom-by 1/2)
                #:duration 1))
  (check-equal? (camera-world-width
                 (scene-current-camera zoomed-out-scene))
                24)

  ;; Replacing the endpoint camera does not rewrite earlier clips.
  (define replaced-focus-scene
    (scene-set-camera focus-scene replacement-camera))
  (check-equal? (scene-camera-at replaced-focus-scene 1)
                focus-mid-camera)
  (check-equal? (scene-camera-at replaced-focus-scene 2)
                replacement-camera)

  ;; Relative requests compile from the endpoint of the preceding clip.
  (define reframed-scene
    (scene-play focus-scene
                (camera-pan-by (vec2 -1 2))
                (camera-zoom-to 10)
                #:duration 1))
  (check-equal? (camera-center
                 (scene-camera-at reframed-scene 5/2))
                (vec2 3/2 2))
  (check-equal? (camera-world-width
                 (scene-camera-at reframed-scene 5/2))
                8)
  (check-equal? (camera-center
                 (scene-camera-at reframed-scene 3))
                (vec2 1 3))
  (check-equal? (camera-world-width
                 (scene-camera-at reframed-scene 3))
                10)

  ;; A wait clip holds the camera together with the Visual state.
  (define held-scene
    (scene-wait reframed-scene 1/2))
  (check-equal? (scene-camera-at held-scene 13/4)
                (scene-current-camera held-scene))
  (check-equal? (scene-camera-at held-scene 7/2)
                (scene-current-camera held-scene))

  ;; Camera center and world width are separate animation components.
  (check-not-exn
   (lambda ()
     (scene-play base-scene
                 (camera-pan-to (vec2 1 0))
                 (camera-zoom-to 7))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play base-scene
                 (camera-pan-to (vec2 1 0))
                 (camera-pan-by (vec2 1 0)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play base-scene
                 (camera-zoom-to 7)
                 (camera-zoom-by 2))))

  ;; Request order does not affect disjoint Visual and camera components.
  (define order-a
    (scene-play base-scene
                (move-to marker (vec2 2 0))
                (camera-pan-to (vec2 1 0))
                (camera-zoom-to 8)
                #:duration 2))
  (define order-b
    (scene-play base-scene
                (camera-zoom-to 8)
                (camera-pan-to (vec2 1 0))
                (move-to marker (vec2 2 0))
                #:duration 2))
  (check-equal? (scene-camera-at order-a 1)
                (scene-camera-at order-b 1))
  (check-equal? (scene-sample order-a 1)
                (scene-sample order-b 1))

  ;; The convenient single-list form accepts mixed requests.
  (define list-form-scene
    (scene-play base-scene
                (list (camera-pan-to (vec2 3 0))
                      (camera-zoom-to 4))
                #:duration 1))
  (check-equal? (camera-center
                 (scene-current-camera list-form-scene))
                (vec2 3 0))
  (check-equal? (camera-world-width
                 (scene-current-camera list-form-scene))
                4)

  ;; Camera-only sampling does not apply unrelated Visual animations.
  (define sampling-probe
    (sampling-probe-visual 'sampling-probe origin))
  (define independent-sampling-scene
    (scene-play
     (scene-add (make-scene #:camera initial-camera)
                sampling-probe)
     (move-to sampling-probe (vec2 2 0))
     (camera-pan-to (vec2 1 0))
     #:duration 1))
  (set-box! visual-update-count 0)
  (void (scene-camera-at independent-sampling-scene 1/2))
  (check-equal? (unbox visual-update-count) 0)
  (void (scene-sample independent-sampling-scene 1/2))
  (check-equal? (unbox visual-update-count) 1)
  (set-box! visual-update-count 0)
  (define-values (_independent-state _independent-camera)
    (scene-sample-with-camera independent-sampling-scene 1/2))
  (check-equal? (unbox visual-update-count) 1)

  ;; Mixed Visual and camera sampling evaluates shared easing only once.
  (define easing-call-count
    (box 0))
  (define (counting-easing progress)
    (set-box! easing-call-count
              (add1 (unbox easing-call-count)))
    progress)

  ;; Sampling an unchanged track does not evaluate the clip easing.
  (define camera-only-scene
    (scene-play base-scene
                (camera-pan-to (vec2 1 0))
                #:duration 1
                #:easing counting-easing))
  (set-box! easing-call-count 0)
  (void (scene-sample camera-only-scene 1/2))
  (check-equal? (unbox easing-call-count) 0)
  (void (scene-camera-at camera-only-scene 1/2))
  (check-equal? (unbox easing-call-count) 1)

  (set-box! easing-call-count 0)
  (define visual-only-scene
    (scene-play base-scene
                (move-to marker (vec2 1 0))
                #:duration 1
                #:easing counting-easing))
  (set-box! easing-call-count 0)
  (void (scene-camera-at visual-only-scene 1/2))
  (check-equal? (unbox easing-call-count) 0)
  (void (scene-sample visual-only-scene 1/2))
  (check-equal? (unbox easing-call-count) 1)

  (set-box! easing-call-count 0)
  (define shared-easing-scene
    (scene-play base-scene
                (move-to marker (vec2 2 0))
                (camera-pan-to (vec2 1 0))
                #:duration 1
                #:easing counting-easing))
  (check-equal? (unbox easing-call-count) 1)
  (set-box! easing-call-count 0)
  (define-values (_shared-state _shared-camera)
    (scene-sample-with-camera shared-easing-scene 1/2))
  (check-equal? (unbox easing-call-count) 1)

  ;; Camera endpoints follow easing, just like ordinary affine animation.
  (define frozen-camera-scene
    (scene-play base-scene
                (camera-pan-to (vec2 5 0))
                (camera-zoom-to 3)
                #:duration 1
                #:easing (lambda (_progress) 0)))
  (check-equal? (scene-current-camera frozen-camera-scene)
                initial-camera)

  ;; Sampling outside the closed scene interval is rejected.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-camera-at focus-scene -1/30)))
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-camera-at focus-scene 61/30)))

  ;; Invalid request values are rejected by scene-play before compilation.
  (check-exn exn:fail:contract?
             (lambda ()
               (scene-play base-scene 'not-an-animation))))
