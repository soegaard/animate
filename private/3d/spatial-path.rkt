#lang racket/base

;;;
;;; Spatial Paths
;;;

;; Implements stable symbol paths through the spatial-container protocol.  The
;; functions here do not mention scenes or 2D Visual traversal: a view3d calls
;; them explicitly after consuming its own outer root symbol.


;;;
;;; Imports and Exports
;;;

(require "spatial-group.rkt"
         "spatial-visual.rkt")

(provide spatial-path?
         spatial-relative-ref
         spatial-relative-replace
         spatial-relative-insert-after)


;;;
;;; Path Validation
;;;

; spatial-path? : any/c -> boolean?
;;   Reports whether value is a nonempty list of symbolic path components.
(define (spatial-path? value)
  (and (list? value)
       (pair? value)
       (andmap symbol? value)))

(define (check-spatial-path who path)
  (unless (spatial-path? path)
    (raise-argument-error who "nonempty list of symbols" path)))


;;;
;;; Lookup
;;;

; spatial-relative-ref : spatial-container? spatial-path? -> spatial-visual?
;;   Looks up a nonempty path below container without treating it as a 2D tree.
(define (spatial-relative-ref container path)
  (unless (spatial-container? container)
    (raise-argument-error 'spatial-relative-ref "spatial-container?" container))
  (check-spatial-path 'spatial-relative-ref path)
  (let loop ([current container] [remaining path])
    (define child
      (child-by-id current (car remaining) 'spatial-relative-ref path))
    (cond [(null? (cdr remaining)) child]
          [(spatial-container? child)
           (loop child (cdr remaining))]
          [else
           (raise-arguments-error
            'spatial-relative-ref
            "an intermediate spatial path entry naming a spatial container"
            "spatial-path" path
            "spatial-visual" child)])))


;;;
;;; Immutable Replacement
;;;

; spatial-relative-replace : spatial-container? spatial-path? spatial-visual?
;                            -> spatial-container?
;;   Rebuilds the container ancestry with one stable-ID spatial child replaced.
(define (spatial-relative-replace container path replacement)
  (unless (spatial-container? container)
    (raise-argument-error 'spatial-relative-replace "spatial-container?" container))
  (check-spatial-path 'spatial-relative-replace path)
  (unless (spatial-visual? replacement)
    (raise-argument-error 'spatial-relative-replace "spatial-visual?" replacement))
  (replace-under-container container path replacement path))

; spatial-relative-insert-after : spatial-container? spatial-path?
;                                 spatial-visual? -> spatial-container?
;; Inserts `addition` as the next direct sibling of the descendant at `path`.
;; The original target and all of its stable path components are unchanged.
(define (spatial-relative-insert-after container path addition)
  (unless (spatial-container? container)
    (raise-argument-error 'spatial-relative-insert-after "spatial-container?" container))
  (check-spatial-path 'spatial-relative-insert-after path)
  (unless (spatial-visual? addition)
    (raise-argument-error 'spatial-relative-insert-after "spatial-visual?" addition))
  (insert-after-under-container container path addition path))

(define (replace-under-container container remaining replacement full-path)
  (define target-id (car remaining))
  (define found? #f)
  (define children
    (for/list ([entry (in-list (spatial-child-entries container))])
      (define child (spatial-child-visual entry))
      (cond
        [(not (eq? (spatial-child-id entry) target-id)) child]
        [else
         (set! found? #t)
         (cond
           [(null? (cdr remaining))
            (unless (eq? (spatial-id replacement) target-id)
              (raise-arguments-error
               'spatial-relative-replace
               "a replacement preserving the spatial ID"
               "expected-spatial-id" target-id
               "replacement-spatial-id" (spatial-id replacement)))
            replacement]
           [(not (spatial-container? child))
            (raise-arguments-error
             'spatial-relative-replace
             "an intermediate spatial path entry naming a spatial container"
             "spatial-path" full-path
             "spatial-visual" child)]
           [else
            (replace-under-container child (cdr remaining)
                                     replacement full-path)])])))
  (unless found?
    (raise-arguments-error
     'spatial-relative-replace
     "a spatial path present in the container"
     "spatial-path" full-path
     "missing-spatial-id" target-id))
  (spatial-container-with-children container children))

(define (insert-after-under-container container remaining addition full-path)
  (define target-id (car remaining))
  (define found? #f)
  (define children
    (apply append
           (for/list ([entry (in-list (spatial-child-entries container))])
             (define child (spatial-child-visual entry))
             (cond
               [(not (eq? (spatial-child-id entry) target-id))
                (list child)]
               [else
                (set! found? #t)
                (cond
                  [(null? (cdr remaining))
                   (list child addition)]
                  [(not (spatial-container? child))
                   (raise-arguments-error
                    'spatial-relative-insert-after
                    "an intermediate spatial path entry naming a spatial container"
                    "spatial-path" full-path
                    "spatial-visual" child)]
                  [else
                   (list (insert-after-under-container child (cdr remaining)
                                                       addition full-path))])]))))
  (unless found?
    (raise-arguments-error
     'spatial-relative-insert-after
     "a spatial path present in the container"
     "spatial-path" full-path
     "missing-spatial-id" target-id))
  ;; `spatial-container-with-children` centrally validates duplicate sibling
  ;; identities, including an accidental collision with `addition`.
  (spatial-container-with-children container children))

(define (child-by-id container id who full-path)
  (define result
    (for/first ([entry (in-list (spatial-child-entries container))]
                #:when (eq? (spatial-child-id entry) id))
      (spatial-child-visual entry)))
  (unless result
    (raise-arguments-error
     who
     "a spatial path present in the container"
     "spatial-path" full-path
     "missing-spatial-id" id))
  result)
