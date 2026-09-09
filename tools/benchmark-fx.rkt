#lang racket/base

;;;
;;; FX-G: deterministic 2D effects benchmark harness
;;;

;; This is a measurement tool, not a timing test.  It keeps the six FX-G
;; workloads explicit and reports the real renderer-cache deltas observed for
;; a shared renderer list.  Machines differ too much for a useful time limit;
;; CI should compile this module but must never compare its timings.

(require racket/cmdline
         racket/list
         (only-in pict pict->bitmap)
         "../main.rkt"
         "../render.rkt"
         (only-in "../private/shape-pict-renderers.rkt"
                  default-pict-renderer-cache-counters
                  renderer-cache-counters-hits
                  renderer-cache-counters-misses
                  renderer-cache-counters-evictions))

(provide (struct-out benchmark-fx-workload)
         benchmark-fx-workloads
         run-fx-benchmarks)

(struct benchmark-fx-instance (scene request duration sample-times render-times)
  #:transparent)

(struct benchmark-fx-workload (name make-instance)
  #:transparent)

(define benchmark-camera
  (make-camera #:width 320 #:height 180 #:world-width 12 #:background "white"))

(define benchmark-sample-times
  ;; 73 is coprime to 120, so this is one shuffled traversal of the exact
  ;; 120-frame grid, including both endpoints.
  (for/list ([index (in-range 120)])
    (/ (modulo (* 73 index) 120) 119)))

(define (benchmark-card id index)
  (rectangle #:id id
             #:width 1/3
             #:height 1/3
             #:center (vec2 (- (modulo index 25) 12)
                            (- (quotient index 25) 2))
             #:fill "cornflowerblue"
             #:stroke "navy"))

(define (make-stagger-instance mapped?)
  (define cards
    (for/list ([index (in-range 1000)])
      (benchmark-card (string->symbol (format "stagger-~a" index)) index)))
  (define make-entry
    (lambda (card _source-index)
      (enter card #:translation-offset (vec2 0 -1/3)
             #:scale-factor 3/4 #:opacity-factor 0)))
  (benchmark-fx-instance
   (make-scene #:camera benchmark-camera)
   (if mapped?
       (stagger-map cards make-entry #:lag-ratio 1/1000)
       (apply lagged-start #:lag-ratio 1/1000
              (for/list ([card (in-list cards)] [index (in-naturals)])
                (make-entry card index))))
   1
   '(0 1/2 1)
   '(1/2)))

(define (make-entrance-instance)
  (define cards
    (for/list ([index (in-range 100)])
      (benchmark-card (string->symbol (format "enter-~a" index)) index)))
  (benchmark-fx-instance
   (make-scene #:camera benchmark-camera)
   (apply animation-group
          (for/list ([card (in-list cards)])
            (enter card #:translation-offset (vec2 0 -1/2)
                   #:scale-factor 4/5 #:opacity-factor 0)))
   1
   benchmark-sample-times
   '(1/2)))

(define (make-reveal-instance)
  (define cards
    (for/list ([index (in-range 100)])
      (benchmark-card (string->symbol (format "reveal-~a" index)) index)))
  (benchmark-fx-instance
   (make-scene #:camera benchmark-camera)
   (apply animation-group
          (for/list ([card (in-list cards)])
            (reveal-in card (linear-reveal-front (vec2 1 0) #:padding 0))))
   1
   '(0 1/2 1)
   '(1/2)))

(define (make-ripple-instance)
  (define target
    (rectangle #:id 'moving-target #:width 2 #:height 1 #:fill "gold"
               #:stroke "sienna"))
  (benchmark-fx-instance
   (scene-add (make-scene #:camera benchmark-camera) target)
   (animation-group
    (move-to target (vec2 3 1))
    (ripple 'moving-target #:rings 8 #:color "mediumorchid"))
   1
   benchmark-sample-times
   '(1/2)))

(define (make-typewrite-instance)
  (define paragraph
    (rich-text #:id 'paragraph #:width 5 #:font-size 1/2 #:line-spacing 6/5
               (text-span "Prepared layouts keep " #:color "navy")
               (text-span "rich text" #:font-weight 'bold #:color "tomato")
               (text-span " on measured lines while the reveal advances.")))
  (benchmark-fx-instance
   (make-scene #:camera benchmark-camera)
   (typewrite paragraph #:unit 'word)
   1
   benchmark-sample-times
   '(1/2 1/2)))

(define (make-confetti-instance)
  (benchmark-fx-instance
   (make-scene #:camera benchmark-camera)
   (confetti origin #:count 100 #:seed 20260909 #:spread 5 #:height 4 #:gravity 5)
   1
   benchmark-sample-times
   '(1/2)))

(define benchmark-fx-workloads
  (list
   ;; The first two results are deliberately comparable: 1,000 mapped entries
   ;; and the same explicit lagged-start expansion.
   (benchmark-fx-workload 'stagger-map-1000
                           (lambda () (make-stagger-instance #t)))
   (benchmark-fx-workload 'explicit-lagged-start-1000
                           (lambda () (make-stagger-instance #f)))
   (benchmark-fx-workload 'combined-entrances-100 make-entrance-instance)
   (benchmark-fx-workload 'hard-reveals-100 make-reveal-instance)
   (benchmark-fx-workload 'moving-target-ripple make-ripple-instance)
   (benchmark-fx-workload 'rich-multiline-typewrite make-typewrite-instance)
   (benchmark-fx-workload 'deterministic-confetti-100 make-confetti-instance)))

(define (measure thunk)
  (define started-at (current-inexact-milliseconds))
  (define value (thunk))
  (values value (- (current-inexact-milliseconds) started-at)))

(define (counter-delta before after)
  (hasheq 'hits (- (renderer-cache-counters-hits after)
                   (renderer-cache-counters-hits before))
          'misses (- (renderer-cache-counters-misses after)
                     (renderer-cache-counters-misses before))
          'evictions (- (renderer-cache-counters-evictions after)
                        (renderer-cache-counters-evictions before))))

(define (prepared-layout-keys scene)
  ;; Inspection carries source keys only.  It deliberately excludes the Pict
  ;; and renderer cache resources used to prepare the layout.
  (for/list ([inspection (in-list (scene-animation-inspections-at scene 1/2))]
             #:when (and (hash? (animation-inspection-data inspection))
                         (hash-has-key? (animation-inspection-data inspection)
                                        'prepared-layout-key)))
    (hash-ref (animation-inspection-data inspection) 'prepared-layout-key)))

;; run-fx-benchmarks : [#:workloads (listof benchmark-fx-workload?)]
;;                      [#:renderers pict-renderer-list?]
;;                      -> (listof immutable-hash?)
;;
;; Workloads report construction, compile, shuffled sampling, and fully
;; rasterized Pict rendering separately. `retained-bytes` is the measured heap
;; delta while the compiled Scene, sampled states, and rendered bitmaps remain
;; reachable; it is intentionally an observation, not a portable allocation
;; assertion. Reusing `renderers` makes cache hits/misses auditable.
(define (run-fx-benchmarks #:workloads [workloads benchmark-fx-workloads]
                           #:renderers [renderers default-pict-renderers])
  (unless (and (list? workloads) (andmap benchmark-fx-workload? workloads))
    (raise-argument-error 'run-fx-benchmarks
                          "list of benchmark-fx-workload? values" workloads))
  (unless (pict-renderer-list? renderers)
    (raise-argument-error 'run-fx-benchmarks "pict-renderer-list?" renderers))
  (for/list ([workload (in-list workloads)])
    (collect-garbage)
    (define before-memory (current-memory-use))
    (define-values (instance construction-milliseconds)
      (measure (benchmark-fx-workload-make-instance workload)))
    (define-values (scene compile-milliseconds)
      (measure
       (lambda ()
         (scene-play (benchmark-fx-instance-scene instance)
                     (benchmark-fx-instance-request instance)
                     #:duration (benchmark-fx-instance-duration instance)))))
    (define-values (states sample-milliseconds)
      (measure
       (lambda ()
         (for/list ([time (in-list (benchmark-fx-instance-sample-times instance))])
           (scene-sample scene time)))))
    (define counters-before (default-pict-renderer-cache-counters renderers))
    (define-values (bitmaps render-milliseconds)
      (measure
       (lambda ()
         (for/list ([time (in-list (benchmark-fx-instance-render-times instance))])
           (pict->bitmap (scene->pict scene time #:renderers renderers)
                         'aligned)))))
    (define counters-after (default-pict-renderer-cache-counters renderers))
    (collect-garbage)
    (define retained-bytes (max 0 (- (current-memory-use) before-memory)))
    ;; Keep every measured result live through the allocation sample.  The
    ;; bindings are intentionally referenced here rather than relying on an
    ;; optimizer-sensitive void loop.
    (hasheq 'name (benchmark-fx-workload-name workload)
            'construction-milliseconds construction-milliseconds
            'compile-milliseconds compile-milliseconds
            'sample-milliseconds sample-milliseconds
            'sample-count (length states)
            'render-milliseconds render-milliseconds
            'rendered-frame-count (length bitmaps)
            'retained-bytes retained-bytes
            'prepared-layout-keys (prepared-layout-keys scene)
            'renderer-cache (counter-delta counters-before counters-after))))

(module+ main
  (define selected-names '())
  (command-line
   #:program "benchmark-fx.rkt"
   #:once-each
   ["--workload" name "Run one named workload (may be repeated)"
    (set! selected-names (append selected-names (list (string->symbol name))))])
  (define selected-workloads
    (if (null? selected-names)
        benchmark-fx-workloads
        (for/list ([name (in-list selected-names)])
          (or (for/first ([workload (in-list benchmark-fx-workloads)]
                          #:when (eq? (benchmark-fx-workload-name workload) name))
                workload)
              (raise-arguments-error 'benchmark-fx.rkt "unknown workload"
                                     "workload" name)))))
  (for ([result (in-list (run-fx-benchmarks #:workloads selected-workloads))])
    (write result)
    (newline)))
