#lang racket/base

;;;
;;; SCENE-L Rendering Tests
;;;

;; Tests built-in plain-text rendering, font sizing, anchor alignment, affine
;; transforms, groups, opacity, renderer overrides, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/file
         rackunit
         (only-in racket/math pi)
         (only-in pict
                  filled-rectangle
                  pict?
                  pict-height
                  pict-width)
         (only-in "../private/group-visual.rkt"
                  group-visual-resolved-children)
         "../main.rkt"
         "../render.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 320
                 #:height 180
                 #:world-width 32
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

  ;; The default renderer set includes semantic text.

  ; centered-text : text-visual?
  ;;   Gives a centered modern-family text line.
  (define centered-text
    (plain-text "Racket"
                #:id 'centered-text
                #:font-family 'modern
                #:font-size 1))

  ; centered-pict : pict?
  ;;   Gives the built-in Pict rendering of centered-text.
  (define centered-pict
    (visual->pict centered-text test-camera))

  (check-true (pict? centered-pict))
  (check-true (> (pict-width centered-pict) 0))
  (check-true (> (pict-height centered-pict) 0))

  ;; Empty text has stable invisible local geometry.

  ; empty-text-pict : pict?
  ;;   Gives the local Pict for empty semantic text.
  (define empty-text-pict
    (visual->pict (plain-text "" #:id 'empty-text)
                  test-camera))

  (check-equal? (pict-width empty-text-pict) 1)
  (check-equal? (pict-height empty-text-pict) 1)

  ;; Font size is measured in world units and converted through the camera.

  ; small-text-pict : pict?
  ;;   Gives a small rendering of the same glyph sequence.
  (define small-text-pict
    (visual->pict
     (plain-text "MMMM"
                 #:id 'small-text
                 #:font-family 'modern
                 #:font-size 1/4)
     test-camera))

  ; large-text-pict : pict?
  ;;   Gives a larger rendering of the same glyph sequence.
  (define large-text-pict
    (visual->pict
     (plain-text "MMMM"
                 #:id 'large-text
                 #:font-family 'modern
                 #:font-size 1)
     test-camera))

  (check-true (> (pict-width large-text-pict)
                 (pict-width small-text-pict)))
  (check-true (> (pict-height large-text-pict)
                 (pict-height small-text-pict)))

  ;; Semantic x and y scale are applied around the selected text anchor.

  ; stretched-text-pict : pict?
  ;;   Gives centered-text with a two-by-three semantic scale.
  (define stretched-text-pict
    (visual->pict
     (visual-with-scale centered-text (vec2 2 3))
     test-camera))

  (check-= (pict-width stretched-text-pict)
           (* 2 (pict-width centered-pict))
           1e-8)
  (check-= (pict-height stretched-text-pict)
           (* 3 (pict-height centered-pict))
           1e-8)

  ;; A quarter turn exchanges the axis-aligned local extents.

  ; turned-text-pict : pict?
  ;;   Gives centered-text after a quarter-turn rotation.
  (define turned-text-pict
    (visual->pict
     (visual-with-rotation centered-text (/ pi 2))
     test-camera))

  (check-= (pict-width turned-text-pict)
           (pict-height centered-pict)
           1e-6)
  (check-= (pict-height turned-text-pict)
           (pict-width centered-pict)
           1e-6)

  ;; Anchor-aligned Picts keep the semantic anchor at their center. Left and
  ;; right anchors need twice the centered width; top and bottom anchors need
  ;; twice the centered height.

  ; left-pict : pict?
  ;;   Gives the same text anchored at its left edge.
  (define left-pict
    (visual->pict
     (plain-text "Racket"
                 #:id 'left-text
                 #:font-family 'modern
                 #:font-size 1
                 #:horizontal-alignment 'left)
     test-camera))

  ; right-pict : pict?
  ;;   Gives the same text anchored at its right edge.
  (define right-pict
    (visual->pict
     (plain-text "Racket"
                 #:id 'right-text
                 #:font-family 'modern
                 #:font-size 1
                 #:horizontal-alignment 'right)
     test-camera))

  ; top-pict : pict?
  ;;   Gives the same text anchored at its top edge.
  (define top-pict
    (visual->pict
     (plain-text "Racket"
                 #:id 'top-text
                 #:font-family 'modern
                 #:font-size 1
                 #:vertical-alignment 'top)
     test-camera))

  ; bottom-pict : pict?
  ;;   Gives the same text anchored at its bottom edge.
  (define bottom-pict
    (visual->pict
     (plain-text "Racket"
                 #:id 'bottom-text
                 #:font-family 'modern
                 #:font-size 1
                 #:vertical-alignment 'bottom)
     test-camera))

  ; baseline-pict : pict?
  ;;   Gives the same text anchored on its font baseline.
  (define baseline-pict
    (visual->pict
     (plain-text "Racket"
                 #:id 'baseline-text
                 #:font-family 'modern
                 #:font-size 1
                 #:vertical-alignment 'baseline)
     test-camera))

  (check-= (pict-width left-pict)
           (* 2 (pict-width centered-pict))
           1e-8)
  (check-= (pict-width right-pict)
           (* 2 (pict-width centered-pict))
           1e-8)
  (check-= (pict-height top-pict)
           (* 2 (pict-height centered-pict))
           1e-8)
  (check-= (pict-height bottom-pict)
           (* 2 (pict-height centered-pict))
           1e-8)
  (check-true (>= (pict-height baseline-pict)
                  (pict-height centered-pict)))

  ;; An explicit renderer before the defaults can override built-in text.

  ; override-shape : pict?
  ;;   Gives the fixed Pict returned by the custom text renderer.
  (define override-shape
    (filled-rectangle 40
                      20
                      #:color "tomato"
                      #:border-color "darkred"
                      #:border-width 2))

  (struct text-override-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (text-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       override-shape)])

  ;; text-override-renderer deliberately replaces built-in text rendering.

  ; override-renderers : (listof pict-renderer?)
  ;;   Gives the custom text renderer before all built-in renderers.
  (define override-renderers
    (cons (text-override-renderer)
          default-pict-renderers))

  (check-eq? (visual->pict centered-text
                           test-camera
                           #:renderers override-renderers)
             override-shape)

  ;; Recursive group composition propagates text rendering and inherited
  ;; transforms. The group and an explicitly flattened child render identically.

  ; local-group-text : text-visual?
  ;;   Gives one local text child for transform-equivalence testing.
  (define local-group-text
    (plain-text "Nested"
                #:id 'local-group-text
                #:center (vec2 2 1)
                #:rotation 1/5
                #:scale (vec2 3/2 4/5)
                #:font-family 'swiss
                #:font-weight 'bold
                #:font-size 3/5
                #:color "navy"
                #:horizontal-alignment 'left
                #:vertical-alignment 'baseline))

  ; text-group : group-visual?
  ;;   Gives a translated, rotated, and uniformly scaled one-child group.
  (define text-group
    (group (list local-group-text)
           #:id 'text-group
           #:center (vec2 -3 1)
           #:rotation 3/10
           #:scale 2))

  ; resolved-group-text : text-visual?
  ;;   Gives the exact top-level equivalent of text-group's child.
  (define resolved-group-text
    (let ([resolved
           (car (group-visual-resolved-children text-group))])
      (visual-with-position
       resolved
       (vec2+ (visual-position text-group)
              (visual-position resolved)))))

  ;; Opacity preserves local text bounds and zero opacity matches an empty frame.

  ; half-text-pict : pict?
  ;;   Gives centered-text at half opacity.
  (define half-text-pict
    (visual->pict
     (visual-with-opacity centered-text 1/2)
     test-camera))

  (check-equal? (pict-width half-text-pict)
                (pict-width centered-pict))
  (check-equal? (pict-height half-text-pict)
                (pict-height centered-pict))

  ;; PNG output verifies anchor direction, color, nested group equivalence,
  ;; opacity, animation progression, and deterministic repeated output.

  ; temporary-root : path?
  ;;   Gives the isolated root directory for text PNG tests.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-l~a" 'directory))

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

      ; empty-bytes : bytes?
      ;;   Gives one background-only frame.
      (define empty-bytes
        (render-one-frame! (scene-wait (make-scene) 1/4)
                           (build-path temporary-root "empty")))

      ; invisible-bytes : bytes?
      ;;   Gives one frame containing zero-opacity text.
      (define invisible-bytes
        (render-one-frame!
         (scene-with (visual-with-opacity centered-text 0))
         (build-path temporary-root "invisible")))

      (check-equal? invisible-bytes empty-bytes)

      ; left-bytes : bytes?
      ;;   Gives one frame with text extending right from its anchor.
      (define left-bytes
        (render-one-frame!
         (scene-with
          (plain-text "Anchor"
                      #:id 'left-frame
                      #:font-family 'modern
                      #:font-size 1
                      #:horizontal-alignment 'left))
         (build-path temporary-root "left")))

      ; right-bytes : bytes?
      ;;   Gives one frame with text extending left from its anchor.
      (define right-bytes
        (render-one-frame!
         (scene-with
          (plain-text "Anchor"
                      #:id 'right-frame
                      #:font-family 'modern
                      #:font-size 1
                      #:horizontal-alignment 'right))
         (build-path temporary-root "right")))

      (check-false (equal? left-bytes right-bytes))

      ; navy-bytes : bytes?
      ;;   Gives one frame of navy text.
      (define navy-bytes
        (render-one-frame!
         (scene-with
          (plain-text "Color"
                      #:id 'navy-text
                      #:font-family 'modern
                      #:font-size 1
                      #:color "navy"))
         (build-path temporary-root "navy")))

      ; crimson-bytes : bytes?
      ;;   Gives one frame of crimson text.
      (define crimson-bytes
        (render-one-frame!
         (scene-with
          (plain-text "Color"
                      #:id 'crimson-text
                      #:font-family 'modern
                      #:font-size 1
                      #:color "crimson"))
         (build-path temporary-root "crimson")))

      (check-false (equal? navy-bytes crimson-bytes))

      ; grouped-bytes : bytes?
      ;;   Gives one frame of the nested text group.
      (define grouped-bytes
        (render-one-frame! (scene-with text-group)
                           (build-path temporary-root "grouped")))

      ; flattened-bytes : bytes?
      ;;   Gives one frame of the resolved standalone text child.
      (define flattened-bytes
        (render-one-frame! (visuals-scene (list resolved-group-text))
                           (build-path temporary-root "flattened")))

      (check-equal? grouped-bytes flattened-bytes)

      ; animated-text : scene?
      ;;   Moves, rotates, scales, and fades one text Visual for one second.
      (define animated-text
        (scene-play (scene-add (make-scene) centered-text)
                    (move-to centered-text (vec2 4 1))
                    (rotate-to centered-text 1/2)
                    (scale-to centered-text (vec2 3/2 3/4))
                    (fade-to centered-text 1/4)
                    #:duration 1))

      ; animated-paths : (listof path?)
      ;;   Gives four frames sampled through the text animation.
      (define animated-paths
        (render-frames! animated-text
                        (build-path temporary-root "animated")
                        #:fps 4
                        #:camera test-camera))

      (check-equal? (length animated-paths) 4)
      (check-false (equal? (file->bytes (car animated-paths))
                           (file->bytes (car (reverse animated-paths)))))

      ; first-repeat-bytes : bytes?
      ;;   Gives the first deterministic rerender of centered-text.
      (define first-repeat-bytes
        (render-one-frame! (scene-with centered-text)
                           (build-path temporary-root "repeat-a")))

      ; second-repeat-bytes : bytes?
      ;;   Gives the second deterministic rerender of centered-text.
      (define second-repeat-bytes
        (render-one-frame! (scene-with centered-text)
                           (build-path temporary-root "repeat-b")))

      (check-equal? first-repeat-bytes second-repeat-bytes))
    (lambda ()
      (delete-directory/files temporary-root))))
