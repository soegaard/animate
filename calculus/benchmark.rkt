#lang racket/base

;;;
;;; Calculus Workload Benchmark Runner
;;;

;; Measures the complete Guide fixture set through the real headless,
;; preparation, and native raster paths.  It is an evidence tool, not a
;; performance promise: timings are environment-specific and the counters
;; describe performed work rather than an optimization score.


;;;
;;; Imports and Public Entry Point
;;;

(require racket/cmdline
         racket/file
         racket/list
         racket/path
         racket/string
         (prefix-in pict: pict)
         (only-in "tests/guide-lessons-test.rkt"
                  guide-reading-square
                  guide-secant-to-tangent
                  guide-build-derivative
                  guide-limit-not-value
                  guide-sums-and-accumulation
                  guide-component-example)
         "render.rkt")

(provide run-calculus-benchmarks!
         calculus-benchmark-fixture-ids)


;;;
;;; Workload Registry
;;;

;; calculus-benchmark-fixture : symbol? calculus-lesson? -> record
;;   Associates one complete Guide lesson with its stable workload name.
(struct calculus-benchmark-fixture (id lesson) #:transparent)

;; calculus-benchmark-case : symbol? symbol? calculus-profile? calculus-lesson? -> record
;;   Freezes one fixture/profile combination before timed work starts.
(struct calculus-benchmark-case (fixture-id profile-id profile lesson) #:transparent)

;; calculus-benchmark-fixtures : (listof calculus-benchmark-fixture?)
;;   Retains every complete Guide lesson once; abbreviated smoke fixtures are
;; deliberately excluded from resource measurements.
(define calculus-benchmark-fixtures
  (list
   (calculus-benchmark-fixture 'reading-square guide-reading-square)
   (calculus-benchmark-fixture 'secant-to-tangent guide-secant-to-tangent)
   (calculus-benchmark-fixture 'build-derivative guide-build-derivative)
   (calculus-benchmark-fixture 'limit-not-value guide-limit-not-value)
   (calculus-benchmark-fixture 'sums-and-accumulation guide-sums-and-accumulation)
   (calculus-benchmark-fixture 'component-example guide-component-example)))

;; calculus-benchmark-fixture-ids : -> (listof symbol?)
;;   Lists stable, full-lesson workload names without native initialization.
(define (calculus-benchmark-fixture-ids)
  (map calculus-benchmark-fixture-id calculus-benchmark-fixtures))

;; benchmark-profile : symbol? -> calculus-profile?
;;   Resolves exactly the documented release-review profiles.
(define (benchmark-profile profile-id)
  (case profile-id
    [(light) classroom-light-profile]
    [(dark) classroom-dark-profile]
    [(textbook) textbook-profile]
    [else
     (raise-arguments-error
      'run-calculus-benchmarks!
      "one of the standard profile names"
      "profile" profile-id)]))

;; benchmark-cases : (listof symbol?) -> (listof calculus-benchmark-case?)
;;   Preserves fixture and profile order, so all timing runs use the same work
;; order and no result depends on hash traversal.
(define (benchmark-cases profile-ids)
  (unless (and (list? profile-ids) (pair? profile-ids)
               (andmap symbol? profile-ids))
    (raise-argument-error 'run-calculus-benchmarks!
                          "nonempty (listof symbol?)" profile-ids))
  (for*/list ([profile-id (in-list profile-ids)]
              [fixture (in-list calculus-benchmark-fixtures)])
    (calculus-benchmark-case
     (calculus-benchmark-fixture-id fixture)
     profile-id
     (benchmark-profile profile-id)
     (calculus-benchmark-fixture-lesson fixture))))


;;;
;;; Timing and Report Construction
;;;

;; call/timed : (-> any/c) -> (values any/c nonnegative-real?)
;;   Evaluates one workload while retaining only monotonic elapsed milliseconds.
(define (call/timed thunk)
  (define started (current-inexact-monotonic-milliseconds))
  (define result (thunk))
  (values result (- (current-inexact-monotonic-milliseconds) started)))

;; median : (nonempty-listof real?) -> real?
;;   Uses the upper middle run for an even count, avoiding interpolation of
;; timing data that has no meaningful fractional observation.
(define (median values)
  (define sorted (sort values <))
  (list-ref sorted (quotient (length sorted) 2)))

;; timing-summary : (listof nonnegative-real?) -> immutable-hash?
;;   Reports every deterministic repeat plus min/median/max evidence.
(define (timing-summary milliseconds)
  (hasheq 'runs-milliseconds milliseconds
          'minimum-milliseconds (apply min milliseconds)
          'median-milliseconds (median milliseconds)
          'maximum-milliseconds (apply max milliseconds)))

;; force-pict! : pict? -> void?
;;   Forces one delayed calculus composition through the native bitmap backend
;; without writing a file or retaining its pixel buffer between workloads.
(define (force-pict! picture)
  (pict:pict->bitmap picture 'aligned)
  (void))

;; run-benchmark-iteration : (listof calculus-benchmark-case?) integer? integer?
;;                           -> immutable-hash?
;;   Executes the three main workload families once in a fixed order. The
;; sample stage exercises initial, mid-transition, and settled snapshots;
;; native rasterization renders the settled state of each prepared lesson.
(define (run-benchmark-iteration cases width height)
  (define-values (plans compilation-milliseconds)
    (call/timed
     (lambda ()
       (for/list ([case (in-list cases)])
         (compile-calculus-lesson
          (calculus-benchmark-case-lesson case)
          #:profile (calculus-benchmark-case-profile case))))))
  (define-values (prepared-lessons preparation-milliseconds)
    (call/timed
     (lambda ()
       (for/list ([case (in-list cases)] [plan (in-list plans)])
         (prepare-calculus-plan plan #:width width #:height height)))))
  (define-values (_snapshots sampling-milliseconds)
    (call/timed
     (lambda ()
       (append-map
        (lambda (plan)
          (define duration (calculus-plan-duration plan))
          (list (calculus-plan-sample plan #:at 'initial)
                (calculus-plan-sample plan #:at (/ duration 2))
                (calculus-plan-sample plan #:at 'final)))
        plans))))
  (define-values (_bitmaps raster-milliseconds)
    (call/timed
     (lambda ()
       (for/list ([prepared (in-list prepared-lessons)])
         (force-pict! (prepared-lesson->pict prepared #:at 'final))))))
  (hasheq 'compilation-milliseconds compilation-milliseconds
          'preparation-milliseconds preparation-milliseconds
          'sampling-milliseconds sampling-milliseconds
          'native-raster-milliseconds raster-milliseconds))

;; run-calculus-benchmarks! : keyword-options -> immutable-hash?
;;   Runs repeatable complete-lesson workloads and optionally writes one new
;; Racket-datum report. The report holds counters and raw timings; consumers
;; must compare only runs recorded under compatible environments.
(define (run-calculus-benchmarks!
         #:iterations [iterations 3]
         #:profiles [profile-ids '(light dark textbook)]
         #:width [width 1280]
         #:height [height 720]
         #:output [output-path #f])
  (unless (exact-positive-integer? iterations)
    (raise-argument-error 'run-calculus-benchmarks!
                          "exact-positive-integer? iterations" iterations))
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (raise-arguments-error 'run-calculus-benchmarks!
                           "positive output dimensions"
                           "width" width "height" height))
  (unless (or (not output-path) (path-string? output-path))
    (raise-argument-error 'run-calculus-benchmarks!
                          "#f or path-string? output" output-path))
  (define cases (benchmark-cases profile-ids))
  (define iterations-report
    (for/list ([ignored (in-range iterations)])
      (run-benchmark-iteration cases width height)))
  (define (stage-milliseconds stage)
    (for/list ([iteration (in-list iterations-report)])
      (hash-ref iteration stage)))
  (define report
    (hasheq
     'format 'animate-calculus-benchmark-v1
     'racket-version (version)
     'iterations iterations
     'width width
     'height height
     'fixture-ids (calculus-benchmark-fixture-ids)
     'profile-ids profile-ids
     'counters
     (hasheq 'fixture-profile-cases (length cases)
             'compiled-plans (* iterations (length cases))
             'prepared-lessons (* iterations (length cases))
             'headless-snapshots (* iterations (length cases) 3)
             'native-bitmaps (* iterations (length cases)))
     'timings
     (hasheq
      'compilation (timing-summary (stage-milliseconds 'compilation-milliseconds))
      'preparation (timing-summary (stage-milliseconds 'preparation-milliseconds))
      'sampling (timing-summary (stage-milliseconds 'sampling-milliseconds))
      'native-raster (timing-summary (stage-milliseconds 'native-raster-milliseconds)))))
  (when output-path
    (call-with-output-file
     output-path
     #:exists 'error
     (lambda (output)
       (write report output)
       (newline output))))
  report)


;;;
;;; Command Line
;;;

;; positive-option : string? string? -> exact-positive-integer?
;;   Parses one required positive benchmark option before rendering begins.
(define (positive-option text flag)
  (define value (string->number text))
  (unless (exact-positive-integer? value)
    (raise-arguments-error 'calculus/benchmark "a positive integer" flag text))
  value)

;; parse-profile-list : string? -> (listof symbol?)
;;   Parses the same compact standard-profile spelling as the review runner.
(define (parse-profile-list text)
  (define values
    (filter (lambda (value) (not (string=? value "")))
            (map string-trim (string-split text ","))))
  (unless (pair? values)
    (raise-arguments-error 'calculus/benchmark "one or more profile names"
                           "profiles" text))
  (map string->symbol values))

(module+ main
  (define iterations 3)
  (define profiles '(light dark textbook))
  (define width 1280)
  (define height 720)
  (define output-path #f)
  (command-line
   #:program "calculus/benchmark.rkt"
   #:once-each
   [("--iterations") value "Measured repeats per complete workload set; default 3."
                     (set! iterations (positive-option value "--iterations"))]
   [("--profiles") value "Comma-separated light,dark,textbook profile names."
                   (set! profiles (parse-profile-list value))]
   [("--width") value "Native raster width in pixels; default 1280."
                 (set! width (positive-option value "--width"))]
   [("--height") value "Native raster height in pixels; default 720."
                  (set! height (positive-option value "--height"))]
   [("--output") value "Write a new Racket-datum report at this path."
                  (set! output-path value)]
   #:args () (void))
  (define report
    (run-calculus-benchmarks!
     #:iterations iterations #:profiles profiles #:width width #:height height
     #:output output-path))
  (printf "Measured ~a prepared lessons and ~a native bitmaps across ~a iteration(s).~n"
          (hash-ref (hash-ref report 'counters) 'prepared-lessons)
          (hash-ref (hash-ref report 'counters) 'native-bitmaps)
          iterations))
