#lang racket/base

(require racket/cmdline racket/pretty racket/list racket/file racket/path racket/system racket/format
         (prefix-in native-colors: "../../../colors.rkt")
         (prefix-in output: "../../../render.rkt")
         "../../main.rkt" "../../render.rkt")
(provide run-geometry-example)

;; No GUI side effects on require. Invoked only from an example's main submodule.
;; factory accepts the output aspect and returns an immutable geometry timeline.

(define (positive-integer text option)
  (define n (string->number text))
  (unless (exact-positive-integer? n)
    (error 'run-geometry-example "~a expects a positive integer, received ~e" option text))
  n)

(define (nonnegative-integer text option)
  (define n (string->number text))
  (unless (exact-nonnegative-integer? n)
    (error 'run-geometry-example "~a expects a nonnegative integer, received ~e" option text))
  n)

(define (ensure-clean-frame-directory! directory)
  (make-directory* directory)
  (for ([entry (in-list (directory-list directory))])
    (define name (path->string (file-name-from-path entry)))
    (define path (build-path directory entry))
    (when (or (regexp-match? #rx"^frame-[0-9]+\\.png$" name)
              (member name '("narration.srt" "stills.tsv")))
      (when (file-exists? path) (delete-file path)))))

(define (directory-frame-paths directory)
  (sort (for/list ([entry (in-list (directory-list directory))]
                   #:when (regexp-match? #rx"^frame-[0-9]+\\.png$"
                                         (path->string (file-name-from-path entry))))
          (build-path directory entry))
        string<?
        #:key path->string))

(define (frame-index->destination-path directory frame-index)
  (build-path directory
              (format "frame-~a.png"
                      (~r frame-index #:min-width 6 #:pad-string "0"))))

(define (worker-frame-indices frame-count worker-id worker-count)
  (for/list ([i (in-range worker-id frame-count worker-count)]) i))

(define (make-timeline name factory width height theme-mode)
  (define aspect (/ width height))
  (cond [(procedure-arity-includes? factory 2) (factory aspect theme-mode)]
        [(procedure-arity-includes? factory 1) (factory aspect)]
        [else (error name "factory must accept 1 or 2 arguments")]))

(define (run-geometry-example name factory)
  (define frames? #f)
  (define describe? #f)
  (define captions? #t)
  (define mp4 #f)
  (define fps 30)
  (define width 1280)
  (define height 720)
  (define supersample 1)
  (define workers 10)
  (define destination #f)
  (define theme-mode 'light)
  (define native-color-theme native-colors:animate-light-theme)
  ;; Hidden worker-shard mode used by the parent example runner.
  (define shard-mode? #f)
  (define shard-id 0)
  (define shard-count 1)
  (command-line
   #:program name
   #:once-each
   [("--frames") "Render every frame (the default is one still per step)." (set! frames? #t)]
   [("--describe") "Print realization diagnostics without rendering." (set! describe? #t)]
   [("--no-captions") "Omit captions from the images; still write narration.srt." (set! captions? #f)]
   [("--mp4") path "Render frames and encode an MP4 using FFmpeg." (set! mp4 path) (set! frames? #t)]
   [("--light") "Use the animate light theme and matching geometry palette (default)."
                 (set! theme-mode 'light)
                 (set! native-color-theme native-colors:animate-light-theme)]
   [("--dark") "Use the animate dark theme and matching geometry palette."
                (set! theme-mode 'dark)
                (set! native-color-theme native-colors:animate-dark-theme)]
   [("--fps") n "Frame rate, default 30." (set! fps (positive-integer n "--fps"))]
   [("--width") n "Output width in pixels, default 1280." (set! width (positive-integer n "--width"))]
   [("--height") n "Output height in pixels, default 720." (set! height (positive-integer n "--height"))]
   [("--supersample") n "Native render supersampling factor, default 1." (set! supersample (positive-integer n "--supersample"))]
   [("--workers") n "Worker processes for full-frame rendering, default 10."
                    (set! workers (positive-integer n "--workers"))]
   [("--worker-shard") "Internal use only: render only one shard of the frame indices."
                       (set! shard-mode? #t) (set! frames? #t)]
   [("--shard-id") n "Internal use only." (set! shard-id (nonnegative-integer n "--shard-id"))]
   [("--shard-count") n "Internal use only." (set! shard-count (positive-integer n "--shard-count"))]
   #:args ([directory #f])
   (set! destination (or directory (build-path "geometry-output" name))))

  (define timeline (make-timeline name factory width height theme-mode))

  (define (run-worker-shard!)
    (unless (< shard-id shard-count)
      (error name "shard id ~a must be less than shard count ~a" shard-id shard-count))
    (ensure-clean-frame-directory! destination)
    (define frame-count (geometry-frame-count timeline fps))
    (define indices (worker-frame-indices frame-count shard-id shard-count))
    (render-geometry-frame-indices! timeline indices destination
                                   #:width width #:height height #:fps fps
                                   #:supersample supersample #:captions? captions?
                                   #:color-theme native-color-theme)
    (printf "Shard ~a/~a wrote ~a frame~a to ~a\n"
            (add1 shard-id) shard-count (length indices)
            (if (= (length indices) 1) "" "s") destination))

  (define (run-process-sharded-render!)
    (define frame-count (geometry-frame-count timeline fps))
    (define actual-workers (min workers frame-count))
    (define staging-root (make-temporary-file "geometry-render-~a" 'directory))
    (define run-file
      (or (find-system-path 'run-file)
          (error name "cannot determine the current example file for worker rendering")))
    (define exec-file
      (or (find-executable-path (find-system-path 'exec-file))
          (find-system-path 'exec-file)
          (error name "cannot determine the current Racket executable")))
    (define render-start (current-inexact-milliseconds))
    (dynamic-wind
      void
      (lambda ()
        (define worker-directories
          (for/list ([id (in-range actual-workers)])
            (define dir (build-path staging-root (string-append "worker-" (~r id #:min-width 2 #:pad-string "0"))))
            (make-directory* dir)
            dir))
        (define results (make-vector actual-workers #f))
        (define threads
          (for/list ([id (in-range actual-workers)] [dir (in-list worker-directories)])
            (thread
             (lambda ()
               (define args
                 (append (list (path->string run-file)
                               "--worker-shard"
                               "--shard-id" (number->string id)
                               "--shard-count" (number->string actual-workers)
                               "--fps" (number->string fps)
                               "--width" (number->string width)
                               "--height" (number->string height)
                               "--supersample" (number->string supersample)
                               "--workers" "1")
                         (if captions? '() (list "--no-captions"))
                         (list (if (eq? theme-mode 'dark) "--dark" "--light")
                               (path->string dir))))
               (vector-set! results id (apply system* exec-file args))))))
        (for ([t (in-list threads)]) (thread-wait t))
        (unless (for/and ([result (in-vector results)]) result)
          (error name "one or more worker render processes failed"))
        (ensure-clean-frame-directory! destination)
        ;; render-frame-indices! deliberately names a selected shard locally as
        ;; frame-000000.png, frame-000001.png, ... .  Reconstruct the original
        ;; global frame index while merging so shards cannot overwrite each other.
        (for ([id (in-range actual-workers)]
              [dir (in-list worker-directories)])
          (define local-paths (directory-frame-paths dir))
          (define global-indices
            (worker-frame-indices frame-count id actual-workers))
          (unless (= (length local-paths) (length global-indices))
            (error name
                   "worker ~a produced ~a files for ~a assigned frames"
                   id (length local-paths) (length global-indices)))
          (for ([path (in-list local-paths)]
                [global-index (in-list global-indices)])
            (rename-file-or-directory
             path
             (frame-index->destination-path destination global-index)
             #f)))
        (write-geometry-subtitles! timeline (build-path destination "narration.srt"))
        (define elapsed (- (current-inexact-milliseconds) render-start))
        (define paths (directory-frame-paths destination))
        (unless (= (length paths) frame-count)
          (error name "merged ~a frames, expected ~a" (length paths) frame-count))
        (printf "Wrote ~a frames to ~a\n" (length paths) destination)
        (printf "Workers: requested ~a, actual ~a (separate Racket processes)\n"
                workers actual-workers)
        (printf "Render time: ~a ms\n" (inexact->exact (round elapsed)))
        (when mp4
          (output:encode-mp4! destination mp4 #:fps fps #:width width #:height height)
          (printf "Encoded ~a\n" mp4))
        (void))
      (lambda ()
        (when (directory-exists? staging-root)
          (delete-directory/files staging-root))))
    (void))

  (cond [describe?
         (printf "~a: ~a seconds\n" name (geometry-timeline-duration timeline))
         (pretty-write (geometry-realization-diagnostics (geometry-timeline-realization timeline)))
         (pretty-write (geometry-realization-choices (geometry-timeline-realization timeline)))
         (define plan (geometry-timeline->annotation-plan timeline #:width width
                                                          #:captions? captions?))
         (printf "Annotation metrics: ~a\n" (annotation-plan-metrics plan))
         (printf "Annotation warnings: ~a\n" (annotation-plan-warnings plan))
         (pretty-write (annotation-plan-labels plan))]
        [shard-mode?
         (run-worker-shard!)]
        [else
         (cond
           [frames?
            (printf "Rendering with ~a requested worker~a...\n"
                    workers (if (= workers 1) "" "s"))
            (if (= workers 1)
                (let* ([report (render-geometry-frames/report! timeline destination
                                                             #:width width #:height height
                                                             #:fps fps #:workers 1
                                                             #:supersample supersample
                                                             #:captions? captions?
                                                             #:color-theme native-color-theme
                                                             #:mp4 mp4)]
                       [paths (output:render-diagnostics-paths report)]
                       [actual-workers (output:render-diagnostics-workers report)])
                  (printf "Wrote ~a frames to ~a\n" (length paths) destination)
                  (printf "Workers: requested ~a, actual ~a\n" workers actual-workers)
                  (printf "Render time: ~a ms\n"
                          (inexact->exact (round (output:render-diagnostics-elapsed-milliseconds report))))
                  (when mp4 (printf "Encoded ~a\n" mp4)))
                (run-process-sharded-render!))]
           [else
            (define paths
              (render-geometry-stills! timeline destination #:width width #:height height
                                       #:fps fps #:supersample supersample #:captions? captions?
                                       #:color-theme native-color-theme))
            (printf "Wrote ~a step stills to ~a\n" (length paths) destination)])]))
