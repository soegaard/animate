#lang racket/base

;;;
;;; Authoring Environment Doctor
;;;

;; Reports capabilities without starting a preview, rendering a frame, or
;; creating output. Commands decide which missing capabilities are fatal.


;;;
;;; Imports and Exports
;;;

(require racket/path
         racket/port
         racket/string
         racket/system
         "../version.rkt")

(provide (struct-out doctor-capability)
         (struct-out tool-identity)
         (struct-out doctor-report)
         collect-doctor-report
         ffmpeg-tool-identity
         doctor-report->lines)


;;;
;;; Immutable Reports
;;;

(struct doctor-capability (name available? detail)
  #:transparent)

;; doctor-capability records one optional authoring capability. detail is a
;; printable executable path or a short explanation of why it is unavailable.

;; tool-identity is deliberately distinct from a doctor-capability.  The
;; environment doctor only discovers paths; project preparation may additionally
;; run a required tool's cheap version command to make a persistent artefact
;; cache conservative across tool upgrades.
(struct tool-identity (name executable version)
  #:transparent)

(struct doctor-report (racket gracket latex dvisvgm ffmpeg ffplay parallel
                             release-version release-stage)
  #:transparent)

;; doctor-report holds only discovered paths and immutable release metadata;
;; collecting it does not establish a GUI or invoke any external tool.


;;;
;;; Capability Discovery
;;;

; collect-doctor-report : -> doctor-report?
;;   Finds authoring tools available to this Racket process.
(define (collect-doctor-report)
  (doctor-report
   (executable-capability 'racket (find-system-path 'exec-file))
   (gracket-capability)
   (executable-capability 'latex (find-executable-path "pdflatex"))
   (executable-capability 'dvisvgm (find-executable-path "dvisvgm"))
   (executable-capability 'ffmpeg (find-executable-path "ffmpeg"))
   (executable-capability 'ffplay (find-executable-path "ffplay"))
   (parallel-capability)
   animate-version
   animate-stage))

(define (executable-capability name executable)
  (doctor-capability
   name
   (and executable #t)
   (if executable
       (path->string executable)
       "not found on PATH")))

(define (gracket-capability)
  (define racket-executable (find-system-path 'exec-file))
  (define candidate
    (build-path (or (path-only racket-executable) (current-directory))
                "gracket"))
  (doctor-capability
   'gracket
   (file-exists? candidate)
   (if (file-exists? candidate)
       (path->string candidate)
       "no sibling gracket launcher")))

(define (parallel-capability)
  (define available?
    (and (dynamic-require 'racket/base
                          'make-parallel-thread-pool
                          (lambda () #f))
         #t))
  (doctor-capability
   'parallel-rendering
   available?
   (if available?
       "Racket parallel thread pools are available"
       "this Racket runtime has no parallel thread pools")))


;;; Tool Identities for Effectful Preparation

; ffmpeg-tool-identity : doctor-report? -> tool-identity?
;;   Obtains the selected ffmpeg release banner for a prepared video project.
;;   This is intentionally not part of collect-doctor-report: `doctor` must be
;;   safe to run without starting external programs.
(define (ffmpeg-tool-identity report)
  (unless (doctor-report? report)
    (raise-argument-error 'ffmpeg-tool-identity "doctor-report?" report))
  (define capability (doctor-report-ffmpeg report))
  (cond
    [(not (doctor-capability-available? capability))
     (tool-identity 'ffmpeg #f #f)]
    [else
     (define executable (doctor-capability-detail capability))
     (tool-identity 'ffmpeg executable
                    (executable-version-line executable "-version"))]))

(define (executable-version-line executable . arguments)
  ;; `ffmpeg -version` is short and writes its banner to standard output.  Read
  ;; both ports before waiting so this helper is also safe for tools that put a
  ;; diagnostic banner on standard error.
  (with-handlers ([exn:fail? (lambda (_error) #f)])
    (define-values (process standard-output standard-input standard-error)
      (apply subprocess #f #f #f executable arguments))
    (close-output-port standard-input)
    (define output (port->string standard-output))
    (define errors (port->string standard-error))
    (subprocess-wait process)
    (close-input-port standard-output)
    (close-input-port standard-error)
    (and (zero? (subprocess-status process))
         (first-nonempty-line (string-append output "\n" errors)))))

(define (first-nonempty-line text)
  (for/or ([line (in-list (string-split text "\n" #:trim? #f))])
    (and (not (string=? (string-trim line) ""))
         (string-trim line))))


;;;
;;; Display
;;;

; doctor-report->lines : doctor-report? -> (listof string?)
;;   Formats a stable, line-oriented report for a CLI or test log.
(define (doctor-report->lines report)
  (unless (doctor-report? report)
    (raise-argument-error 'doctor-report->lines "doctor-report?" report))
  (append
   (list (format "animate ~a (~a)"
                 (doctor-report-release-version report)
                 (doctor-report-release-stage report)))
   (for/list ([capability
               (in-list
                (list (doctor-report-racket report)
                      (doctor-report-gracket report)
                      (doctor-report-latex report)
                      (doctor-report-dvisvgm report)
                      (doctor-report-ffmpeg report)
                      (doctor-report-ffplay report)
                      (doctor-report-parallel report)))])
     (format "~a: ~a (~a)"
             (doctor-capability-name capability)
             (if (doctor-capability-available? capability) "available" "missing")
             (doctor-capability-detail capability)))))
