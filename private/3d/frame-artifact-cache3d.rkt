#lang racket/base

;;;
;;; Frame-Local 3D Artifact Cache
;;;

;; The cache is adapter state, not scene state. Its weak outer key means that
;; finished immutable views and their depth snapshots become collectable while
;; all consumers in one scene/pict pass share exactly one rendered artifact.

(require racket/list
         "../preview-cancellation.rkt"
         "frame-artifact3d.rkt"
         "renderer3d.rkt"
         "view3d-visual.rkt")

(provide frame-artifact-cache?
         make-frame-artifact-cache
         current-frame-artifact-cache
         frame-artifact-cache-clear!
         frame-artifact-cache-render-count
         render-view3d-frame-artifact)

(struct frame-artifact-cache (by-content render-count) #:mutable #:transparent)

; make-frame-artifact-cache : -> frame-artifact-cache?
;; Creates a weak memoization table for one outer scene renderer/worker.
(define (make-frame-artifact-cache)
  (frame-artifact-cache (make-weak-hasheq) 0))

(define current-frame-artifact-cache
  (make-parameter (make-frame-artifact-cache)))

; frame-artifact-cache-clear! : frame-artifact-cache? -> void?
;; Discards only adapter-owned render results and statistics.
(define (frame-artifact-cache-clear! cache)
  (unless (frame-artifact-cache? cache)
    (raise-argument-error 'frame-artifact-cache-clear! "frame-artifact-cache?" cache))
  (hash-clear! (frame-artifact-cache-by-content cache))
  (set-frame-artifact-cache-render-count! cache 0)
  (void))

; render-view3d-frame-artifact : view3d? positive-int? positive-int? renderer3d?
;                                [#:attachments list?]
;                                [#:cancellation-token (or/c #f cancellation-token?)]
;                                -> renderer3d-frame-artifact?
;; Renders once for identical spatial content, camera, renderer, dimensions,
;; and attachment needs. A request carrying a cancellation token deliberately
;; bypasses the cache: cached pixels must not make a cancelled render appear to
;; have succeeded without checking the token.
(define (render-view3d-frame-artifact view width height renderer
                                      #:attachments [attachments '(color)]
                                      #:cancellation-token [cancellation-token #f])
  (unless (view3d? view)
    (raise-argument-error 'render-view3d-frame-artifact "view3d?" view))
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (raise-argument-error 'render-view3d-frame-artifact "positive viewport dimensions"
                          (vector width height)))
  (unless (renderer3d? renderer)
    (raise-argument-error 'render-view3d-frame-artifact "renderer3d?" renderer))
  (unless (and (list? attachments) (memq 'color attachments))
    (raise-argument-error 'render-view3d-frame-artifact "attachment list including 'color" attachments))
  (unless (or (not cancellation-token) (cancellation-token? cancellation-token))
    (raise-argument-error 'render-view3d-frame-artifact
                          "(or/c #f cancellation-token?)"
                          cancellation-token))
  (define (render-one)
    (define request
      (view3d->render3d-request view width height
                                 #:attachments attachments
                                 #:cancellation-token cancellation-token))
    (define result
      (renderer3d-render renderer (renderer3d-prepare renderer request) request))
    (or (renderer3d-render-result-artifact result)
        (renderer3d-frame-artifact
         width height (renderer3d-render-result-argb-bytes result) #f #f
         (view3d-camera view) (renderer3d-render-result-diagnostics result))))
  (if cancellation-token
      (render-one)
      (let* ([cache (current-frame-artifact-cache)]
             [content-key (view3d-content-key view)]
             [entries
              (hash-ref! (frame-artifact-cache-by-content cache) content-key make-hash)]
             [key
              (vector renderer width height (view3d-camera view)
                      (canonical-attachments attachments))]
             [found (hash-ref entries key #f)])
        (or found
            (let ([artifact (render-one)])
              (hash-set! entries key artifact)
              (set-frame-artifact-cache-render-count!
               cache (add1 (frame-artifact-cache-render-count cache)))
              artifact)))))

(define (canonical-attachments attachments)
  (sort (remove-duplicates attachments) symbol<?))
