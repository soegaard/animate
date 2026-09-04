#lang racket/base

;;;
;;; Structured Formula Derivations
;;;

;; Packages an explicit sequence of anchored formula rewrites into a scene
;; timeline. It deliberately sequences author-provided algebra rather than
;; parsing or validating mathematical operations.


;;;
;;; Imports and Exports
;;;

(require racket/string
         "formula-part-transition.rkt"
         "formula-parts-visual.rkt"
         "formula-string-match.rkt"
         "geometry.rkt"
         "scene.rkt"
         "scene-state.rkt"
         "source-selector.rkt"
         "tagged-formula.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide formula-step
         formula-derivation-step?
         formula-derivation
         matching-fragments
         matching-fragments?
         matching-glyphs
         matching-glyphs?
         matching-strings
         matching-strings?)


;;;
;;; Data Representation
;;;

(struct formula-derivation-step
  (destination matching anchor stationary matches path-arc part-paths copies mismatch-mode
               duration pause explanation)
  #:transparent)

;; formula-derivation-step represents one explicit rewrite in a derivation.
;;  - destination   formula-assembly-visual?   requested formula endpoint.
;;  - matching      (or/c false/c formula-matching-strategy?) transition plan.
;;  - anchor        (or/c false/c symbol? formula-part-match?) step override.
;;  - stationary    (listof formula-part-match?) extra fixed matched parts.
;;  - matches       (listof formula-part-match?) explicit correspondence.
;;  - path-arc      finite-real?              default path for matched parts.
;;  - part-paths    (listof formula-part-path?) selected custom paths.
;;  - copies        (listof formula-part-copy?) source-preserving parts.
;;  - mismatch-mode (or/c 'fade 'fade-transform) unmatched-part policy.
;;  - duration      positive finite real?      rewrite duration.
;;  - pause         nonnegative finite real?   pre-rewrite explanatory pause.
;;  - explanation   (or/c false/c string?)     optional one-line note.

;; Strategy values deliberately gather the controls for one transition family
;; instead of growing formula-step into a union of unrelated keyword sets.
(struct matching-fragments-value
  (matches path-arc part-paths copies mismatch-mode)
  #:transparent)

(struct matching-glyphs-value
  (matches path-arc part-paths copies mismatch-mode)
  #:transparent)

(struct matching-strings-value
  (anchor stationary matches key-map protect-source protect-destination copies
          on-ambiguity path-arc mismatch-mode)
  #:transparent)

(define (matching-fragments? value) (matching-fragments-value? value))
(define (matching-glyphs? value) (matching-glyphs-value? value))
(define (matching-strings? value) (matching-strings-value? value))

(define (formula-matching-strategy? value)
  (or (matching-fragments? value)
      (matching-glyphs? value)
      (matching-strings? value)))


;;;
;;; Construction
;;;

;; matching-fragments : [#:matches (listof formula-part-match?)] ...
;;                      -> matching-fragments?
;; Uses the named-formula-fragment transition family.
(define (matching-fragments
         #:matches [matches '()]
         #:path-arc [path-arc 0]
         #:part-paths [part-paths '()]
         #:copies [copies '()]
         #:mismatch-mode [mismatch-mode 'fade])
  (check-formula-transition-controls
   'matching-fragments matches path-arc part-paths copies mismatch-mode)
  (matching-fragments-value
   matches path-arc part-paths copies mismatch-mode))

;; matching-glyphs : [#:matches (listof formula-part-match?)] ...
;;                   -> matching-glyphs?
;; Uses the explicit glyph-outline transition family.
(define (matching-glyphs
         #:matches [matches '()]
         #:path-arc [path-arc 0]
         #:part-paths [part-paths '()]
         #:copies [copies '()]
         #:mismatch-mode [mismatch-mode 'fade])
  (check-formula-transition-controls
   'matching-glyphs matches path-arc part-paths copies mismatch-mode)
  (matching-glyphs-value
   matches path-arc part-paths copies mismatch-mode))

;; matching-strings : [#:anchor (or/c false/c source-selector?)] ...
;;                    -> matching-strings?
;; Collects source-addressed transition controls for one formula-step.  The
;; exact mapping plan remains available independently through
;; plan-matching-strings; this value describes how formula-derivation should
;; invoke it at its current source endpoint.
(define (matching-strings
         #:anchor [anchor #f]
         #:stationary [stationary '()]
         #:matches [matches '()]
         #:key-map [key-map '()]
         #:protect-source [protect-source '()]
         #:protect-destination [protect-destination '()]
         #:copies [copies '()]
         #:on-ambiguity [on-ambiguity 'left-to-right]
         #:path-arc [path-arc 0]
         #:mismatch-mode [mismatch-mode 'fade])
  (unless (or (not anchor) (source-selector? anchor))
    (raise-argument-error
     'matching-strings
     "(or/c false/c source-selector?) as #:anchor"
     anchor))
  (check-list-of 'matching-strings stationary source-selector? "source-selector?")
  (check-list-of 'matching-strings matches string-match? "string-match?")
  (check-list-of 'matching-strings key-map string-match? "string-match?")
  (check-list-of
   'matching-strings protect-source source-selector? "source-selector?")
  (check-list-of
   'matching-strings protect-destination source-selector? "source-selector?")
  (check-list-of 'matching-strings copies string-copy? "string-copy?")
  (unless (memq on-ambiguity '(left-to-right error))
    (raise-argument-error
     'matching-strings
     "(or/c 'left-to-right 'error) as #:on-ambiguity"
     on-ambiguity))
  (unless (finite-real? path-arc)
    (raise-argument-error 'matching-strings "finite real? as #:path-arc" path-arc))
  (unless (memq mismatch-mode '(fade fade-transform))
    (raise-argument-error
     'matching-strings
     "(or/c 'fade 'fade-transform) as #:mismatch-mode"
     mismatch-mode))
  (matching-strings-value
   anchor stationary matches key-map protect-source protect-destination copies
   on-ambiguity path-arc mismatch-mode))

; formula-step : formula-assembly-visual?
;                [#:matching formula-matching-strategy?]
;                [#:anchor (or/c false/c symbol? formula-part-match?)]
;                [#:stationary (listof (or/c symbol? formula-part-match?))]
;                [#:matches (listof formula-part-match?)]
;                [#:path-arc finite-real?]
;                [#:part-paths (listof formula-part-path?)]
;                [#:copies (listof formula-part-copy?)]
;                [#:mismatch-mode (or/c 'fade 'fade-transform)]
;                [#:duration positive-finite-real?]
;                [#:pause nonnegative-finite-real?]
;                [#:explanation (or/c false/c string?)]
;                -> formula-derivation-step?
;;   Describes one explicit formula rewrite for formula-derivation.
(define (formula-step destination
                      #:matching [matching #f]
                      #:anchor [anchor #f]
                      #:stationary [stationary '()]
                      #:matches [matches '()]
                      #:path-arc [path-arc 0]
                      #:part-paths [part-paths '()]
                      #:copies [copies '()]
                      #:mismatch-mode [mismatch-mode 'fade]
                      #:duration [duration 1]
                      #:pause [pause 1/2]
                      #:explanation [explanation #f])
  (unless (formula-assembly-visual? destination)
    (raise-argument-error 'formula-step "formula-assembly-visual?" destination))
  (unless (or (not matching) (formula-matching-strategy? matching))
    (raise-argument-error
     'formula-step
     "(or/c false/c formula matching strategy) as #:matching"
     matching))
  (unless (or (not anchor)
              (symbol? anchor)
              (formula-part-match? anchor))
    (raise-argument-error
     'formula-step
     "(or/c false/c symbol? formula-part-match?)"
     anchor))
  (unless (list? stationary)
    (raise-argument-error
     'formula-step
     "(listof (or/c symbol? formula-part-match?))"
     stationary))
  (for ([entry (in-list stationary)])
    (unless (or (symbol? entry) (formula-part-match? entry))
      (raise-argument-error
       'formula-step
       "(listof (or/c symbol? formula-part-match?))"
       stationary)))
  (check-list-of 'formula-step matches formula-part-match? "formula-part-match?")
  (unless (finite-real? path-arc)
    (raise-argument-error 'formula-step "finite real?" path-arc))
  (check-list-of 'formula-step part-paths formula-part-path? "formula-part-path?")
  (check-list-of 'formula-step copies formula-part-copy? "formula-part-copy?")
  (unless (memq mismatch-mode '(fade fade-transform))
    (raise-argument-error 'formula-step "(or/c 'fade 'fade-transform)" mismatch-mode))
  (unless (and (finite-real? duration) (positive? duration))
    (raise-argument-error 'formula-step "positive finite real?" duration))
  (unless (and (finite-real? pause) (not (negative? pause)))
    (raise-argument-error 'formula-step "nonnegative finite real?" pause))
  (unless (or (not explanation) (string? explanation))
    (raise-argument-error 'formula-step "(or/c false/c string?)" explanation))
  (when (and explanation
             (or (string-contains? explanation "\n")
                 (string-contains? explanation "\r")))
    (raise-arguments-error
     'formula-step
     "a single-line explanation string"
     "explanation" explanation))
  (formula-derivation-step
   destination matching anchor stationary matches path-arc part-paths copies mismatch-mode
   duration pause
   (and explanation (string->immutable-string explanation))))


;;;
;;; Timeline Construction
;;;

; formula-derivation : scene? formula-assembly-visual?
;                      [#:anchor (or/c false/c symbol? formula-part-match?)]
;                      #:steps (listof formula-derivation-step?)
;                      [#:explanation-position (or/c false/c vec2?)]
;                      [#:explanation-id symbol?]
;                      [#:explanation-font-size positive-finite-real?]
;                      [#:explanation-color any/c]
;                      -> scene?
;;   Appends explicit formula rewrites, explanatory pauses, and optional notes.
(define (formula-derivation scene initial
                            #:anchor [anchor #f]
                            #:steps steps
                            #:explanation-position [explanation-position #f]
                            #:explanation-id [explanation-id 'derivation-note]
                            #:explanation-font-size [explanation-font-size 1/4]
                            #:explanation-color [explanation-color "darkslategray"])
  (unless (scene? scene)
    (raise-argument-error 'formula-derivation "scene?" scene))
  (unless (formula-assembly-visual? initial)
    (raise-argument-error 'formula-derivation "formula-assembly-visual?" initial))
  (unless (or (not anchor) (symbol? anchor) (formula-part-match? anchor))
    (raise-argument-error
     'formula-derivation
     "(or/c false/c symbol? formula-part-match?)"
     anchor))
  (check-list-of
   'formula-derivation
   steps
   formula-derivation-step?
   "formula-derivation-step?")
  (for ([step (in-list steps)]
        #:when (not (formula-derivation-step-matching step)))
    (unless (or anchor (formula-derivation-step-anchor step))
      (raise-arguments-error
       'formula-derivation
       "#:anchor or a per-step #:anchor for fragment rewrite steps"
       "step" step)))
  (unless (or (not explanation-position) (vec2? explanation-position))
    (raise-argument-error
     'formula-derivation
     "(or/c false/c vec2?)"
     explanation-position))
  (unless (symbol? explanation-id)
    (raise-argument-error 'formula-derivation "symbol?" explanation-id))
  (unless (and (finite-real? explanation-font-size)
               (positive? explanation-font-size))
    (raise-argument-error
     'formula-derivation
     "positive finite real?"
     explanation-font-size))
  (define formula-id
    (visual-id initial))
  (define initial-state
    (scene-current-state scene))
  (unless (scene-state-has? initial-state formula-id)
    (raise-arguments-error
     'formula-derivation
     "an initial formula present in the scene"
     "formula-id" formula-id))
  (when (scene-state-has? initial-state explanation-id)
    (raise-arguments-error
     'formula-derivation
     "an explanation id absent from the initial scene"
     "explanation-id" explanation-id))
  (when (and (not explanation-position)
             (for/or ([step (in-list steps)])
               (formula-derivation-step-explanation step)))
    (raise-arguments-error
     'formula-derivation
     "#:explanation-position when a step has #:explanation"
     "steps" steps))
  (let loop ([current-scene scene]
             [source initial]
             [remaining steps]
             [note-present? #f])
    (cond
      [(null? remaining) current-scene]
      [else
       (define step (car remaining))
       (define with-explanation
         (install-derivation-explanation
          current-scene
          note-present?
          explanation-id
          explanation-position
          explanation-font-size
          explanation-color
          (formula-derivation-step-explanation step)))
       (define explanation-now?
         (and (formula-derivation-step-explanation step) #t))
       (define paused
         (if (zero? (formula-derivation-step-pause step))
             with-explanation
             (scene-wait with-explanation
                         (formula-derivation-step-pause step))))
       (define rewritten
         (scene-play
          paused
          (formula-step-transition
           source
           (formula-derivation-step-destination step)
           anchor
           step)
          #:duration (formula-derivation-step-duration step)))
       (loop rewritten
             (formula-derivation-step-destination step)
             (cdr remaining)
             explanation-now?)])))

; install-derivation-explanation : scene? boolean? symbol? (or/c false/c vec2?)
;                                  positive-finite-real? any/c (or/c false/c string?)
;                                  -> scene?
;;   Replaces the optional one-line note instantaneously before the next pause.
(define (install-derivation-explanation scene note-present? id position font-size color explanation)
  (define without-prior
    (if note-present?
        (scene-remove scene id)
        scene))
  (if explanation
      (scene-add
       without-prior
       (plain-text explanation
                   #:id id
                   #:center position
                   #:font-size font-size
                   #:font-family 'swiss
                   #:color color))
      without-prior))

;; formula-step-transition : formula assembly formula assembly
;;                           (or/c symbol? formula-part-match?)
;;                           formula-derivation-step?
;;                           -> transform-formula-parts-request?
;; Compiles a transparent strategy at the exact preceding formula endpoint.
;; With no #:matching value, retain the original named-fragment rewrite form.
(define (formula-step-transition source destination default-anchor step)
  (define strategy (formula-derivation-step-matching step))
  (cond
    [(not strategy)
     (rewrite-formula
      source destination
      #:anchor (or (formula-derivation-step-anchor step) default-anchor)
      #:stationary (formula-derivation-step-stationary step)
      #:matches (formula-derivation-step-matches step)
      #:path-arc (formula-derivation-step-path-arc step)
      #:part-paths (formula-derivation-step-part-paths step)
      #:copies (formula-derivation-step-copies step)
      #:mismatch-mode (formula-derivation-step-mismatch-mode step))]
    [(matching-fragments? strategy)
     (transform-matching-formula
      source destination
      #:matches (matching-fragments-value-matches strategy)
      #:path-arc (matching-fragments-value-path-arc strategy)
      #:part-paths (matching-fragments-value-part-paths strategy)
      #:copies (matching-fragments-value-copies strategy)
      #:mismatch-mode (matching-fragments-value-mismatch-mode strategy))]
    [(matching-glyphs? strategy)
     (transform-matching-glyphs
      source destination
      #:matches (matching-glyphs-value-matches strategy)
      #:path-arc (matching-glyphs-value-path-arc strategy)
      #:part-paths (matching-glyphs-value-part-paths strategy)
      #:copies (matching-glyphs-value-copies strategy)
      #:mismatch-mode (matching-glyphs-value-mismatch-mode strategy))]
    [(matching-strings? strategy)
     (define anchor (matching-strings-value-anchor strategy))
     ;; Keyword arguments cannot be assembled portably without losing the
     ;; contract surface, so keep these calls written out.  It makes the
     ;; authored strategy directly visible in stack traces as well.
     (if anchor
         (rewrite-matching-strings
          source destination
          #:anchor anchor
          #:stationary (matching-strings-value-stationary strategy)
          #:matches (matching-strings-value-matches strategy)
          #:key-map (matching-strings-value-key-map strategy)
          #:protect-source (matching-strings-value-protect-source strategy)
          #:protect-destination
          (matching-strings-value-protect-destination strategy)
          #:copies (matching-strings-value-copies strategy)
          #:on-ambiguity (matching-strings-value-on-ambiguity strategy)
          #:path-arc (matching-strings-value-path-arc strategy)
          #:mismatch-mode (matching-strings-value-mismatch-mode strategy))
         (transform-matching-strings
          source destination
          #:matches (matching-strings-value-matches strategy)
          #:key-map (matching-strings-value-key-map strategy)
          #:protect-source (matching-strings-value-protect-source strategy)
          #:protect-destination
          (matching-strings-value-protect-destination strategy)
          #:copies (matching-strings-value-copies strategy)
          #:on-ambiguity (matching-strings-value-on-ambiguity strategy)
          #:path-arc (matching-strings-value-path-arc strategy)
          #:mismatch-mode (matching-strings-value-mismatch-mode strategy)))]
    [else
     ;; formula-step validates strategy construction.  This branch protects the
     ;; invariant if a future strategy variant is added without compilation.
     (raise-arguments-error
      'formula-derivation
      "a formula matching strategy implemented by formula-step-transition"
      "strategy" strategy)]))


;;;
;;; Validation Helpers
;;;

(define (check-list-of who value predicate expected)
  (unless (and (list? value) (andmap predicate value))
    (raise-argument-error who (string-append "(listof " expected ")") value)))

(define (check-formula-transition-controls who matches path-arc part-paths
                                           copies mismatch-mode)
  (check-list-of who matches formula-part-match? "formula-part-match?")
  (unless (finite-real? path-arc)
    (raise-argument-error who "finite real? as #:path-arc" path-arc))
  (check-list-of who part-paths formula-part-path? "formula-part-path?")
  (check-list-of who copies formula-part-copy? "formula-part-copy?")
  (unless (memq mismatch-mode '(fade fade-transform))
    (raise-argument-error
     who
     "(or/c 'fade 'fade-transform) as #:mismatch-mode"
     mismatch-mode)))
