#lang racket/base

;;;
;;; Final Render Worker Fixture
;;;

;; Provides a moving module value plus a PR-A builder/preparer pair for real
;; subprocess final-frame tests. The optional initialization log is rooted in
;; the explicit build context, never in a process-global registry.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/file
         racket/path
         "../../main.rkt"
         "../../project.rkt")

;; Exports
(provide final-render-scene
         prepare-final-render-source!
         build-final-render-source!)


;;;
;;; Module Value Source
;;;

; final-render-scene : scene?
;;   Supplies six seconds of source-index-sensitive movement at a small raster.
(define final-render-scene
  (scene-play
   (scene-add
    (make-scene)
    (circle #:id 'final-render-dot
            #:center (vec2 -3 0)
            #:radius 3/4
            #:fill "tomato"
            #:stroke "firebrick"))
   (move-to 'final-render-dot (vec2 3 0))
   #:duration 6))


;;;
;;; Builder Source
;;;

; prepare-final-render-source! : source-build-context? immutable-hash?
;                                 -> source-preparation?
;;   Records one worker-local preparation and returns a data-only payload.
(define (prepare-final-render-source! context options)
  (record-initialization! context 'prepare)
  (source-preparation
   #:payload (hasheq 'fixture 'final-render-worker
                     'options options)
   #:diagnostics (hasheq 'phase 'prepare)))

; build-final-render-source! : source-build-context? immutable-hash? any/c -> scene?
;;   Records one worker-local build and returns the fixed restartable scene.
(define (build-final-render-source! context options payload)
  (record-initialization! context 'build)
  (unless (and (hash? payload) (equal? (hash-ref payload 'fixture #f)
                                       'final-render-worker))
    (raise-arguments-error
     'build-final-render-source!
     "the fixture preparation payload"
     "payload" payload))
  final-render-scene)

; record-initialization! : source-build-context? symbol? -> void?
;;   Appends a compact test observation under the caller-owned asset base.
(define (record-initialization! context phase)
  (define asset-base (source-build-context-asset-base context))
  (when (directory-exists? asset-base)
    (call-with-output-file
     (build-path asset-base "final-render-initialization.log")
     #:exists 'append
     (lambda (output)
       (writeln phase output))))
  (void))
