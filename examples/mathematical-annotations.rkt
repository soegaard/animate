#lang racket/base

;;;
;;; SCENE-CO: Mathematical Annotation Geometry
;;;

;; The annotation group is a pure derived Visual. It reconstructs ordinary
;; path-backed marks from the sampled vertex positions, so a moving right
;; triangle keeps its right-angle square, angle arc, base brace, and label in
;; the appropriate geometric relationship.

(require "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-CO: mathematical annotations"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 2/5 #:font-weight 'bold #:color "navy"))
  (define explanation
    (plain-text "Angle, right-angle, brace, label, and live enclosure"
                #:id 'explanation #:center (vec2 0 14/5)
                #:font-size 1/5 #:color "darkslategray"))
  (define A
    (circle #:id 'A #:center (vec2 -2 -3/2) #:radius 1/6
            #:fill "royalblue" #:stroke "navy" #:stroke-width 2))
  (define B
    (circle #:id 'B #:center (vec2 2 -3/2) #:radius 1/6
            #:fill "royalblue" #:stroke "navy" #:stroke-width 2))
  (define C
    (circle #:id 'C #:center (vec2 -2 3/2) #:radius 1/6
            #:fill "royalblue" #:stroke "navy" #:stroke-width 2))
  (define AB (segment-between 'A 'B #:id 'AB #:stroke "steelblue" #:stroke-width 4))
  (define BC (segment-between 'B 'C #:id 'BC #:stroke "steelblue" #:stroke-width 4))
  (define CA (segment-between 'C 'A #:id 'CA #:stroke "steelblue" #:stroke-width 4))
  (define (label text id target)
    (attach-to
     (plain-text text #:id id #:center origin
                 #:font-size 1/4 #:color "navy")
     target #:target-anchor 'top #:self-anchor 'bottom #:offset (vec2 0 1/8)))
  (define annotations
    (derived-visual
     (group '() #:id 'annotations)
     (lambda (context _template)
       (define a (visual-position (derived-context-visual-ref context 'A)))
       (define b (visual-position (derived-context-visual-ref context 'B)))
       (define c (visual-position (derived-context-visual-ref context 'C)))
       (group
        (list
         (right-angle b a c #:id 'right-mark #:size 2/5
                      #:stroke "crimson" #:stroke-width 3)
         (angle a c b #:id 'angle-mark #:radius 1/2
                #:stroke "darkorange" #:stroke-width 3)
         (brace-label a b "base" #:id 'base-brace #:offset -1/2 #:gap 1/6
                      #:font-size 1/4 #:color "darkgreen"
                      #:stroke "darkgreen" #:stroke-width 3))
        #:id 'annotations))))
  ;; `surrounding-rectangle` measures a nested path emitted by the derived
  ;; group, so it follows the changing angle mark without path bookkeeping.
  (define angle-outline
    (surrounding-rectangle '(annotations angle-mark)
                           #:id 'angle-outline #:padding 1/10
                           #:stroke "goldenrod" #:stroke-width 2))
  (define initial
    (scene-add (make-scene)
               AB BC CA A B C
               (label "A" 'A-label 'A)
               (label "B" 'B-label 'B)
               (label "C" 'C-label 'C)
               annotations angle-outline title explanation))
  (scene-wait
   (scene-play initial
               (move-to 'B (vec2 5/2 -1))
               (move-to 'C (vec2 -2 2))
               #:duration 3)
   1))

(module+ main
  (run-demo "mathematical-annotations.rkt" make-demo-scene))
