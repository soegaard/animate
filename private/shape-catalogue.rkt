#lang racket/base

;;;
;;; SCENE-DJ Mathematical Shape Catalogue
;;;

;; These are deliberately path-backed or ordinary group Visuals.  That keeps
;; every catalogue item addressable, styleable, morphable, and usable by the
;; existing Pict renderer without growing a parallel rendering protocol.

(require (only-in racket/math pi sqr)
         "arrow-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide ellipse
         annulus
         sector
         regular-polygon
         star
         rounded-rectangle
         arc-between-points
         curved-arrow
         double-arrow
         labeled-point)


;;;
;;; Closed Curves
;;;

;; ellipse : #:id symbol? [#:center vec2?] [#:width positive-real?]
;;           [#:height positive-real?] ... ordinary path style keywords ...
;;           -> path-visual?
;; Creates a cubic Bézier ellipse with a stable ordinary path identity.
(define (ellipse #:id id
                 #:center [center origin]
                 #:width [width 2]
                 #:height [height 1]
                 #:rotation [rotation 0]
                 #:scale [scale 1]
                 #:opacity [opacity 1]
                 #:fill [fill "cornflowerblue"]
                 #:stroke [stroke "black"]
                 #:stroke-width [stroke-width 2])
  (check-symbol 'ellipse id)
  (check-point 'ellipse center)
  (check-positive 'ellipse "width" width)
  (check-positive 'ellipse "height" height)
  (check-finite 'ellipse "rotation" rotation)
  (make-path-visual
   (path-geometry (list (ellipse-subpath (/ width 2) (/ height 2))))
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:fill fill #:stroke stroke #:stroke-width stroke-width))

;; annulus : #:id symbol? [#:center vec2?]
;;           [#:inner-radius positive-real?] [#:outer-radius positive-real?]
;;           ... ordinary path style keywords ... -> path-visual?
;; Creates one odd-even filled circular ring. The hole remains transparent in
;; the standard path renderer, including with a nonfalse fill.
(define (annulus #:id id
                 #:center [center origin]
                 #:inner-radius [inner-radius 1/2]
                 #:outer-radius [outer-radius 1]
                 #:rotation [rotation 0]
                 #:scale [scale 1]
                 #:opacity [opacity 1]
                 #:fill [fill "cornflowerblue"]
                 #:stroke [stroke "black"]
                 #:stroke-width [stroke-width 2])
  (check-symbol 'annulus id)
  (check-point 'annulus center)
  (check-positive 'annulus "inner-radius" inner-radius)
  (check-positive 'annulus "outer-radius" outer-radius)
  (unless (< inner-radius outer-radius)
    (raise-arguments-error 'annulus "inner-radius must be smaller than outer-radius"
                           "inner-radius" inner-radius
                           "outer-radius" outer-radius))
  (check-finite 'annulus "rotation" rotation)
  (make-path-visual
   (path-geometry
    (list (ellipse-subpath outer-radius outer-radius)
          (ellipse-subpath inner-radius inner-radius)))
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:fill fill #:stroke stroke #:stroke-width stroke-width))

;; sector : #:id symbol? [#:center vec2?] [#:radius positive-real?]
;;          [#:start-angle finite-real?] [#:angle nonzero-real?] ... -> path-visual?
;; Creates the closed radial wedge swept counter-clockwise for a positive angle.
(define (sector #:id id
                #:center [center origin]
                #:radius [radius 1]
                #:start-angle [start-angle 0]
                #:angle [sweep-angle (/ pi 2)]
                #:rotation [rotation 0]
                #:scale [scale 1]
                #:opacity [opacity 1]
                #:fill [fill "cornflowerblue"]
                #:stroke [stroke "black"]
                #:stroke-width [stroke-width 2])
  (check-symbol 'sector id)
  (check-point 'sector center)
  (check-positive 'sector "radius" radius)
  (check-finite 'sector "start-angle" start-angle)
  (check-sweep 'sector sweep-angle)
  (check-finite 'sector "rotation" rotation)
  (define start (ellipse-point radius radius start-angle))
  (make-path-visual
   (path-geometry
    (list
     (path-subpath origin
                   (append (list (line-path-segment start))
                           (elliptical-arc-segments
                            radius radius start-angle sweep-angle)
                           (list (line-path-segment origin)))
                   #t)))
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:fill fill #:stroke stroke #:stroke-width stroke-width))

;; regular-polygon : #:id symbol? [#:center vec2?]
;;                   [#:sides exact-integer-at-least-3?]
;;                   [#:radius positive-real?] [#:start-angle finite-real?]
;;                   ... -> path-visual?
(define (regular-polygon #:id id
                         #:center [center origin]
                         #:sides [sides 5]
                         #:radius [radius 1]
                         #:start-angle [start-angle (/ pi 2)]
                         #:rotation [rotation 0]
                         #:scale [scale 1]
                         #:opacity [opacity 1]
                         #:fill [fill "cornflowerblue"]
                         #:stroke [stroke "black"]
                         #:stroke-width [stroke-width 2])
  (check-symbol 'regular-polygon id)
  (check-point 'regular-polygon center)
  (check-at-least 'regular-polygon "sides" sides 3)
  (check-positive 'regular-polygon "radius" radius)
  (check-finite 'regular-polygon "start-angle" start-angle)
  (check-finite 'regular-polygon "rotation" rotation)
  (make-path-visual
   (polygon-path
    (for/list ([index (in-range sides)])
      (ellipse-point radius radius
                     (+ start-angle (* index (/ (* 2 pi) sides))))))
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:fill fill #:stroke stroke #:stroke-width stroke-width))

;; star : #:id symbol? [#:center vec2?]
;;        [#:points exact-integer-at-least-2?]
;;        [#:outer-radius positive-real?] [#:inner-radius positive-real?]
;;        ... -> path-visual?
;; Produces the familiar alternating outer/inner regular star boundary.
(define (star #:id id
              #:center [center origin]
              #:points [points 5]
              #:outer-radius [outer-radius 1]
              #:inner-radius [inner-radius 1/2]
              #:start-angle [start-angle (/ pi 2)]
              #:rotation [rotation 0]
              #:scale [scale 1]
              #:opacity [opacity 1]
              #:fill [fill "gold"]
              #:stroke [stroke "black"]
              #:stroke-width [stroke-width 2])
  (check-symbol 'star id)
  (check-point 'star center)
  (check-at-least 'star "points" points 2)
  (check-positive 'star "outer-radius" outer-radius)
  (check-positive 'star "inner-radius" inner-radius)
  (unless (< inner-radius outer-radius)
    (raise-arguments-error 'star "inner-radius must be smaller than outer-radius"
                           "inner-radius" inner-radius
                           "outer-radius" outer-radius))
  (check-finite 'star "start-angle" start-angle)
  (check-finite 'star "rotation" rotation)
  (make-path-visual
   (polygon-path
    (for/list ([index (in-range (* 2 points))])
      (define radius (if (even? index) outer-radius inner-radius))
      (ellipse-point radius radius
                     (+ start-angle (* index (/ pi points))))))
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:fill fill #:stroke stroke #:stroke-width stroke-width))

;; rounded-rectangle : #:id symbol? [#:center vec2?]
;;                     [#:width positive-real?] [#:height positive-real?]
;;                     [#:corner-radius nonnegative-real?] ... -> path-visual?
;; Creates a closed rectangle with exact straight sides and four quarter-circle
;; cubic corners. A zero radius is a regular path-backed rectangle.
(define (rounded-rectangle #:id id
                           #:center [center origin]
                           #:width [width 2]
                           #:height [height 1]
                           #:corner-radius [corner-radius 1/5]
                           #:rotation [rotation 0]
                           #:scale [scale 1]
                           #:opacity [opacity 1]
                           #:fill [fill "cornflowerblue"]
                           #:stroke [stroke "black"]
                           #:stroke-width [stroke-width 2])
  (check-symbol 'rounded-rectangle id)
  (check-point 'rounded-rectangle center)
  (check-positive 'rounded-rectangle "width" width)
  (check-positive 'rounded-rectangle "height" height)
  (check-nonnegative 'rounded-rectangle "corner-radius" corner-radius)
  (unless (<= corner-radius (/ (min width height) 2))
    (raise-arguments-error
     'rounded-rectangle "corner-radius must fit inside both half-extents"
     "corner-radius" corner-radius "width" width "height" height))
  (check-finite 'rounded-rectangle "rotation" rotation)
  (define half-width (/ width 2))
  (define half-height (/ height 2))
  (define path
    (if (zero? corner-radius)
        (polygon-path
         (list (vec2 (- half-width) half-height)
               (vec2 half-width half-height)
               (vec2 half-width (- half-height))
               (vec2 (- half-width) (- half-height))))
        (rounded-rectangle-path half-width half-height corner-radius)))
  (make-path-visual
   path #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:fill fill #:stroke stroke #:stroke-width stroke-width))


;;;
;;; Arcs and Arrows
;;;

;; arc-between-points : vec2? vec2? #:id symbol? [#:angle nonzero-real?] ...
;;                       -> path-visual?
;; The angle is the signed central sweep. Its sign chooses which side of the
;; chord is traversed; magnitudes must be strictly below a full turn.
(define (arc-between-points start end
                            #:id id
                            #:angle [sweep-angle (/ pi 2)]
                            #:opacity [opacity 1]
                            #:stroke [stroke "black"]
                            #:stroke-width [stroke-width 2])
  (check-point 'arc-between-points start)
  (check-point 'arc-between-points end)
  (check-symbol 'arc-between-points id)
  (check-open-sweep 'arc-between-points sweep-angle)
  (define chord (vec2- end start))
  (define length (point-length chord))
  (unless (positive? length)
    (raise-arguments-error 'arc-between-points "distinct endpoints"
                           "start" start "end" end))
  (define midpoint (vec2-scale 1/2 (vec2+ start end)))
  (define left-normal (vec2 (/ (- (vec2-y chord)) length)
                            (/ (vec2-x chord) length)))
  (define half-sweep (/ sweep-angle 2))
  (define center
    (vec2+ midpoint
           (vec2-scale (/ length (* 2 (tan half-sweep))) left-normal)))
  (define radius (point-distance center start))
  (define start-angle
    (atan (- (vec2-y start) (vec2-y center))
          (- (vec2-x start) (vec2-x center))))
  (make-path-visual
   (path-geometry
    (list
     (path-subpath
      (vec2- start center)
      (elliptical-arc-segments radius radius start-angle sweep-angle)
      #f)))
   #:id id #:center center #:opacity opacity #:fill #f
   #:stroke stroke #:stroke-width stroke-width))

;; curved-arrow : vec2? vec2? #:id symbol? [#:angle nonzero-real?] ...
;;                 -> group-visual?
;; Returns ordinary `shaft` and `tip` children under id. The tip follows the
;; final tangent of the same mathematical circular arc.
(define (curved-arrow start end
                      #:id id
                      #:angle [sweep-angle (/ pi 2)]
                      #:opacity [opacity 1]
                      #:stroke [stroke "black"]
                      #:stroke-width [stroke-width 2]
                      #:tip-length [tip-length 3/10]
                      #:tip-width [tip-width 1/4])
  (check-point 'curved-arrow start)
  (check-point 'curved-arrow end)
  (check-symbol 'curved-arrow id)
  (check-open-sweep 'curved-arrow sweep-angle)
  (check-positive 'curved-arrow "tip-length" tip-length)
  (check-positive 'curved-arrow "tip-width" tip-width)
  (define shaft
    (arc-between-points start end #:id (child-id id "shaft")
                        #:angle sweep-angle #:stroke stroke
                        #:stroke-width stroke-width))
  (define center (visual-position shaft))
  (define radial (vec2- end center))
  (define radius (point-length radial))
  (define tangent
    (if (positive? sweep-angle)
        (vec2 (/ (- (vec2-y radial)) radius) (/ (vec2-x radial) radius))
        (vec2 (/ (vec2-y radial) radius) (/ (- (vec2-x radial)) radius))))
  (define normal (vec2 (- (vec2-y tangent)) (vec2-x tangent)))
  (define base-center (vec2- end (vec2-scale tip-length tangent)))
  (define tip
    (polygon
     (list end
           (vec2+ base-center (vec2-scale (/ tip-width 2) normal))
           (vec2- base-center (vec2-scale (/ tip-width 2) normal)))
     #:id (child-id id "tip") #:fill stroke #:stroke stroke
     #:stroke-width stroke-width))
  (group (list shaft tip) #:id id #:opacity opacity))

;; double-arrow : vec2? vec2? #:id symbol? ... -> arrow-visual?
;; A short semantic spelling for an arrow with tips at both endpoints.
(define (double-arrow start end
                      #:id id
                      #:rotation [rotation 0]
                      #:scale [scale 1]
                      #:opacity [opacity 1]
                      #:stroke [stroke "black"]
                      #:stroke-width [stroke-width 2]
                      #:tip-length [tip-length 3/10]
                      #:tip-width [tip-width 1/4])
  (arrow start end #:id id #:rotation rotation #:scale scale #:opacity opacity
         #:stroke stroke #:stroke-width stroke-width
         #:tip-length tip-length #:tip-width tip-width
         #:start-tip? #t #:end-tip? #t))


;;;
;;; Labeled Marker
;;;

;; labeled-point : string? #:id symbol? [#:center vec2?] ... -> group-visual?
;; Returns a `dot` and `label` as ordinary nested children. Moving or styling
;; the outer group therefore keeps the marker and its label together.
(define (labeled-point label
                       #:id id
                       #:center [center origin]
                       #:radius [radius 1/10]
                       #:label-offset [label-offset (vec2 1/4 1/4)]
                       #:font-size [font-size 1/4]
                       #:font-family [font-family 'roman]
                       #:fill [fill "crimson"]
                       #:stroke [stroke "firebrick"]
                       #:stroke-width [stroke-width 2]
                       #:color [color stroke]
                       #:opacity [opacity 1])
  (unless (string? label)
    (raise-argument-error 'labeled-point "string?" label))
  (check-symbol 'labeled-point id)
  (check-point 'labeled-point center)
  (check-positive 'labeled-point "radius" radius)
  (check-point 'labeled-point label-offset)
  (check-positive 'labeled-point "font-size" font-size)
  (group
   (list
    (circle #:id (child-id id "dot") #:center origin #:radius radius
            #:fill fill #:stroke stroke #:stroke-width stroke-width)
    (plain-text label #:id (child-id id "label") #:center label-offset
                #:font-size font-size #:font-family font-family #:color color))
   #:id id #:center center #:opacity opacity))


;;;
;;; Geometry Helpers
;;;

(define (ellipse-subpath radius-x radius-y)
  (path-subpath (ellipse-point radius-x radius-y 0)
                (elliptical-arc-segments radius-x radius-y 0 (* 2 pi))
                #t))

;; A cubic approximation over pieces no larger than a quarter turn. The usual
;; tangent coefficient gives exact endpoints/tangents and a visually smooth
;; circle/ellipse without depending on a renderer-specific ellipse primitive.
(define (elliptical-arc-segments radius-x radius-y start-angle sweep-angle)
  (define count
    (max 1 (inexact->exact (ceiling (/ (abs sweep-angle) (/ pi 2))))))
  (define delta (/ sweep-angle count))
  (for/list ([index (in-range count)])
    (define from (+ start-angle (* index delta)))
    (define to (+ from delta))
    (define coefficient (* 4/3 (tan (/ delta 4))))
    (define start (ellipse-point radius-x radius-y from))
    (define end (ellipse-point radius-x radius-y to))
    (define tangent-from
      (vec2 (* radius-x (- (sin from))) (* radius-y (cos from))))
    (define tangent-to
      (vec2 (* radius-x (- (sin to))) (* radius-y (cos to))))
    (cubic-bezier-path-segment
     (vec2+ start (vec2-scale coefficient tangent-from))
     (vec2- end (vec2-scale coefficient tangent-to))
     end)))

;; `rounded-rectangle-path` needs translated quarter arcs. Keep that operation
;; explicit rather than making the generic arc helper stateful.
(define (translated-arc-segments center radius start sweep)
  (for/list ([segment (in-list (elliptical-arc-segments radius radius start sweep))])
    (cubic-bezier-path-segment
     (vec2+ center (cubic-bezier-path-segment-control1 segment))
     (vec2+ center (cubic-bezier-path-segment-control2 segment))
     (vec2+ center (cubic-bezier-path-segment-end segment)))))

(define (rounded-rectangle-path half-width half-height radius)
  (define top-right (vec2 (- half-width radius) (- half-height radius)))
  (define bottom-right (vec2 (- half-width radius) (+ (- half-height) radius)))
  (define bottom-left (vec2 (+ (- half-width) radius) (+ (- half-height) radius)))
  (define top-left (vec2 (+ (- half-width) radius) (- half-height radius)))
  (path-geometry
   (list
    (path-subpath
     (vec2 (+ (- half-width) radius) half-height)
     (append
      ;; Walk the straight top edge before entering the top-right quarter arc.
      ;; Omitting this segment would make that corner's cubic start at the
      ;; top-left, visibly skewing the upper edge.
      (list (line-path-segment (vec2 (- half-width radius) half-height)))
      (translated-arc-segments top-right radius (/ pi 2) (- (/ pi 2)))
      (list (line-path-segment (vec2 half-width (+ (- half-height) radius))))
      (translated-arc-segments bottom-right radius 0 (- (/ pi 2)))
      (list (line-path-segment (vec2 (+ (- half-width) radius) (- half-height))))
      (translated-arc-segments bottom-left radius (- (/ pi 2)) (- (/ pi 2)))
      (list (line-path-segment (vec2 (- half-width) (- half-height radius))))
      (translated-arc-segments top-left radius pi (- (/ pi 2))))
     #t))))

(define (ellipse-point radius-x radius-y angle)
  (vec2 (* radius-x (cos angle)) (* radius-y (sin angle))))

(define (point-length point)
  (sqrt (+ (sqr (vec2-x point)) (sqr (vec2-y point)))))

(define (point-distance first second)
  (point-length (vec2- second first)))

(define (check-symbol who value)
  (unless (symbol? value)
    (raise-argument-error who "symbol?" value)))

(define (check-point who value)
  (unless (vec2? value)
    (raise-argument-error who "vec2?" value)))

(define (check-finite who field value)
  (unless (finite-real? value)
    (raise-arguments-error who "finite real?" field value)))

(define (check-positive who field value)
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error who "positive finite real?" field value)))

(define (check-nonnegative who field value)
  (unless (and (finite-real? value) (not (negative? value)))
    (raise-arguments-error who "nonnegative finite real?" field value)))

(define (check-at-least who field value minimum)
  (unless (and (exact-integer? value) (>= value minimum))
    (raise-arguments-error who
                           (format "exact integer at least ~a" minimum)
                           field value)))

(define (check-sweep who value)
  (check-finite who "angle" value)
  (unless (and (not (zero? value)) (<= (abs value) (* 2 pi)))
    (raise-arguments-error who
                           "a nonzero sweep no larger than one full turn"
                           "angle" value)))

(define (check-open-sweep who value)
  (check-finite who "angle" value)
  (unless (and (not (zero? value)) (< (abs value) (* 2 pi)))
    (raise-arguments-error who
                           "a nonzero sweep strictly smaller than one full turn"
                           "angle" value)))

(define (child-id parent suffix)
  (string->symbol (format "~a-~a" parent suffix)))
