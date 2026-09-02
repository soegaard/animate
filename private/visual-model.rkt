#lang racket/base

;;;
;;; Visual Model
;;;

;; Defines semantic Visual values and the built-in visual primitives.
;;
;; This module intentionally contains no pict, bitmap, filesystem, process, or
;; browser dependencies. Rendering belongs in adapter modules.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/generic
         "affine-transform.rkt"
         "color-style.rkt"
         "geometry.rkt"
         "path-geometry.rkt")

;; Exports
(provide gen:visual
         visual?
         visual-id
         visual-position
         visual-with-position
         visual-path?
         visual-target-id
         visual-target-path
         gen:affine-visual
         affine-visual?
         visual-transform
         visual-with-transform
         visual-rotation
         visual-scale
         visual-with-rotation
         visual-with-scale
         gen:opacity-visual
         opacity-visual?
         opacity?
         visual-opacity
         visual-with-opacity
         gen:stroke-width-visual
         stroke-width-visual?
         stroke-width?
         visual-stroke-width
         visual-with-stroke-width
         gen:fill-color-visual
         fill-color-visual?
         visual-fill-color
         visual-with-fill-color
         gen:stroke-color-visual
         stroke-color-visual?
         visual-stroke-color
         visual-with-stroke-color
         transient-visual
         transient-visual?
         transient-visual-underlying
         circle
         circle-visual?
         circle-visual-radius
         circle-visual-fill
         circle-visual-stroke
         circle-visual-stroke-width
         rectangle
         rectangle-visual?
         rectangle-visual-width
         rectangle-visual-height
         rectangle-visual-fill
         rectangle-visual-stroke
         rectangle-visual-stroke-width
         make-path-visual
         path-visual?
         path-visual-path
         path-visual-fill
         path-visual-stroke
         path-visual-stroke-width
         path-visual-with-path
         line
         polygon)


;;;
;;; Visual Protocols
;;;

; visual-id : visual? -> symbol?
;;   Returns the stable identity of visual.
;
; visual-position : visual? -> vec2?
;;   Returns visual's reference position in its containing coordinate system.
;
; visual-with-position : visual? vec2? -> visual?
;;   Returns visual with its containing-system reference position replaced.
(define-generics visual
  (visual-id visual)
  (visual-position visual)
  (visual-with-position visual position))

; visual-transform : affine-visual? -> affine-transform?
;;   Returns the decomposed affine transform of visual.
;
; visual-with-transform : affine-visual? affine-transform? -> affine-visual?
;;   Returns visual with its complete affine transform replaced.
(define-generics affine-visual
  (visual-transform affine-visual)
  (visual-with-transform affine-visual transform))

; visual-opacity : opacity-visual? -> opacity?
;;   Returns the global opacity of visual.
;
; visual-with-opacity : opacity-visual? opacity? -> opacity-visual?
;;   Returns visual with its global opacity replaced.
(define-generics opacity-visual
  (visual-opacity opacity-visual)
  (visual-with-opacity opacity-visual opacity))

; visual-stroke-width : stroke-width-visual? -> stroke-width?
;;   Returns visual's cosmetic stroke width.
;
; visual-with-stroke-width : stroke-width-visual? stroke-width?
;                            -> stroke-width-visual?
;;   Returns visual with its cosmetic stroke width replaced.
(define-generics stroke-width-visual
  (visual-stroke-width stroke-width-visual)
  (visual-with-stroke-width stroke-width-visual stroke-width))

; visual-fill-color : fill-color-visual? -> any/c
;;   Returns visual's current semantic fill color specification.
;
; visual-with-fill-color : fill-color-visual? color-spec? -> fill-color-visual?
;;   Returns visual with its fill color replaced.
(define-generics fill-color-visual
  (visual-fill-color fill-color-visual)
  (visual-with-fill-color fill-color-visual color))

; visual-stroke-color : stroke-color-visual? -> any/c
;;   Returns visual's current semantic stroke color specification.
;
; visual-with-stroke-color : stroke-color-visual? color-spec?
;                            -> stroke-color-visual?
;;   Returns visual with its stroke color replaced.
(define-generics stroke-color-visual
  (visual-stroke-color stroke-color-visual)
  (visual-with-stroke-color stroke-color-visual color))


;;;
;;; Transient Visual Wrapper
;;;

