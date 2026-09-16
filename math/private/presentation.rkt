#lang racket/base

;;;
;;; Presentation Descriptions
;;;
;; Defines immutable presentation policies and exact phase schedules. Native animate
;; remains the only scene and frame-sampling engine.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list append* append-map drop-right last remove-duplicates take)
  (only-in racket/match match-define)
  (only-in racket/math infinite? nan?)
  (for-syntax racket/base)
  "validation.rkt"
  "model.rkt"
  (only-in "transition-plan.rkt" transition-kind)
  "context.rkt"
  "evidence.rkt"
  "derivation.rkt")

;; Exports
(provide
  math-presentation math-presentation? classroom present choreograph
  (struct-out presentation-style) (struct-out presentation-plan) (struct-out plan-segment)
  (struct-out presentation-phase) (struct-out scheduled-phase) (struct-out math-checkpoint)
  plan-checkpoints checkpoint-at plan-schedule plan-duration plan-inspect prepare-space
  reveal-created retire-cancelled retire-removed compact hold transition default-phases
  plan-with-choreography explain-math select-case-plan)

;;;
;;; Data Representation
;;;
(struct presentation-style (anchor history start-group new-parts removed-parts reflow multiplication pause-between-groups duration font-size row-gap max-visible-rows)
  #:transparent)
;; presentation-style is an immutable record. Its fields have the following roles.
;;  - anchor  symbol?  relation or center alignment
;;  - history  symbol?  retained checkpoint policy
;;  - start-group  symbol?  copy or replacement policy
;;  - new-parts  symbol?  validated appearance effect
;;  - removed-parts  symbol?  validated disappearance effect
;;  - reflow  symbol?  staged or simultaneous layout changes
;;  - multiplication  symbol?  school or explicit notation
;;  - pause-between-groups  nonnegative-real?  seconds of reading time after each group
;;  - duration  positive-real?  default step duration in seconds
;;  - font-size  positive-real?  formula size in local world units
;;  - row-gap  positive-real?  requested row separation in world units
;;  - max-visible-rows  exact-positive-integer?  at least two visible rows

; math-presentation? : any/c -> boolean?
;;   Recognizes a validated presentation style.
(define math-presentation?
  presentation-style?)

; enum : symbol? any/c any/c -> void?
;;   Validates an explicitly supported presentation choice.
(define (enum who value values)
  (unless (memq value values) (raise-argument-error who (format "one of ~s" values) value)))

; duration : symbol? any/c [#:zero? any/c] -> void?
;;   Checks a finite phase duration, permitting zero only for an explicit hold.
(define (duration who x #:zero? [allow-zero? #f])
  (unless (and (real? x) (not (nan? x)) (not (infinite? x)) (if allow-zero? (>= x 0) (> x 0)))
    (raise-argument-error who "finite positive duration (nonnegative for holds)" x)))

;;;
;;; Presentation Policy
;;;
; math-presentation : [#:anchor symbol?] [#:history symbol?] [#:start-group symbol?]
;   [#:new-parts symbol?] [#:removed-parts symbol?] [#:reflow symbol?] [#:multiplication
;   symbol?] [#:pause-between-groups nonnegative-real?] [#:duration positive-real?]
;   [#:font-size positive-real?] [#:row-gap positive-real?] [#:max-visible-rows (and/c
;   exact-integer? (>=/c 2))] -> math-presentation?
;;   Constructs validated layout and timing policy with exact rational defaults.
(define (math-presentation
          #:anchor [anchor 'relation]
          #:history [history 'keep-completed-groups]
          #:start-group [start-group 'copy]
          #:new-parts [new-parts 'fade]
          #:removed-parts [removed-parts 'fade]
          #:reflow [reflow 'staged]
          #:multiplication [multiplication 'school]
          #:pause-between-groups [pause 3/5]
          #:duration [step-duration 4/5]
          #:font-size [font-size 11/20]
          #:row-gap [row-gap 21/20]
          #:max-visible-rows [max-rows 5])
  (enum 'math-presentation anchor '(relation center))
  (enum 'math-presentation history '(keep-completed-groups keep-all-checkpoints replace))
  (enum 'math-presentation start-group '(copy replace))
  (enum 'math-presentation new-parts '(fade))
  (enum 'math-presentation removed-parts '(fade))
  (enum 'math-presentation reflow '(staged simultaneous))
  (enum 'math-presentation multiplication '(school explicit))
  (duration 'math-presentation pause #:zero? #t)
  (duration 'math-presentation step-duration)
  (duration 'math-presentation font-size)
  (duration 'math-presentation row-gap)
  (unless (and (exact-integer? max-rows) (>= max-rows 2))
    (raise-argument-error 'math-presentation "maximum visible rows >= 2" max-rows))
  (presentation-style anchor history start-group new-parts removed-parts reflow multiplication pause step-duration font-size row-gap max-rows))

; classroom : math-presentation?
;;   Provides the exact-time, staged, retained-history classroom style.
(define classroom
  (math-presentation))

;;;
;;; Phase Descriptions
;;;
(struct presentation-phase (kind duration effect layout annotation)
  #:transparent)
;; presentation-phase is an immutable record. Its fields have the following roles.
;;  - kind  symbol?  phase behavior
;;  - duration  nonnegative-real?  seconds; zero allowed only for an explicit hold
;;  - effect  symbol?  fade, move, or none
;;  - layout  symbol?  held or destination layout
;;  - annotation  (or/c #f (list/c math? immutable-string?))  independent held explanation and caption

; phase : any/c math-datum? symbol? symbol? -> presentation-phase?
;;   Constructs an immutable phase description with validated timing.
(define (phase kind d effect layout)
  (duration kind d #:zero? (eq? kind 'hold))
  (presentation-phase kind d effect layout #f))

; prepare-space : [#:duration positive-real?] -> presentation-phase?
;;   Moves preserved material to reserve space before revealing new parts.
(define (prepare-space #:duration [d 1/2])
  (phase 'prepare-space d 'move 'destination))

; reveal-created : [#:effect symbol?] [#:duration positive-real?] -> presentation-phase?
;;   Fades in newly introduced material after space has been prepared.
(define (reveal-created #:effect [effect 'fade] #:duration [d 2/5])
  (enum 'reveal-created effect '(fade))
  (phase 'reveal-created d effect 'hold))

; retire-cancelled : [#:effect symbol?] [#:layout symbol?] [#:duration positive-real?]
;   -> presentation-phase?
;;   Fades cancelled material while holding the surrounding layout fixed.
(define (retire-cancelled
          #:effect [effect 'fade]
          #:layout [layout 'hold]
          #:duration [d 2/5])
  (enum 'retire-cancelled effect '(fade))
  (enum 'retire-cancelled layout '(hold))
  (phase 'retire-cancelled d effect layout))

; retire-removed : [#:effect symbol?] [#:layout symbol?] [#:duration positive-real?] ->
;   presentation-phase?
;;   Fades removed material while holding the surrounding layout fixed.
(define (retire-removed #:effect [effect 'fade] #:layout [layout 'hold] #:duration [d 2/5])
  (enum 'retire-removed effect '(fade))
  (enum 'retire-removed layout '(hold))
  (phase 'retire-removed d effect layout))

; compact : [#:duration positive-real?] -> presentation-phase?
;;   Closes reserved gaps by moving survivors to their prepared positions.
(define (compact #:duration [d 2/5])
  (phase 'compact d 'move 'destination))

; hold : nonnegative-real? -> presentation-phase?
;;   Retains the current presentation state for a nonnegative duration.
(define (hold d)
  (phase 'hold d 'none 'hold))

; transition : [#:duration positive-real?] -> presentation-phase?
;;   Replaces one complete semantic unit through a retire/move/reveal visibility barrier.
(define (transition #:duration [d 4/5])
  (phase 'transition d 'fade 'destination))

; explain-math : (or/c math? math-datum?) [#:caption string?] [#:duration positive-real?] -> presentation-phase?
;;   Shows an independent mathematical inset without changing the derivation checkpoint.
(define (explain-math expression #:caption [caption ""] #:duration [seconds 2])
  (duration 'explain-math seconds)
  (unless (string? caption) (raise-argument-error 'explain-math "string? as #:caption" caption))
  (when (regexp-match? #rx"[\r\n]" caption)
    (raise-argument-error 'explain-math "single-line caption" caption))
  (define state (if (math? expression) expression (math expression #:id 'explanation)))
  (presentation-phase 'explain seconds 'fade 'hold
                      (list state (string->immutable-string caption))))

;;;
;;; Plan Descriptions
;;;
(struct plan-segment (path derivation groups context verdict shared?)
  #:transparent)
;; plan-segment is an immutable record. Its fields have the following roles.
;;  - path  (listof symbol?)  case path in declared branch order
;;  - derivation  derivation?  this segment's complete path, shared prefix, or branch suffix
;;  - groups  list?  ordered partition of canonical elementary keys (symbol or symbol path)
;;  - context  math-context?  context displayed with this segment
;;  - verdict  (or/c verification? #f)  optional candidate-check report
;;  - shared?  boolean?  whether this is a once-presented shared prefix, not a terminal case
(struct presentation-plan (source style segments choreography allow-unverified?)
  #:transparent)
;; presentation-plan is an immutable record. Its fields have the following roles.
;;  - source  any/c  original derivation, cases, or candidate check
;;  - style  math-presentation?  validated immutable presentation policy
;;  - segments  (listof plan-segment?)  chronological branch presentations
;;  - choreography  immutable-hash?  step or case-step keys to ordered phase lists
;;  - allow-unverified?  boolean?  whether a visible draft warning is required
(struct scheduled-phase (segment step kind start duration group phase)
  #:transparent)
;; scheduled-phase is an immutable record. Its fields have the following roles.
;;  - segment  exact-nonnegative-integer?  zero-based segment index
;;  - step  (or/c symbol? list? #f)  relative leaf key, or false for group/segment phases
;;  - kind  symbol?  scheduled phase category
;;  - start  nonnegative-real?  absolute start time in seconds
;;  - duration  nonnegative-real?  phase duration in seconds
;;  - group  exact-integer?  group index; minus one before the first group
;;  - phase  (or/c presentation-phase? #f)  explicit effect description when applicable

; all-leaves : any/c [operand-path?] [any/c] -> list?
;;   Collects case leaves with their shared mathematical prefixes in declared order.
(define (all-leaves source [path '()] [prefix #f])
  (cond
    [(derivation? source)
     (define d
       (if prefix
         (derivation-append prefix source)
         source))
     (list (list path d (math-context-of (after source))))]
    [(case-derivation? source)
     (define p (case-derivation-prefix source))
     (define combined
       (if prefix
         (derivation-append prefix p)
         p))
     (append-map
       (lambda (b)
         (all-leaves
           (case-branch-derivation b)
           (append path (list (case-branch-name b)))
           combined))
       (case-derivation-branches source))]
    [else (raise-argument-error 'present "derivation or case derivation" source)]))

; shared-segments : any/c [operand-path?] -> list?
;;   Traverses the case tree without replaying the shared derivation in each leaf.
(define (shared-segments source [path '()])
  (cond
    [(derivation? source)
     (list (list path source (math-context-of (derivation-initial source)) #f))]
    [(case-derivation? source)
     (define prefix (case-derivation-prefix source))
     (append
       (if (null? (derivation-steps prefix)) '()
           (list (list path prefix (math-context-of (derivation-initial prefix)) #t)))
       (append-map
         (lambda (branch)
           (shared-segments (case-branch-derivation branch)
                            (append path (list (case-branch-name branch)))))
         (case-derivation-branches source)))]
    [else (raise-argument-error 'present "derivation or case derivation" source)]))

; path-ancestor? : list? list? -> boolean?
;;   Tests case-path ancestry without interpreting sibling step names.
(define (path-ancestor? parent child)
  (and (<= (length parent) (length child))
       (equal? parent (take child (length parent)))))

; project-groups : list? derivation? -> list?
;;   Restricts complete-path groups to the steps owned by one chronological segment.
(define (project-groups groups d)
  (define names (derivation-step-keys d))
  (filter pair? (map (lambda (g) (filter (lambda (n) (member n names)) g)) groups)))

; validate-groups : derivation? (or/c list? symbol? #f) -> list?
;;   Expands move references to an exact chronological partition of elementary steps.
(define (validate-groups d groups)
  (define names (derivation-step-keys d))
  (define (keys-under node)
    (map (lambda (leaf) (derivation-step-key d (derivation-node-step leaf)))
         (node-leaf-nodes node)))
  (define actual
    (cond
      [(or (not groups) (eq? groups 'top-level))
       (map keys-under (derivation-tree d))]
      [(eq? groups 'steps) (map list names)]
      [(and (list? groups)
            (andmap (lambda (group) (and (list? group) (pair? group))) groups))
       (for/list ([group (in-list groups)])
         (append-map (lambda (reference) (keys-under (derivation-node-at d reference))) group))]
      [else
       (math-error 'present 'invalid-groups
                   "Expected 'top-level, 'steps, or ordered nonempty presentation groups."
                   groups)]))
  (unless (equal? (append* actual) names)
    (math-error 'present 'invalid-groups
      "Presentation groups must partition all steps exactly once, in order."
      names actual))
  actual)

;;;
;;; Plan Construction
;;;
; present : (or/c derivation? case-derivation? solution-check?) [#:style
;   math-presentation?] [#:groups (or/c 'top-level 'steps list? hash? #f)] [#:case (or/c symbol? (listof
;   symbol?) #f)] [#:case-layout (or/c 'complete-paths 'shared-prefix)]
;   [#:allow-unverified? boolean?] -> presentation-plan?
;;   Builds an explicit presentation while retaining verification status and case
;;   context.
(define (present source
          #:style [style classroom]
          #:groups [groups #f]
          #:case [case-path #f]
          #:case-layout [case-layout 'complete-paths]
          #:allow-unverified? [allow? #f])
  (enum 'present case-layout '(complete-paths shared-prefix))
  (check-boolean 'present allow?)
  (unless (or
            (not case-path)
            (symbol? case-path)
            (and (list? case-path) (andmap symbol? case-path)))
    (raise-argument-error 'present "symbol, list of symbols, or #f as #:case" case-path))
  (unless (presentation-style? style)
    (raise-argument-error 'present "math-presentation?" style))
  (define verdict (and (solution-check? source) (solution-check-verification source)))
  (define d (if (solution-check? source) (solution-check-derivation source) source))
  (unless d
    (math-error 'present 'undefined-candidate
      "The candidate is not established to be in the original domain."
      verdict))
  (define check (derivation-verification d))
  (unless (or allow? (eq? (verification-status check) 'established))
    (math-error 'present 'unverified-derivation
      "An unverified derivation needs #:allow-unverified? #t and a visible warning."
      (verification-obligations check)))
  (define leaves (all-leaves d))
  (when (hash? groups)
    (for ([key (in-hash-keys groups)])
      (unless (member key (map car leaves))
        (math-error 'present 'missing-case
                    "Group table contains an unknown case path." key))))
  (define wanted (and case-path (if (symbol? case-path) (list case-path) case-path)))
  (define chosen
    (if wanted (filter (lambda (leaf) (equal? (car leaf) wanted)) leaves) leaves))
  (when (null? chosen) (math-error 'present 'missing-case "No such case path." wanted))
  ;; Validate authored groups against complete mathematical paths first. This
  ;; retains the existing group contract even when presentation shares a prefix.
  (define leaf-groups
    (for/hash ([leaf (in-list chosen)])
      (match-define (list path body ctx) leaf)
      (define gs
        (cond
          [(hash? groups) (hash-ref groups path #f)]
          [(or (not groups) (memq groups '(top-level steps))) groups]
          [(= (length chosen) 1) groups]
          [groups (math-error 'present 'branch-groups
                              "For multiple cases use a hash from case paths to group lists.")]
          [else #f]))
      (values path (validate-groups body gs))))
  (define shared? (and (eq? case-layout 'shared-prefix) (not wanted)))
  (define candidates
    (if shared? (shared-segments d)
        (map (lambda (leaf) (append leaf (list #f))) chosen)))
  (define segments
    (for/list ([entry (in-list candidates)])
      (match-define (list path body ctx prefix?) entry)
      (define alternatives
        (for/list ([leaf (in-list chosen)] #:when (path-ancestor? path (car leaf)))
          (project-groups (hash-ref leaf-groups (car leaf)) body)))
      (define gs (if (null? alternatives) '() (car alternatives)))
      (unless (andmap (lambda (g) (equal? gs g)) alternatives)
        (math-error 'present 'conflicting-prefix-groups
                    "Shared prefix groups must agree across descendant cases." path))
      (plan-segment path body (validate-groups body gs) ctx verdict prefix?)))
  (presentation-plan source style segments (hash) allow?))

; select-case-plan : presentation-plan? (listof symbol?) -> presentation-plan?
;;   Restores the complete mathematical prefix for a stand-alone selected case.
(define (select-case-plan plan case-path)
  (define selected
    (findf (lambda (s) (and (equal? case-path (plan-segment-path s))
                            (not (plan-segment-shared? s))))
           (presentation-plan-segments plan)))
  (unless selected (math-error 'select-case-plan 'missing-case "No terminal case has this path." case-path))
  (define related
    (filter (lambda (s) (or (eq? s selected)
                            (and (plan-segment-shared? s)
                                 (path-ancestor? (plan-segment-path s) case-path))))
            (presentation-plan-segments plan)))
  (define complete
    (present (presentation-plan-source plan)
             #:style (presentation-plan-style plan)
             #:groups (append-map plan-segment-groups related)
             #:case case-path
             #:allow-unverified? (presentation-plan-allow-unverified? plan)))
  ;; Rebind resolved phases, including shared-prefix overrides, to the selected
  ;; complete path. No orphaned sibling-case override is retained.
  (define choreography
    (for*/hash ([segment (in-list related)]
                [step (in-list (derivation-steps (plan-segment-derivation segment)))])
      (define path
        (derivation-node-path
         (derivation-node-at (plan-segment-derivation segment)
                             (derivation-step-key (plan-segment-derivation segment) step))))
      (values (append case-path path) (step-phases plan segment step))))
  (struct-copy presentation-plan complete [choreography choreography]))

;;;
;;; Choreography Overrides
;;;
; choreography-targets : presentation-plan? -> list?
;;   Lists case and derivation-relative leaf addresses in displayed execution order.
(define (choreography-targets plan)
  (remove-duplicates
   (append-map
    (lambda (segment)
      (map (lambda (path) (list (plan-segment-path segment) path))
           (derivation-step-paths (plan-segment-derivation segment))))
    (presentation-plan-segments plan))))

; resolve-choreography-targets : presentation-plan? (or/c symbol? list?) -> list?
;;   Validates unambiguous shorthand, relative paths, or fully case-qualified leaf paths.
(define (resolve-choreography-targets plan key)
  (define targets (choreography-targets plan))
  (define selected
    (cond
      [(symbol? key)
       (define matches (filter (lambda (target) (eq? key (last (cadr target)))) targets))
       (when (> (length (remove-duplicates (map cadr matches))) 1)
         (math-error 'choreograph 'ambiguous-step
                     "Ambiguous step name; use a complete hierarchical path." key matches))
       matches]
      [else
       (define absolute
         (filter (lambda (target) (equal? key (append (car target) (cadr target)))) targets))
       (define relative (filter (lambda (target) (equal? key (cadr target))) targets))
       (when (and (pair? absolute) (pair? relative) (not (equal? absolute relative)))
         (math-error 'choreograph 'ambiguous-step
                     "Address is both case-qualified and derivation-relative; rename the conflicting scope."
                     key))
       (if (pair? absolute) absolute relative)]))
  (when (null? selected)
    (math-error 'choreograph 'missing-step
                "Unknown elementary step name or path; a composite move is not a phase target." key))
  selected)

; plan-with-choreography : presentation-plan? list? -> presentation-plan?
;;   Validates leaf phase overrides; case paths override relative paths and local shorthand.
(define (plan-with-choreography plan overrides)
  (unless (presentation-plan? plan)
    (raise-argument-error 'plan-with-choreography "presentation-plan?" plan))
  (unless (and (list? overrides)
               (andmap (lambda (entry)
                         (and (list? entry) (pair? entry)
                              (or (symbol? (car entry))
                                  (and (list? (car entry)) (pair? (car entry))
                                       (andmap symbol? (car entry))))))
                       overrides))
    (raise-argument-error 'plan-with-choreography "list of named phase lists" overrides))
  (define keys (map car overrides))
  (unless (= (length keys) (length (remove-duplicates keys)))
    (math-error 'choreograph 'duplicate-step "Each override may name a step only once." keys))
  (define table
    (for/fold ([table (presentation-plan-choreography plan)]) ([entry (in-list overrides)])
      (define key (car entry))
      (resolve-choreography-targets plan key)
      (unless (and (pair? (cdr entry)) (andmap presentation-phase? (cdr entry)))
        (raise-argument-error 'choreograph "nonempty phase list" (cdr entry)))
      (hash-set table key (for/list ([phase (in-list (cdr entry))]) phase))))
  (struct-copy presentation-plan plan [choreography table]))

; choreograph : syntax -> syntax
;;   Captures named phase clauses without changing the mathematical derivation.
(define-syntax-rule (choreograph plan [name phase ...] ...)
  (plan-with-choreography plan (list (cons 'name (list phase ...)) ...)))

; default-phases : rewrite-step? math-presentation? -> (listof presentation-phase?)
;;   Selects staged or simultaneous phases from the operation and style.
(define (default-phases step style)
  (define d (presentation-style-duration style))
  (define kind (transition-kind step))
  (cond
    [(memq kind '(split copy reorder))
     (list (retire-removed #:duration (* 1/4 d))
           (compact #:duration (* 1/2 d))
           (reveal-created #:duration (* 1/4 d)))]
    [(eq? (presentation-style-reflow style) 'simultaneous)
     (list (transition #:duration d))]
    [(eq? kind 'introduction)
     (list (prepare-space #:duration (* 11/20 d)) (reveal-created #:duration (* 9/20 d)))]
    [(eq? kind 'cancellation)
     (list (retire-cancelled #:duration (* 9/20 d))
           (hold 3/10)
           (compact #:duration (* 11/20 d)))]
    [else (list (transition #:duration d))]))

; step-phases : presentation-plan? plan-segment? rewrite-step? -> list?
;;   Resolves case-qualified paths, relative paths, local-name shorthand, then defaults.
(define (step-phases plan segment step)
  (define d (plan-segment-derivation segment))
  (define key (derivation-step-key d step))
  (define path (if (symbol? key) (list key) key))
  (define table (presentation-plan-choreography plan))
  (define found
    (for/or ([candidate (in-list (list (append (plan-segment-path segment) path)
                                      path (rewrite-step-name step)))])
      (hash-ref table candidate #f)))
  (or found (default-phases step (presentation-plan-style plan))))

;;;
;;; Exact Phase Schedules
;;;
; plan-schedule : presentation-plan? -> (listof scheduled-phase?)
;;   Computes an ordered exact-time phase schedule without creating native scenes.
(define (plan-schedule plan)
  (define time 0)
  (define result '())
  (define style (presentation-plan-style plan))
  (define (add segment label kind d group [phase #f])
    (set! result (cons (scheduled-phase segment label kind time d group phase) result))
    (set! time (+ time d)))
  (for ([segment (in-list (presentation-plan-segments plan))] [segment-index (in-naturals)])
    (add segment-index #f 'show-initial 4/5 -1)
    (define d (plan-segment-derivation segment))
    (define groups
      (if (eq? (presentation-style-history style) 'keep-all-checkpoints)
        (map list (derivation-step-keys d))
        (plan-segment-groups segment)))
    (for ([group (in-list groups)] [g (in-naturals)])
      (define case-handoff-reuse?
        (and (zero? g)
             (pair? (plan-segment-path segment))
             (not (plan-segment-shared? segment))))
      (when (and
              (not case-handoff-reuse?)
              (not (eq? (presentation-style-history style) 'replace))
              (eq? (presentation-style-start-group style) 'copy))
        (add segment-index #f 'copy-group 1/2 g))
      (for ([name (in-list group)])
        (define step (derivation-step d name))
        (for ([p (in-list (step-phases plan segment step))])
          (add segment-index name
            (presentation-phase-kind p)
            (presentation-phase-duration p)
            g
            p))
        (add segment-index name 'checkpoint 0 g))
      (add segment-index #f 'group-pause (presentation-style-pause-between-groups style) g))
    (add segment-index #f 'segment-pause 1 (length groups)))
  (reverse result))

; plan-duration : presentation-plan? -> nonnegative-real?
;;   Sums the phase durations in seconds; exact inputs retain exactness.
(define (plan-duration plan)
  (for/sum ([p (in-list (plan-schedule plan))]) (scheduled-phase-duration p)))

; plan-inspect : presentation-plan? nonnegative-real? -> scheduled-phase?
;;   Selects a half-open phase interval, with the final endpoint handled explicitly.
(define (plan-inspect plan t)
  (unless (and (real? t) (>= t 0) (<= t (plan-duration plan)))
    (raise-argument-error 'plan-inspect "time within the plan" t))
  (define matches
    (filter
      (lambda (p)
        (and
          (<= (scheduled-phase-start p) t)
          (< t (+ (scheduled-phase-start p) (scheduled-phase-duration p)))))
      (plan-schedule plan)))
  (if (pair? matches) (car matches) (last (plan-schedule plan))))

;; Checkpoints are immutable authoring data; native scenes store only their
;; numeric indices because animate scene values have an interpolation contract.

;;;
;;; Mathematical Checkpoints
;;;
(struct math-checkpoint (index segment step time state case-path)
  #:transparent)
;; math-checkpoint is an immutable record. Its fields have the following roles.
;;  - index  exact-nonnegative-integer?  stable chronological checkpoint index
;;  - segment  exact-nonnegative-integer?  owning segment index
;;  - step  (or/c symbol? list? #f)  committed relative leaf key, or false for initial state
;;  - time  nonnegative-real?  absolute commit time in seconds
;;  - state  math?  committed mathematical state
;;  - case-path  (listof symbol?)  owning case path

; plan-checkpoints : presentation-plan? -> immutable-vector?
;;   Assigns deterministic checkpoint indices in chronological plan order.
(define (plan-checkpoints plan)
  (define index -1)
  (vector->immutable-vector
    (list->vector
      (for/list ([phase (in-list (plan-schedule plan))]
                  #:when (memq (scheduled-phase-kind phase) '(show-initial checkpoint)))
        (set! index (add1 index))
        (define segment
          (list-ref (presentation-plan-segments plan) (scheduled-phase-segment phase)))
        (define d (plan-segment-derivation segment))
        (define name (scheduled-phase-step phase))
        (math-checkpoint index
          (scheduled-phase-segment phase)
          name
          (scheduled-phase-start phase)
          (if name (after d name) (derivation-initial d))
          (plan-segment-path segment))))))

; checkpoint-at : presentation-plan? nonnegative-real? -> math-checkpoint?
;;   Returns the latest committed mathematical checkpoint at the requested time.
(define (checkpoint-at plan time)
  (plan-inspect plan time)
  ; validates range
  (for/fold ([last #f]) ([c (in-vector (plan-checkpoints plan))]
              #:when (<= (math-checkpoint-time c) time))
    c))
