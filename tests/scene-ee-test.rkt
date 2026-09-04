#lang racket/base

;;;
;;; SCENE-EE — Camera View II
;;;

;; Secondary camera views select one or many live world layers, use a semantic
;; viewport clip, and animate their own immutable camera independently of the
;; main scene camera.

(require racket/class
         rackunit
         "../main.rkt")

(module+ test
  (define outer-camera
    (make-camera #:width 480 #:height 270 #:world-width 9 #:background "white"))
  (define inset-camera
    (make-camera #:width 240
                 #:height 135
                 #:world-width 4
                 #:center origin
                 #:background "ivory"))
  (define red-dot
    (circle #:id 'red-dot
            #:center (vec2 -1 0)
            #:radius 2/5
            #:fill "tomato"
            #:stroke "firebrick"
            #:stroke-width 2))
  (define blue-dot
    (circle #:id 'blue-dot
            #:center (vec2 1 0)
            #:radius 2/5
            #:fill "dodgerblue"
            #:stroke "navy"
            #:stroke-width 2))
  (define inset
    (camera-view #:id 'inset
                 #:targets '(red-dot blue-dot)
                 #:camera inset-camera
                 #:frame-camera outer-camera
                 #:at (vec2 3 3/2)
                 #:width 3
                 #:clip 'rounded))
  (define all-layers
    (camera-view #:id 'all-layers
                 #:camera inset-camera
                 #:frame-camera outer-camera
                 #:at (vec2 -3 3/2)
                 #:width 3))
  (define base
    (scene-add (make-scene #:camera outer-camera)
               red-dot blue-dot inset all-layers))
  (define static (scene-wait base 1))

  ;; Explicit multi-target selection retains the declared order; omitted
  ;; selection represents every ordinary top-level world-space layer.
  (check-false (camera-view-visual-target inset))
  (check-equal? (camera-view-visual-targets inset) '(red-dot blue-dot))
  (check-equal? (camera-view-visual-clip inset) 'rounded)
  (check-false (camera-view-visual-targets all-layers))
  (check-true
   (camera? (camera-view-visual-camera
             (camera-view-visual-with-camera inset inset-camera))))

  ;; Both view variants render as ordinary frame-space overlays. In particular,
  ;; the all-layer view does not recursively draw a view inside itself.
  (define static-bitmap (scene-frame->bitmap static 0 #:fps 1))
  (check-equal? (send static-bitmap get-width) 480)
  (check-equal? (send static-bitmap get-height) 270)

  ;; Pan and zoom alter separate camera components and compose with an ordinary
  ;; world motion in the same clip.
  (define panned-and-zoomed
    (scene-play
     static
     (animation-group
      (move-to 'red-dot (vec2 2 0))
      (camera-view-pan-to 'inset (vec2 1 0))
      (camera-view-zoom-by 'inset 2))
     #:duration 1
     #:easing linear))
  (define panned-and-zoomed-inset
    (scene-state-ref (scene-sample panned-and-zoomed 2) 'inset))
  (check-equal?
   (camera-center (camera-view-visual-camera panned-and-zoomed-inset))
   (vec2 1 0))
  (check-equal?
   (camera-world-width (camera-view-visual-camera panned-and-zoomed-inset))
   2)
  (check-not-false (scene-frame->bitmap panned-and-zoomed 1 #:fps 1))

  ;; Follow runs after the regular red-dot motion at each sample, retaining the
  ;; original one-unit offset between dot and inset centre. No prior-frame
  ;; rendering is needed to produce the half-way camera state.
  (define followed
    (scene-play
     static
     (animation-group
      (move-to 'red-dot (vec2 2 0))
      (camera-view-follow 'inset 'red-dot))
     #:duration 1
     #:easing linear))
  (define halfway-follow-view
    (scene-state-ref (scene-sample followed 3/2) 'inset))
  (define final-follow-view
    (scene-state-ref (scene-sample followed 2) 'inset))
  (check-equal?
   (camera-center (camera-view-visual-camera halfway-follow-view))
   (vec2 3/2 0))
  (check-equal?
   (camera-center (camera-view-visual-camera final-follow-view))
   (vec2 3 0))

  ;; Existing renderer-aware camera fitting produces the endpoint supplied to a
  ;; secondary view. The computed fit retains its exact measured components.
  (define measured-fit
    (camera-fit-visuals (list red-dot blue-dot)
                        #:camera inset-camera
                        #:padding 1/3))
  (define fitted
    (scene-play static (camera-view-fit 'inset measured-fit)
                #:duration 1
                #:easing linear))
  (define fitted-camera
    (camera-view-visual-camera
     (scene-state-ref (scene-sample fitted 2) 'inset)))
  (check-equal? (camera-center fitted-camera)
                (camera-fit-request-center measured-fit))
  (check-equal? (camera-world-width fitted-camera)
                (camera-fit-request-world-width measured-fit))

  ;; Two updates to one secondary-camera component remain an error, matching
  ;; the existing ordinary-camera and Visual component rules.
  (check-exn
   exn:fail?
   (lambda ()
     (scene-play
      static
      (animation-group
       (camera-view-pan-to 'inset origin)
       (camera-view-follow 'inset 'red-dot))
      #:duration 1))))
