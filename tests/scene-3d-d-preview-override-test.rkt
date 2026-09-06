#lang racket/base

;;; SCENE-3D-D Preview Inspection-Camera Tests

(require racket/class
         racket/draw
         racket/runtime-path
         rackunit
         "../3d.rkt"
         "../main.rkt"
         "../preview.rkt"
         "../private/preview-worker-process.rkt"
         "../private/preview-repl.rkt"
         "../private/3d/preview-camera3d-override.rkt")

(define-runtime-path worker-fixture "fixtures/preview-worker-3d-scene.rkt")

(define triangle
  (mesh3d #:id 'triangle
          #:vertices (vector (vec3 -1 -1 0) (vec3 1 -1 0) (vec3 0 1 0))
          #:triangles (vector (vector 0 1 2))))

(define authored-camera
  (perspective-camera3d #:position (vec3 0 0 6) #:look-at origin3))

(define source
  (scene-wait
   (scene-add (make-scene)
              (view3d (list triangle) #:id 'world #:camera authored-camera
                      #:render-mode 'opaque))
   1))

(define override
  (make-preview-camera3d-override
   'world
   (perspective-camera3d #:position (vec3 4 1 6) #:look-at origin3)
   #:target origin3))

(define (bitmap-argb bitmap)
  (define bytes (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
  (send bitmap get-argb-pixels 0 0 (send bitmap get-width) (send bitmap get-height) bytes)
  bytes)

(module+ test
  (define sampled (scene-sample source 0))
  (define applied (preview-camera3d-override-apply sampled override))
  (check-equal? (view3d-camera (scene-state-ref sampled 'world)) authored-camera)
  (check-equal? (view3d-camera (scene-state-ref applied 'world))
                (preview-camera3d-override-camera override))
  (check-equal? (scene-sample source 0) sampled)

  ;; The subprocess-safe representation round-trips the navigation camera and
  ;; is independent of the authored scene value.
  (define round-trip
    (datum->preview-camera3d-override
     (preview-camera3d-override->datum override)))
  (check-equal? (preview-camera3d-override-view-id round-trip) 'world)
  (check-equal? (camera3d-position (preview-camera3d-override-camera round-trip))
                (vec3 4 1 6))

  ;; The controller makes the inspection layer part of the immutable render
  ;; specification. Clearing it restores the authored view instead of writing
  ;; a camera change into the Scene.
  (define session
    (open-preview-controller
     source #:prefetch 0
     #:producer (lambda (_document _sample _render-spec _token) 'frame)
     #:byte-size (lambda (_value) 1)))
  (dynamic-wind
   void
   (lambda ()
     (preview-set-camera3d-override! session override)
     (check-equal? (hash-ref (preview-camera3d-overrides session) 'world)
                   override)
     (preview-clear-camera3d-override! session 'world)
     (check-false (hash-ref (preview-camera3d-overrides session) 'world #f))
     (check-equal? (view3d-camera (scene-state-ref (scene-sample source 0) 'world))
                   authored-camera)
     ;; The UI's “Use ... as REPL scratch camera” action writes only a session
     ;; scratch binding, never source text or a scene value.
     (define repl (open-preview-repl! session))
     (preview-repls-set-scratch-binding!
      session 'inspection-camera (preview-camera3d-override-camera override))
     (check-equal? (preview-repl-evaluate-string! repl "inspection-camera")
                   (preview-camera3d-override-camera override))
     (close-preview-repl! repl))
   (lambda () (preview-close! session)))

  ;; An isolated worker receives the reader-safe override and a subsequent
  ;; request with no override returns to the authored render.  This exercises
  ;; the actual subprocess protocol rather than merely its prefab structure.
  (define worker
    (start-project-preview-worker worker-fixture 'worker-3d-scene
                                  #:fingerprint 'scene-3d-d))
  (dynamic-wind
   void
   (lambda ()
     (define request
       (preview-render-request #:id 1 #:document-generation 0 #:render-generation 0
                               #:sample (frame-sample 0 2)
                               #:quality full-preview-quality #:priority 0))
     (define base-spec (make-preview-render-spec #:fps 2 #:pixel-scale 1/8))
     (define override-spec
       (make-preview-render-spec #:fps 2 #:pixel-scale 1/8
                                 #:camera3d-overrides (hasheq 'world override)))
     (define-values (baseline _base-diagnostics)
       (preview-worker-render-frame! worker request base-spec))
     (define-values (inspected _override-diagnostics)
       (preview-worker-render-frame! worker
                                     (preview-render-request
                                      #:id 2 #:document-generation 0 #:render-generation 1
                                      #:sample (frame-sample 0 2)
                                      #:quality full-preview-quality #:priority 0)
                                     override-spec))
     (define-values (restored _restored-diagnostics)
       (preview-worker-render-frame! worker
                                     (preview-render-request
                                      #:id 3 #:document-generation 0 #:render-generation 2
                                      #:sample (frame-sample 0 2)
                                      #:quality full-preview-quality #:priority 0)
                                     base-spec))
     (check-not-equal? (bitmap-argb baseline) (bitmap-argb inspected))
     (check-equal? (bitmap-argb baseline) (bitmap-argb restored)))
   (lambda () (preview-worker-stop! worker))))
