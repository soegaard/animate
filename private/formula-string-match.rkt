#lang racket/base

;;;
;;; Deterministic Formula String-Match Planning
;;;

;; Planning is deliberately separate from animation compilation.  This makes
;; every automatic choice inspectable, deterministic, and testable without
;; rendering a frame.  The first implementation plans declared source-map
;; fragments.  It intentionally does not claim token-to-glyph matching or
;; geometric shape fallback.

(require racket/list
         (only-in racket/math nan? infinite?)
         "formula-part-transition.rkt"
         "formula-parts-visual.rkt"
         "formula-source-map.rkt"
         "formula-source-normalization.rkt"
         "formula-source.rkt"
         "source-document.rkt"
         "source-selector.rkt"
         "visual-selection.rkt"
         "visual-model.rkt")

(provide string-match
         string-match?
         string-match-source-selector
         string-match-destination-selector
         string-match-route
         string-match-mode
         string-match-appearance-complete-at-x
         string-match-appearance-duration
         string-path
         string-copy
         string-copy?
         string-copy-source-selector
         string-copy-destination-selector
         string-copy-route
         string-copy-mode
         (struct-out planned-string-match)
         (struct-out string-match-plan)
         string-match-plan-warnings
         string-match-plan->datum
         compare-string-match-plans
         plan-matching-strings)


;;;
;;; Public Match Values
;;;

;; `mode` is an author preference for the eventual motion compiler.  The
;; planner's `auto` policy selects rigid movement for an equal normalized
;; source block and cross-fade for deliberately changed source such as + -> -.
(struct string-match-data
  (source-selector destination-selector route mode appearance-complete-at-x appearance-duration)
  #:transparent
  #:guard
  (lambda (source-selector destination-selector route mode
                           appearance-complete-at-x appearance-duration who)
    (unless (source-selector? source-selector)
      (raise-argument-error who "source-selector?" source-selector))
    (unless (source-selector? destination-selector)
      (raise-argument-error who "source-selector?" destination-selector))
    (unless (or (not route) (formula-route? route))
      (raise-argument-error who "#f or formula-route?" route))
    (unless (string-movement-mode? mode)
      (raise-argument-error who "string-movement-mode?" mode))
    (unless (or (not appearance-complete-at-x)
                (source-selector? appearance-complete-at-x))
      (raise-argument-error who "#f or source-selector?" appearance-complete-at-x))
    (unless (or (not appearance-duration)
                (and (finite-progress? appearance-duration)
                     (positive? appearance-duration)
                     (<= appearance-duration 1)))
      (raise-argument-error who "#f or positive finite real in [0, 1]"
                            appearance-duration))
    (unless (eq? (not appearance-complete-at-x) (not appearance-duration))
      (raise-arguments-error
       who
       "both an appearance deadline and duration, or neither"
       "appearance-complete-at-x" appearance-complete-at-x
       "appearance-duration" appearance-duration))
    (values source-selector destination-selector route mode
            appearance-complete-at-x appearance-duration)))

