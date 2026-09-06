#lang racket/base

;;;
;;; Deterministic, Stateless Projected Label Layout
;;;

(require racket/list
         "../geometry.rkt"
         "label-placement3d.rkt")

(provide (struct-out label-layout-item3d)
         (struct-out label-layout-candidate3d)
         (struct-out label-layout3d)
         layout-labels3d)

;; anchors and boxes are measured pixels, with y increasing downward as in an
;; output framebuffer.  Keeping this module in pixels makes it independent of
;; the visual and renderer representations.
(struct label-layout-item3d (id anchor width height priority placement) #:transparent)
(struct label-layout-candidate3d (item-id direction box leader? cost) #:transparent)
(struct label-layout3d (placements candidates diagnostics) #:transparent)

(define direction-order '(north north-east east south-east south south-west west north-west))

(define (layout-labels3d items #:width width #:height height)
  (unless (and (list? items) (andmap label-layout-item3d? items))
    (raise-argument-error 'layout-labels3d "list of label-layout-item3d?" items))
  (unless (and (positive? width) (positive? height))
    (raise-argument-error 'layout-labels3d "positive viewport width and height" (vector width height)))
  ;; Priority is author-visible.  Equal priorities intentionally preserve the
  ;; source/declaration order of `items`; only an impossible same-source slot
  ;; would consult the ID.  This avoids a label moving merely because an author
  ;; renames an unrelated sibling.
  (define sorted
    (map cdr
         (sort (for/list ([item (in-list items)] [source-index (in-naturals)])
                 (cons source-index item))
               (lambda (first second)
                 (define first-item (cdr first))
                 (define second-item (cdr second))
                 (or (> (label-layout-item3d-priority first-item)
                        (label-layout-item3d-priority second-item))
                     (and (= (label-layout-item3d-priority first-item)
                             (label-layout-item3d-priority second-item))
                          (or (< (car first) (car second))
                              (and (= (car first) (car second))
                                   (symbol<? (label-layout-item3d-id first-item)
                                             (label-layout-item3d-id second-item))))))))))
  (define placed '())
  (define candidates '())
  (for ([item (in-list sorted)])
    (validate-item item)
    (define choices (item-candidates item width height placed))
    ;; `item-candidates` emits the declared preferred directions first. Fold
    ;; instead of sorting so an exact cost tie retains that documented order.
    (define selected
      (for/fold ([best (car choices)]) ([candidate (in-list (cdr choices))])
        (if (< (label-layout-candidate3d-cost candidate)
               (label-layout-candidate3d-cost best))
            candidate
            best)))
    (set! candidates (append candidates choices))
    (set! placed (append placed (list selected))))
  (label-layout3d placed candidates
                  (hasheq 'mode 'direct 'item-count (length items)
                          'viewport (vector width height))))

(define (validate-item item)
  (unless (symbol? (label-layout-item3d-id item))
    (raise-argument-error 'label-layout-item3d "symbol? id" (label-layout-item3d-id item)))
  (unless (and (vector? (label-layout-item3d-anchor item)) (= (vector-length (label-layout-item3d-anchor item)) 2)
               (andmap finite-real? (vector->list (label-layout-item3d-anchor item)))
               (finite-real? (label-layout-item3d-width item)) (positive? (label-layout-item3d-width item))
               (finite-real? (label-layout-item3d-height item)) (positive? (label-layout-item3d-height item))
               (exact-integer? (label-layout-item3d-priority item))
               (label-placement3d? (label-layout-item3d-placement item)))
    (raise-argument-error 'label-layouts3d "valid immutable label layout item" item)))

(define (item-candidates item width height placed)
  (define placement (label-layout-item3d-placement item))
  (define selected-directions
    (take (append (label-placement3d-preferred placement)
                  (filter (lambda (direction) (not (memq direction (label-placement3d-preferred placement))))
                          direction-order))
          (label-placement3d-candidates placement)))
  (for/list ([direction (in-list selected-directions)] [order (in-naturals)])
    (define box (candidate-box item direction))
    (define overflow (box-overflow box width height))
    (define overlap
      (if (label-placement3d-avoid-overlap? placement)
          (for/sum ([other (in-list placed)]) (box-overlap box (label-layout-candidate3d-box other)))
          0))
    (define leader? (> (label-placement3d-distance placement) (label-placement3d-leader-threshold placement)))
    (label-layout-candidate3d
     (label-layout-item3d-id item) direction box leader?
     (+ (* 1000 overlap)
        (if (label-placement3d-keep-inside? placement) (* 10000 overflow) 0)
        order))))

(define (candidate-box item direction)
  (define anchor (label-layout-item3d-anchor item))
  (define distance (label-placement3d-distance (label-layout-item3d-placement item)))
  (define delta (direction-vector direction))
  (define width (label-layout-item3d-width item)) (define height (label-layout-item3d-height item))
  (define center-x (+ (vector-ref anchor 0) (* distance (vector-ref delta 0))))
  (define center-y (+ (vector-ref anchor 1) (* distance (vector-ref delta 1))))
  (vector (- center-x (/ width 2)) (- center-y (/ height 2)) width height))

(define (direction-vector direction)
  (case direction
    [(north) (vector 0 -1)] [(north-east) (vector 1 -1)] [(east) (vector 1 0)]
    [(south-east) (vector 1 1)] [(south) (vector 0 1)] [(south-west) (vector -1 1)]
    [(west) (vector -1 0)] [else (vector -1 -1)]))

(define (box-overflow box width height)
  (+ (max 0 (- (vector-ref box 0)))
     (max 0 (- (vector-ref box 1)))
     (max 0 (- (+ (vector-ref box 0) (vector-ref box 2)) width))
     (max 0 (- (+ (vector-ref box 1) (vector-ref box 3)) height))))
(define (box-overlap first second)
  (define x (max 0 (- (min (+ (vector-ref first 0) (vector-ref first 2))
                             (+ (vector-ref second 0) (vector-ref second 2)))
                      (max (vector-ref first 0) (vector-ref second 0)))))
  (define y (max 0 (- (min (+ (vector-ref first 1) (vector-ref first 3))
                             (+ (vector-ref second 1) (vector-ref second 3)))
                      (max (vector-ref first 1) (vector-ref second 1)))))
  (* x y))
