#lang racket/base

;;;
;;; SCENE-DL: Serializable Rate Functions
;;;

;; Each dot uses a named, transparent rate-function value through the ordinary
;; timed API. The values remain callable for motion and are also safe inputs to
;; an authored-timeline automatic cache key.

(require racket/list
         animate
         "private/run-demo.rkt")

(provide make-demo-scene)

(define (make-demo-scene)
  (define title
    (plain-text "SCENE-DL: serializable rate functions"
                #:id 'title #:center (vec2 0 17/5)
                #:font-size 1/3 #:font-family 'swiss #:font-weight 'bold
                #:color "navy"))
  (define explanation
    (plain-text "Named easings remain cacheable while custom procedures stay available."
                #:id 'explanation #:center (vec2 0 3)
                #:font-size 1/5 #:font-family 'swiss #:color "darkslategray"))
  (define rows
    (list (list 'linear "linear" 9/5 "steelblue" linear)
          (list 'smooth "smooth" 3/5 "forestgreen" (smooth))
          (list 'rush "rush into" -3/5 "darkorange" (rush-into))
          (list 'pause "there and back + pause" -9/5 "purple"
                (there-and-back-with-pause #:pause-ratio 1/3))))
  (define labels
    (for/list ([row (in-list rows)])
      (plain-text (second row)
                  #:id (string->symbol (format "~a-label" (first row)))
                  #:center (vec2 -23/5 (third row))
                  #:font-size 1/4 #:font-family 'swiss #:color "dimgray")))
  (define guides
    (for/list ([row (in-list rows)])
      (line (vec2 -7/2 (third row)) (vec2 7/2 (third row))
            #:id (string->symbol (format "~a-guide" (first row)))
            #:stroke "lightgray" #:stroke-width 1)))
  (define dots
    (for/list ([row (in-list rows)])
      (circle #:id (string->symbol (format "~a-dot" (first row)))
              #:radius 1/4 #:center (vec2 -7/2 (third row))
              #:fill (fourth row) #:stroke "white" #:stroke-width 1)))
  (define initial
    (scene-wait
     (apply scene-add
            (append (list (make-scene) title explanation) labels guides dots))
     1))
  (define requests
    (for/list ([row (in-list rows)])
      (timed
       (move-to (string->symbol (format "~a-dot" (first row)))
                (vec2 7/2 (third row)))
       #:duration 3 #:easing (fifth row))))
  (scene-wait
   (keyword-apply scene-play '(#:duration) (list 3) (cons initial requests))
   2))

(module+ main
  (run-demo "serializable-rate-functions.rkt" make-demo-scene))
