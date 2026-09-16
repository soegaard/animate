#lang racket/base
;; Generic runner. Authoring modules contain no command-line or rendering effects.
(require racket/cmdline racket/path racket/runtime-path racket/file
         animate/project animate/render
         "main.rkt" "render.rkt" "scene.rkt" "project.rkt")
(module+ main
(define-runtime-path here ".")
(define workers 1) (define fps 30) (define width 1280) (define height 720)
(define mode 'mp4) (define output "slides-output/videos") (define in-process? #f)
(define (positive-integer text who)
  (define n (string->number text))
  (unless (exact-positive-integer? n) (raise-user-error who "expected a positive integer: ~a" text)) n)
(define file
  (command-line #:program "slides/render-example.rkt"
   #:once-each
   [("--workers") n "Number of shared frame workers" (set! workers (positive-integer n 'workers))]
   [("--fps") n "Output frame rate" (set! fps (positive-integer n 'fps))]
   [("--width") n "Output width" (set! width (positive-integer n 'width))]
   [("--height") n "Output height" (set! height (positive-integer n 'height))]
   [("--frames") "Write PNG frames without MP4 encoding" (set! mode 'png-sequence)]
   [("--in-process") "Prepare directly; needed for geometry content in this release" (set! in-process? #t)]
   [("--output") path "Output root directory" (set! output path)]
   #:args (source) source))
(define module (path->complete-path file))
(define film (dynamic-require module 'film))
(unless (storyboard? film) (raise-user-error 'render-example "module must export a storyboard named film"))
;; Avoid private representation access: source's first bound shot is not an
;; appearance accessor. The public storyboard-theme accessor provides it.
(define theme (storyboard-theme film))
(define source
  (if in-process?
      (timeline-source (storyboard->timeline (prepare-storyboard! film #:asset-base (path-only module))
                                             #:size (list width height)))
      (make-storyboard-source module 'film)))
(define name (path->string (path-replace-extension (file-name-from-path module) #"")))
(define project
  (animate-project #:id (storyboard-id film) #:source source
    #:render (render-spec #:fps fps #:width width #:height height #:workers workers
                          #:worker-mode (if in-process? 'in-process 'auto)
                          #:theme (slide-theme-colors theme) #:typography (slide-theme-typography theme))
    #:output (output-spec #:root output #:name name #:format mode)
    #:encoder (encoder-spec #:codec (if (eq? mode 'mp4) 'h264 'none))
    #:cache (cache-spec #:policy 'off)))
(define report (render-project! project))
(for ([path (in-list (project-execution-report-artifact-paths report))]) (displayln path))

)
