#lang racket/base

;;;
;;; SCENE-K Rendering Tests
;;;

;; Tests recursive group composition, nested transform equivalence, significant
;; child order, renderer propagation, custom group overrides, opacity, and PNG
;; determinism.


;;;
;;; Imports
;;;

(require racket/file
         rackunit
         (only-in pict
                  filled-rectangle
                  pict-height
                  pict-width)
         (only-in "../private/group-visual.rkt"
                  group-visual-resolved-children)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 240
                 #:height 160
                 #:world-width 24
                 #:background "white"))

  ; scene-with : visual? -> scene?
  ;;   Creates a quarter-second static scene containing visual.
  (define (scene-with visual)
    (scene-wait (scene-add (make-scene) visual)
                1/4))

  ; visuals-scene : (listof visual?) -> scene?
  ;;   Creates a quarter-second static scene with back-to-front visuals.
  (define (visuals-scene visuals)
    (scene-wait (apply scene-add (make-scene) visuals)
                1/4))

  ;; Empty groups have a stable transparent one-pixel local Pict.

  ; empty-group : group-visual?
  ;;   Gives an empty semantic group.
  (define empty-group
    (group '() #:id 'empty-group))

  ; empty-group-pict : pict?
  ;;   Gives the local Pict for the empty group.
  (define empty-group-pict
    (visual->pict empty-group test-camera))

  (check-equal? (pict-width empty-group-pict) 1)
  (check-equal? (pict-height empty-group-pict) 1)
  (check-equal?
   (pict-width
    (visual->pict empty-group test-camera #:renderers '()))
   1)
  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual->pict
      (group (list (circle #:id 'unsupported-leaf))
             #:id 'unsupported-group)
      test-camera
      #:renderers '())))

  ;; A one-child group at the origin has the same layout box as its child after
  ;; inheriting the group's scale. Cosmetic stroke width is not multiplied.

  ; local-circle : circle-visual?
  ;;   Gives a stroked local child at the group anchor.
  (define local-circle
    (circle #:id 'local-circle
            #:radius 1
            #:fill "gold"
            #:stroke "navy"
            #:stroke-width 6))

  ; scaled-circle-group : group-visual?
  ;;   Gives a group that uniformly scales local-circle by two.
  (define scaled-circle-group
    (group (list local-circle)
           #:id 'scaled-circle-group
           #:scale 2))

  ; equivalent-scaled-circle : circle-visual?
  ;;   Gives the standalone semantic equivalent of the inherited child.
  (define equivalent-scaled-circle
    (visual-with-scale local-circle 2))

  ; scaled-group-pict : pict?
  ;;   Gives the recursively rendered one-child group.
  (define scaled-group-pict
    (visual->pict scaled-circle-group test-camera))

  ; scaled-circle-pict : pict?
  ;;   Gives the standalone equivalent child Pict.
  (define scaled-circle-pict
    (visual->pict equivalent-scaled-circle test-camera))

  (check-equal? (pict-width scaled-group-pict)
                (pict-width scaled-circle-pict))
  (check-equal? (pict-height scaled-group-pict)
                (pict-height scaled-circle-pict))

  ;; Significant child order changes overlap rendering.

  ; back-panel : rectangle-visual?
  ;;   Gives the first overlapping rectangle.
  (define back-panel
    (rectangle #:id 'back-panel
               #:width 6
               #:height 4
               #:fill "crimson"
               #:stroke #f
               #:stroke-width 0))

  ; front-panel : rectangle-visual?
  ;;   Gives the second overlapping rectangle.
  (define front-panel
    (rectangle #:id 'front-panel
               #:width 3
               #:height 2
               #:fill "royalblue"
               #:stroke #f
               #:stroke-width 0))

  ; ordered-group : group-visual?
  ;;   Gives a group with front-panel painted over back-panel.
  (define ordered-group
    (group (list back-panel front-panel)
           #:id 'ordered-group))

  ; reversed-group : group-visual?
  ;;   Gives the same children in the opposite drawing order.
  (define reversed-group
    (group (list front-panel back-panel)
           #:id 'reversed-group))

  ;; Parent rotation, uniform scale, and child-local positions produce the same
  ;; frame as explicitly resolved top-level children.

  ; left-child : circle-visual?
  ;;   Gives the back child for transform-equivalence testing.
  (define left-child
    (circle #:id 'left-child
            #:center (vec2 -2 0)
            #:scale (vec2 1 1/2)
            #:radius 1
            #:fill "gold"
            #:stroke "saddlebrown"))

  ; right-child : rectangle-visual?
  ;;   Gives the front child for transform-equivalence testing.
  (define right-child
    (rectangle #:id 'right-child
               #:center (vec2 2 0)
               #:rotation 1/5
               #:width 2
               #:height 1
               #:fill "cornflowerblue"
               #:stroke "navy"))

  ; transformed-group : group-visual?
  ;;   Gives a translated, rotated, and uniformly scaled group.
  (define transformed-group
    (group (list left-child right-child)
           #:id 'transformed-group
           #:center (vec2 3 -1)
           #:rotation 3/10
           #:scale 3/2))

  ; flattened-children : (listof affine-visual?)
  ;;   Gives the exact top-level equivalents of transformed-group's children.
  (define flattened-children
    (for/list ([child
                (in-list
                 (group-visual-resolved-children transformed-group))])
      (visual-with-position
       child
       (vec2+ (visual-position transformed-group)
              (visual-position child)))))

  ;; Custom child renderers propagate through every nesting level.

  (struct marker-visual (id transform)
    #:transparent
    #:methods gen:visual
    [(define (visual-id marker)
       (marker-visual-id marker))
     (define (visual-position marker)
       (affine-transform-translation
        (marker-visual-transform marker)))
     (define (visual-with-position marker position)
       (struct-copy marker-visual marker
                    [transform
                     (affine-transform-with-translation
                      (marker-visual-transform marker)
                      position)]))]
    #:methods gen:affine-visual
    [(define (visual-transform marker)
       (marker-visual-transform marker))
     (define (visual-with-transform marker transform)
       (struct-copy marker-visual marker [transform transform]))])

  ;; marker-visual represents a custom affine Visual.
  ;;  - id         symbol?             stable Visual identity.
  ;;  - transform  affine-transform?   complete local transform.

  ; marker-shape : pict?
  ;;   Gives the fixed local Pict returned by the custom renderer.
  (define marker-shape
    (filled-rectangle 30
                      20
                      #:color "darkorange"
                      #:border-color "saddlebrown"
                      #:border-width 2))

  (struct marker-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (marker-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       marker-shape)])

  ;; marker-renderer draws marker-visual values at full strength.

  ; marker-renderers : (listof pict-renderer?)
  ;;   Gives a custom renderer followed by the built-in renderers.
  (define marker-renderers
    (cons (marker-renderer)
          default-pict-renderers))

  ; nested-marker-group : group-visual?
  ;;   Gives two levels of groups around one custom affine Visual.
  (define nested-marker-group
    (group
     (list
      (group
       (list
        (marker-visual
         'marker
         (make-affine-transform #:translation (vec2 1 0))))
       #:id 'inner-marker-group
       #:scale 2))
     #:id 'outer-marker-group
     #:rotation 1/4
     #:scale 3/2))

  ; nested-marker-pict : pict?
  ;;   Gives the recursively rendered custom child.
  (define nested-marker-pict
    (visual->pict nested-marker-group
                  test-camera
                  #:renderers marker-renderers))

  (check-true (> (pict-width nested-marker-pict) 0))
  (check-true (> (pict-height nested-marker-pict) 0))

  ;; A custom renderer may deliberately override the built-in group compositor.

  (struct group-override-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (group-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       marker-shape)])

  ;; group-override-renderer replaces complete group composition.

  ; override-renderers : (listof pict-renderer?)
  ;;   Gives a group override before all built-in renderers.
  (define override-renderers
    (cons (group-override-renderer)
          default-pict-renderers))

  (check-eq? (visual->pict ordered-group
                           test-camera
                           #:renderers override-renderers)
             marker-shape)

  ;; Opacity is applied after recursive group composition. A transparent group
  ;; produces the same frame as an empty scene, while a half-opacity group has
  ;; unchanged local bounds.

  ; half-ordered-group : group-visual?
  ;;   Gives ordered-group at half global opacity.
  (define half-ordered-group
    (visual-with-opacity ordered-group 1/2))

  ; invisible-ordered-group : group-visual?
  ;;   Gives ordered-group at zero global opacity.
  (define invisible-ordered-group
    (visual-with-opacity ordered-group 0))

  (check-equal? (pict-width (visual->pict ordered-group test-camera))
                (pict-width (visual->pict half-ordered-group test-camera)))
  (check-equal? (pict-height (visual->pict ordered-group test-camera))
                (pict-height (visual->pict half-ordered-group test-camera)))

  ;; PNG output verifies composition, order, opacity, nested custom rendering,
  ;; transform equivalence, animation progression, and deterministic rerendering.

  ; temporary-root : path?
  ;;   Gives the isolated root directory for group PNG tests.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-k~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; render-one-frame! : scene? path-string?
      ;                     [#:renderers (listof pict-renderer?)]
      ;                     -> bytes?
      ;;   Renders one four-fps frame and returns its PNG bytes.
      (define (render-one-frame! scene directory
                                 #:renderers
                                 [renderers default-pict-renderers])
        (define frame-paths
          (render-frames! scene
                          directory
                          #:fps 4
                          #:camera test-camera
                          #:renderers renderers))
        (check-equal? (length frame-paths) 1)
        (file->bytes (car frame-paths)))

      ; ordered-bytes : bytes?
      ;;   Gives one frame with the declared child order.
      (define ordered-bytes
        (render-one-frame! (scene-with ordered-group)
                           (build-path temporary-root "ordered")))

      ; reversed-bytes : bytes?
      ;;   Gives one frame with reversed child order.
      (define reversed-bytes
        (render-one-frame! (scene-with reversed-group)
                           (build-path temporary-root "reversed")))

      (check-false (equal? ordered-bytes reversed-bytes))

      ; grouped-transform-bytes : bytes?
      ;;   Gives one frame of the nested-transform group.
      (define grouped-transform-bytes
        (render-one-frame! (scene-with transformed-group)
                           (build-path temporary-root "grouped-transform")))

      ; flattened-transform-bytes : bytes?
      ;;   Gives one frame of the equivalent resolved top-level children.
      (define flattened-transform-bytes
        (render-one-frame! (visuals-scene flattened-children)
                           (build-path temporary-root "flattened-transform")))

      (check-equal? grouped-transform-bytes
                    flattened-transform-bytes)

      ; empty-bytes : bytes?
      ;;   Gives one background-only frame.
      (define empty-bytes
        (render-one-frame! (scene-wait (make-scene) 1/4)
                           (build-path temporary-root "empty")))

      ; invisible-bytes : bytes?
      ;;   Gives one frame containing a zero-opacity group.
      (define invisible-bytes
        (render-one-frame! (scene-with invisible-ordered-group)
                           (build-path temporary-root "invisible")))

      (check-equal? invisible-bytes empty-bytes)

      ; nested-custom-bytes : bytes?
      ;;   Gives one frame rendered through a nested custom child renderer.
      (define nested-custom-bytes
        (render-one-frame! (scene-with nested-marker-group)
                           (build-path temporary-root "nested-custom")
                           #:renderers marker-renderers))

      (check-false (equal? nested-custom-bytes empty-bytes))

      ; animated-group : scene?
      ;;   Rotates, scales, moves, and fades one group over one second.
      (define animated-group
        (scene-play (scene-add (make-scene) ordered-group)
                    (move-to ordered-group (vec2 3 0))
                    (rotate-to ordered-group 1/2)
                    (scale-to ordered-group 3/2)
                    (fade-to ordered-group 1/4)
                    #:duration 1))

      ; animated-paths : (listof path?)
      ;;   Gives four frames sampled through the group animation.
      (define animated-paths
        (render-frames! animated-group
                        (build-path temporary-root "animated")
                        #:fps 4
                        #:camera test-camera))

      (check-equal? (length animated-paths) 4)
      (check-false (equal? (file->bytes (car animated-paths))
                           (file->bytes (car (reverse animated-paths)))))

      ; first-repeat-bytes : bytes?
      ;;   Gives the first deterministic rerender of ordered-group.
      (define first-repeat-bytes
        (render-one-frame! (scene-with ordered-group)
                           (build-path temporary-root "repeat-a")))

      ; second-repeat-bytes : bytes?
      ;;   Gives the second deterministic rerender of ordered-group.
      (define second-repeat-bytes
        (render-one-frame! (scene-with ordered-group)
                           (build-path temporary-root "repeat-b")))

      (check-equal? first-repeat-bytes second-repeat-bytes))
    (lambda ()
      (delete-directory/files temporary-root))))
