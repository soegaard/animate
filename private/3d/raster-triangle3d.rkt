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

(provide raster-vertex3d
         raster-vertex3d?
         raster-vertex3d-ndc
         raster-vertex3d-depth
         raster-vertex3d-normal
         raster-vertex3d-color
         raster-vertex3d-source
         raster-vertex3d-view-position
         raster-triangle3d!)

;; ndc has +y upward.  The rasterizer maps it to a top-left pixel coordinate
;; system while retaining a positive forward depth and one flat normal/color.
;; `view-position` makes the view vector explicit for Blinn--Phong shading.
;; It is optional only for the private direct-rasterizer tests and tools that
;; predate lit materials; prepared scene vertices always supply the exact
;; camera-local point.
(struct raster-vertex3d-value (ndc depth normal color source view-position)
  #:transparent
  #:constructor-name make-raster-vertex3d)

(define raster-vertex3d? raster-vertex3d-value?)
(define raster-vertex3d-ndc raster-vertex3d-value-ndc)
(define raster-vertex3d-depth raster-vertex3d-value-depth)
(define raster-vertex3d-normal raster-vertex3d-value-normal)
(define raster-vertex3d-color raster-vertex3d-value-color)
(define raster-vertex3d-source raster-vertex3d-value-source)
(define raster-vertex3d-view-position raster-vertex3d-value-view-position)

(define (raster-vertex3d ndc depth normal color source
                         #:view-position [view-position (vec3 0 0 (- depth))])
  (make-raster-vertex3d ndc depth normal color source view-position))

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
                       (write-pixel!
                        target index
                        (shade color normal
                               (weighted-vector
                                (raster-vertex3d-view-position (screen-vertex-raster first-vertex))
                                (raster-vertex3d-view-position (screen-vertex-raster second-vertex))
                                (raster-vertex3d-view-position (screen-vertex-raster third-vertex))
                                perspective-weight0 perspective-weight1 perspective-weight2)
                               material lights)
                        #:blend? blend?))
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

(define (shade color normal view-position material lights)
  (define emission (material3d-emission material))
  (define emission-scale (material3d-emission-strength material))
  (define (with-emission red green blue)
    (rgba-color (clamp-channel (+ red (* emission-scale (rgba-color-red emission))))
                (clamp-channel (+ green (* emission-scale (rgba-color-green emission))))
                (clamp-channel (+ blue (* emission-scale (rgba-color-blue emission))))
                (rgba-color-alpha color)))
  (cond
    ;; `unlit` is a normal-interpolation policy with no illumination model:
    ;; its base colour remains visible and material emission is an additive,
    ;; light-independent contribution.
    [(eq? (material3d-shading material) 'unlit)
     (with-emission (rgba-color-red color) (rgba-color-green color) (rgba-color-blue color))]
    [else
     (define view-direction
       (safe-normalize (vec3-scale -1 view-position) z-axis3))
     (define-values (light-red light-green light-blue specular-red specular-green specular-blue)
       (for/fold ([light-red 0.0] [light-green 0.0] [light-blue 0.0]
                  [specular-red 0.0] [specular-green 0.0] [specular-blue 0.0])
                 ([light (in-list lights)])
         (cond
           [(ambient-light3d? light)
            (define-values (red green blue)
              (add-light-color light-red light-green light-blue
                               (ambient-light3d-color light)
                               (* (material3d-ambient material)
                                  (ambient-light3d-intensity light))))
            (values red green blue specular-red specular-green specular-blue)]
           [else
            (define light-direction (vec3-scale -1 (directional-light3d-direction light)))
            (define facing (max 0 (vec3-dot normal light-direction)))
            (define-values (red green blue)
              (add-light-color light-red light-green light-blue
                               (directional-light3d-color light)
                               (* (material3d-diffuse material)
                                  (directional-light3d-intensity light)
                                  facing)))
            (define specular-amount
              (if (and (eq? (material3d-lighting material) 'blinn-phong)
                       (positive? facing))
                  (let ([half-vector (safe-normalize (vec3+ light-direction view-direction)
                                                      normal)])
                    (* (material3d-specular material)
                       (directional-light3d-intensity light)
                       (expt (max 0 (vec3-dot normal half-vector))
                             (material3d-specular-exponent material))))
                  0))
            (define-values (spec-red spec-green spec-blue)
              (add-light-color specular-red specular-green specular-blue
                               (directional-light3d-color light) specular-amount))
            (values red green blue spec-red spec-green spec-blue)])))
     (define specular-color (material3d-specular-color material))
     ;; Keep the CPU and GPU equation in display colour space until the later
     ;; colour-management stage establishes the common linear-space boundary.
     (with-emission
      (+ (* (rgba-color-red color) light-red)
         (* (rgba-color-red specular-color) specular-red))
      (+ (* (rgba-color-green color) light-green)
         (* (rgba-color-green specular-color) specular-green))
      (+ (* (rgba-color-blue color) light-blue)
         (* (rgba-color-blue specular-color) specular-blue)))]))

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