;; A transient wrapper gives a temporary rendering layer a fresh outer identity
;; without rebuilding the wrapped Visual tree.  Animation overlays use it when
;; two otherwise independent trees may share descendant ids (for example two
;; tagged formulas with the same part names).  Render adapters deliberately
;; unwrap it; only scene/group identity validation sees the fresh id.
(struct transient-visual (id underlying)
  #:transparent
  #:guard
  (lambda (id underlying who)
    (unless (symbol? id)
      (raise-argument-error who "symbol?" id))
    (unless (and (visual? underlying)
                 (affine-visual? underlying)
                 (opacity-visual? underlying))
      (raise-argument-error
       who
       "(and/c visual? affine-visual? opacity-visual?)"
       underlying))
    (values id underlying))
  #:methods gen:visual
  [(define/generic generic-visual-position visual-position)
   (define/generic generic-visual-with-position visual-with-position)
   (define (visual-id transient)
     (transient-visual-id transient))
   (define (visual-position transient)
     (generic-visual-position (transient-visual-underlying transient)))
   (define (visual-with-position transient position)
     (struct-copy
      transient-visual
      transient
      [underlying
       (generic-visual-with-position (transient-visual-underlying transient)
                                      position)]))]
  #:methods gen:affine-visual
  [(define/generic generic-visual-transform visual-transform)
   (define/generic generic-visual-with-transform visual-with-transform)
   (define (visual-transform transient)
     (generic-visual-transform (transient-visual-underlying transient)))
   (define (visual-with-transform transient transform)
     (struct-copy
      transient-visual
      transient
      [underlying
       (generic-visual-with-transform (transient-visual-underlying transient)
                                       transform)]))]
  #:methods gen:opacity-visual
  [(define/generic generic-visual-opacity visual-opacity)
   (define/generic generic-visual-with-opacity visual-with-opacity)
   (define (visual-opacity transient)
     (generic-visual-opacity (transient-visual-underlying transient)))
   (define (visual-with-opacity transient opacity)
     (struct-copy
      transient-visual
      transient
      [underlying
       (generic-visual-with-opacity (transient-visual-underlying transient)
                                     opacity)]))])


;;;
;;; Opacity
;;;

; opacity? : any/c -> boolean?
;;   Reports whether value is a finite real in the closed unit interval.
(define (opacity? value)
  (and (finite-real? value)
       (<= 0 value 1)))


;;;
;;; Stroke Width
;;;

; stroke-width? : any/c -> boolean?
;;   Reports whether value is a nonnegative finite real stroke width.
(define (stroke-width? value)
  (and (finite-real? value)
       (not (negative? value))))


;;;
;;; Derived Transform Operations
;;;

