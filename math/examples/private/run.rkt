#lang racket/base

;;;
;;; Mathematical Example Command Line
;;;
;; Keeps derivation inspection independent of native rendering and defers the
;; shared project executor until the author requests frames or a movie.

;;;
;;; Imports and Exports
;;;
;; Imports
(require (only-in racket/cmdline command-line)
         (only-in racket/string string-join string-split)
         (only-in racket/lazy-require lazy-require)
         "../../main.rkt"
         (only-in "../../private/presentation.rkt" select-case-plan))
(lazy-require ["project-render.rkt" (render-math-example!)])

;; Exports
(provide run-math-example!)

;;;
;;; Argument Validation and Inspection
;;;
; positive-integer : symbol? string? -> exact-positive-integer?
;;   Parses the integer frame-grid quantities accepted by the shared executor.
(define (positive-integer who text)
  (define n (string->number text))
  (unless (exact-positive-integer? n)
    (raise-user-error who "expected a positive integer, got ~s" text))
  n)

; print-move-tree! : derivation? -> void?
;;   Prints semantic move structure and evidence without native loading or typesetting.
(define (print-move-tree! d)
  (define (walk node depth)
    (printf "~a~a  [~a; ~a]\n"
            (make-string (* depth 2) #\space)
            (string-join (map symbol->string (derivation-node-path node)) "/")
            (derivation-node-relation node)
            (verification-status (derivation-node-verification node)))
    (for ([child (in-list (derivation-node-children node))])
      (walk child (add1 depth))))
  (for ([node (in-list (derivation-tree d))]) (walk node 0)))

; run-math-example! : presentation-plan? string? -> void?
;;   Runs checkpoint inspection or explicitly requested native rendering for one lesson.
(define (run-math-example! original-plan name)
  (define steps? #f)
  (define tree? #f)
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
    [("--tree") "Print the mathematical move hierarchy; do not render." (set! tree? #t)]
    [("--list-cases") "List selectable case paths; do not render." (set! list-cases? #t)]
    [("--case")
     path
     "Select a case, for example quadratic/two-real-roots."
     (set! case-path (map string->symbol (string-split path "/")))]
    [("--dark") "Use the dark presentation." (set! theme 'dark)]
    [("--light") "Use the light presentation." (set! theme 'light)]
    [("--fps") value "Output frames per second (a positive integer frame grid)."
                    (set! fps (positive-integer name value))]
    [("--workers")
     value
     "Shared renderer worker capacity; values above one use subprocess workers."
     (set! workers (positive-integer name value))]
    [("--width")
     value
     "Output width in pixels."
     (set! width (positive-integer name value))]
    [("--height")
     value
     "Output height in pixels."
     (set! height (positive-integer name value))]
    [("--supersample")
     value
     "Native supersampling factor."
     (set! supersample (positive-integer name value))]
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
    [tree?
     (for ([segment (in-list segments)])
       (printf "\nCase ~s~a\n" (plan-segment-path segment)
               (if (plan-segment-shared? segment) " (shared prefix)" ""))
       (print-move-tree! (plan-segment-derivation segment)))
     (printf "\nPresentation duration: ~a seconds.\n" (plan-duration plan))]
    [steps?
     (for ([segment (in-list segments)])
       (printf "\nCase ~s\n" (plan-segment-path segment))
       (define d (plan-segment-derivation segment))
       (for ([state (in-list (derivation-states d))]
              [label (in-list (cons '(initial) (derivation-step-paths d)))])
         (printf "~a\n  ~s\n  ~a\n" (string-join (map symbol->string label) "/")
                 (math-datum state) (math->tex state))))
     (printf "\nPresentation duration: ~a seconds.\n" (plan-duration plan))]
    [else
     (render-math-example! (string->symbol name) output
                           case-path theme fps workers width height supersample video)]))
