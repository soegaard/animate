#lang racket/base

;;;
;;; SCENE-DJ Shape Catalogue Tests
;;;

(require rackunit
         racket/file
         racket/list
         (only-in racket/math pi)
         "../main.rkt"
         "../render.rkt")

(define (approximately=? first second [tolerance 1e-8])
  (<= (abs (- first second)) tolerance))

(define (approximately-point=? first second)
  (and (approximately=? (vec2-x first) (vec2-x second))
       (approximately=? (vec2-y first) (vec2-y second))))

(module+ test
  (define oval
    (ellipse #:id 'oval #:center (vec2 -4 1)
             #:width 4 #:height 2 #:fill "aliceblue"))
  (check-true (path-visual? oval))
  (check-equal? (length (path-subpath-segments
                         (car (path-geometry-subpaths (path-visual-path oval)))))
                4)

  (define ring
    (annulus #:id 'ring #:center (vec2 -2 1)
             #:inner-radius 1/3 #:outer-radius 1))
  (check-equal? (length (path-geometry-subpaths (path-visual-path ring))) 2)

  (define wedge
    (sector #:id 'wedge #:center (vec2 0 1)
            #:radius 1 #:angle (/ pi 2)))
  (check-true (path-subpath-closed?
               (car (path-geometry-subpaths (path-visual-path wedge)))))

  (define hexagon
    (regular-polygon #:id 'hexagon #:center (vec2 2 1) #:sides 6 #:radius 1))
  (check-equal? (length (path-subpath-segments
                         (car (path-geometry-subpaths (path-visual-path hexagon)))))
                5)

  (define five-star
    (star #:id 'five-star #:center (vec2 4 1) #:points 5
          #:outer-radius 1 #:inner-radius 1/2))
  (check-equal? (length (path-subpath-segments
                         (car (path-geometry-subpaths (path-visual-path five-star)))))
                9)

  (define rounded
    (rounded-rectangle #:id 'rounded #:center (vec2 -3 -2)
                       #:width 3 #:height 2 #:corner-radius 1/3))
  (check-true (path-visual? rounded))
  (define rounded-subpath
    (car (path-geometry-subpaths (path-visual-path rounded))))
  (define rounded-segments (path-subpath-segments rounded-subpath))
  ;; Four straight sides alternate with four quarter-circle Bézier corners.
  ;; In particular, preserving the top edge ensures the first corner starts
  ;; at the top-right rather than skewing across the whole width.
  (check-equal? (length rounded-segments) 8)
  (for ([index '(0 2 4 6)])
    (check-true (line-path-segment? (list-ref rounded-segments index))))
  (for ([index '(1 3 5 7)])
    (check-true (cubic-bezier-path-segment? (list-ref rounded-segments index))))
  (check-true
   (approximately-point=? (path-subpath-start rounded-subpath)
                          (vec2 -7/6 1)))
  (check-true
   (approximately-point=?
    (line-path-segment-end (car rounded-segments))
    (vec2 7/6 1)))
  (check-true
   (approximately-point=?
    (line-path-segment-end (list-ref rounded-segments 2))
    (vec2 3/2 -2/3)))
  (check-true
   (approximately-point=?
    (line-path-segment-end (list-ref rounded-segments 6))
    (vec2 -3/2 2/3)))

  (define arc
    (arc-between-points (vec2 -1 -2) (vec2 1 -2)
                        #:id 'arc #:angle (/ pi 2)))
  (define arc-subpath (car (path-geometry-subpaths (path-visual-path arc))))
  (define arc-local-end (last (path-subpath-points arc-subpath)))
  (define arc-world-end
    (affine-transform-apply-point (visual-transform arc) arc-local-end))
  (check-true (approximately-point=? arc-world-end (vec2 1 -2)))

  (define curved
    (curved-arrow (vec2 -4 -4) (vec2 -2 -4)
                  #:id 'curved #:angle (- (/ pi 2))))
  (check-true (group-visual? curved))
  (check-equal? (map visual-id (group-visual-children curved))
                '(curved-shaft curved-tip))

  (define both-way
    (double-arrow (vec2 0 -4) (vec2 2 -4) #:id 'both-way))
  (check-true (arrow-visual-start-tip? both-way))
  (check-true (arrow-visual-end-tip? both-way))

  (define marked
    (labeled-point "P" #:id 'marked #:center (vec2 4 -4)))
  (check-true (group-visual? marked))
  (check-equal? (map visual-id (group-visual-children marked))
                '(marked-dot marked-label))

  (check-exn exn:fail:contract?
             (lambda () (annulus #:id 'bad #:inner-radius 2 #:outer-radius 1)))
  (check-exn exn:fail:contract?
             (lambda () (star #:id 'bad #:points 1)))
  (check-exn exn:fail:contract?
             (lambda () (arc-between-points origin origin #:id 'bad)))

  (define output-directory
    (make-temporary-file "animate-scene-dj-~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     ;; One real frame verifies that odd-even annulus fill, cubic corners,
     ;; curved-arrow tip, and the group catalogue all select the standard Pict
     ;; renderer without adding a special backend.
     (define scene
       (scene-wait
        (scene-add (make-scene)
                   oval ring wedge hexagon five-star rounded arc curved both-way marked)
        1))
     (define paths (render-frames! scene output-directory #:fps 1))
     (check-equal? (length paths) 1)
     (check-true (file-exists? (car paths))))
   (lambda ()
     (delete-directory/files output-directory))))
