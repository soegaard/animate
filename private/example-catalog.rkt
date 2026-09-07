#lang racket/base

;;;
;;; Executable Example Catalogue
;;;

;; One immutable catalogue declares the canonical examples used by the guide,
;; smoke tests, gallery links, and optional thumbnail generation. It has no
;; renderer or GUI dependency.


;;;
;;; Imports and Exports
;;;

(require racket/list
         racket/string)

(provide (struct-out example-entry)
         canonical-example-catalog
         example-entry-by-id
         example-entry->markdown-link
         example-catalog->readme-section)


;;;
;;; Catalogue Values
;;;

(struct example-entry
  (id title source binding categories requirements thumbnail-time expected-duration)
  #:transparent)

;; example-entry declares one maintained author-facing example.
;;  - id                symbol?                 stable catalogue identifier.
;;  - title             immutable-string?       gallery-facing title.
;;  - source            immutable-string?       repository-relative source path.
;;  - binding           symbol?                  exported scene/program binding.
;;  - categories        (listof symbol?)         topical classification.
;;  - requirements      (listof symbol?)         external-run requirements.
;;  - thumbnail-time    nonnegative-real?        representative scene time.
;;  - expected-duration positive-real?           expected scene duration.

(define canonical-example-catalog
  (list
   (example-entry
    'basic-scene "A moving circle" "examples/parallel-animation-groups.rkt"
    'make-demo-scene '(basics animation) '(core) 1 5)
   (example-entry
    'animation-composition "Composed parallel animation"
    "examples/parallel-animation-groups.rkt" 'make-demo-scene
    '(animation composition) '(core) 2 5)
   (example-entry
    'source-formula "Source-addressed formula matching"
    "examples/transform-matching-strings.rkt" 'make-demo-scene
    '(formula source-selection) '(core latex dvisvgm) 2 6)
   (example-entry
    'formula-derivation "Structured formula derivation"
    "examples/structured-formula-derivation.rkt" 'make-demo-scene
    '(formula derivation) '(core latex dvisvgm) 2 7)
   (example-entry
    'relations "First-class relations"
    "examples/relation-visuals.rkt" 'make-demo-scene
    '(relations geometry) '(core) 2 6)
   (example-entry
    'adaptive-plot "Adaptive function plot"
    "examples/function-graphs.rkt" 'make-demo-scene
    '(plotting adaptive) '(core) 2 6)
   (example-entry
    'ode-flow "Adaptive ODE trajectory"
    "examples/adaptive-ode-trajectory.rkt" 'make-demo-scene
    '(ode flow) '(core) 3 7)
   (example-entry
    'source-block-reload "Source-block hot reload"
    "examples/source-block-hot-reload.rkt" 'hot-reload-demo
    '(authoring preview) '(core gui) 1 4)
   (example-entry
    'semantic-inspector "Semantic inspector"
    "examples/semantic-inspector.rkt" 'semantic-inspector-demo
    '(preview inspector formula relations) '(core latex dvisvgm gui) 2 5)
   (example-entry
    'authored-media "Authored audio and video"
    "examples/authored-media-assembly.rkt" 'make-demo-scene
    '(rendering audio subtitles) '(core ffmpeg) 1 4)
   (example-entry
   'wireframe-cube "Perspective wireframe cube"
    "examples/3d/wireframe-cube.rkt" 'make-demo-scene
    '(3d wireframe camera) '(core latex dvisvgm) 1 4)
   (example-entry
   'opaque-cube "Opaque depth-tested cube"
    "examples/3d/opaque-cube.rkt" 'make-demo-scene
    '(3d opaque depth lighting) '(core) 1 4)
   (example-entry
   'camera-orbit "Spatial cube and camera orbit"
    "examples/3d/camera-orbit.rkt" 'make-demo-scene
    '(3d animation camera source-selection) '(core latex dvisvgm) 5/2 5)
   (example-entry
    'cube-net-hinge-rotations "Cube net hinge rotations"
    "examples/3d/fold-unfold-polyhedron.rkt" 'make-demo-scene
    '(3d topology polyhedron nets animation) '(core) 3 6)
   (example-entry
    'projected-labels "Spatial relations and projected labels"
    "examples/3d/projected-labels.rkt" 'make-demo-scene
    '(3d relations projected-labels camera animation) '(core latex dvisvgm) 3 6)
   (example-entry
   'vector-components "Spatial vector components"
    "examples/3d/vector-components.rkt" 'make-demo-scene
    '(3d curves tubes axes vectors camera animation) '(core) 5/2 5)
   (example-entry
   'tangent-plane "Saddle surface and tangent plane"
    "examples/3d/tangent-plane.rkt" 'make-demo-scene
    '(3d surfaces calculus normals color camera animation) '(core) 3 5)
   (example-entry
   'solid-of-revolution "Solid of revolution"
    "examples/3d/solid-of-revolution.rkt" 'make-demo-scene
    '(3d solids revolution calculus camera animation) '(core) 3 5)
   (example-entry
   'sphere-plane-section "Sphere cut by a moving plane"
    "examples/3d/sphere-plane-section.rkt" 'make-demo-scene
    '(3d clipping sections transparency occlusion animation) '(core) 5/2 5)
   (example-entry
    'spatial-maps-and-homotopies "Spatial maps and homotopies"
    "examples/3d/spatial-maps-and-homotopies.rkt" 'make-demo-scene
    '(3d affine pointwise homotopy animation) '(core) 5/2 5)
   (example-entry
   'prepared-lorenz-flow "Prepared Lorenz flow"
    "examples/3d/prepared-lorenz-flow.rkt" 'make-demo-scene
    '(3d ode vector-fields trajectories camera animation) '(core) 3 6)
   (example-entry
   'lorenz-events "Lorenz event crossings"
    "examples/3d/lorenz-events.rkt" 'make-demo-scene
    '(3d ode lorenz events dense-roots trajectories camera animation) '(core) 3 6)
   (example-entry
   'event-aware-trajectory "Event-aware trajectory"
    "examples/3d/event-aware-trajectory.rkt" 'make-demo-scene
    '(3d ode events terminal-roots trajectories camera animation) '(core) 5/2 5)
   (example-entry
   'trajectory-termination "Trajectory termination policies"
    "examples/3d/trajectory-termination.rkt" 'make-demo-scene
    '(3d ode termination bounds arc-length events trajectories camera animation) '(core) 5/2 5)
   (example-entry
    'adaptive-streamlines "Prepared adaptive streamlines"
    "examples/3d/adaptive-streamlines.rkt" 'make-demo-scene
    '(3d ode streamlines adaptive arc-length trajectories camera animation) '(core) 5/2 5)
   (example-entry
    'deterministic-seed-sets "Deterministic streamline seed sets"
    "examples/3d/deterministic-seed-sets.rkt" 'make-demo-scene
    '(3d ode streamlines seed-sets poisson deterministic camera animation) '(core) 5/2 5)
   (example-entry
   'poincare-section "Dense Poincare section crossings"
    "examples/3d/poincare-section.rkt" 'make-demo-scene
    '(3d ode poincare events trajectories crossings camera animation) '(core) 5/2 5)
   (example-entry
    'equilibrium-linearization "Saddle equilibrium linearization"
    "examples/3d/equilibrium-linearization.rkt" 'make-demo-scene
    '(3d ode equilibria jacobian eigensystem linearization camera animation) '(core) 5/2 5)
   (example-entry
    'flow-map-volume "Prepared flow-map volume cell"
    "examples/3d/flow-map-volume.rkt" 'make-demo-scene
    '(3d ode flow-map trajectories volume deformation camera animation) '(core) 5/2 5)
   (example-entry
   'spatial-inspector-picking "Exact spatial picking"
    "examples/3d/spatial-inspector-picking.rkt" 'make-demo-scene
    '(3d preview inspection picking bvh camera) '(core gui) 5/2 5)
   (example-entry
    'retained-renderer "Retained 3D renderer protocol"
    "examples/3d/retained-renderer.rkt" 'make-demo-scene
    '(3d rendering retained conformance camera) '(core) 5/2 5)
   (example-entry
    'mesh-diagnostics "Compiled mesh diagnostics"
    "examples/3d/mesh-diagnostics.rkt" 'make-demo-scene
    '(3d topology diagnostics compilation cache camera) '(core) 5/2 5)
   (example-entry
    'hidden-line-tetrahedron "Depth-aware tetrahedron outline"
    "examples/3d/hidden-line-tetrahedron.rkt" 'make-demo-scene
    '(3d strokes hidden-lines feature-edges silhouettes) '(core) 5/2 5)
   (example-entry
   'screen-space-axes "Screen-space mathematical axes"
    "examples/3d/screen-space-axes.rkt" 'make-demo-scene
    '(3d strokes axes arrowheads screen-space camera) '(core) 5/2 5)
   (example-entry
    'feature-edge-modes "Feature and silhouette edge modes"
    "examples/3d/feature-edge-modes.rkt" 'make-demo-scene
    '(3d strokes feature-edges silhouettes hidden-lines camera) '(core) 5/2 5)
   (example-entry
    'screen-world-strokes "Screen and world stroke width"
    "examples/3d/screen-world-strokes.rkt" 'make-demo-scene
    '(3d strokes screen-space world-space camera) '(core) 5/2 5)
   (example-entry
    'stroke-gallery "Cap, join, and dash gallery"
    "examples/3d/stroke-gallery.rkt" 'make-demo-scene
    '(3d strokes caps joins dashes) '(core) 0 1)
   (example-entry
    'arrow-dolly "Screen-space arrowhead during dolly"
    "examples/3d/arrow-dolly.rkt" 'make-demo-scene
    '(3d strokes arrowheads screen-space camera) '(core) 5/2 5)
   (example-entry
    'near-plane-stroke "Near-plane stroke clipping"
    "examples/3d/near-plane-stroke.rkt" 'make-demo-scene
    '(3d strokes clipping near-plane) '(core) 0 1)
   (example-entry
   'stroke-picking "Stroke, point, and arrow picking"
    "examples/3d/stroke-picking.rkt" 'make-demo-scene
    '(3d strokes markers picking preview) '(core gui) 0 1)
   (example-entry
    'adaptive-trimmed-implicit-surfaces "Adaptive, trimmed, and implicit surfaces"
    "examples/3d/adaptive-trimmed-implicit-surfaces.rkt" 'make-demo-scene
    '(3d surfaces adaptive trimmed implicit provenance) '(core) 2 4)
   (example-entry
   'capped-cube-cutaway "Capped cube cutaway"
    "examples/3d/capped-cube-cutaway.rkt" 'make-demo-scene
    '(3d cutaway sections caps hatching volume clipping) '(core) 2 4)
   (example-entry
   'anchor-aware-labels "Anchor-aware projected labels"
    "examples/3d/anchor-aware-labels.rkt" 'make-demo-scene
    '(3d anchors projected-labels layout prepared-layout camera) '(core) 2 4)
   (example-entry
    'spatial-annotations "Fixed spatial annotations"
    "examples/3d/spatial-annotations.rkt" 'make-demo-scene
    '(3d annotations dimensions angles normals axes camera) '(core) 2 4)
   (example-entry
    'textured-billboards "Depth-tested textured billboards"
    "examples/3d/textured-billboards.rkt" 'make-demo-scene
    '(3d billboards textures alpha depth camera) '(core) 2 4)
   (example-entry
    'opengl-opaque-cube "Retained Racket/OpenGL cube"
    "examples/3d/opengl-opaque-cube.rkt" 'make-demo-scene
    '(3d opengl retained framebuffer cache) '(core gui opengl) 5/2 5)
   (example-entry
    'opengl-two-viewports "OpenGL two spatial viewports"
    "examples/3d/opengl-two-viewports.rkt" 'make-demo-scene
    '(3d opengl viewports perspective orthographic) '(core gui opengl) 0 1)))


;;;
;;; Lookup and Presentation
;;;

; example-entry-by-id : symbol? -> (or/c example-entry? #f)
;;   Finds one canonical example, or #f when its identifier is not registered.
(define (example-entry-by-id id)
  (unless (symbol? id)
    (raise-argument-error 'example-entry-by-id "symbol?" id))
  (findf (lambda (entry) (eq? (example-entry-id entry) id))
         canonical-example-catalog))

; example-entry->markdown-link : example-entry? -> string?
;;   Formats the canonical relative-source link used by generated repositories.
(define (example-entry->markdown-link entry)
  (unless (example-entry? entry)
    (raise-argument-error
     'example-entry->markdown-link "example-entry?" entry))
  (format "[~a](~a)"
          (example-entry-title entry)
          (string-replace (example-entry-source entry) " " "%20")))

; example-catalog->readme-section : [listof example-entry?] -> string?
;;   Produces the canonical Markdown block embedded in README.md. Keeping the
;;   text generation here lets the repository check prove that README links,
;;   requirements, and the executable gallery all describe the same entries.
(define (example-catalog->readme-section [entries canonical-example-catalog])
  (unless (and (list? entries) (andmap example-entry? entries))
    (raise-argument-error
     'example-catalog->readme-section "list of example-entry?" entries))
  (string-append
   "## Canonical examples\n\n"
   (string-join
    (for/list ([entry (in-list entries)])
      (format "- ~a — ~a; requires ~a."
              (example-entry->markdown-link entry)
              (string-join
               (map symbol->string (example-entry-categories entry)) ", ")
              (string-join
               (map symbol->string (example-entry-requirements entry)) ", ")))
    "\n")
   "\n"))
