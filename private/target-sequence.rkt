#lang racket/base

;;;
;;; Deferred scene target queries
;;;

;; A target sequence describes a query, not a collection captured during
;; authoring. Scene compilation resolves it against an immutable local scene
;; state exactly once and returns target references with separate source and
;; scheduled indexes.

(require racket/list
         "formula-parts-visual.rkt"
         "formula-style.rkt"
         "group-visual.rkt"
         "scene-state.rkt"
         "visual-model.rkt"
         "visual-selection.rkt")

(provide target-sequence?
         concrete-targets
         concrete-targets?
         children-of
         children-of?
         descendants-of
         descendants-of?
         selection-targets
         selection-targets?
         formula-part-targets
         formula-part-targets?
         target-ref
         target-ref?
         target-ref-path
         target-ref-value
         target-ref-source-index
         target-ref-scheduled-index
         target-ref-root
         target-ref-selection-data
         target-ref-source-range
         target-ref-origin
         target-ref-with-scheduled-index
         resolve-target-sequence)

(struct concrete-targets-value (values) #:transparent)
(struct children-of-value (parent) #:transparent)
(struct descendants-of-value (root selector) #:transparent)
(struct selection-targets-value (selection) #:transparent)
(struct formula-part-targets-value (formula selections) #:transparent)

(define (target-sequence? value)
  (or (concrete-targets-value? value)
      (children-of-value? value)
      (descendants-of-value? value)
      (selection-targets-value? value)
      (formula-part-targets-value? value)))

(define concrete-targets? concrete-targets-value?)
(define children-of? children-of-value?)
(define descendants-of? descendants-of-value?)
(define selection-targets? selection-targets-value?)
(define formula-part-targets? formula-part-targets-value?)

;; A reference retains the frozen resolved visual value where one is available.
;; `scheduled-index` starts as #f and is filled only after the order policy is
;; resolved, so source order never changes when visual scheduling is reversed.
(struct target-ref
  (path value source-index scheduled-index root selection-data source-range origin)
  #:transparent)

(define (concrete-targets values)
  (unless (or (list? values) (vector? values))
    (raise-argument-error 'concrete-targets "list? or vector?" values))
  (concrete-targets-value
   (vector->immutable-vector
    (if (vector? values) values (list->vector values)))))

(define (children-of parent)
  (unless (target-address? parent)
    (raise-argument-error 'children-of "Visual, symbol, or visual-path?" parent))
  (children-of-value parent))

(define (descendants-of root #:where [selector #f])
  (unless (target-address? root)
    (raise-argument-error 'descendants-of "Visual, symbol, or visual-path?" root))
  (unless (or (not selector) (procedure? selector))
    (raise-argument-error 'descendants-of "#f or procedure? as #:where" selector))
  (descendants-of-value root selector))

(define (selection-targets selection)
  (unless (visual-selection? selection)
    (raise-argument-error 'selection-targets "visual-selection?" selection))
  (selection-targets-value selection))

(define (formula-part-targets formula selections)
  (unless (formula-assembly-visual? formula)
    (raise-argument-error 'formula-part-targets "formula-assembly-visual?" formula))
  (unless (or (list? selections) (vector? selections))
    (raise-argument-error 'formula-part-targets "list? or vector?" selections))
  (formula-part-targets-value
   formula
   (vector->immutable-vector
    (if (vector? selections) selections (list->vector selections)))))

(define (target-address? value)
  (or (visual? value) (symbol? value) (visual-path? value)))

(define (target-path value who)
  (visual-target-path value who))

(define (target-ref-with-scheduled-index reference index)
  (unless (target-ref? reference)
    (raise-argument-error 'target-ref-with-scheduled-index "target-ref?" reference))
  (unless (exact-nonnegative-integer? index)
    (raise-argument-error 'target-ref-with-scheduled-index
                          "exact nonnegative integer" index))
  (struct-copy target-ref reference [scheduled-index index]))

(define (resolve-target-sequence sequence local-state [origin #f])
  (unless (target-sequence? sequence)
    (raise-argument-error 'resolve-target-sequence "target-sequence?" sequence))
  (unless (scene-state? local-state)
    (raise-argument-error 'resolve-target-sequence "scene-state?" local-state))
  (define (make-reference path source-index
                          #:value [value #f]
                          #:root [root #f]
                          #:selection-data [selection-data #f]
                          #:source-range [source-range #f])
    (target-ref path
                (or value
                    (with-handlers ([exn:fail? (lambda (_ignored) #f)])
                      (scene-state-ref local-state path)))
                source-index #f root selection-data source-range origin))
  (define resolved
    (cond
      [(concrete-targets-value? sequence)
       (for/list ([value (in-vector (concrete-targets-value-values sequence))]
                  [source-index (in-naturals)])
         (define path
           (cond [(target-address? value) (target-path value 'concrete-targets)]
                 [else #f]))
         (make-reference path source-index #:value value))]
      [(children-of-value? sequence)
       (define parent-path (target-path (children-of-value-parent sequence) 'children-of))
       (define parent (scene-state-ref local-state parent-path))
       (unless (group-visual? parent)
         (raise-arguments-error 'resolve-target-sequence
                                "a composite Visual for children-of"
                                "target-sequence" sequence
                                "path" parent-path
                                "actual" parent))
       (for/list ([child (in-list (group-visual-children parent))]
                  [source-index (in-naturals)])
         (make-reference (append parent-path (list (visual-id child))) source-index
                         #:value child #:root parent-path))]
      [(descendants-of-value? sequence)
       (define root-path (target-path (descendants-of-value-root sequence) 'descendants-of))
       (define root (scene-state-ref local-state root-path))
       (define selector (descendants-of-value-selector sequence))
       (define (walk visual path)
         (append
          (if (or (not selector) (selector visual)) (list (cons path visual)) '())
          (if (group-visual? visual)
              (append-map
               (lambda (child)
                 (walk child (append path (list (visual-id child)))))
               (group-visual-children visual))
              '())))
       (for/list ([entry (in-list (walk root root-path))]
                  [source-index (in-naturals)])
         (make-reference (car entry) source-index #:value (cdr entry)
                         #:root root-path))]
      [(selection-targets-value? sequence)
       (define selection (selection-targets-value-selection sequence))
       (for/list ([path (in-list (visual-selection-absolute-paths selection))]
                  [source-index (in-naturals)])
         (make-reference path source-index #:root (visual-selection-root selection)
                         #:selection-data selection))]
      [else
       (define formula (formula-part-targets-value-formula sequence))
       (define root-path (list (visual-id formula)))
       ;; A formula selection can denote several leaves. Each leaf is a
       ;; distinct mapped target while retaining the originating semantic
       ;; selection; silently choosing the first leaf loses author intent.
       (define selected-paths
         (append*
          (for/list ([selection
                      (in-vector (formula-part-targets-value-selections sequence))])
            (define paths
              (cond
                [(symbol? selection)
                 (define selected (formula-select formula selection))
                 (cond [(visual-selection? selected)
                        (visual-selection-absolute-paths selected)]
                       [(visual-path? selected) (list selected)]
                       [else
                        (raise-arguments-error
                         'resolve-target-sequence
                         "a formula selector producing a visual selection or path"
                         "selection" selection
                         "result" selected)])]
                [(visual-selection? selection)
                 (unless (equal? (visual-selection-root selection) root-path)
                   (raise-arguments-error
                    'resolve-target-sequence
                    "a formula selection rooted at the supplied formula"
                    "formula-root" root-path
                    "selection-root" (visual-selection-root selection)))
                 (visual-selection-absolute-paths selection)]
                [(visual-path? selection) (list selection)]
                [else
                 (raise-argument-error
                  'resolve-target-sequence
                  "formula part symbol, visual selection, or visual path"
                  selection)]))
            (unless (pair? paths)
              (raise-arguments-error
               'resolve-target-sequence
               "a nonempty formula selection"
               "selection" selection))
            (for/list ([path (in-list paths)])
              (cons path selection)))))
       (for/list ([entry (in-list selected-paths)]
                  [source-index (in-naturals)])
         (make-reference (car entry) source-index #:root root-path
                         #:selection-data (cdr entry)))]))
  (vector->immutable-vector (list->vector resolved)))
