#lang racket/base

;;;
;;; Mathematical Annotation Geometry
;;;

;; Small, semantic, path-backed primitives used repeatedly in explanatory
;; diagrams.  Every constructor returns ordinary built-in Visuals, so path
;; creation, morphing, styling, and renderer substitution continue to work
;; without an annotation-specific backend.

(require (only-in racket/math pi)
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "visual-model.rkt"
         "text-visual.rkt")

(provide arc
         dashed-path
         dashed-line
         angle
         right-angle
         brace
         brace-between
         brace-label
         surrounding-rectangle
         surrounding-rectangle-visual?
         surrounding-rectangle-template
         surrounding-rectangle-visual-target
         surrounding-rectangle-visual-padding)


;;;
;;; Circular and Dashed Paths
;;;

; arc : #:id symbol?
;       [#:center vec2?]
;       [#:radius positive-finite-real?]
;       [#:start-angle finite-real?]
;       [#:angle nonzero finite-real?]
;       [#:opacity opacity?]
;       [#:stroke any/c]
;       [#:stroke-width stroke-width?]
;       -> path-visual?
;; Creates an open circular arc. A positive sweep is counter-clockwise.
(define (arc #:id id
             #:center [center origin]
             #:radius [radius 1]
             #:start-angle [start-angle 0]
             #:angle [sweep-angle (/ pi 2)]
             #:opacity [opacity 1]
             #:stroke [stroke "black"]
             #:stroke-width [stroke-width 2])
  (check-symbol 'arc id)
  (check-point 'arc center)
  (check-positive 'arc "radius" radius)
  (check-finite 'arc "start-angle" start-angle)
  (check-finite 'arc "angle" sweep-angle)
  (unless (and (not (zero? sweep-angle))
               (<= (abs sweep-angle) (* 2 pi)))
    (raise-arguments-error
     'arc
     "a nonzero sweep angle no larger than one full turn"
     "angle" sweep-angle))
  (make-path-visual
   (circular-arc-path radius start-angle sweep-angle)
   #:id id #:center center #:opacity opacity #:fill #f
   #:stroke stroke #:stroke-width stroke-width))

; dashed-path : path-geometry?
;               #:id symbol?
;               [#:dash-length positive-finite-real?]
;               [#:gap-length nonnegative-finite-real?]
;               ... ordinary path style keywords ...
;               -> path-visual?
;; Converts each selected arc-length interval of geometry into a separate open
;; subpath.  Dashes therefore retain curves rather than being flattened.
(define (dashed-path geometry
                     #:id id
                     #:dash-length [dash-length 1/5]
                     #:gap-length [gap-length 1/8]
                     #:center [center origin]
                     #:rotation [rotation 0]
                     #:scale [scale 1]
                     #:opacity [opacity 1]
                     #:stroke [stroke "black"]
                     #:stroke-width [stroke-width 2])
  (unless (path-geometry? geometry)
    (raise-argument-error 'dashed-path "path-geometry?" geometry))
  (check-symbol 'dashed-path id)
  (check-positive 'dashed-path "dash-length" dash-length)
  (check-nonnegative 'dashed-path "gap-length" gap-length)
  (make-path-visual
   (dash-geometry geometry dash-length gap-length)
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:fill #f #:stroke stroke #:stroke-width stroke-width))

; dashed-line : vec2? vec2?
;               #:id symbol?
;               [#:dash-length positive-finite-real?]
;               [#:gap-length nonnegative-finite-real?]
;               ... ordinary line style keywords ...
;               -> path-visual?
;; Creates a finite dashed line with round capped dashes.
(define (dashed-line start end
                     #:id id
                     #:dash-length [dash-length 1/5]
                     #:gap-length [gap-length 1/8]
                     #:opacity [opacity 1]
                     #:stroke [stroke "black"]
                     #:stroke-width [stroke-width 2])
  (check-point 'dashed-line start)
  (check-point 'dashed-line end)
  (when (same-point? start end)
    (raise-arguments-error
     'dashed-line "distinct endpoints" "start" start "end" end))
  (centered-path-visual
   'dashed-line
   (dash-geometry (polyline-path (list start end)) dash-length gap-length)
   id opacity stroke stroke-width))


;;;
;;; Angle Marks
;;;

; angle : vec2? vec2? vec2?
;         #:id symbol?
;         [#:radius positive-finite-real?]
;         [#:reflex? boolean?]
;         ... ordinary path style keywords ...
;         -> path-visual?
;; Draws the shorter (or, with reflex?, longer) directed angle from first to
;; second around vertex. The mark itself is an open circular arc.
(define (angle first vertex second
               #:id id
               #:radius [radius 1/3]
               #:reflex? [reflex? #f]
               #:opacity [opacity 1]
               #:stroke [stroke "black"]
               #:stroke-width [stroke-width 2])
  (check-point 'angle first)
  (check-point 'angle vertex)
  (check-point 'angle second)
  (check-symbol 'angle id)
  (check-positive 'angle "radius" radius)
  (unless (boolean? reflex?)
    (raise-argument-error 'angle "boolean?" reflex?))
  (define first-vector (vec2- first vertex))
  (define second-vector (vec2- second vertex))
  (define first-length (point-distance vertex first))
  (define second-length (point-distance vertex second))
  (unless (positive? first-length)
    (raise-arguments-error 'angle "first distinct from vertex"
                           "first" first "vertex" vertex))
  (unless (positive? second-length)
    (raise-arguments-error 'angle "second distinct from vertex"
                           "second" second "vertex" vertex))
  (define start-angle (atan (vec2-y first-vector) (vec2-x first-vector)))
  (define signed-sweep
    (principal-angle
     (- (atan (vec2-y second-vector) (vec2-x second-vector)) start-angle)))
  (when (zero? signed-sweep)
    (raise-arguments-error
     'angle "noncollinear rays" "first" first "vertex" vertex "second" second))
  (define sweep
    (if reflex?
        (- signed-sweep (* (if (positive? signed-sweep) 1 -1) (* 2 pi)))
        signed-sweep))
  (arc #:id id #:center vertex #:radius radius #:start-angle start-angle
       #:angle sweep #:opacity opacity #:stroke stroke #:stroke-width stroke-width))

; right-angle : vec2? vec2? vec2?
;               #:id symbol?
;               [#:size positive-finite-real?]
;               ... ordinary path style keywords ...
;               -> path-visual?
;; Draws the conventional three-segment right-angle square from two rays. It
;; checks neither that the rays are perpendicular nor that the square is inside
;; a triangle; those are deliberate author-controlled diagram choices.
(define (right-angle first vertex second
                     #:id id
                     #:size [size 1/3]
                     #:opacity [opacity 1]
                     #:stroke [stroke "black"]
                     #:stroke-width [stroke-width 2])
  (check-point 'right-angle first)
  (check-point 'right-angle vertex)
  (check-point 'right-angle second)
  (check-symbol 'right-angle id)
  (check-positive 'right-angle "size" size)
  (define first-direction (unit-vector 'right-angle vertex first))
  (define second-direction (unit-vector 'right-angle vertex second))
  (define a (vec2+ vertex (vec2-scale size first-direction)))
  (define b (vec2+ a (vec2-scale size second-direction)))
  (define c (vec2+ vertex (vec2-scale size second-direction)))
  (centered-path-visual
   'right-angle (polyline-path (list a b c)) id opacity stroke stroke-width))


;;;
;;; Braces
;;;

; brace : vec2? vec2? ... -> path-visual?
;; A short spelling of brace-between.
(define (brace start end
               #:id id
               #:offset [offset 1/3]
               #:opacity [opacity 1]
               #:stroke [stroke "black"]
               #:stroke-width [stroke-width 2])
  (brace-between start end #:id id #:offset offset #:opacity opacity
                 #:stroke stroke #:stroke-width stroke-width))

; brace-between : vec2? vec2?
;                 #:id symbol?
;                 [#:offset finite-real?]
;                 ... ordinary path style keywords ...
;                 -> path-visual?
;; Creates a symmetric, open curly brace from start to end. Positive offset is
;; to the left of start-to-end travel; a negative offset selects the other side.
;; Its stroke follows the Manim/TeX brace convention: shallow end curls lead
;; into a rule with one narrow, unfilled central cusp.
(define (brace-between start end
                       #:id id
                       #:offset [offset 1/3]
                       #:opacity [opacity 1]
                       #:stroke [stroke "black"]
                       #:stroke-width [stroke-width 2])
  (check-point 'brace-between start)
  (check-point 'brace-between end)
  (check-symbol 'brace-between id)
  (check-finite 'brace-between "offset" offset)
  (when (zero? offset)
    (raise-argument-error 'brace-between "nonzero finite offset" offset))
  (define direction (unit-vector 'brace-between start end))
  (define normal (vec2 (- (vec2-y direction)) (vec2-x direction)))
  (define length (point-distance start end))
  (define (at along perpendicular)
    (vec2+ start
           (vec2+ (vec2-scale (* along length) direction)
                  (vec2-scale perpendicular normal))))
  ;; This is one open centreline rather than a closed filled silhouette. Keeping
  ;; every point on the selected side of the annotated segment makes the brace
  ;; safe for closely spaced geometry labels, while the open centre cusp remains
  ;; visibly hollow at any stroke width.
  ;; The curl tips return about a quarter of the way toward the annotated
  ;; segment, while the central cusp reaches twice the rule offset. This gives
  ;; the compact but legible profile of Manim's brace at ordinary diagram size.
  (define curl-offset (* 1/4 offset))
  (define cusp-offset (* 2 offset))
  ;; The outer tips align directly with `start` and `end`. The little horizontal
  ;; span of each curl is four percent of the annotated segment, matching the
  ;; compact proportions of Manim's brace while preserving the endpoint
  ;; alignment expected in a geometry diagram.
  (define end-curl-width 1/25)
  ;; The two central curves occupy roughly eight percent of the rule. This keeps
  ;; the cusp narrow without turning it into a filled-looking triangle.
  (define central-half-width 1/25)
  (define central-right (+ 1/2 central-half-width))
  (define central-left (- 1/2 central-half-width))
  (define geometry
    (path-subpath
     (at 0 curl-offset)
     (list
      ;; Left outer curl and the long rule nearest the annotated segment.
      (cubic-bezier-path-segment (at 0 offset)
                                 (at (/ end-curl-width 2) offset)
                                 (at end-curl-width offset))
      (line-path-segment (at central-left offset))
      ;; The two cubic pieces meet at a narrow outward cusp. Because this path
      ;; is open and unfilled, the region surrounding that cusp stays hollow.
      (cubic-bezier-path-segment
       (at (+ central-left (/ central-half-width 2)) offset)
       (at 1/2 (* 3/2 offset))
       (at 1/2 cusp-offset))
      (cubic-bezier-path-segment
       (at 1/2 (* 3/2 offset))
       (at (- central-right (/ central-half-width 2)) offset)
       (at central-right offset))
      (line-path-segment (at (- 1 end-curl-width) offset))
      ;; Exact mirror of the left curl about the brace midpoint.
      (cubic-bezier-path-segment (at (- 1 (/ end-curl-width 2)) offset)
                                 (at 1 offset)
                                 (at 1 curl-offset)))
     #f))
  (centered-path-visual
   'brace-between (path-geometry (list geometry)) id opacity stroke stroke-width))

; brace-label : vec2? vec2? string?
;               #:id symbol?
;               [#:offset finite-real?]
;               [#:gap nonnegative-finite-real?]
;               ... brace/text style keywords ...
;               -> group-visual?
;; Constructs a static brace with a centered ordinary text label on the brace's
;; selected side.  The group's stable child IDs are derived from id.
(define (brace-label start end label
                     #:id id
                     #:offset [offset 1/3]
                     #:gap [gap 1/6]
                     #:font-size [font-size 1/4]
                     #:color [color "black"]
                     #:opacity [opacity 1]
                     #:stroke [stroke "black"]
                     #:stroke-width [stroke-width 2])
  (unless (string? label)
    (raise-argument-error 'brace-label "string?" label))
  (check-symbol 'brace-label id)
  (check-finite 'brace-label "offset" offset)
  (check-nonnegative 'brace-label "gap" gap)
  (define direction (unit-vector 'brace-label start end))
  (define normal (vec2 (- (vec2-y direction)) (vec2-x direction)))
  ;; Place the label beyond the brace's outward cusp, rather than merely beyond
  ;; its horizontal rule. This preserves the advertised `gap` when a brace has
  ;; a pronounced Manim-style centre notch.
  (define cusp-offset (* 2 offset))
  (define label-position
    (vec2+
     (point-midpoint start end)
     (vec2-scale (+ cusp-offset (if (negative? offset) (- gap) gap)) normal)))
  (group
   (list
    (brace-between start end #:id (derived-id id "brace") #:offset offset
                   #:opacity opacity #:stroke stroke #:stroke-width stroke-width)
    (plain-text label #:id (derived-id id "label") #:center label-position
                #:font-size font-size #:color color #:opacity opacity))
   #:id id))


;;;
;;; Renderer-Measured Enclosure
;;;

;; The selected target's rendered bounds only exist in the adapter, so this is
;; declarative model data. Its concrete rectangle is constructed after ordinary
;; scene sampling, exactly as SCENE-CM's non-centre attachment is.
(define enclosure-template-id visual-id)
(define enclosure-template-position visual-position)
(define enclosure-template-with-position visual-with-position)
(define enclosure-template-opacity visual-opacity)
(define enclosure-template-with-opacity visual-with-opacity)

(struct surrounding-rectangle-value (template target padding)
  #:transparent
  #:methods gen:visual
  [(define (visual-id enclosure)
     (enclosure-template-id (surrounding-rectangle-value-template enclosure)))
   (define (visual-position enclosure)
     (enclosure-template-position
      (surrounding-rectangle-value-template enclosure)))
   (define (visual-with-position enclosure position)
     (struct-copy
      surrounding-rectangle-value enclosure
      [template
       (enclosure-template-with-position
        (surrounding-rectangle-value-template enclosure) position)]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity enclosure)
     (enclosure-template-opacity
      (surrounding-rectangle-value-template enclosure)))
   (define (visual-with-opacity enclosure opacity)
     (struct-copy
      surrounding-rectangle-value enclosure
      [template
       (enclosure-template-with-opacity
        (surrounding-rectangle-value-template enclosure) opacity)]))])

; surrounding-rectangle : (or/c visual? symbol? visual-path?)
;                         #:id symbol?
;                         [#:padding nonnegative-finite-real?]
;                         [#:opacity opacity?]
;                         [#:fill any/c]
;                         [#:stroke any/c]
;                         [#:stroke-width stroke-width?]
;                         -> surrounding-rectangle-visual?
;; Creates a top-level renderer-aware outline around the target's live rendered
;; bounding box. Padding is measured in world coordinates on every render.
(define (surrounding-rectangle target
                               #:id id
                               #:padding [padding 1/8]
                               #:opacity [opacity 1]
                               #:fill [fill #f]
                               #:stroke [stroke "yellow"]
                               #:stroke-width [stroke-width 3])
  (check-symbol 'surrounding-rectangle id)
  (check-nonnegative 'surrounding-rectangle "padding" padding)
  (unless (opacity? opacity)
    (raise-argument-error 'surrounding-rectangle "finite real in [0, 1]" opacity))
  (unless (stroke-width? stroke-width)
    (raise-argument-error 'surrounding-rectangle "nonnegative finite real?" stroke-width))
  (define target-path (visual-target-id target 'surrounding-rectangle))
  (define target-id
    (if (symbol? target-path) target-path (car (reverse target-path))))
  (when (eq? id target-id)
    (raise-arguments-error
     'surrounding-rectangle "an enclosure identity distinct from its target"
     "id" id "target" target-path))
  (surrounding-rectangle-value
   (rectangle #:id id #:center origin #:width 1 #:height 1
              #:opacity opacity #:fill fill #:stroke stroke #:stroke-width stroke-width)
   target-path
   padding))

(define (surrounding-rectangle-visual? value)
  (surrounding-rectangle-value? value))

(define surrounding-rectangle-template
  surrounding-rectangle-value-template)
(define surrounding-rectangle-visual-target
  surrounding-rectangle-value-target)
(define surrounding-rectangle-visual-padding
  surrounding-rectangle-value-padding)


;;;
;;; Helpers
;;;

(define (circular-arc-path radius start-angle sweep)
  (define count
    (max 1 (inexact->exact (ceiling (/ (abs sweep) (/ pi 2))))))
  (define step (/ sweep count))
  (define (point theta)
    (vec2 (* radius (cos theta)) (* radius (sin theta))))
  (define (segment from-angle)
    (define to-angle (+ from-angle step))
    (define k (* 4/3 (tan (/ step 4))))
    (define from (point from-angle))
    (define to (point to-angle))
    (define tangent-from (vec2 (* -1 radius (sin from-angle))
                               (* radius (cos from-angle))))
    (define tangent-to (vec2 (* -1 radius (sin to-angle))
                             (* radius (cos to-angle))))
    (cubic-bezier-path-segment
     (vec2+ from (vec2-scale k tangent-from))
     (vec2- to (vec2-scale k tangent-to))
     to))
  (cubic-bezier-path
   (point start-angle)
   (for/list ([index (in-range count)])
     (segment (+ start-angle (* index step))))))

(define (dash-geometry geometry dash-length gap-length)
  (define total-length (path-geometry-length geometry))
  (cond
    [(zero? total-length) empty-path-geometry]
    [else
     (define subpaths
       (let loop ([start 0] [pieces '()])
         (if (>= start total-length)
             (reverse pieces)
             (let* ([end (min total-length (+ start dash-length))]
                    [piece
                     (path-geometry-partial geometry
                                            (/ start total-length)
                                            (/ end total-length))])
               (loop (+ end gap-length)
                     (append (reverse (path-geometry-subpaths piece)) pieces))))))
     (path-geometry subpaths)]))

(define (centered-path-visual who geometry id opacity stroke stroke-width)
  (check-symbol who id)
  (unless (opacity? opacity)
    (raise-argument-error who "finite real in [0, 1]" opacity))
  (unless (stroke-width? stroke-width)
    (raise-argument-error who "nonnegative finite real?" stroke-width))
  (define center (path-geometry-center geometry))
  (make-path-visual
   (path-geometry-translate geometry (vec2-scale -1 center))
   #:id id #:center center #:opacity opacity #:fill #f
   #:stroke stroke #:stroke-width stroke-width))

(define (centered-filled-path-visual who geometry id opacity fill stroke-width)
  (check-symbol who id)
  (unless (opacity? opacity)
    (raise-argument-error who "finite real in [0, 1]" opacity))
  (unless (stroke-width? stroke-width)
    (raise-argument-error who "nonnegative finite real?" stroke-width))
  (define center (path-geometry-center geometry))
  (make-path-visual
   (path-geometry-translate geometry (vec2-scale -1 center))
   #:id id #:center center #:opacity opacity #:fill fill
   #:stroke fill #:stroke-width stroke-width))

(define (principal-angle value)
  (cond [(> value pi) (- value (* 2 pi))]
        [(<= value (- pi)) (+ value (* 2 pi))]
        [else value]))

(define (unit-vector who start end)
  (define displacement (vec2- end start))
  (define length (point-distance start end))
  (unless (positive? length)
    (raise-arguments-error who "distinct endpoints" "start" start "end" end))
  (vec2-scale (/ 1 length) displacement))

(define (point-midpoint a b)
  (vec2 (+ (/ (vec2-x a) 2) (/ (vec2-x b) 2))
        (+ (/ (vec2-y a) 2) (/ (vec2-y b) 2))))

(define (point-distance a b)
  (define dx (- (vec2-x b) (vec2-x a)))
  (define dy (- (vec2-y b) (vec2-y a)))
  (sqrt (+ (* dx dx) (* dy dy))))

(define (same-point? a b) (and (= (vec2-x a) (vec2-x b)) (= (vec2-y a) (vec2-y b))))
(define (derived-id base suffix) (string->symbol (format "~a-~a" base suffix)))
(define (check-point who value) (unless (vec2? value) (raise-argument-error who "vec2?" value)))
(define (check-symbol who value) (unless (symbol? value) (raise-argument-error who "symbol?" value)))
(define (check-finite who name value) (unless (finite-real? value) (raise-arguments-error who "a finite real" name value)))
(define (check-positive who name value) (unless (and (finite-real? value) (positive? value)) (raise-arguments-error who "a positive finite real" name value)))
(define (check-nonnegative who name value) (unless (and (finite-real? value) (not (negative? value))) (raise-arguments-error who "a nonnegative finite real" name value)))
