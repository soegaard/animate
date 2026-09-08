#lang racket/base

;;; SCENE-3D-V0: extensible renderer capability declarations and preflight

(require racket/set
         racket/file
         racket/runtime-path
         rackunit
         "../3d.rkt"
         "../3d/render.rkt"
         "../main.rkt"
         "../project.rkt")

(define-runtime-path opengl-module-path "../3d/opengl.rkt")

(define full-current-features
  (seteq 'opaque-triangles 'perspective 'orthographic 'depth-buffer
         'flat-shading 'smooth-shading 'transparency 'clipping-planes
         'screen-strokes 'linear-depth 'object-id 'ambient-light
         'directional-light))

(define (capabilities #:features [features full-current-features]
                      #:directional [directional 4])
  (renderer3d-capabilities
   features
   (hasheq 'maximum-directional-lights directional
           'maximum-point-lights 0
           'maximum-spot-lights 0
           'maximum-shadow-lights 0
           'maximum-clip-planes 8
           'maximum-shadow-map-size 0
           'maximum-samples 1)
   (hasheq 'test-backend #t)))

;; This minimal backend is enough to exercise the generic capability boundary.
;; Its renderer methods must never run in this test: a rejected request has to
;; fail before preparing renderer-owned resources.
(struct constrained-renderer (report)
  #:transparent
  #:methods gen:renderer3d
  [(define (renderer3d-id _renderer) 'constrained-test)
   (define (renderer3d-capabilities-of renderer)
     (constrained-renderer-report renderer))
   (define (renderer3d-fingerprint _renderer _request) 'unreachable)
   (define (renderer3d-prepare _renderer _request)
     (error 'constrained-renderer "preparation must not start"))
   (define (renderer3d-render _renderer _preparation _request)
     (error 'constrained-renderer "rendering must not start"))
   (define (renderer3d-release _renderer) (void))])

(define lit-view
  (view3d
   (list (cube3d 2 #:id 'cube #:material (material3d #:shading 'smooth)))
   #:id 'world
   #:width 4 #:height 3 #:render-mode 'opaque
   #:lights
   (list (ambient-light3d)
         (directional-light3d (vec3 1 0 -1) #:id 'key-left)
         (directional-light3d (vec3 -1 0 -1) #:id 'key-right))))

(module+ test
  (define report (capabilities))
  (check-true (renderer3d-capabilities? report))
  (check-true (renderer3d-supports? report 'depth-buffer))
  (check-true (renderer3d-supports? report '(depth-buffer directional-light)))
  (check-false (renderer3d-supports? report 'point-light))
  (check-equal? (renderer3d-capability-limit report 'maximum-directional-lights) 4)
  (check-equal? (renderer3d-capability-limit report 'missing 'fallback) 'fallback)
  (check-not-exn (lambda () (renderer3d-require-capabilities report 'depth-buffer)))
  (check-exn exn:fail?
             (lambda () (renderer3d-require-capabilities report 'point-light)))

  ;; The declaration is immutable data, not a mutable backend-side bag.
  (check-exn exn:fail?
             (lambda ()
               (renderer3d-capabilities (mutable-seteq 'depth-buffer)
                                        (hasheq) (hasheq))))
  (check-exn exn:fail?
             (lambda ()
               (renderer3d-capabilities (seteq 'depth-buffer)
                                        (make-hasheq) (hasheq))))
  (check-exn exn:fail?
             (lambda ()
               (renderer3d-capabilities (seteq 'depth-buffer)
                                        (hasheq 'maximum-samples 1.0)
                                        (hasheq))))

  (define request (view3d->render3d-request lit-view 80 60))
  (check-true
   (renderer3d-supports?
    (renderer3d-capabilities
     (renderer3d-request-required-features request)
     (hasheq)
     (hasheq))
    '(opaque-triangles smooth-shading perspective ambient-light directional-light)))
  (check-equal?
   (hash-ref (renderer3d-request-required-limits request)
             'maximum-directional-lights)
   2)

  ;; Material colours remain public `color-spec?` values until the renderer
  ;; needs channels.  A named opaque colour must not make capability preflight
  ;; either reject the frame or misclassify it as transparent.
  (define named-color-request
    (view3d->render3d-request
     (view3d
      (list (cube3d 2 #:id 'gold-cube
                    #:material (material3d #:color "gold" #:shading 'flat)))
      #:id 'named-colour #:width 4 #:height 3 #:render-mode 'opaque)
     80 60))
  (check-false
   (set-member? (renderer3d-request-required-features named-color-request)
                'transparency))

  ;; A limit violation is observed before preparation, and therefore cannot
  ;; become OpenGL shader-array truncation.
  (check-exn
   exn:fail?
   (lambda ()
     (renderer3d-require-request-capabilities
      (constrained-renderer (capabilities #:directional 1)) request)))

  ;; Project checking samples the selected frame grid and performs the same
  ;; comparison without creating any output or cache directory.
  (define temporary-root (make-temporary-file "animate-v0-capabilities-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (define output-root (build-path temporary-root "output"))
     (define cache-root (build-path temporary-root "cache"))
     (define project
       (animate-project
        #:id 'v0-capabilities
        #:source (scene-source (scene-wait (scene-add (make-scene) lit-view) 1))
        #:render (render-spec #:fps 1 #:width 80 #:height 60)
        #:output (output-spec #:root output-root #:name "frame" #:format 'png-sequence)
        #:encoder (encoder-spec #:codec 'none)
        #:cache (cache-spec #:root cache-root #:policy 'off)))
     (define report (check-project! (plan-project project #:directory temporary-root)))
     (check-true (project-check-report-ok? report))
     (check-false (directory-exists? output-root))
     (check-false (directory-exists? cache-root)))
   (lambda () (delete-directory/files temporary-root))))

;; The normal suite stays GUI-free. The OpenGL lane verifies the critical V0
;; promise against the actual shader backend: five authored directional lights
;; fail during preparation rather than silently becoming four on the GPU.
(module+ test
  (when (equal? (getenv "ANIMATE_OPENGL_INTEGRATION") "1")
    (define make-opengl-renderer
      (dynamic-require opengl-module-path 'opengl-renderer3d))
    (define make-opengl-spec
      (dynamic-require opengl-module-path 'opengl-renderer3d-spec))
    (define renderer
      (make-opengl-renderer
       (make-opengl-spec #:samples 1 #:cache-megabytes 16 #:fallback 'error)))
    (dynamic-wind
     void
     (lambda ()
       (define five-lights-view
         (view3d
          (list (cube3d 2 #:id 'cube #:material (material3d #:shading 'flat)))
          #:id 'five-lights #:width 4 #:height 3 #:render-mode 'opaque
          #:lights
          (for/list ([index (in-range 5)])
            (directional-light3d (vec3 (+ index 1) 1 -1)
                                 #:id (string->symbol (format "key-~a" index))))))
       (check-exn
        exn:fail?
        (lambda ()
          (renderer3d-prepare renderer
                              (view3d->render3d-request five-lights-view 80 60)))))
     (lambda () (renderer3d-release renderer)))))
