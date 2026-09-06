#lang racket/base

;;;
;;; Three-Dimensional Visual Probes
;;;

;; Produces compact, stage-specific visual evidence for the 3D implementation.
;; A probe owns an ordinary immutable Scene and selected sample times; all
;; filesystem output is confined to this tool. The resulting rktd manifests
;; make a rendered image useful for later diagnosis without treating it as the
;; sole semantic test oracle.


;;;
;;; Imports and Exports
;;;

(require (only-in file/sha1 bytes->hex-string sha1-bytes)
         (only-in pict pict->bitmap)
         racket/class
         racket/cmdline
         racket/draw
         racket/file
         racket/list
         racket/path
         (only-in racket/port call-with-output-bytes)
         racket/runtime-path
         racket/string
         "../3d.rkt"
         "../3d/render.rkt"
         "../main.rkt"
         "../version.rkt")

(provide (struct-out probe3d)
         known-3d-probe-stages
         stage->probes
         write-3d-probes!
         compare-3d-probes!)


;;;
;;; Probe Description
;;;

(struct probe3d (id title scene times notes)
  #:transparent)

;; probe3d describes one stage-level visual probe.
;;  - id     symbol?               stable output-directory component.
;;  - title  immutable-string?     human-readable purpose.
;;  - scene  scene?                immutable authored scene to sample.
;;  - times  (listof nonnegative-real?) exact requested sample times.
;;  - notes  immutable-string?     the property a human should inspect.

(define-runtime-path repository-root "..")

; known-3d-probe-stages : -> (listof symbol?)
;;   Lists every visual 3D stage whose canonical example has probe coverage.
(define known-3d-probe-stages
  '(SCENE-3D-B SCENE-3D-C SCENE-3D-D SCENE-3D-E SCENE-3D-F SCENE-3D-G
    SCENE-3D-H SCENE-3D-I SCENE-3D-J SCENE-3D-K SCENE-3D-L SCENE-3D-M
    SCENE-3D-N SCENE-3D-O SCENE-3D-P))

