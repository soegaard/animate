#lang racket/base

;;;
;;; SCENE-N Rendering Tests
;;;

;; Tests recursive formula-assembly composition, significant part order,
;; custom renderer propagation and override, opacity, nesting, and deterministic
;; PNG output without launching TeX.


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

  ; formula-color : formula-visual? -> string?
  ;;   Selects a deterministic test color from formula source.
  (define (formula-color formula)
    (case (string->symbol (formula-visual-source formula))
      [(red) "crimson"]
      [(blue) "royalblue"]
      [(green) "forestgreen"]
      [else "darkorange"]))

  (struct test-formula-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (formula-visual? visual))
     (define (pict-renderer-render _renderer visual _camera)
       (filled-rectangle 30
                         18
                         #:color (formula-color visual)
                         #:border-color "black"
                         #:border-width 1))])

  ;; test-formula-renderer replaces external LaTeX with fixed colored Picts.

  ; formula-renderers : (listof pict-renderer?)
  ;;   Gives the deterministic formula renderer before the built-in renderers.
  (define formula-renderers
    (cons (test-formula-renderer)
          default-pict-renderers))

  ; make-part : symbol? string? vec2? -> formula-part?
  ;;   Creates one local part for deterministic renderer tests.
  (define (make-part name source center)
    (latex-formula-part source
                        #:name name
                        #:center center
                        #:font-size 1/2))

  ;; Empty assemblies use stable transparent one-pixel local geometry.
  ; empty-assembly : formula-assembly-visual?
  ;;   Gives an assembly with no formula parts.
  (define empty-assembly
    (formula-assembly '() #:id 'empty-formula-assembly))

  ; empty-assembly-pict : pict?
  ;;   Gives the rendered empty assembly without any renderer implementations.
  (define empty-assembly-pict
    (visual->pict empty-assembly
                  test-camera
                  #:renderers '()))

  (check-equal? (pict-width empty-assembly-pict) 1)
  (check-equal? (pict-height empty-assembly-pict) 1)

  ;; Nonempty assemblies propagate the explicit renderer list to every formula
  ;; part and fail when no child renderer is available.
  ; red-part : formula-part?
  ;;   Gives the left local formula part.
  (define red-part
    (make-part 'red "red" (vec2 -2 0)))

  ; blue-part : formula-part?
  ;;   Gives the right local formula part.
  (define blue-part
    (make-part 'blue "blue" (vec2 2 0)))

  ; two-part-assembly : formula-assembly-visual?
  ;;   Gives a transformed two-part assembly.
  (define two-part-assembly
    (formula-assembly (list red-part blue-part)
                      #:id 'two-part-assembly
                      #:center (vec2 1 -1)
                      #:rotation 1/5
                      #:scale 3/2
                      #:opacity 4/5))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (visual->pict two-part-assembly
                   test-camera
                   #:renderers '())))

  ; two-part-pict : pict?
  ;;   Gives the recursively rendered formula assembly.
  (define two-part-pict
    (visual->pict two-part-assembly
                  test-camera
                  #:renderers formula-renderers))

  (check-true (> (pict-width two-part-pict) 30))
  (check-true (> (pict-height two-part-pict) 18))

  ;; An ordinary group with the same formulas and transform renders identically.
  ; equivalent-group : group-visual?
  ;;   Gives the public group equivalent of two-part-assembly.
  (define equivalent-group
    (group (list (formula-part-formula red-part)
                 (formula-part-formula blue-part))
           #:id 'equivalent-group
           #:center (vec2 1 -1)
           #:rotation 1/5
           #:scale 3/2
           #:opacity 4/5))

  (check-equal?
   (pict-width two-part-pict)
   (pict-width
    (visual->pict equivalent-group
                  test-camera
                  #:renderers formula-renderers)))
  (check-equal?
   (pict-height two-part-pict)
   (pict-height
    (visual->pict equivalent-group
                  test-camera
                  #:renderers formula-renderers)))

  ;; A custom renderer placed first can replace the complete assembly compositor.
  ; assembly-override-shape : pict?
  ;;   Gives the fixed whole-assembly override Pict.
  (define assembly-override-shape
    (filled-rectangle 44
                      22
                      #:color "gold"
                      #:border-color "saddlebrown"
                      #:border-width 2))

  (struct assembly-override-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (formula-assembly-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       assembly-override-shape)])

  ;; assembly-override-renderer deliberately replaces recursive composition.

  ; assembly-override-renderers : (listof pict-renderer?)
  ;;   Gives a whole-assembly override before the formula renderer and defaults.
  (define assembly-override-renderers
    (cons (assembly-override-renderer)
          formula-renderers))

  ; opaque-assembly : formula-assembly-visual?
  ;;   Gives the same assembly at full global opacity.
  (define opaque-assembly
    (visual-with-opacity two-part-assembly 1))

  (check-eq?
   (visual->pict opaque-assembly
                 test-camera
                 #:renderers assembly-override-renderers)
   assembly-override-shape)

  ; translucent-override-pict : pict?
  ;;   Gives the whole-assembly override after semantic assembly opacity.
  (define translucent-override-pict
    (visual->pict two-part-assembly
                  test-camera
                  #:renderers assembly-override-renderers))

  (check-equal? (pict-width translucent-override-pict)
                (pict-width assembly-override-shape))
  (check-equal? (pict-height translucent-override-pict)
                (pict-height assembly-override-shape))
  (check-false (eq? translucent-override-pict
                    assembly-override-shape))

  ;; Formula assemblies remain ordinary affine children of nested groups.
  ; local-assembly : formula-assembly-visual?
  ;;   Gives one local assembly child for nested transform comparison.
  (define local-assembly
    (formula-assembly
     (list (make-part 'green "green" origin))
     #:id 'local-assembly
     #:center (vec2 2 0)
     #:rotation 1/5
     #:scale 3/2))

  ; parent-group : group-visual?
  ;;   Gives a translated, rotated, and uniformly scaled parent.
  (define parent-group
    (group (list local-assembly)
           #:id 'assembly-parent
           #:center (vec2 -3 1)
           #:rotation 3/10
           #:scale 2))

  ; resolved-assembly : formula-assembly-visual?
  ;;   Gives the exact top-level equivalent of the nested assembly child.
  (define resolved-assembly
    (let ([resolved
           (car (group-visual-resolved-children parent-group))])
      (visual-with-position
       resolved
       (vec2+ (visual-position parent-group)
              (visual-position resolved)))))

  ;; Filesystem-level checks compare actual rasterized output from the fixed
  ;; custom renderers.
  ; temporary-root : path?
  ;;   Gives the isolated root directory for formula-assembly PNG tests.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-n~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; render-one-frame! : scene? path-string? (listof pict-renderer?) -> bytes?
      ;;   Renders one four-fps frame and returns its PNG bytes.
      (define (render-one-frame! scene directory renderers)
        (define frame-paths
          (render-frames! scene
                          directory
                          #:fps 4
                          #:camera test-camera
                          #:renderers renderers))
        (check-equal? (length frame-paths) 1)
        (file->bytes (car frame-paths)))

      ; assembly-bytes : bytes?
      ;;   Gives one frame of the named formula assembly.
      (define assembly-bytes
        (render-one-frame! (scene-with two-part-assembly)
                           (build-path temporary-root "assembly")
                           formula-renderers))

      ; group-bytes : bytes?
      ;;   Gives one frame of the equivalent ordinary group.
      (define group-bytes
        (render-one-frame! (scene-with equivalent-group)
                           (build-path temporary-root "group")
                           formula-renderers))

      (check-equal? assembly-bytes group-bytes)

      ;; Back-to-front part order changes pixels when parts overlap.
      ; overlapping-red : formula-part?
      ;;   Gives a red formula at the assembly anchor.
      (define overlapping-red
        (make-part 'overlapping-red "red" origin))

      ; overlapping-blue : formula-part?
      ;;   Gives a blue formula at the same assembly anchor.
      (define overlapping-blue
        (make-part 'overlapping-blue "blue" origin))

      ; ordered-bytes : bytes?
      ;;   Gives a frame with the blue part painted over the red part.
      (define ordered-bytes
        (render-one-frame!
         (scene-with
          (formula-assembly
           (list overlapping-red overlapping-blue)
           #:id 'ordered-formula))
         (build-path temporary-root "ordered")
         formula-renderers))

      ; reversed-bytes : bytes?
      ;;   Gives a frame with the red part painted over the blue part.
      (define reversed-bytes
        (render-one-frame!
         (scene-with
          (formula-assembly
           (list overlapping-blue overlapping-red)
           #:id 'reversed-formula))
         (build-path temporary-root "reversed")
         formula-renderers))

      (check-false (equal? ordered-bytes reversed-bytes))

      ;; Nested and explicitly flattened assembly transforms render identically.
      ; nested-bytes : bytes?
      ;;   Gives one frame of the nested formula assembly.
      (define nested-bytes
        (render-one-frame! (scene-with parent-group)
                           (build-path temporary-root "nested")
                           formula-renderers))

      ; flattened-bytes : bytes?
      ;;   Gives one frame of the resolved top-level assembly.
      (define flattened-bytes
        (render-one-frame! (scene-with resolved-assembly)
                           (build-path temporary-root "flattened")
                           formula-renderers))

      (check-equal? nested-bytes flattened-bytes)

      ;; Zero assembly opacity is equivalent to a background-only frame.
      ; empty-bytes : bytes?
      ;;   Gives one background-only frame.
      (define empty-bytes
        (render-one-frame! (scene-wait (make-scene) 1/4)
                           (build-path temporary-root "empty")
                           formula-renderers))

      ; invisible-bytes : bytes?
      ;;   Gives one frame containing a zero-opacity formula assembly.
      (define invisible-bytes
        (render-one-frame!
         (scene-with (visual-with-opacity two-part-assembly 0))
         (build-path temporary-root "invisible")
         formula-renderers))

      (check-equal? invisible-bytes empty-bytes)

      ;; Whole-assembly animation affects deterministic frame output.
      ; animated-assembly : scene?
      ;;   Moves, rotates, scales, and fades one assembly for one second.
      (define animated-assembly
        (scene-play
         (scene-add (make-scene) opaque-assembly)
         (move-to opaque-assembly (vec2 4 1))
         (rotate-to opaque-assembly 1/2)
         (scale-to opaque-assembly 2)
         (fade-to opaque-assembly 1/4)
         #:duration 1))

      ; animated-paths : (listof path?)
      ;;   Gives four frames sampled through the assembly animation.
      (define animated-paths
        (render-frames! animated-assembly
                        (build-path temporary-root "animated")
                        #:fps 4
                        #:camera test-camera
                        #:renderers formula-renderers))

      (check-equal? (length animated-paths) 4)
      (check-false
       (equal? (file->bytes (car animated-paths))
               (file->bytes (car (reverse animated-paths)))))

      ;; Repeated rendering with fixed semantic values and renderers is exact.
      ; first-repeat-bytes : bytes?
      ;;   Gives the first deterministic assembly rerender.
      (define first-repeat-bytes
        (render-one-frame! (scene-with two-part-assembly)
                           (build-path temporary-root "repeat-a")
                           formula-renderers))

      ; second-repeat-bytes : bytes?
      ;;   Gives the second deterministic assembly rerender.
      (define second-repeat-bytes
        (render-one-frame! (scene-with two-part-assembly)
                           (build-path temporary-root "repeat-b")
                           formula-renderers))

      (check-equal? first-repeat-bytes second-repeat-bytes))
    (lambda ()
      (delete-directory/files temporary-root))))
