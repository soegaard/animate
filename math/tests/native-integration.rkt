#lang racket/base

;;;
;;; Actual Native Rendering Integration
;;;
;; Exercises actual animate, external typesetting, PNG output, and repeated-time
;; sampling. Run separately in a fully configured repository.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/class send)
  (only-in racket/file make-directory*)
  (only-in racket/list remove-duplicates)
  racket/string
  json
  "check.rkt"
  "../main.rkt"
  "../render.rkt"
  "../private/native.rkt"
  (prefix-in lc: "../examples/linear-concrete.rkt")
  (prefix-in lg: "../examples/linear-general.rkt")
  (prefix-in qc: "../examples/quadratic-concrete.rkt")
  (prefix-in qg: "../examples/quadratic-general.rkt"))

;; Exports
(provide run-native-integration!)

;;;
;;; Construction and Operations
;;;
; a : symbol? -> any/c
;;   Resolves a native animate binding at the adapter boundary.
(define (a name)
  (native 'animate name))

; snapshot : scene? nonnegative-real? -> (is-a?/c bitmap%)
;;   Rasterizes one actual native scene sample to a bitmap.
(define (snapshot scn t)
  (define state ((a 'scene-sample) scn t))
  (define camera ((a 'scene-camera-at) scn t))
  ((native 'pict 'pict->bitmap) ((a 'scene-state->pict) state #:camera camera)))

; bitmap-bytes : any/c -> bytes?
;;   Captures pixels from an actually rendered native bitmap.
(define (bitmap-bytes bitmap)
  (define bytes (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
  (send bitmap get-argb-pixels 0 0 (send bitmap get-width) (send bitmap get-height) bytes)
  bytes)

; active-phase-at : presentation-plan? nonnegative-real? -> (or/c #f scheduled-phase?)
;;   Identifies the active animation phase, not the last mathematical checkpoint.
(define (active-phase-at plan time)
  (for/first ([entry (in-list (plan-schedule plan))]
              #:when (and (positive? (scheduled-phase-duration entry))
                          (<= (scheduled-phase-start entry) time)
                          (< time (+ (scheduled-phase-start entry)
                                     (scheduled-phase-duration entry)))))
    entry))

; phase-probe-times : presentation-plan? -> (listof nonnegative-real?)
;;   Samples every transition family and the two atomic-replacement barriers.
(define (phase-probe-times plan)
  (for*/list ([entry (in-list (plan-schedule plan))]
               #:when (and (positive? (scheduled-phase-duration entry))
                           (not (memq (scheduled-phase-kind entry)
                                      '(hold checkpoint))))
               [fraction (in-list (if (eq? (scheduled-phase-kind entry) 'transition)
                                      '(1/4 9/20 1/2 11/20 3/4)
                                      '(1/4 1/2 3/4)))])
    (+ (scheduled-phase-start entry) (* fraction (scheduled-phase-duration entry)))))

; run-native-integration! : [path-string?] [#:theme (or/c 'light 'dark)]
;                           [#:dense? boolean?] -> void?
;;   Renders true native intermediate frames and checks seek-away/seek-back pixel equality.
(define (run-native-integration! [output "math-output/probes"]
                                #:theme [theme 'light]
                                #:dense? [dense? #t])
  (unless (memq theme '(light dark))
    (raise-argument-error 'run-native-integration! "'light or 'dark as #:theme" theme))
  (unless (boolean? dense?)
    (raise-argument-error 'run-native-integration! "boolean? as #:dense?" dense?))
  (unless (and (find-executable-path "latex") (find-executable-path "dvisvgm"))
    (raise-user-error 'native-integration
      "latex and dvisvgm must be on PATH (on macOS also check /Library/TeX/texbin)."))
  (make-directory* output)
  (define manifest '())
  (for ([plan (in-list (list lc:plan lg:plan qc:plan qg:plan))]
         [name
          (in-list '(linear-concrete linear-general quadratic-concrete quadratic-general))])
    (test-group
      (format "ACTUAL animate integration: ~a (~a)" name theme)
      (lambda ()
        (define prepared (prepare-math-plan! plan #:theme theme))
        (define scn (math-plan->scene! prepared #:title (symbol->string name)))
        (define total ((a 'scene-duration) scn))
        (check-close total (plan-duration plan) 1e-7 'duration)
        (define checkpoints (plan-checkpoints plan))
        (check-equal
          ((a 'scene-value-at) scn 'math-lesson.checkpoint total)
          (sub1 (vector-length checkpoints))
          'checkpoint-index)
        (define times
          (sort
            (remove-duplicates
              (append
                (list 0 (/ total 2) total)
                (for/list ([c (in-vector checkpoints)]) (math-checkpoint-time c))
                (if dense? (phase-probe-times plan) '())))
            <))
        (printf "  Rendering ~a probes across ~a seconds.\n" (length times) total)
        (for ([t (in-list times)] [i (in-naturals)])
          (define image (snapshot scn t))
          ;; Sampling never accumulates transformation/layout state.
          (snapshot scn (max 0 (- total t)))
          (check-equal (bitmap-bytes image) (bitmap-bytes (snapshot scn t))
                       (list 'random-access-pixels name t))
          (define filename (format "~a-~a.png" name i))
          (check-true (send image save-file (build-path output filename) 'png))
          (define cp (checkpoint-at plan t))
          (define phase (active-phase-at plan t))
          (define annotation (and phase
                                  (scheduled-phase-phase phase)
                                  (presentation-phase-annotation
                                    (scheduled-phase-phase phase))))
          (set! manifest
            (cons
              (hash 'file filename
                    'time (exact->inexact t)
                    'exact-time (format "~s" t)
                    'theme (symbol->string theme)
                    'step (format "~a" (if phase (scheduled-phase-step phase)
                                            (math-checkpoint-step cp)))
                    'phase (if phase (symbol->string (scheduled-phase-kind phase)) "finished")
                    'phase-progress (if phase
                                      (exact->inexact
                                        (/ (- t (scheduled-phase-start phase))
                                           (scheduled-phase-duration phase)))
                                      1.0)
                    'checkpoint-step (format "~a" (math-checkpoint-step cp))
                    'case (format "~s" (math-checkpoint-case-path cp))
                    'datum (format "~s" (math-datum (math-checkpoint-state cp)))
                    'inset (if annotation (format "~s" (math-datum (car annotation))) #f))
              manifest))))))
  (call-with-output-file
    (build-path output "manifest.json")
    #:exists 'truncate/replace
    (lambda (out) (write-json (reverse manifest) out)))
  (report!))

(module+ main
  (require racket/cmdline)
  (define output "math-output/probes")
  (define theme 'light)
  (define dense? #t)
  (command-line
    #:once-each
    ["--dark" "Render on a dark background." (set! theme 'dark)]
    ["--checkpoints-only" "Skip dense transition frames." (set! dense? #f)]
    #:args ([directory output]) (set! output directory))
  (run-native-integration! output #:theme theme #:dense? dense?))
