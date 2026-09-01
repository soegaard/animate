#lang racket/base

;;;
;;; SCENE-O Rendering Tests
;;;

;; Tests formula-part transformation through deterministic custom formula
;; renderers, scene sampling, Pict composition, and repeated PNG output.


;;;
;;; Imports
;;;

(require racket/file
         rackunit
         (only-in pict
                  filled-rectangle
                  pict-height
                  pict-width)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 320
                 #:height 180
                 #:world-width 32
                 #:background "white"))

  ; formula-color : formula-visual? -> string?
  ;;   Selects a deterministic color from one test formula source.
  (define (formula-color formula)
    (cond
      [(equal? (formula-visual-source formula) "+") "crimson"]
      [(equal? (formula-visual-source formula) "-") "royalblue"]
      [(equal? (formula-visual-source formula) "c") "forestgreen"]
      [else "darkorange"]))

  ; formula-width : formula-visual? -> positive-real?
  ;;   Selects a deterministic width from one test formula source.
  (define (formula-width formula)
    (+ 18 (* 4 (string-length (formula-visual-source formula)))))

  (struct test-formula-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (formula-visual? visual))
     (define (pict-renderer-render _renderer visual _camera)
       (filled-rectangle
        (formula-width visual)
        18
        #:color (formula-color visual)
        #:border-color "black"
        #:border-width 1))])

  ;; test-formula-renderer replaces external LaTeX with fixed colored Picts.

  ; formula-renderers : (listof pict-renderer?)
  ;;   Gives the deterministic formula renderer before built-in renderers.
  (define formula-renderers
    (cons (test-formula-renderer)
          default-pict-renderers))

  ; make-part : symbol? string? real? -> formula-part?
  ;;   Creates one test formula part at local x.
  (define (make-part name source x)
    (latex-formula-part source
                        #:name name
                        #:center (vec2 x 0)
                        #:mode 'inline
                        #:font-size 1/3))

  ; source-parts : (listof formula-part?)
  ;;   Gives the rendered source equation.
  (define source-parts
    (list (make-part 'left "a" -2)
          (make-part 'operator "+" 0)
          (make-part 'right "c" 2)))

  ; destination-parts : (listof formula-part?)
  ;;   Gives moved terms and a changed operator.
  (define destination-parts
    (list (make-part 'right "c" -2)
          (make-part 'operator-destination "-" 0)
          (make-part 'left "a" 2)))

  ; source : formula-assembly-visual?
  ;;   Gives the source assembly rendered in the scene.
  (define source
    (formula-assembly source-parts #:id 'equation))

  ; destination : formula-assembly-visual?
  ;;   Gives the destination layout template.
  (define destination
    (formula-assembly destination-parts #:id 'destination-template))

  ; correspondence : formula-correspondence?
  ;;   Matches moving terms and cross-fades the changed operator.
  (define correspondence
    (formula-correspondence
     source
     destination
     (list (formula-part-match 'left 'left)
           (formula-part-match 'operator 'operator-destination)
           (formula-part-match 'right 'right))))

  ; animation : scene?
  ;;   Gives a two-second formula transformation and endpoint hold.
  (define animation
    (scene-wait
     (scene-play (scene-add (make-scene) source)
                 (transform-formula-parts correspondence)
                 #:duration 2)
     1/4))

  ; assembly-at : nonnegative-real? -> formula-assembly-visual?
  ;;   Returns the formula assembly sampled at time.
  (define (assembly-at time)
    (scene-state-ref (scene-sample animation time) 'equation))

  ; source-pict : pict?
  ;;   Gives the exact local source Pict at progress zero.
  (define source-pict
    (visual->pict (assembly-at 0)
                  test-camera
                  #:renderers formula-renderers))

  ; midpoint-pict : pict?
  ;;   Gives local moving and cross-fading interior transition layers.
  (define midpoint-pict
    (visual->pict (assembly-at 1)
                  test-camera
                  #:renderers formula-renderers))

  ; endpoint-pict : pict?
  ;;   Gives exact local destination parts under the stable source identity.
  (define endpoint-pict
    (visual->pict (assembly-at 2)
                  test-camera
                  #:renderers formula-renderers))

  ;; At the midpoint, all matched test parts occupy the same local x position.
  ;; The source and destination span a wider interval.
  (check-true (> (pict-width source-pict)
                 (pict-width midpoint-pict)))
  (check-true (> (pict-width endpoint-pict)
                 (pict-width midpoint-pict)))
  (check-equal? (pict-height source-pict) 18)
  (check-equal? (pict-height midpoint-pict) 18)
  (check-equal? (pict-height endpoint-pict) 18)

  ;; Exact endpoint rendering agrees with a static assembly containing the
  ;; destination parts under the original top-level identity.
  ; expected-endpoint : formula-assembly-visual?
  ;;   Gives the static semantic value expected after completion.
  (define expected-endpoint
    (formula-assembly destination-parts #:id 'equation))

  ; expected-endpoint-pict : pict?
  ;;   Gives the local Pict for the static expected endpoint.
  (define expected-endpoint-pict
    (visual->pict expected-endpoint
                  test-camera
                  #:renderers formula-renderers))

  (check-equal? (pict-width endpoint-pict)
                (pict-width expected-endpoint-pict))
  (check-equal? (pict-height endpoint-pict)
                (pict-height expected-endpoint-pict))

  ; temporary-root : path?
  ;;   Gives the isolated directory root for PNG comparisons.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-o~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; render-one-frame! : scene? path-string? -> bytes?
      ;;   Renders one quarter-second frame and returns its PNG bytes.
      (define (render-one-frame! scene directory)
        (define frame-paths
          (render-frames! scene
                          directory
                          #:fps 4
                          #:camera test-camera
                          #:renderers formula-renderers))
        (check-equal? (length frame-paths) 1)
        (file->bytes (car frame-paths)))

      ; source-bytes : bytes?
      ;;   Gives one static source frame.
      (define source-bytes
        (render-one-frame!
         (scene-wait (scene-add (make-scene) source) 1/4)
         (build-path temporary-root "source")))

      ; midpoint-bytes : bytes?
      ;;   Gives one static frame of the sampled transition midpoint.
      (define midpoint-bytes
        (render-one-frame!
         (scene-wait
          (make-scene (scene-sample animation 1))
          1/4)
         (build-path temporary-root "midpoint")))

      ; endpoint-bytes : bytes?
      ;;   Gives one static frame of the exact completed state.
      (define endpoint-bytes
        (render-one-frame!
         (scene-wait
          (scene-add (make-scene) expected-endpoint)
          1/4)
         (build-path temporary-root "endpoint")))

      (check-false (equal? source-bytes midpoint-bytes))
      (check-false (equal? midpoint-bytes endpoint-bytes))
      (check-false (equal? source-bytes endpoint-bytes))

      ;; Rendering the complete animation yields chronological frame changes.
      ; frame-paths : (listof path?)
      ;;   Gives nine frames for two seconds plus a quarter-second hold.
      (define frame-paths
        (render-frames! animation
                        (build-path temporary-root "animation")
                        #:fps 4
                        #:camera test-camera
                        #:renderers formula-renderers))

      (check-equal? (length frame-paths) 9)
      (define first-frame-bytes
        (file->bytes (car frame-paths)))
      (define middle-frame-bytes
        (file->bytes (list-ref frame-paths 4)))
      (define final-frame-bytes
        (file->bytes (car (reverse frame-paths))))
      (check-equal? first-frame-bytes source-bytes)
      (check-false (equal? first-frame-bytes middle-frame-bytes))
      (check-false (equal? middle-frame-bytes final-frame-bytes))
      (check-equal? final-frame-bytes endpoint-bytes)

      ;; Repeated rendering with the same model and renderer list is exact.
      ; first-repeat : bytes?
      ;;   Gives the first deterministic midpoint rerender.
      (define first-repeat
        (render-one-frame!
         (scene-wait
          (make-scene (scene-sample animation 1))
          1/4)
         (build-path temporary-root "repeat-a")))

      ; second-repeat : bytes?
      ;;   Gives the second deterministic midpoint rerender.
      (define second-repeat
        (render-one-frame!
         (scene-wait
          (make-scene (scene-sample animation 1))
          1/4)
         (build-path temporary-root "repeat-b")))

      (check-equal? first-repeat second-repeat))
    (lambda ()
      (delete-directory/files temporary-root))))
