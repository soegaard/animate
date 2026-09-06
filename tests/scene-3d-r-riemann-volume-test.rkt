#lang racket/base

;;; SCENE-3D-R: columns are direct immutable, addressable spatial values.

(require rackunit
         "../3d.rkt")

(module+ test
  (define volume
    (riemann-volume3d (lambda (_x _y) 3)
                      #:x-range '(0 2) #:y-range '(0 3)
                      #:resolution '(2 3) #:base 1 #:id 'volume))
  (check-true (group3d? volume))
  (check-equal? (map spatial-id (group3d-children volume)) '(row-0 row-1))
  (check-equal?
   (map spatial-id (group3d-children (car (group3d-children volume))))
   '(cell-0 cell-1 cell-2))
  (define first-cell (car (group3d-children (car (group3d-children volume)))))
  (check-true (mesh3d? first-cell))
  (check-equal? (transform3-translation (spatial-transform first-cell))
                (vec3 1/2 1/2 2))

  ;; A sampled zero contributes no invented volume but retains its stable path.
  (define zero-volume
    (riemann-volume3d (lambda (_x _y) 0)
                      #:x-range '(0 1) #:y-range '(0 1)
                      #:resolution '(1 1) #:base 0 #:id 'zero))
  (check-true
   (group3d? (car (group3d-children (car (group3d-children zero-volume))))))

  (define washers
    (washer-sum3d (lambda (_x) 2) (lambda (_x) 1)
                    #:x-range '(0 3) #:count 3 #:segments 8 #:id 'washers))
  (check-equal? (map spatial-id (group3d-children washers))
                '(washer-0 washer-1 washer-2))
  (check-true (andmap mesh3d? (group3d-children washers)))

  (define shells
    (shell-sum3d (lambda (_radius) 2)
                  #:radius-range '(0 3) #:count 3 #:segments 8 #:id 'shells))
  (check-equal? (map spatial-id (group3d-children shells))
                '(shell-0 shell-1 shell-2))
  (check-true (andmap mesh3d? (group3d-children shells))))
