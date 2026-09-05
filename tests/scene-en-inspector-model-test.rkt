#lang racket/base

;;;
;;; SCENE-EN Headless Inspector Document Tests
;;;

(require rackunit
         racket/list
         "../main.rkt"
         "../authoring.rkt"
         "../preview.rkt"
         "../private/formula-source-map.rkt"
         "../private/source-document.rkt")

(module+ test
  (define equation
    (math-tex #:id 'equation #:source-map 'tokens "x + x"))
  (define formula-scene
    (scene-add (make-scene) equation))
  (define formula-document
    (scene-inspector-document
     formula-scene 0
     #:subject (visual-inspector-subject equation '(equation))))
  (check-true (inspector-document? formula-document))
  (check-equal? (hash-ref (inspector-document-sample formula-document) 'time) 0)
  (check-equal?
   (map inspector-section-id (inspector-document-sections formula-document))
   '(visual formula-source camera))
  (define source-section
    (second (inspector-document-sections formula-document)))
  (check-equal? (inspector-row-value (car (inspector-section-rows source-section)))
                "x + x")
  (check-equal? (length (inspector-document-overlays formula-document)) 3)
  (define first-source-row (second (inspector-section-rows source-section)))
  (define select-source-action
    (for/first ([action (in-list (inspector-row-actions first-source-row))]
                #:when (eq? (inspector-action-id action) 'select-source-unit))
      action))
  (check-true (inspector-action-enabled? select-source-action))
  (check-equal? (inspector-action-command select-source-action)
                '(select-source-unit (equation source-token-0)))
  (check-equal? (inspector-action-command
                 (car (inspector-document-actions formula-document)))
                '(copy-path (equation)))
  (define camera-section
    (third (inspector-document-sections formula-document)))
  (check-equal? (inspector-section-id camera-section) 'camera)
  (check-equal? (inspector-row-label (car (inspector-section-rows camera-section)))
                "pixels")

  (define relation
    (relation-visual
     (circle #:id 'follower #:radius 1/4 #:fill "gold")
     #:depends-on (list (value-dependency 'offset))
     #:cache-key 'follower-v1
     (lambda (context template) template)))
  (define relation-scene
    (scene-add (scene-set-value (make-scene) 'offset 1) relation))
  (define relation-document
    (scene-inspector-document
     relation-scene 0
     #:subject (relation-dependency-subject relation '(follower))))
  (check-equal?
   (map inspector-section-id (inspector-document-sections relation-document))
   '(visual relation relation-resolution camera))
  (define relation-section
    (second (inspector-document-sections relation-document)))
  (check-equal?
   (inspector-row-value (first (inspector-section-rows relation-section)))
   'semantic)
  (check-equal?
   (inspector-row-value (fourth (inspector-section-rows relation-section)))
   'explicit-key)
  (check-equal?
   (inspector-action-command
    (second (inspector-document-actions relation-document)))
   '(copy-relation-dependencies (follower)))
  ;; The resolver deliberately ignores its declared value, so the sampled
  ;; inspector makes that distinction visible instead of equating declared
  ;; dependencies with ones used in this frame.
  (define resolution-section
    (third (inspector-document-sections relation-document)))
  (check-equal?
   (inspector-row-value (first (inspector-section-rows resolution-section)))
   '())
  (check-equal?
   (inspector-row-value (second (inspector-section-rows resolution-section)))
   (list (value-dependency 'offset)))
  (check-equal? (inspector-document-overlays relation-document) '())

  ;; Camera, source-block, and render diagnostics have their own providers.
  ;; They are metadata snapshots, not inferred scene Visuals or a second
  ;; render request. A caller can therefore inspect a source program and its
  ;; current worker report through the same immutable document in a headless
  ;; editor integration.
  (define mutable-render-diagnostics
    (make-hasheq (list (cons 'render-milliseconds 17)
                       (cons 'cache 'hit))))
  (define source-block
    (inspector-source-block
     'setup 0 1
     (source-location "derivative.rkt" 12 3 180 42)
     4 'verified))
  (define supplemental-document
    (scene-inspector-document
     formula-scene 0
     #:source-block source-block
     #:render-diagnostics mutable-render-diagnostics))
  ;; The document snapshots input diagnostics before returning; a later
  ;; controller update cannot mutate a snapshot already given to the GUI.
  (hash-set! mutable-render-diagnostics 'cache 'miss)
  (check-equal?
   (map inspector-section-id (inspector-document-sections supplemental-document))
   '(camera source-block render-diagnostics))
  (define source-block-section
    (second (inspector-document-sections supplemental-document)))
  (check-equal? (inspector-row-value (car (inspector-section-rows source-block-section)))
                'setup)
  (check-equal? (inspector-row-value (second (inspector-section-rows source-block-section)))
                '(0 1))
  (define diagnostic-section
    (third (inspector-document-sections supplemental-document)))
  (check-equal? (inspector-row-value
                 (for/first ([row (in-list (inspector-section-rows diagnostic-section))]
                             #:when (equal? (inspector-row-label row) "cache"))
                   row))
                'hit)
  (check-true (immutable? (car (inspector-document-diagnostics supplemental-document))))
  (define source-location-row
    (for/first ([row (in-list (inspector-section-rows source-block-section))]
                #:when (equal? (inspector-row-label row) "source location"))
      row))
  (check-equal? (map inspector-action-id (inspector-row-actions source-location-row))
                '(copy-source-location))
  (check-equal?
   (map inspector-action-id
        (inspector-row-actions (car (inspector-section-rows diagnostic-section))))
   '(copy-render-diagnostics))
  (check-equal? (inspector-document-actions supplemental-document) '())
  (check-equal?
   (inspector-subject-kind (source-block-inspector-subject source-block))
   'source-block)
  (check-equal?
   (inspector-subject-kind
    (render-diagnostics-inspector-subject (hasheq 'cache 'hit)))
   'render-diagnostics)

  ;; Spatial relation dependencies become preview-only arrows. Scalar values
  ;; remain rows in the report but deliberately have no invented screen
  ;; location. The overlay itself is just immutable paths and style metadata.
  (define overlay-anchor (circle #:id 'anchor #:radius 1/4 #:fill "skyblue"))
  (define overlay-relation
    (relation-visual
     (circle #:id 'follower #:radius 1/4 #:fill "gold")
     #:depends-on (list (visual-dependency 'anchor)
                        (value-dependency 'offset))
     #:cache-key 'overlay-v1
     (lambda (_context template) template)))
  (define overlay-document
    (scene-inspector-document
     (scene-add
      (scene-add (scene-set-value (make-scene) 'offset 1) overlay-anchor)
      overlay-relation)
     0
     #:subject (relation-dependency-subject overlay-relation '(follower))))
  (define dependency-overlay
    (for/first ([overlay (in-list (inspector-document-overlays overlay-document))]
                #:when (eq? (inspector-overlay-kind overlay)
                            'relation-dependency))
      overlay))
  (check-not-false dependency-overlay)
  (check-equal? (hash-ref (inspector-overlay-geometry dependency-overlay)
                          'dependency-path)
                '(anchor))
  (check-equal? (hash-ref (inspector-overlay-geometry dependency-overlay)
                          'relation-path)
                '(follower))

  ;; A relation participates in the generic style protocols so that supported
  ;; outer styles remain animatable. Its text template has no fill, though.
  ;; Inspector traversal must report that absent optional style rather than
  ;; aborting every canvas hit test before it reaches an unrelated dot.
  (define clickable-dot
    (circle #:id 'clickable-dot #:center (vec2 1 -1) #:radius 1/4
            #:fill "tomato"))
  (define clickable-caption
    (follow-above
     (plain-text "follows the dot" #:id 'clickable-caption #:font-size 1/5)
     'clickable-dot #:gap 1/5))
  (define clickable-scene
    (scene-add (make-scene) clickable-dot clickable-caption))
  (define clickable-camera (scene-camera-at clickable-scene 0))
  (define-values (clickable-pixel-x clickable-pixel-y)
    (camera-world->pixel clickable-camera (visual-position clickable-dot)))
  (define clickable-inspection
    (scene-hit-test clickable-scene 0 clickable-pixel-x clickable-pixel-y
                    #:camera clickable-camera))
  (check-not-false clickable-inspection)
  (check-equal? (visual-inspection-path clickable-inspection)
                '(clickable-dot))

  ;; Source-character selection remains deterministic and never guesses across
  ;; whitespace.  The reverse query preserves repeated source occurrences.
  (define first-source-match
    (formula-source-match-at-index equation 0))
  (check-true (formula-source-match? first-source-match))
  (check-false (formula-source-match-at-index equation 1))
  (define source-subject
    (formula-source-index-subject equation 0 '(equation)))
  (check-true (inspector-subject? source-subject))
  (check-equal?
   (inspector-subject-kind source-subject)
   'formula-source-match)
  (check-equal?
   (formula-source-match-selection equation first-source-match)
   (formula-source-match-selection
    equation
    (cdr (inspector-subject-value source-subject))))
  (check-true
   (pair?
    (formula-leaf-source-matches
     equation
     (car (formula-source-match-relative-paths first-source-match)))))

  ;; A renderer-independent Visual-path click promotes a mapped formula leaf
  ;; to its exact source unit.  The resulting document retains the formula
  ;; root path for preview-only overlays and marks precisely that one unit;
  ;; no pixel position or GUI callback participates in the decision.
  (define clicked-leaf-path
    (append '(equation)
            (car (formula-source-match-relative-paths first-source-match))))
  (define clicked-subject
    (scene-inspector-subject-at-path
     (scene-sample formula-scene 0) clicked-leaf-path))
  (check-equal? (inspector-subject-kind clicked-subject)
                'formula-source-match)
  (check-equal? (inspector-subject-root-path clicked-subject) '(equation))
  (check-equal? (cdr (inspector-subject-value clicked-subject))
                first-source-match)
  (define clicked-document
    (scene-inspector-document formula-scene 0 #:subject clicked-subject))
  (define selected-source-overlay
    (for/first ([overlay (in-list (inspector-document-overlays clicked-document))]
                #:when (and (eq? (inspector-overlay-kind overlay)
                                'formula-source-unit)
                            (hash-ref (inspector-overlay-metadata overlay)
                                      'selected? #f)))
      overlay))
  (check-not-false selected-source-overlay)
  (check-equal? (inspector-overlay-id selected-source-overlay)
                (formula-source-match-name first-source-match))
  (check-equal? (hash-ref (inspector-overlay-metadata selected-source-overlay)
                          'root-path)
                '(equation))

  ;; String matching retains the actual source planner plan on the compiled
  ;; animation.  The same metadata is discoverable inside the clip and at the
  ;; exact scene endpoint, where clip lookup deliberately uses the completed
  ;; final clip.
  (define before (math-tex #:id 'equation #:source-map 'tokens "x + 1"))
  (define after (math-tex #:id 'equation #:source-map 'tokens "x + 2"))
  (define transition-scene
    (scene-play
     (scene-add (make-scene) before)
     (transform-matching-strings before after)
     #:duration 1))
  (check-equal? (scene-clip-index-at transition-scene 0) 0)
  (check-equal? (scene-clip-index-at transition-scene 1) 0)
  (define inspections-at-half
    (scene-animation-inspections-at transition-scene 1/2))
  (check-equal? (length inspections-at-half) 1)
  (check-equal?
   (animation-inspection-kind (car inspections-at-half))
   'string-transition)
  (check-equal?
   (scene-animation-inspections-at transition-scene 1)
   inspections-at-half)
  (define retained-plan
    (hash-ref (animation-inspection-data (car inspections-at-half)) 'plan))
  (define unchanged-plan-report
    (compare-string-match-plans retained-plan retained-plan))
  (check-equal? (hash-ref unchanged-plan-report 'matches-added) '())
  (check-equal? (hash-ref unchanged-plan-report 'matches-removed) '())
  (check-equal? (hash-ref unchanged-plan-report 'matches-changed) '())
  (define transition-document
    (scene-inspector-document transition-scene 1/2))
  (check-not-false
   (member 'string-matching
           (map inspector-section-id
                (inspector-document-sections transition-document))))
  ;; An interior string-transition layer preserves the formula's renderer
  ;; shape but deliberately does not pretend to be source-addressable. The
  ;; preview therefore retains the String matching explanation while hiding
  ;; its Formula source canvas for this transient value.
  (define transition-layer
    (scene-state-ref (scene-sample transition-scene 1/2) '(equation)))
  (check-true (formula-assembly-visual? transition-layer))
  (check-false (formula-source-map transition-layer))
  (define matching-section
    (for/first ([section (in-list (inspector-document-sections transition-document))]
                #:when (eq? (inspector-section-id section) 'string-matching))
      section))
  (check-true (pair? (inspector-section-rows matching-section)))
  (check-true
   (for/or ([overlay (in-list (inspector-document-overlays transition-document))])
     (eq? (inspector-overlay-kind overlay) 'string-match-route)))
  ;; The route overlay is compiled against the actual current formula, rather
  ;; than guessing a correspondence from temporary interior layer names. One
  ;; semantic string match therefore exposes a stable target path and route
  ;; even when a changed fragment renders as a cross-fade pair.
  (define string-route-overlay
    (for/first ([overlay (in-list (inspector-document-overlays transition-document))]
                #:when (eq? (inspector-overlay-kind overlay)
                            'string-match-route))
      overlay))
  (check-equal? (hash-ref (inspector-overlay-geometry string-route-overlay)
                          'target-path)
                '(equation))
  (define compiled-routes
    (hash-ref (inspector-overlay-geometry string-route-overlay) 'routes))
  (check-true (pair? compiled-routes))

  ;; Reload selection recovery is semantic rather than a blind reuse of a
  ;; nested path. An unchanged path wins; when a formula root is renamed, a
  ;; unique named part can retain the author’s selection. Duplicate candidate
  ;; parts are deliberately cleared instead of silently retargeting it.
  (define (selection-session source)
    (define session
      (open-preview-controller
       source #:fps 2 #:prefetch 0
       #:producer (lambda (_document sample _spec _token) sample)
       #:byte-size (lambda (_value) 1)))
    (attach-preview-transactions! session)
    session)
  (define direct-old
    (scene-add (make-scene) (circle #:id 'dot #:radius 1/4)))
  (define direct-new
    (scene-add (make-scene) (circle #:id 'dot #:center (vec2 1 0) #:radius 1/4)))
  (define direct-session (selection-session direct-old))
  (void (preview-select! direct-session '(dot)))
  (void (preview-set-source! direct-session direct-new))
  (void (preview-rebase-transactions! direct-session direct-new))
  (check-equal? (preview-selection direct-session) '(dot))
  (check-equal? (preview-selection-reload-diagnostic direct-session)
                "selection retained after reload: exact Visual path")
  (preview-close! direct-session)

  (define named-old (math-tex #:id 'before #:source-map 'tokens "x"))
  (define part-name (car (formula-assembly-visual-part-names named-old)))
  (define named-new (math-tex #:id 'after #:source-map 'tokens "x"))
  (define named-session
    (selection-session (scene-add (make-scene) named-old)))
  (void (preview-select! named-session (list 'before part-name)))
  (define named-scene (scene-add (make-scene) named-new))
  (void (preview-set-source! named-session named-scene))
  (void (preview-rebase-transactions! named-session named-scene))
  (check-equal? (preview-selection named-session) (list 'after part-name))
  (check-equal? (preview-selection-reload-diagnostic named-session)
                "selection retained after reload: unique named formula part")
  (preview-close! named-session)

  ;; The source-span fallback is intentionally later than a named-part match.
  ;; Here the author has renamed both the root and fragment, but preserved the
  ;; formula's canonical source and one mapped [0,1) source unit.
  (define (mapped-single-part id part-id)
    (formula-assembly
     (list (latex-formula-part "x" #:name part-id))
     #:id id
     #:source-map
     (make-formula-source-map
      (source-document-from-strings (list "x"))
      (list
       (formula-source-match
        (source-span 0 1) "x" part-id (list (list part-id)))))))
  (define source-old (mapped-single-part 'legacy 'old-token))
  (define source-new (mapped-single-part 'revised 'new-token))
  (define source-session
    (selection-session (scene-add (make-scene) source-old)))
  (void (preview-select! source-session '(legacy old-token)))
  (define source-scene (scene-add (make-scene) source-new))
  (void (preview-set-source! source-session source-scene))
  (void (preview-rebase-transactions! source-session source-scene))
  (check-equal? (preview-selection source-session) '(revised new-token))
  (check-equal? (preview-selection-reload-diagnostic source-session)
                "selection retained after reload: exact formula source span")
  (preview-close! source-session)

  (define ambiguity-session
    (selection-session (scene-add (make-scene) named-old)))
  (void (preview-select! ambiguity-session (list 'before part-name)))
  (define ambiguous-scene
    (scene-add
     (scene-add (make-scene) (math-tex #:id 'left #:source-map 'tokens "x"))
     (math-tex #:id 'right #:source-map 'tokens "x")))
  (void (preview-set-source! ambiguity-session ambiguous-scene))
  (void (preview-rebase-transactions! ambiguity-session ambiguous-scene))
  (check-false (preview-selection ambiguity-session))
  (check-equal? (preview-selection-reload-diagnostic ambiguity-session)
                "selection cleared after reload: named formula part is ambiguous")
  (preview-close! ambiguity-session))
