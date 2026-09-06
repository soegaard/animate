#lang racket/base

;;; SCENE-3D-P: backend-neutral 3D benchmark harness

;; The N harness defines canonical, deterministic workloads.  This wrapper
;; measures the same input through either the portable retained software
;; renderer or the explicit OpenGL renderer.  The OpenGL module is dynamically
;; loaded only when the caller explicitly chooses it, so ordinary command-line
;; and CI uses remain headless.

(require racket/cmdline
         racket/list
         racket/runtime-path
         file/sha1
         "../3d/render.rkt"
         "benchmark-3d-n.rkt")

(provide benchmark3d-workload
         benchmark3d-workload?
         benchmark3d-workload-name
         benchmark3d-workload-views
         benchmark3d-workload-renderer-capacity
         benchmark-3d-workloads
         run-3d-benchmarks)

(define benchmark-3d-workloads benchmark-3d-n-workloads)

(define-runtime-path opengl-module-path "../3d/opengl.rkt")

(define (current-renderer selection)
  (case selection
    [(software)
     (define renderer (retained-software-renderer3d #:capacity 16))
     (values renderer
             (lambda () (renderer3d-release renderer))
             (hasheq 'backend 'retained-software-reference)
             renderer3d-statistics-snapshot)]
    [(opengl)
     ;; The public, opt-in module is loaded only for this explicit branch.
     (define make-renderer (dynamic-require opengl-module-path 'opengl-renderer3d))
     (define renderer-info (dynamic-require opengl-module-path 'opengl-renderer3d-info))
     (define renderer-statistics
       (dynamic-require opengl-module-path 'opengl-renderer3d-statistics))
     (define release! (dynamic-require opengl-module-path 'opengl-renderer3d-release!))
     (define renderer (make-renderer))
     (values renderer
             (lambda () (release! renderer))
             (renderer-info renderer)
             renderer-statistics)]
    [else
     (raise-argument-error 'run-3d-benchmarks "'software or 'opengl" selection)]))

(define (render-one renderer view width height)
  (define request (view3d->render3d-request view width height))
  (renderer3d-render renderer (renderer3d-prepare renderer request) request))

(define (fingerprint-digest renderer view width height)
  ;; A complete fingerprint includes compiled geometry, so storing it verbatim
  ;; would turn a benchmark manifest into a multi-megabyte mesh dump. The
  ;; stable digest still makes backend/request identity auditable.
  (sha1
   (open-input-string
    (format "~s"
            (renderer3d-fingerprint
             renderer (view3d->render3d-request view width height))))))

;; run-3d-benchmarks : [#:renderer (or/c 'software 'opengl)]
;;                     [#:width exact-positive-integer?]
;;                     [#:height exact-positive-integer?]
;;                     [#:warm-up exact-nonnegative-integer?]
;;                     -> immutable-hash?
;;
;; Timing observations are evidence, never portable CI thresholds.  The
;; snapshots contain semantic cache/FBO/readback counters, which are the
;; actual performance acceptance criteria for a retained backend.
(define (run-3d-benchmarks #:renderer [selection 'software]
                           #:width [width 320]
                           #:height [height 180]
                           #:warm-up [warm-up 1])
  (unless (memq selection '(software opengl))
    (raise-argument-error 'run-3d-benchmarks "'software or 'opengl" selection))
  (for ([value (in-list (list width height))])
    (unless (exact-positive-integer? value)
      (raise-argument-error 'run-3d-benchmarks "exact-positive-integer?" value)))
  (unless (exact-nonnegative-integer? warm-up)
    (raise-argument-error 'run-3d-benchmarks "exact-nonnegative-integer? as #:warm-up" warm-up))
  (define-values (renderer release! backend-info statistics) (current-renderer selection))
  (dynamic-wind
   void
   (lambda ()
     (define start (current-inexact-milliseconds))
     ;; One warm frame makes first context/shader/allocation work distinguishable
     ;; from the per-workload retained-frame measurements below.
     (define first-view
       (car (benchmark3d-workload-views (car benchmark-3d-workloads))))
     (for ([ignored (in-range warm-up)])
       (render-one renderer first-view width height))
     (define warmup-finished (current-inexact-milliseconds))
     (hasheq
      'stage 'SCENE-3D-P
      'renderer (renderer3d-id renderer)
      'backend-info backend-info
      'width width
      'height height
      'warm-up-count warm-up
      'initialization-milliseconds (- warmup-finished start)
      'initial-statistics (statistics renderer)
      'workloads
      (for/list ([workload (in-list benchmark-3d-workloads)])
        (define frame-times
          (for/list ([view (in-list (benchmark3d-workload-views workload))])
            (define frame-start (current-inexact-milliseconds))
            (render-one renderer view width height)
            (- (current-inexact-milliseconds) frame-start)))
        (hasheq 'name (benchmark3d-workload-name workload)
                'frame-count (length frame-times)
                'frame-milliseconds frame-times
                'total-milliseconds (apply + frame-times)
                'statistics (statistics renderer)
                ;; P-specific backends expose richer cache/FBO/readback state
                ;; through their public statistics procedure; this common
                ;; snapshot still lets software remain the reference run.
                'renderer-fingerprint-sha1
                (fingerprint-digest renderer
                                    (car (benchmark3d-workload-views workload))
                                    width height)))))
   release!))

(module+ main
  (define selection 'software)
  (define width 320)
  (define height 180)
  (define warm-up 1)
  (command-line
   #:program "benchmark-3d.rkt"
   #:once-each
   ["--renderer" name "software (default) or explicit opengl"
    (set! selection (string->symbol name))]
   ["--width" pixels "Output width" (set! width (string->number pixels))]
   ["--height" pixels "Output height" (set! height (string->number pixels))]
   ["--warm-up" count "Warm-up frame count" (set! warm-up (string->number count))])
  (write (run-3d-benchmarks #:renderer selection #:width width #:height height
                            #:warm-up warm-up))
  (newline))
