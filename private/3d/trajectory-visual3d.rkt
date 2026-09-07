#lang racket/base

;; Visual lowering of already prepared trajectory data.  Sampling invokes only
;; `ode-trajectory3d-position`, whose prepared branch is dense retained data.

(require racket/list
         "../geometry.rkt" "flow-map3d.rkt" "mesh3d.rkt" "ode-flow3d.rkt"
         "spatial-group.rkt" "tube3d.rkt" "vec3.rkt")

(provide trajectory-samples3d trajectory-tube3d trajectory-ribbon3d trajectory-bundle3d)

(define (trajectory-samples3d trajectory #:count [count 64])
  (unless (prepared-trajectory3d? trajectory)
    (raise-argument-error 'trajectory-samples3d "prepared-trajectory3d?" trajectory))
  (unless (and (exact-integer? count) (>= count 2))
    (raise-argument-error 'trajectory-samples3d "exact integer at least 2 as #:count" count))
  (define range (ode-trajectory3d-time-range trajectory))
  (define start (car range)) (define end (cdr range))
  (vector->immutable-vector
   (list->vector
    (for/list ([index (in-range count)])
      (ode-trajectory3d-position trajectory
                                 (+ start (* (- end start) (/ index (sub1 count)))))))))

(define (trajectory-tube3d trajectory
                           #:id [id 'trajectory-tube]
                           #:radius [radius 1/20]
                           #:sides [sides 12]
                           #:samples [samples 64]
                           #:caps? [caps? #t]
                           #:style [style #f])
  (unless (symbol? id) (raise-argument-error 'trajectory-tube3d "symbol? as #:id" id))
  (define result
    (tube3d (trajectory-samples3d trajectory #:count samples)
            #:id id #:radius radius #:sides sides #:caps? caps?))
  ;; Existing tubes encode material via the ordinary mesh lowering path.  The
  ;; optional style hook is reserved for the future ribbon/bundle API rather
  ;; than being silently ignored.
  (when style (raise-argument-error 'trajectory-tube3d "#f as #:style (not yet supported)" style))
  result)

;; The frame is projected from one tangent to the next, the discrete minimal
;; parallel-transport update.  Closed-loop twist correction is deliberately
;; absent: callers must opt into a closure convention rather than receive one.
(define (trajectory-ribbon3d trajectory
                             #:id [id 'trajectory-ribbon]
                             #:width [width 1/10]
                             #:samples [samples 64]
                             #:initial-normal [initial-normal #f])
  (unless (symbol? id) (raise-argument-error 'trajectory-ribbon3d "symbol? as #:id" id))
  (unless (and (finite-real? width) (positive? width))
    (raise-argument-error 'trajectory-ribbon3d "positive finite real as #:width" width))
  (when initial-normal
    (unless (vec3-finite? initial-normal)
      (raise-argument-error 'trajectory-ribbon3d "#f or finite vec3? as #:initial-normal" initial-normal)))
  (define points (trajectory-samples3d trajectory #:count samples))
  (define tangents
    (for/vector ([i (in-range (vector-length points))])
      (define before (vector-ref points (max 0 (sub1 i))))
      (define after (vector-ref points (min (sub1 (vector-length points)) (add1 i))))
      (vec3-normalize (vec3- after before))))
  (define first-normal (orthogonal-normal (vector-ref tangents 0) initial-normal))
  (define normals
    (let loop ([i 0] [normal first-normal] [reversed '()])
      (if (= i (vector-length points))
          (list->vector (reverse reversed))
          (let* ([tangent (vector-ref tangents i)]
                 [next (orthogonal-normal tangent normal)])
            (loop (add1 i) next (cons next reversed))))))
  (define half (/ width 2))
  (define vertex-list
    (append*
     (for/list ([point (in-vector points)] [normal (in-vector normals)])
       (define offset (vec3-scale half normal))
       (list (vec3+ point offset) (vec3- point offset)))))
  (define vertices (vector->immutable-vector (list->vector vertex-list)))
  (define triangle-list
    (append*
     (for/list ([i (in-range (sub1 (vector-length points)))])
       (define a (* 2 i)) (define b (+ a 1)) (define c (+ a 2)) (define d (+ a 3))
       (list (vector a c b) (vector b c d)))))
  (define triangles (vector->immutable-vector (list->vector triangle-list)))
  (mesh3d #:id id #:vertices vertices #:triangles triangles))

;; A bundle lowers only trajectories retained by a prepared flow map. In
;; particular it never re-prepares a seed and it retains input slot order even
;; when individual trajectories ended at different times.
(define (trajectory-bundle3d map
                             #:id [id 'trajectory-bundle]
                             #:style [style 'tube]
                             #:radius [radius 1/20]
                             #:width [width 1/10]
                             #:sides [sides 12]
                             #:samples [samples 64]
                             #:initial-normal [initial-normal #f])
  (unless (prepared-flow-map3d? map)
    (raise-argument-error 'trajectory-bundle3d "prepared-flow-map3d?" map))
  (unless (symbol? id)
    (raise-argument-error 'trajectory-bundle3d "symbol? as #:id" id))
  (unless (memq style '(tube ribbon))
    (raise-argument-error 'trajectory-bundle3d "'tube or 'ribbon as #:style" style))
  (group3d
   (for/list ([trajectory (in-vector (prepared-flow-map3d-trajectories map))]
              [index (in-naturals)])
     (define child-id (string->symbol (format "trajectory-~a" index)))
     (case style
       [(tube)
        (trajectory-tube3d trajectory #:id child-id #:radius radius
                           #:sides sides #:samples samples)]
       [else
        (trajectory-ribbon3d trajectory #:id child-id #:width width
                             #:samples samples #:initial-normal initial-normal)]))
   #:id id))

(define (orthogonal-normal tangent preferred)
  (define candidate
    (or preferred
        (if (< (abs (vec3-x tangent)) 0.9) (vec3 1 0 0) (vec3 0 1 0))))
  (define projected (vec3- candidate (vec3-scale (vec3-dot candidate tangent) tangent)))
  (if (> (vec3-length projected) 1e-12)
      (vec3-normalize projected)
      (vec3-normalize (vec3-cross tangent (vec3 0 0 1)))))
