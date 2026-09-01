#lang racket/base

;;;
;;; SCENE-AX Stable Moving Text Raster Tests
;;;

;; Verifies the v0.50.1 renderer correction that freezes one plain-text glyph
;; appearance at local origin and reuses it across position-only motion.

(require rackunit
         "../main.rkt")

(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera whose scale is independent of its center.
  (define test-camera
    (make-camera #:width 300
                 #:height 160
                 #:world-width 15
                 #:background "white"))

  ; panned-camera : camera?
  ;;   Gives the same pixel scale with a different world center.
  (define panned-camera
    (make-camera #:width 300
                 #:height 160
                 #:world-width 15
                 #:center (vec2 3 -1)
                 #:background "white"))

  ; zoomed-camera : camera?
  ;;   Gives a different pixel scale and therefore requires a fresh text raster.
  (define zoomed-camera
    (make-camera #:width 300
                 #:height 160
                 #:world-width 10
                 #:background "white"))

  ; label : text-visual?
  ;;   Gives the same word that exposed the moving-glyph rasterization artifact.
  (define label
    (plain-text "dependent"
                #:id 'label
                #:center origin
                #:font-size 2/5
                #:font-family 'swiss
                #:color "black"))

  ; local-raster : pict?
  ;;   Gives the default renderer's frozen local text appearance.
  (define local-raster
    (visual->pict label test-camera))

  ;; Translation is scene placement, not glyph rerasterization. The renderer
  ;; therefore returns the same cached local Pict for any position-only update.
  (check-eq?
   (visual->pict (visual-with-position label (vec2 1/30 0))
                 test-camera)
   local-raster)
  (check-eq?
   (visual->pict (visual-with-position label (vec2 7/3 -2))
                 test-camera)
   local-raster)
  (check-eq?
   (visual->pict
    (plain-text "dependent"
                #:id 'same-appearance-other-id
                #:font-size 2/5
                #:font-family 'swiss
                #:color "black")
    test-camera)
   local-raster)

  ;; Opacity is applied by the high-level adapter after renderer dispatch, so it
  ;; does not invalidate the underlying cached glyph raster either.
  (define text-renderer
    (for/first ([renderer (in-list default-pict-renderers)]
                #:when (pict-renderer-supports? renderer label))
      renderer))
  (check-true (pict-renderer? text-renderer))
  (check-eq?
   (pict-renderer-render text-renderer label test-camera)
   (pict-renderer-render text-renderer
                         (visual-with-opacity label 1/2)
                         test-camera))

  ;; Camera pan likewise changes only placement. Camera zoom changes the
  ;; world-to-pixel font scale and must rerasterize for sharp output.
  (check-eq? (visual->pict label panned-camera)
             local-raster)
  (check-false (eq? (visual->pict label zoomed-camera)
                    local-raster))

  ;; Appearance changes invalidate the cache key. Scale and rotation are baked
  ;; into the local frozen raster so continuously changing them rerasterizes.
  (check-false
   (eq? (visual->pict (text-visual-with-content label "dependency")
                      test-camera)
        local-raster))
  (check-false
   (eq? (visual->pict (visual-with-scale label 3/2)
                      test-camera)
        local-raster))
  (check-false
   (eq? (visual->pict (visual-with-rotation label 1/5)
                      test-camera)
        local-raster))
  (check-false
   (eq? (visual->pict
         (plain-text "dependent"
                     #:id 'different-font-label
                     #:font-size 2/5
                     #:font-family 'modern
                     #:color "black")
         test-camera)
        local-raster))
  (check-false
   (eq? (visual->pict
         (plain-text "dependent"
                     #:id 'recolored-label
                     #:font-size 2/5
                     #:font-family 'swiss
                     #:color "navy")
         test-camera)
        local-raster))
  (check-false
   (eq? (visual->pict
         (plain-text "dependent"
                     #:id 'left-label
                     #:font-size 2/5
                     #:font-family 'swiss
                     #:color "black"
                     #:horizontal-alignment 'left)
         test-camera)
        local-raster))

  ;; Mutable color strings are snapshotted by value for the cache key, so a
  ;; caller-side style mutation cannot leave a stale cached text raster behind.
  (define mutable-color
    (string-copy "gray"))
  (define mutable-color-label
    (plain-text "dependent"
                #:id 'mutable-color-label
                #:font-size 2/5
                #:font-family 'swiss
                #:color mutable-color))
  (define gray-raster
    (visual->pict mutable-color-label test-camera))
  (string-set! mutable-color 0 #\n)
  (string-set! mutable-color 1 #\a)
  (string-set! mutable-color 2 #\v)
  (check-equal? mutable-color "navy")
  (check-false (eq? (visual->pict mutable-color-label test-camera)
                    gray-raster))

  ;; A dependency-driven text Visual resolves to different world positions while
  ;; retaining exactly the same cacheable local appearance.
  (define anchor
    (circle #:id 'anchor
            #:center origin
            #:radius 1/4
            #:opacity 0))

  (define dependent-label
    (derived-visual
     (plain-text "dependent"
                 #:id 'dependent-label
                 #:font-size 2/5
                 #:font-family 'swiss
                 #:color "black")
     (lambda (context template)
       (visual-with-position
        template
        (visual-position
         (derived-context-visual-ref context 'anchor))))))

  (define moving-scene
    (scene-play
     (scene-add (make-scene #:camera test-camera)
                anchor
                dependent-label)
     (move-to 'anchor (vec2 2 0))
     #:duration 2
     #:easing linear))

  (define resolved-start
    (scene-state-resolved-ref (scene-sample moving-scene 0)
                              'dependent-label))
  (define resolved-middle
    (scene-state-resolved-ref (scene-sample moving-scene 1)
                              'dependent-label))

  (check-equal? (visual-position resolved-start) origin)
  (check-equal? (visual-position resolved-middle) (vec2 1 0))
  (check-eq? (visual->pict resolved-start test-camera)
             (visual->pict resolved-middle test-camera)))
