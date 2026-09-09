#lang racket/base

;;;
;;; Renderer Conformance Metrics
;;;

;; This module is deliberately renderer- and GUI-independent. It classifies
;; two straight-ARGB images into interior and coverage-edge populations, then
;; returns immutable metrics and diagnostic masks. OpenGL integration tests can
;; assert semantic tolerances without hiding a lost primitive behind one global
;; maximum-byte threshold; the command-line tool writes the resulting bytes as
;; PNG artifacts when visual inspection is needed.

(require racket/list)

(provide conformance-report3d?
         conformance-report3d-width
         conformance-report3d-height
         conformance-report3d-difference-argb
         conformance-report3d-large-difference-mask-argb
         conformance-report3d-edge-mask-argb
         conformance-report3d-interior-mask-argb
         conformance-report3d-metrics
         argb-conformance-report3d)

(struct conformance-report3d
  (width height difference-argb large-difference-mask-argb edge-mask-argb
         interior-mask-argb metrics)
  #:transparent)

(define (argb-conformance-report3d expected actual width height)
  (check-dimensions 'argb-conformance-report3d width height)
  (define component-count (* 4 width height))
  (unless (= (bytes-length expected) component-count)
    (raise-arguments-error
     'argb-conformance-report3d "expected ARGB bytes matching width and height"
     "expected-length" (bytes-length expected)
     "width" width "height" height))
  (unless (= (bytes-length actual) component-count)
    (raise-arguments-error
     'argb-conformance-report3d "actual ARGB bytes matching width and height"
     "actual-length" (bytes-length actual)
     "width" width "height" height))
  (define pixel-count (* width height))
  (define difference (make-bytes component-count 0))
  (define large-difference-mask (make-bytes component-count 0))
  (define edge-mask (make-bytes component-count 0))
  (define interior-mask (make-bytes component-count 0))
  (define large-difference-pixels (make-vector pixel-count #f))
  (define histogram (make-vector 256 0))
  (define totals (make-vector 4 0))
  (define total-difference 0)
  (define different-components 0)
  (define large-component-differences 0)
  (define large-difference-edge-pixels 0)
  (define large-difference-interior-pixels 0)
  (define different-pixels 0)
  (define alpha-only-pixels 0)
  (define alpha-only-edge-pixels 0)
  (define alpha-only-interior-pixels 0)
  (define edge-pixels 0)
  (define interior-pixels 0)
  (define edge-difference 0)
  (define interior-difference 0)
  (define edge-components 0)
  (define interior-components 0)
  (define changed-left width)
  (define changed-top height)
  (define changed-right -1)
  (define changed-bottom -1)
  (define differences '())
  (define (pixel-offset x y) (* 4 (+ x (* y width))))
  (define (component-difference offset channel)
    (abs (- (bytes-ref expected (+ offset channel))
            (bytes-ref actual (+ offset channel)))))
  ;; Coverage boundaries are the places where either renderer changes visibly
  ;; across a four-neighbour relation. They are kept separate from the stable
  ;; interiors whose lighting/colour transfer must agree more tightly.
  (define (edge-pixel? x y)
    (define offset (pixel-offset x y))
    (for/or ([delta (in-list '((-1 . 0) (1 . 0) (0 . -1) (0 . 1)))])
      (define nx (+ x (car delta)))
      (define ny (+ y (cdr delta)))
      (and (<= 0 nx) (< nx width) (<= 0 ny) (< ny height)
           (let ([other (pixel-offset nx ny)])
             (for/or ([channel (in-range 4)])
               (> (max (abs (- (bytes-ref expected (+ offset channel))
                                (bytes-ref expected (+ other channel))))
                       (abs (- (bytes-ref actual (+ offset channel))
                                (bytes-ref actual (+ other channel)))))
                  12))))))
  (for* ([y (in-range height)] [x (in-range width)])
    (define offset (pixel-offset x y))
    (define edge? (edge-pixel? x y))
    (define pixel-different? #f)
    (define large-difference-pixel? #f)
    (define rgb-different? #f)
    (define alpha-different? #f)
    (bytes-set! difference offset 255)
    (bytes-set! large-difference-mask offset 255)
    (bytes-set! edge-mask offset 255)
    (bytes-set! interior-mask offset 255)
    (for ([channel (in-range 4)])
      (define delta (component-difference offset channel))
      (vector-set! totals channel (+ (vector-ref totals channel) delta))
      (vector-set! histogram delta (add1 (vector-ref histogram delta)))
      (set! total-difference (+ total-difference delta))
      (set! differences (cons delta differences))
      (when (positive? delta)
        (set! pixel-different? #t)
        (set! different-components (add1 different-components))
        (if (= channel 0)
            (set! alpha-different? #t)
            (set! rgb-different? #t)))
      (when (>= delta 128)
        (set! large-component-differences (add1 large-component-differences))
        (set! large-difference-pixel? #t))
      (when edge?
        (set! edge-difference (+ edge-difference delta))
        (set! edge-components (add1 edge-components)))
      (unless edge?
        (set! interior-difference (+ interior-difference delta))
        (set! interior-components (add1 interior-components)))
      ;; A conventional ARGB diagnostic image keeps alpha opaque and displays
      ;; RGB absolute error. Alpha remains an explicit metric below.
      (when (positive? channel)
        (bytes-set! difference (+ offset channel) delta)))
    (define mask-value (if edge? 255 0))
    (for ([channel (in-range 1 4)])
      (bytes-set! edge-mask (+ offset channel) mask-value)
      (bytes-set! interior-mask (+ offset channel) (- 255 mask-value)))
    (when large-difference-pixel?
      (vector-set! large-difference-pixels (+ x (* y width)) #t)
      (for ([channel (in-range 1 4)])
        (bytes-set! large-difference-mask (+ offset channel) 255))
      (if edge?
          (set! large-difference-edge-pixels (add1 large-difference-edge-pixels))
          (set! large-difference-interior-pixels
                (add1 large-difference-interior-pixels))))
    (if edge?
        (set! edge-pixels (add1 edge-pixels))
        (set! interior-pixels (add1 interior-pixels)))
    (when pixel-different?
      (set! different-pixels (add1 different-pixels))
      (when (and alpha-different? (not rgb-different?))
        (set! alpha-only-pixels (add1 alpha-only-pixels))
        (if edge?
            (set! alpha-only-edge-pixels (add1 alpha-only-edge-pixels))
            (set! alpha-only-interior-pixels (add1 alpha-only-interior-pixels))))
      (set! changed-left (min changed-left x))
      (set! changed-top (min changed-top y))
      (set! changed-right (max changed-right x))
      (set! changed-bottom (max changed-bottom y))))
  (define ordered-differences (sort differences <))
  (define large-components
    (large-difference-components large-difference-pixels width height))
  (define (quantile proportion)
    (if (zero? component-count)
        0
        (list-ref ordered-differences
                  (min (sub1 component-count)
                       (inexact->exact (floor (* proportion component-count)))))))
  (define (mean total count) (if (zero? count) 0 (/ total count)))
  (conformance-report3d
   width height
   (bytes->immutable-bytes difference)
   (bytes->immutable-bytes large-difference-mask)
   (bytes->immutable-bytes edge-mask)
   (bytes->immutable-bytes interior-mask)
   (hasheq
    'pixel-count pixel-count
    'component-count component-count
    'mean-absolute-error (mean total-difference component-count)
    'mean-absolute-error-per-channel
    (vector->immutable-vector
     (for/vector ([total (in-vector totals)]) (mean total pixel-count)))
    'p95-component-error (quantile 0.95)
    'p99-component-error (quantile 0.99)
    'maximum-component-error (if (null? ordered-differences) 0 (last ordered-differences))
    'different-pixel-count different-pixels
    'different-component-count different-components
    'large-difference-components large-component-differences
    'large-difference-pixel-count
    (for/sum ([different? (in-vector large-difference-pixels)])
      (if different? 1 0))
    'large-difference-edge-pixel-count large-difference-edge-pixels
    'large-difference-interior-pixel-count large-difference-interior-pixels
    'large-difference-connected-component-count (vector-length large-components)
    'large-difference-connected-components large-components
    'alpha-only-different-pixel-count alpha-only-pixels
    'alpha-only-edge-pixel-count alpha-only-edge-pixels
    'alpha-only-interior-pixel-count alpha-only-interior-pixels
    'difference-bounds
    (and (positive? different-pixels)
         (vector-immutable changed-left changed-top changed-right changed-bottom))
    'histogram (vector->immutable-vector histogram)
    'edge
    (hasheq 'pixel-count edge-pixels
            'component-count edge-components
            'mean-absolute-error (mean edge-difference edge-components))
    'interior
    (hasheq 'pixel-count interior-pixels
            'component-count interior-components
            'mean-absolute-error (mean interior-difference interior-components)))))

;; Connected components are a four-neighbour partition of pixels containing
;; one or more large (>= 128) ARGB component errors.  This is deliberately a
;; separate measure from `large-difference-components`, which counts colour
;; components and remains useful for the existing numeric tolerance checks.
(define (large-difference-components pixels width height)
  (define pixel-count (* width height))
  (define visited (make-vector pixel-count #f))
  (define queue (make-vector pixel-count 0))
  (define components '())
  (define (enqueue-neighbour! index tail)
    (if (and (vector-ref pixels index) (not (vector-ref visited index)))
        (begin
          (vector-set! visited index #t)
          (vector-set! queue tail index)
          (add1 tail))
        tail))
  (for* ([y (in-range height)] [x (in-range width)])
    (define start (+ x (* y width)))
    (when (and (vector-ref pixels start) (not (vector-ref visited start)))
      (vector-set! visited start #t)
      (vector-set! queue 0 start)
      (let loop ([head 0] [tail 1]
                 [left x] [top y] [right x] [bottom y] [population 0])
        (if (= head tail)
            (set! components
                  (cons (hasheq 'bounds (vector->immutable-vector
                                         (vector left top right bottom))
                                'pixel-count population)
                        components))
            (let* ([index (vector-ref queue head)]
                   [px (remainder index width)]
                   [py (quotient index width)]
                   [tail (if (> px 0) (enqueue-neighbour! (sub1 index) tail) tail)]
                   [tail (if (< px (sub1 width))
                             (enqueue-neighbour! (add1 index) tail)
                             tail)]
                   [tail (if (> py 0) (enqueue-neighbour! (- index width) tail) tail)]
                   [tail (if (< py (sub1 height))
                             (enqueue-neighbour! (+ index width) tail)
                             tail)])
              (loop (add1 head) tail
                    (min left px) (min top py) (max right px) (max bottom py)
                    (add1 population)))))))
  (vector->immutable-vector (list->vector (reverse components))))

(define (check-dimensions who width height)
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (raise-arguments-error who "positive exact image dimensions"
                           "width" width "height" height)))
