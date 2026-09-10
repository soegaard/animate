#lang racket/base

;;;
;;; Theme Cache Identity Tests
;;;

(require racket/list
         rackunit
         "../3d.rkt"
         "../authoring.rkt"
         "../colors.rkt"
         "../main.rkt"
         "../preview.rkt"
         "../private/3d/compiled-view3d.rkt"
         "../private/3d/opengl/geometry-pack.rkt"
         (only-in "../private/color-theme.rkt" color-theme-resolved-roles)
         "../private/render-color-context.rkt"
         "../private/section-renderer.rkt")

(module+ test
  (define warm
    (color-theme #:id 'cache-warm
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'cache-warm-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#d02020"))))
  (define cool
    (color-theme #:id 'cache-cool
                 #:extends animate-light-theme
                 #:palette (color-palette #:id 'cache-cool-palette
                                          #:extends animate-palette
                                          #:colors (hash 'aqua-c "#2060d0"))))
  (define timeline
    (make-authored-timeline
     (scene-wait
      (scene-add (make-scene) (circle #:id 'dot #:fill aqua-c #:stroke #f))
      1)
     #:sections (list (section 'only 0 1))))
  (define entry (timeline-section timeline 'only))
  (check-not-equal?
   (automatic-section-cache-key timeline entry #:fps 1 #:camera #f
                                #:renderers '() #:theme warm
                                #:asset-files '())
   (automatic-section-cache-key timeline entry #:fps 1 #:camera #f
                                #:renderers '() #:theme cool
                                #:asset-files '()))
  ;; A resolver-version bump partitions persistent artifacts even when the
  ;; immutable theme appearance data are exactly equal. Version 4 owns the
  ;; semantic interpretation of newly accepted named literal colors.
  (define resolver-4-context (make-render-color-context warm))
  (define resolver-3-context
    (render-color-context warm
                          (color-theme-resolved-roles warm)
                          (color-theme-fingerprint warm)
                          3))
  (check-equal? render-color-resolver-version 4)
  (check-equal? (render-color-context-appearance-fingerprint resolver-4-context)
                (render-color-context-appearance-fingerprint resolver-3-context))
  (define resolver-4-section-key
    (automatic-section-cache-key timeline entry #:fps 1 #:camera #f
                                 #:renderers '()
                                 #:color-context resolver-4-context
                                 #:asset-files '()))
  (define resolver-3-section-key
    (automatic-section-cache-key timeline entry #:fps 1 #:camera #f
                                 #:renderers '()
                                 #:color-context resolver-3-context
                                 #:asset-files '()))
  (check-not-equal? resolver-3-section-key resolver-4-section-key)
  (check-equal?
   resolver-4-section-key
   (automatic-section-cache-key timeline entry #:fps 1 #:camera #f
                                #:renderers '()
                                #:color-context resolver-4-context
                                #:asset-files '()))
  (define document (make-preview-document (authored-timeline-scene timeline)))
  (define sample (frame-sample 0 1))
  (check-not-equal?
   (make-preview-frame-key document 0 sample
                           (make-preview-render-spec #:fps 1 #:theme warm))
   (make-preview-frame-key document 0 sample
                           (make-preview-render-spec #:fps 1 #:theme cool)))
  ;; The preview grammar is private but its resolver field is a deliberate
  ;; appearance component. A v3 identity must not equal the current v4 one.
  (define preview-identity
    (preview-render-spec-id (make-preview-render-spec #:fps 1 #:theme warm)))
  (check-equal? (list-ref preview-identity 7) 4)
  (check-not-equal? preview-identity
                    (list-set preview-identity 7 3))
  ;; Resolved per-vertex colors are packed into a persistent GL resource, so
  ;; its appearance key must carry the same resolver namespace as 2D caches.
  (define colored-view
    (view3d
     (list
      (mesh3d #:id 'resolver-color-mesh
              #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
              #:triangles (vector (vector 0 1 2))
              #:colors (vector "crimson" "crimson" "crimson")))
     #:id 'resolver-color-view))
  (define colored-geometry
    (vector-ref (compiled-view3d-geometries (compile-view3d colored-view)) 0))
  (check-not-equal?
   (packed-geometry-appearance-key colored-geometry resolver-3-context)
   (packed-geometry-appearance-key colored-geometry resolver-4-context)))
