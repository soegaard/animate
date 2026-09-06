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
         "scene-frame-grid.rkt"
         "ode-flow.rkt"
         "3d/ode-flow3d.rkt"
         "pict-adapter.rkt"
         "pict-renderer.rkt"
         "scene.rkt"
         "shape-pict-renderers.rkt"
         "../version.rkt")

;; Exports
(provide render-frames!
         render-frames/report!
         render-frame-indices!
         render-frame-indices/report!
         (struct-out render-diagnostics))


;;;
;;; Constants
;;;

; frame-name-pattern : regexp?
;;   Matches numbered PNG files owned by the frame renderer.
(define frame-name-pattern
  #px"^frame-[0-9]{6,}\\.png$")

;; Racket 8.18 added parallel thread pools. Looking up the bindings at run
;; time keeps this package loadable with its Racket 8.12 baseline, where frame
;; workers keep their existing coroutine-thread implementation.
(define make-parallel-thread-pool/proc
  (dynamic-require 'racket/base
                   'make-parallel-thread-pool
                   (lambda () #f)))

(define parallel-thread-pool-close/proc
  (dynamic-require 'racket/base
                   'parallel-thread-pool-close
                   (lambda () #f)))


;;;
;;; Frame Output
;;;

; render-frames! : scene? path-string?
;                  [#:fps exact-positive-integer?]
;                  [#:camera (or/c camera? false/c)]
;                  [#:renderers (listof pict-renderer?)]
;                  [#:clean? boolean?]
;                  [#:workers exact-positive-integer?]
;                  [#:supersample exact-positive-integer?]
;                  -> (listof path?)
;; Writes every sampled scene frame as a numbered PNG file. Paths stay in
;; frame-index order even when workers render files concurrently.
(define (render-frames! scene output-directory
                        #:fps [fps 30]
                        #:camera [camera #f]
                        #:renderers [renderers default-pict-renderers]
                        #:clean? [clean? #t]
                        #:workers [workers 1]
                        #:supersample [supersample 1])
  (render-diagnostics-paths
   (render-frames/report! scene
                          output-directory
                          #:fps fps
                          #:camera camera
                          #:renderers renderers
                          #:clean? clean?
                          #:workers workers
                          #:supersample supersample)))

;; render-diagnostics contains the deterministic output paths, actual worker
;; count, wall time, per-frame render/write durations in frame-index order, and
;; the resource-cache counter deltas observed for built-in renderers. Its
;; release identity records the implementation that produced those files.
(struct render-diagnostics
  (paths frame-count workers elapsed-milliseconds frame-milliseconds
         cache-hits cache-misses cache-evictions release-version release-stage)
  #:transparent)

;; pending-frame transfers one finished bitmap from a render worker to the
;; ordinary PNG writer thread. The original start time lets diagnostics retain
;; one complete duration for each frame, including output queuing and writing.
(struct pending-frame (local-index path bitmap started-at)
  #:transparent)

; render-frames/report! : scene? path-string?
;                         [#:fps exact-positive-integer?]
;                         [#:camera (or/c camera? false/c)]
;                         [#:renderers (listof pict-renderer?)]
;                         [#:clean? boolean?]
;                         [#:workers exact-positive-integer?]
;                         [#:supersample exact-positive-integer?]
;                         -> render-diagnostics?
;; Writes frames just as render-frames! does, returning output and performance
;; diagnostics instead of only paths.
(define (render-frames/report! scene output-directory
                               #:fps [fps 30]
                               #:camera [camera #f]
                               #:renderers [renderers default-pict-renderers]
                               #:clean? [clean? #t]
                               #:workers [workers 1]
                               #:supersample [supersample 1])
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
  (render-frame-indices/report!
   scene
   (build-list frame-count values)
   output-directory
   #:fps fps
   #:camera camera
   #:renderers renderers
   #:clean? clean?
   #:workers workers
   #:supersample supersample))

; render-frame-indices! : scene? (listof exact-nonnegative-integer?) path-string?
;                         [#:fps exact-positive-integer?]
;                         [#:camera (or/c camera? false/c)]
;                         [#:renderers (listof pict-renderer?)]
;                         [#:clean? boolean?]
;                         [#:workers exact-positive-integer?]
;                         [#:supersample exact-positive-integer?]
;                         -> (listof path?)
;; Renders selected scene-frame indices in the supplied order, naming the
;; output locally from frame-000000.png. This keeps a rendered timeline section
;; directly encodable without first copying or renumbering global frames.
(define (render-frame-indices! scene frame-indices output-directory
                               #:fps [fps 30]
                               #:camera [camera #f]
                               #:renderers [renderers default-pict-renderers]
                               #:clean? [clean? #t]
                               #:workers [workers 1]
                               #:supersample [supersample 1])
  (render-diagnostics-paths
   (render-frame-indices/report!
    scene frame-indices output-directory
    #:fps fps
    #:camera camera
    #:renderers renderers
    #:clean? clean?
    #:workers workers
    #:supersample supersample)))

; render-frame-indices/report! : scene? (listof exact-nonnegative-integer?)
;                                path-string? ... -> render-diagnostics?
;; Like render-frame-indices!, returning the normal renderer diagnostics. The
;; requested global indices are validated before any output directory changes.
(define (render-frame-indices/report! scene frame-indices output-directory
                                      #:fps [fps 30]
                                      #:camera [camera #f]
                                      #:renderers [renderers default-pict-renderers]
                                      #:clean? [clean? #t]
                                      #:workers [workers 1]
                                      #:supersample [supersample 1])
  (define available-frame-count
    (scene-frame-count scene #:fps fps))
  (unless (and (list? frame-indices)
               (andmap exact-nonnegative-integer? frame-indices)
               (andmap (lambda (frame-index)
                         (< frame-index available-frame-count))
                       frame-indices))
    (raise-argument-error
     'render-frame-indices!
     (format "list of frame indices in [0, ~a)" available-frame-count)
     frame-indices))
  (unless (path-string? output-directory)
    (raise-argument-error
     'render-frame-indices!
     "path-string?"
     output-directory))
  (unless (or (not camera)
              (camera? camera))
    (raise-argument-error
     'render-frame-indices!
     "(or/c camera? false/c)"
     camera))
  (check-pict-renderer-list 'render-frame-indices! renderers)
  (unless (boolean? clean?)
    (raise-argument-error 'render-frame-indices! "boolean?" clean?))
  (unless (exact-positive-integer? workers)
    (raise-argument-error 'render-frame-indices! "exact-positive-integer?" workers))
  (unless (exact-positive-integer? supersample)
    (raise-argument-error 'render-frame-indices! "exact-positive-integer?" supersample))
  (make-directory* output-directory)
  (when clean?
    (delete-old-frames! output-directory))
  (define before-counters
    (default-pict-renderer-cache-counters renderers))
  (define started-at (current-inexact-milliseconds))
  ;; Prepare positions for every selected frame before any renderer workers are
  ;; created. Prepared flow particles then read immutable coordinates instead of
  ;; calling an arbitrary author ODE procedure concurrently from worker threads.
  (define ode-frame-samples
    (prepare-ode-frame-samples
     (for/list ([frame-index (in-list frame-indices)])
       (scene-sample scene
                     (frame-index->time frame-index #:fps fps)))))
  (define ode3d-frame-samples
    (prepare-ode3d-frame-samples
     (for/list ([frame-index (in-list frame-indices)])
       (scene-sample scene
                     (frame-index->time frame-index #:fps fps)))))
  (define-values (paths frame-milliseconds active-workers)
    (render-frame-index-jobs! scene
                              frame-indices
                              output-directory
                              fps
                              camera
                              renderers
                              workers
                              supersample
                              ode-frame-samples
                              ode3d-frame-samples))
  (define after-counters
    (default-pict-renderer-cache-counters renderers))
  (render-diagnostics
   paths
   (length frame-indices)
   active-workers
   (- (current-inexact-milliseconds) started-at)
   frame-milliseconds
   (- (renderer-cache-counters-hits after-counters)
      (renderer-cache-counters-hits before-counters))
   (- (renderer-cache-counters-misses after-counters)
      (renderer-cache-counters-misses before-counters))
   (- (renderer-cache-counters-evictions after-counters)
      (renderer-cache-counters-evictions before-counters))
   animate-version
   animate-stage))

; render-frame-index-jobs! : scene? (listof exact-nonnegative-integer?)
;                            path-string? exact-positive-integer?
;                            (or/c camera? false/c) (listof pict-renderer?)
;                            exact-positive-integer?
;                            -> (values (listof path?)
;                                       (listof nonnegative-real?)
;                                       exact-nonnegative-integer?)
;; Runs independent frame render/write jobs through a bounded worker pool. On
;; Racket versions with parallel thread pools, workers build bitmaps in parallel
;; and hand them to one ordinary thread for PNG encoding. The latter is needed
;; because racket/draw's PNG/JPEG encoders use C callbacks that cannot run in a
;; parallel thread. Each job owns a unique local output filename, while returned
;; lists are rebuilt in the requested global-frame order after all work ends.
(define (render-frame-index-jobs! scene frame-indices output-directory fps camera renderers workers
                                  supersample ode-frame-samples ode3d-frame-samples)
  (define frame-count
    (length frame-indices))
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
  (define (render-one->pending-frame local-index)
    (define source-index
      (list-ref frame-indices local-index))
    (define path (frame-index->path output-directory local-index))
    (define started-at (current-inexact-milliseconds))
    (define bitmap
      (call-with-ode-frame-samples
       ode-frame-samples
       (lambda ()
         (call-with-ode3d-frame-samples
          ode3d-frame-samples
          (lambda ()
            (scene-frame->bitmap scene
                                 source-index
                                 #:fps fps
                                 #:camera camera
                                 #:renderers renderers
                                 #:supersample supersample))))))
    (pending-frame local-index path bitmap started-at))
  (define (save-pending-frame! pending)
    (define path (pending-frame-path pending))
    (define bitmap (pending-frame-bitmap pending))
    (unless (send bitmap save-file path 'png)
      (raise-arguments-error
       'render-frames!
       "could not save a PNG frame"
       "path" path))
    (define local-index (pending-frame-local-index pending))
    (vector-set! paths local-index path)
    (vector-set! durations
                 local-index
                 (- (current-inexact-milliseconds)
                    (pending-frame-started-at pending))))
  (define (render-one! local-index)
    (save-pending-frame!
     (render-one->pending-frame local-index)))
  (define (regular-worker)
    (let loop ()
      (define local-index (take-frame-index!))
      (when local-index
        (with-handlers ([exn:fail? record-failure!])
          (render-one! local-index))
        (loop))))
  (cond
    [(parallel-frame-rendering-available? active-workers)
     (define output-channel (make-channel))
     ;; Keep all image-codec calls on an ordinary thread. A save failure is
     ;; recorded, but the writer continues draining the channel so that render
     ;; workers cannot be stranded in channel-put.
     (define saver-thread
       (thread
        (lambda ()
          (let loop ()
            (define pending (channel-get output-channel))
            (unless (eq? pending 'done)
              (with-handlers ([exn:fail? record-failure!])
                (save-pending-frame! pending))
              (loop))))))
     (define (parallel-worker)
       (let loop ()
         (define local-index (take-frame-index!))
         (when local-index
           (with-handlers ([exn:fail? record-failure!])
             (channel-put
              output-channel
              (render-one->pending-frame local-index)))
           (loop))))
     (define pool
       (make-parallel-thread-pool/proc active-workers))
     (define worker-threads
       (for/list ([_ (in-range active-workers)])
         (keyword-apply thread
                        '(#:pool)
                        (list pool)
                        (list parallel-worker))))
     ;; No further workers belong to this fixed pool. Closing it now preserves
     ;; the pool's workers until they finish, then lets its resources go away.
     (parallel-thread-pool-close/proc pool)
     (for ([worker-thread (in-list worker-threads)])
       (thread-wait worker-thread))
     (channel-put output-channel 'done)
     (thread-wait saver-thread)]
    [else
     (define worker-threads
       (for/list ([_ (in-range active-workers)])
         (thread regular-worker)))
     (for ([worker-thread (in-list worker-threads)])
       (thread-wait worker-thread))])
  (when first-failure
    (raise first-failure))
  (values (vector->list paths)
          (vector->list durations)
          active-workers))

;; parallel-frame-rendering-available? : exact-nonnegative-integer? -> boolean?
;; Creating a pool only helps when more than one frame worker exists. Racket
;; 8.12 does not provide the two dynamically loaded procedures, so it follows
;; the regular-worker branch above unchanged.
(define (parallel-frame-rendering-available? active-workers)
  (and (> active-workers 1)
       make-parallel-thread-pool/proc
       parallel-thread-pool-close/proc))

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
