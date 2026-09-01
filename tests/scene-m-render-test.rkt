#lang racket/base

;;;
;;; SCENE-M Rendering Tests
;;;

;; Tests formula renderer selection, deterministic injected typesetting, size
;; calibration, anchor alignment, affine transforms, groups, opacity, and PNG
;; output without requiring an external TeX process.


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
         (submod "../private/latex-formula-pict-renderer.rkt"
                 test-support)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with twenty pixels per world unit.
  (define test-camera
    (make-camera #:width 200
                 #:height 100
                 #:world-width 10
                 #:background "white"))

  ; base-formula-pict : pict?
  ;;   Gives deterministic visible geometry standing in for a TeX result.
  (define base-formula-pict
    (filled-rectangle 20
                      10
                      #:color "navy"
                      #:border-color "black"
                      #:border-width 1))

  ; fake-typesetter : formula-visual? -> pict?
  ;;   Returns the deterministic formula Pict without running TeX.
  (define (fake-typesetter _visual)
    base-formula-pict)

  ; render-formula : formula-visual? -> pict?
  ;;   Renders a formula through the injected deterministic typesetter.
  (define (render-formula visual)
    (formula-visual->pict/using visual
                                test-camera
                                fake-typesetter))

  ; scene-with : visual? -> scene?
  ;;   Creates a quarter-second static scene containing visual.
  (define (scene-with visual)
    (scene-wait (scene-add (make-scene) visual)
                1/4))

  ;; Semantic modes map to the three documented latex-pict procedures.

  (check-equal? (formula-mode->latex-binding 'inline)
                'tex-math)
  (check-equal? (formula-mode->latex-binding 'display)
                'tex-display-math)
  (check-equal?
   (formula-mode->latex-binding 'display-environment)
   'tex-real-display-math)

  ;; The latex-pict adapter forwards source and all explicit options to the
  ;; selected mode-specific procedure.

  ; loaded-bindings : box?
  ;;   Records binding names requested through the injected loader.
  (define loaded-bindings
    (box '()))

  ; typesetter-calls : box?
  ;;   Records arguments received by the injected latex-pict procedure.
  (define typesetter-calls
    (box '()))

  ; recording-loader : symbol? -> procedure?
  ;;   Returns a keyword typesetter while recording the requested binding.
  (define (recording-loader binding)
    (set-box! loaded-bindings
              (cons binding (unbox loaded-bindings)))
    (lambda (source
             #:document-class-options document-options
             #:preview-options preview-options
             #:preamble preamble
             #:scale scale-factor)
      (set-box! typesetter-calls
                (cons (list source
                            document-options
                            preview-options
                            preamble
                            scale-factor)
                      (unbox typesetter-calls)))
      base-formula-pict))

  ; forwarded-formula : formula-visual?
  ;;   Gives a formula with explicit adapter options for forwarding tests.
  (define forwarded-formula
    (latex-formula "x^2+y^2"
                   #:id 'forwarded-formula
                   #:mode 'inline
                   #:preamble "\\usepackage{amsmath}"
                   #:document-class-options
                   (list "12pt" 'fleqn)
                   #:preview-options
                   (list 'tightpage "lyx")))

  (check-eq? (typeset-formula/using forwarded-formula
                                     recording-loader)
             base-formula-pict)
  (check-equal? (unbox loaded-bindings)
                (list 'tex-math))
  (check-equal?
   (unbox typesetter-calls)
   (list
    (list "x^2+y^2"
          (list "12pt" 'fleqn)
          (list 'tightpage "lyx")
          "\\usepackage{amsmath}"
          1)))

  (check-exn exn:fail:contract?
             (lambda ()
               (typeset-formula/using forwarded-formula
                                      (lambda (_binding)
                                        'not-a-procedure))))

  ;; Standard document-class font sizes calibrate semantic world-unit sizing.

  ; default-formula : formula-visual?
  ;;   Gives a ten-point-base formula with a one-world-unit font size.
  (define default-formula
    (latex-formula "x^2" #:id 'default-formula))

  ; eleven-point-formula : formula-visual?
  ;;   Gives the same semantic size with an eleven-point document base.
  (define eleven-point-formula
    (latex-formula "x^2"
                   #:id 'eleven-point-formula
                   #:document-class-options
                   (list "11pt")))

  ; twelve-point-formula : formula-visual?
  ;;   Gives the same semantic size with a twelve-point document base.
  (define twelve-point-formula
    (latex-formula "x^2"
                   #:id 'twelve-point-formula
                   #:document-class-options
                   (list "12pt")))

  (check-equal? (formula-document-font-points default-formula) 10)
  (check-equal? (formula-document-font-points eleven-point-formula) 11)
  (check-equal? (formula-document-font-points twelve-point-formula) 12)
  (check-equal? (formula-font-scale default-formula test-camera) 2)
  (check-equal? (formula-font-scale eleven-point-formula test-camera)
                20/11)
  (check-equal? (formula-font-scale twelve-point-formula test-camera)
                5/3)

  ;; A centered formula maps its base TeX font size to semantic world units.

  ; centered-pict : pict?
  ;;   Gives the deterministic centered formula rendering.
  (define centered-pict
    (render-formula default-formula))

  (check-true (pict? centered-pict))
  (check-equal? (pict-width centered-pict) 40)
  (check-equal? (pict-height centered-pict) 20)

  ;; Empty source has stable one-pixel geometry and skips the typesetter.

  ; typesetter-call-count : box?
  ;;   Counts calls made while rendering an empty formula.
  (define typesetter-call-count
    (box 0))

  ; counting-typesetter : formula-visual? -> pict?
  ;;   Records each invocation and returns deterministic visible geometry.
  (define (counting-typesetter _visual)
    (set-box! typesetter-call-count
              (add1 (unbox typesetter-call-count)))
    base-formula-pict)

  ; empty-pict : pict?
  ;;   Gives the local Pict for empty semantic formula source.
  (define empty-pict
    (formula-visual->pict/using
     (latex-formula "" #:id 'empty-formula)
     test-camera
     counting-typesetter))

  (check-equal? (unbox typesetter-call-count) 0)
  (check-equal? (pict-width empty-pict) 1)
  (check-equal? (pict-height empty-pict) 1)

  ;; An injected typesetter must return a Pict.

  (check-exn exn:fail:contract?
             (lambda ()
               (formula-visual->pict/using
                default-formula
                test-camera
                (lambda (_visual) 'not-a-pict))))

  ;; Semantic x and y scale are applied around the selected formula anchor.

  ; stretched-pict : pict?
  ;;   Gives the centered formula with a two-by-three semantic scale.
  (define stretched-pict
    (render-formula
     (visual-with-scale default-formula
                        (vec2 2 3))))

  (check-equal? (pict-width stretched-pict) 80)
  (check-equal? (pict-height stretched-pict) 60)

  ;; A quarter turn exchanges the local axis-aligned extents.

  ; turned-pict : pict?
  ;;   Gives the formula after a quarter-turn rotation.
  (define turned-pict
    (render-formula
     (visual-with-rotation default-formula
                           (/ pi 2))))

  (check-= (pict-width turned-pict)
           (pict-height centered-pict)
           1e-6)
  (check-= (pict-height turned-pict)
           (pict-width centered-pict)
           1e-6)

  ;; Left and right anchors double centered width. Top and bottom anchors double
  ;; centered height. Baseline anchoring keeps explicit ascent/descent space.

  ; left-pict : pict?
  ;;   Gives the formula anchored at its left edge.
  (define left-pict
    (render-formula
     (latex-formula "x^2"
                    #:id 'left-formula
                    #:horizontal-alignment 'left)))

  ; right-pict : pict?
  ;;   Gives the formula anchored at its right edge.
  (define right-pict
    (render-formula
     (latex-formula "x^2"
                    #:id 'right-formula
                    #:horizontal-alignment 'right)))

  ; top-pict : pict?
  ;;   Gives the formula anchored at its top edge.
  (define top-pict
    (render-formula
     (latex-formula "x^2"
                    #:id 'top-formula
                    #:vertical-alignment 'top)))

  ; bottom-pict : pict?
  ;;   Gives the formula anchored at its bottom edge.
  (define bottom-pict
    (render-formula
     (latex-formula "x^2"
                    #:id 'bottom-formula
                    #:vertical-alignment 'bottom)))

  ; baseline-pict : pict?
  ;;   Gives the formula anchored on its Pict baseline.
  (define baseline-pict
    (render-formula
     (latex-formula "x^2"
                    #:id 'baseline-formula
                    #:vertical-alignment 'baseline)))

  (check-equal? (pict-width left-pict)
                (* 2 (pict-width centered-pict)))
  (check-equal? (pict-width right-pict)
                (* 2 (pict-width centered-pict)))
  (check-equal? (pict-height top-pict)
                (* 2 (pict-height centered-pict)))
  (check-equal? (pict-height bottom-pict)
                (* 2 (pict-height centered-pict)))
  (check-true (>= (pict-height baseline-pict)
                  (pict-height centered-pict)))

  ;; The default renderer set recognizes formulas without requiring TeX during
  ;; support selection.

  (check-true
   (for/or ([renderer (in-list default-pict-renderers)])
     (pict-renderer-supports? renderer default-formula)))

  ;; A custom renderer before the defaults can override built-in formulas.

  ; override-shape : pict?
  ;;   Gives the fixed Pict returned by the custom formula renderer.
  (define override-shape
    (filled-rectangle 36
                      18
                      #:color "tomato"
                      #:border-color "darkred"
                      #:border-width 2))

  (struct formula-override-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (formula-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       override-shape)])

  ;; formula-override-renderer deliberately replaces LaTeX typesetting.

  ; override-renderers : (listof pict-renderer?)
  ;;   Gives the custom formula renderer before all built-in renderers.
  (define override-renderers
    (cons (formula-override-renderer)
          default-pict-renderers))

  (check-eq? (visual->pict default-formula
                           test-camera
                           #:renderers override-renderers)
             override-shape)

  ;; Semantic opacity is applied after custom formula renderer dispatch.

  ; half-opaque-pict : pict?
  ;;   Gives the custom formula rendering at half opacity.
  (define half-opaque-pict
    (visual->pict
     (visual-with-opacity default-formula 1/2)
     test-camera
     #:renderers override-renderers))

  (check-equal? (pict-width half-opaque-pict)
                (pict-width override-shape))
  (check-equal? (pict-height half-opaque-pict)
                (pict-height override-shape))

  ;; Recursive groups propagate the same explicit formula renderer. A group and
  ;; its explicitly flattened child render identically.

  ; local-group-formula : formula-visual?
  ;;   Gives one local formula child for transform-equivalence testing.
  (define local-group-formula
    (latex-formula "x+y"
                   #:id 'local-group-formula
                   #:center (vec2 2 1)
                   #:rotation 1/5
                   #:scale (vec2 3/2 4/5)))

  ; formula-group : group-visual?
  ;;   Gives a transformed one-child formula group.
  (define formula-group
    (group (list local-group-formula)
           #:id 'formula-group
           #:center (vec2 -3 1)
           #:rotation 3/10
           #:scale 2))

  ; resolved-group-formula : formula-visual?
  ;;   Gives the exact top-level equivalent of formula-group's child.
  (define resolved-group-formula
    (let ([resolved
           (car (group-visual-resolved-children formula-group))])
      (visual-with-position
       resolved
       (vec2+ (visual-position formula-group)
              (visual-position resolved)))))

  ;; PNG output uses the custom renderer so the deterministic suite has no
  ;; external TeX, Poppler, or font-installation dependency.

  ; temporary-root : path?
  ;;   Gives the isolated root directory for formula PNG tests.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-m~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; render-one-frame! : scene? path-string? -> bytes?
      ;;   Renders one four-fps frame and returns its PNG bytes.
      (define (render-one-frame! scene directory)
        (define frame-paths
          (render-frames! scene
                          directory
                          #:fps 4
                          #:camera test-camera
                          #:renderers override-renderers))
        (check-equal? (length frame-paths) 1)
        (file->bytes (car frame-paths)))

      ; empty-bytes : bytes?
      ;;   Gives one background-only frame.
      (define empty-bytes
        (render-one-frame! (scene-wait (make-scene) 1/4)
                           (build-path temporary-root "empty")))

      ; invisible-bytes : bytes?
      ;;   Gives one frame containing a zero-opacity formula.
      (define invisible-bytes
        (render-one-frame!
         (scene-with
          (visual-with-opacity default-formula 0))
         (build-path temporary-root "invisible")))

      (check-equal? invisible-bytes empty-bytes)

      ; grouped-bytes : bytes?
      ;;   Gives one frame of the nested formula group.
      (define grouped-bytes
        (render-one-frame! (scene-with formula-group)
                           (build-path temporary-root "grouped")))

      ; flattened-bytes : bytes?
      ;;   Gives one frame of the resolved standalone formula child.
      (define flattened-bytes
        (render-one-frame! (scene-with resolved-group-formula)
                           (build-path temporary-root "flattened")))

      (check-equal? grouped-bytes flattened-bytes)

      ; animated-formula : scene?
      ;;   Moves, rotates, scales, and fades one formula for one second.
      (define animated-formula
        (scene-play (scene-add (make-scene) default-formula)
                    (move-to default-formula (vec2 3 1))
                    (rotate-to default-formula 1/2)
                    (scale-to default-formula (vec2 3/2 3/4))
                    (fade-to default-formula 1/4)
                    #:duration 1))

      ; animated-paths : (listof path?)
      ;;   Gives four frames sampled through the formula animation.
      (define animated-paths
        (render-frames! animated-formula
                        (build-path temporary-root "animated")
                        #:fps 4
                        #:camera test-camera
                        #:renderers override-renderers))

      (check-equal? (length animated-paths) 4)
      (check-false
       (equal? (file->bytes (car animated-paths))
               (file->bytes (car (reverse animated-paths)))))

      ; first-repeat-bytes : bytes?
      ;;   Gives the first deterministic formula rerender.
      (define first-repeat-bytes
        (render-one-frame! (scene-with default-formula)
                           (build-path temporary-root "repeat-a")))

      ; second-repeat-bytes : bytes?
      ;;   Gives the second deterministic formula rerender.
      (define second-repeat-bytes
        (render-one-frame! (scene-with default-formula)
                           (build-path temporary-root "repeat-b")))

      (check-equal? first-repeat-bytes second-repeat-bytes))
    (lambda ()
      (delete-directory/files temporary-root))))
