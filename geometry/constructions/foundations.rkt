#lang racket/base

;; Compass-and-straightedge algorithms, not coordinate shortcuts.
;; A transferable compass is assumed by circle's #:radius form. The midpoint,
;; projection, angle-bisector, and parallel results are obtained by intersections.
(require "../core.rkt")
(provide perpendicular-bisector bisect-segment erect-perpendicular
         drop-perpendicular angle-bisector parallel-through-point
         copy-segment copy-angle)

(define-construction perpendicular-bisector
  (given [A : Point] [B : Point])
  (require (distinct? A B))
  (results Line)
  (step (caption "Join " A " to " B ".") [base (segment A B)])
  (step "Draw a circle centred at each endpoint, through the other."
    [cA (circle A B)] [cB (circle B A)])
  (step (caption "The circles meet at " X " and " Y ".")
    [(X Y) (intersections cA cB)])
  (step (caption "Draw the line through " X " and " Y ".") [m (line X Y)])
  (step "This line is the perpendicular bisector of the segment."
    (deemphasize cA cB) (hide base) (hide-label X Y))
  (assert (perpendicular base m)
          (midpoint-of (intersection base m) base))
  (result m))

(define-construction bisect-segment
  (given [A : Point] [B : Point])
  (require (distinct? A B))
  (results Point)
  (step "Construct the perpendicular bisector."
    (expand [m (perpendicular-bisector A B)] #:auxiliaries 'hide))
  (step "Its intersection with the segment is the midpoint."
    [base (segment A B)] [M (intersection base m)])
  (step "The two parts have equal length."
    [halves (marker (midpoint-of M base))]
    (deemphasize m))
  (assert (midpoint-of M base))
  (result M))

(define-construction erect-perpendicular
  (given [l : Line] [P : Point])
  (require (on P l))
  (results Line)
  ;; This preference realizes a free compass opening, not a mathematical step.
  (layout (prefer (distance P A)
                  (/ (distance (start-point l) (end-point l)) 3)))
  (step (caption "Choose " A " on the line, different from " P ".")
    (show l) [A (choose (point-on l #:except P))])
  (step (caption "Draw a circle centred at " P " through " A ".") [c (circle P A)])
  (step (caption "Let " B " be the other intersection with the line.")
    [B (intersection c l #:other-than A)])
  (step (caption "Draw equal circles centred at " A " and " B ".")
    [cA (circle A B)] [cB (circle B A)])
  (step (caption "Call one of the circle intersections " X ".")
    [X (intersection cA cB #:side-of l 'left)])
  (step "Draw the perpendicular through the given point and this intersection."
    [m (line P X)])
  (step "It passes through the given point at a right angle."
    [right-angle (marker (perpendicular l m #:at P))]
    (deemphasize c cA cB) (hide-label A B X))
  (assert (on P m) (perpendicular l m #:at P) (side-of? (end-point m) l 'left))
  (result m))

(define-construction drop-perpendicular
  (given [l : Line] [P : Point])
  (require (not (on P l)))
  (results Line)
  (initially (hide-label A B))
  (step #:duration 0.2 "Use two distinct points on the given line."
    (show l) [A (start-point l)] [B (end-point l)])
  (step "Draw a circle about each point, through the external point."
    [cA (circle A P)] [cB (circle B P)])
  (step (caption "The circles have one more intersection, " Q ".")
    [Q (intersection cA cB #:other-than P)])
  (step (caption "Join " P " to " Q ".") [m (line P Q)])
  (step "This line meets the given line at a right angle."
    (deemphasize cA cB) (hide-label Q))
  (assert (on P m) (perpendicular l m))
  (result m))

(define-construction angle-bisector
  (given [A : Point] [B : Point] [C : Point])
  (require (noncollinear? A B C))
  (results Ray)
  (layout (prefer (distance B U) (/ (distance B A) 3)))
  (step "Draw the two rays of the angle."
    [BA (ray B A)] [BC (ray B C)])
  (step (caption "Choose " U " on the first ray, away from the vertex.")
    [U (choose (point-on BA #:except B))])
  (step (caption "Draw a circle centred at " B " through " U ".") [c (circle B U)])
  (step (caption "It meets the second ray at " D ".") [D (intersection c BC)])
  (step (caption "Draw equal circles about " U " and " D ".")
    [cA (circle U D)] [cD (circle D U)])
  ;; The farther intersection lies in the interior angular sector even for an
  ;; obtuse angle. There is no screen-coordinate 'above' branch selection.
  (step "Choose the intersection farther from the vertex."
    [E (intersection cA cD #:far-from B)])
  (step "Draw the ray from the vertex through this intersection."
    [r (ray B E)])
  (step "The ray divides the angle into two equal angles."
    [angles (marker (equal-angle (angle A B E) (angle E B C)))]
    (deemphasize BA BC c cA cD) (hide-label U D E))
  (assert (equal-angle (angle A B E) (angle E B C)))
  (result r))

(define-construction parallel-through-point
  (given [l : Line] [P : Point])
  ;; Separate on-line/off-line construction stories, as with erect/drop.
  ;; Through a point already on l the answer is simply l; no new construction.
  (require (not (on P l)))
  (results Line)
  (step "Construct the perpendicular from the external point to the line."
    (expand [n (drop-perpendicular l P)] #:auxiliaries 'hide))
  (step "At the external point, construct a perpendicular to that perpendicular."
    (expand [m (erect-perpendicular n P)] #:auxiliaries 'hide))
  (step "The resulting line is parallel to the original line."
    [arrows (marker (parallel l m))] (deemphasize n))
  (assert (on P m) (parallel l m))
  (result m))

(define-construction copy-segment
  (given [source : Segment] [target : Ray])
  (results Point)
  (initially (hide-label O))
  (step #:duration 0.2 "Use the starting point of the target ray."
    [O (start-point target)] (show target))
  (step "Set the compass to the source length, and draw a circle at this point."
    [c (circle O #:radius (length source))])
  (step "The circle meets the target ray at the required endpoint."
    [Q (intersection c target)])
  (step "The new segment has the same length as the source segment."
    [s (segment O Q)] [ticks (marker (equal-length source s))]
    (deemphasize c))
  (assert (on Q target) (equal-length source (segment O Q)))
  (result Q))

(define-construction copy-angle
  (given [source : Angle] [target : Ray] [side : Side])
  (require (noncollinear? (angle-first source)
                         (angle-vertex source)
                         (angle-last source)))
  (results Ray)
  (initially (hide-label A B C O))
  ;; U chooses only a convenient compass opening. The resulting angle does not
  ;; depend on that choice. A segment domain avoids the old full-side opening,
  ;; which made D coincide (or nearly coincide) with the source endpoint C.
  (layout (prefer (distance B U) (/ (distance B A) 3)))
  (step #:duration 0.15 #:pause 0 "Use the source angle and the target ray."
    [A (angle-first source)] [B (angle-vertex source)] [C (angle-last source)]
    [O (start-point target)]
    [first-arm (ray B A)] [second-arm (ray B C)] (show target))
  (step (caption "Choose " U " between " B " and " A ".")
    [U (choose (point-on (segment B A)))])
  (step (caption "Draw a circle centred at " B " through " U ".")
    [c (circle B U)])
  (step (caption "It meets the second arm at " D ".")
    [D (intersection c second-arm)])
  (step (caption "Join " U " to " D " to form a chord.")
    [chord (segment U D)])
  (step (caption "With the same compass opening, draw a circle centred at " O ".")
    [cO (circle O #:radius (distance B U))])
  (step (caption "Let " X " be its intersection with the target ray.")
    [X (intersection cO target)])
  (step (caption "Set the compass to " U D ", and draw a circle centred at " X ".")
    [cX (circle X #:radius (length chord))])
  (step "Use the intersection on the chosen side of the target ray."
    [Y (intersection cO cX #:side-of target side)])
  (step (caption "Draw the ray from " O " through " Y ".") [r (ray O Y)])
  (step "The new angle equals the source angle."
    [angles (marker (equal-angle source (angle X O Y)))]
    (deemphasize first-arm second-arm c cO cX chord) (hide-label U D X Y))
  (assert (equal-angle source (angle X O Y))
          (side-of? Y target side))
  (result r))
