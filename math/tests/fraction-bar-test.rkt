#lang racket/base

;;;
;;; Persistent Fraction-Bar Regression Tests
;;;
;; Exercises semantic fraction-bar preparation, correspondence, and native path
;; choreography with deterministic synthetic geometry rather than TeX rendering.

;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         "check.rkt"
         (submod "native-contract.rkt" support)
         "../main.rkt"
         "../private/native.rkt"
         "../private/prepare.rkt"
         "../private/transition-plan.rkt"
         "../private/typeset.rkt"
         (prefix-in adapter: "../private/animate-adapter.rkt"))

;; Exports
(provide run-fraction-bar-tests)

;;;
;;; Focused Mathematical Plans
;;;

; focused-fraction-solution : derivation?
;;   Holds the persistent division structure while evaluating its numerator.
(define focused-fraction-solution
  (derive (math '(/ (- 17 5) 3) #:id 'fraction-bar-focus)
    [numerator (evaluate #:at (numerator))]
    [quotient (evaluate)]))

; focused-fraction-plan : presentation-plan?
;;   Gives the focused fraction steps ordinary replacement choreography.
(define focused-fraction-plan
  (present focused-fraction-solution
           #:style (math-presentation #:history 'replace #:duration 1
                                      #:pause-between-groups 0)))

; nested-fraction-solution : derivation?
;;   Retains two separate division owners while changing only the inner numerator.
(define nested-fraction-solution
  (derive (math '(/ (/ (- 17 5) 3) 2) #:id 'nested-fraction-bars)
    [inner-numerator (evaluate #:at (at-path '(0 0)))]))

;;;
;;; Prepared-Geometry Helpers
;;;

; fixture-layout : math? -> prepared-layout?
;;   Uses the native-contract typesetter to expose stable semantic token geometry.
(define (fixture-layout state)
  (parameterize ([current-native-loader loader]
                 [current-math-typesetter synthetic-typesetter])
    (typeset-state! state #:foreground "#171B24")))

; fraction-bars : prepared-layout? -> (listof prepared-token?)
;;   Returns the explicit persistent division-bar structural tokens in source order.
(define (fraction-bars layout)
  (filter fraction-bar-token? (prepared-layout-tokens layout)))

; only-fraction-bar : prepared-layout? -> prepared-token?
;;   Requires exactly one division owner in a focused fraction layout.
(define (only-fraction-bar layout)
  (define bars (fraction-bars layout))
  (unless (= (length bars) 1)
    (error 'only-fraction-bar "expected exactly one fraction bar, got ~s" bars))
  (car bars))

; token-index : list? prepared-token? -> exact-nonnegative-integer?
;;   Locates a prepared token by its deterministic object in one ordered layout.
(define (token-index tokens token)
  (for/first ([candidate (in-list tokens)] [index (in-naturals)]
              #:when (equal? candidate token))
    index))

; phase-by-name : presentation-plan? symbol? symbol? -> scheduled-phase?
;;   Finds one authored phase without inferring from elapsed time.
(define (phase-by-name plan name kind)
  (or (findf (lambda (phase)
               (and (equal? (scheduled-phase-step phase) name)
                    (eq? (scheduled-phase-kind phase) kind)))
             (plan-schedule plan))
      (error 'phase-by-name "missing ~a phase for ~a" kind name)))

; phase-clips : scene? scheduled-phase? -> (listof clip?)
;;   Selects native contract clips wholly owned by one scheduled phase.
(define (phase-clips scn phase)
  (filter
   (lambda (clip)
     (and (>= (clip-start clip) (scheduled-phase-start phase))
          (< (clip-start clip)
             (+ (scheduled-phase-start phase) (scheduled-phase-duration phase)))))
   (scene-clips scn)))

; sample-clip : clip? real? -> immutable-hash?
;;   Samples the contract clip's independently animated position, opacity, and path bounds.
(define (sample-clip clip progress)
  (for/hash ([(id start) (in-hash (clip-before clip))])
    (define end (hash-ref (clip-after clip) id start))
    (define p (visual-position start))
    (define q (visual-position end))
    (values
     id
     (struct-copy visual start
       [opacity (+ (visual-opacity start)
                   (* progress (- (visual-opacity end) (visual-opacity start))))]
       [position (point (+ (point-x p) (* progress (- (point-x q) (point-x p))))
                        (+ (point-y p) (* progress (- (point-y q) (point-y p)))))]
       [width (+ (visual-width start)
                 (* progress (- (visual-width end) (visual-width start))))]
       [height (+ (visual-height start)
                  (* progress (- (visual-height end) (visual-height start))))]))))

; phase-sample : scene? scheduled-phase? real? -> immutable-hash?
;;   Samples one requested interior fraction of an authored phase.
(define (phase-sample scn phase fraction)
  (define time
    (+ (scheduled-phase-start phase)
       (* fraction (scheduled-phase-duration phase))))
  (define clip (clip-for-time scn time))
  (unless clip
    (error 'phase-sample "no native clip at ~a" time))
  (sample-clip clip (/ (- time (clip-start clip)) (clip-duration clip))))

; phase-snapshot : scene? scheduled-phase? real? -> immutable-hash?
;;   Samples a phase endpoint directly and every other fraction through its owning clip.
(define (phase-snapshot scn phase fraction)
  (if (= fraction 1)
      (clip-after (last (phase-clips scn phase)))
      (phase-sample scn phase fraction)))

; path-id : immutable-hash? -> symbol?
;;   Requires one fraction-bar path Visual in a focused snapshot.
(define (path-id snapshot)
  (define ids
    (for/list ([(id item) (in-hash snapshot)]
               #:when (eq? (visual-kind item) 'path))
      id))
  (unless (= (length ids) 1)
    (error 'path-id "expected one path Visual, got ~s" ids))
  (car ids))

; between-strictly? : real? real? real? -> boolean?
;;   Reports whether value lies in the open interval between two distinct endpoints.
(define (between-strictly? value start end)
  (< (min start end) value (max start end)))

;;;
;;; Regression Groups
;;;

; run-fraction-bar-tests : -> void?
;;   Checks division-bar preparation, semantic lineage, native morphing, and retirement.
(define (run-fraction-bar-tests)
  (test-group
   "fraction bars: explicit prepared structural role"
   (lambda ()
     (define layout (fixture-layout (math '(/ 12 3))))
     (define bar (only-fraction-bar layout))
     (check-equal (prepared-token-role bar) 'fraction-bar 'fraction-bar-role)
     (check-equal (prepared-token-path bar) '() 'fraction-owner-path)
     (check-true (positive? (prepared-token-width bar)) 'positive-bar-width)
     (check-true (positive? (prepared-token-height bar)) 'positive-bar-height)
     (for ([path '((0) (1))])
       (define token
         (findf (lambda (candidate)
                  (and (equal? (prepared-token-path candidate) path)
                       (not (fraction-bar-token? candidate))))
                (prepared-layout-tokens layout)))
       (check-true token (list 'ordinary-fraction-operand path)))
     (define radical-layout (fixture-layout (math '(sqrt x))))
     (define radical-structure
       (findf (lambda (token)
                (and (equal? (prepared-token-path token) '())
                     (eq? (prepared-token-role token) 'structure)))
              (prepared-layout-tokens radical-layout)))
     (check-true radical-structure 'sqrt-remains-structure)
     (check-false (fraction-bar-token? radical-structure) 'sqrt-is-not-fraction-bar)))
  (test-group
   "fraction bars: semantic rewrite lineage preserves each division owner"
   (lambda ()
     (define step (derivation-step focused-fraction-solution 'numerator))
     (define old-layout (fixture-layout (rewrite-step-before step)))
     (define new-layout (fixture-layout (rewrite-step-after step)))
     (define old (prepared-layout-tokens old-layout))
     (define new (prepared-layout-tokens new-layout))
     (define transition (plan-token-transition step old new))
     (define source-bar (only-fraction-bar old-layout))
     (define target-bar (only-fraction-bar new-layout))
     (define source-index (token-index old source-bar))
     (define target-index (token-index new target-bar))
     (define match
       (findf (lambda (entry)
                (and (= (token-match-source entry) source-index)
                     (= (token-match-target entry) target-index)))
              (token-transition-matches transition)))
     (check-true match 'persistent-fraction-bar-match)
     (check-false (member source-index (token-transition-outgoing transition))
                  'persistent-bar-never-retires)
     (check-false (member target-index (token-transition-incoming transition))
                  'persistent-bar-never-reappears)
     (define nested-step (derivation-step nested-fraction-solution 'inner-numerator))
     (define nested-old (fixture-layout (rewrite-step-before nested-step)))
     (define nested-new (fixture-layout (rewrite-step-after nested-step)))
     (define nested-transition
       (plan-token-transition nested-step
                              (prepared-layout-tokens nested-old)
                              (prepared-layout-tokens nested-new)))
     (check-equal (length (fraction-bars nested-old)) 2 'two-source-division-owners)
     (check-equal (length (fraction-bars nested-new)) 2 'two-target-division-owners)
     (for ([target (in-list (fraction-bars nested-new))])
       (define target-index (token-index (prepared-layout-tokens nested-new) target))
       (define entry
         (findf (lambda (candidate) (= (token-match-target candidate) target-index))
                (token-transition-matches nested-transition)))
       (check-true entry (list 'nested-fraction-bar-matched (prepared-token-path target)))
       (check-equal
        (prepared-token-path
         (list-ref (prepared-layout-tokens nested-old) (token-match-source entry)))
        (prepared-token-path target)
        'nested-bars-never-cross-match))))
  (test-group
   "fraction bars: native path morph remains continuous through the checkpoint"
   (lambda ()
     (parameterize ([current-native-loader loader]
                    [current-math-typesetter synthetic-typesetter])
       (define prepared (adapter:prepare-math-plan! focused-fraction-plan))
       (define step (derivation-step focused-fraction-solution 'numerator))
       (define old-layout
         (hash-ref (prepared-math-plan-layouts prepared) (rewrite-step-before step)))
       (define new-layout
         (hash-ref (prepared-math-plan-layouts prepared) (rewrite-step-after step)))
       (define old (prepared-layout-tokens old-layout))
       (define new (prepared-layout-tokens new-layout))
       (define transition (plan-token-transition step old new))
       (define source-index (token-index old (only-fraction-bar old-layout)))
       (define target-index (token-index new (only-fraction-bar new-layout)))
       (check-true
        (findf (lambda (entry)
                 (and (= (token-match-source entry) source-index)
                      (= (token-match-target entry) target-index)))
               (token-transition-matches transition))
        'native-plan-keeps-one-bar-correspondence)
       (check-false (member source-index (token-transition-outgoing transition))
                    'native-plan-has-no-old-bar-replacement)
       (check-false (member target-index (token-transition-incoming transition))
                    'native-plan-has-no-new-bar-replacement)
       (define scn (adapter:math-plan->scene! prepared))
       (define phase (phase-by-name focused-fraction-plan 'numerator 'transition))
       (define clips (phase-clips scn phase))
       (check-true (pair? clips) 'fraction-transition-has-native-clips)
       (define start (clip-before (car clips)))
       (define bar-id (path-id start))
       (define source (hash-ref start bar-id))
       (check-equal (visual-kind source) 'path 'fraction-bar-is-native-path)
       (check-equal (cadr (visual-content source))
                    (prepared-math-plan-foreground prepared)
                    'bar-fill-follows-prepared-foreground)
       (define morph-clips
         (filter (lambda (clip)
                   (ormap (lambda (request)
                            (and (eq? (request-kind request) 'morph)
                                 (eq? (request-id request) bar-id)))
                          (clip-requests clip)))
                 clips))
       (check-equal (length morph-clips) 3 'persistent-bar-spans-three-transition-subclips)
       (for ([clip (in-list morph-clips)])
         (check-true
          (ormap (lambda (request)
                   (and (eq? (request-kind request) 'move)
                        (eq? (request-id request) bar-id)))
                 (clip-requests clip))
          'bar-morphs-with-matched-motion))
       (define destination (hash-ref (clip-after (last clips)) bar-id))
       (check-false (= (visual-width source) (visual-width destination))
                    'fixture-requires-width-change)
       (define samples
         (for/list ([fraction '(0 3/20 3/10 9/20 3/5 3/4 9/10 1)])
           (cons fraction (hash-ref (phase-snapshot scn phase fraction) bar-id #f))))
       (for ([sample (in-list samples)])
         (define fraction (car sample))
         (define bar (cdr sample))
         (check-true bar (list 'one-bar-id-through-phase fraction))
         (check-true (positive? (visual-opacity bar))
                     (list 'persistent-bar-visible fraction))
         (check-true (<= (min (visual-height source) (visual-height destination))
                         (visual-height bar)
                         (max (visual-height source) (visual-height destination)))
                     (list 'bar-thickness-interpolates fraction)))
       (for ([earlier (in-list samples)] [later (in-list (cdr samples))])
         (check-true (>= (visual-width (cdr earlier)) (visual-width (cdr later)))
                     (list 'bar-width-never-reverses (car earlier) (car later))))
       (define broad-intermediates
         (for/list ([fraction '(7/20 2/5 9/20 1/2 11/20 3/5 13/20)])
           (hash-ref (phase-snapshot scn phase fraction) bar-id)))
       (for ([bar (in-list broad-intermediates)])
         (check-true (between-strictly? (visual-width bar)
                                        (visual-width source)
                                        (visual-width destination))
                     'bar-morph-has-broad-intermediate-width))
       ;; The old 10% survivor-only policy had not yet begun at 45%; this bar
       ;; is already 3/8 of the way through its 30%-70% transition window.
       (define early-interior (cdr (list-ref samples 3)))
       (check-true (between-strictly? (visual-width early-interior)
                                      (visual-width source)
                                      (visual-width destination))
                   'bar-changes-before-old-survivor-window)
       (define midpoint (hash-ref (phase-snapshot scn phase 1/2) bar-id))
       (check-true (between-strictly? (visual-width midpoint)
                                      (visual-width source)
                                      (visual-width destination))
                   'midpoint-bar-width-is-strictly-interior)
       (for ([fraction '(9/20 3/5)])
         (define bar (hash-ref (phase-snapshot scn phase fraction) bar-id))
         (define progress (/ (- fraction 3/10) 2/5))
         (check-close (point-x (visual-position bar))
                      (+ (point-x (visual-position source))
                         (* progress (- (point-x (visual-position destination))
                                        (point-x (visual-position source)))))
                      1e-8
                      (list 'bar-center-follows-extended-move-x fraction))
         (check-close (point-y (visual-position bar))
                      (+ (point-y (visual-position source))
                         (* progress (- (point-y (visual-position destination))
                                        (point-y (visual-position source)))))
                      1e-8
                      (list 'bar-center-follows-extended-move-y fraction)))
       (define outgoing-ids
         (remove-duplicates
          (for*/list ([clip (in-list clips)] [request (in-list (clip-requests clip))]
                      #:when (and (eq? (request-kind request) 'fade)
                                  (= (request-value request) 0)))
            (request-id request))))
       (define incoming-ids
         (remove-duplicates
          (for*/list ([clip (in-list clips)] [request (in-list (clip-requests clip))]
                      #:when (and (eq? (request-kind request) 'fade)
                                  (= (request-value request) 1)))
            (request-id request))))
       (for* ([clip (in-list clips)] [fraction '(0 1/4 1/2 3/4 1)])
         (define snapshot (sample-clip clip fraction))
         (define old-opacity
           (map (lambda (id) (visual-opacity (hash-ref snapshot id))) outgoing-ids))
         (define new-opacity
           (map (lambda (id) (visual-opacity (hash-ref snapshot id))) incoming-ids))
         (check-true (or (andmap zero? old-opacity) (andmap zero? new-opacity))
                     'fraction-bar-keeps-replacement-visibility-barrier))
       (define phase-end (clip-after (last clips)))
       (define following
         (findf (lambda (clip) (= (clip-start clip)
                                  (+ (scheduled-phase-start phase)
                                     (scheduled-phase-duration phase))))
                (scene-clips scn)))
       (check-true following 'checkpoint-has-following-native-state)
       (define after-checkpoint (clip-before following))
       (define ended-bar (hash-ref phase-end bar-id))
       (define continued-bar (hash-ref after-checkpoint bar-id))
       (check-equal (visual-kind continued-bar) 'path 'checkpoint-keeps-path-bar)
       (check-equal (visual-width continued-bar) (visual-width ended-bar)
                    'checkpoint-has-no-bar-width-jump)
       (check-equal (visual-height continued-bar) (visual-height ended-bar)
                    'checkpoint-has-no-bar-thickness-jump)
       (check-close (point-x (visual-position continued-bar))
                    (point-x (visual-position ended-bar))
                    1e-8
                    'checkpoint-has-no-bar-center-x-jump)
       (check-close (point-y (visual-position continued-bar))
                    (point-y (visual-position ended-bar))
                    1e-8
                    'checkpoint-has-no-bar-center-y-jump)
       (define quotient-step (derivation-step focused-fraction-solution 'quotient))
       (define quotient-old
         (prepared-layout-tokens
          (hash-ref (prepared-math-plan-layouts prepared) (rewrite-step-before quotient-step))))
       (define quotient-new
         (prepared-layout-tokens
          (hash-ref (prepared-math-plan-layouts prepared) (rewrite-step-after quotient-step))))
       (define quotient-transition (plan-token-transition quotient-step quotient-old quotient-new))
       (define quotient-bar-index
         (token-index quotient-old
                      (only-fraction-bar
                       (hash-ref (prepared-math-plan-layouts prepared)
                                 (rewrite-step-before quotient-step)))))
       (check-true (member quotient-bar-index (token-transition-outgoing quotient-transition))
                   'fraction-bar-retires-when-division-disappears)))))

(module+ main
  (run-fraction-bar-tests)
  (report!))

(module+ test
  (run-fraction-bar-tests)
  (report!))
