#lang racket/base

;;;
;;; SCENE-DV Layout Finishing Tests
;;;

(require rackunit "../main.rkt")

(define (overlap? a b)
  (and (< (layout-box-left a) (layout-box-right b))
       (< (layout-box-left b) (layout-box-right a))
       (< (layout-box-bottom a) (layout-box-top b))
       (< (layout-box-bottom b) (layout-box-top a))))

(module+ test
  (define first-visual (plain-text "x" #:id 'first #:center (vec2 -1 1)
                                   #:vertical-alignment 'baseline))
  (define second-visual (plain-text "y" #:id 'second #:center (vec2 1 -1)
                                    #:vertical-alignment 'baseline))
  (define aligned (align-baselines (list first-visual second-visual)))
  (check-equal? (vec2-y (visual-position (car aligned)))
                (vec2-y (visual-position (cadr aligned))))

  (define camera (make-camera #:width 600 #:height 400 #:world-width 6))
  (define outside (circle #:id 'outside #:center (vec2 8 0) #:radius 1))
  (define fitted (keep-inside-frame outside #:camera camera #:margin 1/5))
  (define fitted-box (visual-layout-box fitted #:camera camera))
  (check-true (<= (layout-box-right fitted-box) 14/5))
  (check-true (>= (layout-box-left fitted-box) -14/5))

  (define cards
    (list (rectangle #:id 'one #:center origin #:width 1 #:height 1)
          (rectangle #:id 'two #:center origin #:width 1 #:height 1)
          (rectangle #:id 'three #:center origin #:width 1 #:height 1)))
  (define separated (avoid-overlap cards #:gap 1/4))
  (for* ([left (in-list separated)] [right (in-list separated)]
         #:when (string<? (symbol->string (visual-id left))
                          (symbol->string (visual-id right))))
    (check-false (overlap? (visual-layout-box left) (visual-layout-box right))))

  (define distributed (distribute-within cards -3 3))
  (check-equal? (map (lambda (visual) (vec2-x (visual-position visual))) distributed)
                '(-3 0 3))
  (define vertical (distribute-within cards -2 2 #:axis 'vertical))
  (check-equal? (map (lambda (visual) (vec2-y (visual-position visual))) vertical)
                '(-2 0 2)))
