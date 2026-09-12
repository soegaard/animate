#lang racket/base

;; One launcher for all examples or a single named example. Runs each requested
;; review in its own ordinary Racket process, one at a time. A completed example
;; remains available if a later example fails. No FFmpeg or external ZIP tool.
(require racket/cmdline racket/runtime-path racket/system racket/path racket/file
         "examples/private/review-example-names.rkt")
(provide run-geometry-reviews)
(define-runtime-path examples-directory "examples")

(define (run-geometry-reviews)
  (define selection #f)
  (define list? #f)
  (define theme "light") (define theme-set? #f)
  (define output-root "geometry-review")
  (define width 1280) (define height 720) (define supersample 1) (define fps 30)
  (define contact-sheet? #t) (define captions? #t) (define expanded? #t)
  (define include-cleanup? #f)
  (define (select! value)
    (when selection (error 'review-examples "choose only one of --all, --library, --example"))
    (set! selection value))
  (define (theme! value)
    (when theme-set? (error 'review-examples "choose only one of --light, --dark, --both"))
    (set! theme-set? #t) (set! theme value))
  (define (positive text flag)
    (define n (string->number text))
    (unless (exact-positive-integer? n) (error 'review-examples "~a expects a positive integer" flag)) n)
  (command-line
   #:program "geometry/review-examples.rkt"
   #:once-each
   [("--all") "Review all 19 examples, including transformations, semantic labels, and gallery." (select! 'all)]
   [("--library") "Review only the 13 standard-library application examples." (select! 'library)]
   [("--example") name "Review one named example; use --list for available names." (select! name)]
   [("--list") "List example names without rendering." (set! list? #t)]
   [("--light") "Light theme (default)." (theme! "light")]
   [("--dark") "Dark theme." (theme! "dark")]
   [("--both") "Review each selected example in light and dark themes." (theme! "both")]
   [("--output") dir "Root directory, default geometry-review." (set! output-root dir)]
   [("--width") n "Image width, default 1280 pixels." (set! width (positive n "--width"))]
   [("--height") n "Image height, default 720 pixels." (set! height (positive n "--height"))]
   [("--fps") n "Reference movie FPS recorded in metadata, default 30." (set! fps (positive n "--fps"))]
   [("--supersample") n "Raster multiplier, default 1." (set! supersample (positive n "--supersample"))]
   [("--no-contact-sheet") "Omit overview contact sheets." (set! contact-sheet? #f)]
   [("--no-captions") "Omit on-image captions; still include step text in the bundle." (set! captions? #f)]
   [("--top-level-only") "Only authored outer steps, without separate expanded helper rows." (set! expanded? #f)]
   [("--include-cleanup") "Include silent cleanup/no-op rows (omitted by default)." (set! include-cleanup? #t)]
   #:args () (void))
  (cond
    [list?
     (when selection (error 'review-examples "--list cannot be combined with a selection"))
     (for ([name (in-list review-example-names)]) (displayln name))
     0]
    [else
     (define names (select-review-examples selection))
     (define modes (if (equal? theme "both") '("light" "dark") (list theme)))
     (define root (path->complete-path output-root))
     (define executable (or (find-executable-path (find-system-path 'exec-file))
                            (find-system-path 'exec-file)))
     (let/ec stop
       (for* ([mode (in-list modes)] [name (in-list names)])
         (define dir (build-path root mode name))
         (define archive (build-path root mode (string-append name ".zip")))
         (printf "\nReviewing ~a / ~a\n" name mode) (flush-output)
         (define args
           (append (list (build-path examples-directory (string-append name ".rkt"))
                         (string-append "--" mode)
                         "--review-stills" dir "--review-zip" archive
                         "--width" (number->string width) "--height" (number->string height)
                         "--fps" (number->string fps) "--supersample" (number->string supersample))
                   (if contact-sheet? '() '("--no-contact-sheet"))
                   (if captions? '() '("--no-captions"))
                   (if expanded? '() '("--review-top-level-only"))
                   (if include-cleanup? '("--review-include-cleanup") '())))
         (define code (apply system*/exit-code executable args))
         (unless (zero? code)
           (eprintf "Review failed: ~a / ~a. Earlier bundles have been kept.\n" name mode)
           (stop code)))
       (printf "\nCreated ~a review bundles under ~a\n" (* (length names) (length modes)) root)
       0)]))

(module+ main (exit (run-geometry-reviews)))