;; string-match : source-selector? source-selector?
;;                [#:route (or/c #f formula-route?)]
;;                [#:mode string-movement-mode?]
;;                [#:appearance-complete-at-x (or/c #f source-selector?)]
;;                [#:appearance-duration (or/c #f positive finite real in [0,1])]
;;                -> string-match?
(define (string-match source-selector destination-selector
                      #:route [route #f]
                      #:mode [mode 'auto]
                      #:appearance-complete-at-x [appearance-complete-at-x #f]
                      #:appearance-duration [appearance-duration #f])
  (string-match-data source-selector destination-selector route mode
                     appearance-complete-at-x appearance-duration))

;; `string-match` is intentionally a keyword constructor.  The transparent
;; structure still supplies the usual predicate and accessors.
(define string-match? string-match-data?)
(define string-match-source-selector string-match-data-source-selector)
(define string-match-destination-selector string-match-data-destination-selector)
(define string-match-route string-match-data-route)
(define string-match-mode string-match-data-mode)
(define string-match-appearance-complete-at-x
  string-match-data-appearance-complete-at-x)
(define string-match-appearance-duration string-match-data-appearance-duration)

;; string-path : source-selector? source-selector? formula-route?
;;               [#:mode string-movement-mode?] -> string-match?
;; Concise spelling when an explicit match exists only to select a route.
(define (string-path source-selector destination-selector route
                     #:mode [mode 'auto]
                     #:appearance-complete-at-x [appearance-complete-at-x #f]
                     #:appearance-duration [appearance-duration #f])
  (string-match source-selector destination-selector
                #:route route
                #:mode mode
                #:appearance-complete-at-x appearance-complete-at-x
                #:appearance-duration appearance-duration))

;; A source-addressed copy deliberately uses a separate type from a match: it
;; does not consume its source material. The destination must instead remain
;; unmatched after ordinary matching, exactly like `formula-part-copy`.
(struct string-copy-data (source-selector destination-selector route mode)
  #:transparent
  #:guard
  (lambda (source-selector destination-selector route mode who)
    (unless (source-selector? source-selector)
      (raise-argument-error who "source-selector?" source-selector))
    (unless (source-selector? destination-selector)
      (raise-argument-error who "source-selector?" destination-selector))
    (unless (or (not route) (formula-route? route))
      (raise-argument-error who "#f or formula-route?" route))
    (unless (string-movement-mode? mode)
      (raise-argument-error who "string-movement-mode?" mode))
    (values source-selector destination-selector route mode)))

;; string-copy : source-selector? source-selector?
;;               [#:route (or/c #f formula-route?)]
;;               [#:mode string-movement-mode?] -> string-copy?
(define (string-copy source-selector destination-selector
                     #:route [route #f]
                     #:mode [mode 'auto])
  (string-copy-data source-selector destination-selector route mode))

(define string-copy? string-copy-data?)
(define string-copy-source-selector string-copy-data-source-selector)
(define string-copy-destination-selector string-copy-data-destination-selector)
(define string-copy-route string-copy-data-route)
(define string-copy-mode string-copy-data-mode)


;;;
;;; Planned Correspondence
;;;

(struct planned-string-match
  (source-span
   destination-span
   source-selection
   destination-selection
   reason
   movement-mode
   route
   appearance-complete-at-x
   appearance-duration)
  #:transparent
  #:guard
  (lambda (source-span destination-span source-selection destination-selection
                       reason movement-mode route appearance-complete-at-x
                       appearance-duration who)
    (unless (source-span? source-span)
      (raise-argument-error who "source-span?" source-span))
    (unless (source-span? destination-span)
      (raise-argument-error who "source-span?" destination-span))
    (unless (and (visual-selection? source-selection)
                 (not (visual-selection-empty? source-selection)))
      (raise-argument-error who "nonempty visual-selection?" source-selection))
    (unless (and (visual-selection? destination-selection)
                 (not (visual-selection-empty? destination-selection)))
      (raise-argument-error who "nonempty visual-selection?" destination-selection))
    (unless (memq reason '(explicit-span
                           explicit-string
                           explicit-key-map
                           automatic-source-block))
      (raise-argument-error who "planned-string-match-reason?" reason))
    (unless (string-movement-mode? movement-mode)
      (raise-argument-error who "string-movement-mode?" movement-mode))
    (unless (or (not route) (formula-route? route))
      (raise-argument-error who "#f or formula-route?" route))
    (unless (or (not appearance-complete-at-x)
                (source-selector? appearance-complete-at-x))
      (raise-argument-error who "#f or source-selector?" appearance-complete-at-x))
    (unless (or (not appearance-duration)
                (and (finite-progress? appearance-duration)
                     (positive? appearance-duration)
                     (<= appearance-duration 1)))
      (raise-argument-error who "#f or positive finite real in [0, 1]"
                            appearance-duration))
    (unless (eq? (not appearance-complete-at-x) (not appearance-duration))
      (raise-arguments-error
       who
       "both an appearance deadline and duration, or neither"
       "appearance-complete-at-x" appearance-complete-at-x
       "appearance-duration" appearance-duration))
    (values source-span destination-span source-selection destination-selection
            reason movement-mode route appearance-complete-at-x
            appearance-duration)))

;; A plan retains formulas only for diagnostics and later compilation.  All
;; decisions themselves are captured by `planned-string-match` values and the
;; ordered unmatched units.
(struct string-match-plan
  (source destination matches unmatched-source unmatched-destination diagnostics)
  #:transparent
  #:guard
  (lambda (source destination matches unmatched-source unmatched-destination
                  diagnostics who)
    (unless (formula-assembly-visual? source)
      (raise-argument-error who "formula-assembly-visual?" source))
    (unless (formula-assembly-visual? destination)
      (raise-argument-error who "formula-assembly-visual?" destination))
    (unless (and (list? matches) (andmap planned-string-match? matches))
      (raise-argument-error who "list of planned-string-match? values" matches))
    (unless (and (list? unmatched-source)
                 (andmap formula-source-unit? unmatched-source))
      (raise-argument-error who "list of formula-source-unit? values" unmatched-source))
    (unless (and (list? unmatched-destination)
                 (andmap formula-source-unit? unmatched-destination))
      (raise-argument-error who "list of formula-source-unit? values" unmatched-destination))
    (unless (and (list? diagnostics) (andmap string? diagnostics))
      (raise-argument-error who "list of strings" diagnostics))
    (values source destination matches unmatched-source unmatched-destination
            (map string->immutable-string diagnostics))))


;;;
;;; Planning API
;;;

;; plan-matching-strings : formula-assembly-visual? formula-assembly-visual?
;;                          [#:matches (listof string-match?)]
;;                          [#:key-map (listof string-match?)]
;;                          [#:protect-source (listof source-selector?)]
;;                          [#:protect-destination (listof source-selector?)]
;;                          [#:on-ambiguity (or/c 'left-to-right 'error)]
;;                          -> string-match-plan?
;;
;; Explicit matches are consumed in list order; automatic source blocks are
;; then selected by a deterministic longest-common-substring policy.  There is
;; no glyph-shape fallback in this planner, intentionally: this is string
;; correspondence, not geometry correspondence.
(define (plan-matching-strings source destination
                               #:matches [matches '()]
                               #:key-map [key-map '()]
                               #:protect-source [protect-source '()]
                               #:protect-destination [protect-destination '()]
                               #:on-ambiguity [on-ambiguity 'left-to-right])
  (check-formula 'plan-matching-strings source)
  (check-formula 'plan-matching-strings destination)
  (check-match-list 'plan-matching-strings "matches" matches)
  (check-match-list 'plan-matching-strings "key-map" key-map)
  (check-selector-list 'plan-matching-strings "protect-source" protect-source)
  (check-selector-list 'plan-matching-strings "protect-destination" protect-destination)
  (unless (memq on-ambiguity '(left-to-right error))
    (raise-argument-error
     'plan-matching-strings
     "(or/c 'left-to-right 'error)"
     on-ambiguity))
  ;; Accessing the unit stream deliberately verifies both formulas carry a
  ;; source map before we resolve any caller selectors.
  (define source-units (formula-source-units source))
  (define destination-units (formula-source-units destination))
  (define source-by-name (units-by-name source source-units))
  (define destination-by-name (units-by-name destination destination-units))
  (define protected-source
    (resolve-protected-unit-names source protect-source source-by-name))
  (define protected-destination
    (resolve-protected-unit-names destination protect-destination destination-by-name))
  (define-values (explicit-plans used-source used-destination)
    (consume-explicit-matches
     source destination source-by-name destination-by-name matches
     'explicit #hasheq() #hasheq()))
  (define-values (key-plans key-source key-destination)
    (consume-explicit-matches
     source destination source-by-name destination-by-name key-map
     'key-map used-source used-destination))
  (define remaining-source
    (filter-units source-units key-source protected-source))
  (define remaining-destination
    (filter-units destination-units key-destination protected-destination))
  (define-values (automatic-plans final-source final-destination)
    (consume-automatic-blocks source destination
                              remaining-source remaining-destination
                              on-ambiguity))
  (string-match-plan
   source
   destination
   (append explicit-plans key-plans automatic-plans)
   (restore-protected-unmatched source-units final-source protected-source)
   (restore-protected-unmatched destination-units
                                final-destination
                                protected-destination)
   (append
    (if (zero? (hash-count protected-source))
        '()
        (list "protected source material was excluded from automatic matching"))
    (if (zero? (hash-count protected-destination))
        '()
        (list "protected destination material was excluded from automatic matching")))))


;;;
;;; Plan Inspection
;;;

(define (string-match-plan-warnings plan)
  (check-plan 'string-match-plan-warnings plan)
  (string-match-plan-diagnostics plan))

;; string-match-plan->datum : string-match-plan? -> immutable hash?
;; A compact, stable report suitable for a previewer or test failure message.
(define (string-match-plan->datum plan)
  (check-plan 'string-match-plan->datum plan)
  (hash
   'matches
   (for/list ([match (in-list (string-match-plan-matches plan))])
     (hash 'source-span (span->datum (planned-string-match-source-span match))
           'destination-span (span->datum (planned-string-match-destination-span match))
           'reason (planned-string-match-reason match)
           'movement-mode (planned-string-match-movement-mode match)
           'route (planned-string-match-route match)
           'appearance-complete-at-x
           (planned-string-match-appearance-complete-at-x match)
           'appearance-duration
           (planned-string-match-appearance-duration match)))
   'unmatched-source
   (map unit->datum (string-match-plan-unmatched-source plan))
   'unmatched-destination
   (map unit->datum (string-match-plan-unmatched-destination plan))
   'diagnostics (string-match-plan-diagnostics plan)))

; compare-string-match-plans : string-match-plan? string-match-plan? -> immutable-hash?
;; Reports semantic planner changes after a source reload.  Matches are keyed
;; by exact source/destination spans, so repeated textual occurrences remain
;; distinct and a changed decision is not mistaken for a removal plus addition.
(define (compare-string-match-plans before after)
  (check-plan 'compare-string-match-plans before)
  (check-plan 'compare-string-match-plans after)
  (define before-matches (string-match-plan-matches before))
  (define after-matches (string-match-plan-matches after))
  (define before-by-key
    (for/hash ([match (in-list before-matches)])
      (values (planned-match-key match) match)))
  (define after-by-key
    (for/hash ([match (in-list after-matches)])
      (values (planned-match-key match) match)))
  (define added-keys
    (filter (lambda (key) (not (hash-has-key? before-by-key key)))
            (hash-keys-in-order after-by-key after-matches)))
  (define removed-keys
    (filter (lambda (key) (not (hash-has-key? after-by-key key)))
            (hash-keys-in-order before-by-key before-matches)))
  (define shared-keys
    (filter (lambda (key) (hash-has-key? after-by-key key))
            (hash-keys-in-order before-by-key before-matches)))
  (hash
   'matches-added (map (lambda (key) (planned-match->datum (hash-ref after-by-key key)))
                       added-keys)
   'matches-removed (map (lambda (key) (planned-match->datum (hash-ref before-by-key key)))
                         removed-keys)
   'matches-changed
   (for/list ([key (in-list shared-keys)]
              #:unless (equal? (planned-match-decision (hash-ref before-by-key key))
                               (planned-match-decision (hash-ref after-by-key key))))
     (hash 'before (planned-match->datum (hash-ref before-by-key key))
           'after (planned-match->datum (hash-ref after-by-key key))))
   'unmatched-source-changed?
   (not (equal? (string-match-plan-unmatched-source before)
                (string-match-plan-unmatched-source after)))
   'unmatched-destination-changed?
   (not (equal? (string-match-plan-unmatched-destination before)
                (string-match-plan-unmatched-destination after)))))

(define (hash-keys-in-order table matches)
  (for/list ([match (in-list matches)])
    (planned-match-key match)))

(define (planned-match-key match)
  (list (span->datum (planned-string-match-source-span match))
        (span->datum (planned-string-match-destination-span match))))

(define (planned-match-decision match)
  (list (planned-string-match-reason match)
        (planned-string-match-movement-mode match)
        (planned-string-match-route match)
        (planned-string-match-appearance-complete-at-x match)
        (planned-string-match-appearance-duration match)))

(define (planned-match->datum match)
  (hash 'source-span (span->datum (planned-string-match-source-span match))
        'destination-span (span->datum (planned-string-match-destination-span match))
        'reason (planned-string-match-reason match)
        'movement-mode (planned-string-match-movement-mode match)
        'route (planned-string-match-route match)
        'appearance-complete-at-x
        (planned-string-match-appearance-complete-at-x match)
        'appearance-duration
        (planned-string-match-appearance-duration match)))


;;;
;;; Explicit Matching
;;;

(define (consume-explicit-matches source destination source-by-name destination-by-name
                                  match-values kind used-source used-destination)
  (for/fold ([plans '()] [source-used used-source] [destination-used used-destination])
            ([match-value (in-list match-values)])
    (define source-units
      (selector->units source
                       (string-match-source-selector match-value)
                       source-by-name))
    (define destination-units
      (selector->units destination
                       (string-match-destination-selector match-value)
                       destination-by-name))
    (unless (= (length source-units) (length destination-units))
      (raise-arguments-error
       'plan-matching-strings
       "explicit selector pairs resolving to the same number of source units"
       "source-selector" (string-match-source-selector match-value)
       "destination-selector" (string-match-destination-selector match-value)
       "source-count" (length source-units)
       "destination-count" (length destination-units)))
    (when (null? source-units)
      (raise-arguments-error
       'plan-matching-strings
       "explicit selectors resolving to mapped formula material"
       "source-selector" (string-match-source-selector match-value)
       "destination-selector" (string-match-destination-selector match-value)))
    (check-units-unconsumed! kind source-units source-used 'source)
    (check-units-unconsumed! kind destination-units destination-used 'destination)
    (define reason
      (cond
        [(eq? kind 'key-map) 'explicit-key-map]
        [(and (source-span? (string-match-source-selector match-value))
              (source-span? (string-match-destination-selector match-value)))
         'explicit-span]
        [else 'explicit-string]))
    (define new-plans
      (for/list ([source-unit (in-list source-units)]
                 [destination-unit (in-list destination-units)])
        (make-planned-match source destination
                            (list source-unit) (list destination-unit)
                            reason
                            (string-match-mode match-value)
                            (string-match-route match-value)
                            (string-match-appearance-complete-at-x match-value)
                            (string-match-appearance-duration match-value))))
    (values
     (append plans new-plans)
     (mark-units source-used source-units)
     (mark-units destination-used destination-units))))

(define (selector->units formula selector units-by-name)
  (define matches (formula-find formula selector))
  (for/list ([match (in-list matches)])
    (hash-ref
     units-by-name
     (formula-source-match-name match)
     (lambda ()
       (error 'plan-matching-strings
              "internal error: source map match has no normalized unit")))))

(define (resolve-protected-unit-names formula selectors units-by-name)
  (for/fold ([result #hasheq()]) ([selector (in-list selectors)])
    (define units (selector->units formula selector units-by-name))
    (when (null? units)
      (raise-arguments-error
       'plan-matching-strings
       "protected selectors resolving to mapped formula material"
       "formula-id" (visual-id formula)
       "selector" selector))
    (mark-units result units)))

(define (check-units-unconsumed! kind units used side)
  (for ([unit (in-list units)])
    (when (hash-has-key? used (unit-name unit))
      (raise-arguments-error
       'plan-matching-strings
       "explicit source material consumed at most once"
       "mapping-kind" kind
       "side" side
       "span" (formula-source-unit-span unit)))))


;;;
;;; Automatic Longest Blocks
;;;

;; The loop recomputes the longest common contiguous block after every
;; consumption.  This is intentionally straightforward rather than clever:
;; input streams are normally short and the direct implementation makes the
;; documented tie rules auditable.
(define (consume-automatic-blocks source destination source-units destination-units
                                  on-ambiguity)
  (let loop ([remaining-source source-units]
             [remaining-destination destination-units]
             [plans '()])
    (define candidates
      (longest-common-block-candidates remaining-source remaining-destination))
    (cond
      [(null? candidates)
       (values plans remaining-source remaining-destination)]
      [else
       (define selected
         (choose-automatic-candidate candidates on-ambiguity))
       (define source-block (automatic-block-source-units selected))
       (define destination-block (automatic-block-destination-units selected))
       (define plan
         (make-planned-match source destination
                             source-block destination-block
                             'automatic-source-block 'rigid #f #f #f))
       (loop (remove-block remaining-source source-block)
             (remove-block remaining-destination destination-block)
             (append plans (list plan)))])))

(struct automatic-block (source-units destination-units) #:transparent)

(define (longest-common-block-candidates source-units destination-units)
  (define source-count (length source-units))
  (define destination-count (length destination-units))
  ;; The loop below is the direct formulation of longest common substring. It
  ;; is deliberately kept clear rather than micro-optimised: formula source
  ;; streams are short, and every candidate must be retained for the public
  ;; ambiguity policy anyway.  A future token map can replace it with a
  ;; dynamic program without changing the plan representation or tie rules.
  (define (common-prefix-length source-tail destination-tail)
    (let loop ([remaining-source source-tail]
               [remaining-destination destination-tail]
               [count 0])
      (if (and (pair? remaining-source)
               (pair? remaining-destination)
               (equal? (formula-source-unit-normalized-key
                        (car remaining-source))
                       (formula-source-unit-normalized-key
                        (car remaining-destination))))
          (loop (cdr remaining-source)
                (cdr remaining-destination)
                (add1 count))
          count)))
  (define all-candidates-reversed '())
  (for* ([source-index (in-range source-count)]
         [destination-index (in-range destination-count)])
    (define block-length
      (common-prefix-length
       (drop source-units source-index)
       (drop destination-units destination-index)))
    (when (positive? block-length)
      (set! all-candidates-reversed
            (cons
             (automatic-block
              (take (drop source-units source-index) block-length)
              (take (drop destination-units destination-index) block-length))
             all-candidates-reversed))))
  (define all-candidates (reverse all-candidates-reversed))
  (cond
    [(null? all-candidates) '()]
    [else
     (define sorted
       (sort all-candidates automatic-block<?))
     (define best (car sorted))
     (filter (lambda (candidate)
               (automatic-block-score=? candidate best))
             sorted)]))

;; Lower sort order is better.  The last four clauses are the documented
;; left-to-right deterministic policy; the first two are the block-quality
;; ranking.  Length is compared before weight because a block means a count of
;; contiguous source units, not a count of source characters.
(define (automatic-block<? left right)
  (define (less? left-score right-score)
    (cond
      [(null? left-score) #f]
      [(< (car left-score) (car right-score)) #t]
      [(> (car left-score) (car right-score)) #f]
      [else (less? (cdr left-score) (cdr right-score))]))
  (less? (automatic-block-sort-key left)
         (automatic-block-sort-key right)))

(define (automatic-block-score=? left right)
  (equal? (automatic-block-quality-key left)
          (automatic-block-quality-key right)))

(define (automatic-block-sort-key block)
  (append (automatic-block-quality-key block)
          (list (source-span-start
                 (formula-source-unit-span
                  (car (automatic-block-source-units block))))
                (source-span-start
                 (formula-source-unit-span
                  (car (automatic-block-destination-units block))))
                (source-span-length
                 (span-covering-units (automatic-block-source-units block)))
                (source-span-length
                 (span-covering-units (automatic-block-destination-units block))))))

(define (automatic-block-quality-key block)
  (list (- (length (automatic-block-source-units block)))
        (- (units-visible-weight (automatic-block-source-units block)))
        (- (units-normalized-length (automatic-block-source-units block)))))

(define (choose-automatic-candidate candidates on-ambiguity)
  (when (and (eq? on-ambiguity 'error)
             (pair? (cdr candidates)))
    (raise-arguments-error
     'plan-matching-strings
     "an unambiguous automatic source block or #:on-ambiguity 'left-to-right"
     "candidates"
     (for/list ([candidate (in-list candidates)])
       (list (span-covering-units (automatic-block-source-units candidate))
             (span-covering-units (automatic-block-destination-units candidate))))))
  ;; `longest-common-block-candidates` preserves automatic-block<? order.
  (car candidates))

(define (remove-block units block)
  (for/fold ([remaining units]) ([unit (in-list block)])
    (remove unit remaining eq?)))


;;;
;;; Plan Construction and Helpers
;;;

(define (make-planned-match source destination source-units destination-units
                            reason requested-mode route
                            appearance-complete-at-x appearance-duration)
  (planned-string-match
   (span-covering-units source-units)
   (span-covering-units destination-units)
   (units->selection source source-units)
   (units->selection destination destination-units)
   reason
   (resolve-movement-mode requested-mode source-units destination-units)
   route
   appearance-complete-at-x
   appearance-duration))

(define (resolve-movement-mode requested-mode source-units destination-units)
  (if (eq? requested-mode 'auto)
      (if (and (= (length source-units) (length destination-units))
               (for/and ([source-unit (in-list source-units)]
                         [destination-unit (in-list destination-units)])
                 (equal? (formula-source-unit-normalized-key source-unit)
                         (formula-source-unit-normalized-key destination-unit))))
          'rigid
          'cross-fade)
      requested-mode))

(define (units->selection formula units)
  (visual-selection
   (list (visual-id formula))
   (append* (map formula-source-unit-glyph-paths units))))

(define (span-covering-units units)
  (unless (pair? units)
    (error 'plan-matching-strings "internal error: empty source unit block"))
  (source-span
   (source-span-start (formula-source-unit-span (car units)))
   (source-span-end (formula-source-unit-span (last units)))))

(define (units-visible-weight units)
  (for/sum ([unit (in-list units)])
    (formula-source-unit-visible-weight unit)))

(define (units-normalized-length units)
  (for/sum ([unit (in-list units)])
    (length (formula-source-unit-normalized-key unit))))

(define (source-span-length span)
  (- (source-span-end span) (source-span-start span)))

(define (units-by-name formula units)
  (define matches
    (formula-source-map-matches (formula-source-map formula)))
  (unless (= (length units) (length matches))
    (error 'plan-matching-strings
           "internal error: source map and normalized unit stream disagree"))
  (for/hash ([unit (in-list units)]
             [match (in-list matches)])
    (values (formula-source-match-name match) unit)))

(define (unit-name unit)
  ;; The local path first element is a formula part name in declared mode.
  ;; Token maps can retain this helper by assigning every source unit one
  ;; stable owning leaf name in their source-map layer.
  (car (car (formula-source-unit-glyph-paths unit))))

(define (mark-units result units)
  (for/fold ([marked result]) ([unit (in-list units)])
    (hash-set marked (unit-name unit) #t)))

(define (filter-units units consumed protected)
  (filter (lambda (unit)
            (and (not (hash-has-key? consumed (unit-name unit)))
                 (not (hash-has-key? protected (unit-name unit)))))
          units))

;; Protected units are excluded while looking for automatic blocks, but are
;; still unmatched material: they must fade according to the caller's mismatch
;; policy.  Rebuilding from the original stream restores canonical source
;; order instead of appending them arbitrarily after automatic leftovers.
(define (restore-protected-unmatched original-units automatic-leftovers protected)
  (define automatic-leftover-names
    (mark-units #hasheq() automatic-leftovers))
  (filter (lambda (unit)
            (or (hash-has-key? automatic-leftover-names (unit-name unit))
                (hash-has-key? protected (unit-name unit))))
          original-units))

(define (span->datum span)
  (list (source-span-start span) (source-span-end span)))

(define (unit->datum unit)
  (hash 'span (span->datum (formula-source-unit-span unit))
        'raw-key (formula-source-unit-raw-key unit)
        'normalized-key (formula-source-unit-normalized-key unit)))

(define (string-movement-mode? value)
  (and (memq value '(auto rigid glyphwise cross-fade)) #t))

(define (finite-progress? value)
  (and (real? value) (not (nan? value)) (not (infinite? value))))

(define (check-formula who value)
  (unless (formula-assembly-visual? value)
    (raise-argument-error who "formula-assembly-visual?" value)))

(define (check-match-list who name value)
  (unless (and (list? value) (andmap string-match? value))
    (raise-arguments-error who "a list of string-match? values" name value)))

(define (check-selector-list who name value)
  (unless (and (list? value) (andmap source-selector? value))
    (raise-arguments-error who "a list of source-selector? values" name value)))

(define (check-plan who value)
  (unless (string-match-plan? value)
    (raise-argument-error who "string-match-plan?" value)))
