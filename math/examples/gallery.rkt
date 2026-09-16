#lang racket/base

;;;
;;; Mathematical Gallery
;;;
;; A selectable visual catalogue of held operations, provenance, conditions,
;; named moves, and presentation policy. Requiring this module does not render.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/lazy-require lazy-require)
         "gallery/catalogue.rkt" "gallery/model.rkt")
(lazy-require ["gallery/run.rkt" (run-gallery!)]
              ["gallery/source.rkt" ([gallery-render-preparer prepare-source!]
                                      [gallery-render-builder build-source!])]
              ["gallery/preview.rkt" ([make-gallery-scene! preview-gallery!])])
(provide gallery-plates gallery-chapters select-gallery-plates gallery-entries gallery-duration
         gallery-render-preparer gallery-render-builder make-demo-scene)

; gallery-render-preparer : any/c immutable-hash? -> any/c
;;   Defers the generic parent preparation boundary until a render is explicitly requested.
(define (gallery-render-preparer context options) (prepare-source! context options))

; gallery-render-builder : any/c immutable-hash? immutable-hash? -> any/c
;;   Defers worker-local reconstruction from already verified portable preparation.
(define (gallery-render-builder context options payload) (build-source! context options payload))

; make-demo-scene : [#:plates (or/c #f list?)] [#:chapter (or/c #f symbol?)]
;   [#:theme symbol?] [#:width integer?] [#:height integer?] [#:show-api? boolean?] -> scene?
;;   Prepares a directly usable gallery scene; command-line movie rendering is restartable.
(define (make-demo-scene #:plates [plates #f] #:chapter [chapter #f] #:theme [theme 'light]
                         #:width [width 1280] #:height [height 720] #:show-api? [show-api? #f])
  (preview-gallery! (select-gallery-plates #:plates plates #:chapter chapter)
                    #:theme theme #:width width #:height height #:show-api? show-api?))

(module+ main (run-gallery!))
