#lang racket/base

;;;
;;; Restartable Mathematical Example Sources
;;;
;; Shares the documented PR-A preparer/builder contract across ordinary math
;; lessons. Parent preparation owns TeX and layout; builders only rebind data.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (for-syntax racket/base)
         (only-in racket/runtime-path define-runtime-path)
         (only-in "../../../private/render-preparation-manifest.rkt"
                  build-render-input-manifest!)
         "../../../colors.rkt"
         "../../../project.rkt"
         "../../private/native.rkt"
         "../../private/preparation-artifacts.rkt"
         "../../private/prepared-plan-codec.rkt"
         "../../private/presentation.rkt"
         "../../private/prepare.rkt"
         "../../render.rkt")

;; Exports
(provide math-render-preparer
         math-render-builder)


;;;
;;; Frozen Render Inputs
;;;

; runtime-module-path : path?
;;   Declares this lazy adapter as a tracked preparation dependency, including its imports.
(define-runtime-path runtime-module-path "library-example-runtime.rkt")

; math-native-theme : symbol? -> color-theme?
;;   Selects the generic rendering theme that corresponds to math's formula palette.
(define (math-native-theme theme-mode)
  (case theme-mode
    [(light) animate-light-theme]
    [(dark) animate-dark-theme]
    [else (raise-argument-error 'math-native-theme "'light or 'dark" theme-mode)]))

; math-background : symbol? -> string?
;;   Gives the one camera background paired with the requested mathematical theme.
(define (math-background theme-mode)
  (case theme-mode
    [(light) "#FFFFFF"]
    [(dark) "#121620"]
    [else (raise-argument-error 'math-background "'light or 'dark" theme-mode)]))

; math-render-options : source-build-context? immutable-hash? -> immutable-hash?
;;   Validates the transferable lesson/case/appearance snapshot shared by all builders.
(define (math-render-options context options)
  (unless (source-build-context? context)
    (raise-argument-error 'math-render-options "source-build-context?" context))
  (unless (and (immutable? options) (hash? options))
    (raise-argument-error 'math-render-options "immutable hash?" options))
  (define lesson (hash-ref options 'lesson #f))
  (define case-path (hash-ref options 'case-path #f))
  (define title (hash-ref options 'title #f))
  (define theme-mode (hash-ref options 'theme-mode #f))
  (define width (hash-ref options 'width #f))
  (define height (hash-ref options 'height #f))
  (define fps (hash-ref options 'fps #f))
  (define supersample (hash-ref options 'supersample #f))
  (unless (and (symbol? lesson)
               (or (not case-path)
                   (and (list? case-path) (andmap symbol? case-path)))
               (string? title)
               (memq theme-mode '(light dark))
               (exact-positive-integer? width)
               (exact-positive-integer? height)
               (exact-positive-integer? fps)
               (exact-positive-integer? supersample))
    (raise-arguments-error
     'math-render-options
     "lesson, optional case path, title, light/dark appearance, and positive raster options"
     "options" options))
  (unless (and (= width (source-build-context-width context))
               (= height (source-build-context-height context))
               (= fps (source-build-context-fps context)))
    (raise-arguments-error
     'math-render-options
     "options matching the project width, height, and FPS snapshot"
     "options" options))
  (unless (equal? (color-theme-fingerprint (source-build-context-theme context))
                  (color-theme-fingerprint (math-native-theme theme-mode)))
    (raise-arguments-error
     'math-render-options
     "a generic color theme matching the mathematical light/dark appearance"
     "theme-mode" theme-mode))
  (hasheq 'schema 'animate-math-render-options-v1
          'lesson lesson
          'case-path case-path
          'title (string->immutable-string title)
          'theme-mode theme-mode
          'width width
          'height height
          'fps fps
          'supersample supersample
          'camera
          (hasheq 'schema 'animate-math-camera-v1
                  'width width
                  'height height
                  'background (math-background theme-mode))))

; math-source-plan : source-build-context? immutable-hash? -> presentation-plan?
;;   Reconstructs the selected local lesson plan without typesetting or rendering.
(define (math-source-plan context values)
  (define original-plan
    (dynamic-require (string->path (source-build-context-module-path context)) 'plan))
  (unless (presentation-plan? original-plan)
    (raise-arguments-error
     'math-source-plan
     "an example module exporting a presentation plan"
     "module-path" (source-build-context-module-path context)
     "plan" original-plan))
  (define case-path (hash-ref values 'case-path))
  (if case-path
      (select-case-plan original-plan case-path)
      original-plan))

; make-math-render-camera : immutable-hash? -> any/c
;;   Builds the one effective native camera used by preparation and every builder.
(define (make-math-render-camera values)
  ((native 'animate 'make-camera)
   #:width (hash-ref values 'width)
   #:height (hash-ref values 'height)
   #:background (hash-ref (hash-ref values 'camera) 'background)))


;;;
;;; PR-A Source Contract
;;;

; math-render-preparer : source-build-context? immutable-hash? -> source-preparation?
;;   Typesets and lays out the complete lesson once in the parent before worker startup.
(define (math-render-preparer context options)
  (define values (math-render-options context options))
  (define plan (math-source-plan context values))
  (define camera (make-math-render-camera values))
  (define prepared
    (prepare-math-plan! plan
                        #:camera camera
                        #:theme (hash-ref values 'theme-mode)))
  (define staged-assets
    (stage-prepared-svg-artifacts!
     prepared
     (source-build-context-asset-base context)))
  (define payload
    (prepared-math-plan->portable-payload prepared values staged-assets))
  (source-preparation
   #:payload payload
   ;; Lazy loading keeps inspection native-independent. Explicitly declare the
   ;; runtime adapter's import closure so input-integrity checking is not weakened.
   #:dependencies
   (hash-ref (build-render-input-manifest! runtime-module-path '()) 'entries)
   #:artifacts (staged-svg-artifact-descriptors staged-assets)
   #:diagnostics
   (hasheq 'schema 'animate-math-preparation-diagnostics-v1
           'lesson (hash-ref values 'lesson)
           'case-path (hash-ref values 'case-path)
           'plan-duration (plan-duration plan)
           'layout-count (hash-count (prepared-math-plan-layouts prepared))
           'typesetting-owner 'parent-only
           'math-preparation-count 1
           'portable-schema math-preparation-payload-schema
           'persistent-cache-eligible? #t)))

; math-render-builder : source-build-context? immutable-hash? immutable-hash? -> scene?
;;   Rebinds validated parent preparation to worker-local states without invoking TeX.
(define (math-render-builder context options payload)
  (define values (math-render-options context options))
  (define plan (math-source-plan context values))
  (define camera (make-math-render-camera values))
  (define prepared
    (portable-payload->prepared-math-plan payload plan camera values))
  (define-values (expected-foreground expected-background)
    (theme-colors (hash-ref values 'theme-mode)))
  (unless (and (string=? (prepared-math-plan-foreground prepared) expected-foreground)
               (string=? (prepared-math-plan-background prepared) expected-background))
    (raise-arguments-error
     'math-render-builder
     "prepared formula colors matching the requested light/dark theme"
     "prepared-foreground" (prepared-math-plan-foreground prepared)
     "prepared-background" (prepared-math-plan-background prepared)
     "theme" (hash-ref values 'theme-mode)))
  (math-plan->scene! prepared
                     #:camera camera
                     #:theme (hash-ref values 'theme-mode)
                     #:title (hash-ref values 'title)
                     #:id 'math-lesson))
