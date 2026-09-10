#lang racket/base

;; Semantic typography stays immutable until a render boundary.  These tests
;; characterize both the data contract and one headless Pict realization.

(require racket/async-channel
         racket/class
         rackunit
         (only-in pict filled-rectangle pict->bitmap pict-height pict-width)
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
  ;; Appearance identity is independent of ambient printer preferences.
  (define default-fingerprint
    (typography-theme-fingerprint animate-typography-theme))
  (for ([settings (in-list (list (list #t #t #t #t)
                                 (list #f #t #f #t)
                                 (list #t #f #t #f)))])
    (parameterize ([print-pair-curly-braces (list-ref settings 0)]
                   [print-graph (list-ref settings 1)]
                   [print-reader-abbreviations (list-ref settings 2)]
                   [print-boolean-long-form (list-ref settings 3)])
      (check-equal? (typography-theme-fingerprint animate-typography-theme)
                    default-fingerprint)))
  ;; Typography transport rejects malformed wrappers before traversing style
  ;; data, rejects duplicate keys, and keeps nested treatment errors in the
  ;; typography decoder rather than exposing incidental list/number failures.
  (check-exn exn:fail?
             (lambda ()
               (datum->typography-theme
                '(animate-typography-theme schema theme "Theme" () #f))))
  (check-exn exn:fail?
             (lambda ()
               (datum->typography-theme
                '(animate-typography-theme 1 theme "Theme" not-a-list #f))))
  (define body-style-datum
    (text-style->datum (typography-ref animate-typography-theme 'body)))
  (check-exn exn:fail?
             (lambda ()
               (datum->typography-theme
                `(animate-typography-theme 1 duplicate "Duplicate"
                                           ((body ,body-style-datum)
                                            (body ,body-style-datum))
                                           #f))))
  (check-exn exn:fail?
             (lambda ()
               (datum->typography-theme
                `(animate-typography-theme 1 overflow "Overflow"
                                           ,(build-list 10001 (lambda (_) '(body bad)))
                                           #f))))
  ;; The complete theme budget also bounds nested treatment paint data, not
  ;; just the outer number of style definitions.
  (define excessive-stop-style-datum
    `(text-style #f swiss 1 normal normal
                 (animate-color-spec 1 (rgba 0 0 0 1))
                 1 left left top
                 (text-treatment
                  (linear-gradient (0 0) (1 1)
                                   ,(build-list
                                     10001
                                     (lambda (_)
                                       '(0 (animate-color-spec 1 (rgba 0 0 0 1))))))
                  #f 0 0 0)))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"datum->typography-theme" (exn-message error))))
   (lambda ()
     (datum->typography-theme
      `(animate-typography-theme 1 nested-overflow "Nested overflow"
                                 ,(for/list ([key (in-list typography-standard-style-keys)])
                                    (list key (if (eq? key 'body)
                                                  excessive-stop-style-datum
                                                  body-style-datum)))
                                 #f))))
  (check-exn exn:fail?
             (lambda ()
               (datum->text-style
                `(text-style #f swiss 1 normal normal
                             ,(color-spec->datum "black")
                             1 left left top
                             (text-treatment #f #f bad-width 0 0)))))

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
  ;; A custom renderer declares its own logical Pict as the treatment box.
  ;; The adapter never tries to infer a tighter visible-ink rectangle.
  (define custom-treated-code-pict
    (visual->pict
     (code-text "x" #:id 'custom-treated-code)
     camera #:renderers (cons (custom-text-renderer) default-pict-renderers)))
  (check-true (> (pict-width custom-treated-code-pict)
                 (pict-width custom-text-pict)))
  (check-true (> (pict-height custom-treated-code-pict)
                 (pict-height custom-text-pict)))

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

  ;; Treatment decorates actual content before anchoring. At left/top and
  ;; baseline anchors its painted box is narrower than the transparent
  ;; anchor-balancing Pict; center/center remains a no-spare-space control.
  (define (red-box-dimensions pict)
    (define bitmap (pict->bitmap pict))
    (define width (send bitmap get-width))
    (define height (send bitmap get-height))
    (define pixels (make-bytes (* 4 width height)))
    (send bitmap get-argb-pixels 0 0 width height pixels)
    (define points
      (for*/list ([y (in-range height)] [x (in-range width)]
                  #:when (let ([offset (* 4 (+ x (* y width)))])
                           (and (> (bytes-ref pixels (add1 offset)) 200)
                                (< (bytes-ref pixels (+ offset 2)) 80)
                                (< (bytes-ref pixels (+ offset 3)) 80))))
        (cons x y)))
    (if (null? points)
        (values 0 0)
        (values (add1 (- (apply max (map car points))
                         (apply min (map car points))))
                (add1 (- (apply max (map cdr points))
                         (apply min (map cdr points)))))))
  (define (treated-probe id horizontal vertical)
    (body-text "T" #:id id
               #:horizontal-alignment horizontal #:vertical-alignment vertical
               #:treatment (text-treatment #:background "red")))
  (define left-top-pict
    (visual->pict (treated-probe 'left-top 'left 'top) camera))
  (define center-pict
    (visual->pict (treated-probe 'center 'center 'center) camera))
  (define baseline-pict
    (visual->pict (treated-probe 'baseline 'left 'baseline) camera))
  (define right-bottom-pict
    (visual->pict (treated-probe 'right-bottom 'right 'bottom) camera))
  (define center-baseline-pict
    (visual->pict (treated-probe 'center-baseline 'center 'baseline) camera))
  (define-values (left-top-red-width left-top-red-height)
    (red-box-dimensions left-top-pict))
  (define-values (center-red-width center-red-height)
    (red-box-dimensions center-pict))
  (define-values (baseline-red-width baseline-red-height)
    (red-box-dimensions baseline-pict))
  (define-values (right-bottom-red-width right-bottom-red-height)
    (red-box-dimensions right-bottom-pict))
  (define-values (center-baseline-red-width center-baseline-red-height)
    (red-box-dimensions center-baseline-pict))
  (check-true (< left-top-red-width (pict-width left-top-pict)))
  (check-true (< left-top-red-height (pict-height left-top-pict)))
  (check-= center-red-width (pict-width center-pict) 1e-9)
  (check-= center-red-height (pict-height center-pict) 1e-9)
  (check-true (< baseline-red-width (pict-width baseline-pict)))
  (check-true (< baseline-red-height (pict-height baseline-pict)))
  (check-true (< right-bottom-red-width (pict-width right-bottom-pict)))
  (check-true (< right-bottom-red-height (pict-height right-bottom-pict)))
  (check-= center-baseline-red-width (pict-width center-baseline-pict) 1e-9)
  (check-true (< center-baseline-red-height
                 (pict-height center-baseline-pict)))

  ;; A zero-width border is no border even when a color is supplied.
  (define zero-border
    (body-text "border" #:id 'zero-border
               #:treatment (text-treatment #:background "white"
                                            #:border-color "red" #:border-width 0)))
  (define no-border
    (body-text "border" #:id 'no-border
               #:treatment (text-treatment #:background "white")))
  (check-equal? (bitmap-bytes (pict->bitmap (visual->pict zero-border camera)))
                (bitmap-bytes (pict->bitmap (visual->pict no-border camera))))
  (define positive-border
    (body-text "border" #:id 'positive-border
               #:treatment (text-treatment #:background "white"
                                            #:border-color "red" #:border-width 2)))
  (check-not-equal?
   (bitmap-bytes (pict->bitmap (visual->pict positive-border camera)))
   (bitmap-bytes (pict->bitmap (visual->pict no-border camera))))
  ;; The same content-first treatment path accepts wrapped, rich, and empty
  ;; semantic text without adding a second layout engine or an empty-text
  ;; special case to callers.
  (define wrapped-treated
    (body-text "A wrapped treatment uses the one final text layout."
               #:id 'wrapped-treated #:width 2
               #:treatment (text-treatment #:background "red" #:padding-x 1/3)))
  (define rich-treated
    (styled-rich-text #:style 'body #:id 'rich-treated
                      #:treatment (text-treatment #:background "red")
                      (text-span "rich" #:font-style 'italic) " text"))
  (define empty-treated
    (body-text "" #:id 'empty-treated
               #:treatment (text-treatment #:background "red")))
  (for ([value (in-list (list wrapped-treated rich-treated empty-treated))])
    (define rendered (visual->pict value camera))
    (check-true (positive? (pict-width rendered)))
    (check-true (positive? (pict-height rendered))))

  ;; Individual treatment fields refine inherited code treatment without
  ;; forcing an author to reconstruct the other fields.
  (define inherited-code-treatment
    (text-style-treatment (typography-ref animate-typography-theme 'code)))
  (define partial-treatment
    (resolve-semantic-text-style
     (code-text "x" #:id 'partial-treatment #:background #f #:padding-x 7/10)
     animate-typography-theme))
  (define partial-value (text-style-treatment partial-treatment))
  (check-false (text-treatment-background partial-value))
  (check-equal? (text-treatment-border-color partial-value)
                (text-treatment-border-color inherited-code-treatment))
  (check-equal? (text-treatment-border-width partial-value)
                (text-treatment-border-width inherited-code-treatment))
  (check-equal? (text-treatment-padding-x partial-value) 7/10)
  (check-equal? (text-treatment-padding-y partial-value)
                (text-treatment-padding-y inherited-code-treatment))
  (define border-color-value
    (text-style-treatment
     (resolve-semantic-text-style
      (code-text "x" #:id 'border-color-override #:border-color "blue")
      animate-typography-theme)))
  (define border-width-value
    (text-style-treatment
     (resolve-semantic-text-style
      (code-text "x" #:id 'border-width-override #:border-width 3)
      animate-typography-theme)))
  (define padding-y-value
    (text-style-treatment
     (resolve-semantic-text-style
      (code-text "x" #:id 'padding-y-override #:padding-y 2/5)
      animate-typography-theme)))
  (check-equal? (text-treatment-border-color border-color-value) "blue")
  (check-equal? (text-treatment-padding-x border-color-value)
                (text-treatment-padding-x inherited-code-treatment))
  (check-equal? (text-treatment-border-width border-width-value) 3)
  (check-equal? (text-treatment-background border-width-value)
                (text-treatment-background inherited-code-treatment))
  (check-equal? (text-treatment-padding-y padding-y-value) 2/5)
  (check-equal? (text-treatment-border-color padding-y-value)
                (text-treatment-border-color inherited-code-treatment))
  (check-false
   (text-treatment-background
    (text-treatment-update inherited-code-treatment #:background #f)))

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
  ;; Inherited semantic fields have a stable prefab marker instead of a
  ;; process-local gensym, so rebuilt equivalent timelines keep their automatic
  ;; persistent-cache identity.
  (define (rebuilt-semantic-section-key)
    (define rebuilt-heading (title-text "A semantic title" #:id 'heading))
    (define rebuilt-timeline
      (make-authored-timeline
       (scene-wait (scene-add (make-scene) rebuilt-heading) 1)
       #:sections (list (section 'only 0 1))))
    (automatic-section-cache-key
     rebuilt-timeline (timeline-section rebuilt-timeline 'only)
     #:fps 1 #:camera #f #:renderers '() #:asset-files '()))
  (check-equal? (rebuilt-semantic-section-key)
                (rebuilt-semantic-section-key))
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
                    (preview-status-render-generation before)))
     ;; Metadata-only switches update inspection metadata without discarding an
     ;; equal-appearance bitmap or advancing the render generation.
     (define metadata-after
       (preview-set-typography-theme! preview-session enlarged-metadata-theme))
     (check-eq? (preview-typography-theme preview-session) enlarged-metadata-theme)
     (check-equal? (preview-status-render-generation metadata-after)
                   (preview-status-render-generation after)))
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
