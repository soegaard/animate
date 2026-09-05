#lang racket/base

;;;
;;; SCENE-CQ: Adaptive Plotting
;;;

;; The two panels use the same adaptive sampler for complementary cases. The
;; reciprocal samples a division-by-zero pole as a gap; the sine curve starts
;; with a sparse grid and receives extra midpoint samples where it bends.

(require animate "private/run-demo.rkt")
(provide make-demo-scene)

(define (make-demo-scene)
  (define reciprocal-axes
    (axes #:id 'reciprocal-axes #:center (vec2 -2 -1/2)
          #:x-range (axis-range -2 2 1) #:y-range (axis-range -3 3 1)
          #:x-length 7/2 #:y-length 7/2 #:stroke "slategray" #:stroke-width 2
          #:x-tip? #f #:y-tip? #f #:tick-size 1/10))
  (define oscillation-axes
    (axes #:id 'oscillation-axes #:center (vec2 2 -1/2)
          #:x-range (axis-range -1 1 1) #:y-range (axis-range -6/5 6/5 1/5)
          #:x-length 7/2 #:y-length 7/2 #:stroke "slategray" #:stroke-width 2
          #:x-tip? #f #:y-tip? #f #:tick-size 1/10))
  (define reciprocal
    (adaptive-function-graph
     reciprocal-axes (lambda (x) (/ 1 x)) #:id 'reciprocal
     #:x-min -2 #:x-max 2 #:initial-sample-count 17
     #:max-deviation 1/100 #:max-depth 10
     #:stroke "crimson" #:stroke-width 3))
  (define oscillation
    (adaptive-function-graph
     oscillation-axes (lambda (x) (sin (* 30 x))) #:id 'oscillation
     #:x-min -1 #:x-max 1 #:initial-sample-count 17
     ;; This high-frequency stress case needs a finer display-space tolerance
     ;; than the reciprocal: it adds samples around every crest and trough
     ;; rather than leaving them as visibly pointed line joins.
     #:max-deviation 1/1000 #:max-depth 10
     #:stroke "royalblue" #:stroke-width 3))
  (define pole-guide
    (dashed-line (axes-coordinates->point reciprocal-axes 0 -3)
                 (axes-coordinates->point reciprocal-axes 0 3)
                 #:id 'pole-guide #:dash-length 1/10 #:gap-length 1/10
                 #:stroke "darkorange" #:stroke-width 2))
  (define title
    (plain-text "SCENE-CQ: adaptive plotting"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 2/5 #:font-weight 'bold #:color "navy"))
  (define explanation
    (plain-text "Refine where the curve bends; leave a true gap at a pole."
                #:id 'explanation #:center (vec2 0 14/5)
                #:font-size 1/5 #:color "darkslategray"))
  (define reciprocal-label
    (plain-text "1/x — discontinuity-aware"
                #:id 'reciprocal-label #:center (vec2 -2 8/5)
                #:font-size 1/5 #:color "crimson"))
  (define oscillation-label
    (plain-text "sin(30x) — curvature refinement"
                #:id 'oscillation-label #:center (vec2 2 8/5)
                #:font-size 1/5 #:color "royalblue"))
  (scene-wait
   (scene-play (make-scene)
               (animation-group (fade-in reciprocal-axes)
                                (fade-in oscillation-axes)
                                (fade-in pole-guide)
                                (create reciprocal)
                                (create oscillation)
                                (fade-in title)
                                (fade-in explanation)
                                (fade-in reciprocal-label)
                                (fade-in oscillation-label))
               #:duration 3)
   1))

(module+ main
  (run-demo "adaptive-plotting.rkt" make-demo-scene))
