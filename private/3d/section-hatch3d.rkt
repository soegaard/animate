#lang racket/base

;;;
;;; Deterministic Section Hatching
;;;

;; Hatching works entirely in the deterministic plane basis carried by a
;; section.  Each hatch line uses even/odd crossings across every closed loop;
;; consequently nested section loops naturally leave holes unhatched.

(require racket/list
         racket/math
         "../geometry.rkt"
         "clipping3d.rkt"
         "curve3d.rkt"
         "plane-basis3d.rkt"
         "ray-plane.rkt"
         "spatial-group.rkt"
         "stroke3d.rkt"
         "vec3.rkt")

(provide section-hatch3d)

; section-hatch3d : section3d? ... -> group3d?
;; Produces screen/world-stroke hatching in a plane-local angle.  Open chains
;; do not define fillable interiors and are deliberately ignored.
(define (section-hatch3d section
                         #:angle [angle (/ pi 4)]
                         #:spacing [spacing 3/20]
                         #:style [style (stroke3d #:color "goldenrod" #:width 1)]
                         #:offset [offset 1e-5]
                         #:id [id 'section-hatch])
  (unless (section3d? section)
    (raise-argument-error 'section-hatch3d "section3d?" section))
  (unless (finite-real? angle)
    (raise-argument-error 'section-hatch3d "finite real angle" angle))
  (unless (and (finite-real? spacing) (positive? spacing))
    (raise-argument-error 'section-hatch3d "positive finite spacing" spacing))
  (unless (stroke3d? style)
    (raise-argument-error 'section-hatch3d "stroke3d?" style))
  (unless (finite-real? offset)
    (raise-argument-error 'section-hatch3d "finite real offset" offset))
  (unless (symbol? id)
    (raise-argument-error 'section-hatch3d "symbol?" id))
  (define loops (section3d-loops section))
  (define basis (section3d-basis section))
  (define coordinate-loops
    (for/list ([loop (in-list loops)])
      (for/list ([point (in-list loop)]) (plane-basis3d-project basis point))))
  (define direction (vector (cos angle) (sin angle)))
  (define perpendicular (vector (- (vector-ref direction 1)) (vector-ref direction 0)))
  (define all-coordinates (apply append coordinate-loops))
  (define normal-offset
    (vec3-scale offset (plane3-normal (section3d-plane section))))
  (define curves
    (cond [(null? all-coordinates) '()]
          [else
           (define min-line
             (apply min (map (lambda (point) (dot2 perpendicular point)) all-coordinates)))
           (define max-line
             (apply max (map (lambda (point) (dot2 perpendicular point)) all-coordinates)))
           (for/fold ([reversed '()])
                     ([line-index (in-range (inexact->exact (ceiling (/ min-line spacing)))
                                             (add1 (inexact->exact (floor (/ max-line spacing)))) )])
             (define line (* line-index spacing))
             (define crossings
               (sort (deduplicate-scalars
                      (apply append
                             (for/list ([loop (in-list coordinate-loops)])
                               (line-crossings loop line perpendicular direction))) )
                     <))
             (define segments (crossing-pairs crossings))
             (for/fold ([inside reversed]) ([segment (in-list segments)] [segment-index (in-naturals)])
               (define start (car segment))
               (define end (cdr segment))
               (if (<= (abs (- end start)) 1e-10)
                   inside
                   (let* ([start-point
                           (vec3+ normal-offset
                                  (plane-basis3d-unproject basis
                                                           (add2 (scale2 direction start)
                                                                 (scale2 perpendicular line))))]
                          [end-point
                           (vec3+ normal-offset
                                  (plane-basis3d-unproject basis
                                                           (add2 (scale2 direction end)
                                                                 (scale2 perpendicular line))))])
                     (cons (polyline3d (list start-point end-point)
                                       #:id (string->symbol
                                             (format "~a-~a-~a" id line-index segment-index))
                                       #:style style)
                           inside)))))]))
  (group3d (reverse curves) #:id id))

(define (line-crossings coordinates line perpendicular direction)
  ;; A half-open crossing convention counts a vertex once even when the hatch
  ;; happens to meet it exactly.  It is therefore deterministic under a fixed
  ;; section basis and avoids zero-length double intervals.
  (cond [(null? coordinates) '()]
        [else
         (let loop ([remaining coordinates]
                    [point-a (last coordinates)]
                    [crossings '()])
           (cond [(null? remaining) crossings]
                 [else
                  (define point-b (car remaining))
                  (define line-a (dot2 perpendicular point-a))
                  (define line-b (dot2 perpendicular point-b))
                  (define next-crossings
                    (if (or (and (<= line-a line) (< line line-b))
                            (and (<= line-b line) (< line line-a)))
                        (let* ([progress (/ (- line line-a) (- line-b line-a))]
                               [point (add2 point-a
                                            (scale2 (sub2 point-b point-a) progress))])
                          (cons (dot2 direction point) crossings))
                        crossings))
                  (loop (cdr remaining) point-b next-crossings)]))]))

(define (crossing-pairs crossings)
  (let loop ([remaining crossings] [reversed '()])
    (cond [(or (null? remaining) (null? (cdr remaining))) (reverse reversed)]
          [else (loop (cddr remaining) (cons (cons (car remaining) (cadr remaining)) reversed))])))

(define (deduplicate-scalars values)
  (for/fold ([reversed '()]) ([value (in-list (sort values <))])
    (if (and (pair? reversed) (<= (abs (- value (car reversed))) 1e-10))
        reversed
        (cons value reversed))))

(define (dot2 vector-a vector-b)
  (+ (* (vector-ref vector-a 0) (vector-ref vector-b 0))
     (* (vector-ref vector-a 1) (vector-ref vector-b 1))))
(define (add2 vector-a vector-b)
  (vector (+ (vector-ref vector-a 0) (vector-ref vector-b 0))
          (+ (vector-ref vector-a 1) (vector-ref vector-b 1))))
(define (sub2 vector-a vector-b)
  (vector (- (vector-ref vector-a 0) (vector-ref vector-b 0))
          (- (vector-ref vector-a 1) (vector-ref vector-b 1))))
(define (scale2 vector2 scalar)
  (vector (* scalar (vector-ref vector2 0)) (* scalar (vector-ref vector2 1))))
