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
         racket/file
         racket/list
         racket/path
         (only-in racket/port call-with-output-bytes)
         racket/runtime-path
         "../3d.rkt"
         "../3d/render.rkt"
         "../main.rkt"
         "../version.rkt")

(provide (struct-out probe3d)
         known-3d-probe-stages
         stage->probes
         write-3d-probes!)


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
    SCENE-3D-H SCENE-3D-I SCENE-3D-J SCENE-3D-K SCENE-3D-L SCENE-3D-M))

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
               '(0 5/2 5) "Retained preparation with independent fresh frames."))))

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
;                    -> path?
;;   Renders a stage's canonical probes and writes its manifest beneath output.
(define (write-3d-probes! stage output-directory
                           #:width [width 640]
                           #:height [height 360])
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
  (define destination
    (simplify-path (path->complete-path output-directory)))
  (make-directory* destination)
  (define probes (stage->probes stage))
  (define probe-manifests
    (for/list ([probe (in-list probes)] [probe-index (in-naturals 1)])
      (write-one-probe! probe probe-index destination width height)))
  (define manifest
    (hasheq 'animate-version animate-version
            'animate-stage animate-stage
            'requested-stage stage
            'racket-version (version)
            'renderer-id (renderer3d-id (current-view3d-renderer3d))
            'output-dimensions (vector width height)
            'probes probe-manifests
            'warnings
            (list "Visual probes are review evidence; semantic and raster tests remain authoritative."
                  "The retained software backend is deterministic but not GPU accelerated.")))
  (write-rktd! (build-path destination "manifest.rktd") manifest)
  destination)

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
    (hasheq 'view-id (visual-id visual)
            ;; A backend fingerprint can legitimately contain every frozen
            ;; mesh. Record a stable digest rather than embedding that entire
            ;; author tree into every diagnostics file.
            'fingerprint-sha1
            (fingerprint-sha1
             (renderer3d-fingerprint
              renderer
              (render3d-request visual width height #f))))))

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
     (if (regexp-match? #rx"^SCENE-3D-[A-M]$" upper)
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
  (command-line
   #:program "run-3d-probes.rkt"
   #:once-each
   ["--stage" stage-text
    "Stage to probe (for example, 3D-M)."
    (set! selected-stage (parse-stage stage-text))]
   ["--output" output-text
    "Destination directory (for example, rendered-examples/3d-m)."
    (set! selected-output output-text)])
  (unless selected-stage
    (raise-arguments-error 'run-3d-probes "the required --stage option"))
  (define default-output
    (build-path repository-root "rendered-examples"
                (string-downcase
                 (substring (symbol->string selected-stage)
                            (string-length "SCENE-")))))
  (define destination
    (write-3d-probes! selected-stage (or selected-output default-output)))
  (printf "Wrote SCENE-3D probes to ~a\n" destination))
