#lang racket/base

;;;
;;; SCENE-CU: Deterministic Traced Cycloid
;;;

(require racket/math
         "../main.rkt" "private/run-demo.rkt")
(provide make-demo-scene)

(define phase (parameter 'phase 0))
(define start-x -3)

(define (cycloid time)
  (vec2 (+ start-x time (- (sin time)))
        (- 1 (cos time))))

(define (make-demo-scene)
  (define wheel
    (derived-visual
     (circle #:id 'wheel #:center (vec2 start-x 1) #:radius 1
             ;; An outline keeps the ground and previously traced cycloid
             ;; visible as the wheel rolls over them.
             #:fill #f #:stroke "royalblue" #:stroke-width 3)
     (lambda (context template)
       (visual-with-position
        template
        (vec2 (+ start-x (derived-context-value-ref context phase)) 1)))))
  (define point
    (derived-visual
     (circle #:id 'point #:center (cycloid 0) #:radius 1/12
             #:fill "crimson" #:stroke "firebrick" #:stroke-width 1)
     (lambda (context template)
       (visual-with-position template
                             (cycloid (derived-context-value-ref context phase))))))
  (define locus
    (traced-path phase
                 (lambda (_context time) (cycloid time))
                 #:id 'locus #:sample-count 181 #:stroke "crimson"
                 #:stroke-width 3))
  (define title
    (plain-text "SCENE-CU: deterministic traced path"
                #:id 'title #:center (vec2 0 16/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "The cycloid is resampled from phase 0 through the current phase."
                #:id 'explanation #:center (vec2 0 13/5)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define ground
    (line (vec2 -17/5 0) (vec2 17/5 0)
          #:id 'ground #:stroke "slategray" #:stroke-width 2))
  (define initial
    (scene-add (scene-set-value (make-scene) phase)
               ground locus wheel point title explanation))
  (scene-wait
   (scene-play initial (value-to phase (* 2 pi)) #:duration 4)
   1))

(module+ main
  (run-demo "traced-cycloid.rkt" make-demo-scene))
