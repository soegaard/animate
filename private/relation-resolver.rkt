#lang racket/base

;;;
;;; Relation Dependency Inspection
;;;

;; Static validation complements scene-state's on-demand runtime resolver. It
;; does not resolve a relation or run its closure; it validates the declarative
;; graph authors can inspect before rendering.

(require racket/list
         "affine-map-visual.rkt"
         "parameter.rkt"
         "relation-dependency.rkt"
         "relation-visual.rkt"
         "scene-state.rkt"
         "visual-model.rkt"
         "visual-selection.rkt")

(provide scene-relation-dependency-graph
         scene-validate-relations
         (struct-out relation-resolution-report)
         scene-relation-report)

;; A report is static, inspectable relation metadata for one sampled scene
;; definition. `order` is its deterministic drawing-order index. Runtime
;; context accesses are separately checked while a resolver runs; this report
;; intentionally does not execute arbitrary author code merely to inspect it.
(struct relation-resolution-report
  (path order phase structure dependencies cacheability warnings)
  #:transparent)

;; scene-relation-dependency-graph : scene-state? -> immutable-hash?
;; Maps every complete relation Visual path to its ordered declared dependency
;; descriptions. Paths—not terminal symbols—are the graph identity.
(define (scene-relation-dependency-graph state)
  (unless (scene-state? state)
    (raise-argument-error
     'scene-relation-dependency-graph "scene-state?" state))
  (make-immutable-hash
   (for/list ([entry (in-list (scene-relation-entries state))])
     (cons (car entry) (relation-visual-dependencies (cdr entry))))))

;; scene-validate-relations : scene-state? -> immutable-hash?
;; Checks that every declared target exists and that explicit relation-to-
;; relation edges are acyclic. Returns the same inspectable graph on success.
(define (scene-validate-relations state)
  (unless (scene-state? state)
    (raise-argument-error 'scene-validate-relations "scene-state?" state))
  (define entries (scene-relation-entries state))
  (for ([entry (in-list entries)])
    (define relation-path (car entry))
    (for ([dependency
           (in-list (relation-visual-dependencies (cdr entry)))])
      (validate-dependency state relation-path dependency)))
  (define graph (scene-relation-dependency-graph state))
  (define relation-paths (map car entries))
  (define edges
    (for/hash ([path (in-list relation-paths)])
      (values
       path
       (filter (lambda (target) (member target relation-paths))
               (dependency-visual-target-paths (hash-ref graph path))))))
  (define cycle (first-relation-cycle relation-paths edges))
  (when cycle
    (raise-arguments-error
     'scene-validate-relations
     "an acyclic relation dependency graph"
     "relation dependency cycle" cycle))
  graph)

;; scene-relation-report : scene-state?
;;                         [(or/c false/c visual? symbol? visual-path?)]
;;                      -> (or/c relation-resolution-report?
;;                               (listof relation-resolution-report?))
;; Returns reports in semantic drawing order, or one report when `target` is
;; supplied. Validation runs first so an inspector never displays a plausible
;; graph for a scene with a missing dependency or an explicit cycle.
(define (scene-relation-report state [target #f])
  (unless (scene-state? state)
    (raise-argument-error 'scene-relation-report "scene-state?" state))
  (scene-validate-relations state)
  (define reports
    (for/list ([entry (in-list (scene-relation-entries state))]
               [order (in-naturals)])
      (define path (car entry))
      (define relation (cdr entry))
      (define cacheability (relation-visual-cacheability relation))
      (relation-resolution-report
       path
       order
       (relation-visual-phase relation)
       (relation-visual-structure relation)
       (relation-visual-dependencies relation)
       cacheability
       (case cacheability
         [(disabled)
          (list "generic relation resolver has no persistent cache key")]
         [else '()]))))
  (if target
      (let ([path (visual-target-path target 'scene-relation-report)])
        (or (for/first ([report (in-list reports)]
                        #:when (equal? (relation-resolution-report-path report)
                                       path))
              report)
            (raise-arguments-error
             'scene-relation-report
             "a relation Visual path present in the scene"
             "visual-path" path)))
      reports))

(define (scene-relation-entries state)
  (append*
   (for/list ([root (in-list (scene-state-visuals-in-drawing-order state))])
     (walk-visual (list (visual-id root)) root))))

(define (walk-visual path visual)
  (cond
    [(relation-visual? visual)
     (list (cons path visual))]
    [(affine-map-visual? visual)
     ;; An affine-map wrapper is transparent in Animate's semantic path model.
     (walk-visual path (affine-map-visual-content visual))]
    [(visual-container? visual)
     (append*
      (for/list ([child (in-list (visual-child-entries visual))])
        (walk-visual (append path (list (visual-child-id child)))
                     (visual-child-visual child))))]
    [else '()]))

(define (validate-dependency state relation-path dependency)
  (cond
    [(value-dependency? dependency)
     (define id
       (parameter-target-id
        (value-dependency-target dependency)
        'scene-validate-relations))
     (unless (scene-state-value-has? state id)
       (raise-arguments-error
        'scene-validate-relations
        "a declared relation value dependency present in the scene"
        "relation path" relation-path
        "dependency" dependency
        "missing value" id))]
    [(visual-dependency? dependency)
     (validate-visual-target
      state relation-path dependency (visual-dependency-target dependency))]
    [(anchor-dependency? dependency)
     ;; Anchor geometry is measured only in EL-4, but the Visual target itself
     ;; is already a semantic dependency and can be diagnosed now.
     (validate-visual-target
      state relation-path dependency (anchor-dependency-target dependency))]
    [(selection-dependency? dependency)
     (for ([path (in-list
                  (visual-selection-absolute-paths
                   (selection-dependency-selection dependency)))])
       (validate-visual-target state relation-path dependency path))]
    [else
     ;; relation-visual validates descriptor construction, so this protects
     ;; callers of the private inspection helper against future variants.
     (raise-arguments-error
      'scene-validate-relations
      "relation-dependency?"
      "relation path" relation-path
      "dependency" dependency)]))

(define (validate-visual-target state relation-path dependency target)
  (unless (scene-state-has? state target)
    (raise-arguments-error
     'scene-validate-relations
     "a declared relation Visual dependency present in the scene"
     "relation path" relation-path
     "dependency" dependency
     "missing Visual path"
     (visual-target-path target 'scene-validate-relations))))

(define (dependency-visual-target-paths dependencies)
  (append*
   (for/list ([dependency (in-list dependencies)])
     (cond
       [(visual-dependency? dependency)
        (list (visual-target-path
               (visual-dependency-target dependency)
               'scene-validate-relations))]
       [(anchor-dependency? dependency)
        (list (visual-target-path
               (anchor-dependency-target dependency)
               'scene-validate-relations))]
       [(selection-dependency? dependency)
        (visual-selection-absolute-paths
         (selection-dependency-selection dependency))]
       [else '()]))))

;; first-relation-cycle : (listof visual-path?) hash? -> (or/c false/c list?)
;; A DFS in scene drawing order gives stable full-path cycle reports.
(define (first-relation-cycle nodes edges)
  (define active '())
  (define complete (make-hash))
  (define found #f)
  (define (visit path)
    (cond
      [found (void)]
      [(member path active)
       (define tail (member path active))
       (set! found (append tail (list path)))]
      [(hash-has-key? complete path) (void)]
      [else
       (set! active (append active (list path)))
       (for ([next (in-list (hash-ref edges path '()))])
         (visit next))
       (set! active (drop-right active 1))
       (hash-set! complete path #t)]))
  (for ([node (in-list nodes)]) (visit node))
  found)
