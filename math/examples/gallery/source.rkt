#lang racket/base

;;;
;;; Restartable Mathematical Gallery Source
;;;
;; Runs one parent preparation for the selected gallery. Workers consume verified
;; per-view portable files; they never typeset, fit formulas, or create another pool.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/list remove-duplicates)
         (only-in racket/runtime-path define-runtime-path)
         (for-syntax racket/base)
         "../../private/native.rkt" "../../private/prepare.rkt"
         "../../private/preparation-artifacts.rkt" "../../private/prepared-plan-codec.rkt"
         "model.rkt" "catalogue.rkt" "render.rkt" "artifacts.rkt")
(provide gallery-render-preparer gallery-render-builder gallery-render-options)

; gallery-runtime-module : path?
;;   Identifies the lazy preparation/render adapter whose complete imports must be tracked.
(define-runtime-path gallery-runtime-module "source.rkt")

; gallery-runtime-dependencies! : -> list?
;;   Tracks both the lazy gallery code and native renderer imports through the existing manifest builder.
(define (gallery-runtime-dependencies!)
  (define build-manifest! (native 'preparation-manifest 'build-render-input-manifest!))
  (append (hash-ref (build-manifest! gallery-runtime-module '()) 'entries)
          (hash-ref (build-manifest! native-root '()) 'entries)))

; gallery-render-options : any/c immutable-hash? -> immutable-hash?
;;   Resolves one exact selection and checks the effective generic rendering snapshot.
(define (gallery-render-options context options)
  (unless ((native 'project 'source-build-context?) context)
    (raise-argument-error 'gallery-render-options "source-build-context?" context))
  (unless (and (hash? options) (immutable? options) (= (hash-count options) 7)
               (list? (hash-ref options 'plates #f))
               (memq (hash-ref options 'theme #f) '(light dark))
               (boolean? (hash-ref options 'show-api? 'absent))
               (andmap (lambda (key) (exact-positive-integer? (hash-ref options key #f)))
                       '(width height fps supersample)))
    (raise-argument-error 'gallery-render-options "exact gallery source option snapshot" options))
  (define ids (hash-ref options 'plates))
  (define selected (select-gallery-plates #:plates ids))
  (unless (equal? ids (map gallery-plate-id selected))
    (raise-user-error 'gallery-render-options "plate ids must use catalogue order"))
  (for ([key (in-list '(width height fps))]
         [accessor (in-list '(source-build-context-width source-build-context-height source-build-context-fps))])
    (unless (= (hash-ref options key) ((native 'project accessor) context))
      (raise-arguments-error 'gallery-render-options "options differ from project configuration" "field" key)))
  (define theme (native 'colors (if (eq? (hash-ref options 'theme) 'dark)
                                     'animate-dark-theme 'animate-light-theme)))
  (unless (equal? ((native 'colors 'color-theme-fingerprint) theme)
                  ((native 'colors 'color-theme-fingerprint) ((native 'project 'source-build-context-theme) context)))
    (raise-user-error 'gallery-render-options "gallery and project themes differ"))
  options)

; view-options : immutable-hash? gallery-entry? -> immutable-hash?
;;   Identifies a portable replay without session, output, or worker information.
(define (view-options options entry)
  (hash-set options 'view (gallery-view-key entry)))

; gallery-render-preparer : any/c immutable-hash? -> source-preparation?
;;   Prepares each selected view once in the parent and publishes bounded replay files.
(define (gallery-render-preparer context input-options)
  (define options (gallery-render-options context input-options))
  (define entries (gallery-entries (select-gallery-plates #:plates (hash-ref options 'plates))))
  (define camera (make-gallery-camera! (hash-ref options 'width) (hash-ref options 'height) (hash-ref options 'theme)))
  (define base ((native 'project 'source-build-context-asset-base) context))
  (define artifacts '())
  (define descriptors
    (for/list ([entry (in-list entries)])
      (define prepared (prepare-gallery-view! entry camera (hash-ref options 'theme)))
      (define staged (stage-prepared-svg-artifacts! prepared base))
      (define portable (prepared-math-plan->portable-payload prepared (view-options options entry) staged))
      (define descriptor (write-gallery-payload! portable base))
      (set! artifacts (append artifacts (staged-svg-artifact-descriptors staged) (list descriptor)))
      (hasheq 'view (gallery-view-key entry) 'payload descriptor)))
  ((native 'project 'source-preparation)
   #:payload (hasheq 'schema 'animate-math-gallery-preparation-v1 'options options
                     'views (vector->immutable-vector (list->vector descriptors)))
   #:dependencies (gallery-runtime-dependencies!)
   #:artifacts (sort (remove-duplicates artifacts equal?) string<? #:key (lambda (a) (hash-ref a 'path)))
   #:diagnostics (hasheq 'gallery-preparation-count 1 'view-count (length entries)
                         'math-preparation-count (length entries) 'typesetting-owner 'parent-only
                         'persistent-cache-eligible? #t)))

; gallery-render-builder : any/c immutable-hash? immutable-hash? -> scene?
;;   Verifies and rebinds every prepared view without invoking the parent preparer.
(define (gallery-render-builder context input-options payload)
  (define options (gallery-render-options context input-options))
  (unless (and (hash? payload) (immutable? payload)
               (eq? (hash-ref payload 'schema #f) 'animate-math-gallery-preparation-v1)
               (equal? (hash-ref payload 'options #f) options)
               (vector? (hash-ref payload 'views #f)) (immutable? (hash-ref payload 'views)))
    (raise-user-error 'gallery-render-builder "wrong gallery preparation schema or options"))
  (define entries (gallery-entries (select-gallery-plates #:plates (hash-ref options 'plates))))
  (define descriptors (vector->list (hash-ref payload 'views)))
  (unless (= (length descriptors) (length entries))
    (raise-user-error 'gallery-render-builder "incomplete gallery preparation"))
  (define camera (make-gallery-camera! (hash-ref options 'width) (hash-ref options 'height) (hash-ref options 'theme)))
  (define base ((native 'project 'source-build-context-asset-base) context))
  (define preparations
    (for/list ([entry (in-list entries)] [descriptor (in-list descriptors)])
      (unless (and (hash? descriptor) (equal? (hash-ref descriptor 'view #f) (gallery-view-key entry)))
        (raise-user-error 'gallery-render-builder "wrong or repeated prepared view identity"))
      (portable-payload->prepared-math-plan
        (read-gallery-payload! (hash-ref descriptor 'payload) base)
        (gallery-view-plan (gallery-entry-view entry)) camera (view-options options entry))))
  (define-values (foreground background) (theme-colors (hash-ref options 'theme)))
  (for ([prepared (in-list preparations)])
    (unless (and (equal? foreground (prepared-math-plan-foreground prepared))
                 (equal? background (prepared-math-plan-background prepared)))
      (raise-user-error 'gallery-render-builder "prepared colors differ from the gallery theme")))
  (build-gallery-scene! entries preparations camera #:show-api? (hash-ref options 'show-api?)))
