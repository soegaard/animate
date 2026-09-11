#lang racket/base
(provide expression-heads action-heads geometry-types)
(define geometry-types '(Point Line Segment Ray Circle Marker Number Angle Side Relation))
(define expression-heads
  '(quote point line segment ray circle marker angle
          perpendicular parallel equal-length equal-angle collinear midpoint-of
          intersection intersections choose point-on
          distance midpoint center length start-point end-point
          angle-first angle-vertex angle-last side-of?
          distinct? noncollinear? on
          + - * / = < > <= >= and or not))
(define action-heads
  '(show hide show-label hide-label deemphasize normalize highlight together expand assert))
