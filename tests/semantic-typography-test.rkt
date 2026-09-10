#lang racket/base

;; Semantic typography stays immutable until a render boundary.  These tests
;; characterize both the data contract and one headless Pict realization.

(require racket/async-channel
         racket/class
         rackunit
         (only-in pict filled-rectangle pict-height pict-width)
         "../authoring.rkt"
         "../colors.rkt"
         "../main.rkt"
         "../preview.rkt"
         "../project.rkt"
         "../private/inspector-document.rkt"
         "../private/render-typography-context.rkt"
         "../private/semantic-text-visual.rkt"
         "../private/section-renderer.rkt"
         "../private/text-reveal-visual.rkt")

(module+ test
  (define camera
    (make-camera #:width 320 #:height 180 #:world-width 8 #:background "white"))
  (define enlarged-theme
    (typography-theme
     #:id 'enlarged
     #:extends animate-typography-theme
     #:styles
     (hash 'title
           (text-style-update
            (typography-ref animate-typography-theme 'title)
            #:font-size 3/2)
           'body
           (text-style-update
           (typography-ref animate-typography-theme 'body)
            #:font-size 4/5))))
  (define enlarged-metadata-theme
    ;; This is the same complete appearance as `enlarged-theme`; only
    ;; descriptive theme metadata differs.  Persistent render identities must
    ;; use its fingerprint rather than its name or provenance.
    (typography-theme
     #:id 'enlarged-metadata
     #:display-name "Enlarged presentation copy"
     #:provenance 'documentation-copy
     #:extends animate-typography-theme
     #:styles
     (hash 'title
           (text-style-update
            (typography-ref animate-typography-theme 'title)
            #:font-size 3/2)
           'body
           (text-style-update
            (typography-ref animate-typography-theme 'body)
            #:font-size 4/5))))

  ;; Themes are complete, deterministic data snapshots.  Metadata may change
  ;; without changing the appearance fingerprint, but an actual style update
  ;; must partition the snapshot.
  (check-equal? (typography-style-keys animate-typography-theme)
                (sort typography-standard-style-keys symbol<?))
  (check-equal?
   (typography-theme-fingerprint animate-typography-theme)
   (typography-theme-fingerprint
    (datum->typography-theme
     (typography-theme->datum animate-typography-theme))))
  (check-not-equal? (typography-theme-fingerprint animate-typography-theme)
                    (typography-theme-fingerprint enlarged-theme))
  (check-equal? (typography-theme-fingerprint enlarged-theme)
                (typography-theme-fingerprint enlarged-metadata-theme))
  (check-equal?
   (text-style-font-face
    (text-style-update
     (text-style #:font-face "A" #:font-family 'swiss #:font-size 1/2
                 #:font-style 'normal #:font-weight 'normal #:color "black"
                 #:line-spacing 1 #:line-alignment 'left
                 #:horizontal-alignment 'left #:vertical-alignment 'top)
     #:font-face #f))
   #f)

  ;; The authored object stores the role and override, not a font/color chosen
  ;; from the currently active rendering context.
  (define heading
    (title-text "A semantic title" #:id 'heading #:center origin))
  (check-true (semantic-text-visual? heading))
  (check-eq? (semantic-text-style-key heading) 'title)
  (check-equal? (semantic-text-content heading) "A semantic title")
  (define lowered-default
    (semantic-text->text-visual
     heading
     (make-render-typography-context animate-typography-theme)))
  (define lowered-enlarged
    (semantic-text->text-visual
     heading
     (make-render-typography-context enlarged-theme)))
  (check-equal? (text-visual-font-size lowered-default) 3/4)
  (check-equal? (text-visual-font-size lowered-enlarged) 3/2)
  (define semantic-rich
    (styled-rich-text #:style 'body #:id 'semantic-rich
                      (text-span "one" #:font-weight 'bold)
                      " two"))
  (check-equal? (map text-span-content (semantic-text-spans semantic-rich))
                '("one" " two"))
  (check-equal? (map text-span-content
                     (text-visual-spans
                      (semantic-text->text-visual
                       semantic-rich
                       (make-render-typography-context animate-typography-theme))))
                '("one" " two"))

  ;; A raw constructor remains raw even when a typography snapshot is supplied.
  (define raw
    (plain-text "Raw text" #:id 'raw #:font-size 1/2))
  (check-equal?
   (pict-height (visual->pict raw camera #:typography animate-typography-theme))
   (pict-height (visual->pict raw camera #:typography enlarged-theme)))
  (check-true
   (> (pict-height (visual->pict heading camera #:typography enlarged-theme))
      (pict-height (visual->pict heading camera #:typography animate-typography-theme))))

  ;; Typography keeps its color symbolic until the ordinary color boundary.
  ;; The exact same semantic title therefore remains authored once while its
  ;; rendered pixels follow the selected light or dark color snapshot.
  (define themed-heading-scene
    (scene-wait (scene-add (make-scene) heading) 1))
  (define (bitmap-bytes bitmap)
    (define bytes (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
    (send bitmap get-argb-pixels 0 0
          (send bitmap get-width) (send bitmap get-height) bytes)
    bytes)
  (check-not-equal?
   (bitmap-bytes
    (scene-frame->bitmap themed-heading-scene 0 #:fps 1 #:camera camera
                         #:theme animate-light-theme))
   (bitmap-bytes
    (scene-frame->bitmap themed-heading-scene 0 #:fps 1 #:camera camera
                         #:theme animate-dark-theme)))

  ;; Lowering semantic text before renderer dispatch preserves existing custom
  ;; `text-visual?` renderers.  A third-party renderer does not need a new
  ;; semantic-text protocol merely because callers use a role constructor.
  (define custom-text-pict (filled-rectangle 47 19 #:color "tomato"))
  (struct custom-text-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual) (text-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera) custom-text-pict)])
  (define custom-heading-pict
    (visual->pict heading camera
                  #:renderers (cons (custom-text-renderer) default-pict-renderers)))
  (check-= (pict-width custom-heading-pict) (pict-width custom-text-pict) 1e-9)
  (check-= (pict-height custom-heading-pict) (pict-height custom-text-pict) 1e-9)

  ;; Code's built-in treatment is visible geometry around the lowered text.
  (define code (code-text "(add1 x)" #:id 'code))
  (check-true
   (> (pict-width (visual->pict code camera))
      (pict-width (visual->pict
                   (plain-text "(add1 x)" #:id 'raw-code
                               #:font-family 'modern #:font-size 7/20)
                   camera))))

  ;; Explicit renderer-measured snapshots use their supplied typography rather
  ;; than whichever default happens to be available during the call.
  (define body
    (body-text "The body role can wrap under a chosen typography snapshot."
               #:id 'body #:center origin #:width 3))
  (define body-default-box
    (visual-layout-box body #:camera camera #:typography animate-typography-theme))
  (define body-enlarged-box
    (visual-layout-box body #:camera camera #:typography enlarged-theme))
  (check-true (> (layout-box-height body-enlarged-box)
                 (layout-box-height body-default-box)))
  (define layout-left
    (visual-place-left-of
     (label-text "label" #:id 'layout-label)
     heading
     #:camera camera #:typography animate-typography-theme))
  (define layout-right
    (visual-place-left-of
     (label-text "label" #:id 'layout-label-large)
     heading
     #:camera camera #:typography enlarged-theme))
  (check-true (< (vec2-x (visual-position layout-right))
                 (vec2-x (visual-position layout-left))))
  (define fit-default
    (camera-fit-visuals (list heading) #:camera camera
                        #:typography animate-typography-theme))
  (define fit-enlarged
    (camera-fit-visuals (list heading) #:camera camera
                        #:typography enlarged-theme))
  (check-true (> (camera-fit-request-world-width fit-enlarged)
                 (camera-fit-request-world-width fit-default)))

  ;; A treatment is renderer-visible geometry, but symmetric padding leaves
  ;; callers free to use the same requested rendered-box anchor.
  (define treated-body
    (body-text "anchored"
               #:id 'treated-body
               #:horizontal-alignment 'left
               #:vertical-alignment 'top
               #:treatment (text-treatment #:background "ivory"
                                            #:border-color "black"
                                            #:border-width 1
                                            #:padding-x 1/2 #:padding-y 1/4)))
  (define treatment-anchor (vec2 2 -1))
  (define placed-treated-body
    (visual-place-at treated-body treatment-anchor #:anchor 'top-left
                     #:camera camera #:typography animate-typography-theme))
  (define measured-treatment-anchor
    (visual-layout-anchor placed-treated-body 'top-left #:camera camera
                          #:typography animate-typography-theme))
  (check-= (vec2-x measured-treatment-anchor) (vec2-x treatment-anchor) 1e-9)
  (check-= (vec2-y measured-treatment-anchor) (vec2-y treatment-anchor) 1e-9)

  ;; Matrix/table auto sizing is a construction snapshot.  Its chosen cell
  ;; dimensions therefore reflect the selected typography at construction,
  ;; but the returned ordinary group carries no mutable theme dependency.
  (define matrix-default
    (matrix (list (list heading)) #:id 'matrix-default
            #:entry-width 'auto #:entry-height 'auto
            #:typography animate-typography-theme))
  (define matrix-enlarged
    (matrix (list (list heading)) #:id 'matrix-enlarged
            #:entry-width 'auto #:entry-height 'auto
            #:typography enlarged-theme))
  (define table-default
    (table (list (list heading)) #:id 'table-default
           #:cell-width 'auto #:cell-height 'auto
           #:typography animate-typography-theme))
  (define table-enlarged
    (table (list (list heading)) #:id 'table-enlarged
           #:cell-width 'auto #:cell-height 'auto
           #:typography enlarged-theme))
  (check-true
   (> (layout-box-width
       (visual-layout-box matrix-enlarged #:camera camera #:typography enlarged-theme))
      (layout-box-width
       (visual-layout-box matrix-default #:camera camera #:typography animate-typography-theme))))
  (check-true
   (> (layout-box-width
       (visual-layout-box table-enlarged #:camera camera #:typography enlarged-theme))
      (layout-box-width
       (visual-layout-box table-default #:camera camera #:typography animate-typography-theme))))

  ;; A custom named role is deliberately late-bound. Construction succeeds for
  ;; a reusable scene, while resolution against a theme without the role gives
  ;; a focused lookup error.
  (define custom-theme
    (typography-theme
     #:id 'custom
     #:extends animate-typography-theme
     #:styles
     (hash 'theorem-heading
           (text-style-update
            (typography-ref animate-typography-theme 'section-heading)
            #:font-size 11/10))))
  (define theorem
    (styled-text "Theorem" #:style 'theorem-heading #:id 'theorem))
  (check-equal? (text-style-font-size
                 (resolve-semantic-text-style theorem custom-theme))
                11/10)
  (check-exn exn:fail?
             (lambda ()
               (resolve-semantic-text-style theorem animate-typography-theme)))

  ;; Project and preview identities retain the full immutable typography
  ;; snapshot. Replacing it advances preview generation, so late frames under
  ;; the old typography cannot overwrite a newer view.
  (define typography-project
    (animate-project
     #:id 'typography-test
     #:source (scene-source (scene-wait (scene-add (make-scene) heading) 1))
     #:render (render-spec #:fps 2 #:typography enlarged-theme)
     #:output (output-spec #:root "media" #:name "typography-test")))
  (define typography-plan (plan-project typography-project))
  (define recorded-typography
    (hash-ref (project-plan->datum typography-plan) 'typography-theme))
  (check-eq? (hash-ref recorded-typography 'id) 'enlarged)
  (check-equal? (hash-ref recorded-typography 'datum)
                (typography-theme->datum enlarged-theme))
  (check-equal? (hash-ref recorded-typography 'appearance-fingerprint)
                (typography-theme-fingerprint enlarged-theme))
  (check-equal? (hash-ref recorded-typography 'resolver-version)
                render-typography-resolver-version)
  ;; The two explicit render-spec replacement helpers are intentionally
  ;; orthogonal: selecting a color theme does not silently replace typography,
  ;; and selecting typography does not replace the color snapshot.
  (define combined-render-spec
    (render-spec #:theme animate-dark-theme #:typography enlarged-theme))
  (check-eq?
   (render-spec-typography
    (render-spec-with-theme combined-render-spec animate-light-theme))
   enlarged-theme)
  (check-eq?
   (render-spec-theme
    (render-spec-with-typography combined-render-spec animate-typography-theme))
   animate-dark-theme)
  ;; A persistent section cache keys on appearance plus resolver version, even
  ;; when an author supplies a source identity.  Theme metadata can therefore
  ;; change without invalidating a compatible cached image, while a real style
  ;; change cannot cross the cache boundary.
  (define typography-timeline
    (make-authored-timeline
     (scene-wait (scene-add (make-scene) heading) 1)
     #:sections (list (section 'only 0 1))))
  (define typography-entry (timeline-section typography-timeline 'only))
  (define (section-key typography)
    (automatic-section-cache-key
     typography-timeline typography-entry
     #:fps 1 #:camera #f #:renderers '() #:typography typography #:asset-files '()))
  (check-equal? (section-key enlarged-theme)
                (section-key enlarged-metadata-theme))
  (check-not-equal? (section-key animate-typography-theme)
                    (section-key enlarged-theme))
  (define preview-document
    (make-preview-document (scene-wait (scene-add (make-scene) heading) 1)))
  (define preview-sample (frame-sample 0 1))
  (check-not-equal?
   (make-preview-frame-key preview-document 0 preview-sample
                           (make-preview-render-spec #:fps 1
                                                     #:typography animate-typography-theme))
   (make-preview-frame-key preview-document 0 preview-sample
                           (make-preview-render-spec #:fps 1
                                                     #:typography enlarged-theme)))
  (define preview-session
    (open-preview-controller
     (scene-wait (scene-add (make-scene) heading) 1)
     #:typography animate-typography-theme #:prefetch 0
     #:producer (lambda (_document _sample _spec _token) 'frame)
     #:byte-size (lambda (_value) 1)))
  (dynamic-wind
   void
   (lambda ()
     (define before (preview-session-status preview-session))
     (check-eq? (preview-typography-theme preview-session)
                animate-typography-theme)
     (define preview-diagnostics (preview-session-diagnostics preview-session))
     (check-equal? (hash-ref preview-diagnostics 'typography-appearance-fingerprint)
                   (typography-theme-fingerprint animate-typography-theme))
     (check-equal? (hash-ref preview-diagnostics 'typography-resolver-version)
                   render-typography-resolver-version)
     (define after (preview-set-typography-theme! preview-session enlarged-theme))
     (check-eq? (preview-typography-theme preview-session) enlarged-theme)
     (check-true (> (preview-status-render-generation after)
                    (preview-status-render-generation before))))
   (lambda () (preview-close! preview-session)))

  ;; A producer is allowed to finish only at its own coarse cancellation
  ;; boundary.  Deliberately let the initial producer ignore cancellation,
  ;; switch typography while it is running, and then release it after the new
  ;; frame has displayed.  Its obsolete completion must neither replace the
  ;; displayed bitmap nor enter the current cache namespace.
  (define typography-starts (make-async-channel))
  (define typography-releases (make-async-channel))
  (define typography-events (make-async-channel))
  (define (await-typography value)
    (or (sync/timeout 2 value)
        (error 'semantic-typography-test "timed out waiting for preview work")))
  (define (await-typography-frame)
    (let loop ()
      (define event (await-typography typography-events))
      (if (eq? (preview-event-kind event) 'frame-ready) event (loop))))
  (define stale-typography-session
    (open-preview-controller
     (scene-wait (scene-add (make-scene) heading) 1)
     #:typography animate-typography-theme #:prefetch 0 #:render-workers 2
     #:producer
     (lambda (_document _sample spec _token)
       (define id (typography-theme-id (preview-render-spec-typography spec)))
       (async-channel-put typography-starts id)
       (if (eq? id 'animate)
           (async-channel-get typography-releases)
           'enlarged-frame))
     #:byte-size (lambda (_value) 1)
     #:on-event (lambda (event) (async-channel-put typography-events event))))
  (dynamic-wind
   void
   (lambda ()
     (check-eq? (await-typography typography-starts) 'animate)
     (void (preview-set-typography-theme! stale-typography-session enlarged-theme))
     (check-eq? (await-typography typography-starts) 'enlarged)
     (check-eq? (preview-event-bitmap (await-typography-frame)) 'enlarged-frame)
     (async-channel-put typography-releases 'obsolete-frame)
     ;; The old producer returns a successful value here, not a cancellation
     ;; exception.  Generation checks in the controller must still reject it.
     (sleep 1/20)
     (check-eq? (preview-current-bitmap stale-typography-session)
                'enlarged-frame))
   (lambda ()
     ;; Unblock the deliberately slow fake even if one of the checks failed.
     (async-channel-put typography-releases 'close)
     (preview-close! stale-typography-session)))

  ;; Inspection names the authored role and shows the theme-dependent resolved
  ;; value separately. It never changes the selected semantic Scene value.
  (define inspect-scene
    (scene-wait (scene-add (make-scene) heading) 1))
  (define inspected
    (scene-inspector-document
     inspect-scene 0
     #:subject (visual-inspector-subject heading '(heading))
     #:theme animate-dark-theme
     #:typography enlarged-theme))
  (define typography-section
    (for/first ([section (in-list (inspector-document-sections inspected))]
                #:when (eq? (inspector-section-id section) 'semantic-typography))
      section))
  (check-not-false typography-section)
  (define typography-rows (inspector-section-rows typography-section))
  (check-equal? (inspector-row-value (car typography-rows)) 'title)
  (define (typography-row label)
    (for/first ([row (in-list typography-rows)]
                #:when (string=? (inspector-row-label row) label))
      row))
  (check-equal?
   (inspector-row-value (typography-row "style value"))
   (text-style->datum (typography-ref enlarged-theme 'title)))
  (check-equal?
   (inspector-row-value (typography-row "resolved color"))
   (resolve-color theme-foreground animate-dark-theme))
  (check-true
   (hash? (inspector-row-value (typography-row "measured rendered box"))))
  (check-equal?
   (scene-visual-at inspect-scene 'heading 1)
   heading)

  ;; Temporary typewriter values retain a semantic source and exact endpoint.
  ;; The treated code box has the same outer dimensions before any glyph has
  ;; appeared as it does at the normal semantic endpoint.
  (define typed-code
    (code-text "abc" #:id 'typed-code #:scale 3/2))
  (define typed-scene
    (scene-play (make-scene) (typewrite typed-code #:unit 'grapheme) #:duration 3))
  (define typed-start (scene-visual-at typed-scene 'typed-code 0))
  (check-true (text-reveal-visual? typed-start))
  (check-equal? (text-reveal-visual-source typed-start) typed-code)
  (check-equal? (scene-visual-at typed-scene 'typed-code 3) typed-code)
  (check-= (pict-width (visual->pict typed-start camera))
            (pict-width (visual->pict typed-code camera))
            1e-9)
  (check-= (pict-height (visual->pict typed-start camera))
            (pict-height (visual->pict typed-code camera))
            1e-9)
  (check-not-false (scene-frame->bitmap typed-scene 1 #:fps 3))
  (check-not-false (scene-frame->bitmap typed-scene 8 #:fps 3))

  ;; Erasure follows the same semantic-source rule in reverse: its exact
  ;; initial sample is the authored role value, its interior is temporary, and
  ;; the exact endpoint removes the target rather than leaving a concrete text
  ;; proxy behind.
  (define erased-body
    (body-text "remove me" #:id 'erased-body))
  (define erased-scene
    (scene-play (scene-add (make-scene) erased-body)
                (erase-text 'erased-body) #:duration 1))
  (check-equal? (scene-visual-at erased-scene 'erased-body 0) erased-body)
  (check-true (text-reveal-visual?
               (scene-visual-at erased-scene 'erased-body 1/2)))
  (check-false (scene-state-has? (scene-sample erased-scene 1) 'erased-body))

  ;; The established frozen-layout effects accept semantic text while keeping
  ;; their helper geometry separate from the authored source.
  (define decorated-scene
    (scene-play
     (scene-add (make-scene) (body-text "marked" #:id 'marked))
     (underline-sweep 'marked)
     (strike-through 'marked)
     (highlight-sweep 'marked)
     #:duration 1))
  (check-not-false (scene-frame->bitmap decorated-scene 1 #:fps 2)))
