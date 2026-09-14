#lang racket/base

;;;
;;; Mathematical Example Command Line
;;;
;; Separates lesson declarations from explicit inspection, cache preparation, frame
;; rendering, and video encoding.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  racket/cmdline
  (only-in racket/file make-directory*)
  racket/list
  (only-in racket/runtime-path define-runtime-path)
  (for-syntax racket/base)
  (only-in racket/string string-join string-replace string-split)
  "../../main.rkt"
  "../../render.rkt"
  (only-in "../../private/presentation.rkt" select-case-plan)
  "../../private/native.rkt")

;; Exports
(provide run-math-example!)

;;;
;;; Construction and Operations
;;;
; render-module : path?
;;   Locates the parent animate rendering module without loading it during lesson
;;   construction.
(define-runtime-path render-module "../../../render.rkt")

; positive-number : symbol? any/c [#:integer? any/c] -> positive-real?
;;   Parses and validates a positive numeric command-line argument.
(define (positive-number who text #:integer? [integer? #f])
  (define n (string->number text))
  (unless (and (real? n) (> n 0) (< n +inf.0) (or (not integer?) (exact-integer? n)))
    (raise-user-error who
      "expected a finite positive ~a, got ~s"
      (if integer? "integer" "number")
      text))
  n)

; run-math-example! : any/c symbol? -> void?
;;   Runs checkpoint inspection or explicitly requested native rendering for one lesson.
(define (run-math-example! original-plan name)
  (define steps? #f)
  (define list-cases? #f)
  (define case-path #f)
  (define theme 'light)
  (define fps 30)
  (define workers 1)
  (define width 1280)
  (define height 720)
  (define supersample 1)
  (define video #f)
  (define output #f)
  (command-line
    #:program name
    #:once-each
    [("--steps")
     "Print held S-expressions and TeX checkpoints; do not render."
     (set! steps? #t)]
    [("--list-cases") "List selectable case paths; do not render." (set! list-cases? #t)]
    [("--case")
     path
     "Select a case, for example quadratic/two-real-roots."
     (set! case-path (map string->symbol (string-split path "/")))]
    [("--dark") "Use the dark presentation." (set! theme 'dark)]
    [("--light") "Use the light presentation." (set! theme 'light)]
    [("--fps") value "Output frames per second." (set! fps (positive-number name value))]
    [("--workers")
     value
     "Native parallel frame workers."
     (set! workers (positive-number name value #:integer? #t))]
    [("--width")
     value
     "Output width in pixels."
     (set! width (positive-number name value #:integer? #t))]
    [("--height")
     value
     "Output height in pixels."
     (set! height (positive-number name value #:integer? #t))]
    [("--supersample")
     value
     "Native supersampling factor."
     (set! supersample (positive-number name value #:integer? #t))]
    [("--mp4")
     path
     "Also encode an MP4 at this path using native animate/render."
     (set! video path)]
    #:args ([directory #f])
    (set! output (or directory (build-path "math-output" name))))
  (define plan (if case-path (select-case-plan original-plan case-path) original-plan))
  (define segments (presentation-plan-segments plan))
  (cond
    [list-cases?
     (for ([s (in-list segments)] #:unless (plan-segment-shared? s))
       (displayln
         (if (null? (plan-segment-path s))
           "(single derivation)"
           (string-join (map symbol->string (plan-segment-path s)) "/"))))]
    [steps?
     (for ([segment (in-list segments)])
       (printf "\nCase ~s\n" (plan-segment-path segment))
       (define d (plan-segment-derivation segment))
       (for ([state (in-list (derivation-states d))]
              [label (in-list (cons 'initial (map rewrite-step-name (derivation-steps d))))])
         (printf "~a\n  ~s\n  ~a\n" label (math-datum state) (math->tex state))))
     (printf "\nPresentation duration: ~a seconds.\n" (plan-duration plan))]
    [else
     (define camera
       ((native 'animate 'make-camera)
         #:width width
         #:height height
         #:background (if (eq? theme 'dark) "#121620" "#FFFFFF")))
     (define scn
       (math-plan->scene! plan
         #:theme theme
         #:camera camera
         #:title (string-replace name "-" " ")))
     (make-directory* output)
     (define render-frames! (dynamic-require render-module 'render-frames!))
     (define frames
       (render-frames! scn output #:fps fps #:workers workers #:supersample supersample))
     (printf "Rendered ~a frames to ~a\n" (length frames) output)
     (when video
       (define-values (parent base directory?) (split-path (path->complete-path video)))
       (when (path? parent) (make-directory* parent))
       ((dynamic-require render-module 'encode-mp4!) output video #:fps fps)
       (printf "Wrote ~a\n" video))]))
