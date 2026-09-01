#lang racket/base

;;;
;;; SCENE-X Frame-Space Model Tests
;;;

;; Tests pure fixed-in-frame and callout semantics, ordinary Visual animation,
;; camera interaction, and world/frame coordinate-domain validation.


;;;
;;; Imports
;;;

(require rackunit
         "../private/animation.rkt"
         "../private/camera-animation.rkt"
         "../private/camera.rkt"
         "../private/frame-space.rkt"
         "../private/geometry.rkt"
         "../private/group-visual.rkt"
         "../private/scene-state.rkt"
         "../private/scene.rkt"
         "../private/visual-model.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives the capture camera used to define stable frame coordinates.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 20
                 #:center (vec2 5 -2)
                 #:background "ivory"))

  ; label : rectangle-visual?
  ;;   Gives semantic content whose world placement differs from frame origin.
  (define label
    (rectangle #:id 'label
               #:center (vec2 8 1)
               #:width 4
               #:height 2
               #:fill "gold"
               #:stroke #f
               #:stroke-width 0))

  ; overlay : fixed-in-frame-visual?
  ;;   Gives label pinned at the same screen position it had under test-camera.
  (define overlay
    (fixed-in-frame label #:camera test-camera))

  ;; Construction snapshots frame width and converts the initial world position
  ;; to an origin-centered frame coordinate without changing semantic content.
  (check-true (fixed-in-frame-visual? overlay))
  (check-true (frame-space-visual? overlay))
  (check-equal? (visual-id overlay) 'label)
  (check-equal? (visual-position overlay) (vec2 3 3))
  (check-equal? (frame-space-visual-frame-width overlay) 20)
  (check-equal? (fixed-in-frame-visual-content overlay) label)
  (check-true (affine-visual? overlay))
  (check-true (opacity-visual? overlay))
  (check-equal? (visual-scale overlay) (vec2 1 1))
  (check-equal? (visual-rotation overlay) 0)
  (check-equal? (visual-opacity overlay) 1)

  ;; Explicit frame placement is interpreted relative to frame center.
  (define placed-overlay
    (fixed-in-frame label
                    #:camera test-camera
                    #:at (vec2 -7 4)
                    #:rotation 1/4
                    #:scale 2
                    #:opacity 3/4))
  (check-equal? (visual-position placed-overlay) (vec2 -7 4))
  (check-equal? (visual-rotation placed-overlay) 1/4)
  (check-equal? (visual-scale placed-overlay) (vec2 2 2))
  (check-equal? (visual-opacity placed-overlay) 3/4)

  ;; Frame-space cameras inherit output settings but ignore world pan and zoom.
  (define changed-camera
    (make-camera #:width 320
                 #:height 180
                 #:world-width 5
                 #:center (vec2 -100 80)
                 #:background "black"))
  (define overlay-camera
    (frame-space-camera changed-camera
                        (frame-space-visual-frame-width overlay)))
  (check-equal? (camera-width overlay-camera) 320)
  (check-equal? (camera-height overlay-camera) 180)
  (check-equal? (camera-world-width overlay-camera) 20)
  (check-equal? (camera-center overlay-camera) origin)
  (check-equal? (camera-background overlay-camera) "black")

  ;; Frame-space wrappers remain ordinary affine/opacity animation targets.
  (define animated-overlay-scene
    (scene-play
     (scene-add (make-scene #:camera test-camera)
                overlay)
     (move-to overlay (vec2 -2 1))
     (rotate-by overlay 1/2)
     (scale-by overlay 3/2)
     (fade-to overlay 1/4)
     (camera-pan-by (vec2 6 -3))
     (camera-zoom-by 2)
     #:duration 2))
  (define animated-overlay-end
    (scene-state-ref (scene-current-state animated-overlay-scene)
                     'label))
  (check-true (fixed-in-frame-visual? animated-overlay-end))
  (check-equal? (visual-position animated-overlay-end) (vec2 -2 1))
  (check-equal? (visual-rotation animated-overlay-end) 1/2)
  (check-equal? (visual-scale animated-overlay-end) (vec2 3/2 3/2))
  (check-equal? (visual-opacity animated-overlay-end) 1/4)
  (check-equal? (camera-center
                 (scene-current-camera animated-overlay-scene))
                (vec2 11 -5))
  (check-equal? (camera-world-width
                 (scene-current-camera animated-overlay-scene))
                10)

  ;; The world camera cannot follow something that already lives in frame space.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play
      (scene-add (make-scene #:camera test-camera)
                 overlay)
      (camera-follow overlay))))

  ; marker : circle-visual?
  ;;   Gives the world-space target used by callout tests.
  (define marker
    (circle #:id 'marker
            #:center (vec2 -4 2)
            #:radius 1/2
            #:fill "crimson"))

  ; annotation-content : rectangle-visual?
  ;;   Gives a simple frame annotation box independent of external fonts.
  (define annotation-content
    (rectangle #:id 'annotation
               #:center (vec2 9 2)
               #:width 3
               #:height 1
               #:fill "white"
               #:stroke "navy"
               #:stroke-width 2))

  ; annotation : callout-visual?
  ;;   Gives a fixed annotation pointing at marker by stable identity.
  (define annotation
    (callout annotation-content
             marker
             #:camera test-camera
             #:at (vec2 6 3)
             #:connector-stroke "navy"
             #:connector-width 3))

  (check-true (callout-visual? annotation))
  (check-true (frame-space-visual? annotation))
  (check-equal? (visual-id annotation) 'annotation)
  (check-equal? (visual-position annotation) (vec2 6 3))
  (check-equal? (frame-space-visual-frame-width annotation) 20)
  (check-equal? (callout-visual-content annotation)
                annotation-content)
  (check-equal? (callout-visual-target annotation) 'marker)
  (check-equal? (callout-visual-connector-stroke annotation) "navy")
  (check-equal? (callout-visual-connector-width annotation) 3)

  ;; Fixed world points are valid callout targets and remain literal vec2 values.
  (define point-callout
    (callout annotation-content
             (vec2 1 -3)
             #:camera test-camera
             #:connector-stroke #f
             #:connector-width 0))
  (check-equal? (callout-visual-target point-callout)
                (vec2 1 -3))
  (check-false (callout-visual-connector-stroke point-callout))
  (check-equal? (callout-visual-connector-width point-callout) 0)

  ;; Frame-space targets cannot be passed as callout Visual values.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (callout annotation-content
              overlay
              #:camera test-camera)))

  ;; Frame-space wrappers stay top-level. To make a compound overlay, build an
  ;; ordinary group first and wrap that complete group in frame space.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (group (list overlay) #:id 'invalid-world-group)))
  (define grouped-content
    (group (list
            (rectangle #:id 'grouped-child
                       #:center (vec2 1 0)
                       #:width 1
                       #:height 1
                       #:fill "white"))
           #:id 'grouped-content))
  (check-true
   (fixed-in-frame-visual?
    (fixed-in-frame grouped-content #:camera test-camera)))

  ;; Constructors reject nested wrappers and malformed frame requests.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (fixed-in-frame overlay #:camera test-camera)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (fixed-in-frame label #:camera 'not-a-camera)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (fixed-in-frame label
                     #:camera test-camera
                     #:at 'top-left)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (callout annotation-content
              42
              #:camera test-camera)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (callout annotation-content
              marker
              #:camera test-camera
              #:connector-width -1))))
