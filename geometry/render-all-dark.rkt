#lang racket/base

;; Run all geometry tests, then render every registered example in dark mode,
;; followed by the gallery in dark mode.
;;
;; Intended location:
;;   animate/geometry/render-all-dark.rkt
;;
;; Run from anywhere with:
;;   "/Applications/Racket v9.3.0.2/bin/racket" geometry/render-all-dark.rkt
;;
;; Optional:
;;   --workers N
;;   --output DIR

(require racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/runtime-path
         racket/system)

(define-runtime-path geometry-directory ".")
(define repository-root
  (simplify-path (build-path geometry-directory 'up)))

(define racket-executable
  (or (find-executable-path (find-system-path 'exec-file))
      (find-system-path 'exec-file)))

(define workers 10)
(define output-root
  (build-path repository-root "geometry-output"))

(define (positive-integer text option)
  (define n (string->number text))
  (unless (exact-positive-integer? n)
    (raise-user-error 'render-all-dark
                      "~a expects a positive integer; received ~e"
                      option text))
  n)

(command-line
 #:program "geometry/render-all-dark.rkt"
 #:once-each
 [("--workers") n
  "Worker processes per video; default 10."
  (set! workers (positive-integer n "--workers"))]
 [("--output") dir
  "Output root; default geometry-output."
  (set! output-root
        (path->complete-path dir repository-root))]
 #:args ()
 (void))

(define examples-module
  (build-path geometry-directory
              "examples"
              "private"
              "review-example-names.rkt"))

(define review-example-names
  (dynamic-require examples-module 'review-example-names))

(define examples
  (filter (lambda (name) (not (string=? name "gallery")))
          review-example-names))

(define videos-directory
  (build-path output-root "videos" "dark"))
(define frames-directory
  (build-path output-root "dark"))

(make-directory* videos-directory)
(make-directory* frames-directory)

(define (run! label . args)
  (printf "\n=== ~a ===\n" label)
  (flush-output)
  (define exit-code
    (parameterize ([current-directory repository-root])
      (apply system*/exit-code racket-executable args)))
  (unless (zero? exit-code)
    (eprintf "\nFAILED: ~a (exit code ~a)\n" label exit-code)
    (exit exit-code)))

;; 1. Full test suite.
(run! "tests"
      (path->string (build-path geometry-directory "run-tests.rkt")))

;; 2. Every registered example except the gallery.
(for ([example (in-list examples)])
  (define source
    (build-path geometry-directory "examples"
                (string-append example ".rkt")))
  (define mp4
    (build-path videos-directory
                (string-append example ".mp4")))
  (define frames
    (build-path frames-directory example))

  (run! (format "~a / dark" example)
        (path->string source)
        "--dark"
        "--workers" (number->string workers)
        "--mp4" (path->string mp4)
        (path->string frames)))

;; 3. Gallery, explicitly last.
(define gallery-source
  (build-path geometry-directory "examples" "gallery.rkt"))
(define gallery-mp4
  (build-path videos-directory "gallery.mp4"))
(define gallery-frames
  (build-path frames-directory "gallery"))

(run! "gallery / dark"
      (path->string gallery-source)
      "--dark"
      "--workers" (number->string workers)
      "--mp4" (path->string gallery-mp4)
      (path->string gallery-frames))

(printf "\n=== complete ===\n")
(printf "Videos: ~a\n" (path->string videos-directory))
