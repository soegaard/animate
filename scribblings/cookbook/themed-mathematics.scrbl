#lang scribble/manual

@(require (for-label (except-in racket/base tan)
                     animate
                     animate/colors
                     animate/3d))

@title[#:tag "themed-mathematics"]{Themed Mathematics}

This recipe makes a small mathematical diagram readable on light and dark
backgrounds while keeping one literal institutional color fixed.

@racketblock[
(require animate
         animate/colors
         animate/3d)

(define institution-blue (rgb-color 20 70 170))

(define axes
  (coordinate-axes #:id 'axes #:stroke theme-axis))
(define grid
  (axes-grid-lines axes #:id 'grid #:stroke theme-grid))
(define heading
  (plain-text "f(x) = x²" #:id 'heading
              #:color theme-foreground #:center (vec2 0 3)))
(define badge
  (circle #:id 'institution-mark #:radius 1/5
          #:fill institution-blue #:stroke institution-blue))

(define diagram
  (scene-wait (scene-add (make-scene) grid axes heading badge) 1))

(define heat
  (diverging-color-scale #:minimum -1 #:maximum 1 #:midpoint 0
                         #:missing theme-muted))]

Pass @racket[diagram] unchanged to a preview or render specification with
@racket[animate-light-theme] and @racket[animate-dark-theme]. The roles adapt;
@racket[institution-blue] stays fixed. The diverging scale separately records
that zero is a meaningful center, so it is not confused with the categorical
series used for multiple curves.

For a spatial object, material color follows the same rule:

@racketblock[
(define material
  (material3d #:color theme-surface
              #:specular-color theme-highlight
              #:emission institution-blue
              #:emission-strength 1/10))]

The preview Material section reports each authored material color and the
resolved input to the lighting equation. It does not describe the final lit
pixel as if it were a palette swatch.
