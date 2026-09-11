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
  (step "Join the two endpoints." [base (segment A B)])
  (step "Draw a circle centred at each endpoint, through the other."
    [cA (circle A B)] [cB (circle B A)])
  (step "The circles meet at X and Y."
    [(X Y) (intersections cA cB)])
  (step "Draw the line through X and Y." [m (line X Y)])
  (step "This line is the perpendicular bisector of the segment."
    (deemphasize base cA cB) (hide-label X Y))
  (assert (perpendicular base m)
          (midpoint-of (intersection base m) base))
  (result m))

(define-construction bisect-segment
  (given [A : Point] [B : Point])
  (require (distinct? A B))
  (results Point)
  (step "Join the endpoints." [base (segment A B)])
  (step "Construct the perpendicular bisector."
    (expand [m (perpendicular-bisector A B)] #:auxiliaries 'hide))
  (step "Its intersection with the segment is the midpoint."
    [M (intersection base m)])
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
  (step "Choose a point A on the line, different from the given point."
    [A (choose (point-on l #:except P))])
  (step "Draw a circle about the given point, through A." [c (circle P A)])
  (step "Let B be the other intersection with the line."
    [B (intersection c l #:other-than A)])
  (step "Draw equal circles centred at A and B."
    [cA (circle A B)] [cB (circle B A)])
  (step "Use the intersection on the left of the directed given line."
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
  (step "Use two distinct points on the given line."
    [A (start-point l)] [B (end-point l)])
  (step "Draw a circle about each point, through the external point."
    [cA (circle A P)] [cB (circle B P)])
  (step "The circles have one more intersection, Q."
    [Q (intersection cA cB #:other-than P)])
  (step "Join the external point to Q." [m (line P Q)])
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
  (step "Choose a point U on the first ray, different from the vertex."
    [U (choose (point-on BA #:except B))])
  (step "Draw a circle at the vertex, through U." [c (circle B U)])
  (step "It meets the second ray at D." [D (intersection c BC)])
  (step "Draw equal circles about U and D."
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
  (step "Use the starting point of the target ray." [O (start-point target)])
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
  (step "Use the source angle and the starting point of the target ray."
    [A (angle-first source)] [B (angle-vertex source)] [C (angle-last source)]
    [O (start-point target)])
  (step "Draw a circle at the source vertex, through A."
    [c (circle B A)])
  (step "It meets the second side at D."
    [D (intersection c (ray B C))])
  (step "With the same compass opening, draw a circle at the new vertex."
    [cO (circle O #:radius (distance B A))])
  (step "Let X be its intersection with the target ray."
    [X (intersection cO target)])
  (step "Set the compass to the chord from A to D, and draw a circle about X."
    [cX (circle X #:radius (distance A D))])
  (step "Use the intersection on the chosen side of the target ray."
    [Y (intersection cO cX #:side-of target side)])
  (step "Draw the ray from the new vertex through Y." [r (ray O Y)])
  (step "The new angle equals the source angle."
    [angles (marker (equal-angle source (angle X O Y)))]
    (deemphasize c cO cX) (hide-label D X Y))
  (assert (equal-angle source (angle X O Y))
          (side-of? Y target side))
  (result r))