; visual-rotation : affine-visual? -> finite-real?
;;   Returns visual's counter-clockwise rotation in radians.
(define (visual-rotation visual)
  (check-affine-visual 'visual-rotation visual)
  (affine-transform-rotation (visual-transform visual)))

; visual-scale : affine-visual? -> vec2?
;;   Returns visual's local x and y scale factors.
(define (visual-scale visual)
  (check-affine-visual 'visual-scale visual)
  (affine-transform-scale (visual-transform visual)))

; visual-with-rotation : affine-visual? finite-real? -> affine-visual?
;;   Returns visual with its rotation replaced.
(define (visual-with-rotation visual rotation)
  (check-affine-visual 'visual-with-rotation visual)
  (visual-with-transform
   visual
   (affine-transform-with-rotation (visual-transform visual)
                                   rotation)))

; visual-with-scale : affine-visual? (or/c positive-real? vec2?)
;                     -> affine-visual?
;;   Returns visual with its local scale replaced.
(define (visual-with-scale visual scale)
  (check-affine-visual 'visual-with-scale visual)
  (visual-with-transform
   visual
   (affine-transform-with-scale (visual-transform visual)
                                scale)))


;;;
;;; Circle Visual
;;;

(struct circle-visual (id transform opacity radius fill stroke stroke-width)
  #:transparent
  #:methods gen:visual
  [(define (visual-id circle)
     (circle-visual-id circle))
   (define (visual-position circle)
     (affine-transform-translation
      (circle-visual-transform circle)))
   (define (visual-with-position circle position)
     (check-visual-position 'visual-with-position position)
     (struct-copy circle-visual circle
                  [transform
                   (affine-transform-with-translation
                    (circle-visual-transform circle)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform circle)
     (circle-visual-transform circle))
   (define (visual-with-transform circle transform)
     (check-visual-transform 'visual-with-transform transform)
     (struct-copy circle-visual circle [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity circle)
     (circle-visual-opacity circle))
   (define (visual-with-opacity circle opacity)
     (check-opacity 'visual-with-opacity opacity)
     (struct-copy circle-visual circle [opacity opacity]))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width circle)
     (circle-visual-stroke-width circle))
   (define (visual-with-stroke-width circle stroke-width)
     (check-stroke-width 'visual-with-stroke-width stroke-width)
     (struct-copy circle-visual circle [stroke-width stroke-width]))]
  #:methods gen:fill-color-visual
  [(define (visual-fill-color circle)
     (circle-visual-fill circle))
   (define (visual-with-fill-color circle color)
     (check-color-spec 'visual-with-fill-color color)
     (struct-copy circle-visual circle [fill color]))]
  #:methods gen:stroke-color-visual
  [(define (visual-stroke-color circle)
     (circle-visual-stroke circle))
   (define (visual-with-stroke-color circle color)
     (check-color-spec 'visual-with-stroke-color color)
     (struct-copy circle-visual circle [stroke color]))])

;; circle-visual represents a semantic circle with local geometry.
;;  - id            symbol?                    stable visual identity.
;;  - transform     affine-transform?          placement and deformation in containing coordinates.
;;  - opacity       opacity?                   global rendering opacity.
;;  - radius        positive finite real?      local radius in world units.
;;  - fill          any/c                      opaque fill style for an adapter.
;;  - stroke        any/c                      opaque stroke style for an adapter.
;;  - stroke-width  nonnegative finite real?   cosmetic stroke width.

; circle : #:id symbol?
;          [#:center vec2?]
;          [#:rotation finite-real?]
;          [#:scale (or/c positive-real? vec2?)]
;          [#:opacity opacity?]
;          [#:radius positive-real?]
;          [#:fill any/c]
;          [#:stroke any/c]
;          [#:stroke-width nonnegative-real?]
;          -> circle-visual?
;;   Creates a semantic circle with explicit identity and affine transform.
(define (circle #:id id
                #:center [center origin]
                #:rotation [rotation 0]
                #:scale [scale 1]
                #:opacity [opacity 1]
                #:radius [radius 1]
                #:fill [fill "dodgerblue"]
                #:stroke [stroke "black"]
                #:stroke-width [stroke-width 2])
  (check-visual-id 'circle id)
  (check-visual-position 'circle center)
  (check-rotation 'circle rotation)
  (check-scale 'circle scale)
  (check-opacity 'circle opacity)
  (check-positive-length 'circle "radius" radius)
  (check-stroke-width 'circle stroke-width)
  (circle-visual id
                 (make-affine-transform #:translation center
                                        #:rotation rotation
                                        #:scale scale)
                 opacity
                 radius
                 fill
                 stroke
                 stroke-width))


;;;
;;; Rectangle Visual
;;;

(struct rectangle-visual (id transform opacity width height fill stroke stroke-width)
  #:transparent
  #:methods gen:visual
  [(define (visual-id rectangle)
     (rectangle-visual-id rectangle))
   (define (visual-position rectangle)
     (affine-transform-translation
      (rectangle-visual-transform rectangle)))
   (define (visual-with-position rectangle position)
     (check-visual-position 'visual-with-position position)
     (struct-copy rectangle-visual rectangle
                  [transform
                   (affine-transform-with-translation
                    (rectangle-visual-transform rectangle)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform rectangle)
     (rectangle-visual-transform rectangle))
   (define (visual-with-transform rectangle transform)
     (check-visual-transform 'visual-with-transform transform)
     (struct-copy rectangle-visual rectangle [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity rectangle)
     (rectangle-visual-opacity rectangle))
   (define (visual-with-opacity rectangle opacity)
     (check-opacity 'visual-with-opacity opacity)
     (struct-copy rectangle-visual rectangle [opacity opacity]))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width rectangle)
     (rectangle-visual-stroke-width rectangle))
   (define (visual-with-stroke-width rectangle stroke-width)
     (check-stroke-width 'visual-with-stroke-width stroke-width)
     (struct-copy rectangle-visual rectangle [stroke-width stroke-width]))]
  #:methods gen:fill-color-visual
  [(define (visual-fill-color rectangle)
     (rectangle-visual-fill rectangle))
   (define (visual-with-fill-color rectangle color)
     (check-color-spec 'visual-with-fill-color color)
     (struct-copy rectangle-visual rectangle [fill color]))]
  #:methods gen:stroke-color-visual
  [(define (visual-stroke-color rectangle)
     (rectangle-visual-stroke rectangle))
   (define (visual-with-stroke-color rectangle color)
     (check-color-spec 'visual-with-stroke-color color)
     (struct-copy rectangle-visual rectangle [stroke color]))])

;; rectangle-visual represents a rectangle with local axis-aligned geometry.
;;  - id            symbol?                    stable visual identity.
;;  - transform     affine-transform?          placement and deformation in containing coordinates.
;;  - opacity       opacity?                   global rendering opacity.
;;  - width         positive finite real?      local width in world units.
;;  - height        positive finite real?      local height in world units.
;;  - fill          any/c                      opaque fill style for an adapter.
;;  - stroke        any/c                      opaque stroke style for an adapter.
;;  - stroke-width  nonnegative finite real?   cosmetic stroke width.

; rectangle : #:id symbol?
;             [#:center vec2?]
;             [#:rotation finite-real?]
;             [#:scale (or/c positive-real? vec2?)]
;             [#:opacity opacity?]
;             [#:width positive-real?]
;             [#:height positive-real?]
;             [#:fill any/c]
;             [#:stroke any/c]
;             [#:stroke-width nonnegative-real?]
;             -> rectangle-visual?
;;   Creates a semantic rectangle with explicit identity and affine transform.
(define (rectangle #:id id
                   #:center [center origin]
                   #:rotation [rotation 0]
                   #:scale [scale 1]
                   #:opacity [opacity 1]
                   #:width [width 2]
                   #:height [height 1]
                   #:fill [fill "goldenrod"]
                   #:stroke [stroke "black"]
                   #:stroke-width [stroke-width 2])
  (check-visual-id 'rectangle id)
  (check-visual-position 'rectangle center)
  (check-rotation 'rectangle rotation)
  (check-scale 'rectangle scale)
  (check-opacity 'rectangle opacity)
  (check-positive-length 'rectangle "width" width)
  (check-positive-length 'rectangle "height" height)
  (check-stroke-width 'rectangle stroke-width)
  (rectangle-visual id
                    (make-affine-transform #:translation center
                                           #:rotation rotation
                                           #:scale scale)
                    opacity
                    width
                    height
                    fill
                    stroke
                    stroke-width))


;;;
;;; Path Visual
;;;

(struct path-visual (id transform opacity path fill stroke stroke-width)
  #:transparent
  #:methods gen:visual
  [(define (visual-id path-visual-value)
     (path-visual-id path-visual-value))
   (define (visual-position path-visual-value)
     (affine-transform-translation
      (path-visual-transform path-visual-value)))
   (define (visual-with-position path-visual-value position)
     (check-visual-position 'visual-with-position position)
     (struct-copy path-visual path-visual-value
                  [transform
                   (affine-transform-with-translation
                    (path-visual-transform path-visual-value)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform path-visual-value)
     (path-visual-transform path-visual-value))
   (define (visual-with-transform path-visual-value transform)
     (check-visual-transform 'visual-with-transform transform)
     (struct-copy path-visual path-visual-value
                  [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity path-visual-value)
     (path-visual-opacity path-visual-value))
   (define (visual-with-opacity path-visual-value opacity)
     (check-opacity 'visual-with-opacity opacity)
     (struct-copy path-visual path-visual-value
                  [opacity opacity]))]
  #:methods gen:stroke-width-visual
  [(define (visual-stroke-width path-visual-value)
     (path-visual-stroke-width path-visual-value))
   (define (visual-with-stroke-width path-visual-value stroke-width)
     (check-stroke-width 'visual-with-stroke-width stroke-width)
     (struct-copy path-visual path-visual-value
                  [stroke-width stroke-width]))]
  #:methods gen:fill-color-visual
  [(define (visual-fill-color path-visual-value)
     (path-visual-fill path-visual-value))
   (define (visual-with-fill-color path-visual-value color)
     (check-color-spec 'visual-with-fill-color color)
     (struct-copy path-visual path-visual-value [fill color]))]
  #:methods gen:stroke-color-visual
  [(define (visual-stroke-color path-visual-value)
     (path-visual-stroke path-visual-value))
   (define (visual-with-stroke-color path-visual-value color)
     (check-color-spec 'visual-with-stroke-color color)
     (struct-copy path-visual path-visual-value [stroke color]))])

;; path-visual represents styled local path geometry with affine placement.
;;  - id            symbol?                    stable visual identity.
;;  - transform     affine-transform?          placement and deformation in containing coordinates.
;;  - opacity       opacity?                   global rendering opacity.
;;  - path          path-geometry?              local path geometry.
;;  - fill          any/c                      opaque fill style or #f.
;;  - stroke        any/c                      opaque stroke style or #f.
;;  - stroke-width  nonnegative finite real?   cosmetic stroke width.

; make-path-visual : path-geometry?
;                    #:id symbol?
;                    [#:center vec2?]
;                    [#:rotation finite-real?]
;                    [#:scale (or/c positive-real? vec2?)]
;                    [#:opacity opacity?]
;                    [#:fill any/c]
;                    [#:stroke any/c]
;                    [#:stroke-width nonnegative-real?]
;                    -> path-visual?
;;   Creates a semantic path Visual from local geometry.
(define (make-path-visual path
                          #:id id
                          #:center [center origin]
                          #:rotation [rotation 0]
                          #:scale [scale 1]
                          #:opacity [opacity 1]
                          #:fill [fill #f]
                          #:stroke [stroke "black"]
                          #:stroke-width [stroke-width 2])
  (check-visual-id 'make-path-visual id)
  (check-visual-position 'make-path-visual center)
  (check-rotation 'make-path-visual rotation)
  (check-scale 'make-path-visual scale)
  (check-opacity 'make-path-visual opacity)
  (check-path 'make-path-visual path)
  (check-stroke-width 'make-path-visual stroke-width)
  (path-visual id
               (make-affine-transform #:translation center
                                      #:rotation rotation
                                      #:scale scale)
               opacity
               path
               fill
               stroke
               stroke-width))

; path-visual-with-path : path-visual? path-geometry? -> path-visual?
;;   Returns visual with its local path geometry replaced.
(define (path-visual-with-path visual path)
  (unless (path-visual? visual)
    (raise-argument-error 'path-visual-with-path "path-visual?" visual))
  (check-path 'path-visual-with-path path)
  (struct-copy path-visual visual [path path]))


;;;
;;; Path Visuals
;;;

; line : vec2? vec2?
;        #:id symbol?
;        [#:rotation finite-real?]
;        [#:scale (or/c positive-real? vec2?)]
;        [#:opacity opacity?]
;        [#:stroke any/c]
;        [#:stroke-width nonnegative-real?]
;        -> path-visual?
;;   Creates a centered open path between two points in one coordinate system.
(define (line start end
              #:id id
              #:rotation [rotation 0]
              #:scale [scale 1]
              #:opacity [opacity 1]
              #:stroke [stroke "black"]
              #:stroke-width [stroke-width 2])
  (check-visual-position 'line start)
  (check-visual-position 'line end)
  (when (same-point? start end)
    (raise-arguments-error
     'line
     "start and end must be distinct points"
     "start" start
     "end" end))
  (define input-path
    (polyline-path (list start end)))
  (define center
    (path-geometry-center input-path))
  (make-path-visual
   (path-geometry-translate input-path
                            (vec2-scale -1 center))
   #:id id
   #:center center
   #:rotation rotation
   #:scale scale
   #:opacity opacity
   #:fill #f
   #:stroke stroke
   #:stroke-width stroke-width))

; polygon : (listof vec2?)
;           #:id symbol?
;           [#:rotation finite-real?]
;           [#:scale (or/c positive-real? vec2?)]
;           [#:opacity opacity?]
;           [#:fill any/c]
;           [#:stroke any/c]
;           [#:stroke-width nonnegative-real?]
;           -> path-visual?
;;   Creates a centered closed path through points in one coordinate system.
(define (polygon vertices
                 #:id id
                 #:rotation [rotation 0]
                 #:scale [scale 1]
                 #:opacity [opacity 1]
                 #:fill [fill "cornflowerblue"]
                 #:stroke [stroke "black"]
                 #:stroke-width [stroke-width 2])
  (define input-path
    (polygon-path vertices))
  (define center
    (path-geometry-center input-path))
  (make-path-visual
   (path-geometry-translate input-path
                            (vec2-scale -1 center))
   #:id id
   #:center center
   #:rotation rotation
   #:scale scale
   #:opacity opacity
   #:fill fill
   #:stroke stroke
   #:stroke-width stroke-width))


;;;
;;; Visual Identity
;;;

; visual-path? : any/c -> boolean?
;; Reports whether value is a nonempty stable path of Visual identities.
(define (visual-path? value)
  (and (list? value)
       (pair? value)
       (andmap symbol? value)))

; visual-target-id : (or/c visual? symbol? visual-path?) [symbol?] ->
;                     (or/c symbol? visual-path?)
;; Resolves a Visual, top-level ID, or nested identity path to its stable
;; address. A Visual object supplies only its own ID; nested targets therefore
;; use an explicit path whose first entry identifies the top-level Visual.
(define (visual-target-id target [who 'visual-target-id])
  (cond
    [(visual? target)
     (define id (visual-id target))
     (unless (symbol? id)
       (raise-arguments-error
        who
        "a Visual must have a symbol identity"
        "visual" target
        "visual-id" id))
     id]
    [(symbol? target)
     target]
    [(visual-path? target)
     target]
    [else
     (raise-argument-error who "(or/c visual? symbol? visual-path?)" target)]))

; visual-target-path : (or/c visual? symbol? visual-path?) [symbol?]
;;                      -> visual-path?
;; Converts a Visual target to its nonempty path representation.
(define (visual-target-path target [who 'visual-target-path])
  (define id-or-path
    (visual-target-id target who))
  (if (symbol? id-or-path)
      (list id-or-path)
      id-or-path))


;;;
;;; Validation
;;;

; check-affine-visual : symbol? any/c -> void?
;;   Raises an argument error unless visual supports affine transforms.
(define (check-affine-visual who visual)
  (unless (affine-visual? visual)
    (raise-argument-error who "affine-visual?" visual)))

; check-visual-id : symbol? any/c -> void?
;;   Raises an argument error unless id is a symbol.
(define (check-visual-id who id)
  (unless (symbol? id)
    (raise-argument-error who "symbol?" id)))

; check-visual-position : symbol? any/c -> void?
;;   Raises an argument error unless position is a vec2.
(define (check-visual-position who position)
  (unless (vec2? position)
    (raise-argument-error who "vec2?" position)))

; check-visual-transform : symbol? any/c -> void?
;;   Raises an argument error unless transform is an affine transform.
(define (check-visual-transform who transform)
  (unless (affine-transform? transform)
    (raise-argument-error who "affine-transform?" transform)))

; check-rotation : symbol? any/c -> void?
;;   Raises an argument error unless rotation is finite.
(define (check-rotation who rotation)
  (unless (finite-real? rotation)
    (raise-argument-error who "finite real?" rotation)))

; check-scale : symbol? any/c -> void?
;;   Raises an argument error unless scale is positive and finite.
(define (check-scale who scale)
  (unless (scale-factor? scale)
    (raise-argument-error
     who
     "positive finite real or vec2 with positive components"
     scale)))

; check-opacity : symbol? any/c -> void?
;;   Raises an argument error unless opacity is in the closed unit interval.
(define (check-opacity who opacity)
  (unless (opacity? opacity)
    (raise-argument-error
     who
     "finite real in [0, 1]"
     opacity)))

; check-positive-length : symbol? string? any/c -> void?
;;   Raises an argument error unless length is positive and finite.
(define (check-positive-length who field-name length)
  (unless (and (finite-real? length)
               (positive? length))
    (raise-arguments-error
     who
     "a visual dimension must be a positive finite real"
     field-name length)))

; check-path : symbol? any/c -> void?
;;   Raises an argument error unless path is semantic path geometry.
(define (check-path who path)
  (unless (path-geometry? path)
    (raise-argument-error who "path-geometry?" path)))

; same-point? : vec2? vec2? -> boolean?
;;   Reports whether two points have equal coordinates.
(define (same-point? a b)
  (and (= (vec2-x a) (vec2-x b))
       (= (vec2-y a) (vec2-y b))))

; check-stroke-width : symbol? any/c -> void?
;;   Raises an argument error unless stroke-width is nonnegative and finite.
(define (check-stroke-width who stroke-width)
  (unless (stroke-width? stroke-width)
    (raise-argument-error
     who
     "nonnegative finite real?"
     stroke-width)))

; check-color-spec : symbol? any/c -> void?
;;   Raises an argument error unless color is a supported semantic color.
(define (check-color-spec who color)
  (unless (color-spec? color)
    (raise-argument-error
     who
     "color-spec?"
     color)))
