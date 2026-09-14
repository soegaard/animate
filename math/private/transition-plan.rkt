#lang racket/base

;;;
;;; Semantic Transition Units
;;;

;; Partitions prepared ink using checked occurrence links and typed rewrite events.
;; Pixel dimensions never determine mathematical identity. This pure planner owns
;; correspondence only; native animate owns timing and frame sampling.

;;;
;;; Imports and Exports
;;;

(require racket/list
         racket/match
         "datum.rkt"
         "model.rkt"
         "typeset-model.rkt")

(provide transition-kind
         plan-token-transition
         (struct-out token-match)
         (struct-out token-transition)
         transition-atomic-paths
         tokens-at-path
         token-center)

;;;
;;; Transition Records
;;;

(struct token-match (source target unit kind) #:transparent)
;; token-match records one witnessed ink correspondence, not a string guess.
;;  - source  exact-nonnegative-integer?  index in the ordered source tokens.
;;  - target  exact-nonnegative-integer?  index in the ordered destination tokens.
;;  - unit  operand-path?  destination semantic unit; its ink moves rigidly.
;;  - kind  symbol?  preserve, copy, or container witness.

(struct token-transition (kind matches outgoing incoming atomic-sources atomic-targets)
  #:transparent)
;; token-transition partitions all input and output ink exactly once per view.
;;  - kind  symbol?  introduction, cancellation, replacement, split, or reorder.
;;  - matches  (listof token-match?)  destination order; copies may reuse a source.
;;  - outgoing  (listof exact-nonnegative-integer?)  unmatched source ink in order.
;;  - incoming  (listof exact-nonnegative-integer?)  unmatched destination ink in order.
;;  - atomic-sources  (listof operand-path?)  indivisible outgoing rewrite scopes.
;;  - atomic-targets  (listof operand-path?)  indivisible incoming rewrite scopes.

;;;
;;; Semantic Classification
;;;

; effective-rule : rewrite-step? -> symbol?
;;   Unwraps each-branch metadata without depending on lesson-specific step names.
(define (effective-rule step)
  (if (eq? (rewrite-step-rule step) 'each-branch)
      (cdr (or (assq 'operation (rewrite-step-details step))
               (cons 'operation 'each-branch)))
      (rewrite-step-rule step)))

; transition-kind : rewrite-step? -> symbol?
;;   Chooses behavior from mathematical events before considering rule convenience names.
(define (transition-kind step)
  (define kinds (map trace-relation-kind (rewrite-step-trace step)))
  (cond
    [(memq 'split kinds) 'split]
    [(memq 'reorder kinds) 'reorder]
    [(or (memq 'cancel kinds) (eq? (effective-rule step) 'remove-unit)) 'cancellation]
    [(eq? (effective-rule step) 'both-sides) 'introduction]
    [(and (memq 'copy kinds)
          (not (ormap (lambda (k) (memq k '(evaluate rewrite specialize merge classify))) kinds)))
     'copy]
    [else 'replacement]))

; occurrence-paths : math? (listof symbol?) -> (listof operand-path?)
;;   Resolves event identities in numerical operand traversal order.
(define (occurrence-paths state ids)
  (for/list ([p (in-list (datum-paths (math-datum state)))]
             #:when (member (occurrence-id (math-occurrence-at state p)) ids))
    p))

; minimal-paths : (listof operand-path?) -> (listof operand-path?)
;;   Removes redundant descendant scopes while retaining declared order.
(define (minimal-paths paths)
  (define distinct (remove-duplicates paths equal?))
  (filter (lambda (p)
            (not (ormap (lambda (q) (and (not (equal? p q)) (path-prefix? q p)))
                        distinct)))
          distinct))

; nearest-additive-ancestor : math? operand-path? -> (or/c operand-path? #f)
;;   Finds the selected additive expression whose signed terms own one reordered occurrence.
(define (nearest-additive-ancestor state path)
  (for/first ([n (in-range (length path) -1 -1)]
              #:do [(define candidate (take path n))
                    (define d (datum-ref (math-datum state) candidate))]
              #:when (memq (head d) '(+ -)))
    candidate))

; reorder-focus-paths : rewrite-step? -> (listof operand-path?)
;;   Collapses source term-level reorder evidence to the exact additive focus locations.
(define (reorder-focus-paths step)
  (define before (rewrite-step-before step))
  (define relations
    (filter (lambda (r) (eq? (trace-relation-kind r) 'reorder))
            (rewrite-step-trace step)))
  (minimal-paths
   (filter values
           (append-map
            (lambda (r)
              (for/list ([p (in-list (occurrence-paths before (trace-relation-sources r)))])
                (nearest-additive-ancestor before p)))
            relations))))

; scopes-cover-relation-operands? : math? (listof operand-path?) -> boolean?
;;   Reports whether atomic replacement scopes cover both operands of one root relation.
(define (scopes-cover-relation-operands? state scopes)
  (and (relation? (math-datum state))
       (for/and ([operand-path (in-list '((0) (1)))])
         (ormap (lambda (scope) (path-prefix? scope operand-path)) scopes))))

; transition-atomic-paths : rewrite-step? -> (values list? list?)
;;   Blocks fine matching inside evaluation, opaque rewrites, and conservative reorders.
(define (transition-atomic-paths step)
  (define kind (transition-kind step))
  (define events
    (filter (lambda (r) (memq (trace-relation-kind r)
                              '(evaluate rewrite abbreviate specialize merge classify)))
            (rewrite-step-trace step)))
  (define before (rewrite-step-before step))
  (define after (rewrite-step-after step))
  (cond
    [(eq? kind 'replacement)
     (define source-scopes
       (minimal-paths
        (append-map (lambda (r) (occurrence-paths before (trace-relation-sources r))) events)))
     (define target-scopes
       (minimal-paths
        (append-map (lambda (r) (occurrence-paths after (trace-relation-targets r))) events)))
     ;; If both sides of a relation are being replaced, preserving only the
     ;; relation glyph would create a transient bare `=`/`<`/etc.  Treat the
     ;; complete assertion as the atomic presentation unit instead.
     (if (and (equal? (head (math-datum before)) (head (math-datum after)))
              (scopes-cover-relation-operands? before source-scopes)
              (scopes-cover-relation-operands? after target-scopes))
         (values '(()) '(()))
         (values source-scopes target-scopes))]
    [(eq? kind 'reorder)
     ;; Reordering preserves the selected focus location. Native term motion is
     ;; not guaranteed collision-free, so that additive focus is atomic on both
     ;; sides while surrounding equation/fraction structure remains matchable.
     (define focuses (reorder-focus-paths step))
     (values focuses focuses)]
    [(eq? kind 'split)
     ;; A root value in a newly created radical is not a free-standing moving
     ;; digit. Copy the shared left sides; introduce each complete RHS together.
     (define targets
       (append-map
         (lambda (r) (occurrence-paths after (trace-relation-targets r)))
         (filter (lambda (r) (eq? (trace-relation-kind r) 'split))
                 (rewrite-step-trace step))))
     (values '()
             (for/list ([p (in-list targets)]
                        #:when (relation? (datum-ref (math-datum after) p)))
               (append p '(1))))]
    [else (values '() '())]))

; tokens-at-path : (listof prepared-token?) operand-path? -> (listof exact-nonnegative-integer?)
;;   Collects complete owned subexpression ink, including contextual delimiters.
(define (tokens-at-path tokens path)
  (for/list ([t (in-list tokens)] [i (in-naturals)]
             #:when (path-prefix? path (prepared-token-path t)))
    i))

; token-center : (listof prepared-token?) -> (values real? real?)
;;   Uses the union box center to translate an entire semantic unit rigidly.
(define (token-center tokens)
  (if (null? tokens)
      (values 0 0)
      (values
        (/ (+ (apply min (map (lambda (t) (- (prepared-token-x t) (/ (prepared-token-width t) 2))) tokens))
              (apply max (map (lambda (t) (+ (prepared-token-x t) (/ (prepared-token-width t) 2))) tokens))) 2)
        (/ (+ (apply min (map (lambda (t) (- (prepared-token-y t) (/ (prepared-token-height t) 2))) tokens))
              (apply max (map (lambda (t) (+ (prepared-token-y t) (/ (prepared-token-height t) 2))) tokens))) 2))))

;;;
;;; Witnessed Ink Matching
;;;

; blocked? : operand-path? (listof operand-path?) -> boolean?
;;   Reports whether ink belongs to an indivisible replacement scope.
(define (blocked? path scopes)
  (ormap (lambda (p) (path-prefix? p path)) scopes))

; compatible-ink? : prepared-token? prepared-token? math? math? -> boolean?
;;   Requires the same owned role and notation; crop quantization is not identity.
(define (compatible-ink? source target before after)
  (and (eq? (prepared-token-role source) (prepared-token-role target))
       (if (eq? (prepared-token-role source) 'structure)
           ;; Residual ink (a fraction bar or radical) belongs to its operator,
           ;; not to the complete source substring containing all its children.
           (equal? (head (datum-ref (math-datum before) (prepared-token-path source)))
                   (head (datum-ref (math-datum after) (prepared-token-path target))))
           (string=? (prepared-token-text source) (prepared-token-text target)))))

; enclosing-unit : rewrite-step? operand-path? operand-path? -> operand-path?
;;   Finds the largest exact subtree witness containing this source/target pair.
(define (enclosing-unit step source target)
  (define before (math-datum (rewrite-step-before step)))
  (define after (math-datum (rewrite-step-after step)))
  (define candidates
    (for/list ([l (in-list (rewrite-step-links step))]
               #:when
               (and (path-prefix? (path-link-source l) source)
                    (path-prefix? (path-link-target l) target)
                    (equal? (drop source (length (path-link-source l)))
                            (drop target (length (path-link-target l))))
                    (equal? (datum-ref before (path-link-source l))
                            (datum-ref after (path-link-target l)))))
      (path-link-target l)))
  (if (null? candidates) target (argmin length candidates)))

; additive-operator-index : symbol? -> (or/c exact-positive-integer? #f)
;;   Extracts the right-operand index encoded by one n-ary additive separator role.
(define (additive-operator-index role)
  (define match
    (regexp-match #px"^operator-([0-9]+)$" (symbol->string role)))
  (and match
       (let ([index (string->number (cadr match))])
         (and (exact-positive-integer? index) index))))

; exact-source-path-for-target : rewrite-step? operand-path? -> (or/c operand-path? #f)
;;   Resolves one exact preserved/copy link into a target operand root.
(define (exact-source-path-for-target step target-path)
  (define candidates
    (remove-duplicates
     (for/list ([link (in-list (rewrite-step-links step))]
                #:when (and (equal? (path-link-target link) target-path)
                            (memq (path-link-kind link) '(preserve copy container))))
       (path-link-source link))
     equal?))
  (and (= (length candidates) 1) (car candidates)))

; surviving-additive-separator-matches : rewrite-step? list? list? list? -> list?
;;   Preserves an infix plus when the same adjacent surviving operands bracket it.
(define (surviving-additive-separator-matches step old destination existing)
  (define before-datum (math-datum (rewrite-step-before step)))
  (define after-datum (math-datum (rewrite-step-after step)))
  (define used-sources (map token-match-source existing))
  (define used-targets (map token-match-target existing))
  (filter
   values
   (for/list ([target (in-list destination)] [target-index (in-naturals)])
     (define right-index (additive-operator-index (prepared-token-role target)))
     (define target-parent (prepared-token-path target))
     (cond
       [(or (not right-index)
            (member target-index used-targets)
            (not (eq? (head (datum-ref after-datum target-parent)) '+)))
        #f]
       [else
        (define left-target (append target-parent (list (sub1 right-index))))
        (define right-target (append target-parent (list right-index)))
        (define left-source (exact-source-path-for-target step left-target))
        (define right-source (exact-source-path-for-target step right-target))
        (cond
          [(or (not left-source) (not right-source)
               (null? left-source) (null? right-source)
               (not (equal? (drop-right left-source 1)
                            (drop-right right-source 1)))
               (not (= (last right-source) (add1 (last left-source)))))
           #f]
          [else
           (define source-parent (drop-right left-source 1))
           (define source-role
             (string->symbol (format "operator-~a" (last right-source))))
           (define candidates
             (for/list ([source (in-list old)] [source-index (in-naturals)]
                        #:when (and (not (member source-index used-sources))
                                    (equal? (prepared-token-path source) source-parent)
                                    (eq? (prepared-token-role source) source-role)
                                    (string=? (prepared-token-text source)
                                              (prepared-token-text target))
                                    (eq? (head (datum-ref before-datum source-parent)) '+)))
               source-index))
           (and (= (length candidates) 1)
                (token-match (car candidates)
                             target-index
                             target-parent
                             'preserve))])]))))

; plan-token-transition : rewrite-step? list? list? -> token-transition?
;;   Partitions prepared ink using source/target paths carried by the applied rewrite.
(define (plan-token-transition step old destination)
  (define before (rewrite-step-before step))
  (define after (rewrite-step-after step))
  (define kind (transition-kind step))
  (define-values (atomic-sources atomic-targets) (transition-atomic-paths step))
  (define matches
    (filter values
      (for/list ([target (in-list destination)] [j (in-naturals)])
        (define p (prepared-token-path target))
        (define candidates
          (if (blocked? p atomic-targets)
              '()
              (remove-duplicates
                (for*/list ([link (in-list (rewrite-step-links step))]
                            #:when (and (equal? (path-link-target link) p)
                                        (not (blocked? (path-link-source link) atomic-sources)))
                            [i (in-range (length old))]
                            #:do [(define source (list-ref old i))]
                            #:when (and (equal? (prepared-token-path source) (path-link-source link))
                                        (compatible-ink? source target before after)))
                  (cons i link))
                equal?)))
        (and (= (length candidates) 1)
             (let* ([entry (car candidates)] [link (cdr entry)])
               (token-match (car entry) j
                            (enclosing-unit step (path-link-source link) p)
                            (path-link-kind link)))))))
  (define inferred-separators
    (if (eq? kind 'cancellation)
        (surviving-additive-separator-matches step old destination matches)
        '()))
  (define final-matches
    ;; Reorders are deliberately conservative: the affected additive focus is
    ;; atomic, so no sign or term token is reintroduced as a moving match here.
    ;; Cancellation may additionally preserve an infix plus whose two adjacent
    ;; operands are both witnessed survivors of the rewrite.
    (sort (append matches inferred-separators) < #:key token-match-target))
  (define sources (map token-match-source final-matches))
  (define targets (map token-match-target final-matches))
  (token-transition kind final-matches
                    (filter (lambda (i) (not (member i sources))) (range (length old)))
                    (filter (lambda (i) (not (member i targets))) (range (length destination)))
                    atomic-sources atomic-targets))
