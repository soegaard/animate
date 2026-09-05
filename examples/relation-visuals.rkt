#lang racket/base

;;;
;;; First-Class Relation Visuals
;;;

;; The altitude is a pure semantic relation of three named vertices. Its label
;; is a separate renderer-aware layout relation, declared against the altitude's
;; rendered top anchor. Neither is a mutable per-frame callback.

(require animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (vertex id center color)
  ;; Vertices mark geometric points; keep them visually subordinate to the
  ;; triangle edges they identify.
  (circle #:id id #:center center #:radius 1/16
          #:fill color #:stroke "midnightblue" #:stroke-width 2))

(define (altitude-endpoint A C)
  ;; This focused example keeps AB horizontal, so its perpendicular foot has
  ;; C's x coordinate and A's y coordinate.
  (vec2 (vec2-x (visual-position C))
        (vec2-y (visual-position A))))

(define (make-demo-scene)
  (define A (vertex 'A (vec2 -2 -1) "royalblue"))
  (define B (vertex 'B (vec2 2 -1) "royalblue"))
  (define C (vertex 'C (vec2 1 2) "tomato"))
  (define base
    (line (visual-position A) (visual-position B)
          #:id 'base #:stroke "steelblue" #:stroke-width 3))
  (define side-AC
    (relation-visual
     ;; The template's centre must be at the origin: its outer envelope is
     ;; applied after the semantic relation has produced the current edge.
     (line (vec2 -1/2 0) (vec2 1/2 0)
           #:id 'side-AC #:stroke "steelblue" #:stroke-width 3)
     #:depends-on (list (visual-dependency 'A) (visual-dependency 'C))
     (lambda (context template)
       (line (visual-position (relation-context-visual-ref context 'A))
             (visual-position (relation-context-visual-ref context 'C))
             #:id (visual-id template)
             #:stroke "steelblue" #:stroke-width 3))))
  (define side-BC
    (relation-visual
     (line (vec2 -1/2 0) (vec2 1/2 0)
           #:id 'side-BC #:stroke "steelblue" #:stroke-width 3)
     #:depends-on (list (visual-dependency 'B) (visual-dependency 'C))
     (lambda (context template)
       (line (visual-position (relation-context-visual-ref context 'B))
             (visual-position (relation-context-visual-ref context 'C))
             #:id (visual-id template)
             #:stroke "steelblue" #:stroke-width 3))))
  (define altitude
    (relation-visual
     (line (vec2 -1/2 0) (vec2 1/2 0)
           #:id 'altitude #:stroke "goldenrod" #:stroke-width 3)
     #:depends-on
     (list (visual-dependency 'A)
           (visual-dependency 'B)
           (visual-dependency 'C))
     (lambda (context template)
       (define current-A (relation-context-visual-ref context 'A))
       (define current-C (relation-context-visual-ref context 'C))
       (line (visual-position current-C)
             (altitude-endpoint current-A current-C)
             #:id (visual-id template)
             #:stroke "goldenrod"
             #:stroke-width 3))))
  (define altitude-label
    (relation-visual
     (plain-text "height" #:id 'height-label #:font-size 1/4
                 #:font-family 'swiss #:color "darkgoldenrod")
     #:phase 'layout
     #:depends-on (list (anchor-dependency 'altitude 'top))
     (lambda (context template)
       (visual-with-position
        template
        (vec2+ (relation-context-anchor-ref context 'altitude 'top)
               (vec2 2/5 1/5))))))
  (define title
    (plain-text "SCENE-EL: immutable relation Visuals"
                #:id 'title #:center (vec2 0 14/5)
                #:font-size 3/10 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define note
    (plain-text "Move C; the semantic altitude and layout label recompute."
                #:id 'note #:center (vec2 0 -12/5)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define initial
    ;; Draw geometric relations before the point markers, so the vertices stay
    ;; crisp at their joins.
    (scene-add (make-scene)
               title note base side-AC side-BC altitude A B C altitude-label))
  (define animated
    (scene-play (scene-wait initial 1)
                (move-to 'C (vec2 -1 3/2))
                #:duration 3))
  (scene-wait animated 1))

(module+ main
  (run-demo "relation-visuals.rkt" make-demo-scene))
