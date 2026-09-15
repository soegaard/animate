#lang racket/base

;; Keep construction programs and timelines usable in a minimal/headless Racket.
;; The native/project adapters are loaded only when a scene or a render is requested.
(require racket/list
         racket/runtime-path
         "../../../private/render-job-plan.rkt"
         "../../core.rkt"
         "../../private/frame-reuse.rkt")
(provide make-library-theme
         library-example->scene
         run-library-example
         geometry-render-preparer
         geometry-render-builder)
(define-runtime-path adapter "../../animate.rkt")
(define-runtime-path project-module "../../../project.rkt")
(define (make-library-theme mode)
  (define parent
    (case mode [(light) default-light-geometry-theme] [(dark) default-dark-geometry-theme]
      [else (raise-argument-error 'make-library-theme "'light or 'dark" mode)]))
  (geometry-theme #:extends parent
    (stroke [width 2.5])
    (point [radius 0.055])
    (label [font-size 0.28])
    (circle (deemphasized (stroke [dash (7 5)])))
    (marker [size 0.18] [radius 0.28] [spacing 0.08])
    (highlighted (stroke [width 4.5]))))
(define (library-example->scene timeline #:width [width 1280] #:height [height 720])
  ((dynamic-require adapter 'geometry-timeline->scene) timeline #:width width #:height height))

(define-runtime-path runner "run-example.rkt")
(define (run-library-example name factory)
  ((dynamic-require runner 'run-geometry-example) name factory))

;; geometry-render-preparer : source-build-context? immutable-hash?
;;                             -> source-preparation?
;;   Produces geometry's once-per-project semantic static-frame witness.
(define (geometry-render-preparer context options)
  (define geometry-options (geometry-render-options context options))
  (define timeline (geometry-render-timeline context geometry-options))
  (define fps (hash-ref geometry-options 'fps))
  (define captions? (hash-ref geometry-options 'captions?))
  (define source-frame-indices
    (build-list (geometry-frame-count timeline fps) values))
  (define witness
   (make-frame-reuse-witness
     (geometry-context-field context 'source-build-context-base-fingerprint)
     (list->vector
      (geometry-frame-reuse-representatives
       timeline source-frame-indices fps captions?))))
  ((dynamic-require project-module 'source-preparation)
   #:payload (geometry-render-preparation-payload geometry-options)
   #:frame-reuse (frame-reuse-witness->datum witness)
   #:diagnostics #hasheq((geometry-reuse-planned? . #t)
                          (persistent-cache-eligible? . #t))))

;; geometry-render-builder : source-build-context? immutable-hash? immutable-hash?
;;                           -> scene?
;;   Reconstructs one geometry scene from the same frozen option snapshot in a worker.
(define (geometry-render-builder context options payload)
  (define values (geometry-render-options context options))
  (unless (equal? payload (geometry-render-preparation-payload values))
    (raise-arguments-error
     'geometry-render-builder
     "the verified geometry preparation payload for this option snapshot"
     "payload" payload))
  (define timeline (geometry-render-timeline context values))
  ((dynamic-require adapter 'geometry-timeline->scene)
   timeline
   #:width (hash-ref values 'width)
   #:height (hash-ref values 'height)
   #:captions? (hash-ref values 'captions?)))

;; geometry-render-options : source-build-context? immutable-hash? -> immutable-hash?
;;   Validates the transferable geometry construction choices shared by all workers.
(define (geometry-render-options context options)
  (unless ((dynamic-require project-module 'source-build-context?) context)
    (raise-argument-error 'geometry-render-options "source-build-context?" context))
  (unless (hash? options)
    (raise-argument-error 'geometry-render-options "immutable hash?" options))
  (define width (hash-ref options 'width #f))
  (define height (hash-ref options 'height #f))
  (define fps (hash-ref options 'fps #f))
  (define theme-mode (hash-ref options 'theme-mode #f))
  (define captions? (hash-ref options 'captions? #f))
  (unless (and (exact-positive-integer? width)
               (exact-positive-integer? height)
               (exact-positive-integer? fps)
               (memq theme-mode '(light dark))
               (boolean? captions?))
    (raise-arguments-error
     'geometry-render-options
     "geometry render options containing positive width, height, fps, light/dark theme-mode, and captions?"
     "options" options))
  (unless (and (= width (geometry-context-field context 'source-build-context-width))
               (= height (geometry-context-field context 'source-build-context-height))
               (= fps (geometry-context-field context 'source-build-context-fps)))
    (raise-arguments-error
     'geometry-render-options
     "options matching the project render snapshot"
     "options" options
     "context-width" (geometry-context-field context 'source-build-context-width)
     "context-height" (geometry-context-field context 'source-build-context-height)
     "context-fps" (geometry-context-field context 'source-build-context-fps)))
  (hasheq 'width width
          'height height
          'fps fps
          'theme-mode theme-mode
          'captions? captions?))

;; geometry-render-preparation-payload : immutable-hash? -> immutable-hash?
;;   Names the exact data a worker must receive instead of recomputing preparation.
(define (geometry-render-preparation-payload values)
  (hasheq 'schema 'animate-geometry-render-preparation-v1
          'width (hash-ref values 'width)
          'height (hash-ref values 'height)
          'fps (hash-ref values 'fps)
          'theme-mode (hash-ref values 'theme-mode)
          'captions? (hash-ref values 'captions?)))

;; geometry-render-timeline : source-build-context? immutable-hash? -> geometry-timeline?
;;   Loads an example's explicit timeline factory and applies the frozen semantic options.
(define (geometry-render-timeline context values)
  (define module-path
    (geometry-context-field context 'source-build-context-module-path))
  (define factory
    (dynamic-require (string->path module-path) 'make-demo-timeline))
  (unless (and (procedure? factory)
               (procedure-arity-includes? factory 0))
    (raise-arguments-error
     'geometry-render-timeline
     "an example make-demo-timeline procedure accepting its documented keywords"
     "module-path" module-path
     "factory" factory))
  (factory #:aspect (/ (hash-ref values 'width) (hash-ref values 'height))
           #:theme-mode (hash-ref values 'theme-mode)))

;; geometry-context-field : source-build-context? symbol? -> any/c
;;   Retrieves one project context accessor lazily to keep ordinary example requires headless.
(define (geometry-context-field context accessor)
  ((dynamic-require project-module accessor) context))
