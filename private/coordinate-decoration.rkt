#lang racket/base

;;;
;;; Coordinate Decorations
;;;

;; Constructs immutable grid-line and numeric-label Visuals from snapshots of
;; existing axes and number-line model values.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "axes-visual.rkt"
         "geometry.rkt"
         "number-line-visual.rkt"
         "path-geometry.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

;; Exports
(provide axes-grid-lines
         axes-number-labels
         number-line-number-labels)


;;;
;;; Axes Grid Lines
;;;

; axes-grid-lines : axes-visual? [keyword arguments] -> path-visual?
;;   Constructs grid-line path geometry from the current axes snapshot.
(define (axes-grid-lines axes
                         #:id identifier
                         #:x-grid? [x-grid? #t]
                         #:y-grid? [y-grid? #t]
                         #:include-zero? [include-zero? #f]
                         #:opacity [opacity 1]
                         #:stroke [stroke "lightgray"]
                         #:stroke-width [stroke-width 1])
  (check-axes 'axes-grid-lines axes)
  (unless (symbol? identifier)
    (raise-argument-error 'axes-grid-lines "symbol?" identifier))
  (unless (boolean? x-grid?)
    (raise-argument-error 'axes-grid-lines "boolean?" x-grid?))
  (unless (boolean? y-grid?)
    (raise-argument-error 'axes-grid-lines "boolean?" y-grid?))
  (unless (boolean? include-zero?)
    (raise-argument-error 'axes-grid-lines "boolean?" include-zero?))
  (unless (opacity? opacity)
    (raise-argument-error 'axes-grid-lines "opacity?" opacity))
  (unless (string? stroke)
    (raise-argument-error 'axes-grid-lines "string?" stroke))
  (check-nonnegative-finite-real
   'axes-grid-lines "stroke-width" stroke-width)
  (define x-values
    (if x-grid?
        (axis-values axes 'x include-zero?)
        '()))
  (define y-values
    (if y-grid?
        (axis-values axes 'y include-zero?)
        '()))
  (define geometry
    (path-geometry
     (append
      (for/list ([value (in-list x-values)])
        (vertical-grid-subpath axes value))
      (for/list ([value (in-list y-values)])
        (horizontal-grid-subpath axes value)))))
  (make-path-visual
   geometry
   #:id identifier
   #:center (visual-position axes)
   #:rotation (visual-rotation axes)
   #:scale (visual-scale axes)
   #:opacity opacity
   #:stroke stroke
   #:stroke-width stroke-width))

; vertical-grid-subpath : axes-visual? finite-real? -> path-subpath?
;;   Constructs one local vertical grid line.
(define (vertical-grid-subpath axes x-value)
  (define y-range
    (axes-visual-y-range axes))
  (line-subpath
   (axes-coordinates->local-point axes x-value (axis-range-minimum y-range))
   (axes-coordinates->local-point axes x-value (axis-range-maximum y-range))))

; horizontal-grid-subpath : axes-visual? finite-real? -> path-subpath?
;;   Constructs one local horizontal grid line.
(define (horizontal-grid-subpath axes y-value)
  (define x-range
    (axes-visual-x-range axes))
  (line-subpath
   (axes-coordinates->local-point axes (axis-range-minimum x-range) y-value)
   (axes-coordinates->local-point axes (axis-range-maximum x-range) y-value)))


;;;
;;; Axes Number Labels
;;;

; axes-number-labels : axes-visual? [keyword arguments]
;                      -> (listof text-visual?)
;;   Constructs upright numeric labels at the current axes tick positions.
(define (axes-number-labels axes
                            #:id-prefix identifier-prefix
                            #:include-zero? [include-zero? #f]
                            #:font-size [font-size 3/10]
                            #:color [color "black"]
                            #:x-gap [x-gap 1/10]
                            #:y-gap [y-gap 1/10]
                            #:number->string
                            [number->label default-number->label])
  (check-axes 'axes-number-labels axes)
  (check-label-options
   'axes-number-labels
   identifier-prefix
   include-zero?
   font-size
   color
   number->label)
  (check-nonnegative-finite-real 'axes-number-labels "x-gap" x-gap)
  (check-nonnegative-finite-real 'axes-number-labels "y-gap" y-gap)
  (define x-values
    (axis-values axes 'x include-zero?))
  (define y-values
    (axis-values axes 'y #f))
  (append
   (for/list ([value (in-list x-values)]
              [index (in-naturals)])
     (define local-point
       (let ([anchor
              (axes-coordinates->local-point
               axes value (axis-reference-value axes 'y))])
         (vec2 (vec2-x anchor)
               (- (vec2-y anchor)
                  (+ (/ (axes-visual-tick-size axes) 2) x-gap)))))
     (plain-text
      (format-number-label
       'axes-number-labels
       number->label
       value)
      #:id (label-id identifier-prefix 'x index)
      #:center
      (affine-transform-apply-point
       (visual-transform axes)
       local-point)
      #:font-size font-size
      #:color color
      #:horizontal-alignment 'center
      #:vertical-alignment 'top))
   (for/list ([value (in-list y-values)]
              [index (in-naturals)])
     (define local-point
       (let ([anchor
              (axes-coordinates->local-point
               axes (axis-reference-value axes 'x) value)])
         (vec2 (- (vec2-x anchor)
                  (+ (/ (axes-visual-tick-size axes) 2) y-gap))
               (vec2-y anchor))))
     (plain-text
      (format-number-label
       'axes-number-labels
       number->label
       value)
      #:id (label-id identifier-prefix 'y index)
      #:center
      (affine-transform-apply-point
       (visual-transform axes)
       local-point)
      #:font-size font-size
      #:color color
      #:horizontal-alignment 'right
      #:vertical-alignment 'center))))


;;;
;;; Number-Line Number Labels
;;;

; number-line-number-labels : number-line-visual? [keyword arguments]
;                             -> (listof text-visual?)
;;   Constructs upright numeric labels below the current number-line ticks.
(define (number-line-number-labels number-line
                                   #:id-prefix identifier-prefix
                                   #:include-zero? [include-zero? #t]
                                   #:font-size [font-size 3/10]
                                   #:color [color "black"]
                                   #:gap [gap 1/10]
                                   #:number->string
                                   [number->label default-number->label])
  (unless (number-line-visual? number-line)
    (raise-argument-error
     'number-line-number-labels
     "number-line-visual?"
     number-line))
  (check-label-options
   'number-line-number-labels
   identifier-prefix
   include-zero?
   font-size
   color
   number->label)
  (check-nonnegative-finite-real
   'number-line-number-labels "gap" gap)
  (for/list ([value
              (in-list
               (number-line-tick-values
                number-line
                #:include-zero? include-zero?))]
             [index (in-naturals)])
    (define local-point
      (vec2 (* value
               (number-line-unit-length number-line))
            (- (+ (/ (number-line-visual-tick-size number-line) 2)
                  gap))))
    (plain-text
     (format-number-label
      'number-line-number-labels
      number->label
      value)
     #:id (label-id identifier-prefix 'number index)
     #:center
     (affine-transform-apply-point
      (visual-transform number-line)
      local-point)
     #:font-size font-size
     #:color color
     #:horizontal-alignment 'center
     #:vertical-alignment 'top)))


;;;
;;; Shared Helpers
;;;

; axis-values : axes-visual? symbol? boolean? -> (listof finite-real?)
;; Returns scale-aware increasing ticks and optionally inserts linear zero.
(define (axis-values axes direction include-zero?)
  (define scale
    (case direction
      [(x) (axes-visual-x-scale axes)]
      [(y) (axes-visual-y-scale axes)]
      [else (raise-argument-error 'axis-values "'x or 'y" direction)]))
  (define values
    (case direction
      [(x) (axes-x-tick-values axes)]
      [(y) (axes-y-tick-values axes)]))
  (cond
    [(not include-zero?) values]
    [(eq? scale 'linear) (sort (cons 0 values) <)]
    [else
     (raise-arguments-error
      'axes-grid-lines
      "a logarithmic axis cannot include a zero grid line or label"
      "direction" direction)]))

; axis-reference-value : axes-visual? symbol? -> finite-real?
;; Gives the coordinate where the two shafts meet for one scale.
(define (axis-reference-value axes direction)
  (define range
    (case direction
      [(x) (axes-visual-x-range axes)]
      [(y) (axes-visual-y-range axes)]
      [else (raise-argument-error 'axis-reference-value "'x or 'y" direction)]))
  (define scale
    (case direction
      [(x) (axes-visual-x-scale axes)]
      [(y) (axes-visual-y-scale axes)]))
  (if (eq? scale 'linear)
      0
      (if (axis-range-contains? range 1)
          1
          (axis-range-minimum range))))

; line-subpath : vec2? vec2? -> path-subpath?
;;   Constructs one open line subpath.
(define (line-subpath start end)
  (path-subpath start
                (list (line-path-segment end))
                #f))

; label-id : symbol? symbol? exact-nonnegative-integer? -> symbol?
;;   Constructs a deterministic label identity from a prefix, axis, and index.
(define (label-id prefix axis index)
  (string->symbol
   (format "~a-~a-~a"
           prefix
           axis
           index)))

; default-number->label : finite-real? -> string?
;;   Formats a numeric tick value using Racket's stable printed notation.
(define (default-number->label value)
  (number->string value))

; format-number-label : symbol? procedure? finite-real? -> string?
;;   Calls a label formatter once and validates its single result.
(define (format-number-label who formatter value)
  (define results
    (call-with-values
     (lambda ()
       (formatter value))
     list))
  (unless (= (length results) 1)
    (raise-arguments-error
     who
     "the number formatter must return exactly one value"
     "number" value
     "result count" (length results)))
  (define label
    (car results))
  (unless (string? label)
    (raise-arguments-error
     who
     "the number formatter must return a string"
     "number" value
     "result" label))
  label)

; check-label-options : symbol? any/c any/c any/c any/c any/c -> void?
;;   Validates common numeric-label construction options.
(define (check-label-options who prefix include-zero? font-size color formatter)
  (unless (symbol? prefix)
    (raise-argument-error who "symbol?" prefix))
  (unless (boolean? include-zero?)
    (raise-argument-error who "boolean?" include-zero?))
  (unless (and (finite-real? font-size)
               (> font-size 0))
    (raise-arguments-error
     who
     "font size must be a positive finite real"
     "font-size" font-size))
  (unless (string? color)
    (raise-argument-error who "string?" color))
  (unless (and (procedure? formatter)
               (procedure-arity-includes? formatter 1))
    (raise-argument-error
     who
     "(and/c procedure? (procedure-arity-includes/c 1))"
     formatter)))

; check-axes : symbol? any/c -> void?
;;   Raises an argument error unless value is an axes Visual.
(define (check-axes who value)
  (unless (axes-visual? value)
    (raise-argument-error who "axes-visual?" value)))

; check-nonnegative-finite-real : symbol? string? any/c -> void?
;;   Raises an argument error unless value is nonnegative and finite.
(define (check-nonnegative-finite-real who field value)
  (unless (and (finite-real? value)
               (>= value 0))
    (raise-arguments-error
     who
     "expected a nonnegative finite real"
     field value)))
