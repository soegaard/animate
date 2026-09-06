#lang racket/base

;;;
;;; Sampled Spatial Curves
;;;

;; Defines immutable curve semantics separately from their tube tessellation.
;; Curve sampling and partial-arc calculations remain exact and deterministic
;; enough to be sampled directly at any timeline time.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "../color-style.rkt"
         "../geometry.rkt"
         "bounds3.rkt"
         "spatial-visual.rkt"
         "transform3.rkt"
         "tube3d.rkt"
         "vec3.rkt")

(provide curve3d?
         curve3d-points
         curve3d-radius
         curve3d-sides
         curve3d-color
         curve3d-width-mode
         curve3d-closed?
         curve3d-local-bounds
         curve3d-with-color
         curve3d-with-id
         polyline3d
         parametric-curve3d
         curve3d->mesh3d
         curve3d-partial
         curve3d-point-at
         curve3d-tangent-at)


;;;
;;; Curve Value
;;;

(struct curve3d-value
  (id transform opacity points radius sides color width-mode closed? local-bounds)
  #:transparent
  #:methods gen:spatial-visual
  [(define (spatial-id curve) (curve3d-value-id curve))
   (define (spatial-transform curve) (curve3d-value-transform curve))
   (define (spatial-with-transform curve transform)
     (unless (transform3? transform)
       (raise-argument-error 'spatial-with-transform "transform3?" transform))
     (struct-copy curve3d-value curve [transform transform]))
   (define (spatial-opacity curve) (curve3d-value-opacity curve))
   (define (spatial-with-opacity curve opacity)
     (unless (spatial-opacity? opacity)
       (raise-argument-error 'spatial-with-opacity "finite real in [0, 1]" opacity))
     (struct-copy curve3d-value curve [opacity opacity]))
   (define (spatial-local-bounds curve) (curve3d-value-local-bounds curve))])

;; curve3d-value represents one sampled curve centre line.
;;  - points      nonempty immutable vector of distinct consecutive vec3 samples.
;;  - radius      physical world radius used by the tube tessellator.
;;  - sides       stable tube radial sample count.
;;  - width-mode  currently `world`; screen widths are intentionally deferred.

(define curve3d? curve3d-value?)
(define curve3d-points curve3d-value-points)
(define curve3d-radius curve3d-value-radius)
(define curve3d-sides curve3d-value-sides)
(define curve3d-color curve3d-value-color)
(define curve3d-width-mode curve3d-value-width-mode)
(define curve3d-closed? curve3d-value-closed?)
(define curve3d-local-bounds curve3d-value-local-bounds)

; curve3d-with-color : curve3d? color-spec? -> curve3d?
;;   Returns the same sampled geometry with a replacement diagram colour.
(define (curve3d-with-color curve color)
  (unless (curve3d? curve)
    (raise-argument-error 'curve3d-with-color "curve3d?" curve))
  (unless (color-spec? color)
    (raise-argument-error 'curve3d-with-color "color-spec?" color))
  (struct-copy curve3d-value curve [color color]))

;; `curve3d-with-id` is a small internal composition helper: transient curve
;; overlays must have their own sibling identity while retaining all source
;; geometry and authored styling.
(define (curve3d-with-id curve id)
  (unless (curve3d? curve)
    (raise-argument-error 'curve3d-with-id "curve3d?" curve))
  (unless (symbol? id)
    (raise-argument-error 'curve3d-with-id "symbol?" id))
  (struct-copy curve3d-value curve [id id]))


;;;
;;; Public Constructors
;;;

; polyline3d : (or/c (listof vec3?) (vectorof vec3?)) #:id symbol? ... -> curve3d?
;;   Creates a tube-rendered spatial polyline with stable supplied sample order.
(define (polyline3d points
                    #:id id
                    #:radius [radius 1/20]
                    #:sides [sides 8]
                    #:closed? [closed? #f]
                    #:color [color "steelblue"]
                    #:transform [transform identity-transform3]
                    #:opacity [opacity 1]
                    #:width-mode [width-mode 'world])
  (unless (symbol? id) (raise-argument-error 'polyline3d "symbol?" id))
  (unless (and (finite-real? radius) (positive? radius))
    (raise-argument-error 'polyline3d "positive finite radius" radius))
  (unless (and (exact-integer? sides) (>= sides 3))
    (raise-argument-error 'polyline3d "exact integer at least 3" sides))
  (unless (boolean? closed?) (raise-argument-error 'polyline3d "boolean?" closed?))
  (unless (transform3? transform) (raise-argument-error 'polyline3d "transform3?" transform))
  (unless (spatial-opacity? opacity)
    (raise-argument-error 'polyline3d "finite real in [0, 1]" opacity))
  (unless (eq? width-mode 'world)
    (raise-arguments-error
     'polyline3d
     "a physical `world` width; depth-aware screen widths are not implemented"
     "width-mode" width-mode))
  (define samples (tube3d-sanitize-points points #:closed? closed?))
  (when (< (length samples) 2)
    (raise-arguments-error 'polyline3d "at least two distinct points" "points" points))
  (curve3d-value id transform opacity (vector->immutable-vector (list->vector samples))
                 radius sides color width-mode closed?
                 (expanded-bounds samples radius)))

; parametric-curve3d : (finite-real? -> vec3?) #:range pair-or-two-list?
;                      #:samples exact-integer? #:id symbol? ... -> curve3d?
;;   Samples procedure at deterministic equally-spaced parameter locations,
;; including both authored range endpoints.
(define (parametric-curve3d procedure
                            #:range [range (list 0 1)]
                            #:samples [samples 64]
                            #:id id
                            #:radius [radius 1/20]
                            #:sides [sides 8]
                            #:closed? [closed? #f]
                            #:color [color "steelblue"]
                            #:transform [transform identity-transform3]
                            #:opacity [opacity 1]
                            #:width-mode [width-mode 'world])
  (unless (procedure? procedure)
    (raise-argument-error 'parametric-curve3d "procedure?" procedure))
  (unless (and (exact-integer? samples) (>= samples 2))
    (raise-argument-error 'parametric-curve3d "exact integer at least 2" samples))
  (define-values (start end) (curve-range 'parametric-curve3d range))
  (polyline3d
   (for/list ([index (in-range samples)])
     (define parameter
       (+ start (* (/ index (sub1 samples)) (- end start))))
     (define point (procedure parameter))
     (unless (vec3? point)
       (raise-arguments-error 'parametric-curve3d
                              "a procedure returning vec3? at every sample"
                              "parameter" parameter "result" point))
     point)
   #:id id #:radius radius #:sides sides #:closed? closed? #:color color
   #:transform transform #:opacity opacity #:width-mode width-mode))


;;;
;;; Rendering and Arc-Length Queries
;;;

; curve3d->mesh3d : curve3d? -> mesh3d?
;;   Lowers one semantic curve to its deterministic tube mesh at render time.
(define (curve3d->mesh3d curve)
  (unless (curve3d? curve)
    (raise-argument-error 'curve3d->mesh3d "curve3d?" curve))
  (tube3d-mesh (curve3d-points curve)
               #:id (spatial-id curve) #:radius (curve3d-radius curve)
               #:sides (curve3d-sides curve) #:closed? (curve3d-closed? curve)
               #:color (curve3d-color curve) #:transform (spatial-transform curve)
               #:opacity (spatial-opacity curve)))

; curve3d-partial : curve3d? unit-real? unit-real? -> curve3d?
;;   Returns the direct arc-length subcurve from start progress to end progress.
;;   It never consults previous frames or stores reveal history.
(define (curve3d-partial curve start end)
  (unless (curve3d? curve)
    (raise-argument-error 'curve3d-partial "curve3d?" curve))
  (check-progress 'curve3d-partial start)
  (check-progress 'curve3d-partial end)
  (when (> start end)
    (raise-arguments-error 'curve3d-partial "start no later than end"
                           "start" start "end" end))
  (define samples (vector->list (curve3d-points curve)))
  (define partial-points (arc-subsequence samples start end (curve3d-closed? curve)))
  ;; A zero-length requested span must remain a valid, renderable but empty
  ;; curve representation.  Reuse a tiny coincident-free segment at its point
  ;; and hide it with opacity 0; this preserves path identity for sampling.
  (if (< (length partial-points) 2)
      (struct-copy curve3d-value curve [opacity 0])
      (polyline3d partial-points
                  #:id (spatial-id curve) #:radius (curve3d-radius curve)
                  #:sides (curve3d-sides curve) #:closed? #f
                  #:color (curve3d-color curve)
                  #:transform (spatial-transform curve)
                  #:opacity (spatial-opacity curve)
                  #:width-mode (curve3d-width-mode curve))))

; curve3d-point-at : curve3d? unit-real? -> vec3?
;;   Returns the deterministic centre-line point at an arc-length fraction.
(define (curve3d-point-at curve progress)
  (unless (curve3d? curve)
    (raise-argument-error 'curve3d-point-at "curve3d?" curve))
  (check-progress 'curve3d-point-at progress)
  (cond [(zero? progress) (vector-ref (curve3d-points curve) 0)]
        [(= progress 1)
         (if (curve3d-closed? curve)
             (vector-ref (curve3d-points curve) 0)
             (vector-ref (curve3d-points curve)
                         (sub1 (vector-length (curve3d-points curve)))))]
        [else
         (arc-point (vector->list (curve3d-points curve))
                    progress (curve3d-closed? curve))]))

; curve3d-tangent-at : curve3d? unit-real? -> vec3?
;;   Returns a nonzero unit tangent from the arc segment containing progress.
(define (curve3d-tangent-at curve progress)
  (unless (curve3d? curve)
    (raise-argument-error 'curve3d-tangent-at "curve3d?" curve))
  (check-progress 'curve3d-tangent-at progress)
  (arc-tangent (vector->list (curve3d-points curve)) progress (curve3d-closed? curve)))


;;;
;;; Local Helpers
;;;

(define (expanded-bounds points radius)
  (define bounds (aabb3-from-points points))
  (define minimum (aabb3-minimum bounds))
  (define maximum (aabb3-maximum bounds))
  (aabb3 (vec3 (- (vec3-x minimum) radius)
               (- (vec3-y minimum) radius)
               (- (vec3-z minimum) radius))
         (vec3 (+ (vec3-x maximum) radius)
               (+ (vec3-y maximum) radius)
               (+ (vec3-z maximum) radius))))

(define (curve-range who range)
  (define endpoints
    (cond [(and (list? range) (= (length range) 2)) range]
          [(pair? range) (list (car range) (cdr range))]
          [else #f]))
  (unless (and endpoints (andmap finite-real? endpoints))
    (raise-argument-error who "pair or two-element list of finite reals" range))
  (values (first endpoints) (second endpoints)))

(define (segments points closed?)
  (append (for/list ([first-point (in-list points)] [second-point (in-list (cdr points))])
            (cons first-point second-point))
          (if closed? (list (cons (last points) (first points))) '())))

(define (arc-point points progress closed?)
  (define selected (arc-segment points progress closed?))
  (vec3-lerp (first selected) (second selected) (third selected)))

(define (arc-tangent points progress closed?)
  (define selected (arc-segment points progress closed?))
  (vec3-normalize (vec3- (second selected) (first selected))))

;; Returns first-point, second-point, and within-segment progress.
(define (arc-segment points progress closed?)
  (define pieces (segments points closed?))
  (define lengths (map (lambda (piece) (vec3-distance (car piece) (cdr piece))) pieces))
  (define total (apply + lengths))
  (define target (* progress total))
  (let loop ([remaining-pieces pieces] [remaining-lengths lengths] [before 0])
    (define piece (car remaining-pieces))
    (define length (car remaining-lengths))
    (if (or (null? (cdr remaining-pieces)) (<= target (+ before length)))
        (list (car piece) (cdr piece)
              (if (zero? length) 0 (/ (- target before) length)))
        (loop (cdr remaining-pieces) (cdr remaining-lengths) (+ before length)))))

(define (arc-subsequence points start end closed?)
  (if (= start end)
      '()
      (let* ([pieces (segments points closed?)]
             [lengths (map (lambda (piece) (vec3-distance (car piece) (cdr piece))) pieces)]
             [total (apply + lengths)]
             [begin (* start total)]
             [finish (* end total)])
        (define reversed '())
        (define offset 0)
        (for ([piece (in-list pieces)] [length (in-list lengths)])
          (define next-offset (+ offset length))
          (when (and (< offset finish) (> next-offset begin))
            (define local-start (max 0 (/ (- begin offset) length)))
            (define local-end (min 1 (/ (- finish offset) length)))
            (define first-point (vec3-lerp (car piece) (cdr piece) local-start))
            (define second-point (vec3-lerp (car piece) (cdr piece) local-end))
            (when (or (null? reversed)
                      (not (zero? (vec3-distance (car reversed) first-point))))
              (set! reversed (cons first-point reversed)))
            (set! reversed (cons second-point reversed)))
          (set! offset next-offset))
        (reverse
         (for/fold ([kept '()]) ([point (in-list (reverse reversed))])
           (cond [(null? kept) (list point)]
                 [(zero? (vec3-distance point (car kept))) kept]
                 [else (cons point kept)]))))))

(define (check-progress who value)
  (unless (and (finite-real? value) (<= 0 value 1))
    (raise-argument-error who "finite real in [0, 1]" value)))
