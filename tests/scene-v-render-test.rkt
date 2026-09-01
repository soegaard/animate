#lang racket/base

;;;
;;; SCENE-V Point Marker, Scatter, and Area Rendering Tests
;;;

;; Tests marker fallback rendering, custom renderer precedence, filled-area
;; bounds, composite scatter rendering, timelines, and deterministic PNG output.


;;;
;;; Imports
;;;

(require racket/class
         racket/file
         rackunit
         (only-in pict
                  blank
                  cellophane
                  filled-rectangle
                  pict->bitmap
                  pict-height
                  pict-width)
         "../main.rkt")


(module+ test
  ; test-camera : camera?
  ;;   Gives a fixed camera with ten pixels per world unit.
  (define test-camera
    (make-camera #:width 300
                 #:height 180
                 #:world-width 30
                 #:background "white"))

  ; pict->argb-bytes : pict? -> bytes?
  ;;   Returns one Pict's rendered ARGB bytes for exact local comparisons.
  (define (pict->argb-bytes source)
    (define bitmap
      (pict->bitmap source))
    (define width
      (send bitmap get-width))
    (define height
      (send bitmap get-height))
    (define pixels
      (make-bytes (* width height 4)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    pixels)

  ; unit-axes : axes-visual?
  ;;   Gives four-by-four axes without tips or visible stroke padding.
  (define unit-axes
    (axes #:id 'unit-axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -2 2 1)
          #:x-length 4
          #:y-length 4
          #:stroke-width 0
          #:tick-size 0
          #:x-tip? #f
          #:y-tip? #f))

  ;; Built-in marker shapes render through existing semantic primitives.
  ; circle-marker : point-marker-visual?
  ;;   Gives a one-world-unit circle marker.
  (define circle-marker
    (point-marker #:id 'circle-marker
                  #:shape 'circle
                  #:size 1
                  #:stroke-width 0))

  ; square-marker : point-marker-visual?
  ;;   Gives a one-world-unit square marker.
  (define square-marker
    (point-marker #:id 'square-marker
                  #:shape 'square
                  #:size 1
                  #:stroke-width 0))

  ; diamond-marker : point-marker-visual?
  ;;   Gives a one-world-unit path-backed diamond marker.
  (define diamond-marker
    (point-marker #:id 'diamond-marker
                  #:shape 'diamond
                  #:size 1
                  #:stroke-width 0))

  ; circle-pict : pict?
  ;;   Gives the circular marker's local Pict.
  (define circle-pict
    (visual->pict circle-marker test-camera))

  ; square-pict : pict?
  ;;   Gives the square marker's local Pict.
  (define square-pict
    (visual->pict square-marker test-camera))

  ; diamond-pict : pict?
  ;;   Gives the path-backed marker's local Pict.
  (define diamond-pict
    (visual->pict diamond-marker test-camera))

  (check-equal? (pict-width circle-pict) 10)
  (check-equal? (pict-height circle-pict) 10)
  (check-equal? (pict-width square-pict) 10)
  (check-equal? (pict-height square-pict) 10)
  (check-true (positive? (pict-width diamond-pict)))
  (check-true (positive? (pict-height diamond-pict)))

  ;; A custom renderer can override the complete marker before fallback.
  (struct marker-override-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (point-marker-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       (blank 17 9))])

  ; overridden-pict : pict?
  ;;   Gives the custom renderer result for a point marker.
  (define overridden-pict
    (visual->pict circle-marker
                  test-camera
                  #:renderers
                  (cons (marker-override-renderer)
                        default-pict-renderers)))

  (check-equal? (pict-width overridden-pict) 17)
  (check-equal? (pict-height overridden-pict) 9)

  ;; Fallback opacity is applied once rather than once per semantic wrapper.
  (struct solid-path-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual)
       (path-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       (filled-rectangle 20 10
                         #:draw-border? #f
                         #:color "black"))])

  ; fallback-renderers : (listof pict-renderer?)
  ;;   Gives a deterministic renderer for number-line fallback path geometry.
  (define fallback-renderers
    (cons (solid-path-renderer)
          default-pict-renderers))

  ; opaque-number-line : number-line-visual?
  ;;   Gives the full-opacity source for the expected half-opacity result.
  (define opaque-number-line
    (number-line (axis-range -1 1 1)
                 #:id 'opaque-number-line
                 #:length 2
                 #:opacity 1))

  ; half-opacity-number-line : number-line-visual?
  ;;   Gives equivalent geometry with semantic opacity one half.
  (define half-opacity-number-line
    (number-line (axis-range -1 1 1)
                 #:id 'half-opacity-number-line
                 #:length 2
                 #:opacity 1/2))

  ; expected-half-opacity-pict : pict?
  ;;   Gives one explicit opacity application to the opaque fallback result.
  (define expected-half-opacity-pict
    (cellophane
     (visual->pict opaque-number-line
                   test-camera
                   #:renderers fallback-renderers)
     1/2))

  ; actual-half-opacity-pict : pict?
  ;;   Gives the number-line fallback result through the public adapter.
  (define actual-half-opacity-pict
    (visual->pict half-opacity-number-line
                  test-camera
                  #:renderers fallback-renderers))

  (check-equal? (pict->argb-bytes actual-half-opacity-pict)
                (pict->argb-bytes expected-half-opacity-pict))

  ;; A linear area over x = -2 through 2 has predictable symmetric bounds.
  ; filled-area : path-visual?
  ;;   Gives a triangle-like filled region above the zero baseline.
  (define filled-area
    (function-area unit-axes
                   (lambda (x) (/ (+ x 2) 2))
                   #:id 'filled-area
                   #:sample-count 3
                   #:clip? #f
                   #:opacity 1
                   #:stroke-width 0))

  ; filled-area-pict : pict?
  ;;   Gives the complete filled area Pict.
  (define filled-area-pict
    (visual->pict filled-area test-camera))

  ;; The anchor-centered path renderer uses the largest absolute extent
  ;; on each axis and adds one pixel of safety padding per side.
  (check-equal? (pict-width filled-area-pict) 42)
  (check-equal? (pict-height filled-area-pict) 42)

  ;; Scatter plots render recursively as ordered marker groups.
  ; scatter : group-visual?
  ;;   Gives three differently positioned diamond markers.
  (define scatter
    (scatter-plot unit-axes
                  (list (vec2 -1 -1)
                        origin
                        (vec2 1 1))
                  #:id 'scatter
                  #:shape 'diamond
                  #:size 2/5
                  #:stroke-width 0))

  ; scatter-pict : pict?
  ;;   Gives the recursively composed scatter Pict.
  (define scatter-pict
    (visual->pict scatter test-camera))

  (check-true (positive? (pict-width scatter-pict)))
  (check-true (positive? (pict-height scatter-pict)))

  ;; Filled areas, graphs, markers, and axes animate through existing requests.
  ; graph : path-visual?
  ;;   Gives a line over the filled region.
  (define graph
    (function-graph unit-axes
                    (lambda (x) (/ (+ x 2) 2))
                    #:id 'graph
                    #:sample-count 3
                    #:clip? #f
                    #:stroke "navy"
                    #:stroke-width 2))

  ; entrance : scene?
  ;;   Introduces the area, graph, scatter, and axes over one second.
  (define entrance
    (scene-play (make-scene)
                (fade-in filled-area)
                (create graph)
                (fade-in scatter)
                (fade-in unit-axes)
                #:duration 1))

  ; animation : scene?
  ;;   Holds the complete diagram for one further half second.
  (define animation
    (scene-wait entrance 1/2))

  (check-equal? (scene-frame-count animation #:fps 4) 6)

  ; start-pict : pict?
  ;;   Gives the first complete scene frame.
  (define start-pict
    (scene->pict animation 0 #:camera test-camera))

  ; end-pict : pict?
  ;;   Gives the structural endpoint after the entrance clip.
  (define end-pict
    (scene->pict animation 1 #:camera test-camera))

  (check-equal? (pict-width start-pict) 300)
  (check-equal? (pict-height start-pict) 180)
  (check-equal? (pict-width end-pict) 300)
  (check-equal? (pict-height end-pict) 180)

  ; temporary-root : path?
  ;;   Gives an isolated directory root for deterministic PNG comparisons.
  (define temporary-root
    (make-temporary-file "visual-animation-scene-v~a" 'directory))

  (dynamic-wind
    void
    (lambda ()
      ; first-paths : (listof path?)
      ;;   Gives the first complete rendering of the scene.
      (define first-paths
        (render-frames! animation
                        (build-path temporary-root "first")
                        #:fps 4
                        #:camera test-camera))

      ; second-paths : (listof path?)
      ;;   Gives the repeated rendering of the same semantic scene.
      (define second-paths
        (render-frames! animation
                        (build-path temporary-root "second")
                        #:fps 4
                        #:camera test-camera))

      (check-equal? (length first-paths) 6)
      (check-equal? (length second-paths) 6)
      (check-equal? (map file->bytes first-paths)
                    (map file->bytes second-paths))
      (check-false
       (equal? (file->bytes (car first-paths))
               (file->bytes (car (reverse first-paths))))))
    (lambda ()
      (delete-directory/files temporary-root))))
