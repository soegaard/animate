#lang racket/base

;; --list stays a data-only operation. Load the effectful gallery renderer only
;; after validating the user's selection and output options.
(require racket/cmdline racket/runtime-path "gallery.rkt")
(define-runtime-path renderer "private/gallery/render.rkt")
(module+ main
  (define list? #f) (define ids '()) (define category #f)
  (define theme 'light) (define fmt 'widescreen) (define motion 'normal)
  (define videos? #f) (define workers 1) (define fps 30) (define width 960)
  (define repeat 2) (define in-process? #f) (define zip? #t)
  (define (integer text who)
    (define n (string->number text))
    (unless (exact-positive-integer? n) (raise-user-error who "expected a positive integer")) n)
  (define output
    (command-line #:program "slides/run-gallery.rkt"
      #:once-each
      [("--list") "List entries; do not render or load optional engines" (set! list? #t)]
      [("--category") name "layouts, transitions, or integration" (set! category (string->symbol name))]
      [("--format") name "widescreen, standard, portrait, or square" (set! fmt (string->symbol name))]
      [("--videos" "--mp4") "Also render a playable MP4 for each selected example" (set! videos? #t)]
      [("--workers") n "Shared frame-worker capacity, including geometry" (set! workers (integer n 'workers))]
      [("--fps") n "Video frame rate" (set! fps (integer n 'fps))]
      [("--width") n "Output width; height is derived from the selected format" (set! width (integer n 'width))]
      [("--repeat") n "Repeat static samples and check their pixels" (set! repeat (integer n 'repeat))]
      [("--reduced-motion") "Replace spatial transitions with same-duration crossfades" (set! motion 'reduced)]
      [("--in-process") "Render all videos in-process" (set! in-process? #t)]
      [("--no-zip") "Do not create a review ZIP" (set! zip? #f)]
      #:once-any
      [("--light") "Use the light lecture theme (default)" (set! theme 'light)]
      [("--dark") "Use the dark lecture theme" (set! theme 'dark)]
      #:multi
      [("--entry") name "Select an entry; repeat to choose several" (set! ids (cons (string->symbol name) ids))]
      #:args ([directory "slides-output/gallery"]) directory))
  (unless (memq fmt '(widescreen standard portrait square))
    (raise-user-error 'run-gallery "unknown format: ~a" fmt))
  (define selected (select-slide-gallery-entries #:entries (and (pair? ids) (reverse ids)) #:category category))
  (cond
    [list?
     (for ([e (in-list selected)])
       (printf "~a\t~a\t~a~a\n" (slide-gallery-entry-id e) (slide-gallery-entry-category e)
               (slide-gallery-entry-title e)
               (if (null? (slide-gallery-entry-requirements e)) ""
                   (format " [~a]" (slide-gallery-entry-requirements e)))))]
    [else
     (exit
      ((dynamic-require renderer 'render-slide-gallery!) selected output
       #:theme theme #:format fmt #:motion motion #:videos? videos? #:workers workers
       #:fps fps #:width width #:repeat repeat #:in-process? in-process? #:zip? zip?))]))
