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
         current-view3d-attachment-demands
         frame-artifact-cache-clear!
         frame-artifact-cache-render-count
         render-view3d-frame-artifact)

(struct frame-artifact-cache-entry (attachments artifact) #:transparent)
(struct frame-artifact-cache (by-content render-count) #:mutable #:transparent)

; make-frame-artifact-cache : -> frame-artifact-cache?
;; Creates a weak memoization table for one outer scene renderer/worker.
(define (make-frame-artifact-cache)
  (frame-artifact-cache (make-weak-hasheq) 0))

(define current-frame-artifact-cache
  ;; #f means that a direct one-off adapter call receives a short-lived cache.
  ;; scene-state->pict installs one explicit cache for its entire outer frame.
  (make-parameter #f))

;; The outer 2D compositor binds this once for a scene frame after examining
;; projected labels and inspector consumers.  Keeping demand separate from the
;; cache means the view adapter can request the union before its first draw,
;; rather than rendering colour and discovering later that a label needs depth.
;; Keys are immutable view IDs; values are canonical attachment lists.
(define current-view3d-attachment-demands
  (make-parameter (hasheq)))

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
  (define canonical-request (renderer3d-canonical-attachments attachments))
  (unless (or (not cancellation-token) (cancellation-token? cancellation-token))
    (raise-argument-error 'render-view3d-frame-artifact
                          "(or/c #f cancellation-token?)"
                          cancellation-token))
  (define (render-one)
    (define request
      (view3d->render3d-request view width height
                                 #:attachments canonical-request
                                 #:cancellation-token cancellation-token))
    (define result
      (renderer3d-render renderer (renderer3d-prepare renderer request) request))
    (define artifact (renderer3d-render-result-artifact result))
    (unless (renderer3d-attachment-set-satisfies?
             (renderer3d-frame-artifact-attachments artifact) canonical-request)
      (raise-arguments-error
       'render-view3d-frame-artifact
       "a renderer artifact satisfying every requested attachment"
       "requested" canonical-request
       "available" (renderer3d-frame-artifact-attachments artifact)))
    artifact)
  (if cancellation-token
      (render-one)
      (let* ([cache (or (current-frame-artifact-cache)
                        (make-frame-artifact-cache))]
             [content-key (view3d-content-key view)]
             [by-renderer
              (hash-ref! (frame-artifact-cache-by-content cache) content-key make-weak-hasheq)]
             [entries (hash-ref! by-renderer renderer make-hash)]
             [key (vector width height (view3d-camera view))]
             [found
              (for/first ([entry (in-list (hash-ref entries key '()))]
                          #:when (renderer3d-attachment-set-satisfies?
                                  (frame-artifact-cache-entry-attachments entry)
                                  canonical-request))
                (frame-artifact-cache-entry-artifact entry))])
        (or found
            (let ([artifact (render-one)])
              (hash-set! entries key
                         ;; A richer newly-rendered artifact supersedes any
                         ;; cached subset for this frame.  Besides avoiding
                         ;; needless retention, this makes a later colour-only
                         ;; reader share the authoritative colour+depth result,
                         ;; rather than revive an older colour-only snapshot.
                         (append
                          (filter
                           (lambda (entry)
                             (not (renderer3d-attachment-set-satisfies?
                                   (renderer3d-frame-artifact-attachments artifact)
                                   (frame-artifact-cache-entry-attachments entry))))
                           (hash-ref entries key '()))
                          (list
                           (frame-artifact-cache-entry
                            (renderer3d-frame-artifact-attachments artifact)
                            artifact))))
              (set-frame-artifact-cache-render-count!
               cache (add1 (frame-artifact-cache-render-count cache)))
              artifact)))))
