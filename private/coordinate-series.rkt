#lang racket/base

;;;
;;; Coordinate Series Paths
;;;

;; Converts ordered numeric-coordinate samples into immutable path geometry
;; aligned with semantic Cartesian axes.
;;
;; This module contains only pure model-level calculations. It does not retain
;; sampling procedures or import Pict, drawing, filesystem, or process modules.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "axes-visual.rkt"
         "geometry.rkt"
         "path-geometry.rkt")

;; Exports
(provide curve-interpolation?
         coordinate-samples->path
         coordinate-y-distance-exceeds?
         coordinate-distance-exceeds?)


;;;
;;; Interpolation Modes
;;;

; curve-interpolation? : any/c -> boolean?
;;   Reports whether value names a supported coordinate-curve interpolation.
(define (curve-interpolation? value)
  (and (symbol? value)
       (memq value '(linear smooth))
       #t))


;;;
;;; Data Representation
;;;

(struct coordinate-segment (start end)
  #:transparent)

;; coordinate-segment represents one accepted numeric-coordinate line segment.
;;  - start  vec2?  first numeric coordinate.
;;  - end    vec2?  second numeric coordinate.


;;;
;;; Coordinate-Series Conversion
;;;

; coordinate-samples->path : axes-visual?
;                            (listof (or/c vec2? false/c))
;                            [#:clip? boolean?]
;                            [#:break-between? (-> vec2? vec2? boolean?)]
;                            [#:interpolation curve-interpolation?]
;                            -> path-geometry?
;;   Converts ordered samples and explicit gaps to axes-local open subpaths.
(define (coordinate-samples->path axes
                                  samples
                                  #:clip? [clip? #t]
                                  #:break-between?
                                  [break-between? never-break-between?]
                                  #:interpolation [interpolation 'linear])
  (check-coordinate-series-arguments axes
                                     samples
                                     clip?
                                     break-between?
                                     interpolation)
  (define maybe-segments
    (coordinate-samples->segments axes
                                  samples
                                  clip?
                                  break-between?))
  (define runs
    (coordinate-segments->runs maybe-segments))
  (coordinate-runs->path axes
                         runs
                         clip?
                         interpolation))

; never-break-between? : vec2? vec2? -> boolean?
;;   Keeps every pair of adjacent finite samples connected.
(define (never-break-between? _start _end)
  #f)


;;;
;;; Segment Construction
;;;

; coordinate-samples->segments : axes-visual?
;                                (listof (or/c vec2? false/c))
;                                boolean?
;                                (-> vec2? vec2? boolean?)
;                                -> (listof (or/c coordinate-segment? false/c))
;;   Converts adjacent samples to clipped segments and explicit breaks.
(define (coordinate-samples->segments axes samples clip? break-between?)
  (cond
    [(or (null? samples)
         (null? (cdr samples)))
     '()]
    [else
     (for/list ([start (in-list samples)]
                [end (in-list (cdr samples))])
       (coordinate-sample-pair->segment axes
                                        start
                                        end
                                        clip?
                                        break-between?))]))

; coordinate-sample-pair->segment : axes-visual?
;                                   (or/c vec2? false/c)
;                                   (or/c vec2? false/c)
;                                   boolean?
;                                   (-> vec2? vec2? boolean?)
;                                   -> (or/c coordinate-segment? false/c)
;;   Returns one accepted segment or an explicit path break.
(define (coordinate-sample-pair->segment axes
                                         start
                                         end
                                         clip?
                                         break-between?)
  (cond
    [(or (not start)
         (not end))
     #f]
    [(checked-break-between? break-between? start end)
     #f]
    [clip?
     (clip-coordinate-segment axes start end)]
    [else
     (coordinate-segment start end)]))

; checked-break-between? : (-> vec2? vec2? any/c) vec2? vec2? -> boolean?
;;   Calls the break predicate and verifies its Boolean result.
(define (checked-break-between? break-between? start end)
  (define result
    (break-between? start end))
  (unless (boolean? result)
    (raise-arguments-error
     'coordinate-samples->path
     "the break predicate must return a Boolean"
     "start" start
     "end" end
     "result" result))
  result)


;;;
;;; Segment Runs
;;;

; coordinate-segments->runs :
;   (listof (or/c coordinate-segment? false/c))
;   -> (listof (listof vec2?))
;;   Collects connected segments into significant ordered point runs.
(define (coordinate-segments->runs maybe-segments)
  (define reversed-runs
    (let loop ([remaining maybe-segments]
               [current-reversed-points '()]
               [runs '()])
      (cond
        [(null? remaining)
         (flush-coordinate-run current-reversed-points runs)]
        [(not (car remaining))
         (loop (cdr remaining)
               '()
               (flush-coordinate-run current-reversed-points runs))]
        [else
         (define segment
           (car remaining))
         (define start
           (coordinate-segment-start segment))
         (define end
           (coordinate-segment-end segment))
         (cond
           [(null? current-reversed-points)
            (loop (cdr remaining)
                  (list end start)
                  runs)]
           [(same-coordinate-point? (car current-reversed-points)
                                    start)
            (loop (cdr remaining)
                  (cons end current-reversed-points)
                  runs)]
           [else
            (loop remaining
                  '()
                  (flush-coordinate-run current-reversed-points
                                        runs))])])))
  (reverse reversed-runs))

; flush-coordinate-run : (listof vec2?) (listof (listof vec2?))
;                        -> (listof (listof vec2?))
;;   Adds one reversed run when it contains at least one stored segment.
(define (flush-coordinate-run reversed-points reversed-runs)
  (if (and (pair? reversed-points)
           (pair? (cdr reversed-points)))
      (cons (reverse reversed-points)
            reversed-runs)
      reversed-runs))


;;;
;;; Path Assembly
;;;

; coordinate-runs->path : axes-visual?
;                         (listof (listof vec2?))
;                         boolean?
;                         curve-interpolation?
;                         -> path-geometry?
;;   Converts ordered numeric-coordinate runs to axes-local path subpaths.
(define (coordinate-runs->path axes runs clip? interpolation)
  (path-geometry
   (for/list ([run (in-list runs)])
     (coordinate-run->subpath axes
                              run
                              clip?
                              interpolation))))

; coordinate-run->subpath : axes-visual?
;                           (listof vec2?)
;                           boolean?
;                           curve-interpolation?
;                           -> path-subpath?
;;   Converts one accepted numeric-coordinate run to one open path subpath.
(define (coordinate-run->subpath axes run clip? interpolation)
  (case interpolation
    [(linear)
     (linear-coordinate-run->subpath axes run)]
    [(smooth)
     (smooth-coordinate-run->subpath axes run clip?)]
    [else
     (raise-argument-error
      'coordinate-run->subpath
      "curve-interpolation?"
      interpolation)]))

; linear-coordinate-run->subpath : axes-visual? (listof vec2?)
;                                  -> path-subpath?
;;   Converts one point run to a piecewise-linear open subpath.
(define (linear-coordinate-run->subpath axes run)
  (path-subpath
   (numeric-coordinate->axes-local axes (car run))
   (for/list ([point (in-list (cdr run))])
     (line-path-segment
      (numeric-coordinate->axes-local axes point)))
   #f))

; smooth-coordinate-run->subpath : axes-visual? (listof vec2?) boolean?
;                                  -> path-subpath?
;;   Converts one point run to an interpolating Catmull-Rom cubic subpath.
(define (smooth-coordinate-run->subpath axes run clip?)
  (define clip-box
    (and clip?
         (axes-coordinate-box axes)))
  (define point-vector
    (list->vector run))
  (define point-count
    (vector-length point-vector))
  (path-subpath
   (numeric-coordinate->axes-local axes (vector-ref point-vector 0))
   (for/list ([index (in-range (sub1 point-count))])
     (define-values (control1 control2 end)
       (smooth-coordinate-segment point-vector point-count index))
     (cubic-bezier-path-segment
      (numeric-coordinate->axes-local
       axes
       (clamp-coordinate-point control1 clip-box))
      (numeric-coordinate->axes-local
       axes
       (clamp-coordinate-point control2 clip-box))
      (numeric-coordinate->axes-local axes end)))
   #f))

; smooth-coordinate-segment : (vectorof vec2?)
;                             exact-positive-integer?
;                             exact-nonnegative-integer?
;                             -> (values vec2? vec2? vec2?)
;;   Returns Catmull-Rom-equivalent cubic controls for one run segment.
(define (smooth-coordinate-segment points point-count index)
  (define start
    (vector-ref points index))
  (define end
    (vector-ref points (add1 index)))
  (cond
    [(= point-count 2)
     (values (safe-vec2-lerp start end 1/3)
             (safe-vec2-lerp start end 2/3)
             end)]
    [else
     (define previous
       (if (zero? index)
           start
           (vector-ref points (sub1 index))))
     (define following
       (if (= (+ index 2) point-count)
           end
           (vector-ref points (+ index 2))))
     (values
      (safe-control-point start end previous 1/6)
      (safe-control-point end start following 1/6)
      end)]))

; safe-control-point : vec2? vec2? vec2? finite-real? -> vec2?
;;   Adds a scaled coordinate difference with exact overflow fallback.
(define (safe-control-point base positive negative factor)
  (vec2 (stable-control-coordinate (vec2-x base)
                                   (vec2-x positive)
                                   (vec2-x negative)
                                   factor)
        (stable-control-coordinate (vec2-y base)
                                   (vec2-y positive)
                                   (vec2-y negative)
                                   factor)))

; stable-control-coordinate : finite-real? finite-real? finite-real?
;                             finite-real? -> finite-real?
;;   Computes base plus factor times a difference without retaining overflow.
(define (stable-control-coordinate base positive negative factor)
  (define direct
    (+ base
       (* factor
          (- positive negative))))
  (if (finite-real? direct)
      direct
      (+ (real->exact base)
         (* (real->exact factor)
            (- (real->exact positive)
               (real->exact negative))))))

; safe-vec2-lerp : vec2? vec2? finite-real? -> vec2?
;;   Interpolates one coordinate point with exact overflow fallback.
(define (safe-vec2-lerp start end progress)
  (vec2 (stable-segment-coordinate (vec2-x start)
                                   (vec2-x end)
                                   progress)
        (stable-segment-coordinate (vec2-y start)
                                   (vec2-y end)
                                   progress)))

; numeric-coordinate->axes-local : axes-visual? vec2? -> vec2?
;;   Maps one numeric coordinate to untransformed local axes geometry.
(define (numeric-coordinate->axes-local axes point)
  (axes-coordinates->local-point axes
                                 (vec2-x point)
                                 (vec2-y point)))


;;;
;;; Rectangular Clipping
;;;

; axes-coordinate-box : axes-visual?
;                       -> (vector/c finite-real? finite-real?
;                                    finite-real? finite-real?)
;;   Returns the axes rectangle as x-min, x-max, y-min, and y-max.
(define (axes-coordinate-box axes)
  (define x-range
    (axes-visual-x-range axes))
  (define y-range
    (axes-visual-y-range axes))
  (vector (axis-range-minimum x-range)
          (axis-range-maximum x-range)
          (axis-range-minimum y-range)
          (axis-range-maximum y-range)))

; clip-coordinate-segment : axes-visual? vec2? vec2?
;                           -> (or/c coordinate-segment? false/c)
;;   Clips one numeric-coordinate segment to the displayed axes rectangle.
(define (clip-coordinate-segment axes start end)
  (define box
    (axes-coordinate-box axes))
  (define x-min
    (vector-ref box 0))
  (define x-max
    (vector-ref box 1))
  (define y-min
    (vector-ref box 2))
  (define y-max
    (vector-ref box 3))
  (define-values (lower upper accepted?)
    (line-clip-parameter-interval start
                                  end
                                  x-min
                                  x-max
                                  y-min
                                  y-max))
  (cond
    [(not accepted?)
     #f]
    [else
     (define clipped-start
       (clamped-segment-point start
                              end
                              lower
                              x-min
                              x-max
                              y-min
                              y-max))
     (define clipped-end
       (clamped-segment-point start
                              end
                              upper
                              x-min
                              x-max
                              y-min
                              y-max))
     (if (same-coordinate-point? clipped-start clipped-end)
         #f
         (coordinate-segment clipped-start clipped-end))]))

; line-clip-parameter-interval : vec2? vec2?
;                                finite-real? finite-real?
;                                finite-real? finite-real?
;                                -> (values real? real? boolean?)
;;   Computes the accepted Liang-Barsky parameter interval for one segment.
(define (line-clip-parameter-interval start end x-min x-max y-min y-max)
  (define start-x
    (vec2-x start))
  (define start-y
    (vec2-y start))
  (define end-x
    (vec2-x end))
  (define end-y
    (vec2-y end))
  (define exact-fallback?
    (ormap nonfinite-difference?
           (list (cons end-x start-x)
                 (cons end-y start-y)
                 (cons start-x x-min)
                 (cons x-max start-x)
                 (cons start-y y-min)
                 (cons y-max start-y))))
  (define (clip-number value)
    (if exact-fallback?
        (real->exact value)
        value))
  (define clipped-start-x
    (clip-number start-x))
  (define clipped-start-y
    (clip-number start-y))
  (define clipped-end-x
    (clip-number end-x))
  (define clipped-end-y
    (clip-number end-y))
  (define clipped-x-min
    (clip-number x-min))
  (define clipped-x-max
    (clip-number x-max))
  (define clipped-y-min
    (clip-number y-min))
  (define clipped-y-max
    (clip-number y-max))
  (define dx
    (- clipped-end-x clipped-start-x))
  (define dy
    (- clipped-end-y clipped-start-y))
  (define constraints
    (list
     (cons (- dx)
           (- clipped-start-x clipped-x-min))
     (cons dx
           (- clipped-x-max clipped-start-x))
     (cons (- dy)
           (- clipped-start-y clipped-y-min))
     (cons dy
           (- clipped-y-max clipped-start-y))))
  (for/fold ([lower 0]
             [upper 1]
             [accepted? #t])
            ([constraint (in-list constraints)])
    (cond
      [(not accepted?)
       (values lower upper #f)]
      [else
       (define p
         (car constraint))
       (define q
         (cdr constraint))
       (cond
         [(zero? p)
          (values lower upper (not (negative? q)))]
         [(negative? p)
          (define ratio
            (/ q p))
          (if (> ratio upper)
              (values lower upper #f)
              (values (max lower ratio) upper #t))]
         [else
          (define ratio
            (/ q p))
          (if (< ratio lower)
              (values lower upper #f)
              (values lower (min upper ratio) #t))])])))

; clamped-segment-point : vec2? vec2? real?
;                         finite-real? finite-real?
;                         finite-real? finite-real?
;                         -> vec2?
;;   Returns one clipped segment point, clamped against roundoff at the box.
(define (clamped-segment-point start end progress
                               x-min x-max y-min y-max)
  (vec2 (clamp-real
         (stable-segment-coordinate (vec2-x start)
                                    (vec2-x end)
                                    progress)
         x-min
         x-max)
        (clamp-real
         (stable-segment-coordinate (vec2-y start)
                                    (vec2-y end)
                                    progress)
         y-min
         y-max)))

; clamp-coordinate-point : vec2? (or/c vector? false/c) -> vec2?
;;   Clamps one smooth control point to the closed axes rectangle when supplied.
(define (clamp-coordinate-point point box)
  (cond
    [(not box)
     point]
    [else
     (vec2 (clamp-real (vec2-x point)
                       (vector-ref box 0)
                       (vector-ref box 1))
           (clamp-real (vec2-y point)
                       (vector-ref box 2)
                       (vector-ref box 3)))]))

; stable-segment-coordinate : finite-real? finite-real? real? -> finite-real?
;;   Interpolates one coordinate with exact fallback after inexact overflow.
(define (stable-segment-coordinate start end progress)
  (define direct-difference
    (- end start))
  (define direct
    (+ start
       (* progress direct-difference)))
  (if (and (finite-real? direct-difference)
           (finite-real? direct))
      direct
      (+ (real->exact start)
         (* (real->exact progress)
            (- (real->exact end)
               (real->exact start))))))

; clamp-real : real? finite-real? finite-real? -> finite-real?
;;   Clamps value to the closed finite interval from minimum to maximum.
(define (clamp-real value minimum maximum)
  (min maximum
       (max minimum value)))


;;;
;;; Distance Rules
;;;

; coordinate-y-distance-exceeds? : vec2? vec2? nonnegative-finite-real?
;                                  -> boolean?
;;   Reports whether the absolute numeric y difference exceeds threshold.
(define (coordinate-y-distance-exceeds? start end threshold)
  (check-distance-arguments 'coordinate-y-distance-exceeds?
                            start
                            end
                            threshold)
  (> (abs (safe-real-difference (vec2-y end)
                                (vec2-y start)))
     threshold))

; coordinate-distance-exceeds? : vec2? vec2? nonnegative-finite-real?
;                                -> boolean?
;;   Reports whether the Euclidean numeric-coordinate distance exceeds threshold.
(define (coordinate-distance-exceeds? start end threshold)
  (check-distance-arguments 'coordinate-distance-exceeds?
                            start
                            end
                            threshold)
  (define dx
    (abs (safe-real-difference (vec2-x end)
                               (vec2-x start))))
  (define dy
    (abs (safe-real-difference (vec2-y end)
                               (vec2-y start))))
  (define scale
    (max dx dy))
  (cond
    [(zero? scale)
     #f]
    [(> scale threshold)
     #t]
    [else
     (define normalized-square
       (+ (sqr (/ dx scale))
          (sqr (/ dy scale))))
     (define normalized-threshold
       (/ threshold scale))
     (> normalized-square
        (sqr normalized-threshold))]))

; sqr : real? -> real?
;;   Returns the square of value.
(define (sqr value)
  (* value value))


;;;
;;; Validation and Numeric Helpers
;;;

; check-coordinate-series-arguments : any/c any/c any/c any/c any/c -> void?
;;   Validates shared coordinate-series arguments before any predicate calls.
(define (check-coordinate-series-arguments axes
                                           samples
                                           clip?
                                           break-between?
                                           interpolation)
  (unless (axes-visual? axes)
    (raise-argument-error
     'coordinate-samples->path
     "axes-visual?"
     axes))
  (unless (and (list? samples)
               (andmap coordinate-sample? samples))
    (raise-argument-error
     'coordinate-samples->path
     "list of vec2 values and #f gaps"
     samples))
  (unless (boolean? clip?)
    (raise-argument-error
     'coordinate-samples->path
     "boolean?"
     clip?))
  (unless (and (procedure? break-between?)
               (procedure-arity-includes? break-between? 2))
    (raise-argument-error
     'coordinate-samples->path
     "procedure accepting two arguments"
     break-between?))
  (unless (curve-interpolation? interpolation)
    (raise-argument-error
     'coordinate-samples->path
     "curve-interpolation?"
     interpolation)))

; coordinate-sample? : any/c -> boolean?
;;   Reports whether value is a finite coordinate sample or an explicit gap.
(define (coordinate-sample? value)
  (or (not value)
      (vec2? value)))

; check-distance-arguments : symbol? any/c any/c any/c -> void?
;;   Validates coordinate points and one nonnegative finite distance.
(define (check-distance-arguments who start end threshold)
  (unless (vec2? start)
    (raise-argument-error who "vec2?" start))
  (unless (vec2? end)
    (raise-argument-error who "vec2?" end))
  (unless (and (finite-real? threshold)
               (not (negative? threshold)))
    (raise-argument-error
     who
     "nonnegative finite real?"
     threshold)))

; nonfinite-difference? : (cons/c finite-real? finite-real?) -> boolean?
;;   Reports whether subtracting the pair would overflow or become non-finite.
(define (nonfinite-difference? values)
  (not (finite-real? (- (car values)
                        (cdr values)))))

; safe-real-difference : finite-real? finite-real? -> finite-real?
;;   Subtracts finite reals without retaining an overflowing inexact result.
(define (safe-real-difference left right)
  (define difference
    (- left right))
  (if (finite-real? difference)
      difference
      (- (real->exact left)
         (real->exact right))))

; real->exact : finite-real? -> exact-real?
;;   Converts one finite inexact real to its exact represented value.
(define (real->exact value)
  (if (exact? value)
      value
      (inexact->exact value)))

; same-coordinate-point? : vec2? vec2? -> boolean?
;;   Reports whether two numeric-coordinate points have equal components.
(define (same-coordinate-point? left right)
  (and (= (vec2-x left)
          (vec2-x right))
       (= (vec2-y left)
          (vec2-y right))))
