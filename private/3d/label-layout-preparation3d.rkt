#lang racket/base

;;;
;;; Immutable Prepared Label Layout Tables
;;;

(require racket/list "label-layout3d.rkt")

(provide (struct-out prepared-label-layout3d)
         prepare-label-layout3d
         prepared-label-layout3d-ref)

(struct prepared-label-layout3d (frames layouts switch-penalty movement-penalty) #:transparent)

;; Frame data is a list of (cons exact-frame-index items).  Direct layout stays
;; the semantic fallback; preparation freezes only the supplied finite frame
;; grid and is consequently safe for parallel rendering.  For labels present
;; throughout the grid, preparation chooses a deterministic minimum-cost
;; candidate trajectory.  Labels which appear or disappear retain their direct
;; layout in those frames instead of inventing history across a discontinuity.
(define (prepare-label-layout3d frame-data #:width width #:height height
                                #:switch-penalty [switch-penalty 0]
                                #:movement-penalty [movement-penalty 0])
  (unless (and (list? frame-data) (andmap pair? frame-data))
    (raise-argument-error 'prepare-label-layout3d "list of frame/index item pairs" frame-data))
  (unless (and (real? switch-penalty) (>= switch-penalty 0)
               (real? movement-penalty) (>= movement-penalty 0))
    (raise-argument-error 'prepare-label-layout3d "nonnegative penalties" (vector switch-penalty movement-penalty)))
  (define sorted (sort frame-data < #:key car))
  (when (for/or ([earlier (in-list sorted)] [later (in-list (cdr sorted))])
          (= (car earlier) (car later)))
    (raise-arguments-error 'prepare-label-layout3d
                           "distinct frame indexes"
                           "frame-data" frame-data))
  (define direct-layouts
    (for/list ([entry (in-list sorted)])
      (layout-labels3d (cdr entry) #:width width #:height height)))
  (define direct-placement-lists
    (map label-layout3d-placements direct-layouts))
  (define common-ids
    (if (null? direct-placement-lists)
        '()
        (filter
         (lambda (id)
           (for/and ([placements (in-list direct-placement-lists)])
             (member id (map label-layout-candidate3d-item-id placements))))
         (map label-layout-candidate3d-item-id (car direct-placement-lists)))))
  ;; Each vector entry maps a label ID to its prepared selected candidate.
  ;; The vector is mutable only while this constructor builds the final
  ;; immutable layouts; neither the cache nor a renderer observes it.
  (define selections (make-vector (length direct-layouts) #hasheq()))
  (for ([id (in-list common-ids)])
    (define candidate-frames
      (for/list ([layout (in-list direct-layouts)])
        (filter (lambda (candidate) (eq? (label-layout-candidate3d-item-id candidate) id))
                (label-layout3d-candidates layout))))
    (for ([candidate (in-list (best-candidate-trajectory
                               candidate-frames switch-penalty movement-penalty))]
          [index (in-naturals)])
      (vector-set! selections index
                   (hash-set (vector-ref selections index) id candidate))))
  (define prepared-layouts
    (for/list ([layout (in-list direct-layouts)] [selection (in-vector selections)])
      (label-layout3d
       (for/list ([direct (in-list (label-layout3d-placements layout))])
         (hash-ref selection (label-layout-candidate3d-item-id direct) direct))
       (label-layout3d-candidates layout)
       (hasheq 'mode 'prepared
               'item-count (length (label-layout3d-placements layout))
               'viewport (vector width height)
               'switch-penalty switch-penalty
               'movement-penalty movement-penalty))))
  (prepared-label-layout3d
   (vector->immutable-vector (list->vector (map car sorted)))
   (vector->immutable-vector (list->vector prepared-layouts))
   switch-penalty movement-penalty))

(define (prepared-label-layout3d-ref prepared frame)
  (unless (prepared-label-layout3d? prepared)
    (raise-argument-error 'prepared-label-layout3d-ref "prepared-label-layout3d?" prepared))
  (define index (index-of (vector->list (prepared-label-layout3d-frames prepared)) frame))
  (and index (vector-ref (prepared-label-layout3d-layouts prepared) index)))

;; Returns one candidate for each frame. Candidate vectors remain in the
;; source order emitted by `layout-labels3d`, so equal-cost choices resolve
;; without hash or worker-order dependence.
(define (best-candidate-trajectory candidate-frames switch-penalty movement-penalty)
  (cond [(null? candidate-frames) '()]
        [else
         (define initial
           (for/list ([candidate (in-list (car candidate-frames))])
             (cons (label-layout-candidate3d-cost candidate) #f)))
         (define states
           (let loop ([remaining (cdr candidate-frames)]
                      [previous-candidates (car candidate-frames)]
                      [previous-states initial]
                      [reversed-states (list initial)])
             (cond [(null? remaining) (reverse reversed-states)]
                   [else
                    (define candidates (car remaining))
                    (define current
                      (for/list ([candidate (in-list candidates)])
                        (best-predecessor candidate previous-candidates previous-states
                                          switch-penalty movement-penalty)))
                    (loop (cdr remaining) candidates current
                          (cons current reversed-states))])))
         (define final-states (last states))
         (define final-index
           (best-state-index final-states))
         (let loop ([frame-index (sub1 (length candidate-frames))]
                    [candidate-index final-index]
                    [reversed '()])
           (define candidate
             (list-ref (list-ref candidate-frames frame-index) candidate-index))
           (define predecessor (cdr (list-ref (list-ref states frame-index) candidate-index)))
           (define next (cons candidate reversed))
           (if (zero? frame-index)
               next
               (loop (sub1 frame-index) predecessor next)))]))

;; A state is `(cons total-cost predecessor-index)`.  Selecting a predecessor
;; by its original index is the specified final tie-break after equal costs.
(define (best-predecessor candidate previous-candidates previous-states
                          switch-penalty movement-penalty)
  (for/fold ([best #f]) ([previous (in-list previous-candidates)]
                         [state (in-list previous-states)]
                         [index (in-naturals)])
    (define penalty
      (+ (if (eq? (label-layout-candidate3d-direction candidate)
                   (label-layout-candidate3d-direction previous))
             0 switch-penalty)
         (* movement-penalty (candidate-distance candidate previous))))
    (define choice (cons (+ (car state) (label-layout-candidate3d-cost candidate) penalty) index))
    (if (or (not best)
            (< (car choice) (car best))
            (and (= (car choice) (car best)) (< (cdr choice) (cdr best))))
        choice
        best)))

(define (best-state-index states)
  (for/fold ([best-index 0])
            ([state (in-list (cdr states))] [index (in-naturals 1)])
    (if (< (car state) (car (list-ref states best-index)))
        index
        best-index)))

(define (candidate-distance first second)
  (define first-box (label-layout-candidate3d-box first))
  (define second-box (label-layout-candidate3d-box second))
  (define dx
    (- (+ (vector-ref first-box 0) (/ (vector-ref first-box 2) 2))
       (+ (vector-ref second-box 0) (/ (vector-ref second-box 2) 2))))
  (define dy
    (- (+ (vector-ref first-box 1) (/ (vector-ref first-box 3) 2))
       (+ (vector-ref second-box 1) (/ (vector-ref second-box 3) 2))))
  (sqrt (+ (* dx dx) (* dy dy))))
