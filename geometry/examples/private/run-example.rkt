#lang racket/base

(require racket/cmdline racket/pretty
         (prefix-in native-colors: "../../../colors.rkt")
         "../../main.rkt" "../../render.rkt")
(provide run-geometry-example)

;; No GUI side effects on require. Invoked only from an example's main submodule.
;; factory accepts the output aspect and returns an immutable geometry timeline.
(define (run-geometry-example name factory)
  (define frames? #f)
  (define describe? #f)
  (define captions? #t)
  (define mp4 #f)
  (define fps 30)
  (define width 1280)
  (define height 720)
  (define supersample 1)
  (define destination #f)
  (define theme-mode 'light)
  (define native-color-theme native-colors:animate-light-theme)
  (define (positive-integer text option)
    (define n (string->number text))
    (unless (exact-positive-integer? n) (error name "~a expects a positive integer, received ~e" option text))
    n)
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
   #:args ([directory #f])
   (set! destination (or directory (build-path "geometry-output" name))))
  (define aspect (/ width height))
  (define timeline
    (cond [(procedure-arity-includes? factory 2) (factory aspect theme-mode)]
          [(procedure-arity-includes? factory 1) (factory aspect)]
          [else (error name "factory must accept 1 or 2 arguments")]))
  (cond [describe?
         (printf "~a: ~a seconds\n" name (geometry-timeline-duration timeline))
         (pretty-write (geometry-realization-diagnostics (geometry-timeline-realization timeline)))
         (pretty-write (geometry-realization-choices (geometry-timeline-realization timeline)))]
        [else
         (define paths
           (if frames?
               (render-geometry-frames! timeline destination #:width width #:height height
                                        #:fps fps #:supersample supersample #:captions? captions?
                                        #:color-theme native-color-theme #:mp4 mp4)
               (render-geometry-stills! timeline destination #:width width #:height height
                                        #:fps fps #:supersample supersample #:captions? captions?
                                        #:color-theme native-color-theme)))
         (printf "Wrote ~a ~a to ~a\n" (length paths) (if frames? "frames" "step stills") destination)
         (when mp4 (printf "Encoded ~a\n" mp4))]))
