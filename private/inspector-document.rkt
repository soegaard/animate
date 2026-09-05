#lang racket/base

;;;
;;; Semantic Inspector Documents
;;;

;; Builds immutable explanation data from sampled scene semantics. This module
;; has no GUI, bitmap, or preview-controller dependency: a window is only one
;; possible client for the document and its preview-only overlays.


;;;
;;; Imports and Exports
;;;

(require racket/generic
         racket/list
         "animation-inspection.rkt"
         "camera.rkt"
         "formula-parts-visual.rkt"
         "formula-part-transition.rkt"
         "formula-source.rkt"
         "formula-source-map.rkt"
         "formula-string-match.rkt"
         "geometry.rkt"
         "relation-dependency.rkt"
         "relation-resolver.rkt"
         "relation-visual.rkt"
         "scene-state.rkt"
         "scene-program.rkt"
         "scene.rkt"
         "source-document.rkt"
         "visual-inspector.rkt"
         "visual-selection.rkt"
         "visual-model.rkt")

(provide (struct-out inspector-document)
         (struct-out inspector-section)
         (struct-out inspector-row)
         (struct-out inspector-action)
         (struct-out inspector-overlay)
         (struct-out inspector-subject)
         (struct-out inspector-source-block)
         gen:inspection-provider
         inspection-provider?
         inspection-sections
         inspection-overlays
         inspection-actions
         visual-inspector-subject
         scene-inspector-subject-at-path
         formula-source-match-subject
         formula-source-index-subject
         formula-source-match-at-index
         formula-leaf-source-matches
         relation-dependency-subject
         string-transition-subject
         source-block-inspector-subject
         render-diagnostics-inspector-subject
         scene-inspector-document)


;;;
;;; Immutable Inspector Values
;;;

