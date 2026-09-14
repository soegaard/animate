#lang racket/base

;;;
;;; Native Mathematical Scene Compilation
;;;
;; Lowers prepared lesson phases to ordinary animate movements, fades, and waits.
;; Mathematical queries and typesetting never run during frame sampling.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list append-map take-right remove-duplicates)
  (only-in racket/match match)
  (only-in racket/string string-join)
  "native.rkt"
  "validation.rkt"
  "typeset.rkt"
  "prepare.rkt"
  "token-layout.rkt"
  "transition-plan.rkt"
  "datum.rkt"
  "model.rkt"
  "context.rkt"
  "evidence.rkt"
  "derivation.rkt"
  "presentation.rkt"
  "format.rkt")

;; Exports
(provide
  math-plan->scene! prepare-math-plan! math->visual! math-plan->pict!
  (struct-out prepared-math-plan) matching-token-index)

;;;
;;; Construction and Operations
;;;
; animate-binding : symbol? -> any/c
;;   Resolves a native animate binding at the adapter boundary.
(define (animate-binding name)
  (native 'animate name))

; add-tokens : scene? (listof prepared-token?) [#:opacity (real-in 0 1)] -> scene?
;;   Updates native scene presence in the explicit token order.
(define (add-tokens scn tokens #:opacity [opacity 1])
  (apply
    (animate-binding 'scene-add)
    scn
    (map (lambda (t) (token-visual t #:opacity opacity)) tokens)))

; remove-tokens : scene? (listof prepared-token?) -> scene?
;;   Updates native scene presence in the explicit token order.
(define (remove-tokens scn tokens)
  (if (null? tokens)
    scn
    (apply (animate-binding 'scene-remove) scn (map prepared-token-id tokens))))

; play : scene? any/c positive-real? -> scene?
;;   Compiles ordinary native requests or a native wait for the requested duration.
(define (play scn requests seconds)
  (cond
    [(<= seconds 0) scn]
    [(null? requests) ((animate-binding 'scene-wait) scn seconds)]
    [else
     (keyword-apply
       (animate-binding 'scene-play)
       '(#:duration)
       (list seconds)
       (cons scn requests))]))

; move-request : prepared-token? -> any/c
;;   Constructs an ordinary native animation request for one prepared part.
(define (move-request t)
  ((animate-binding 'move-to)
    (prepared-token-id t)
    ((animate-binding 'vec2) (prepared-token-x t) (prepared-token-y t))))

; fade-request : prepared-token? (real-in 0 1) -> any/c
;;   Constructs an ordinary native animation request for one prepared part.
(define (fade-request t opacity)
  ((animate-binding 'fade-to) (prepared-token-id t) opacity))

; pretty : any/c -> string?
;;   Formats context captions independently of the mathematical formula source.
(define (pretty x)
  (match x
    [(? symbol?) (symbol->string x)]
    [(? number?) (number->string x)]
    [(list 'not (list '= a b)) (format "~a ≠ ~a" (pretty a) (pretty b))]
    [(list '= a b) (format "~a = ~a" (pretty a) (pretty b))]
    [(list (and op (or '< '> '<= '>=)) a b)
     (format "~a ~a ~a"
       (pretty a)
       (case op [(<=) "≤"] [(>=) "≥"] [else (symbol->string op)])
       (pretty b))]
    [(list (and op (or 'and 'or)) vs ...)
     (string-join (map pretty vs) (if (eq? op 'and) "; " " or "))]
    [(list '+ vs ...) (string-join (map pretty vs) " + ")]
    [(list '- a b) (format "~a − ~a" (pretty a) (pretty b))]
    [(list '- a) (format "−~a" (pretty a))]
    [(list '* vs ...) (string-join (map pretty vs) "·")]
    [(list 'expt a 2) (format "~a²" (pretty a))]
    [else (format "~s" x)]))

; compile-explanation : scene? prepared-math-plan? presentation-phase? symbol? -> scene?
;;   Places a separately prepared inset in the reserved lower band and removes it afterward.
(define (compile-explanation scn prepared phase id)
  (define annotation (presentation-phase-annotation phase))
  (define state (car annotation))
  (define caption (cadr annotation))
  (define camera (prepared-math-plan-camera prepared))
  (define height (* ((animate-binding 'camera-world-width) camera)
                    (/ ((animate-binding 'camera-height) camera)
                       ((animate-binding 'camera-width) camera))))
  (define raw
    (prepared-layout-tokens (hash-ref (prepared-math-plan-layouts prepared) state)))
  (define ink-width
    (- (apply max (map (lambda (t) (+ (prepared-token-x t) (/ (prepared-token-width t) 2))) raw))
       (apply min (map (lambda (t) (- (prepared-token-x t) (/ (prepared-token-width t) 2))) raw))))
  (define ink-height
    (- (apply max (map (lambda (t) (+ (prepared-token-y t) (/ (prepared-token-height t) 2))) raw))
       (apply min (map (lambda (t) (- (prepared-token-y t) (/ (prepared-token-height t) 2))) raw))))
  (define inset-scale
    (min 7/10 (/ 4/5 ink-height)
         (/ (- ((animate-binding 'camera-world-width) camera) 6/5) ink-width)))
  (define ink
    (clone-view (map (lambda (t) (token-scaled t inset-scale)) raw) id 'explanation))
  (define-values (cx cy) (token-center ink))
  (define tokens (translate ink (- cx) (- (+ (- (/ height 2)) 9/10) cy)))
  (define caption-id (string->symbol (format "~a.explanation-caption" id)))
  (define scene-with-caption
    (if (string=? caption "") scn
        ((animate-binding 'scene-add) scn
          ((animate-binding 'plain-text) caption #:id caption-id
            #:center ((animate-binding 'vec2) 0 (+ (- (/ height 2)) 3/10))
            #:font-size (min 1/5
                             (/ (- ((animate-binding 'camera-world-width) camera) 6/5)
                                (max 1 (* 14/25 (string-length caption)))))
            #:color (prepared-math-plan-foreground prepared)))))
  (define seconds (presentation-phase-duration phase))
  (define shown (play (add-tokens scene-with-caption tokens #:opacity 0)
                      (map (lambda (t) (fade-request t 1)) tokens) (/ seconds 5)))
  (define held (play shown '() (* 3/5 seconds)))
  (define hidden (play held (map (lambda (t) (fade-request t 0)) tokens) (/ seconds 5)))
  (define cleaned (remove-tokens hidden tokens))
  (if (string=? caption "") cleaned ((animate-binding 'scene-remove) cleaned caption-id)))

;;;
;;; One-Step Native Compilation
;;;
; compile-math-step : scene? prepared-math-plan? integer? rewrite-step? list? list? symbol? any/c ->
;   (values scene? list? exact-nonnegative-integer?)
;;   Lowers typed semantic units to native batches, with a visibility barrier for replacements.
(define (compile-math-step scn prepared segment-index step destination old id view)
  (define name (rewrite-step-name step))
  (define unit-plan (plan-token-transition step old destination))
  (define kind (token-transition-kind unit-plan))
  (define matches (token-transition-matches unit-plan))
  (define split? (eq? kind 'split))
  (define used (make-hash))
  (define ghosts '())
  (define next
    (for/list ([token (in-list destination)] [i (in-naturals)])
      (define matched (findf (lambda (m) (= i (token-match-target m))) matches))
      (cond
        [split?
         ;; Branch copies must coexist briefly with their source, so every
         ;; destination token receives a fresh view identity at its final position.
         (token-with-id token (string->symbol (format "~a.branch~a.~a" id view i)))]
        [matched
         (define source-index (token-match-source matched))
         (define source (list-ref old source-index))
         (define key
           (if (hash-has-key? used source-index)
               (let ([copy-id (string->symbol (format "~a.copy~a.~a" id view i))])
                 (set! ghosts (append ghosts (list (token-with-id source copy-id))))
                 copy-id)
               (begin (hash-set! used source-index #t) (prepared-token-id source))))
         (token-with-id token key)]
        [else (token-with-id token (string->symbol (format "~a.new~a.~a" id view i)))])))
  (define matched-target-indices
    (remove-duplicates (map token-match-target matches)))
  (define split-copies
    (if split?
        (map (lambda (i) (list-ref next i)) matched-target-indices)
        '()))
  (define retired
    (if split?
        old
        (map (lambda (i) (list-ref old i)) (token-transition-outgoing unit-plan))))
  (define created
    (map (lambda (i) (list-ref next i)) (token-transition-incoming unit-plan)))
  ;; Equal mathematical subtrees move as rigid blocks except at a branch split.
  ;; Split copies are placed invisibly at their final locations and revealed there,
  ;; avoiding crossed source trajectories while preserving semantic copy evidence.
  (define units (remove-duplicates (map token-match-unit matches) equal?))
  (define moving
    (if split?
        '()
        (append-map
         (lambda (unit)
           (define ms (filter (lambda (m) (equal? unit (token-match-unit m))) matches))
           (define from (map (lambda (m) (list-ref old (token-match-source m))) ms))
           (define to (map (lambda (m) (list-ref next (token-match-target m))) ms))
           (define-values (sx sy) (token-center from))
           (define-values (tx ty) (token-center to))
           (for/list ([a (in-list from)] [b (in-list to)])
             (token-with-position (token-with-id a (prepared-token-id b))
                                  (+ (prepared-token-x a) (- tx sx))
                                  (+ (prepared-token-y a) (- ty sy)))))
         units)))
  (define starts
    (if split?
        '()
        (for/list ([m (in-list matches)])
          (token-with-id (list-ref old (token-match-source m))
                         (prepared-token-id (list-ref next (token-match-target m)))))))
  (set! scn (add-tokens scn ghosts))
  (set! scn (add-tokens scn split-copies #:opacity 0))
  (set! scn (add-tokens scn created #:opacity 0))
  (define entries
    (filter (lambda (p)
              (and (= (scheduled-phase-segment p) segment-index)
                   (eq? (scheduled-phase-step p) name)
                   (not (eq? (scheduled-phase-kind p) 'checkpoint))))
            (prepared-math-plan-schedule prepared)))
  (define kinds (map scheduled-phase-kind entries))
  (when (and (pair? retired)
             (not (ormap (lambda (k) (memq k '(retire-cancelled retire-removed transition))) kinds)))
    (math-error 'choreograph 'incomplete-choreography "The phases never retire outgoing parts." name))
  (when (and (pair? created)
             (not (ormap (lambda (k) (or (memq k '(reveal-created transition))
                                         (and (eq? kind 'cancellation) (eq? k 'compact)))) kinds)))
    (math-error 'choreograph 'incomplete-choreography "The phases never reveal incoming parts." name))
  (when (and (pair? moving)
             (not (ormap (lambda (k) (memq k '(prepare-space compact transition))) kinds)))
    (math-error 'choreograph 'incomplete-choreography "The phases never position preserved parts." name))
  (when (and (pair? split-copies)
             (not (ormap (lambda (k) (memq k '(prepare-space compact transition))) kinds)))
    (math-error 'choreograph 'incomplete-choreography
                "The phases never reveal branch copies at their destination positions." name))
  (define retired? (null? retired))
  (define copies-revealed? (null? split-copies))
  (define (retire! seconds)
    (set! scn (play scn (map (lambda (t) (fade-request t 0)) retired) seconds))
    (set! retired? #t))
  (define (reveal! seconds)
    (unless retired?
      (math-error 'choreograph 'unsafe-overlap
                  "Retire the outgoing mathematical unit before revealing its replacement." name))
    (set! scn (play scn (map (lambda (t) (fade-request t 1)) created) seconds)))
  (define (move! seconds)
    (cond
      [split?
       ;; Copy semantics do not imply that two glyph paths should visibly cross.
       ;; Reveal the shared branch material only after it is already at its final
       ;; positions; the following reveal-created phase introduces the radicals.
       (unless copies-revealed?
         (set! scn (play scn (map (lambda (t) (fade-request t 1)) split-copies) seconds))
         (set! copies-revealed? #t))]
      [else
       (set! scn (play scn (map move-request moving) seconds))
       (set! starts moving)]))
  (for ([entry (in-list entries)])
    (define seconds (scheduled-phase-duration entry))
    (case (scheduled-phase-kind entry)
      [(explain)
       (set! scn (compile-explanation scn prepared (scheduled-phase-phase entry)
                                      (string->symbol (format "~a.inset~a" id view))))]
      [(prepare-space)
       (when (and (pair? retired) (not retired?))
         (math-error 'choreograph 'unsafe-reflow
                     "Retire obsolete structure before moving the surviving expression." name))
       (move! seconds)]
      [(retire-cancelled retire-removed) (retire! seconds)]
      [(reveal-created) (reveal! seconds)]
      [(compact)
       (unless retired?
         (math-error 'choreograph 'unsafe-reflow "Cancel or retire first; compact survivors afterward." name))
       (if (and (eq? kind 'cancellation) (pair? created)
                (not (memq 'reveal-created kinds)))
           (begin (move! (* 3/4 seconds)) (reveal! (* 1/4 seconds)))
           (move! seconds))]
      [(transition)
       ;; Even a simultaneous-layout request cannot mix new numeric results
       ;; with remnants of old arithmetic. All replacement ink reaches opacity
       ;; zero before any destination ink becomes visible.
       (retire! (* 9/20 seconds))
       (move! (* 1/10 seconds))
       (reveal! (* 9/20 seconds))]
      [else (set! scn (play scn '() seconds))]))
  ;; Restore exact endpoint assets once, without accumulating typography errors.
  (set! scn (remove-tokens scn (append old ghosts split-copies created)))
  (set! scn (add-tokens scn next))
  (values scn next (add1 view)))

;;;
;;; Complete Native Scene Assembly
;;;
; math-plan->scene! : (or/c presentation-plan? prepared-math-plan?) [#:camera any/c]
;   [#:theme (or/c #f 'light 'dark)] [#:title string?] [#:id symbol?]
;   [#:cache-directory path-string?] -> scene?
;;   Prepares when necessary and compiles the lesson into the existing native scene
;;   engine.
(define (math-plan->scene! plan-or-prepared
          #:camera [camera #f]
          #:theme [theme #f]
          #:title [title "Mathematical derivation"]
          #:id [id 'math-lesson]
          #:cache-directory [directory default-math-cache-directory])
  (check-symbol 'math-plan->scene! id)
  (unless (string? title)
    (raise-argument-error 'math-plan->scene! "string? as #:title" title))
  (when (prepared-math-plan? plan-or-prepared)
    (when (and camera (not (equal? camera (prepared-math-plan-camera plan-or-prepared))))
      (math-error 'math-plan->scene! 'frozen-camera
        "Prepare again to use a different camera."))
    (when theme
      (define-values (fg bg) (theme-colors theme))
      (unless (equal? fg (prepared-math-plan-foreground plan-or-prepared))
        (math-error 'math-plan->scene! 'frozen-theme
          "Prepare again to use a different theme."))))
  (define prepared
    (if (prepared-math-plan? plan-or-prepared)
      plan-or-prepared
      (prepare-math-plan! plan-or-prepared
        #:camera camera
        #:theme (or theme 'light)
        #:cache-directory directory)))
  (define plan (prepared-math-plan-plan prepared))
  (define style (presentation-plan-style plan))
  (define cam (prepared-math-plan-camera prepared))
  (define world-height
    (*
      ((animate-binding 'camera-world-width) cam)
      (/ ((animate-binding 'camera-height) cam) ((animate-binding 'camera-width) cam))))
  (define top (- (/ world-height 2) 2))
  (define foreground (prepared-math-plan-foreground prepared))
  (define gap (prepared-math-plan-row-gap prepared))
  (define scn ((animate-binding 'make-scene) #:camera cam))
  (define view 0)
  (define all-on-scene '())
  (define heading-ids '())
  (define checkpoint-key (string->symbol (format "~a.checkpoint" id)))
  (define checkpoint-index -1)
  (define (commit-checkpoint! current)
    (set! checkpoint-index (add1 checkpoint-index))
    ((animate-binding 'scene-set-value) current checkpoint-key checkpoint-index))
  (define (make-heading text y size suffix)
    (define key (string->symbol (format "~a.~a" id suffix)))
    (set! heading-ids (cons key heading-ids))
    ((animate-binding 'plain-text) text
      #:id key
      #:center ((animate-binding 'vec2) 0 y)
      #:font-size
      (min size
        (/
          (- ((animate-binding 'camera-world-width) cam) 6/5)
          (max 1 (* 14/25 (string-length text)))))
      #:color foreground))
  (for ([segment (in-list (presentation-plan-segments plan))] [segment-index (in-naturals)])
    (unless (null? all-on-scene) (set! scn (remove-tokens scn all-on-scene)))
    (unless (null? heading-ids)
      (set! scn (apply (animate-binding 'scene-remove) scn heading-ids)))
    (set! heading-ids '())
    (define ctx (plan-segment-context segment))
    ;; Prove consequences using authored assumptions only, not the very
    ;; restrictions being filtered. Genuine inherited domain exclusions remain.
    (define authored-context
      (math-context #:real (math-context-real ctx)
                    #:assuming (math-context-assumptions ctx)
                    #:definitions (math-context-definitions ctx)))
    (define assumptions
      (append (math-context-assumptions ctx)
              (filter (lambda (p)
                        (not (eq? (verification-status (context-prove authored-context p))
                                  'established)))
                      (math-context-restrictions ctx))))
    (define label
      (if (null? (plan-segment-path segment))
        title
        (format "~a — ~a" title
          (string-append (string-join (map symbol->string (plan-segment-path segment)) " / ")
                         (if (plan-segment-shared? segment) " — common derivation" "")))))
    (define warning
      (if (presentation-plan-allow-unverified? plan) "DRAFT: unverified obligations — " ""))
    (set! scn
      ((animate-binding 'scene-add) scn
        (make-heading label (- (/ world-height 2) 9/20) 3/10 'title)
        (make-heading
          (string-append warning
            (if (null? assumptions)
              "Real scalar algebra"
              (string-join (map pretty assumptions) "; ")))
          (- (/ world-height 2) 23/25)
          1/5
          'context)))
    (unless (zero? (hash-count (math-context-definitions ctx)))
      (set! scn
        ((animate-binding 'scene-add) scn
          (make-heading
            (string-join
              (for/list ([name (in-list (sort (hash-keys (math-context-definitions ctx)) symbol<?))])
                (format "~a = ~a" name
                  (pretty (hash-ref (math-context-definitions ctx) name))))
              "; ")
            (- (/ world-height 2) 32/25)
            1/5
            'definitions))))
    (define d (plan-segment-derivation segment))
    (define (layout state) (hash-ref (prepared-math-plan-layouts prepared) state))
    (define (at-row state row)
      (translate (prepared-layout-tokens (layout state)) 0 (- top (* gap row))))
    (define active-state (derivation-initial d))
    (define active (clone-view (at-row active-state 0) id view))
    (define active-row 0)
    (define history '())
    ; list of (list row tokens), never includes active
    (set! view (add1 view))
    (set! scn (add-tokens scn active))
    (set! scn (commit-checkpoint! scn))
    (set! scn ((animate-binding 'scene-wait) scn 4/5))
    (define groups
      (if (eq? (presentation-style-history style) 'keep-all-checkpoints)
        (map (lambda (s) (list (rewrite-step-name s))) (derivation-steps d))
        (plan-segment-groups segment)))
    (for ([group (in-list groups)] [group-index (in-naturals)])
      (define case-handoff-reuse?
        (and (zero? group-index)
             (pair? (plan-segment-path segment))
             (not (plan-segment-shared? segment))))
      (when (and
              (not case-handoff-reuse?)
              (not (eq? (presentation-style-history style) 'replace))
              (eq? (presentation-style-start-group style) 'copy))
        (define pending-history (append history (list (list active-row active))))
        (define retain-count (sub1 (prepared-math-plan-max-rows prepared)))
        (define kept
          (if (<= (length pending-history) retain-count)
            pending-history
            (cons (car pending-history) (take-right pending-history (sub1 retain-count)))))
        (define discarded (filter (lambda (h) (not (member h kept))) pending-history))
        (define shifts '())
        (set! history
          (for/list ([h (in-list kept)] [row (in-naturals)])
            (define original (cadr h))
            (define moved (translate original 0 (* gap (- (car h) row))))
            (set! shifts
              (append shifts
                (for/list ([before-token (in-list original)]
                           [after-token (in-list moved)]
                           #:unless (and (= (prepared-token-x before-token)
                                           (prepared-token-x after-token))
                                        (= (prepared-token-y before-token)
                                           (prepared-token-y after-token))))
                  (move-request after-token))))
            (list row moved)))
        (define row (length history))
        (define new-active
          (translate (clone-view active id view) 0 (* gap (- active-row row))))
        (set! view (add1 view))
        ;; At the first group of a parameter case, showing a second copy at the
        ;; same position makes the shared checkpoint briefly look doubled/bold.
        ;; Keep the existing checkpoint as history and reveal its working copy
        ;; directly at the destination row instead. Root, non-case lessons retain
        ;; their visible copy-and-move choreography.
        (define destination-copy?
          (and (zero? group-index)
               (pair? (plan-segment-path segment))
               (not (plan-segment-shared? segment))))
        (if destination-copy?
            (begin
              (set! scn (add-tokens scn new-active #:opacity 0))
              (set! scn
                (play scn
                  (append shifts
                    (map (lambda (t) (fade-request t 1)) new-active)
                    (map (lambda (t) (fade-request t 0)) (append-map cadr discarded)))
                  1/2)))
            (let ([copy-at-source (translate new-active 0 (* gap (- row active-row)))])
              (set! scn (add-tokens scn copy-at-source))
              (set! scn
                (play scn
                  (append shifts
                    (map move-request new-active)
                    (map (lambda (t) (fade-request t 0)) (append-map cadr discarded)))
                  1/2))))
        (set! active new-active)
        (set! active-row row)
        (set! scn (remove-tokens scn (append-map cadr discarded))))
      (for ([name (in-list group)])
        (define step (derivation-step d name))
        (define destination (at-row (rewrite-step-after step) active-row))
        (define-values (next-scene next-tokens next-view)
          (compile-math-step scn prepared segment-index step destination active id view))
        (set! scn next-scene)
        (set! active next-tokens)
        (set! view next-view)
        (set! active-state (rewrite-step-after step))
        (set! scn (commit-checkpoint! scn)))
      (set! scn (play scn '() (presentation-style-pause-between-groups style))))
    (when (plan-segment-verdict segment)
      (set! scn
        ((animate-binding 'scene-add) scn
          (make-heading
            (format "Candidate check: ~a"
              (verification-status (plan-segment-verdict segment)))
            (- 1/2 (/ world-height 2))
            23/100
            'verdict))))
    (set! scn ((animate-binding 'scene-wait) scn 1))
    (set! all-on-scene (append active (append-map cadr history))))
  scn)

;;;
;;; Static Visual and Pict Adapters
;;;
; math->visual! : math? [#:id symbol?] [#:font-size positive-real?]
;   [#:theme (or/c 'light 'dark)] [#:cache-directory path-string?] -> visual?
;;   Typesets one complete mathematical state and creates an ordinary native group.
(define (math->visual! state
          #:id [id 'math-snapshot]
          #:font-size [font-size 11/20]
          #:theme [theme 'light]
          #:cache-directory [directory default-math-cache-directory])
  (check-symbol 'math->visual! id)
  (define-values (foreground background) (theme-colors theme))
  (define layout
    (typeset-state! state
      #:font-size font-size
      #:foreground foreground
      #:cache-directory directory))
  ((animate-binding 'group)
    (map token-visual (clone-view (prepared-layout-tokens layout) id 0))
    #:id id))

; math-plan->pict! : (or/c presentation-plan? prepared-math-plan?) nonnegative-real?
;   [#:theme (or/c #f 'light 'dark)] [#:camera any/c]
;   [#:renderers (or/c list? #f)] -> pict?
;;   Renders one sampled native frame using the explicit camera and renderer selection.
(define (math-plan->pict! plan time
          #:theme [theme #f]
          #:camera [camera #f]
          #:renderers [renderers #f])
  (define scn (math-plan->scene! plan #:theme theme #:camera camera))
  (define state ((animate-binding 'scene-sample) scn time))
  ((animate-binding 'scene-state->pict) state
    #:camera ((animate-binding 'scene-camera-at) scn time)
    #:renderers (or renderers (animate-binding 'default-pict-renderers))))
