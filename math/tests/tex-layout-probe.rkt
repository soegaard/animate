#lang racket/base

;;;
;;; TeX Marker Layout Regression
;;;
;; Compares real complete-formula TeX output with and without semantic markers. External
;; executables and filesystem writes are deliberate here.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/file file->bytes make-directory*)
  (only-in racket/list append-map remove-duplicates)
  racket/cmdline
  (only-in racket/system system*)
  "check.rkt"
  "../main.rkt"
  "../private/semantic-svg.rkt"
  (prefix-in lc: "../examples/linear-concrete.rkt")
  (prefix-in lg: "../examples/linear-general.rkt")
  (prefix-in qc: "../examples/quadratic-concrete.rkt")
  (prefix-in qg: "../examples/quadratic-general.rkt"))

;;;
;;; Construction and Operations
;;;
; output : path-string?
;;   Names the command-line probe output directory.
(define output
  "math-output/tex-layout-probe")

(command-line #:args ([directory output]) (set! output directory))

; directory : path-string?
;;   Names the output directory for the optional TeX layout probe.
(define directory
  (path->complete-path output))

(make-directory* directory)

; latex : path?
;;   Locates the explicitly required external TeX executable.
(define latex
  (find-executable-path "latex"))

; dvipng : path?
;;   Locates the explicitly required DVI rasterization executable.
(define dvipng
  (find-executable-path "dvipng"))

(unless (and latex dvipng)
  (raise-user-error 'tex-layout-probe "latex and dvipng must be on PATH."))

; forms : (listof math-datum?)
;;   Lists distinct held lesson formulas in deterministic comparison order.
(define forms
  (remove-duplicates
    (append
      (append-map
        (lambda (plan)
          (append
            (append-map
              (lambda (segment)
                (map math-datum (derivation-states (plan-segment-derivation segment))))
              (presentation-plan-segments plan))
            (for/list ([entry (in-list (plan-schedule plan))]
                       #:when (eq? (scheduled-phase-kind entry) 'explain))
              (math-datum (car (presentation-phase-annotation (scheduled-phase-phase entry)))))))
        (list lc:plan lg:plan qc:plan qg:plan))
      '((+ -3 x) (+ x -3) (- x 3) (+ (- x) 3) -0.0
        (expt (sqrt x) 2) (expt (/ x y) 2) (expt 2/3 2)
        (expt (expt x 2) 3) (expt (+ x 1) 2)))
    equal?))

(parameterize ([current-directory directory])
  (call-with-output-file "probe.tex"
    #:exists 'truncate/replace
    (lambda (out)
      (display
        "\\documentclass{article}\n\\usepackage[active,tightpage]{preview}\n\\usepackage{amsmath,amssymb}\n\\begin{document}\n"
        out)
      (for ([d (in-list forms)])
        (define source (format-math-source d))
        (define-values (marked markers) (annotate-math-source source))
        (for ([s (in-list (list (math-source-text source) marked))])
          (fprintf out "\\begin{preview}$\\displaystyle ~a$\\end{preview}\n" s)))
      (display "\\end{document}\n" out)))
  (call-with-output-file "commands.log"
    #:exists 'truncate/replace
    (lambda (log)
      (parameterize ([current-output-port log] [current-error-port log])
        (unless (system* latex "-interaction=nonstopmode" "-halt-on-error" "probe.tex")
          (error 'tex-layout-probe "TeX failed; see ~a/commands.log" directory))
        (unless (system* dvipng "-T" "tight" "-D" "144" "-o" "probe-%d.png" "probe.dvi")
          (error 'tex-layout-probe "dvipng failed; see ~a/commands.log" directory)))))
  (test-group
    "TeX layout unchanged by semantic markers"
    (lambda ()
      (for ([d (in-list forms)] [i (in-naturals)])
        (check-equal
          (file->bytes (format "probe-~a.png" (+ 1 (* 2 i))))
          (file->bytes (format "probe-~a.png" (+ 2 (* 2 i))))
          (format "held formula ~s" d))))))

(printf
  "Compared ~a complete formulas (~a TeX pages).\n"
  (length forms)
  (* 2 (length forms)))

(report!)
