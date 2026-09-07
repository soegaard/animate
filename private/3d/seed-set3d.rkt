#lang racket/base

;;;
;;; Deterministic Three-Dimensional Seed Sets
;;;

;; A seed set is immutable numerical input to a collection of trajectories.
;; Every constructor establishes a canonical point order.  In particular, the
;; stochastic-looking Poisson constructor owns its small PRNG, so preparing a
;; scene neither observes nor changes Racket's process-global random state.


;;;
;;; Imports and Exports

(require racket/list
         "../geometry.rkt"
         "bounds3.rkt"
         "curve3d.rkt"
         "parametric-surface3d.rkt"
         "plane-basis3d.rkt"
         "ray-plane.rkt"
         "spatial-visual.rkt"
         "vec3.rkt")

(provide seed-set3d?
         seed-set3d-kind
         seed-set3d-points
         seed-set3d-count
         seed-set3d-provenance
         seed-set3d-diagnostics
         seed-set3d-cache-key
         explicit-seeds3d
         grid-seeds3d
         plane-seeds3d
         curve-seeds3d
         surface-seeds3d
         sphere-seeds3d
         poisson-seeds3d)


;;;
;;; Immutable Value

(struct seed-set3d-value (kind points provenance diagnostics cache-key)
  #:transparent)

(define seed-set3d? seed-set3d-value?)

(define (check-seed-set3d who value)
  (unless (seed-set3d? value)
    (raise-argument-error who "seed-set3d?" value)))

(define (seed-set3d-kind value)
  (check-seed-set3d 'seed-set3d-kind value)
  (seed-set3d-value-kind value))

(define (seed-set3d-points value)
  (check-seed-set3d 'seed-set3d-points value)
  (seed-set3d-value-points value))

(define (seed-set3d-count value)
  (vector-length (seed-set3d-points value)))

(define (seed-set3d-provenance value)
  (check-seed-set3d 'seed-set3d-provenance value)
  (seed-set3d-value-provenance value))

(define (seed-set3d-diagnostics value)
  (check-seed-set3d 'seed-set3d-diagnostics value)
  (seed-set3d-value-diagnostics value))

(define (seed-set3d-cache-key value)
  (check-seed-set3d 'seed-set3d-cache-key value)
  (seed-set3d-value-cache-key value))

(define (make-seed-set3d kind points provenance diagnostics cache-key)
  (seed-set3d-value
   kind
   (vector->immutable-vector (list->vector points))
   provenance diagnostics cache-key))


;;;
;;; Explicit and Regular Seed Sets

;; explicit-seeds3d : (or/c (listof vec3?) (vectorof vec3?)) -> seed-set3d?
;; Preserves author declaration order, including deliberately duplicate seeds.
(define (explicit-seeds3d points)
  (define normalized (normalize-points 'explicit-seeds3d points))
  (make-seed-set3d
   'explicit normalized
   (hasheq 'source 'explicit 'count (length normalized))
   (hasheq 'duplicate-points? (has-duplicate-points? normalized))
   (list 'explicit normalized)))

;; grid-seeds3d : #:x-range two-real-range #:y-range two-real-range
;;                #:z-range two-real-range #:counts three-positive-integers
;;                #:order seed-order -> seed-set3d?
;; The final axis changes fastest.  Thus 'xyz is x-major, then y, then z.
(define (grid-seeds3d #:x-range [x-range (list -1 1)]
                      #:y-range [y-range (list -1 1)]
                      #:z-range [z-range (list -1 1)]
                      #:counts [counts (list 3 3 3)]
                      #:order [order 'xyz])
  (define checked-x (normalize-range 'grid-seeds3d "x-range" x-range))
  (define checked-y (normalize-range 'grid-seeds3d "y-range" y-range))
  (define checked-z (normalize-range 'grid-seeds3d "z-range" z-range))
  (define checked-counts (normalize-counts 'grid-seeds3d counts 3))
  (check-seed-order 'grid-seeds3d order)
  (define values
    (hasheq 'x (sample-range checked-x (first checked-counts))
            'y (sample-range checked-y (second checked-counts))
            'z (sample-range checked-z (third checked-counts))))
  (define axes (order->axes order))
  (define points
    (for*/list ([first-value (in-list (hash-ref values (first axes)))]
                [second-value (in-list (hash-ref values (second axes)))]
                [third-value (in-list (hash-ref values (third axes)))])
      (define coordinates
        (hasheq (first axes) first-value
                (second axes) second-value
                (third axes) third-value))
      (vec3 (hash-ref coordinates 'x)
            (hash-ref coordinates 'y)
            (hash-ref coordinates 'z))))
  (make-seed-set3d
   'grid points
   (hasheq 'x-range checked-x 'y-range checked-y 'z-range checked-z
           'counts checked-counts 'order order)
   (hasheq 'regular? #t)
   (list 'grid checked-x checked-y checked-z checked-counts order)))

;; plane-seeds3d : plane3? #:u-range two-real-range #:v-range two-real-range
;;                 #:counts two-positive-integers -> seed-set3d?
(define (plane-seeds3d plane
                       #:u-range [u-range (list -1 1)]
                       #:v-range [v-range (list -1 1)]
                       #:counts [counts (list 3 3)])
  (unless (plane3? plane)
    (raise-argument-error 'plane-seeds3d "plane3?" plane))
  (define checked-u (normalize-range 'plane-seeds3d "u-range" u-range))
  (define checked-v (normalize-range 'plane-seeds3d "v-range" v-range))
  (define checked-counts (normalize-counts 'plane-seeds3d counts 2))
  (define basis (plane3d-basis plane))
  (define points
    (for*/list ([u (in-list (sample-range checked-u (first checked-counts)))]
                [v (in-list (sample-range checked-v (second checked-counts)))])
      (plane-basis3d-unproject basis (vector u v))))
  (make-seed-set3d
   'plane points
   (hasheq 'plane plane 'u-range checked-u 'v-range checked-v
           'counts checked-counts)
   (hasheq 'basis-u (plane-basis3d-u basis) 'basis-v (plane-basis3d-v basis))
   (list 'plane plane checked-u checked-v checked-counts)))


;;;
;;; Existing Geometric Values

;; curve-seeds3d : curve3d? #:count positive-integer?
;;                 #:spacing (or/c 'parameter 'arc-length) -> seed-set3d?
;; `parameter` distributes across the source curve's stored samples; it does
;; not claim an unavailable author procedure parameterization.
(define (curve-seeds3d curve
                       #:count [count 8]
                       #:spacing [spacing 'arc-length])
  (unless (curve3d? curve)
    (raise-argument-error 'curve-seeds3d "curve3d?" curve))
  (check-positive-integer 'curve-seeds3d "count" count)
  (unless (memq spacing '(parameter arc-length))
    (raise-argument-error 'curve-seeds3d "'parameter or 'arc-length" spacing))
  (define closed? (curve3d-closed? curve))
  (define positions (sample-progress count closed?))
  (define points
    (for/list ([progress (in-list positions)])
      (case spacing
        [(arc-length) (curve3d-point-at curve progress)]
        [else (curve-sample-parameter-point curve progress)])))
  (make-seed-set3d
   'curve points
   (hasheq 'curve-id (spatial-id curve) 'count count
           'spacing spacing 'closed? closed?)
   (hasheq 'duplicate-points? (has-duplicate-points? points))
   (list 'curve (spatial-id curve) (vector->list (curve3d-points curve))
         count spacing closed?)))

;; surface-seeds3d : surface3d? #:u-count positive-integer?
;;                   #:v-count positive-integer? #:inside-domain? boolean?
;;                   -> seed-set3d?
(define (surface-seeds3d surface
                         #:u-count [u-count 8]
                         #:v-count [v-count 8]
                         #:inside-domain? [inside-domain? #t])
  (unless (surface3d? surface)
    (raise-argument-error 'surface-seeds3d "surface3d?" surface))
  (check-positive-integer 'surface-seeds3d "u-count" u-count)
  (check-positive-integer 'surface-seeds3d "v-count" v-count)
  (unless (boolean? inside-domain?)
    (raise-argument-error 'surface-seeds3d "boolean? as #:inside-domain?" inside-domain?))
  (define u-range (surface3d-u-range surface))
  (define v-range (surface3d-v-range surface))
  (define attempted (* u-count v-count))
  (define points
    (for*/fold ([reversed '()])
               ([u (in-list (sample-range u-range u-count))]
                [v (in-list (sample-range v-range v-count))])
      (define point
        (if inside-domain?
            (surface3d-position-at? surface u v)
            (surface3d-position-at surface u v)))
      (if point (cons point reversed) reversed)))
  (define ordered-points (reverse points))
  (make-seed-set3d
   'surface ordered-points
   (hasheq 'surface-kind (surface3d-kind surface)
           'u-range u-range 'v-range v-range
           'u-count u-count 'v-count v-count 'inside-domain? inside-domain?)
   (hasheq 'attempted attempted 'accepted (length ordered-points)
           'discarded (- attempted (length ordered-points)))
   (list 'surface (surface3d-kind surface) u-range v-range
         u-count v-count inside-domain?)))


;;;
;;; Sphere and Poisson Seed Sets

;; sphere-seeds3d : vec3? nonnegative-finite-real? #:count positive-integer?
;;                  #:method 'fibonacci -> seed-set3d?
(define (sphere-seeds3d center radius
                        #:count [count 64]
                        #:method [method 'fibonacci])
  (check-vec3 'sphere-seeds3d center)
  (unless (and (finite-real? radius) (>= radius 0))
    (raise-arguments-error 'sphere-seeds3d "nonnegative finite radius"
                           "radius" radius))
  (check-positive-integer 'sphere-seeds3d "count" count)
  (unless (eq? method 'fibonacci)
    (raise-argument-error 'sphere-seeds3d "'fibonacci" method))
  ;; Golden-angle spiral, sampled at cell centres.  This has no polar double
  ;; points and gives a single, deterministic answer even for count = 1.
  (define golden-angle (* (acos -1) (- 3 (sqrt 5))))
  (define points
    (for/list ([index (in-range count)])
      (define y (- 1 (/ (* 2 (+ index 1/2)) count)))
      (define radial (sqrt (max 0 (- 1 (* y y)))))
      (define angle (* index golden-angle))
      (vec3+ center
             (vec3-scale radius
                         (vec3 (* radial (cos angle)) y
                               (* radial (sin angle)))))))
  (make-seed-set3d
   'sphere points
   (hasheq 'center center 'radius radius 'count count 'method method)
   (hasheq 'uniformity 'fibonacci)
   (list 'sphere center radius count method)))

;; poisson-seeds3d : aabb3? #:minimum-distance positive-finite-real?
;;                    #:count-limit exact-nonnegative-integer?
;;                    #:seed exact-integer? -> seed-set3d?
;; Uses FIFO active points and exactly 30 candidate draws per active point.
(define (poisson-seeds3d bounds
                         #:minimum-distance [minimum-distance 1]
                         #:count-limit [count-limit 128]
                         #:seed [seed 0])
  (unless (and (aabb3? bounds) (not (aabb3-empty? bounds)))
    (raise-argument-error 'poisson-seeds3d "nonempty aabb3?" bounds))
  (unless (and (finite-real? minimum-distance) (positive? minimum-distance))
    (raise-arguments-error 'poisson-seeds3d "positive finite minimum distance"
                           "minimum-distance" minimum-distance))
  (unless (exact-nonnegative-integer? count-limit)
    (raise-arguments-error 'poisson-seeds3d "nonnegative exact integer"
                           "count-limit" count-limit))
  (unless (exact-integer? seed)
    (raise-arguments-error 'poisson-seeds3d "exact integer seed" "seed" seed))
  (define candidate-count 30)
  (define minimum (aabb3-minimum bounds))
  (define maximum (aabb3-maximum bounds))
  (define cell-size (/ minimum-distance (sqrt 3)))
  (define-values (first-point first-state)
    (stable-random-point-in-box minimum maximum seed))
  (define-values (points attempts)
    (if (zero? count-limit)
        (values '() 0)
        (poisson-points3d minimum maximum minimum-distance cell-size candidate-count
                          count-limit first-point first-state)))
  (make-seed-set3d
   'poisson points
   (hasheq 'bounds bounds 'minimum-distance minimum-distance
           'count-limit count-limit 'seed seed)
   (hasheq 'candidate-count candidate-count 'attempts attempts
           'accepted (length points) 'exhausted? (< (length points) count-limit))
   (list 'poisson bounds minimum-distance count-limit seed)))


;;;
;;; Deterministic Poisson Implementation

;; SplitMix64.  Exact integer arithmetic makes the state transition stable;
;; only the subsequent geometric trigonometry is inexact, just as in sphere
;; sampling.  No value here calls `random`, `random-seed`, or accesses a
;; process-global generator.
(define u64-modulus (expt 2 64))
(define u64-mask (sub1 u64-modulus))

(define (u64 value) (bitwise-and value u64-mask))

(define (splitmix64-next state)
  (define next-state (u64 (+ state #x9E3779B97F4A7C15)))
  (define z1 (u64 (* (bitwise-xor next-state (arithmetic-shift next-state -30))
                     #xBF58476D1CE4E5B9)))
  (define z2 (u64 (* (bitwise-xor z1 (arithmetic-shift z1 -27))
                     #x94D049BB133111EB)))
  (values (u64 (bitwise-xor z2 (arithmetic-shift z2 -31))) next-state))

(define (stable-unit state)
  (define-values (word next-state) (splitmix64-next (u64 state)))
  (values (/ (exact->inexact word) (exact->inexact u64-modulus)) next-state))

(define (stable-random-point-in-box minimum maximum state)
  (define-values (x state-x) (stable-unit state))
  (define-values (y state-y) (stable-unit state-x))
  (define-values (z state-z) (stable-unit state-y))
  (values
   (vec3 (+ (vec3-x minimum) (* x (- (vec3-x maximum) (vec3-x minimum))))
         (+ (vec3-y minimum) (* y (- (vec3-y maximum) (vec3-y minimum))))
         (+ (vec3-z minimum) (* z (- (vec3-z maximum) (vec3-z minimum)))))
   state-z))

(define (poisson-points3d minimum maximum minimum-distance cell-size
                          candidate-count count-limit first-point initial-state)
  (define initial-grid
    (hash-set (hash) (poisson-cell minimum cell-size first-point) (list first-point)))
  (let loop ([queue (list first-point)] [reversed-points (list first-point)]
             [grid initial-grid] [state initial-state] [attempts 0])
    (cond [(or (null? queue) (>= (length reversed-points) count-limit))
           (values (reverse reversed-points) attempts)]
          [else
           (define parent (car queue))
           (define rest-queue (cdr queue))
           (define-values (new-points new-grid new-state new-attempts)
             (poisson-candidates3d
              parent minimum maximum minimum-distance cell-size candidate-count
              (- count-limit (length reversed-points)) grid state attempts))
           ;; `new-points` is in candidate acceptance order.  Appending it at
           ;; the queue tail implements FIFO active processing exactly.
           (loop (append rest-queue new-points)
                 (append (reverse new-points) reversed-points)
                 new-grid new-state new-attempts)])))

(define (poisson-candidates3d parent minimum maximum minimum-distance cell-size
                              candidate-count remaining grid initial-state attempts)
  (let loop ([index 0] [accepted '()] [current-grid grid]
             [state initial-state] [current-attempts attempts])
    (cond [(or (= index candidate-count) (>= (length accepted) remaining))
           (values (reverse accepted) current-grid state current-attempts)]
          [else
           (define-values (candidate next-state)
             (poisson-candidate3d parent minimum-distance state))
           (define valid?
             (and (point-in-box? candidate minimum maximum)
                  (poisson-far-enough? candidate minimum cell-size
                                       minimum-distance current-grid)))
           (if valid?
               (let* ([cell (poisson-cell minimum cell-size candidate)]
                      [next-grid
                       (hash-set current-grid cell
                                 (cons candidate (hash-ref current-grid cell '())))])
                 (loop (add1 index) (cons candidate accepted) next-grid next-state
                       (add1 current-attempts)))
               (loop (add1 index) accepted current-grid next-state
                     (add1 current-attempts)))])))

(define (poisson-candidate3d parent minimum-distance state)
  (define-values (first state-1) (stable-unit state))
  (define-values (second state-2) (stable-unit state-1))
  (define-values (third state-3) (stable-unit state-2))
  (define z (- 1 (* 2 first)))
  (define radial (sqrt (max 0 (- 1 (* z z)))))
  (define angle (* 2 (acos -1) second))
  (define distance (* minimum-distance (+ 1 third)))
  (values
   (vec3+ parent
          (vec3-scale distance
                      (vec3 (* radial (cos angle)) z (* radial (sin angle)))))
   state-3))

(define (poisson-cell minimum cell-size point)
  (vector (inexact->exact (floor (/ (- (vec3-x point) (vec3-x minimum)) cell-size)))
          (inexact->exact (floor (/ (- (vec3-y point) (vec3-y minimum)) cell-size)))
          (inexact->exact (floor (/ (- (vec3-z point) (vec3-z minimum)) cell-size)))))

(define (poisson-far-enough? point minimum cell-size minimum-distance grid)
  (define cell (poisson-cell minimum cell-size point))
  (for*/and ([x (in-range (- (vector-ref cell 0) 2) (+ (vector-ref cell 0) 3))]
             [y (in-range (- (vector-ref cell 1) 2) (+ (vector-ref cell 1) 3))]
             [z (in-range (- (vector-ref cell 2) 2) (+ (vector-ref cell 2) 3))]
             [other (in-list (hash-ref grid (vector x y z) '()))])
    (>= (vec3-distance point other) minimum-distance)))


;;;
;;; Shared Local Helpers

(define (normalize-points who points)
  (unless (or (list? points) (vector? points))
    (raise-argument-error who "list or vector of vec3? values" points))
  (define normalized (if (vector? points) (vector->list points) points))
  (for ([point (in-list normalized)])
    (unless (vec3? point)
      (raise-argument-error who "list or vector of vec3? values" points)))
  normalized)

(define (normalize-range who name range)
  (unless (and (list? range) (= (length range) 2)
               (finite-real? (first range)) (finite-real? (second range))
               (<= (first range) (second range)))
    (raise-arguments-error who "two nondecreasing finite endpoints" name range))
  range)

(define (normalize-counts who counts expected-length)
  (unless (and (list? counts) (= (length counts) expected-length)
               (andmap exact-positive-integer? counts))
    (raise-arguments-error who
                           (format "list of ~a positive exact integers" expected-length)
                           "counts" counts))
  counts)

(define (check-positive-integer who name value)
  (unless (exact-positive-integer? value)
    (raise-arguments-error who "positive exact integer" name value)))

(define (check-vec3 who value)
  (unless (vec3? value)
    (raise-argument-error who "vec3?" value)))

(define (check-seed-order who value)
  (unless (memq value '(xyz xzy yxz yzx zxy zyx))
    (raise-argument-error who
                          "one of 'xyz, 'xzy, 'yxz, 'yzx, 'zxy, or 'zyx"
                          value)))

(define (order->axes order)
  (case order
    [(xyz) '(x y z)] [(xzy) '(x z y)] [(yxz) '(y x z)]
    [(yzx) '(y z x)] [(zxy) '(z x y)] [else '(z y x)]))

(define (sample-range range count)
  (define start (first range))
  (define end (second range))
  (if (= count 1)
      (list (/ (+ start end) 2))
      (for/list ([index (in-range count)])
        (+ start (* (/ index (sub1 count)) (- end start))))))

(define (sample-progress count closed?)
  (cond [(= count 1) (list 1/2)]
        [closed? (for/list ([index (in-range count)]) (/ index count))]
        [else (for/list ([index (in-range count)]) (/ index (sub1 count)))]))

(define (curve-sample-parameter-point curve progress)
  (define samples (curve3d-points curve))
  (define length (vector-length samples))
  (define position (* progress (sub1 length)))
  (define lower (inexact->exact (floor position)))
  (define upper (min (sub1 length) (add1 lower)))
  (vec3-lerp (vector-ref samples lower) (vector-ref samples upper)
             (- position lower)))

(define (has-duplicate-points? points)
  (< (length (remove-duplicates points equal?)) (length points)))

(define (point-in-box? point minimum maximum)
  (and (<= (vec3-x minimum) (vec3-x point) (vec3-x maximum))
       (<= (vec3-y minimum) (vec3-y point) (vec3-y maximum))
       (<= (vec3-z minimum) (vec3-z point) (vec3-z maximum))))