(struct inspector-document
  (sample subject sections overlays actions diagnostics)
  #:transparent)

;; inspector-document is a sampled explanation snapshot. sample is an
;; immutable hash containing the requested time, sampled state, and camera.

(struct inspector-section (id title rows content)
  #:transparent)

;; inspector-section groups ordered labelled rows and optional rich immutable
;; content. A GUI may render the same sections as tabs, panes, or plain text.

(struct inspector-row (label value severity actions)
  #:transparent)

;; inspector-row represents one inspectable property. severity is one of
;; 'info, 'warning, or 'error; actions are immutable inspector-action values.

(struct inspector-action (id label command enabled?)
  #:transparent)

;; inspector-action describes an author-requestable operation without invoking
;; it. command is a transparent datum interpreted by a preview client.

(struct inspector-overlay (id kind geometry style metadata)
  #:transparent)

;; inspector-overlay is preview-only geometry. It never becomes a scene Visual
;; and therefore cannot affect frame rendering or persistent frame caches.

(struct inspector-subject (kind value root-path)
  #:transparent)

;; inspector-subject names an inspected semantic entity. root-path is a stable
;; scene path when it has one, rather than a transient pixel hit coordinate.

;; inspector-source-block is the narrow source-program record that an
;; inspector needs.  It deliberately does not retain a block builder or its
;; input/output Scenes: those can contain arbitrary procedures and are neither
;; useful nor honest to serialize as inspector data.
(struct inspector-source-block
  (id start end source-location generation branch-mode)
  #:transparent)


;;;
;;; Extensible Provider Protocol
;;;

(define-generics inspection-provider
  (inspection-sections inspection-provider subject)
  (inspection-overlays inspection-provider subject)
  (inspection-actions inspection-provider subject))

;; Providers expose data only. Their methods cannot mutate a Scene, preview
;; session, or renderer cache; clients dispatch enabled action commands later.


;;;
;;; Subject Constructors
;;;

; visual-inspector-subject : visual? visual-path? -> inspector-subject?
;;   Creates a stable visual subject with its known scene path.
(define (visual-inspector-subject visual root-path)
  (unless (visual? visual)
    (raise-argument-error 'visual-inspector-subject "visual?" visual))
  (check-root-path 'visual-inspector-subject root-path)
  (inspector-subject 'visual visual root-path))

; scene-inspector-subject-at-path : scene-state? visual-path? -> inspector-subject?
;; Builds the most informative stable inspector subject for one selected
;; Visual path in an already sampled Scene state.  A click on a mapped formula
;; leaf selects the corresponding source-map unit; a click on an unmapped leaf
;; selects its containing formula instead.  The latter is intentional: it
;; shows every available source unit without pretending that unmapped ink has
;; a source address.
;;
;; This is the Visual-to-source half of formula inspection.  It has no GUI or
;; renderer dependency, so previews, REPLs, and a future editor integration
;; all make exactly the same no-guess selection decision.
(define (scene-inspector-subject-at-path state path)
  (unless (scene-state? state)
    (raise-argument-error 'scene-inspector-subject-at-path "scene-state?" state))
  (check-root-path 'scene-inspector-subject-at-path path)
  ;; Check the complete path first.  This gives callers the normal
  ;; scene-state-ref failure for a stale or malformed selection instead of
  ;; concealing it by falling back to an ancestor.
  (define selected (scene-state-ref state path))
  (define formula-root (nearest-formula-root state path))
  (cond
    [(not formula-root)
     (visual-inspector-subject selected path)]
    [else
     (define root-path (car formula-root))
     (define formula (cdr formula-root))
     (define relative-path (drop path (length root-path)))
     (define matches
       (if (null? relative-path)
           '()
           (formula-leaf-source-matches formula relative-path)))
     (cond
       ;; A unique map unit is semantic identity, not a positional guess.
       [(= (length matches) 1)
        (formula-source-match-subject formula (car matches) root-path)]
       ;; Shared formula leaves can legitimately correspond to multiple source
       ;; spans.  Keep the whole formula selected until a source-side UI can
       ;; present those alternatives; never choose one occurrence silently.
       [else
        (visual-inspector-subject formula root-path)])]))

; formula-source-match-subject : formula-assembly-visual? formula-source-match?
;;                                visual-path? -> inspector-subject?
;;   Names one exact source-map unit and its formula root path.
(define (formula-source-match-subject formula match root-path)
  (unless (formula-assembly-visual? formula)
    (raise-argument-error
     'formula-source-match-subject "formula-assembly-visual?" formula))
  (unless (formula-source-match? match)
    (raise-argument-error
     'formula-source-match-subject "formula-source-match?" match))
  (check-root-path 'formula-source-match-subject root-path)
  (inspector-subject 'formula-source-match (cons formula match) root-path))

(define (nearest-formula-root state path)
  (let loop ([length (length path)])
    (cond
      [(zero? length) #f]
      [else
       (define candidate-path (take path length))
       (define candidate (scene-state-ref state candidate-path))
       (if (formula-assembly-visual? candidate)
           (cons candidate-path candidate)
           (loop (sub1 length)))])))

; formula-source-index-subject : formula-assembly-visual? exact-nonnegative-integer?
;                               visual-path? -> (or/c inspector-subject? #f)
;; Maps one source-character index to its smallest safe rendered source unit.
;; Whitespace and unmapped source return #f rather than guessing a neighbour.
(define (formula-source-index-subject formula index root-path)
  (unless (formula-assembly-visual? formula)
    (raise-argument-error
     'formula-source-index-subject "formula-assembly-visual?" formula))
  (unless (exact-nonnegative-integer? index)
    (raise-argument-error
     'formula-source-index-subject "exact-nonnegative-integer?" index))
  (check-root-path 'formula-source-index-subject root-path)
  (define match (formula-source-match-at-index formula index))
  (and match (formula-source-match-subject formula match root-path)))

; formula-source-match-at-index : formula-assembly-visual? exact-nonnegative-integer?
;;                                 -> (or/c formula-source-match? #f)
;; Returns the narrowest map unit containing index.  This is the source-to-leaf
;; half of bidirectional formula selection and remains entirely headless.
(define (formula-source-match-at-index formula index)
  (unless (formula-assembly-visual? formula)
    (raise-argument-error
     'formula-source-match-at-index "formula-assembly-visual?" formula))
  (unless (exact-nonnegative-integer? index)
    (raise-argument-error
     'formula-source-match-at-index "exact-nonnegative-integer?" index))
  (define mapping (formula-source-map formula))
  (and mapping
       (for/fold ([best #f])
                 ([match (in-list (formula-source-map-matches mapping))])
         (define span (formula-source-match-span match))
         (if (and (<= (source-span-start span) index)
                  (< index (source-span-end span))
                  (or (not best)
                      (< (- (source-span-end span) (source-span-start span))
                         (- (source-span-end (formula-source-match-span best))
                            (source-span-start (formula-source-match-span best))))))
             match
             best))))

; formula-leaf-source-matches : formula-assembly-visual? relative-visual-path?
;;                               -> (listof formula-source-match?)
;; Finds all source units containing one formula-relative leaf.  Repeated
;; source text remains distinct because matches retain their own spans/names.
(define (formula-leaf-source-matches formula relative-path)
  (unless (formula-assembly-visual? formula)
    (raise-argument-error
     'formula-leaf-source-matches "formula-assembly-visual?" formula))
  (unless (and (list? relative-path) (andmap symbol? relative-path))
    (raise-argument-error
     'formula-leaf-source-matches "list of symbols" relative-path))
  (define mapping (formula-source-map formula))
  (if mapping
      (filter
       (lambda (match)
         (member relative-path
                 (formula-source-match-relative-paths match)
                 equal?))
       (formula-source-map-matches mapping))
      '()))

; relation-dependency-subject : relation-visual? visual-path? -> inspector-subject?
;;   Names a relation declaration at a stable scene path.
(define (relation-dependency-subject relation root-path)
  (unless (relation-visual? relation)
    (raise-argument-error
     'relation-dependency-subject "relation-visual?" relation))
  (check-root-path 'relation-dependency-subject root-path)
  (inspector-subject 'relation-dependency relation root-path))

; source-block-inspector-subject : inspector-source-block? -> inspector-subject?
;; Names a compact immutable source-block record.  The provider presents the
;; block's exact compiled interval and source location without exposing the
;; program's arbitrary builder procedure or retained scene checkpoints.
(define (source-block-inspector-subject block)
  (unless (inspector-source-block? block)
    (raise-argument-error 'source-block-inspector-subject
                          "inspector-source-block?" block))
  (inspector-subject 'source-block block #f))

; render-diagnostics-inspector-subject : immutable-hash? -> inspector-subject?
;; Names one already-published diagnostic snapshot.  Render diagnostics are
;; controller output, never a reason for the inspector to request a bitmap.
(define (render-diagnostics-inspector-subject diagnostics)
  (unless (hash? diagnostics)
    (raise-argument-error 'render-diagnostics-inspector-subject "hash?" diagnostics))
  (inspector-subject 'render-diagnostics
                     (immutable-hash-snapshot diagnostics)
                     #f))

; string-transition-subject : animation-inspection? -> inspector-subject?
;; Selects a retained compiled string-transition plan directly.  The constructor
;; rejects unrelated metadata kinds so a GUI never renders a misleading pane.
(define (string-transition-subject inspection)
  (unless (and (animation-inspection? inspection)
               (eq? (animation-inspection-kind inspection) 'string-transition))
    (raise-argument-error
     'string-transition-subject "string-transition animation-inspection?" inspection))
  (inspector-subject 'string-transition inspection #f))


;;;
;;; Headless Document Construction
;;;

; scene-inspector-document : scene? nonnegative-real?
;;                            [#:subject (or/c #f inspector-subject?)]
;;                            [#:source-block (or/c #f inspector-source-block?)]
;;                            [#:render-diagnostics (or/c #f hash?)]
;;                            -> inspector-document?
;;   Samples once and produces generic, formula, relation, camera, source-block,
;;   and render-diagnostic explanation data. Optional production metadata is
;;   already-published immutable data; it never starts a renderer or reload.
(define (scene-inspector-document scene time
                                  #:subject [subject #f]
                                  #:source-block [source-block #f]
                                  #:render-diagnostics [render-diagnostics #f])
  (unless (scene? scene)
    (raise-argument-error 'scene-inspector-document "scene?" scene))
  (unless (and (finite-real? time) (not (negative? time))
               (<= time (scene-duration scene)))
    (raise-argument-error
     'scene-inspector-document "scene time within the scene duration" time))
  (unless (or (not subject) (inspector-subject? subject))
    (raise-argument-error
     'scene-inspector-document "#f or inspector-subject?" subject))
  (unless (or (not source-block) (inspector-source-block? source-block))
    (raise-argument-error
     'scene-inspector-document "#f or inspector-source-block?" source-block))
  (unless (or (not render-diagnostics) (hash? render-diagnostics))
    (raise-argument-error
     'scene-inspector-document "#f or hash?" render-diagnostics))
  (define-values (state camera)
    (scene-sample-with-camera scene time))
  (define effective-subject
    (or subject (inspector-subject 'scene state #f)))
  (define subject-value
    (subject-value-at-state effective-subject state))
  (define providers
    (list generic-inspection-provider
          formula-inspection-provider
          relation-inspection-provider))
  (define sections
    (append*
     (for/list ([provider (in-list providers)])
       (inspection-sections provider
                            (inspector-subject
                             (inspector-subject-kind effective-subject)
                             subject-value
                             (inspector-subject-root-path effective-subject))))))
  ;; Static relation declarations and their cacheability are available from
  ;; the ordinary provider above. A selected semantic relation additionally
  ;; gets a deliberately opt-in sampled report: it records which declarations
  ;; its resolver actually read at this time, while making renderer-dependent
  ;; layout use explicitly unknown rather than guessing from declarations.
  (define relation-sample-sections
    (relation-sample-inspection-sections
     state
     (inspector-subject
      (inspector-subject-kind effective-subject)
      subject-value
      (inspector-subject-root-path effective-subject))))
  (define overlays
    (append*
     (for/list ([provider (in-list providers)])
       (inspection-overlays provider
                            (inspector-subject
                             (inspector-subject-kind effective-subject)
                             subject-value
                             (inspector-subject-root-path effective-subject))))))
  (define actions
    (append*
     (for/list ([provider (in-list providers)])
       (inspection-actions provider
                           (inspector-subject
                            (inspector-subject-kind effective-subject)
                             subject-value
                             (inspector-subject-root-path effective-subject))))))
  ;; A transition belongs to the clip under the playhead rather than to one
  ;; selected Visual path.  Keep it as a second subject so a Visual/formula
  ;; selection can coexist with a string-match explanation.
  (define transition-subject
    (inspector-subject
     'active-animations
     (scene-animation-inspections-at scene time)
     #f))
  (define transition-sections
    (inspection-sections transition-inspection-provider transition-subject))
  (define transition-overlays
    (inspection-overlays transition-inspection-provider transition-subject))
  (define transition-actions
    (inspection-actions transition-inspection-provider transition-subject))
  ;; These providers describe session metadata rather than a selected Visual.
  ;; The camera comes from the same one scene sample above; program and render
  ;; data arrive as immutable snapshots supplied by a preview or editor.
  (define camera-subject (inspector-subject 'camera camera #f))
  (define source-block-subject
    (and source-block (source-block-inspector-subject source-block)))
  (define render-diagnostics-subject
    (and render-diagnostics
         (render-diagnostics-inspector-subject render-diagnostics)))
  (define supplemental-subjects
    (filter values
            (list camera-subject source-block-subject render-diagnostics-subject)))
  (define supplemental-providers
    (list camera-inspection-provider
          source-block-inspection-provider
          render-diagnostics-inspection-provider))
  (define supplemental-sections
    (append*
     (for/list ([supplemental-subject (in-list supplemental-subjects)])
       (append*
        (for/list ([provider (in-list supplemental-providers)])
          (inspection-sections provider supplemental-subject))))))
  (define supplemental-actions
    (append*
     (for/list ([supplemental-subject (in-list supplemental-subjects)])
       (append*
        (for/list ([provider (in-list supplemental-providers)])
          (inspection-actions provider supplemental-subject))))))
  (inspector-document
   (hasheq 'time time 'state state 'camera camera)
   (inspector-subject (inspector-subject-kind effective-subject)
                      subject-value
                      (inspector-subject-root-path effective-subject))
   (append sections relation-sample-sections transition-sections supplemental-sections)
   (append overlays transition-overlays)
   (append actions transition-actions supplemental-actions)
   (if render-diagnostics
       (list (immutable-hash-snapshot render-diagnostics))
       '())))


;;;
;;; Built-In Providers
;;;

(struct generic-inspection-provider-value ()
  #:transparent
  #:methods gen:inspection-provider
  [(define (inspection-sections _provider subject)
     (cond
       [(visual? (inspector-subject-value subject))
        (define visual (inspector-subject-value subject))
        (list
         (inspector-section
          'visual "Visual"
          (list
           (inspector-row "path" (inspector-subject-root-path subject) 'info '())
           (inspector-row "id" (visual-id visual) 'info '())
           (inspector-row "kind" (visual-kind-name visual) 'info '()))
          #f))]
       [else '()]))
   (define (inspection-overlays _provider _subject) '())
   (define (inspection-actions _provider subject)
     (if (inspector-subject-root-path subject)
         (list
          (inspector-action
           'copy-path "Copy selected path"
           `(copy-path ,(inspector-subject-root-path subject)) #t))
         '()))])

(define generic-inspection-provider
  (generic-inspection-provider-value))

;; Camera inspection is always available because `scene-inspector-document`
;; samples the Scene and camera together.  It is independent of a selected
;; Visual and therefore shows the exact view that produced the current bitmap.
(struct camera-inspection-provider-value ()
  #:transparent
  #:methods gen:inspection-provider
  [(define (inspection-sections _provider subject)
     (define value (inspector-subject-value subject))
     (if (and (eq? (inspector-subject-kind subject) 'camera) (camera? value))
         (list
          (inspector-section
           'camera "Camera"
           (list
            (inspector-row "pixels"
                           (list (camera-width value) (camera-height value))
                           'info '())
            (inspector-row "world viewport"
                           (list (camera-world-width value)
                                 (camera-world-height value))
                           'info '())
            (inspector-row "center" (camera-center value) 'info '())
            (inspector-row "pixels per world unit" (camera-scale value) 'info '())
            (inspector-row "background" (camera-background value) 'info '()))
           #f))
         '()))
   (define (inspection-overlays _provider _subject) '())
   (define (inspection-actions _provider _subject) '())])

(define camera-inspection-provider
  (camera-inspection-provider-value))

;; Source blocks are source-program metadata, not rendered Visuals.  The
;; section is supplied only when a caller has an exact compiled block record
;; for the playhead; a plain Scene cannot fabricate one.
(struct source-block-inspection-provider-value ()
  #:transparent
  #:methods gen:inspection-provider
  [(define (inspection-sections _provider subject)
     (define block (inspector-subject-value subject))
     (if (and (eq? (inspector-subject-kind subject) 'source-block)
              (inspector-source-block? block))
         (list
          (inspector-section
           'source-block "Source block"
           (append
            (list
             (inspector-row "id" (inspector-source-block-id block) 'info '())
             (inspector-row "interval"
                            (list (inspector-source-block-start block)
                                  (inspector-source-block-end block))
                            'info '())
             (inspector-row "program generation"
                            (inspector-source-block-generation block) 'info '())
             (inspector-row "branch mode"
                            (inspector-source-block-branch-mode block) 'info '()))
            (if (inspector-source-block-source-location block)
                (list
                 (inspector-row
                  "source location"
                  (source-location->datum
                   (inspector-source-block-source-location block))
                  'info
                  (list
                   (inspector-action
                    'copy-source-location "Copy source location"
                    `(copy-source-location
                      ,(source-location->datum
                        (inspector-source-block-source-location block)))
                    #t))))
                (list (inspector-row "source location" "unavailable" 'warning '()))))
           #f))
         '()))
   (define (inspection-overlays _provider _subject) '())
   (define (inspection-actions _provider _subject) '())])

(define source-block-inspection-provider
  (source-block-inspection-provider-value))

;; Render diagnostics arrive after a controller has published a snapshot. The
;; inspector only formats that immutable data; it neither waits for a render
;; nor makes cache or worker state part of a Scene sample.
(struct render-diagnostics-inspection-provider-value ()
  #:transparent
  #:methods gen:inspection-provider
  [(define (inspection-sections _provider subject)
     (define diagnostics (inspector-subject-value subject))
   (if (and (eq? (inspector-subject-kind subject) 'render-diagnostics)
              (hash? diagnostics))
         (list
          (inspector-section
           'render-diagnostics "Render diagnostics"
           (append
            (list
             ;; Putting the action on a row makes it visible in the existing
             ;; generic inspector list widget, whose action button is driven
             ;; by the currently selected row.
             (inspector-row
              "snapshot" "Copy the published render-diagnostic snapshot"
              'info
              (list
               (inspector-action
                'copy-render-diagnostics "Copy render diagnostics"
                `(copy-render-diagnostics ,diagnostics)
                #t))))
            (if (zero? (hash-count diagnostics))
                (list (inspector-row "status" "no render diagnostics yet" 'warning '()))
                (for/list ([key (in-list (sort (hash-keys diagnostics)
                                            string<?
                                            #:key (lambda (entry)
                                                    (format "~s" entry))))])
                  (inspector-row (format "~a" key)
                                 (hash-ref diagnostics key)
                                 'info
                                 '()))))
           diagnostics))
         '()))
   (define (inspection-overlays _provider _subject) '())
   (define (inspection-actions _provider _subject) '())])

(define render-diagnostics-inspection-provider
  (render-diagnostics-inspection-provider-value))

(struct formula-inspection-provider-value ()
  #:transparent
  #:methods gen:inspection-provider
  [(define (inspection-sections _provider subject)
     (define formula (subject-formula subject))
     (cond
       [(not formula) '()]
       [(not (formula-source-map formula))
        (list
         (inspector-section
          'formula-source "Formula source"
          (list (inspector-row
                 "source map" "No source map was declared" 'warning '()))
          #f))]
       [else
        (define mapping (formula-source-map formula))
        (define matches (formula-source-map-matches mapping))
        (list
         (inspector-section
          'formula-source "Formula source"
          (append
           (list (inspector-row "source" (formula-source formula) 'info '()))
           (for/list ([match (in-list matches)])
             (define span (formula-source-match-span match))
             (inspector-row
              (symbol->string (formula-source-match-name match))
              (hasheq 'text (formula-source-match-text match)
                      'span (list (source-span-start span) (source-span-end span))
                      'paths (formula-source-match-relative-paths match))
              'info
              (formula-source-row-actions subject match))))
          matches))]))
   (define (inspection-overlays _provider subject)
     (define formula (subject-formula subject))
     (if (and formula (formula-source-map formula))
         (let ([selected-match (subject-formula-source-match subject)])
           (for/list ([match (in-list (formula-source-map-matches
                                       (formula-source-map formula)))])
             (define selected? (equal? match selected-match))
           (inspector-overlay
            (formula-source-match-name match)
            'formula-source-unit
            (formula-source-match-relative-paths match)
            (hasheq 'color (if selected? "crimson" "goldenrod")
                    'width (if selected? 2 1))
            (hasheq 'span (formula-source-match-span match)
                    'text (formula-source-match-text match)
                    'root-path (inspector-subject-root-path subject)
                    'selected? selected?))))
         '()))
   (define (inspection-actions _provider _subject) '())])

(define formula-inspection-provider
  (formula-inspection-provider-value))

;; A source unit may map to several rendered leaves (for example, a declared
;; fraction spans more than one glyph group). The current path-based preview
;; can select one Visual at a time, so only expose a live selection action for
;; an unambiguous leaf. The immutable row still exposes its source span and
;; the preview overlay outlines every mapped leaf in either case.
(define (formula-source-row-actions subject match)
  (define root-path (inspector-subject-root-path subject))
  (define relative-paths (formula-source-match-relative-paths match))
  (define selectable?
    (and (list? root-path) (pair? root-path)
         (= (length relative-paths) 1)))
  (list
   (inspector-action
    'select-source-unit "Select mapped leaf"
    (if selectable?
        `(select-source-unit ,(append root-path (car relative-paths)))
        '(select-source-unit))
    selectable?)
   (inspector-action
    'copy-selector "Copy selector"
    `(copy-selector ,(formula-source-match-span match)) #t)))

(struct relation-inspection-provider-value ()
  #:transparent
  #:methods gen:inspection-provider
  [(define (inspection-sections _provider subject)
     (define relation (subject-relation subject))
     (if relation
         (list
          (inspector-section
           'relation "Relation"
           (list
            (inspector-row "phase" (relation-visual-phase relation) 'info '())
            (inspector-row "structure" (relation-visual-structure relation) 'info '())
            (inspector-row "dependencies"
                           (relation-visual-dependencies relation) 'info '())
            (inspector-row "cacheability"
                           (relation-visual-cacheability relation)
                           (if (eq? (relation-visual-cacheability relation) 'disabled)
                               'warning
                               'info)
                           '()))
           #f))
         '()))
   (define (inspection-overlays _provider subject)
     (define relation (subject-relation subject))
     (define relation-path (inspector-subject-root-path subject))
     (if (and relation relation-path)
         (append*
          (for/list ([dependency (in-list (relation-visual-dependencies relation))]
                     [index (in-naturals)])
            (for/list ([dependency-path
                        (in-list (relation-dependency-visual-paths dependency))])
              (inspector-overlay
               (list 'relation-dependency index dependency-path)
               'relation-dependency
               (hasheq 'dependency-path dependency-path
                       'relation-path relation-path)
               (hasheq 'color "mediumpurple" 'width 1)
               (hasheq 'dependency dependency
                       'anchor (and (anchor-dependency? dependency)
                                    (anchor-dependency-anchor dependency)))))))
         '()))
   (define (inspection-actions _provider subject)
     (if (subject-relation subject)
         (list
          (inspector-action
           'copy-dependencies "Copy relation dependencies"
           `(copy-relation-dependencies ,(inspector-subject-root-path subject)) #t))
         '()))])

(define relation-inspection-provider
  (relation-inspection-provider-value))

;; Only Visual and anchor dependencies have a world-space location. Value
;; dependencies remain visible in the relation table, but no fake arrow is
;; invented for a scalar or scene parameter. Selection dependencies expand to
;; their immutable absolute paths in source order.
(define (relation-dependency-visual-paths dependency)
  (cond
    [(visual-dependency? dependency)
     (list (visual-target-path (visual-dependency-target dependency)
                               'relation-inspection-provider))]
    [(anchor-dependency? dependency)
     (list (visual-target-path (anchor-dependency-target dependency)
                               'relation-inspection-provider))]
    [(selection-dependency? dependency)
     (visual-selection-absolute-paths
      (selection-dependency-selection dependency))]
    [else '()]))


;;;
;;; Active String-Transition Provider
;;;

;; This provider renders a stable, source-oriented view of the exact plan
;; attached at compilation time.  It deliberately returns overlays as semantic
;; source/destination selections: the preview UI can draw them without adding
;; any Visual to the sampled Scene or disturbing a frame cache.
(struct transition-inspection-provider-value ()
  #:transparent
  #:methods gen:inspection-provider
  [(define (inspection-sections _provider subject)
     (transition-inspection-sections subject))
   (define (inspection-overlays _provider subject)
     (transition-inspection-overlays subject))
   (define (inspection-actions _provider subject)
     (transition-inspection-actions subject))])

(define (transition-inspection-sections subject)
  (for/list ([inspection (in-list (subject-transition-inspections subject))]
             #:when (eq? (animation-inspection-kind inspection)
                          'string-transition))
    (define plan (hash-ref (animation-inspection-data inspection) 'plan))
    (inspector-section
     'string-matching
     "String matching"
     (append
      (for/list ([match (in-list (string-match-plan-matches plan))]
                 [index (in-naturals)])
        (string-transition-match-row plan match index))
      (unmatched-rows "unmatched source"
                      (string-match-plan-unmatched-source plan))
      (unmatched-rows "unmatched destination"
                      (string-match-plan-unmatched-destination plan))
      (for/list ([diagnostic (in-list (string-match-plan-diagnostics plan))])
        (inspector-row "diagnostic" diagnostic 'warning '())))
     (string-match-plan->datum plan))))

(define (string-transition-match-row plan match index)
  (inspector-row
   (format "match ~a" index)
   (hasheq
    'source-span (span->list (planned-string-match-source-span match))
    'destination-span (span->list (planned-string-match-destination-span match))
    'source-text (span-text (formula-source (string-match-plan-source plan))
                            (planned-string-match-source-span match))
    'destination-text (span-text (formula-source (string-match-plan-destination plan))
                                 (planned-string-match-destination-span match))
    'reason (planned-string-match-reason match)
    'movement-mode (planned-string-match-movement-mode match)
    'route (planned-string-match-route match)
    'appearance-complete-at-x
    (planned-string-match-appearance-complete-at-x match)
    'appearance-duration
    (planned-string-match-appearance-duration match)
    'consume? #t)
   'info
   (list
    (inspector-action
     'copy-string-match
     "Copy string match"
     `(copy-string-match
       ,(planned-string-match-source-span match)
       ,(planned-string-match-destination-span match))
     #t))))

(define (transition-inspection-overlays subject)
  (append*
   (for/list ([inspection (in-list (subject-transition-inspections subject))]
              #:when (eq? (animation-inspection-kind inspection)
                           'string-transition))
     (define plan (hash-ref (animation-inspection-data inspection) 'plan))
     (for/list ([match (in-list (string-match-plan-matches plan))]
                [index (in-naturals)])
       (inspector-overlay
        (string->symbol (format "string-match-~a" index))
        'string-match-route
        (hasheq 'source-selection (planned-string-match-source-selection match)
                'destination-selection
                (planned-string-match-destination-selection match)
                ;; These are compiler-derived local paths under the formula
                ;; target, not guesses based on a transient rendered glyph.
                ;; A changed match can have two fade layers but remains one
                ;; semantic formula-transition-route here.
                'target-path (string-transition-target-path inspection)
                'routes (string-match-compiled-routes inspection match))
        (hasheq 'color "goldenrod")
        (hasheq 'reason (planned-string-match-reason match)
                'movement-mode (planned-string-match-movement-mode match)
                'route (planned-string-match-route match)
                'appearance-complete-at-x
                (planned-string-match-appearance-complete-at-x match)
                'appearance-duration
                (planned-string-match-appearance-duration match)))))))

;; The source map records local formula part paths. String matching presently
;; requires whole declared fragments, so preserving only one-symbol paths is
;; both exact and defensive: a future nested source map simply produces no
;; route overlay until it has an explicit transition representation.
(define (selection-local-part-names selection)
  (if (visual-selection? selection)
      (for/list ([path (in-list (visual-selection-paths selection))]
                 #:when (and (pair? path) (null? (cdr path)) (symbol? (car path))))
        (car path))
      '()))

(define (string-transition-target-path inspection)
  (define data (animation-inspection-data inspection))
  (define target-id (hash-ref data 'target-id #f))
  (and (symbol? target-id) (list target-id)))

(define (string-match-compiled-routes inspection match)
  (define data (animation-inspection-data inspection))
  (define compiled-plan (hash-ref data 'compiled-plan #f))
  (cond
    [(not (formula-transition-plan? compiled-plan)) '()]
    [else
     (define source-names
       (selection-local-part-names
        (planned-string-match-source-selection match)))
     (define destination-names
       (selection-local-part-names
        (planned-string-match-destination-selection match)))
     (append*
      (for/list ([source-name (in-list source-names)]
                 [destination-name (in-list destination-names)])
        (formula-transition-plan-match-routes
         compiled-plan source-name destination-name)))]))

(define (transition-inspection-actions subject)
  (append*
   (for/list ([inspection (in-list (subject-transition-inspections subject))]
              #:when (eq? (animation-inspection-kind inspection)
                           'string-transition))
     (define plan (hash-ref (animation-inspection-data inspection) 'plan))
     (for/list ([match (in-list (string-match-plan-matches plan))])
       (inspector-action
        'copy-string-match
        "Copy string match"
        `(copy-string-match
          ,(planned-string-match-source-span match)
          ,(planned-string-match-destination-span match))
        #t)))))

(define transition-inspection-provider
  (transition-inspection-provider-value))

(define (subject-transition-inspections subject)
  (define value (inspector-subject-value subject))
  (if (and (list? value) (andmap animation-inspection? value)) value '()))

(define (span->list span)
  (list (source-span-start span) (source-span-end span)))

(define (span-text source span)
  (substring source (source-span-start span) (source-span-end span)))

(define (unmatched-rows label units)
  (for/list ([unit (in-list units)])
    (inspector-row label (format "~s" unit) 'warning '())))


;;;
;;; Sampled Relation Inspection
;;;

;; This narrow adapter is intentionally outside the static relation provider:
;; asking for a sampled report can run an author resolver, while constructing
;; ordinary inspector documents for scenes and formulas must remain a cheap,
;; declaration-only operation. Only a selected relation at a stable path opts
;; into the report.
(define (relation-sample-inspection-sections state subject)
  (define relation (subject-relation subject))
  (define path (inspector-subject-root-path subject))
  (cond
    [(not (and relation path)) '()]
    [else
     (with-handlers
         ([exn:fail?
           (lambda (error)
             (list
              (inspector-section
               'relation-resolution "Relation resolution"
               (list (inspector-row "sample report" (exn-message error) 'warning '()))
               #f)))])
       (define report (scene-relation-sample-report state path))
       (define used (relation-resolution-report-used-dependencies report))
       (define unused (relation-resolution-report-unused-dependencies report))
       (list
        (inspector-section
         'relation-resolution "Relation resolution"
         (append
          (list
           (inspector-row "used at this sample"
                          (or used "unknown: renderer-aware layout is required")
                          (if used 'info 'warning) '())
           (inspector-row "unused at this sample"
                          (or unused "unknown")
                          (if unused 'info 'warning) '()))
          (for/list ([warning (in-list (relation-resolution-report-warnings report))])
            (inspector-row "diagnostic" warning 'warning '())))
         #f)))]))


;;;
;;; Subject Resolution
;;;

(define (subject-value-at-state subject state)
  (case (inspector-subject-kind subject)
    [(scene) state]
    [(visual relation-dependency)
     (or (inspector-subject-value subject)
         (and (inspector-subject-root-path subject)
              (scene-state-ref state (inspector-subject-root-path subject))))]
    [(formula-source-match)
     ;; The match is part of the semantic subject, not merely a lookup hint.
     ;; Retain it through document construction so providers can distinguish
     ;; one selected source unit from the other units of the same formula.
     (inspector-subject-value subject)]
    [else (inspector-subject-value subject)]))

(define (subject-formula subject)
  (define value (inspector-subject-value subject))
  (cond
    [(formula-assembly-visual? value) value]
    [(and (pair? value) (formula-assembly-visual? (car value))) (car value)]
    [else #f]))

(define (subject-formula-source-match subject)
  (and (eq? (inspector-subject-kind subject) 'formula-source-match)
       (formula-source-match? (cdr (inspector-subject-value subject)))
       (cdr (inspector-subject-value subject))))

(define (subject-relation subject)
  (and (relation-visual? (inspector-subject-value subject))
       (inspector-subject-value subject)))

(define (source-location->datum location)
  (unless (source-location? location)
    (raise-argument-error 'source-location->datum "source-location?" location))
  (hasheq 'source (source-location-source location)
          'line (source-location-line location)
          'column (source-location-column location)
          'position (source-location-position location)
          'span (source-location-span location)))

;; Inspector values may be handed to a GUI eventspace or a REPL. Copy caller
;; supplied diagnostic maps so neither side can mutate the document after it
;; has been constructed. `for/hash` returns an immutable equal?-keyed map,
;; which is appropriate for arbitrary diagnostic field names.
(define (immutable-hash-snapshot value)
  (for/hash ([(key entry) (in-hash value)])
    (values key entry)))

(define (visual-kind-name visual)
  (cond
    [(formula-assembly-visual? visual) 'formula-assembly]
    [else
     (let ([printed (format "~s" visual)])
       (cond [(regexp-match #rx"^#\\(struct:([^ ]+)" printed)
              => (lambda (match) (string->symbol (cadr match)))]
             [else 'visual]))]))

(define (check-root-path who path)
  (unless (and (list? path) (pair? path) (andmap symbol? path))
    (raise-argument-error who "nonempty list of symbols" path)))
