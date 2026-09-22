#lang racket/base

;;;
;;; Inline TeX Review Runner
;;;

;; Produces one browsable, portable review of the shared inline-TeX feature.
;; It uses the normal slide and calculus preparation/project paths.

(require file/zip
         json
         racket/cmdline
         racket/class
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         (only-in pict pict->bitmap pict-width filled-rectangle colorize pin-over)
         "../project.rkt"
         "../render.rkt"
         "../calculus/render.rkt"
         "../calculus/examples/differential-quotient-x-squared.rkt"
         "main.rkt"
         "pict.rkt"
         "render.rkt"
         "project.rkt"
         "private/data.rkt"
         "private/sample.rkt"
         "private/project-artifacts.rkt")

(define-runtime-path review-source "examples/inline-tex-review.rkt")

(define (positive-integer text who)
  (define value (string->number text))
  (unless (exact-positive-integer? value)
    (raise-user-error who "expected a positive integer: ~a" text))
  value)

(define (save-picture! path picture)
  (define bitmap (pict->bitmap picture))
  (unless (send bitmap save-file path 'png)
    (raise-user-error 'run-inline-tex-review "could not write ~a" path)))

(define (add-baselines picture prepared)
  (define frame (sample-slide prepared 0))
  (define slide-format (prepared-slide-value-format prepared))
  (define scale (/ (pict-width picture) (slide-format-width slide-format)))
  (for/fold ([result picture])
            ([leaf (in-list (frame-value-leaves frame))])
    (define box (frame-leaf-box leaf))
    (define baseline
      (+ (box-value-y box)
         (asset-baseline (frame-leaf-asset leaf))))
    (pin-over result
              (* scale (box-value-x box))
              (* scale baseline)
              (colorize
               (filled-rectangle (max 1 (* scale (box-value-width box))) 2)
               "magenta"))))

(define (write-index! directory records video)
  (call-with-output-file (build-path directory "index.html") #:exists 'error
    (lambda (out)
      (display
       "<!doctype html><meta charset='utf-8'><title>Animate inline TeX review</title><style>body{font:16px/1.5 system-ui;margin:2rem auto;max-width:1200px;background:#151922;color:#edf2f7}a{color:#8bd5ff}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:1rem}.card{background:#222936;padding:1rem;border-radius:10px}.card img,video{max-width:100%;height:auto;border-radius:4px}code{background:#303948;padding:.1rem .25rem}</style><h1>Animate inline TeX review</h1><p>Expected: prose retains its selected slide role; TeX shares each line baseline; display formulae occupy their own line; magenta rules show prepared text baselines; dark math remains legible. The calculus frames use the actual x squared lesson.</p><p><a href='manifest.json'>Environment metadata and artifacts</a></p>"
       out)
      (when video
        (fprintf out "<h2>Prepared-project transition</h2><video controls src='~a'></video>" video))
      (display "<h2>Stills and overlays</h2><div class='grid'>" out)
      (for ([record (in-list records)])
        (fprintf out "<article class='card'><h3>~a</h3><img src='~a' alt='~a'></article>"
                 (hash-ref record 'label) (hash-ref record 'path) (hash-ref record 'label)))
      (display "</div></html>" out))))

(module+ main
  (define workers 2)
  (define fps 12)
  (define include-video? #t)
  (define output
    (command-line
     #:program "slides/run-inline-tex-review.rkt"
     #:once-each
     [("--workers") count "Project workers for the transition movie"
                    (set! workers (positive-integer count 'workers))]
     [("--fps") count "Frame rate for the transition movie"
                (set! fps (positive-integer count 'fps))]
     [("--no-video") "Skip only the MP4; stills and the review archive remain"
                     (set! include-video? #f)]
     #:args (directory) directory))
  (define directory (simplify-path (path->complete-path output) #f))
  (define archive (string->path (string-append (path->string directory) ".zip")))
  (when (or (file-exists? directory) (directory-exists? directory) (file-exists? archive))
    (raise-user-error 'run-inline-tex-review
                      "choose a fresh review directory and archive: ~a" directory))
  (make-directory* directory)
  (make-directory* (build-path directory "stills"))
  (make-directory* (build-path directory "calculus"))
  (make-directory* (build-path directory "video"))
  (make-directory* (build-path directory "_work"))
  (define records '())
  (define (record! label relative picture)
    (save-picture! (build-path directory relative) picture)
    (set! records (append records (list (hash 'label label 'path relative)))))
  (define review-film (dynamic-require review-source 'inline-tex-review-film))
  (for* ([theme (in-list (list lecture-light lecture-dark))]
         [slide-format (in-list (list widescreen portrait))])
    (define prepared (prepare-storyboard! (storyboard-with-format
                                           (storyboard-with-theme review-film theme)
                                           slide-format)))
    (define ratio (/ (slide-format-width slide-format)
                     (slide-format-height slide-format)))
    (define width
      (* (numerator ratio)
         (inexact->exact (ceiling (/ 960 (numerator ratio))))))
    (define height (/ width ratio))
    (define picture (storyboard->pict prepared #:at 1/2 #:size (list width height)))
    (record! (format "~a / ~a" (slide-theme-id theme) (slide-format-id slide-format))
             (format "stills/~a-~a.png" (slide-theme-id theme) (slide-format-id slide-format))
             picture)
    (record! (format "~a / ~a / baseline overlay"
                     (slide-theme-id theme) (slide-format-id slide-format))
             (format "stills/~a-~a-baselines.png"
                     (slide-theme-id theme) (slide-format-id slide-format))
             (add-baselines picture
                            (prepared-clip-value-slide
                             (prepared-shot-clip
                              (car (prepared-storyboard-value-shots prepared)))))))
  (define calculus-prepared
    (prepare-calculus-lesson differentiate-x-squared #:width 960 #:height 540))
  (define calculus-plan (prepared-lesson-plan calculus-prepared))
  (define calculus-duration (calculus-plan-duration calculus-plan))
  (for ([sample (in-list (list (cons "initial" 'initial)
                                (cons "middle" (/ calculus-duration 2))
                                (cons "final" 'final)))])
    (record! (string-append "x squared calculus lesson / " (car sample))
             (format "calculus/x-squared-~a.png" (car sample))
             (prepared-lesson->pict calculus-prepared #:at (cdr sample))))
  (define video #f)
  (define project-diagnostics #f)
  (when include-video?
    (define film (dynamic-require review-source 'inline-tex-review-film))
    (define project
      (animate-project
       #:id 'inline-tex-review-movie
       #:source (make-storyboard-source review-source 'inline-tex-review-film)
       #:render (render-spec #:fps fps #:width 960 #:height 540
                             #:workers workers #:worker-mode 'auto
                             #:theme (slide-theme-colors (storyboard-theme film))
                             #:typography (slide-theme-typography (storyboard-theme film)))
       #:output (output-spec #:root (build-path directory "_work")
                             #:name "inline-tex-review" #:format 'mp4)
       #:encoder (encoder-spec #:codec 'h264)
       #:cache (cache-spec #:root (build-path directory "_work" "cache")
                            #:policy 'off)))
    (define report (render-project! project))
    (set! project-diagnostics (project-execution-report-diagnostics report))
    (define rendered (project-primary-artifact-path
                      (project-execution-report-artifact-paths report)))
    (set! video "video/inline-tex-transition.mp4")
    (copy-file rendered (build-path directory video)))
  (call-with-output-file (build-path directory "manifest.json") #:exists 'error
    (lambda (out)
      (write-json
       (hash 'schema "animate-inline-tex-review-v1"
             'racket (version)
             'backend "latex-pict via Animate formula Pict renderer"
             'workers-requested workers
             'workers-started
             (and project-diagnostics
                  (project-frame-execution-diagnostics-workers-started
                   project-diagnostics))
             'video video
             'records records)
       out)))
  (write-index! directory records video)
  (define archive-paths
    (append (list (build-path directory "index.html")
                  (build-path directory "manifest.json"))
            (find-files file-exists? (build-path directory "stills"))
            (find-files file-exists? (build-path directory "calculus"))
            (find-files file-exists? (build-path directory "video"))))
  (parameterize ([current-directory (path-only directory)])
    (apply zip archive
           (map (lambda (path) (find-relative-path (path-only directory) path))
                archive-paths)))
  (printf "Review: ~a\nArchive: ~a\n" directory archive))
