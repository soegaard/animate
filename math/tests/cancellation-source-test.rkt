#lang racket/base

;;;
;;; Source-Relative Cancellation Regression
;;;

;; Compiles the real math adapter against deliberately non-flat, deterministic
;; fraction geometry. This is an animation-contract test, not a native TeX render.
;; The source variable is above and to the right of its destination; the unit,
;; multiplication dot, and variable also have distinct typographic centre heights.

;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in racket/list last)
         "check.rkt"
         (submod "native-contract.rkt" support)
         "../main.rkt"
         "../private/datum.rkt"
         "../private/native.rkt"
         "../private/typeset-model.rkt"
         "../private/typeset.rkt"
         "../private/prepare.rkt"
         "../private/transition-plan.rkt"
         (prefix-in adapter: "../private/animate-adapter.rkt"))

;; Exports
(provide run-cancellation-source-tests)

;;;
;;; Non-flat Prepared Geometry
;;;

; nonflat-typesetter : boolean? boolean? boolean? -> procedure?
;;   Builds source/target fixtures, optionally putting unrelated equation ink first.
(define (nonflat-typesetter equation? outside-first? incompatible?)
  (lambda (state size multiplication foreground directory)
    (define datum (math-datum state))
    (define focus (if equation? '(0) '()))
    (define body (datum-ref datum focus))
    (define source? (eq? (head body) '/))
    (define product? (eq? (head body) '*))
    (define compound?
      (if source? (pair? (caddr (cadr body)))
          (if product? (pair? (caddr body)) (pair? body))))
    (define survivor-prefix
      (cond [source? '(0 1)] [product? '(1)] [else '()]))
    (define tokens '())
    (define (add! path role text x y width height)
      (define i (length tokens))
      (set! tokens
        (append tokens
          (list (prepared-token path role text
                   (format "nonflat|~s|~s|~s" datum path role)
                   x y width height (string->symbol (format "nonflat~a" i)))))))
    (define (local! path role text x y width height)
      (add! (append focus path) role text x y width height))
    (define (outside!)
      (when equation?
        (add! '() 'relation "=" 4 0 1/4 1/5)
        (add! '(1 0) 'atom "12" 6 3/5 3/5 2/5)
        (add! '(1) 'structure "\\frac{12}{3}" 6 0 4/5 1/25)
        (add! '(1 1) 'atom "3" 6 -3/5 1/4 2/5)))
    (when outside-first? (outside!))
    (cond
      [source?
       (local! '(0 0) 'atom "3" 1/2 4/5 1/4 2/5)
       (local! '() 'structure "\\frac{3x}{3}" 3/2 0 3 1/25)
       (local! '(1) 'atom "3" 3/2 -4/5 1/4 2/5)]
      [product?
       (local! '(0) 'atom "1" 0 1/20 1/4 2/5)
       (local! '() 'operator-1 "\\cdot " 1/2 3/20 1/10 1/10)])
    (define delta-x (if source? 1 0))
    (define delta-y (if source? 4/5 0))
    (local! (append survivor-prefix (if compound? '(0) '())) 'atom "x"
            (+ 1 delta-x) delta-y 2/5 1/2)
    (when compound?
      (local! survivor-prefix 'operator-1 "+"
              (+ 3/2 delta-x) (+ 1/10 delta-y) 1/4 1/4)
      (local! (append survivor-prefix '(1)) 'atom "y"
              (+ 2 delta-x) (+ 1/20 delta-y (if (and source? incompatible?) 1/3 0))
              2/5 1/2))
    (unless outside-first? (outside!))
    (prepared-layout state tokens (format-math-source state #:multiplication multiplication)
                     '("Non-flat numerator geometry; contract test only."))))

; phase-at : presentation-plan? symbol? -> scheduled-phase?
;;   Finds one cancellation phase by its hierarchical address, never by a timestamp.
(define (phase-at plan kind)
  (findf (lambda (phase)
           (define key (scheduled-phase-step phase))
           (and (eq? kind (scheduled-phase-kind phase))
                (eq? 'cancel (if (pair? key) (last key) key))))
         (plan-schedule plan)))

; sample-contract : scene? real? -> immutable-hash?
;;   Interpolates one recorded native request batch with common linear progress.
;;   Relative-position invariance must hold for any common native easing as well.
(define (sample-contract scn time)
  (define c (clip-for-time scn time))
  (unless c (error 'nonflat-cancellation "no clip at ~a" time))
  (define u (/ (- time (clip-start c)) (clip-duration c)))
  (for/hash ([(id start) (in-hash (clip-before c))])
    (define end (hash-ref (clip-after c) id start))
    (define p (visual-position start))
    (define q (visual-position end))
    (values id
      (struct-copy visual start
        [opacity (+ (visual-opacity start) (* u (- (visual-opacity end) (visual-opacity start))))]
        [position (point (+ (point-x p) (* u (- (point-x q) (point-x p))))
                         (+ (point-y p) (* u (- (point-y q) (point-y p)))))]))))

; visual-for-asset : immutable-hash? string? -> visual?
;;   Identifies one view from its explicit fixture asset, not repeated glyph text.
(define (visual-for-asset snapshot asset)
  (or (findf (lambda (v) (and (eq? (visual-kind v) 'svg)
                             (equal? (visual-content v) asset)))
             (hash-values snapshot))
      (error 'nonflat-cancellation "missing fixture asset ~a" asset)))

; check-nonflat-cancellation : boolean? boolean? boolean? boolean? boolean? -> void?
;;   Checks a complete cancel/remove-unit sequence and the unaffected equation side.
(define (check-nonflat-cancellation equation? outside-first? explicit? compound? incompatible?)
  (define survivor (if compound? '(+ x y) 'x))
  (define focus (if equation? '(0) '()))
  (define problem
    (math (if equation? `(= (/ (* 3 ,survivor) 3) (/ 12 3)) `(/ (* 3 ,survivor) 3))
          #:id 'nonflat-cancellation #:context (math-context #:real '(x y))))
  (define solution
    (derive problem
      [isolate-x
       (steps [remove-coefficient
               (steps [cancel (cancel-factor #:factor 3 #:keep-one? #t #:at (at-path focus))]
                      [remove-unit (remove-unit #:at (at-path focus))])])]))
  (define ordinary
    (present solution #:style (math-presentation #:history 'replace #:duration 1
                                                 #:pause-between-groups 0)))
  (define plan
    (if explicit?
      (choreograph ordinary
        [(isolate-x remove-coefficient cancel)
         (retire-cancelled #:duration 1/2)
         (reveal-created #:duration 1/4)
         (compact #:duration 3/4)])
      ordinary))
  (define step (derivation-step solution '(isolate-x remove-coefficient cancel)))
  (define typesetter (nonflat-typesetter equation? outside-first? incompatible?))
  (define prepared
    (parameterize ([current-native-loader loader] [current-math-typesetter typesetter])
      (prepare-math-plan! plan)))
  (define scn
    (parameterize ([current-native-loader loader]
                   [current-math-typesetter (lambda args (error 'nonflat-cancellation "unexpected typesetting"))])
      (adapter:math-plan->scene! prepared)))
  (check-close (scene-duration scn) (plan-duration plan) 1e-8 'duration-preserved)
  (check-equal (math-datum (derivation-final solution))
               (if equation? `(= ,survivor (/ 12 3)) survivor) 'remove-unit-remains-separate)
  (define old (prepared-layout-tokens (hash-ref (prepared-math-plan-layouts prepared) (rewrite-step-before step))))
  (define target (prepared-layout-tokens (hash-ref (prepared-math-plan-layouts prepared) (rewrite-step-after step))))
  (define partition (plan-token-transition step old target))
  (define source-x
    (findf (lambda (token) (and (equal? (prepared-token-path token)
                                       (append focus '(0 1) (if compound? '(0) '())))
                               (eq? 'atom (prepared-token-role token)))) old))
  (define target-x
    (findf (lambda (token) (and (equal? (prepared-token-path token)
                                       (append focus '(1) (if compound? '(0) '())))
                               (eq? 'atom (prepared-token-role token)))) target))
  (check-true (> (- (prepared-token-y source-x) (prepared-token-y target-x)) 1/2)
              'regression-requires-a-raised-source-numerator)
  (check-true (> (abs (- (prepared-token-x source-x) (prepared-token-x target-x))) 1/2)
              'regression-also-has-horizontal-source-displacement)
  (define retired-phase (phase-at plan 'retire-cancelled))
  (define compact-phase (phase-at plan 'compact))
  (define reveal (and explicit? (phase-at plan 'reveal-created)))
  (define start (+ (scheduled-phase-start retired-phase) (scheduled-phase-duration retired-phase)))
  (define reference-snapshot (sample-contract scn start))
  (define survivor-id (visual-id (visual-for-asset reference-snapshot (prepared-token-asset source-x))))
  (define outsiders
    (if equation?
        (filter (lambda (t) (or (eq? (prepared-token-role t) 'relation)
                                (path-prefix? '(1) (prepared-token-path t)))) old)
        '()))
  (for* ([phase (in-list (filter values (list reveal compact-phase)))]
         [fraction (in-list '(1/20 3/20 2499/10000 1/4 2501/10000 1/2 3/4 17/20 19/20))])
    (define time (+ (scheduled-phase-start phase) (* fraction (scheduled-phase-duration phase))))
    (define snapshot (sample-contract scn time))
    (define x-visual
      (if incompatible? (visual-for-asset snapshot (prepared-token-asset target-x))
          (hash-ref snapshot survivor-id)))
    (for ([token (in-list target)] #:when (path-prefix? focus (prepared-token-path token)))
      (define match
        (findf (lambda (m) (equal? (list-ref target (token-match-target m)) token))
               (token-transition-matches partition)))
      (define current
        (visual-for-asset snapshot
          (if (and match (not incompatible?))
              (prepared-token-asset (list-ref old (token-match-source match)))
              (prepared-token-asset token))))
      (check-true (positive? (visual-opacity current))
                  (list 'product-is-visible-before-compaction-finishes explicit? fraction))
      (when (positive? (visual-opacity current))
        (check-close (- (point-x (visual-position current)) (point-x (visual-position x-visual)))
                     (- (prepared-token-x token) (prepared-token-x target-x)) 1e-8
                     (list 'target-relative-x explicit? equation? compound? fraction))
        (check-close (- (point-y (visual-position current)) (point-y (visual-position x-visual)))
                     (- (prepared-token-y token) (prepared-token-y target-x)) 1e-8
                     (list 'target-relative-y explicit? equation? compound? fraction))))
    (when incompatible?
      (for ([token (in-list old)] #:when (path-prefix? focus (prepared-token-path token)))
        (define retired (visual-for-asset snapshot (prepared-token-asset token)))
        (check-equal (visual-opacity retired) 0 'fallback-retires-whole-old-focus-first)))
    (for ([token (in-list outsiders)])
      (define before (visual-for-asset reference-snapshot (prepared-token-asset token)))
      (define after (visual-for-asset snapshot (prepared-token-asset token)))
      (check-equal (visual-opacity after) 1 'unaffected-relation-and-rhs-stay-visible)
      (check-equal (visual-position after) (visual-position before) 'unaffected-relation-and-rhs-stay-put)))
  (define cancelled-state (after solution '(isolate-x remove-coefficient cancel)))
  (check-equal (math-datum cancelled-state)
               (if equation? `(= (* 1 ,survivor) (/ 12 3)) `(* 1 ,survivor))
               'explicit-unit-checkpoint-preserved))

;;;
;;; Additive Hold Regression
;;;

; additive-gap-typesetter : math? real? symbol? string? path-string? -> prepared-layout?
;;   Gives the cancelled source a visible interior gap and a compact destination.
(define (additive-gap-typesetter state size multiplication foreground directory)
  (define source (format-math-source state #:multiplication multiplication))
  (define datum (math-datum state))
  (define spans
    (filter (lambda (span) (not (eq? (math-source-span-role span) 'expression)))
            (math-source-spans source)))
  (prepared-layout state
    (for/list ([span (in-list spans)] [i (in-naturals)])
      (define path (math-source-span-path span))
      (define role (math-source-span-role span))
      (define text
        (substring (math-source-text source)
                   (math-source-span-start span)
                   (math-source-span-end span)))
      (prepared-token path role text (format "additive-gap|~s|~s|~s" datum path role)
                      (* 3/10 i) 0 1/5 2/5
                      (string->symbol (format "additive-gap~a" i))))
    source '("Separated additive survivors; contract test only.")))

; check-additive-hold : -> void?
;;   Proves that retirement leaves the matched x/y ink visible until compaction.
(define (check-additive-hold)
  (define solution
    (derive (math '(- (+ x 5 y) 5) #:id 'additive-gap
                  #:context (math-context #:real '(x y)))
      [cancel-five (cancel-addends)]))
  (define plan
    (choreograph
      (present solution #:style (math-presentation #:history 'replace #:duration 1))
      [cancel-five (retire-cancelled #:duration 3/5)
                   (hold 6/5)
                   (compact #:duration 3/5)]))
  (define step (derivation-step solution 'cancel-five))
  (define prepared
    (parameterize ([current-native-loader loader]
                   [current-math-typesetter additive-gap-typesetter])
      (prepare-math-plan! plan)))
  (define scn
    (parameterize ([current-native-loader loader]
                   [current-math-typesetter
                    (lambda args (error 'additive-gap "unexpected typesetting"))])
      (adapter:math-plan->scene! prepared)))
  (define old
    (prepared-layout-tokens
      (hash-ref (prepared-math-plan-layouts prepared) (rewrite-step-before step))))
  (define target
    (prepared-layout-tokens
      (hash-ref (prepared-math-plan-layouts prepared) (rewrite-step-after step))))
  (define partition (plan-token-transition step old target))
  (define source-x
    (findf (lambda (token) (and (string=? (prepared-token-text token) "x")
                                (equal? (prepared-token-path token) '(0 0)))) old))
  (define source-y
    (findf (lambda (token) (and (string=? (prepared-token-text token) "y")
                                (equal? (prepared-token-path token) '(0 2)))) old))
  (check-true source-x 'source-x-is-explicit)
  (check-true source-y 'source-y-is-explicit)
  (define matched-sources (map token-match-source (token-transition-matches partition)))
  (define source-x-index
    (for/first ([token (in-list old)] [i (in-naturals)] #:when (equal? token source-x)) i))
  (define source-y-index
    (for/first ([token (in-list old)] [i (in-naturals)] #:when (equal? token source-y)) i))
  (check-true (member source-x-index matched-sources) 'x-is-a-preserved-survivor)
  (check-true (member source-y-index matched-sources) 'y-is-a-preserved-survivor)
  (define hold-phase
    (findf (lambda (phase)
             (and (eq? (scheduled-phase-kind phase) 'hold)
                  (eq? (scheduled-phase-step phase) 'cancel-five)))
           (plan-schedule plan)))
  (check-true hold-phase 'explicit-hold-phase)
  (define snapshot
    (sample-contract scn (+ (scheduled-phase-start hold-phase)
                            (/ (scheduled-phase-duration hold-phase) 2))))
  (define x-view (visual-for-asset snapshot (prepared-token-asset source-x)))
  (define y-view (visual-for-asset snapshot (prepared-token-asset source-y)))
  (check-equal (visual-opacity x-view) 1 'x-remains-visible-during-hold)
  (check-equal (visual-opacity y-view) 1 'y-remains-visible-during-hold)
  (check-true (> (abs (- (point-x (visual-position y-view))
                         (point-x (visual-position x-view))))
                 1/2)
              'survivors-remain-visibly-separated))

;;;
;;; Regression Matrix
;;;

; run-cancellation-source-tests : -> void?
;;   Covers nonzero source deltas, outside survivors, hierarchical keys, and explicit reveals.
(define (run-cancellation-source-tests)
  (for* ([equation? '(#f #t)] [outside-first? (if equation? '(#f #t) '(#f))]
         [explicit? '(#f #t)] [compound? '(#f #t)])
    (test-group (format "non-flat cancellation: equation ~a outside-first ~a explicit ~a compound ~a"
                        equation? outside-first? explicit? compound?)
      (lambda () (check-nonflat-cancellation equation? outside-first? explicit? compound? #f))))
  (for ([explicit? '(#f #t)])
    (test-group (format "non-flat cancellation: incompatible survivor geometry, explicit ~a" explicit?)
      (lambda () (check-nonflat-cancellation #t #t explicit? #t #t))))
  (test-group "additive cancellation: hold keeps separated survivors visible"
    check-additive-hold))

(module+ main
  (run-cancellation-source-tests)
  (report!))

(module+ test
  (run-cancellation-source-tests)
  (report!))
