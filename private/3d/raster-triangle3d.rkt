#lang racket/base

;;; Pixel-centre Triangle Rasterization

(require racket/list
         "../color-style.rkt"
         "../geometry.rkt"
         "../preview-cancellation.rkt"
         "light3d.rkt"
         "material3d.rkt"
         "raster-target3d.rkt"
         "vec3.rkt")

(provide (struct-out raster-vertex3d)
         raster-triangle3d!)

;; ndc has +y upward.  The rasterizer maps it to a top-left pixel coordinate
;; system while retaining a positive forward depth and one flat normal/color.
(struct raster-vertex3d (ndc depth normal color source) #:transparent)

; raster-triangle3d! : raster-target3d? (vector/c raster-vertex3d? ...)
;                       material3d? (listof light3d?) exact-nonnegative-integer?
;                       [#:write-depth? boolean?] [#:write-color? boolean?]
;                       [#:blend? boolean?]
;                       [#:cancellation-token (or/c #f cancellation-token?)]
;                       -> exact-nonnegative-integer?
;; Returns how many pixels were replaced.  Equal depths resolve to the later
;; larger owner, making co-planar declared draw order independently reproducible.
(define (raster-triangle3d! target triangle material lights owner
                            #:write-depth? [write-depth? #t]
                            #:write-color? [write-color? #t]
                            #:blend? [blend? #f]
                            #:cancellation-token [cancellation-token #f])
  (unless (raster-target3d? target)
    (raise-argument-error 'raster-triangle3d! "raster-target3d?" target))
  (unless (and (vector? triangle) (= (vector-length triangle) 3)
               (for/and ([vertex (in-vector triangle)]) (raster-vertex3d? vertex)))
    (raise-argument-error 'raster-triangle3d! "vector of three raster-vertex3d?" triangle))
  (unless (material3d? material)
    (raise-argument-error 'raster-triangle3d! "material3d?" material))
  (unless (and (list? lights) (andmap light3d? lights))
    (raise-argument-error 'raster-triangle3d! "(listof light3d?)" lights))
  (unless (exact-nonnegative-integer? owner)
    (raise-argument-error 'raster-triangle3d! "exact-nonnegative-integer?" owner))
  (unless (boolean? write-depth?)
    (raise-argument-error 'raster-triangle3d! "boolean? as #:write-depth?" write-depth?))
  (unless (boolean? write-color?)
    (raise-argument-error 'raster-triangle3d! "boolean? as #:write-color?" write-color?))
  (unless (boolean? blend?)
    (raise-argument-error 'raster-triangle3d! "boolean? as #:blend?" blend?))
  (when cancellation-token (check-cancellation cancellation-token))
  (define original (vector->list triangle))
  ;; Front faces are CCW in NDC (the conventional camera-local projected view).
  (define ndc-area (signed-area-ndc original))
  (cond
    [(zero? ndc-area) 0]
    [(and (negative? ndc-area) (not (material3d-double-sided? material))) 0]
    [else
     (define screen-vertices (map (lambda (vertex) (to-screen target vertex)) original))
     ;; In screen (+y down) coordinates an NDC-CCW face has negative area.
     ;; Reverse it before applying the top-left rule, preserving all attributes.
     (define vertices
       (if (negative? (signed-area-screen screen-vertices))
           (list (first screen-vertices) (third screen-vertices) (second screen-vertices))
           screen-vertices))
     (define area (signed-area-screen vertices))
     (if (zero? area)
         0
         (rasterize! target vertices area material lights owner write-depth? write-color? blend?
                     cancellation-token))]))

(struct screen-vertex (x y raster) #:transparent)

(define (to-screen target vertex)
  (define ndc (raster-vertex3d-ndc vertex))
  (screen-vertex (* (raster-target3d-width target) (/ (+ (vec2-x ndc) 1) 2))
                 (* (raster-target3d-height target) (/ (- 1 (vec2-y ndc)) 2))
                 vertex))

(define (signed-area-ndc vertices)
  (define first-ndc (raster-vertex3d-ndc (first vertices)))
  (define second-ndc (raster-vertex3d-ndc (second vertices)))
  (define third-ndc (raster-vertex3d-ndc (third vertices)))
  (cross2 (vec2-x first-ndc) (vec2-y first-ndc)
          (vec2-x second-ndc) (vec2-y second-ndc)
          (vec2-x third-ndc) (vec2-y third-ndc)))

(define (signed-area-screen vertices)
  (cross2 (screen-vertex-x (first vertices)) (screen-vertex-y (first vertices))
          (screen-vertex-x (second vertices)) (screen-vertex-y (second vertices))
          (screen-vertex-x (third vertices)) (screen-vertex-y (third vertices))))

(define (cross2 ax ay bx by cx cy)
  (- (* (- bx ax) (- cy ay)) (* (- by ay) (- cx ax))))

(define (rasterize! target vertices area material lights owner write-depth? write-color? blend? cancellation-token)
  (define first-vertex (first vertices))
  (define second-vertex (second vertices))
  (define third-vertex (third vertices))
  (define left (max 0 (inexact->exact (floor (min (screen-vertex-x first-vertex)
                                                   (screen-vertex-x second-vertex)
                                                   (screen-vertex-x third-vertex))))))
  (define right (min (sub1 (raster-target3d-width target))
                     (sub1 (inexact->exact (ceiling (max (screen-vertex-x first-vertex)
                                                        (screen-vertex-x second-vertex)
                                                        (screen-vertex-x third-vertex)))))))
  (define top (max 0 (inexact->exact (floor (min (screen-vertex-y first-vertex)
                                                  (screen-vertex-y second-vertex)
                                                  (screen-vertex-y third-vertex))))))
  (define bottom (min (sub1 (raster-target3d-height target))
                      (sub1 (inexact->exact (ceiling (max (screen-vertex-y first-vertex)
                                                         (screen-vertex-y second-vertex)
                                                         (screen-vertex-y third-vertex)))))))
  (cond
    [(or (> left right) (> top bottom)) 0]
    [else
     (for/fold ([written 0]) ([pixel-y (in-range top (add1 bottom))])
       (when cancellation-token (check-cancellation cancellation-token))
       (for/fold ([written written]) ([pixel-x (in-range left (add1 right))])
         (define center-x (+ pixel-x 1/2))
         (define center-y (+ pixel-y 1/2))
         (define edge0 (edge (screen-vertex-x second-vertex) (screen-vertex-y second-vertex)
                             (screen-vertex-x third-vertex) (screen-vertex-y third-vertex)
                             center-x center-y))
         (define edge1 (edge (screen-vertex-x third-vertex) (screen-vertex-y third-vertex)
                             (screen-vertex-x first-vertex) (screen-vertex-y first-vertex)
                             center-x center-y))
         (define edge2 (edge (screen-vertex-x first-vertex) (screen-vertex-y first-vertex)
                             (screen-vertex-x second-vertex) (screen-vertex-y second-vertex)
                             center-x center-y))
         (if (and (inside-edge? edge0 second-vertex third-vertex)
                  (inside-edge? edge1 third-vertex first-vertex)
                  (inside-edge? edge2 first-vertex second-vertex))
             (let* ([weight0 (/ edge0 area)]
                    [weight1 (/ edge1 area)]
                    [weight2 (/ edge2 area)]
                    [reciprocal-depth
                     (+ (/ weight0 (raster-vertex3d-depth (screen-vertex-raster first-vertex)))
                        (/ weight1 (raster-vertex3d-depth (screen-vertex-raster second-vertex)))
                        (/ weight2 (raster-vertex3d-depth (screen-vertex-raster third-vertex))))]
                    [depth (/ 1.0 reciprocal-depth)]
                    [perspective-weight0 (/ (/ weight0 (raster-vertex3d-depth (screen-vertex-raster first-vertex)))
                                            reciprocal-depth)]
                    [perspective-weight1 (/ (/ weight1 (raster-vertex3d-depth (screen-vertex-raster second-vertex)))
                                            reciprocal-depth)]
                    [perspective-weight2 (/ (/ weight2 (raster-vertex3d-depth (screen-vertex-raster third-vertex)))
                                            reciprocal-depth)]
                    [color
                     (weighted-color
                      (raster-vertex3d-color (screen-vertex-raster first-vertex))
                      (raster-vertex3d-color (screen-vertex-raster second-vertex))
                      (raster-vertex3d-color (screen-vertex-raster third-vertex))
                      perspective-weight0 perspective-weight1 perspective-weight2)]
                    [normal
                     (if (eq? (material3d-shading material) 'smooth)
                         (safe-normalize
                          (weighted-vector
                           (raster-vertex3d-normal (screen-vertex-raster first-vertex))
                           (raster-vertex3d-normal (screen-vertex-raster second-vertex))
                           (raster-vertex3d-normal (screen-vertex-raster third-vertex))
                           perspective-weight0 perspective-weight1 perspective-weight2)
                          (raster-vertex3d-normal (screen-vertex-raster first-vertex)))
                         (raster-vertex3d-normal (screen-vertex-raster first-vertex)))]
                    [index (+ pixel-x (* pixel-y (raster-target3d-width target)))]
                    [old-depth (vector-ref (raster-target3d-depth-values target) index)]
                    [old-owner (vector-ref (raster-target3d-owner-values target) index)])
               (if (if write-depth?
                       (or (< depth old-depth) (and (= depth old-depth) (> owner old-owner)))
                       (<= depth old-depth))
                   (begin
                     (when write-depth?
                       (vector-set! (raster-target3d-depth-values target) index depth)
                       (vector-set! (raster-target3d-owner-values target) index owner))
                     (when write-color?
                       (write-pixel! target index (shade color normal material lights) #:blend? blend?))
                     (add1 written))
                   written))
             written)))]))

(define (edge ax ay bx by px py)
  (cross2 ax ay bx by px py))

(define (inside-edge? value start end)
  (or (positive? value)
      (and (zero? value) (top-left-edge? start end))))

(define (top-left-edge? start end)
  (define dx (- (screen-vertex-x end) (screen-vertex-x start)))
  (define dy (- (screen-vertex-y end) (screen-vertex-y start)))
  (or (negative? dy) (and (zero? dy) (positive? dx))))

(define (shade color normal material lights)
  (cond
    [(eq? (material3d-shading material) 'unlit) color]
    [else
     (define-values (red green blue)
       (for/fold ([red 0.0] [green 0.0] [blue 0.0]) ([light (in-list lights)])
         (cond
           [(ambient-light3d? light)
            (add-light-color red green blue
                             (ambient-light3d-color light)
                             (* (material3d-ambient material)
                                (ambient-light3d-intensity light)))]
           [else
            (define facing
              (max 0 (vec3-dot normal
                               (vec3-scale -1 (directional-light3d-direction light)))))
            (add-light-color red green blue
                             (directional-light3d-color light)
                             (* (material3d-diffuse material)
                                (directional-light3d-intensity light)
                                facing))])))
     ;; A mathematically unit illumination sum can be
     ;; 1.0000000000000002 in floating point.  Clamp after lighting just as
     ;; weighted vertex colours are clamped, keeping semantic RGBA channels
     ;; valid at saturated colour endpoints.
     (rgba-color (clamp-channel (* (rgba-color-red color) red))
                 (clamp-channel (* (rgba-color-green color) green))
                 (clamp-channel (* (rgba-color-blue color) blue))
                 (rgba-color-alpha color))]))

(define (add-light-color red green blue color amount)
  (values (+ red (* amount (/ (rgba-color-red color) 255)))
          (+ green (* amount (/ (rgba-color-green color) 255)))
          (+ blue (* amount (/ (rgba-color-blue color) 255)))))

(define (weighted-color first-color second-color third-color first-weight second-weight third-weight)
  (rgba-color (clamp-channel (+ (* first-weight (rgba-color-red first-color))
                                (* second-weight (rgba-color-red second-color))
                                (* third-weight (rgba-color-red third-color))))
              (clamp-channel (+ (* first-weight (rgba-color-green first-color))
                                (* second-weight (rgba-color-green second-color))
                                (* third-weight (rgba-color-green third-color))))
              (clamp-channel (+ (* first-weight (rgba-color-blue first-color))
                                (* second-weight (rgba-color-blue second-color))
                                (* third-weight (rgba-color-blue third-color))))
              (max 0 (min 1 (+ (* first-weight (rgba-color-alpha first-color))
                               (* second-weight (rgba-color-alpha second-color))
                               (* third-weight (rgba-color-alpha third-color)))))))

(define (weighted-vector first-vector second-vector third-vector first-weight second-weight third-weight)
  (vec3+ (vec3-scale first-weight first-vector)
         (vec3+ (vec3-scale second-weight second-vector)
                (vec3-scale third-weight third-vector))))

(define (safe-normalize vector fallback)
  (if (zero? (vec3-length vector)) fallback (vec3-normalize vector)))

(define (clamp-channel value)
  (max 0 (min 255 value)))

(define (write-pixel! target index color #:blend? [blend? #f])
  (define bytes (raster-target3d-color-bytes target))
  (define byte-index (* index 4))
  (define final-color
    (if blend?
        (let* ([source-alpha (rgba-color-alpha color)]
               [destination-alpha (/ (bytes-ref bytes byte-index) 255.0)]
               [destination-red (bytes-ref bytes (add1 byte-index))]
               [destination-green (bytes-ref bytes (+ byte-index 2))]
               [destination-blue (bytes-ref bytes (+ byte-index 3))]
               [result-alpha (+ source-alpha (* (- 1 source-alpha) destination-alpha))])
          ;; The target stores straight alpha.  The normal viewport background
          ;; is opaque, but this also keeps semi-transparent backgrounds honest.
          (if (zero? result-alpha)
              (rgba-color 0 0 0 0)
              (rgba-color
               (/ (+ (* source-alpha (rgba-color-red color))
                     (* (- 1 source-alpha) destination-alpha destination-red))
                  result-alpha)
               (/ (+ (* source-alpha (rgba-color-green color))
                     (* (- 1 source-alpha) destination-alpha destination-green))
                  result-alpha)
               (/ (+ (* source-alpha (rgba-color-blue color))
                     (* (- 1 source-alpha) destination-alpha destination-blue))
                  result-alpha)
               result-alpha)))
        color))
  (bytes-set! bytes byte-index (channel-byte (* 255 (rgba-color-alpha final-color))))
  (bytes-set! bytes (add1 byte-index) (channel-byte (rgba-color-red final-color)))
  (bytes-set! bytes (+ byte-index 2) (channel-byte (rgba-color-green final-color)))
  (bytes-set! bytes (+ byte-index 3) (channel-byte (rgba-color-blue final-color))))

(define (channel-byte value)
  (inexact->exact (round (max 0 (min 255 value)))))
