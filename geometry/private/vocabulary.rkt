#lang racket/base
(provide expression-heads action-heads geometry-types)
(define geometry-types '(Point Line Segment Ray Circle Marker Number))
(define expression-heads
  '(quote point line segment ray circle marker angle perpendicular equal-length equal-angle
          intersection intersections choose point-on
          distance midpoint center length distinct? noncollinear? on
          + - * / = < > <= >= and or not))
(define action-heads
  '(show hide show-label hide-label deemphasize normalize highlight together expand))
