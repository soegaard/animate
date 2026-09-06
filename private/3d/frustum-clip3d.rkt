#lang racket/base

;;; Deterministic View-frustum Triangle Clipping

(require racket/list
         "../color-style.rkt"
         "camera3d.rkt"
         "projection3d.rkt"
         "vec3.rkt")

(provide (struct-out clip-vertex3d)
         clip-triangle3d)

;; A clip vertex retains all attributes a later shader may need.  `source` is
;; intentionally opaque provenance (normally original face/index information)
;; and survives generated intersection vertices.
(struct clip-vertex3d (view-position normal color source) #:transparent)

; clip-triangle3d : camera3d? positive-real? clip-vertex3d? clip-vertex3d?
;                   clip-vertex3d? -> (listof (vector/c clip-vertex3d? ...))
;; Clips in stable near, far, left, right, bottom, top order and triangulates
;; each surviving polygon as a stable fan from vertex zero.
(define (clip-triangle3d camera aspect vertex0 vertex1 vertex2)
  (unless (camera3d? camera)
    (raise-argument-error 'clip-triangle3d "camera3d?" camera))
  (unless (and (real? aspect) (positive? aspect))
    (raise-argument-error 'clip-triangle3d "positive finite real?" aspect))
  (for ([vertex (in-list (list vertex0 vertex1 vertex2))])
    (unless (clip-vertex3d? vertex)
      (raise-argument-error 'clip-triangle3d "clip-vertex3d?" vertex)))
  (define clipped
    (for/fold ([polygon (list vertex0 vertex1 vertex2)])
              ([inside-distance (in-list (frustum-distance-functions camera aspect))])
      (clip-polygon polygon inside-distance)))
  (if (< (length clipped) 3)
      '()
      (for/list ([index (in-range 1 (sub1 (length clipped)))])
        (vector (first clipped) (list-ref clipped index) (list-ref clipped (add1 index))))))

(define (frustum-distance-functions camera aspect)
  (define near (camera3d-near camera))
  (define far (camera3d-far camera))
  (define projection (camera3d-projection camera))
  (define depth (lambda (vertex) (- (vec3-z (clip-vertex3d-view-position vertex)))))
  (define depth-planes
    (list (lambda (vertex) (- (depth vertex) near))
          (lambda (vertex) (- far (depth vertex)))))
  (define side-planes
    (cond
      [(perspective-projection3d? projection)
       (define slope
         (tan (/ (perspective-projection3d-vertical-field-of-view projection) 2)))
       (list
        (lambda (vertex)
          (define point (clip-vertex3d-view-position vertex))
          (+ (vec3-x point) (* aspect slope (depth vertex))))
        (lambda (vertex)
          (define point (clip-vertex3d-view-position vertex))
          (- (* aspect slope (depth vertex)) (vec3-x point)))
        (lambda (vertex)
          (define point (clip-vertex3d-view-position vertex))
          (+ (vec3-y point) (* slope (depth vertex))))
        (lambda (vertex)
          (define point (clip-vertex3d-view-position vertex))
          (- (* slope (depth vertex)) (vec3-y point))))]
      [else
       (define half-height (/ (orthographic-projection3d-vertical-size projection) 2))
       (define half-width (* aspect half-height))
       (list
        (lambda (vertex) (+ (vec3-x (clip-vertex3d-view-position vertex)) half-width))
        (lambda (vertex) (- half-width (vec3-x (clip-vertex3d-view-position vertex))))
        (lambda (vertex) (+ (vec3-y (clip-vertex3d-view-position vertex)) half-height))
        (lambda (vertex) (- half-height (vec3-y (clip-vertex3d-view-position vertex)))))]))
  (append depth-planes side-planes))

(define (clip-polygon polygon distance)
  (cond [(null? polygon) '()]
        [else
         (define reversed '())
         (define previous (last polygon))
         (define previous-distance (distance previous))
         (for ([current (in-list polygon)])
           (define current-distance (distance current))
           (define previous-inside? (>= previous-distance 0))
           (define current-inside? (>= current-distance 0))
           (cond
             [(and previous-inside? current-inside?)
              (set! reversed (cons current reversed))]
             [(and previous-inside? (not current-inside?))
              (set! reversed (cons (intersect previous current previous-distance current-distance)
                                   reversed))]
             [(and (not previous-inside?) current-inside?)
              (set! reversed (cons current
                                   (cons (intersect previous current previous-distance current-distance)
                                         reversed)))])
           (set! previous current)
           (set! previous-distance current-distance))
         (reverse reversed)]))

(define (intersect first second first-distance second-distance)
  (define progress (/ first-distance (- first-distance second-distance)))
  (clip-vertex3d
   (vec3-lerp (clip-vertex3d-view-position first)
              (clip-vertex3d-view-position second)
              progress)
   (vec3-lerp (clip-vertex3d-normal first)
              (clip-vertex3d-normal second)
              progress)
   (rgba-color-lerp (clip-vertex3d-color first)
                     (clip-vertex3d-color second)
                     progress)
   (clip-vertex3d-source first)))
