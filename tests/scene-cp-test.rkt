#lang racket/base
(require "../experimental.rkt")

;;;
;;; SCENE-CP Coordinate-System and Calculus Helper Tests
;;;

(require rackunit
         "../main.rkt")

(define (point-close? actual expected [tolerance 1e-8])
  (and (<= (abs (- (vec2-x actual) (vec2-x expected))) tolerance)
       (<= (abs (- (vec2-y actual) (vec2-y expected))) tolerance)))

(module+ test
  (define coordinate-axes
    (axes #:id 'axes
          #:x-range (axis-range -2 2 1)
          #:y-range (axis-range -1 5 1)
          #:x-length 8 #:y-length 6 #:x-tip? #f #:y-tip? #f))
  (define (square x) (* x x))

  ;; Helpers are built on the existing numeric-to-world conversion rather than
  ;; assuming a unit or untransformed coordinate system.
  (check-equal? (graph-point coordinate-axes square 1) (vec2 2 1))
  (define labelled
    (graph-label coordinate-axes square 1 "P" #:id 'P #:offset (vec2 1/5 2/5)))
  (check-equal? (visual-position labelled) (vec2 11/5 7/5))
  (define vertical
    (vertical-line-to-graph coordinate-axes square 1 #:id 'vertical))
  (check-equal? (visual-position vertical) (vec2 2 1/2))
  (define horizontal
    (horizontal-line-to-graph coordinate-axes square 1 #:id 'horizontal))
  (check-equal? (visual-position horizontal) (vec2 1 1))

  ;; Tangent/secant helpers return ordinary finite path Visuals. The secant's
  ;; midpoint follows graph points exactly, while its slope group has stable
  ;; nested names for later attention or animation requests.
  (define tangent
    (tangent-line coordinate-axes square 1 #:id 'tangent #:dx 1/100 #:length 2))
  (check-true (point-close? (visual-position tangent) (vec2 2 1)))
  (define secant
    (secant-line coordinate-axes square 1 1 #:id 'secant))
  (check-equal? (visual-position secant) (vec2 3 5/2))
  (define slope-group
    (secant-slope-group coordinate-axes square 1 1 #:id 'slope))
  (check-true (group-visual? slope-group))
  (check-equal?
   (map visual-id (group-visual-children slope-group))
   '(slope-secant slope-delta-x slope-delta-y slope-first-point
                  slope-second-point slope-delta-x-label slope-delta-y-label))

  ;; The calculus-area helpers create closed semantic paths in axes-local
  ;; coordinates and preserve the axes affine transform on the result.
  (define under
    (area-under-graph coordinate-axes square #:id 'under #:x-min -1 #:x-max 1
                      #:sample-count 5))
  (check-true (path-subpath-closed?
               (car (path-geometry-subpaths (path-visual-path under)))))
  (check-equal? (visual-position under) origin)
  (define between
    (area-between-curves coordinate-axes square (lambda (_x) 1)
                         #:id 'between #:x-min -1 #:x-max 1 #:sample-count 5))
  (check-true (path-subpath-closed?
               (car (path-geometry-subpaths (path-visual-path between)))))
  (define rectangles
    (riemann-rectangles coordinate-axes square #:id 'rectangles
                        #:x-min 0 #:x-max 2 #:count 4))
  (check-equal? (length (path-geometry-subpaths (path-visual-path rectangles))) 4)
  (check-true (andmap path-subpath-closed?
                       (path-geometry-subpaths (path-visual-path rectangles))))

  ;; Parameter-driven calculus scenes remain functional: a derived group simply
  ;; rebuilds a static secant construction for its sampled h value.
  (define h (parameter 'h 1))
  (define live-secant
    (derived-visual
     (secant-slope-group coordinate-axes square 1 1 #:id 'live)
     (lambda (context _template)
       (secant-slope-group coordinate-axes square 1
                           (derived-context-value-ref context h)
                           #:id 'live))))
  (define animated
    (scene-play
     (scene-add (scene-set-value (make-scene) h) live-secant)
     (value-to h 1/5)
     #:duration 2))
  (check-equal? (visual-id (scene-visual-at animated 'live 1)) 'live)

  (check-exn exn:fail:contract?
             (lambda () (graph-point coordinate-axes square +inf.0)))
  (check-exn exn:fail:contract?
             (lambda () (secant-line coordinate-axes square 1 0 #:id 'bad)))
  (check-exn exn:fail:contract?
             (lambda () (riemann-rectangles coordinate-axes square #:id 'bad #:count 0))))