(define stage-example-specifications
  ;; A binding is dynamically required only for the requested stage. This
  ;; keeps a core wireframe run independent of unrelated optional tooling and
  ;; makes the catalogue's examples the single source of rendered probes.
  (hash
   'SCENE-3D-B
   (list (list 'wireframe-cube "Perspective wireframe cube"
               "examples/3d/wireframe-cube.rkt" 'make-demo-scene
               '(0 1 4) "Perspective projection, clipping, and 2D overlays."))
   'SCENE-3D-C
   (list (list 'opaque-cube "Opaque depth-tested cube"
               "examples/3d/opaque-cube.rkt" 'make-demo-scene
               '(0 2 4) "Opaque depth, clipping, culling, and flat lighting.")
         (list 'depth-test "Order-independent opaque depth"
               "examples/3d/depth-test.rkt" 'make-depth-test-scene
               '(0 2) "Nearer geometry wins regardless of declaration order."))
   'SCENE-3D-D
   (list (list 'camera-orbit "Spatial cube and camera orbit"
               "examples/3d/camera-orbit.rkt" 'make-demo-scene
               '(0 5/2 5) "Camera and object animation agree at exact endpoints."))
   'SCENE-3D-E
   (list (list 'projected-labels "Spatial relations and projected labels"
               "examples/3d/projected-labels.rkt" 'make-demo-scene
               '(0 3 6) "Derived spatial relations and projected 2D labels."))
   'SCENE-3D-F
   (list (list 'vector-components "Spatial vector components"
               "examples/3d/vector-components.rkt" 'make-demo-scene
               '(0 5/2 5) "Curves, tubes, axes, arrows, and projected labels."))
   'SCENE-3D-G
   (list (list 'tangent-plane "Saddle surface and tangent plane"
               "examples/3d/tangent-plane.rkt" 'make-demo-scene
               '(0 3 5) "Surface sampling, normals, colours, and tangent plane."))
   'SCENE-3D-H
   (list (list 'solid-of-revolution "Solid of revolution"
               "examples/3d/solid-of-revolution.rkt" 'make-demo-scene
               '(0 3 5) "Solid construction and depth-tested surface topology."))
   'SCENE-3D-I
   (list (list 'sphere-plane-section "Sphere cut by a moving plane"
               "examples/3d/sphere-plane-section.rkt" 'make-demo-scene
               '(0 5/2 5) "Clipping, section curves, labels, and transparency."))
   'SCENE-3D-J
   (list (list 'spatial-maps-and-homotopies "Spatial maps and homotopies"
               "examples/3d/spatial-maps-and-homotopies.rkt" 'make-demo-scene
               '(0 5/2 5) "Pointwise maps and homotopy endpoint semantics."))
   'SCENE-3D-K
   (list (list 'prepared-lorenz-flow "Prepared Lorenz flow"
               "examples/3d/prepared-lorenz-flow.rkt" 'make-demo-scene
               '(0 3 6) "Prepared ODE trajectories and camera-independent samples."))
   'SCENE-3D-L
   (list (list 'spatial-inspector-picking "Exact spatial picking"
               "examples/3d/spatial-inspector-picking.rkt" 'make-demo-scene
               '(0 5/2 5) "Visible geometry for inspection and exact ray picking."))
   'SCENE-3D-M
   (list (list 'retained-renderer "Retained 3D renderer protocol"
               "examples/3d/retained-renderer.rkt" 'make-demo-scene
               '(0 5/2 5) "Retained preparation with independent fresh frames."))
   'SCENE-3D-N
   (list (list 'mesh-diagnostics "Compiled mesh diagnostics"
               "examples/3d/mesh-diagnostics.rkt" 'make-demo-scene
               '(0 5/2 5)
               "Dense closed surface, camera orbit, and shared geometry instances."))
   'SCENE-3D-O
   (list (list 'hidden-line-tetrahedron "Depth-aware tetrahedron outline"
               "examples/3d/hidden-line-tetrahedron.rkt" 'make-demo-scene
               '(0 5/2 5)
               "Visible solid edges, dashed hidden edges, and a camera-dependent feature set.")
         (list 'feature-edge-modes "Feature and silhouette edge modes"
               "examples/3d/feature-edge-modes.rkt" 'make-demo-scene
               '(0 5/2 5)
               "All, feature, and silhouette edge selections remain deterministic during an orbit.")
         (list 'screen-space-axes "Screen-space mathematical axes"
               "examples/3d/screen-space-axes.rkt" 'make-demo-scene
               '(0 5/2 5)
               "Constant-pixel axes, points, and arrowheads during a camera dolly.")
         (list 'screen-world-strokes "Screen and world stroke width"
               "examples/3d/screen-world-strokes.rkt" 'make-demo-scene
               '(0 5/2 5)
               "A screen stroke stays pixel-constant while an explicit world stroke changes apparent size.")
         (list 'stroke-gallery "Cap, join, and dash gallery"
               "examples/3d/stroke-gallery.rkt" 'make-demo-scene
               '(0)
               "Round, square, and butt caps; miter, bevel, and round joins; and dash phase.")
         (list 'arrow-dolly "Screen-space arrowhead during dolly"
               "examples/3d/arrow-dolly.rkt" 'make-demo-scene
               '(0 5/2 5)
               "The shaft and arrowhead retain distinct mathematical screen semantics.")
         (list 'near-plane-stroke "Near-plane stroke clipping"
               "examples/3d/near-plane-stroke.rkt" 'make-demo-scene
               '(0)
               "Near-plane clipping retains finite projected geometry and source progress.")
         (list 'stroke-picking "Stroke, point, and arrow picking"
               "examples/3d/stroke-picking.rkt" 'make-demo-scene
               '(0)
               "Preview-oriented picking surface for screen-space primitives."))
   'SCENE-3D-P
   (list (list 'opengl-opaque-cube "Retained Racket/OpenGL cube"
               "examples/3d/opengl-opaque-cube.rkt" 'make-demo-scene
               '(0 5/2 5)
               "Offscreen OpenGL FBO readback, retained mesh geometry, and ordinary 2D composition.")
         (list 'smooth-coloured-saddle "Smooth coloured saddle"
               "examples/3d/tangent-plane.rkt" 'make-demo-scene
               '(3)
               "Smooth normals and interpolated material colour on a sampled surface.")
         (list 'hidden-line-tetrahedron "Hidden-line tetrahedron"
               "examples/3d/hidden-line-tetrahedron.rkt" 'make-demo-scene
               '(0)
               "Depth-tested visible and hidden screen-space mathematical strokes.")
         (list 'screen-space-axes "Axes during a camera dolly"
               "examples/3d/screen-space-axes.rkt" 'make-demo-scene
               '(0 5)
               "Screen-sized shafts, ticks, point markers, and arrowheads remain legible.")
         (list 'clip-plane-sphere "Clip-plane sphere"
               "examples/3d/sphere-plane-section.rkt" 'make-demo-scene
               '(0)
               "Clip-plane discard agrees with the existing spatial material semantics.")
         (list 'transparent-section "Transparent sphere and plane section"
               "examples/3d/sphere-plane-section.rkt" 'make-demo-scene
               '(0)
               "CPU-stable far-to-near transparent ordering is retained by the OpenGL pass.")
         (list 'surface-camera-orbit "Static surface under camera orbit"
               "examples/3d/mesh-diagnostics.rkt" 'make-demo-scene
               '(0 5)
               "Camera-only motion should reuse retained geometry rather than upload it again.")
         (list 'two-viewports "Two spatial viewports"
               "examples/3d/opengl-two-viewports.rkt" 'make-demo-scene
               '(0)
               "Two ordinary 2D placements independently request the same retained OpenGL backend.")
         (list 'lorenz-curve "Lorenz curve and particle"
               "examples/3d/prepared-lorenz-flow.rkt" 'make-demo-scene
               '(0 3)
               "Prepared ODE geometry remains an immutable input to the backend.")
         (list 'context-restart-repeat "Context restart repeat frame"
               "examples/3d/opengl-opaque-cube.rkt" 'make-demo-scene
               '(0)
               "The companion real-context test releases and recreates the renderer, then compares this frame."))))

; stage->probes : symbol? -> (listof probe3d?)
;;   Instantiates the canonical visual probes registered for one 3D stage.
(define (stage->probes stage)
  (unless (member stage known-3d-probe-stages)
    (raise-arguments-error 'stage->probes
                           "a supported visual 3D stage"
                           "stage" stage
                           "supported-stages" known-3d-probe-stages))
  (for/list ([specification (in-list (hash-ref stage-example-specifications stage))])
    (define id (list-ref specification 0))
    (define title (list-ref specification 1))
    (define source (list-ref specification 2))
    (define binding (list-ref specification 3))
    (define times (list-ref specification 4))
    (define notes (list-ref specification 5))
    (define make-scene
      (dynamic-require (build-path repository-root source) binding))
    (unless (procedure? make-scene)
      (raise-arguments-error 'stage->probes
                             "a canonical example constructor procedure"
                             "stage" stage
                             "source" source
                             "binding" binding
                             "value" make-scene))
    (define scn (make-scene))
    (unless (scene? scn)
      (raise-arguments-error 'stage->probes
                             "a canonical example constructor returning scene?"
                             "stage" stage
                             "source" source
                             "binding" binding
                             "value" scn))
    (probe3d id title scn times notes)))


;;;
;;; Rendering and Evidence
;;;

; write-3d-probes! : symbol? path-string? [#:width exact-positive-integer?]
;                    [#:height exact-positive-integer?]
;                    [#:renderer (or/c 'software 'opengl)]
;                    [#:compare-renderers (or/c #f '(software opengl))]
;                    -> path?
;;   Renders a stage's canonical probes and writes its manifest beneath output.
(define (write-3d-probes/single! stage output-directory
                                  #:width [width 640]
                                  #:height [height 360]
                                  #:renderer [renderer-selection 'software])
  (unless (member stage known-3d-probe-stages)
    (raise-arguments-error 'write-3d-probes!
                           "a supported visual 3D stage"
                           "stage" stage
                           "supported-stages" known-3d-probe-stages))
  (unless (path-string? output-directory)
    (raise-argument-error 'write-3d-probes! "path-string?" output-directory))
  (unless (exact-positive-integer? width)
    (raise-argument-error 'write-3d-probes! "exact-positive-integer?" width))
  (unless (exact-positive-integer? height)
    (raise-argument-error 'write-3d-probes! "exact-positive-integer?" height))
  (unless (memq renderer-selection '(software opengl))
    (raise-argument-error 'write-3d-probes! "'software or 'opengl" renderer-selection))
  (define-values (renderer release renderer-info renderer-statistics)
    (case renderer-selection
      [(software) (values (current-view3d-renderer3d) void #f #f)]
      [else
       ;; This dynamic boundary keeps ordinary probe runs and `animate/3d`
       ;; free of racket/gui/base and the optional OpenGL package.
       (define module-path (build-path repository-root "3d" "opengl.rkt"))
       (define make-spec (dynamic-require module-path 'opengl-renderer3d-spec))
       (define make-renderer (dynamic-require module-path 'opengl-renderer3d))
       (define info (dynamic-require module-path 'opengl-renderer3d-info))
       (define statistics (dynamic-require module-path 'opengl-renderer3d-statistics))
       (define release! (dynamic-require module-path 'opengl-renderer3d-release!))
       (define selected (make-renderer (make-spec #:fallback 'error)))
       (values selected release! info statistics)]))
  (define destination
    (simplify-path (path->complete-path output-directory)))
  (make-directory* destination)
  (dynamic-wind
   void
   (lambda ()
     (parameterize ([current-view3d-renderer3d renderer])
       (define probes (stage->probes stage))
       (define probe-manifests
         (for/list ([probe (in-list probes)] [probe-index (in-naturals 1)])
           (write-one-probe! probe probe-index destination width height)))
       (define manifest
         (hasheq 'animate-version animate-version
                 'animate-stage animate-stage
                 'requested-stage stage
                 'racket-version (version)
                 'renderer-id (renderer3d-id renderer)
                 'renderer-info (and renderer-info (renderer-info renderer))
                 'renderer-statistics (and renderer-statistics (renderer-statistics renderer))
                 'output-dimensions (vector width height)
                 'probes probe-manifests
                 'warnings
                 (if (eq? renderer-selection 'opengl)
                     (list "OpenGL pixels are compared with the software reference by tolerance, not by bit identity.")
                     (list "Visual probes are review evidence; semantic and raster tests remain authoritative."
                           "The retained software backend is deterministic but not GPU accelerated."))))
       (write-rktd! (build-path destination "manifest.rktd") manifest)))
   (lambda () (release renderer)))
  destination)

;; `--compare-renderers` deliberately produces two independently inspectable
;; render trees.  The difference image is diagnostic evidence, not a claim of
;; bit identity: edge antialiasing and floating-point interpolation legitimately
;; differ between the software reference and OpenGL.
(define (compare-3d-probes! stage output-directory
                            #:width [width 640]
                            #:height [height 360])
  (define destination
    (simplify-path (path->complete-path output-directory)))
  (define software-directory (build-path destination "software"))
  (define opengl-directory (build-path destination "opengl"))
  (write-3d-probes/single! stage software-directory
                            #:width width #:height height #:renderer 'software)
  (write-3d-probes/single! stage opengl-directory
                            #:width width #:height height #:renderer 'opengl)
  (define software-manifest
    (call-with-input-file (build-path software-directory "manifest.rktd") read))
  (define opengl-manifest
    (call-with-input-file (build-path opengl-directory "manifest.rktd") read))
  (define differences-directory (build-path destination "differences"))
  (make-directory* differences-directory)
  (define comparisons
    (for/list ([software-probe (in-list (hash-ref software-manifest 'probes))]
               [opengl-probe (in-list (hash-ref opengl-manifest 'probes))])
      (unless (eq? (hash-ref software-probe 'id) (hash-ref opengl-probe 'id))
        (error 'compare-3d-probes! "probe order differs between renderers"))
      (define probe-id (hash-ref software-probe 'id))
      (define probe-directory
        (build-path differences-directory (symbol->string probe-id)))
      (make-directory* probe-directory)
      (hasheq
       'id probe-id
       'frames
       (for/list ([software-frame (in-list (hash-ref software-probe 'frames))]
                  [opengl-frame (in-list (hash-ref opengl-probe 'frames))]
                  [frame-index (in-naturals)])
         (unless (= (hash-ref software-frame 'time) (hash-ref opengl-frame 'time))
           (error 'compare-3d-probes! "frame times differ between renderers"))
         (define difference-name
           (format "frame-~a-difference.png" (pad-number frame-index 3)))
         (define metrics
           (write-bitmap-difference!
            (build-path software-directory
                        (hash-ref software-probe 'directory)
                        (hash-ref software-frame 'file))
            (build-path opengl-directory
                        (hash-ref opengl-probe 'directory)
                        (hash-ref opengl-frame 'file))
            (build-path probe-directory difference-name)))
         (hash-set* metrics
                    'time (hash-ref software-frame 'time)
                    ;; An `.rktd` manifest must remain readable by `read`.
                    ;; Racket path values print as opaque `#<path:...>` data,
                    ;; so retain the relative pathname as a plain string.
                    'file (path->string
                           (build-path (symbol->string probe-id)
                                       difference-name)))))))
  (write-rktd!
   (build-path destination "comparison.rktd")
   (hasheq 'animate-version animate-version
           'animate-stage animate-stage
           'requested-stage stage
           'renderers '(software opengl)
           'comparison "absolute-ARGB-channel-difference"
           'notes
           (list "Software is the semantic reference."
                 "Use separate tolerances for opaque interiors, antialiased edges, and transparent regions."
                 "Each difference PNG brightens absolute per-channel disagreement.")
           'probes comparisons))
  destination)

(define (write-3d-probes! stage output-directory
                           #:width [width 640]
                           #:height [height 360]
                           #:renderer [renderer-selection 'software]
                           #:compare-renderers [compare-renderers #f])
  (cond
    [(not compare-renderers)
     (write-3d-probes/single! stage output-directory
                               #:width width #:height height
                               #:renderer renderer-selection)]
    [(equal? compare-renderers '(software opengl))
     (compare-3d-probes! stage output-directory #:width width #:height height)]
    [else
     (raise-argument-error
      'write-3d-probes!
      "#f or '(software opengl) as #:compare-renderers"
      compare-renderers)]))

(define (write-bitmap-difference! software-path opengl-path output-path)
  (define software (read-bitmap software-path))
  (define opengl (read-bitmap opengl-path))
  (define width (send software get-width))
  (define height (send software get-height))
  (unless (and (= width (send opengl get-width))
               (= height (send opengl get-height)))
    (raise-arguments-error
     'write-bitmap-difference!
     "same-sized software and OpenGL frames"
     "software" software-path
     "opengl" opengl-path))
  (define count (* width height))
  (define software-bytes (make-bytes (* 4 count)))
  (define opengl-bytes (make-bytes (* 4 count)))
  (send software get-argb-pixels 0 0 width height software-bytes)
  (send opengl get-argb-pixels 0 0 width height opengl-bytes)
  (define differences (make-bytes (* 4 count)))
  (define maximum 0)
  (define total 0)
  (define changed 0)
  (for ([offset (in-range 0 (* 4 count) 4)])
    (define pixel-changed? #f)
    (bytes-set! differences offset 255)
    (for ([channel (in-range 1 4)])
      (define difference
        (abs (- (bytes-ref software-bytes (+ offset channel))
                (bytes-ref opengl-bytes (+ offset channel)))))
      (bytes-set! differences (+ offset channel) difference)
      (set! maximum (max maximum difference))
      (set! total (+ total difference))
      (when (positive? difference) (set! pixel-changed? #t)))
    (when pixel-changed? (set! changed (add1 changed))))
  (define difference-bitmap (make-object bitmap% width height #t))
  (send difference-bitmap set-argb-pixels 0 0 width height differences)
  (unless (send difference-bitmap save-file output-path 'png)
    (error 'write-bitmap-difference! "could not write ~a" output-path))
  (hasheq 'pixel-count count
          'different-pixel-count changed
          'maximum-rgb-channel-difference maximum
          'mean-rgb-channel-difference (/ total (* 3 count))))

(define (write-one-probe! probe probe-index destination width height)
  (define probe-directory
    (build-path destination
                (format "probe-~a-~a" (pad-number probe-index 2)
                        (symbol->string (probe3d-id probe)))))
  (make-directory* probe-directory)
  (define frame-records
    (for/list ([time (in-list (probe3d-times probe))] [frame-index (in-naturals)])
      (define bitmap
        (pict->bitmap
         (scene->pict (probe3d-scene probe) time
                      #:camera (make-camera #:width width #:height height
                                            #:world-width 12))
         'smoothed))
      (define frame-name (format "frame-~a.png" (pad-number frame-index 3)))
      (define frame-path (build-path probe-directory frame-name))
      (unless (send bitmap save-file frame-path 'png)
        (error 'write-3d-probes! "could not write ~a" frame-path))
      (hasheq 'time time
              'file frame-name
              'sha1 (bitmap-sha1 bitmap)
              'cameras (sampled-view-cameras (probe3d-scene probe) time)
              'renderer-fingerprints
              (sampled-renderer-fingerprints (probe3d-scene probe) time width height))))
  (write-rktd!
   (build-path probe-directory "diagnostics.rktd")
   (hasheq 'id (probe3d-id probe)
           'title (probe3d-title probe)
           'notes (probe3d-notes probe)
           'sample-times (probe3d-times probe)
           'frames frame-records))
  (hasheq 'id (probe3d-id probe)
          'title (probe3d-title probe)
          'notes (probe3d-notes probe)
          'directory (path->string (file-name-from-path probe-directory))
          'frames frame-records))

(define (sampled-view-cameras scn time)
  (for/list ([visual (in-list
                      (scene-state-visuals-in-drawing-order
                       (scene-sample scn time)))]
             #:when (view3d? visual))
    (hasheq 'id (visual-id visual)
            'camera (view3d-camera visual)
            'render-mode (view3d-render-mode visual))))

(define (sampled-renderer-fingerprints scn time width height)
  (define renderer (current-view3d-renderer3d))
  (for/list ([visual (in-list
                      (scene-state-visuals-in-drawing-order
                       (scene-sample scn time)))]
             #:when (and (view3d? visual)
                         (eq? (view3d-render-mode visual) 'opaque)))
    (define request (view3d->render3d-request visual width height))
    (define compiled (render3d-request-compiled-view request))
    (hasheq 'view-id (visual-id visual)
            ;; A backend fingerprint can legitimately contain every frozen
            ;; mesh. Record a stable digest rather than embedding that entire
            ;; author tree into every diagnostics file.
            'fingerprint-sha1
            (fingerprint-sha1
             (renderer3d-fingerprint
              renderer
              request))
            'geometry-count (vector-length (compiled-view3d-geometries compiled))
            'instance-count (vector-length (compiled-view3d-instances compiled))
            'stroke-command-count (vector-length (compiled-view3d-strokes compiled))
            'point-marker-count (vector-length (compiled-view3d-point-markers compiled))
            'arrow-marker-count (vector-length (compiled-view3d-arrow-markers compiled))
            'edge-overlay-count (vector-length (compiled-view3d-edge-overlays compiled))
            'stroke-width-modes
            (for/list ([stroke (in-vector (compiled-view3d-strokes compiled))])
              (stroke3d-width-mode (compiled-stroke3d-style stroke)))
            'geometry-keys
            (for/list ([geometry (in-vector (compiled-view3d-geometries compiled))])
              (bytes->hex-string
               (geometry-key3d-digest (compiled-geometry3d-key geometry)))))))

(define (fingerprint-sha1 fingerprint)
  (bytes->hex-string
   (sha1-bytes
    (call-with-output-bytes
     (lambda (out) (write fingerprint out))))))

(define (bitmap-sha1 bitmap)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* 4 width height)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  (bytes->hex-string (sha1-bytes pixels)))

(define (write-rktd! path value)
  (call-with-output-file path
    (lambda (out)
      (write value out)
      (newline out))
    #:exists 'truncate/replace))

(define (pad-number value digits)
  (define text (number->string value))
  (string-append (make-string (max 0 (- digits (string-length text))) #\0) text))

(define (parse-stage text)
  (define upper (string-upcase text))
  (define candidate
    (string->symbol
    (if (regexp-match? #rx"^SCENE-3D-[A-P]$" upper)
         upper
         (string-append "SCENE-" upper))))
  (unless (member candidate known-3d-probe-stages)
    (raise-arguments-error 'run-3d-probes
                           "a supported visual 3D stage"
                           "stage" text
                           "supported-stages" known-3d-probe-stages))
  candidate)

(module+ main
  (define selected-stage #f)
  (define selected-output #f)
  (define selected-renderer 'software)
  (define compare-renderers #f)
  (command-line
   #:program "run-3d-probes.rkt"
   #:once-each
   ["--stage" stage-text
    "Stage to probe (for example, 3D-N)."
    (set! selected-stage (parse-stage stage-text))]
   ["--output" output-text
    "Destination directory (for example, rendered-examples/3d-m)."
    (set! selected-output output-text)]
   ["--renderer" renderer-text
   "Renderer: software (default) or explicit opengl."
    (define candidate (string->symbol (string-downcase renderer-text)))
    (unless (memq candidate '(software opengl))
      (raise-arguments-error 'run-3d-probes "'software or 'opengl" "renderer" renderer-text))
    (set! selected-renderer candidate)]
   ["--compare-renderers" renderer-list
    "Render software and OpenGL trees and write difference evidence. Use software,opengl."
    (unless (equal? (map (lambda (text) (string->symbol (string-downcase text)))
                         (string-split renderer-list ","))
                    '(software opengl))
      (raise-arguments-error
       'run-3d-probes
       "the exact renderer list software,opengl"
       "compare-renderers" renderer-list))
    (set! compare-renderers '(software opengl))])
  (unless selected-stage
    (raise-arguments-error 'run-3d-probes "the required --stage option"))
  (define default-output
    (build-path repository-root "rendered-examples"
                (string-downcase
                 (substring (symbol->string selected-stage)
                            (string-length "SCENE-")))))
  (define destination
    (write-3d-probes! selected-stage (or selected-output default-output)
                      #:renderer selected-renderer
                      #:compare-renderers compare-renderers))
  (printf "Wrote SCENE-3D probes with ~a to ~a\n"
          (if compare-renderers 'software+opengl selected-renderer)
          destination))
