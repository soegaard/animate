#lang racket/base

;;;
;;; SCENE-T Model Tests
;;;

(require rackunit
         (only-in racket/math pi)
         (only-in racket/list take)
         "../main.rkt")

(module+ test
  (define range
    (axis-range -3 5 1))
  (define line
    (number-line range
                 #:id 'line
                 #:length 8
                 #:end-tip? #t))

  (check-true (number-line-visual? line))
  (check-equal? (number-line-visual-range line) range)
  (check-equal? (number-line-unit-length line) 1)
  (check-equal? (number-line-tick-values line)
                '(-3 -2 -1 0 1 2 3 4 5))
  (check-equal? (number-line-tick-values line #:include-zero? #f)
                '(-3 -2 -1 1 2 3 4 5))
  (check-equal? (number-line-number->point line -3)
                (vec2 -3 0))
  (check-equal? (number-line-number->point line 5)
                (vec2 5 0))
  (check-equal? (number-line-point->number line (vec2 2 7))
                2)
  (check-equal? (number-line-visual-start line)
                (vec2 -3 0))
  (check-equal? (number-line-visual-end line)
                (vec2 5 0))

  (define transformed-line
    (visual-with-scale
     (visual-with-rotation
      (visual-with-position line (vec2 4 -2))
      (/ pi 2))
     (vec2 2 1)))
  (define transformed-point
    (number-line-number->point transformed-line 3))
  (check-= (vec2-x transformed-point) 4 1e-10)
  (check-= (vec2-y transformed-point) 4 1e-10)
  (check-= (number-line-point->number transformed-line transformed-point)
           3
           1e-10)

  (define coordinate-axes
    (axes #:id 'axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -1 1 1)
          #:x-length 4
          #:y-length 2
          #:tick-size 1/5))
  (define grid
    (axes-grid-lines coordinate-axes
                     #:id 'grid))
  (check-true (path-visual? grid))
  (check-equal?
   (length
    (path-geometry-subpaths
     (path-visual-path grid)))
   6)

  (define labels
    (axes-number-labels coordinate-axes
                        #:id-prefix 'coordinate))
  (check-equal? (map visual-id labels)
                '(coordinate-x-0
                  coordinate-x-1
                  coordinate-x-2
                  coordinate-x-3
                  coordinate-y-0
                  coordinate-y-1))
  (check-equal? (map text-visual-content labels)
                '("-2" "-1" "1" "2" "-1" "1"))

  (define labels-with-zero
    (axes-number-labels coordinate-axes
                        #:id-prefix 'with-zero
                        #:include-zero? #t))
  (check-equal? (length labels-with-zero) 7)
  (check-equal? (text-visual-content (list-ref labels-with-zero 2))
                "0")

  (define line-labels
    (number-line-number-labels line
                               #:id-prefix 'line-label))
  (check-equal? (length line-labels) 9)
  (check-equal? (map visual-id (take line-labels 3))
                '(line-label-number-0
                  line-label-number-1
                  line-label-number-2))

  (check-exn exn:fail:contract?
             (lambda ()
               (number-line (axis-range -3 5 1)
                            #:id 'bad
                            #:length 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (axes-number-labels
                coordinate-axes
                #:id-prefix 'bad-label
                #:number->string (lambda (_value) 42))))
  (check-exn exn:fail:contract?
             (lambda ()
               (number-line-number-labels
                line
                #:id-prefix 'bad-label
                #:number->string
                (lambda (_value)
                  (values "a" "b"))))))
