#lang racket/base

;;;
;;; PNG Renderer
;;;

;; Writes deterministic numbered PNG frames for a sampled scene.
;;
;; Filesystem changes are isolated in this module and use names ending in !.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/class
         racket/file
         racket/format
         racket/path
         "camera.rkt"
         "frame-renderer.rkt"
         "pict-adapter.rkt"
         "pict-renderer.rkt"
         "shape-pict-renderers.rkt")

;; Exports
(provide render-frames!
         render-frames/report!
         (struct-out render-diagnostics))


;;;
;;; Constants
;;;

; frame-name-pattern : regexp?
;;   Matches numbered PNG files owned by the frame renderer.
(define frame-name-pattern
  #px"^frame-[0-9]{6,}\\.png$")


;;;
;;; Frame Output
;;;

; render-frames! : scene? path-string?
;                  [#:fps exact-positive-integer?]
;                  [#:camera (or/c camera? false/c)]
;                  [#:renderers (listof pict-renderer?)]
;                  [#:clean? boolean?]
;                  [#:workers exact-positive-integer?]
;                  -> (listof path?)
;; Writes every sampled scene frame as a numbered PNG file. Paths stay in
;; frame-index order even when workers render files concurrently.
(define (render-frames! scene output-directory
                        #:fps [fps 30]
                        #:camera [camera #f]
                        #:renderers [renderers default-pict-renderers]
                        #:clean? [clean? #t]
                        #:workers [workers 1])
  (render-diagnostics-paths
   (render-frames/report! scene
                          output-directory
                          #:fps fps
                          #:camera camera
                          #:renderers renderers
                          #:clean? clean?
                          #:workers workers)))

;; render-diagnostics contains the deterministic output paths, actual worker
;; count, wall time, per-frame render/write durations in frame-index order, and
;; the resource-cache counter deltas observed for built-in renderers.
(struct render-diagnostics
  (paths frame-count workers elapsed-milliseconds frame-milliseconds
         cache-hits cache-misses cache-evictions)
  #:transparent)

; render-frames/report! : scene? path-string?
;                         [#:fps exact-positive-integer?]
;                         [#:camera (or/c camera? false/c)]
;                         [#:renderers (listof pict-renderer?)]
;                         [#:clean? boolean?]
;                         [#:workers exact-positive-integer?]
;                         -> render-diagnostics?
;; Writes frames just as render-frames! does, returning output and performance
;; diagnostics instead of only paths.
(define (render-frames/report! scene output-directory
                               #:fps [fps 30]
                               #:camera [camera #f]
                               #:renderers [renderers default-pict-renderers]
                               #:clean? [clean? #t]
                               #:workers [workers 1])
  (define frame-count
    (scene-frame-count scene #:fps fps))
  (unless (path-string? output-directory)
    (raise-argument-error
     'render-frames!
     "path-string?"
     output-directory))
  (unless (or (not camera)
              (camera? camera))
    (raise-argument-error
     'render-frames!
     "(or/c camera? false/c)"
     camera))
  (check-pict-renderer-list 'render-frames! renderers)
  (unless (boolean? clean?)
    (raise-argument-error 'render-frames! "boolean?" clean?))
  (unless (exact-positive-integer? workers)
    (raise-argument-error 'render-frames! "exact-positive-integer?" workers))
  (make-directory* output-directory)
  (when clean?
    (delete-old-frames! output-directory))
  (define before-counters
    (default-pict-renderer-cache-counters renderers))
  (define started-at (current-inexact-milliseconds))
  (define-values (paths frame-milliseconds active-workers)
    (render-frame-jobs! scene
                        output-directory
                        frame-count
                        fps
                        camera
                        renderers
                        workers))
  (define after-counters
    (default-pict-renderer-cache-counters renderers))
  (render-diagnostics
   paths
   frame-count
   active-workers
   (- (current-inexact-milliseconds) started-at)
   frame-milliseconds
   (- (renderer-cache-counters-hits after-counters)
      (renderer-cache-counters-hits before-counters))
   (- (renderer-cache-counters-misses after-counters)
      (renderer-cache-counters-misses before-counters))
   (- (renderer-cache-counters-evictions after-counters)
      (renderer-cache-counters-evictions before-counters))))

; render-frame-jobs! : scene? path-string? exact-nonnegative-integer?
;                      exact-positive-integer? (or/c camera? false/c)
;                      (listof pict-renderer?) exact-positive-integer?
;                      -> (values (listof path?) (listof nonnegative-real?)
;                                 exact-nonnegative-integer?)
;; Runs independent frame render/write jobs through a bounded thread pool. Each
;; job owns a unique output filename, while the returned lists are rebuilt in
;; deterministic frame-index order after all workers complete.
(define (render-frame-jobs! scene output-directory frame-count fps camera renderers workers)
  (define active-workers
    (if (zero? frame-count)
        0
        (min workers frame-count)))
  (define paths (make-vector frame-count #f))
  (define durations (make-vector frame-count #f))
  (define work-lock (make-semaphore 1))
  (define next-index 0)
  (define first-failure #f)
  (define (take-frame-index!)
    (call-with-semaphore
     work-lock
     (lambda ()
       (cond [first-failure #f]
             [(>= next-index frame-count) #f]
             [else
              (define result next-index)
              (set! next-index (add1 next-index))
              result]))))
  (define (record-failure! exception)
    (call-with-semaphore
     work-lock
     (lambda ()
       (unless first-failure
         (set! first-failure exception)))))
  (define (render-one! frame-index)
    (define path (frame-index->path output-directory frame-index))
    (define started-at (current-inexact-milliseconds))
    (define bitmap
      (scene-frame->bitmap scene
                           frame-index
                           #:fps fps
                           #:camera camera
                           #:renderers renderers))
    (unless (send bitmap save-file path 'png)
      (raise-arguments-error
       'render-frames!
       "could not save a PNG frame"
       "path" path))
    (vector-set! paths frame-index path)
    (vector-set! durations frame-index
                 (- (current-inexact-milliseconds) started-at)))
  (define (worker)
    (let loop ()
      (define frame-index (take-frame-index!))
      (when frame-index
        (with-handlers ([exn:fail? record-failure!])
          (render-one! frame-index))
        (loop))))
  (define worker-threads
    (for/list ([_ (in-range active-workers)])
      (thread worker)))
  (for ([worker-thread (in-list worker-threads)])
    (thread-wait worker-thread))
  (when first-failure
    (raise first-failure))
  (values (vector->list paths)
          (vector->list durations)
          active-workers))

; frame-index->path : path-string? exact-nonnegative-integer? -> path?
;;   Converts frame-index to its zero-padded PNG output path.
(define (frame-index->path output-directory frame-index)
  (build-path
   output-directory
   (format "frame-~a.png"
           (~r frame-index
               #:min-width 6
               #:pad-string "0"))))

; delete-old-frames! : path-string? -> void?
;;   Deletes only numbered PNG files previously owned by the renderer.
(define (delete-old-frames! output-directory)
  (for ([entry (in-list (directory-list output-directory))])
    (when (regexp-match? frame-name-pattern (path->string entry))
      (delete-file (build-path output-directory entry)))))
