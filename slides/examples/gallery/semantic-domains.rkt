#lang racket/base

;; This example intentionally uses the existing domain plans as witnesses.
;; There is no string-to-glyph matching and no second geometry evaluator.
(require "../../main.rkt" "../../math.rkt" "../../geometry.rkt"
         (only-in "../math-lesson.rkt" plan)
         (only-in "../../../geometry/examples/equilateral-triangle.rkt" equilateral-triangle))
(provide gallery-entry-shots)
(define equation (math-content plan))
(define construction (geometry-content equilateral-triangle))
;; Step 1 reveals the two given points. Starting at its endpoint keeps the
;; gallery's held source slide visually informative while the bridge still
;; replays the rest of the authored construction timeline.
(define geometry-visible-start '(1 end))
(define (math-at at) (content-state equation #:at at #:viewport '(12 7)))
(define (geometry-at at) (content-state construction #:at at #:viewport '(12 7)))
(define (combined final?)
  (semantic-group #:width 16 #:height 8
    (semantic-part 'equation
                   (math-at (if final? '(evaluate-rhs end) '(subtract-five start)))
                   #:x (if final? 8.2 0) #:y 0 #:width 7.8 #:height 6.7)
    (semantic-part 'construction
                   (geometry-at (if final? 'end geometry-visible-start))
                   #:x (if final? 0 8.2) #:y 0 #:width 7.8 #:height 6.7)
    (semantic-part 'caption "One bridge; two independent domain plans."
                   #:x 0 #:y 7 #:width 16 #:height 0.8 #:fit 'natural)))
(define (gallery-entry-shots id theme fmt)
  (define-values (title old new duration)
    (case id
      [(semantic-math)
       (values "Keep the algebra, change the layout"
               (math-at '(subtract-five start)) (math-at '(evaluate-rhs end)) 4)]
      [(semantic-geometry)
       (values "Keep the construction, change the layout"
               (geometry-at geometry-visible-start) (geometry-at 'end) 6)]
      [(semantic-math-geometry)
       (values "Semantic continuity across layouts" (combined #f) (combined #t) 6)]
      [else (raise-argument-error 'gallery-entry-shots "semantic gallery entry" id)]))
  (define before
    (slide #:layout 'title+figure [title title] [figure #:key 'work old]))
  (define after
    (if (eq? id 'semantic-math-geometry)
        (slide #:layout 'figure+caption [figure #:key 'work new]
               [caption "The math planner owns the algebra; the construction owns its geometry."])
        (slide #:layout 'title+figure [title title]
               [body (if (eq? id 'semantic-math)
                         "Subtract five on both sides. Cancel the opposites. Evaluate the right side."
                         "The original construction timeline controls points, circles, labels, and segments.")]
               [figure #:key 'work new])))
  (list
   (storyboard-shot (string->symbol (format "~a-before" id)) (hold-slide before #:duration 2))
   (slide-transition #:effect 'match #:keys '(work) #:depth 'semantic
                     #:duration duration #:easing 'smooth)
   (storyboard-shot (string->symbol (format "~a-after" id)) (hold-slide after #:duration 3))))
