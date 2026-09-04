#lang racket/base

;;;
;;; Complex-Plane Builders and Maps
;;;

;; Keeps complex arithmetic in Racket's ordinary numeric domain while using
;; vec2 at the drawing boundary. Complex animations are a thin specialization
;; of apply-pointwise rather than a second scene representation.

(require racket/math
         "axes-visual.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "linear-algebra.rkt"
         "text-visual.rkt"
         "visual-model.rkt"
         "animation.rkt")

(provide complex->point
         point->complex
         complex-domain-color
         complex-domain-coloring
         complex-plane
         apply-complex-function
         apply-complex-homotopy)

;; complex->point : complex? -> vec2?
;; Maps a + bi to the usual Cartesian point (a,b).
(define (complex->point value)
  (unless (complex? value)
    (raise-argument-error 'complex->point "complex?" value))
  (define real (real-part value))
  (define imaginary (imag-part value))
  (unless (and (finite-real? real) (finite-real? imaginary))
    (raise-arguments-error
     'complex->point
     "a complex number with finite real and imaginary parts"
     "value" value))
  (vec2 real imaginary))

;; point->complex : vec2? -> complex?
;; Maps a Cartesian point (x,y) to x + yi.
(define (point->complex point)
  (unless (vec2? point)
    (raise-argument-error 'point->complex "vec2?" point))
  (make-rectangular (vec2-x point) (vec2-y point)))

;; complex-domain-color : complex? ... -> rgba-color?
;; Maps argument to hue and (optionally) modulus to value. It is a pure color
;; helper for author-built domain-color meshes; it deliberately does not impose
;; a raster field renderer on the ordinary semantic path system.
(define (complex-domain-color value
                              #:saturation [saturation 3/4]
                              #:brightness [brightness 4/5]
                              #:radial? [radial? #t])
  (define point (complex->point value))
  (unless (and (finite-real? saturation) (<= 0 saturation 1))
    (raise-argument-error 'complex-domain-color "finite real in [0, 1]" saturation))
  (unless (and (finite-real? brightness) (<= 0 brightness 1))
    (raise-argument-error 'complex-domain-color "finite real in [0, 1]" brightness))
  (unless (boolean? radial?)
    (raise-argument-error 'complex-domain-color "boolean?" radial?))
  (define magnitude
    (sqrt (+ (sqr (vec2-x point)) (sqr (vec2-y point)))))
  (define value-channel
    (if radial?
        (* brightness (+ 1/3 (* 2/3 (/ magnitude (+ 1 magnitude)))))
        brightness))
  (define hue
    (/ (+ (atan (vec2-y point) (vec2-x point)) pi) (* 2 pi)))
  (hsv->rgba hue saturation value-channel))

(define (hsv->rgba hue saturation value)
  (define wrapped (- hue (floor hue)))
  (define sector (* 6 wrapped))
  (define chroma (* value saturation))
  ;; `sector` is inexact, so use its period-two position explicitly instead
  ;; of integer `modulo`.
  (define sector-position
    (- sector (* 2 (floor (/ sector 2)))))
  (define auxiliary (* chroma (- 1 (abs (- sector-position 1)))))
  (define-values (red green blue)
    (cond
      [(< sector 1) (values chroma auxiliary 0)]
      [(< sector 2) (values auxiliary chroma 0)]
      [(< sector 3) (values 0 chroma auxiliary)]
      [(< sector 4) (values 0 auxiliary chroma)]
      [(< sector 5) (values auxiliary 0 chroma)]
      [else (values chroma 0 auxiliary)]))
  (define adjustment (- value chroma))
  (rgb-color (* 255 (+ red adjustment))
             (* 255 (+ green adjustment))
             (* 255 (+ blue adjustment))))

;; complex-domain-coloring : (-> complex? complex?) #:id symbol? ...
;;                              -> group-visual?
;; Produces a semantic, cell-sampled domain-colour field. The output remains a
;; normal group of addressable rectangles: it can be placed, transformed, and
;; animated with the rest of a scene without a renderer-specific raster layer.
(define (complex-domain-coloring function
                                 #:id id
                                 #:x-min [x-min -3]
                                 #:x-max [x-max 3]
                                 #:y-min [y-min -2]
                                 #:y-max [y-max 2]
                                 #:columns [columns 24]
                                 #:rows [rows 16]
                                 #:saturation [saturation 3/4]
                                 #:brightness [brightness 4/5]
                                 #:radial? [radial? #t]
                                 #:opacity [opacity 1])
  (unless (and (procedure? function)
               (procedure-arity-includes? function 1))
    (raise-argument-error
     'complex-domain-coloring "(procedure-arity-includes/c 1)" function))
  (unless (symbol? id)
    (raise-argument-error 'complex-domain-coloring "symbol?" id))
  (for ([value (in-list (list x-min x-max y-min y-max))])
    (unless (finite-real? value)
      (raise-argument-error 'complex-domain-coloring "finite real bound" value)))
  (unless (< x-min x-max)
    (raise-arguments-error 'complex-domain-coloring "x-min smaller than x-max"
                           "x-min" x-min "x-max" x-max))
  (unless (< y-min y-max)
    (raise-arguments-error 'complex-domain-coloring "y-min smaller than y-max"
                           "y-min" y-min "y-max" y-max))
  (for ([count (in-list (list columns rows))])
    (unless (and (exact-integer? count) (positive? count))
      (raise-argument-error
       'complex-domain-coloring "positive exact integer" count)))
  (unless (and (finite-real? opacity) (<= 0 opacity 1))
    (raise-argument-error 'complex-domain-coloring "finite real in [0, 1]" opacity))
  (define cell-width (/ (- x-max x-min) columns))
  (define cell-height (/ (- y-max y-min) rows))
  (define (cell-center column row)
    (vec2 (+ x-min (* (+ column 1/2) cell-width))
          (+ y-min (* (+ row 1/2) cell-height))))
  (define (cell-id column row)
    (string->symbol
     (format "~a-cell-~a-~a" id column row)))
  (group
   (for*/list ([row (in-range rows)] [column (in-range columns)])
     (define point (cell-center column row))
     (define result (function (point->complex point)))
     (unless (complex? result)
       (raise-arguments-error
        'complex-domain-coloring
        "the complex function must return a complex number"
        "point" point "result" result))
     ;; `complex-domain-color` additionally rejects infinities and NaNs.
     (rectangle #:id (cell-id column row) #:center point
                #:width cell-width #:height cell-height
                #:fill (complex-domain-color result
                                             #:saturation saturation
                                             #:brightness brightness
                                             #:radial? radial?)
                #:stroke #f))
   #:id id #:opacity opacity))

;; complex-plane : #:id symbol? ... -> group-visual?
;; Builds a Cartesian grid with conventional Re/Im labels. Numeric tick labels
;; are delegated to number-plane, keeping their scale and range consistent with
;; the existing linear-algebra API.
(define (complex-plane #:id id
                       #:x-range [x-range (axis-range -4 4 1)]
                       #:y-range [y-range (axis-range -3 3 1)]
                       #:x-length [x-length 8]
                       #:y-length [y-length 6]
                       #:center [center origin]
                       #:rotation [rotation 0]
                       #:scale [scale 1]
                       #:grid? [grid? #t]
                       #:labels? [labels? #t]
                       #:grid-stroke [grid-stroke "lightsteelblue"]
                       #:grid-stroke-width [grid-stroke-width 1]
                       #:axes-stroke [axes-stroke "navy"]
                       #:axes-stroke-width [axes-stroke-width 2]
                       #:label-font-size [label-font-size 1/4]
                       #:label-color [label-color "navy"])
  (unless (symbol? id)
    (raise-argument-error 'complex-plane "symbol?" id))
  (unless (axis-range? x-range)
    (raise-argument-error 'complex-plane "axis-range?" x-range))
  (unless (axis-range? y-range)
    (raise-argument-error 'complex-plane "axis-range?" y-range))
  (unless (and (finite-real? x-length) (positive? x-length))
    (raise-argument-error 'complex-plane "positive finite x length" x-length))
  (unless (and (finite-real? y-length) (positive? y-length))
    (raise-argument-error 'complex-plane "positive finite y length" y-length))
  (unless (boolean? labels?)
    (raise-argument-error 'complex-plane "boolean?" labels?))
  (define plane
    (number-plane
     #:id 'coordinates
     #:x-range x-range #:y-range y-range
     #:x-length x-length #:y-length y-length
     #:grid? grid? #:labels? labels?
     #:grid-stroke grid-stroke #:grid-stroke-width grid-stroke-width
     #:axes-stroke axes-stroke #:axes-stroke-width axes-stroke-width
     #:label-font-size label-font-size #:label-color label-color))
  (define semantic-axis-labels
    (if labels?
        (list
         (plain-text "Re" #:id 'real-axis
                     #:center (vec2 (+ (/ x-length 2) 3/10) 1/5)
                     #:font-size label-font-size #:font-family 'swiss
                     #:font-weight 'bold #:color label-color)
         (plain-text "Im" #:id 'imaginary-axis
                     #:center (vec2 1/5 (+ (/ y-length 2) 3/10))
                     #:font-size label-font-size #:font-family 'swiss
                     #:font-weight 'bold #:color label-color))
        '()))
  (group (append (list plane) semantic-axis-labels)
         #:id id #:center center #:rotation rotation #:scale scale))

;; apply-complex-function : target (-> complex? complex?) ...
;; Applies f to every sampled world point interpreted as a complex number.
(define (apply-complex-function target function
                                #:samples [samples 24]
                                #:adaptive? [adaptive? #t]
                                #:tolerance [tolerance 1/32]
                                #:max-depth [max-depth 8]
                                #:discontinuities [discontinuity-mode 'error])
  (unless (and (procedure? function)
               (procedure-arity-includes? function 1))
    (raise-argument-error
     'apply-complex-function "(procedure-arity-includes/c 1)" function))
  (apply-pointwise
   target
   (lambda (point)
     (define result (function (point->complex point)))
     (unless (complex? result)
       (raise-arguments-error
        'apply-complex-function
        "the complex function must return a complex number"
        "point" point
        "result" result))
     (complex->point result))
   #:samples samples
   #:adaptive? adaptive?
   #:tolerance tolerance
   #:max-depth max-depth
   #:discontinuities discontinuity-mode))

;; apply-complex-homotopy : target (-> complex? finite-real? complex?) ...
;; Applies H(z, alpha) to every sampled world point interpreted as a complex
;; value. It is the time-dependent counterpart of apply-complex-function.
(define (apply-complex-homotopy target homotopy
                                #:samples [samples 24]
                                #:adaptive? [adaptive? #t]
                                #:tolerance [tolerance 1/32]
                                #:max-depth [max-depth 8]
                                #:discontinuities [discontinuity-mode 'error])
  (unless (and (procedure? homotopy)
               (procedure-arity-includes? homotopy 2))
    (raise-argument-error
     'apply-complex-homotopy "(procedure-arity-includes/c 2)" homotopy))
  (apply-homotopy
   target
   (lambda (point alpha)
     (define result (homotopy (point->complex point) alpha))
     (unless (complex? result)
       (raise-arguments-error
        'apply-complex-homotopy
        "the complex homotopy must return a complex number"
        "point" point
        "alpha" alpha
        "result" result))
     (complex->point result))
   #:samples samples
   #:adaptive? adaptive?
   #:tolerance tolerance
   #:max-depth max-depth
   #:discontinuities discontinuity-mode))
