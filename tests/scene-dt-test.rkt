#lang racket/base

;;;
;;; SCENE-DT Probability and Statistical Diagram Tests
;;;

(require rackunit "../main.rkt")

(module+ test
  (define bars (bar-chart '(2 5 3) #:id 'chart #:labels '("A" "B" "C")))
  (check-true (group-visual? bars))
  (check-equal? (bar-chart-bar-path 'chart 2) '(chart bars bar-2))
  (check-true (rectangle-visual? (scene-ref (scene-add (make-scene) bars) '(chart bars bar-2))))

  (define hist (histogram '(0 0 1 2 3 3 3) #:id 'hist #:bins 4))
  (check-true (group-visual? hist))

  (define stacked (stacked-bar-chart '((2 1) (1 3)) #:id 'stacked))
  (check-true (rectangle-visual? (scene-ref (scene-add (make-scene) stacked)
                                               '(stacked bars bar-2 segment-2))))
  (check-equal? (stacked-bar-segment-path 'stacked 1 2) '(stacked bars bar-1 segment-2))

  (define space (sample-space '((1/4 1/4) (1/4 1/4)) #:id 'space))
  (check-true (group-visual? space))
  (check-equal? (sample-space-cell-path 'space 2 1) '(space cells cell-2-1))

  (define tree
    (probability-tree
     (list (probability-branch 'heads "H" 1/2
                               (list (probability-branch 'hh "H" 1/2 '())
                                     (probability-branch 'ht "T" 1/2 '())))
           (probability-branch 'tails "T" 1/2 '()))
     #:id 'tree))
  (check-true (group-visual? tree))
  (check-true (group-visual? (scene-ref (scene-add (make-scene) tree) '(tree nodes hh))))
  (check-equal? (probability-tree-node-path 'tree 'tails) '(tree nodes tails))

  (define summary (box-plot-summary 1 2 3 4 5))
  (check-equal? (box-plot-summary-median summary) 3)
  (check-true (group-visual? (box-plot '(1 2 3 4 5 9) #:id 'box)))

  (define errors
    (error-bars (list (error-bar-point -1 2 1/2) (error-bar-point 1 3 1)) #:id 'errors))
  (check-true (group-visual? errors))
  (check-true (group-visual? (scene-ref (scene-add (make-scene) errors) '(errors bars bar-1))))
  (check-equal? (error-bar-path 'errors 2) '(errors bars bar-2))

  (check-exn exn:fail:contract? (lambda () (bar-chart '() #:id 'empty)))
  (check-exn exn:fail:contract? (lambda () (histogram '(1 2) #:id 'bad #:bins 0))))
