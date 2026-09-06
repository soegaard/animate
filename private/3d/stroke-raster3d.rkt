#lang racket/base

;;;
;;; Software Preparation and Rasterization for Mathematical Strokes
;;;

;; Strokes stay centrelines until this module.  The preparation path clips in
;; world/view space, performs dash measurement in its declared space, then
;; makes finite screen-space segments.  Rasterization operates at pixel
;; centres against the same opaque depth target used by mesh triangles.

(require racket/list
         racket/math
         "../color-style.rkt"
         "../geometry.rkt"
         "affine3.rkt"
         "camera3d.rkt"
         "clipping3d.rkt"
         "raster-target3d.rkt"
         "stroke3d.rkt"
         "vec3.rkt")

(provide (struct-out prepared-stroke-segment3d)
         prepare-stroke3d-segments
         rasterize-prepared-strokes!)

;; Positions are pixel coordinates with the usual top-left origin.  Depth is
;; positive camera-forward distance; interpolation is reciprocal-depth, just
;; like mesh triangle attributes. `source-progress` is retained for picking.
(struct prepared-stroke-segment3d
  (path start-x start-y start-depth end-x end-y end-depth width style color
        start-world end-world drawing-index source-segment source-start-progress source-end-progress
        source-kind source-metadata)
  #:transparent)

; prepare-stroke3d-segments : (listof symbol?) affine3? vector? boolean?
;                             stroke3d? finite-real? (listof clip-plane3d?)
;                             camera3d? positive-real? width height index -> list?
(define (prepare-stroke3d-segments path world-transform local-points closed? style inherited-opacity
                                   clip-planes camera aspect width height drawing-index
                                   #:source-kind [source-kind 'curve]
                                   #:source-metadata [source-metadata #hasheq()])
  (unless (and (list? path) (andmap symbol? path))
    (raise-argument-error 'prepare-stroke3d-segments "(listof symbol?)" path))
  (unless (affine3? world-transform)
    (raise-argument-error 'prepare-stroke3d-segments "affine3?" world-transform))
  (unless (and (vector? local-points)
               (>= (vector-length local-points) 2)
               (for/and ([point (in-vector local-points)]) (vec3? point)))
    (raise-argument-error 'prepare-stroke3d-segments "vector of at least two vec3?" local-points))
  (unless (boolean? closed?)
    (raise-argument-error 'prepare-stroke3d-segments "boolean?" closed?))
  (unless (stroke3d? style)
    (raise-argument-error 'prepare-stroke3d-segments "stroke3d?" style))
  (unless (and (finite-real? inherited-opacity) (<= 0 inherited-opacity 1))
    (raise-argument-error 'prepare-stroke3d-segments "finite real in [0, 1]" inherited-opacity))
  (unless (and (exact-positive-integer? width) (exact-positive-integer? height))
    (raise-argument-error 'prepare-stroke3d-segments "positive viewport dimensions" (vector width height)))
  (unless (symbol? source-kind)
    (raise-argument-error 'prepare-stroke3d-segments "symbol? as #:source-kind" source-kind))
  (unless (and (hash? source-metadata) (immutable? source-metadata))
    (raise-argument-error 'prepare-stroke3d-segments "immutable hash? as #:source-metadata" source-metadata))
  (define points
    (for/vector ([point (in-vector local-points)])
      (affine3-apply-point world-transform point)))
  (define raw-segments
    (let loop ([index 0] [world-offset 0] [reversed '()])
      (cond [(>= index (sub1 (vector-length points)))
             (if closed?
                 (let* ([first-point (vector-ref points (sub1 (vector-length points)))]
                        [second-point (vector-ref points 0)])
                   (reverse
                    (cons (list index first-point second-point world-offset) reversed)))
                 (reverse reversed))]
            [else
             (define first-point (vector-ref points index))
             (define second-point (vector-ref points (add1 index)))
             (loop (add1 index) (+ world-offset (vec3-distance first-point second-point))
                   (cons (list index first-point second-point world-offset) reversed))])))
  (define clipped
    (for/list ([entry (in-list raw-segments)]
               #:do [(define segment (clip-world-segment camera (second entry) (third entry) clip-planes))]
               #:when segment)
      (list (first entry) (first segment) (second segment) (third segment) (fourth segment)
            (fourth entry))))
  ;; Dash phase accumulates through the clipped centreline in its declared
  ;; metric.  This deliberately keeps screen dashes visually stable under a
  ;; camera orbit while allowing an explicit world-dash style for physical
  ;; construction marks.
  (define phase 0)
  (append*
   (for/list ([entry (in-list clipped)])
     (define source-index (first entry))
     (define first-world (second entry))
     (define second-world (third entry))
     (define source-start (fourth entry))
     (define source-end (fifth entry))
     (define source-world-offset (sixth entry))
     (define first-view (camera3d-world->view camera first-world))
     (define second-view (camera3d-world->view camera second-world))
     (define first-projected (camera3d-project-view camera first-view #:aspect aspect))
     (define second-projected (camera3d-project-view camera second-view #:aspect aspect))
     ;; Near/far clipping above guarantees this. Keeping the guard means an
     ;; unusual camera implementation cannot leak #f into raster arithmetic.
     (cond [(or (not first-projected) (not second-projected)) '()]
           [else
            (define first-screen (ndc->screen first-projected width height))
            (define second-screen (ndc->screen second-projected width height))
            (define metric-length
              (if (eq? (stroke3d-dash-space style) 'screen)
                  (distance2 first-screen second-screen)
                  (vec3-distance first-world second-world)))
            (define dash-phase
              (if (eq? (stroke3d-dash-space style) 'world)
                  (+ source-world-offset
                     (* source-start
                        (vec3-distance
                         (vector-ref points source-index)
                         (if (and closed? (= source-index (sub1 (vector-length points))))
                             (vector-ref points 0)
                             (vector-ref points (add1 source-index))))))
                  phase))
            (define intervals (dash-intervals style dash-phase metric-length))
            (set! phase (+ phase metric-length))
            (for/list ([interval (in-list intervals)])
              (define begin (first interval))
              (define finish (second interval))
              (define start-screen (lerp2 first-screen second-screen begin))
              (define end-screen (lerp2 first-screen second-screen finish))
              (prepared-stroke-segment3d
               path
               (car start-screen) (cdr start-screen)
               (reciprocal-depth-lerp (- (vec3-z first-view)) (- (vec3-z second-view)) begin)
               (car end-screen) (cdr end-screen)
               (reciprocal-depth-lerp (- (vec3-z first-view)) (- (vec3-z second-view)) finish)
               (stroke-width-pixels style first-world second-world camera aspect width height)
               style
               (resolve-stroke-color style inherited-opacity)
               (vec3-lerp first-world second-world begin)
               (vec3-lerp first-world second-world finish)
               drawing-index source-index
               (+ source-start (* begin (- source-end source-start)))
               (+ source-start (* finish (- source-end source-start)))
               source-kind source-metadata))]))))

(define (clip-world-segment camera first-point second-point clips)
  ;; Retain source parameters through every clip. Besides truthful picking,
  ;; this makes world-space dash phase continuous when only the middle of a
  ;; source segment survives an author or near/far plane.
  (let loop ([start 0] [finish 1] [remaining clips])
    (define current-first (vec3-lerp first-point second-point start))
    (define current-second (vec3-lerp first-point second-point finish))
    (cond [(null? remaining)
           (define result (clip-view-depth-parameters camera current-first current-second))
           (and result
                (let ([local-start (first result)] [local-end (second result)])
                  (list (vec3-lerp first-point second-point (+ start (* local-start (- finish start))))
                        (vec3-lerp first-point second-point (+ start (* local-end (- finish start))))
                        (+ start (* local-start (- finish start)))
                        (+ start (* local-end (- finish start))))))]
          [else
           (define result (clip-one-segment-parameters current-first current-second (car remaining)) )
           (and result
                (loop (+ start (* (first result) (- finish start)))
                      (+ start (* (second result) (- finish start)))
                      (cdr remaining)))])))

(define (clip-view-depth-parameters camera first-point second-point)
  (define first-depth (camera3d-view-depth camera first-point))
  (define second-depth (camera3d-view-depth camera second-point))
  (define lower (camera3d-near camera))
  (define upper (camera3d-far camera))
  (define direction (- second-depth first-depth))
  (cond [(zero? direction)
         (and (<= lower first-depth upper) (list 0 1))]
        [else
         (define first-t (/ (- lower first-depth) direction))
         (define second-t (/ (- upper first-depth) direction))
         (define start (max 0 (min first-t second-t)))
         (define finish (min 1 (max first-t second-t)))
         (and (<= start finish) (list start finish))]))

(define (clip-one-segment-parameters first-point second-point clip)
  (define plane (clip-plane3d-plane clip))
  (define sign (if (eq? (clip-plane3d-keep clip) 'positive) 1 -1))
  (define first-distance (* sign (plane-signed-distance plane first-point)))
  (define second-distance (* sign (plane-signed-distance plane second-point)))
  (cond [(and (>= first-distance 0) (>= second-distance 0)) (list 0 1)]
        [(and (< first-distance 0) (< second-distance 0)) #f]
        [else
         (define progress (/ first-distance (- first-distance second-distance)))
         (if (>= first-distance 0)
             (list 0 progress)
             (list progress 1))]))

(define (dash-intervals style phase length)
  (cond [(or (not (stroke3d-dash style)) (zero? length))
         (if (positive? length) (list (list 0 1)) '())]
        [else
         (define pattern (vector->list (stroke3d-dash style)))
         (define total (apply + pattern))
         ;; dash-offset advances the pattern at the start of the centreline.
         (define start (modulo-real (+ phase (stroke3d-dash-offset style)) total))
         (define output '())
         (define consumed 0)
         (let loop ([pattern-index 0] [within start])
           (when (< consumed length)
             (define index (locate-dash-index pattern within))
             (define before (apply + (take pattern index)))
             (define available (- (list-ref pattern index) (- within before)))
             (define amount (min available (- length consumed)))
             (when (even? index)
               (set! output
                     (append output
                             (list (list (/ consumed length)
                                         (/ (+ consumed amount) length))))))
             (set! consumed (+ consumed amount))
             (loop (add1 pattern-index) (modulo-real (+ within amount) total))))
         output]))

(define (locate-dash-index pattern offset)
  (let loop ([index 0] [before 0])
    (define after (+ before (list-ref pattern index)))
    (if (< offset after) index
        (loop (add1 index) after))))

(define (modulo-real value divisor)
  (- value (* divisor (floor (/ value divisor)))))

(define (ndc->screen point width height)
  (cons (* width (/ (+ (vec2-x point) 1) 2))
        (* height (/ (- 1 (vec2-y point)) 2))))

(define (distance2 first second)
  (sqrt (+ (sqr (- (car second) (car first)))
           (sqr (- (cdr second) (cdr first))))))

(define (lerp2 first second progress)
  (cons (+ (car first) (* progress (- (car second) (car first))))
        (+ (cdr first) (* progress (- (cdr second) (cdr first))))))

(define (reciprocal-depth-lerp first-depth second-depth progress)
  (/ 1.0 (+ (/ (- 1 progress) first-depth) (/ progress second-depth))))

(define (stroke-width-pixels style first-world second-world camera aspect width height)
  (cond [(eq? (stroke3d-width-mode style) 'screen) (stroke3d-width style)]
        [else
         ;; Project a short camera-right span at the segment midpoint. This is
         ;; the local screen diameter of a physical world-space stroke; unlike
         ;; a tube it does not gain perspective-dependent polygon faceting.
         (define midpoint (vec3-lerp first-world second-world 1/2))
         (define offset (vec3-scale (/ (stroke3d-width style) 2) (camera3d-right camera)))
         (define first-projected (camera3d-project camera (vec3- midpoint offset) #:aspect aspect))
         (define second-projected (camera3d-project camera (vec3+ midpoint offset) #:aspect aspect))
         (if (and first-projected second-projected)
             (max 1e-6 (distance2 (ndc->screen first-projected width height)
                                  (ndc->screen second-projected width height)))
             0)]))

(define (resolve-stroke-color style inherited-opacity)
  (define source (color-spec->rgba-color (stroke3d-color style) 'prepare-stroke3d-segments))
  (rgba-color (rgba-color-red source) (rgba-color-green source) (rgba-color-blue source)
              (* inherited-opacity (stroke3d-opacity style) (rgba-color-alpha source))))

; rasterize-prepared-strokes! : raster-target3d? (listof prepared-stroke-segment3d?)
;                                (or/c 'test 'hidden 'always) -> exact-nonnegative-integer?
;; `pass` is a renderer-selected pass, so the renderer can honor the required
;; hidden → visible → overlay ordering without mutating any stroke style.
(define (rasterize-prepared-strokes! target segments pass)
  (unless (raster-target3d? target)
    (raise-argument-error 'rasterize-prepared-strokes! "raster-target3d?" target))
  (unless (memq pass '(test hidden always))
    (raise-argument-error 'rasterize-prepared-strokes! "one of 'test, 'hidden, or 'always" pass))
  (define selected
    (filter (lambda (segment)
              (eq? (stroke3d-depth-mode (prepared-stroke-segment3d-style segment)) pass))
            segments))
  ;; Adjacent undashed centreline segments must be one stroked path, not a row
  ;; of independently capped segments.  Suppress their internal caps and add
  ;; the declared join once.  A dash boundary intentionally fails
  ;; `stroke-contiguous?`, retaining two caps on either side of the gap.
  (let loop ([remaining selected] [previous #f] [written 0])
    (if (null? remaining)
        written
        (let* ([segment (car remaining)]
               [successor (and (pair? (cdr remaining)) (cadr remaining))]
               [connects-back? (and previous (stroke-contiguous? previous segment))]
               [connects-forward? (and successor (stroke-contiguous? segment successor))])
          (loop (cdr remaining) segment
                (+ written
                   (if connects-back?
                       (rasterize-stroke-join! target previous segment)
                       0)
                   (rasterize-one-stroke! target segment
                                          #:start-cap? (not connects-back?)
                                          #:end-cap? (not connects-forward?))))))))

(define (rasterize-one-stroke! target segment #:start-cap? [start-cap? #t]
                               #:end-cap? [end-cap? #t])
  (define start-x (prepared-stroke-segment3d-start-x segment))
  (define start-y (prepared-stroke-segment3d-start-y segment))
  (define end-x (prepared-stroke-segment3d-end-x segment))
  (define end-y (prepared-stroke-segment3d-end-y segment))
  (define style (prepared-stroke-segment3d-style segment))
  (define half-width (/ (prepared-stroke-segment3d-width segment) 2))
  (define dx (- end-x start-x))
  (define dy (- end-y start-y))
  (define length-squared (+ (* dx dx) (* dy dy)))
  (define start-extension (if (and start-cap? (eq? (stroke3d-cap style) 'square)) half-width 0))
  (define end-extension (if (and end-cap? (eq? (stroke3d-cap style) 'square)) half-width 0))
  (define extension (max start-extension end-extension))
  (define left (max 0 (inexact->exact (floor (- (min start-x end-x) half-width extension)))))
  (define right (min (sub1 (raster-target3d-width target))
                     (inexact->exact (ceiling (+ (max start-x end-x) half-width extension)))))
  (define top (max 0 (inexact->exact (floor (- (min start-y end-y) half-width extension)))))
  (define bottom (min (sub1 (raster-target3d-height target))
                      (inexact->exact (ceiling (+ (max start-y end-y) half-width extension)))))
  (if (or (zero? length-squared) (> left right) (> top bottom))
      0
      (for*/fold ([written 0]) ([pixel-y (in-range top (add1 bottom))]
                             [pixel-x (in-range left (add1 right))])
        (define point-x (+ pixel-x 1/2))
        (define point-y (+ pixel-y 1/2))
        (define progress (/ (+ (* (- point-x start-x) dx)
                               (* (- point-y start-y) dy))
                            length-squared))
        (define length (sqrt length-squared))
        (define lower-progress (if start-extension (- (/ start-extension length)) 0))
        (define upper-progress (if end-extension (+ 1 (/ end-extension length)) 1))
        (define projected-progress (max lower-progress (min upper-progress progress)))
        (define closest-x (+ start-x (* projected-progress dx)))
        (define closest-y (+ start-y (* projected-progress dy)))
        (define distance (sqrt (+ (sqr (- point-x closest-x)) (sqr (- point-y closest-y)))))
        (define within-segment?
          (case (stroke3d-cap style)
            [(butt) (and (<= lower-progress progress upper-progress) (<= distance half-width))]
            [(square) (and (<= lower-progress progress upper-progress) (<= distance half-width))]
            [else
             (or (and (<= 0 progress 1) (<= distance half-width))
                 (and start-cap? (< progress 0) (<= distance half-width))
                 (and end-cap? (> progress 1) (<= distance half-width)))]))
        (if (not within-segment?)
            written
            (let* ([depth (reciprocal-depth-lerp
                           (prepared-stroke-segment3d-start-depth segment)
                           (prepared-stroke-segment3d-end-depth segment)
                           (max 0 (min 1 progress)))]
                   [index (+ pixel-x (* pixel-y (raster-target3d-width target)))]
                   [old-depth (vector-ref (raster-target3d-depth-values target) index)])
              (if (stroke-depth-accepts? style depth old-depth)
                  (begin
                    (blend-straight-color! target index (prepared-stroke-segment3d-color segment))
                    (add1 written))
                  written))))))

(define (stroke-contiguous? previous current)
  (and (= (prepared-stroke-segment3d-drawing-index previous)
          (prepared-stroke-segment3d-drawing-index current))
       (equal? (prepared-stroke-segment3d-path previous)
               (prepared-stroke-segment3d-path current))
       (equal? (prepared-stroke-segment3d-style previous)
               (prepared-stroke-segment3d-style current))
       (= (prepared-stroke-segment3d-source-end-progress previous) 1)
       (= (prepared-stroke-segment3d-source-start-progress current) 0)
       (= (add1 (prepared-stroke-segment3d-source-segment previous))
          (prepared-stroke-segment3d-source-segment current))
       (equal? (prepared-stroke-segment3d-end-world previous)
               (prepared-stroke-segment3d-start-world current))))

;; Fill the outside corner only.  The two un-capped segment rectangles already
;; cover the inside of a join.  Round joins use a deterministic disc; its
;; interior overlaps only existing stroke coverage and avoids an unstable
;; angle-dependent tessellation count in the software reference renderer.
(define (rasterize-stroke-join! target previous current)
  (define style (prepared-stroke-segment3d-style previous))
  (define half-width (/ (prepared-stroke-segment3d-width previous) 2))
  (define px (prepared-stroke-segment3d-end-x previous))
  (define py (prepared-stroke-segment3d-end-y previous))
  (define first-direction
    (unit2 (- px (prepared-stroke-segment3d-start-x previous))
           (- py (prepared-stroke-segment3d-start-y previous))))
  (define second-direction
    (unit2 (- (prepared-stroke-segment3d-end-x current) px)
           (- (prepared-stroke-segment3d-end-y current) py)))
  (cond [(or (not first-direction) (not second-direction)) 0]
        [else
         (define cross (- (* (car first-direction) (cdr second-direction))
                          (* (cdr first-direction) (car second-direction))))
         (cond [(<= (abs cross) 1e-10) 0]
               [(eq? (stroke3d-join style) 'round)
                (rasterize-stroke-disc! target px py half-width
                                        (prepared-stroke-segment3d-end-depth previous)
                                        previous)]
               [else
                ;; With screen y increasing downward, a positive turn's outer
                ;; side is the right normal, hence the sign inversion here.
                (define side (if (positive? cross) -1 1))
                (define first-normal
                  (cons (* side (- (cdr first-direction)))
                        (* side (car first-direction))))
                (define second-normal
                  (cons (* side (- (cdr second-direction)))
                        (* side (car second-direction))))
                (define first-point (cons (+ px (* half-width (car first-normal)))
                                          (+ py (* half-width (cdr first-normal)))))
                (define second-point (cons (+ px (* half-width (car second-normal)))
                                           (+ py (* half-width (cdr second-normal)))))
                (define miter-point (line-intersection first-point first-direction
                                                       second-point second-direction))
                (define use-miter?
                  (and (eq? (stroke3d-join style) 'miter)
                       miter-point
                       (<= (/ (distance2 miter-point (cons px py)) half-width)
                           (stroke3d-miter-limit style))))
                (if use-miter?
                    (rasterize-stroke-triangle! target first-point miter-point second-point
                                                (prepared-stroke-segment3d-end-depth previous)
                                                previous)
                    (rasterize-stroke-triangle! target first-point (cons px py) second-point
                                                (prepared-stroke-segment3d-end-depth previous)
                                                previous))])]))

(define (unit2 x y)
  (define length (sqrt (+ (sqr x) (sqr y))))
  (and (positive? length) (cons (/ x length) (/ y length))))

(define (line-intersection first-point first-direction second-point second-direction)
  (define determinant (- (* (car first-direction) (cdr second-direction))
                        (* (cdr first-direction) (car second-direction))))
  (and (> (abs determinant) 1e-10)
       (let ([factor (/ (- (* (- (car second-point) (car first-point)) (cdr second-direction))
                           (* (- (cdr second-point) (cdr first-point)) (car second-direction)))
                        determinant)])
         (cons (+ (car first-point) (* factor (car first-direction)))
               (+ (cdr first-point) (* factor (cdr first-direction)))))))

(define (rasterize-stroke-disc! target center-x center-y radius depth segment)
  (rasterize-stroke-shape!
   target (- center-x radius) (+ center-x radius) (- center-y radius) (+ center-y radius)
   depth segment
   (lambda (x y)
     (<= (+ (sqr (- x center-x)) (sqr (- y center-y))) (sqr radius)))))

(define (rasterize-stroke-triangle! target first second third depth segment)
  (rasterize-stroke-shape!
   target (min (car first) (car second) (car third))
   (max (car first) (car second) (car third))
   (min (cdr first) (cdr second) (cdr third))
   (max (cdr first) (cdr second) (cdr third))
   depth segment
   (lambda (x y)
     (define a (cross2 first second (cons x y)))
     (define b (cross2 second third (cons x y)))
     (define c (cross2 third first (cons x y)))
     (or (and (>= a 0) (>= b 0) (>= c 0))
         (and (<= a 0) (<= b 0) (<= c 0))))))

(define (rasterize-stroke-shape! target left right top bottom depth segment contains?)
  (define style (prepared-stroke-segment3d-style segment))
  (for*/fold ([written 0])
             ([pixel-y (in-range (max 0 (inexact->exact (floor top)))
                                 (add1 (min (sub1 (raster-target3d-height target))
                                            (inexact->exact (ceiling bottom)))))]
              [pixel-x (in-range (max 0 (inexact->exact (floor left)))
                                 (add1 (min (sub1 (raster-target3d-width target))
                                            (inexact->exact (ceiling right)))))])
    (define x (+ pixel-x 1/2))
    (define y (+ pixel-y 1/2))
    (if (not (contains? x y))
        written
        (let* ([index (+ pixel-x (* pixel-y (raster-target3d-width target)))]
               [old-depth (vector-ref (raster-target3d-depth-values target) index)])
          (if (stroke-depth-accepts? style depth old-depth)
              (begin
                (blend-straight-color! target index (prepared-stroke-segment3d-color segment))
                (add1 written))
              written)))))

(define (cross2 first second point)
  (- (* (- (car second) (car first)) (- (cdr point) (cdr first)))
     (* (- (cdr second) (cdr first)) (- (car point) (car first)))))

(define (stroke-depth-accepts? style depth old-depth)
  (case (stroke3d-depth-mode style)
    [(always) #t]
    [(test) (<= (- depth (stroke3d-depth-bias style)) old-depth)]
    [(hidden) (and (not (eqv? old-depth +inf.0))
                   (> (+ depth (stroke3d-depth-bias style)) old-depth))]))

(define (blend-straight-color! target index source)
  (define bytes (raster-target3d-color-bytes target))
  (define byte-index (* index 4))
  (define source-alpha (rgba-color-alpha source))
  (define destination-alpha (/ (bytes-ref bytes byte-index) 255.0))
  (define destination-red (bytes-ref bytes (add1 byte-index)))
  (define destination-green (bytes-ref bytes (+ byte-index 2)))
  (define destination-blue (bytes-ref bytes (+ byte-index 3)))
  (define result-alpha (+ source-alpha (* (- 1 source-alpha) destination-alpha)))
  (define (channel source-channel destination-channel)
    (if (zero? result-alpha) 0
        (/ (+ (* source-alpha source-channel)
              (* (- 1 source-alpha) destination-alpha destination-channel))
           result-alpha)))
  (bytes-set! bytes byte-index (channel-byte (* 255 result-alpha)))
  (bytes-set! bytes (add1 byte-index)
              (channel-byte (channel (rgba-color-red source) destination-red)))
  (bytes-set! bytes (+ byte-index 2)
              (channel-byte (channel (rgba-color-green source) destination-green)))
  (bytes-set! bytes (+ byte-index 3)
              (channel-byte (channel (rgba-color-blue source) destination-blue))))

(define (channel-byte value)
  (inexact->exact (round (max 0 (min 255 value)))))
