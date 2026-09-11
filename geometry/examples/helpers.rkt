#lang racket/base

;; Reusable mathematical construction; no rendering side effects or dependency
;; on animate. The perpendicular-bisector demo expands this same helper.
(require "../core.rkt")
(provide perpendicular-bisector)

(define-construction perpendicular-bisector
  (given [A : Point] [B : Point])
  (results Line)
  (require (distinct? A B))
  (style [cA [color-family blue]] [cB [color-family aqua]])
  (step "Draw a circle centred at A through B." [cA (circle A B)])
  (step "Draw a circle centred at B through A." [cB (circle B A)])
  (step "The two circles meet at C and D." [(C D) (intersections cA cB)])
  (step "Draw the line through C and D." [m (line C D)])
  (step "The circles remain as subdued construction aids."
    (deemphasize cA cB) (hide-label C D))
  (result m))
