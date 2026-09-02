#lang racket/base

;;;
;;; SCENE-CN: Dynamic Endpoint Geometry
;;;

;; The triangle sides are derived from the vertices rather than manually
;; recomputed.  As the three vertices move, the sides and the highlighted arrow
;; remain connected at every sampled frame.

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

;; The perpendicular foot of point c on the infinite line through a and b.
;; This is deliberately a pure vector calculation: its three inputs are read
;; from one sampled scene state by the derived altitude Visual below.
(define (projection-on-line a b c)
  (define ab (vec2- b a))
  (define ac (vec2- c a))
  (define denominator
    (+ (* (vec2-x ab) (vec2-x ab))
       (* (vec2-y ab) (vec2-y ab))))
  (unless (positive? denominator)
    (raise-arguments-error
     'projection-on-line
     "two distinct points defining the base line"
     "a" a
     "b" b))
  (define projection-scale
    (/ (+ (* (vec2-x ac) (vec2-x ab))
          (* (vec2-y ac) (vec2-y ab)))
       denominator))
  (vec2+ a (vec2-scale projection-scale ab)))

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-CN: dynamic endpoint geometry"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 2/5 #:font-weight 'bold #:color "navy"))
  (define explanation
    (plain-text "Move the vertices; sides stay connected and the altitude stays perpendicular."
                #:id 'explanation #:center (vec2 0 14/5)
                #:font-size 1/5 #:color "darkslategray"))
  (define A
    (circle #:id 'A #:center (vec2 -3/2 -1) #:radius 1/6
            #:fill "royalblue" #:stroke "navy" #:stroke-width 2))
  (define B
    (circle #:id 'B #:center (vec2 5/2 -1) #:radius 1/6
            #:fill "royalblue" #:stroke "navy" #:stroke-width 2))
  (define C
    (circle #:id 'C #:center (vec2 1/2 2) #:radius 1/6
            #:fill "royalblue" #:stroke "navy" #:stroke-width 2))
  (define A-label
    (attach-to
     (plain-text "A" #:id 'A-label #:center origin
                 #:font-size 1/4 #:color "navy")
     'A #:target-anchor 'top #:self-anchor 'bottom #:offset (vec2 0 1/8)))
  (define B-label
    (attach-to
     (plain-text "B" #:id 'B-label #:center origin
                 #:font-size 1/4 #:color "navy")
     'B #:target-anchor 'top #:self-anchor 'bottom #:offset (vec2 0 1/8)))
  (define C-label
    (attach-to
     (plain-text "C" #:id 'C-label #:center origin
                 #:font-size 1/4 #:color "navy")
     'C #:target-anchor 'top #:self-anchor 'bottom #:offset (vec2 0 1/8)))
  (define AB (segment-between 'A 'B #:id 'AB #:stroke "steelblue" #:stroke-width 4))
  (define BC (segment-between 'B 'C #:id 'BC #:stroke "steelblue" #:stroke-width 4))
  (define CA (segment-between 'C 'A #:id 'CA #:stroke "steelblue" #:stroke-width 4))
  ;; Rebuild a genuine altitude from the sampled triangle: its endpoint is the
  ;; perpendicular projection of C onto the live line through A and B. The
  ;; arrow is painted behind the triangle, so AB cleanly covers its contact
  ;; point and C naturally covers its centre start.
  (define height-hint
    (derived-visual
     (arrow origin (vec2 1 0)
            #:id 'height-hint #:stroke "crimson" #:stroke-width 3
            #:tip-length 1/4 #:tip-width 1/4)
     (lambda (context _template)
       (define a
         (visual-position (derived-context-visual-ref context 'A)))
       (define b
         (visual-position (derived-context-visual-ref context 'B)))
       (define c
         (visual-position (derived-context-visual-ref context 'C)))
       (arrow c (projection-on-line a b c)
              #:id 'height-hint #:stroke "crimson" #:stroke-width 3
              #:tip-length 1/4 #:tip-width 1/4))))
  (define initial
    (scene-add (make-scene)
               height-hint AB BC CA A B C A-label B-label C-label
               title explanation))
  (scene-wait
   (scene-play initial
               (move-to 'A (vec2 -5/2 -3/2))
               (move-to 'B (vec2 3 -1/4))
               (move-to 'C (vec2 -1/4 3/2))
               #:duration 3)
   1))

(module+ main
  (run-demo "dynamic-endpoint-geometry.rkt" make-demo-scene))
