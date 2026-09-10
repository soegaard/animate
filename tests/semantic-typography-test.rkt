#lang racket/base

;; Semantic typography stays immutable until a render boundary.  These tests
;; characterize both the data contract and one headless Pict realization.

(require racket/async-channel
         racket/class
         racket/runtime-path
         rackunit
         (only-in pict blank filled-rectangle pict->bitmap pict-ascent pict-descent
                  pict-height pict-width)
         "../authoring.rkt"
         "../colors.rkt"
         "../main.rkt"
         "../preview.rkt"
         "../project.rkt"
         "../private/inspector-document.rkt"
         "../private/render-typography-context.rkt"
         "../private/semantic-text-visual.rkt"
         "../private/section-renderer.rkt"
         "../private/text-treatment-pict.rkt"
         "../private/text-reveal-visual.rkt")

(define-runtime-path semantic-section-key-fixture
  "fixtures/semantic-typography-section-key.rkt")

(module+ test
  (define camera
    (make-camera #:width 320 #:height 180 #:world-width 8 #:background "white"))
  (define (bitmap-bytes bitmap)
    (define bytes (make-bytes (* 4 (send bitmap get-width) (send bitmap get-height))))
    (send bitmap get-argb-pixels 0 0
          (send bitmap get-width) (send bitmap get-height) bytes)
    bytes)
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
  ;; `#:center` places a body paragraph's box. Its lines remain left-aligned,
  ;; so explanatory copy stays readable without unexpectedly starting at the
  ;; supplied center point.
  (define default-body-style
    (typography-ref animate-typography-theme 'body))
  (check-eq? (text-style-horizontal-alignment default-body-style) 'center)
  (check-eq? (text-style-line-alignment default-body-style) 'left)
  (define default-body-visual
    (semantic-text->text-visual
     (body-text "A centered text box with left-aligned lines."
                #:id 'default-body-alignment #:center origin #:width 6)))
  (check-eq? (text-visual-horizontal-alignment default-body-visual) 'center)
  (check-eq? (text-visual-line-alignment default-body-visual) 'left)
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
  ;; Appearance identity is independent of ambient printer preferences. Build
  ;; a fresh equivalent theme under each setting, so this tests the canonical
  ;; writer rather than merely querying a stored fingerprint.
  (define (fresh-printer-theme)
    (typography-theme
     #:id 'printer-probe
     #:extends animate-typography-theme
     #:styles
     (hash 'title
           (text-style-update
            (typography-ref animate-typography-theme 'title)
            #:font-size 7/5))))
  (define default-fingerprint
    (typography-theme-fingerprint (fresh-printer-theme)))
  (for ([settings (in-list (list (list #t #t #t #t)
                                 (list #f #t #f #t)
                                 (list #t #f #t #f)))])
    (parameterize ([print-pair-curly-braces (list-ref settings 0)]
                   [print-graph (list-ref settings 1)]
                   [print-reader-abbreviations (list-ref settings 2)]
                   [print-boolean-long-form (list-ref settings 3)])
      (check-equal? (typography-theme-fingerprint (fresh-printer-theme))
                    default-fingerprint)))
  ;; Typography values are immutable appearance snapshots all the way down to
  ;; caller-supplied literal strings inside colors, treatment borders, and
  ;; paint stops. Mutating those original strings cannot invalidate a retained
  ;; fingerprint or silently change an existing rendered Scene.
  (define mutable-text-color (string-copy "#ff0000"))
  (define mutable-border-color (string-copy "#0000ff"))
  (define mutable-stop-color (string-copy "#00ff00"))
  (define mutable-theme
    (typography-theme
     #:id 'mutable-input-probe
     #:extends animate-typography-theme
     #:styles
     (hash 'title
           (text-style-update
            (typography-ref animate-typography-theme 'title)
            #:color mutable-text-color
            #:treatment
            (text-treatment
             #:background
             (linear-gradient (vec2 -1 1) (vec2 1 -1)
                              (list (paint-stop 0 mutable-stop-color)
                                    (paint-stop 1 "#000000")))
             #:border-color mutable-border-color
             #:border-width 1)))))
  (define mutable-probe (title-text "Snapshot" #:id 'mutable-probe))
  (define mutable-fingerprint (typography-theme-fingerprint mutable-theme))
  (define mutable-datum (typography-theme->datum mutable-theme))
  (define mutable-bitmap
    (bitmap-bytes
     (pict->bitmap (visual->pict mutable-probe camera #:typography mutable-theme))))
  (for ([mutation (in-list (list (cons mutable-text-color "#00ff00")
                                  (cons mutable-border-color "#ff0000")
                                  (cons mutable-stop-color "#0000ff")))])
    (for ([index (in-range (string-length (car mutation)))])
      (string-set! (car mutation) index (string-ref (cdr mutation) index))))
  (check-equal? (typography-theme-fingerprint mutable-theme) mutable-fingerprint)
  (check-equal? (typography-theme->datum mutable-theme) mutable-datum)
  (check-equal?
   (bitmap-bytes
    (pict->bitmap (visual->pict mutable-probe camera #:typography mutable-theme)))
   mutable-bitmap)
  (define mutable-face (string-copy "Helvetica"))
  (define mutable-override-color (string-copy "#ff0000"))
  (define semantic-mutable-probe
    (body-text "Snapshot" #:id 'semantic-mutable-probe
               #:font-face mutable-face #:color mutable-override-color
               #:background (checker-pattern mutable-override-color "#0000ff")))
  (define semantic-before
    (semantic-text->text-visual semantic-mutable-probe))
  (string-set! mutable-face 0 #\X)
  (for ([index (in-range (string-length mutable-override-color))])
    (string-set! mutable-override-color index (string-ref "#00ff00" index)))
  (define semantic-after
    (semantic-text->text-visual semantic-mutable-probe))
  (check-equal? (text-visual-font-face semantic-after) "Helvetica")
  (check-equal? (text-visual-color semantic-after)
                (color-spec->rgba-color "#ff0000"))
  (check-equal? semantic-after semantic-before)
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
  ;; A huge authored gradient is rejected before theme fingerprinting or
  ;; transport expands every stop into a portable color datum.
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"typography-theme" (exn-message error))))
   (lambda ()
     (typography-theme
      #:id 'oversized-gradient-serialization
      #:extends animate-typography-theme
      #:styles
      (hash
       'body
       (text-style-update
        (typography-ref animate-typography-theme 'body)
        #:treatment
        (text-treatment
         #:background
         (linear-gradient
          (vec2 0 0) (vec2 1 1)
          (build-list 5000
                      (lambda (index)
                        (paint-stop (/ index 4999) "black"))))))))))

  ;; Source-structure preflight validates atom sizes as well as tree nodes.
  ;; A huge font face is rejected while fingerprinting, before canonical bytes
  ;; are allocated; metadata that is absent from the fingerprint is checked
  ;; before the portable theme datum is constructed.
  (define oversized-atom (make-string 65537 #\x))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"typography-theme" (exn-message error))))
   (lambda ()
     (typography-theme
      #:id 'oversized-font-face
      #:extends animate-typography-theme
      #:styles
      (hash 'body
            (text-style-update
             (typography-ref animate-typography-theme 'body)
             #:font-face oversized-atom)))))
  (define oversized-display-theme
    (typography-theme #:id 'oversized-display
                      #:display-name oversized-atom
                      #:extends animate-typography-theme))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"typography-theme->datum" (exn-message error))))
   (lambda () (typography-theme->datum oversized-display-theme)))

  ;; The budget permits one atom just below the per-atom limit, but counts
  ;; every occurrence before fingerprinting. Reusing an individually valid
  ;; face across many styles therefore cannot allocate an unbounded canonical
  ;; appearance datum.
  (define near-limit-font-face (make-string 65535 #\x))
  (check-not-exn
   (lambda ()
     (typography-theme
      #:id 'near-atom-limit
      #:extends animate-typography-theme
      #:styles
      (hash 'body
            (text-style-update
             (typography-ref animate-typography-theme 'body)
             #:font-face near-limit-font-face)))))
  (define repeated-medium-font-face (make-string 60000 #\y))
  (check-exn
   (lambda (error)
     (and (exn:fail? error)
          (regexp-match? #rx"cumulative byte budget" (exn-message error))))
   (lambda ()
     (typography-theme
      #:id 'aggregate-atom-limit
      #:extends animate-typography-theme
      #:styles
      (for/hash ([index (in-range 18)])
        (values
         (string->symbol (format "aggregate-style-~a" index))
         (text-style-update
          (typography-ref animate-typography-theme 'body)
          #:font-face repeated-medium-font-face))))))

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
  ;; Raster rows are device-rounded and can be anti-aliased. Establish the
  ;; center treatment geometry from logical Pict dimensions and use painted
  ;; pixels only as a tolerant smoke test.
  (define center-plain-pict
    (visual->pict
     (body-text "T" #:id 'center-plain
                #:horizontal-alignment 'center #:vertical-alignment 'center)
     camera))
  (check-= (pict-width center-pict) (pict-width center-plain-pict) 1e-9)
  (check-= (pict-height center-pict) (pict-height center-plain-pict) 1e-9)
  (check-true (and (positive? center-red-width)
                   (positive? center-red-height)
                   (<= center-red-width (ceiling (pict-width center-pict)))
                   (<= center-red-height (ceiling (pict-height center-pict)))))
  (check-true (< baseline-red-width (pict-width baseline-pict)))
  (check-true (< baseline-red-height (pict-height baseline-pict)))
  (check-true (< right-bottom-red-width (pict-width right-bottom-pict)))
  (check-true (< right-bottom-red-height (pict-height right-bottom-pict)))
  (check-= center-baseline-red-width (pict-width center-baseline-pict) 1e-9)
  (check-true (< center-baseline-red-height
                 (pict-height center-baseline-pict)))

  ;; A decoration must retain padded text metrics.  The semantic baseline
  ;; anchor therefore still follows the actual glyph baseline, rather than the
  ;; default bottom baseline of a `dc` decoration.
  (define baseline-content
    (visual->pict
     (body-text "Ag" #:id 'baseline-content
                #:horizontal-alignment 'center #:vertical-alignment 'baseline)
     camera))
  (define baseline-treated
    (visual->pict
     (body-text "Ag" #:id 'baseline-treated
                #:horizontal-alignment 'center #:vertical-alignment 'baseline
                #:treatment (text-treatment #:background "ivory"
                                             #:border-color "black" #:border-width 1
                                             #:padding-x 1/4 #:padding-y 1/4))
     camera))
  (check-= (/ (pict-ascent baseline-treated) (pict-height baseline-treated))
            (/ (pict-ascent baseline-content) (pict-height baseline-content))
            1e-9)
  ;; Check the production invariant directly, before `anchor-pict` adds its
  ;; symmetric placement box: decoration must retain the padded content's
  ;; actual baseline metrics. A descender-bearing probe makes a synthetic
  ;; bottom baseline immediately visible to this test.
  (define baseline-metrics-content (blank 60 20 13 7))
  (define baseline-metrics-treatment
    (text-treatment #:background "ivory" #:border-color "black" #:border-width 1
                    #:padding-x 1/4 #:padding-y 1/4))
  (define baseline-metrics-padded
    (text-treatment-content-pict baseline-metrics-content
                                 baseline-metrics-treatment 1 camera))
  (define baseline-metrics-decoration
    (text-treatment-decoration-pict baseline-metrics-content
                                    baseline-metrics-treatment 1 camera))
  (check-= (pict-ascent baseline-metrics-decoration)
            (pict-ascent baseline-metrics-padded) 1e-9)
  (check-= (pict-descent baseline-metrics-decoration)
            (pict-descent baseline-metrics-padded) 1e-9)

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
  ;; Treatment paints use the text anchor as a normal y-up local origin. An
  ;; asymmetric vertical gradient must therefore be red above the anchor and
  ;; blue below it, rather than following Pict's y-down box coordinates.
  (define gradient-treatment-pict
    (visual->pict
     (body-text "" #:id 'gradient-treatment
                #:horizontal-alignment 'center #:vertical-alignment 'center
                #:treatment
                (text-treatment
                 #:background
                 (linear-gradient (vec2 0 1) (vec2 0 -1)
                                  (list (paint-stop 0 "red")
                                        (paint-stop 1 "blue")))
                 #:padding-x 1 #:padding-y 1))
     camera))
  (define gradient-bitmap (pict->bitmap gradient-treatment-pict))
  (define gradient-width (send gradient-bitmap get-width))
  (define gradient-height (send gradient-bitmap get-height))
  (define gradient-pixels (bitmap-bytes gradient-bitmap))
  (define (gradient-rgb y)
    (define offset (* 4 (+ (quotient gradient-width 2)
                           (* y gradient-width))))
    (values (bytes-ref gradient-pixels (add1 offset))
            (bytes-ref gradient-pixels (+ offset 2))
            (bytes-ref gradient-pixels (+ offset 3))))
  (define-values (top-red _top-green top-blue) (gradient-rgb 2))
  (define-values (bottom-red _bottom-green bottom-blue)
    (gradient-rgb (- gradient-height 3)))
  (check-true (> top-red top-blue))
  (check-true (> bottom-blue bottom-red))
  ;; A treatment border is cosmetic: the surrounding box grows under semantic
  ;; scale, but the sampled device-row pen thickness remains unchanged.
  (define (red-border-thickness scale)
    (define border-pict
      (visual->pict
       (body-text "" #:id (if (= scale 1) 'border-scale-1 'border-scale-2)
                  #:scale scale
                  #:treatment (text-treatment #:border-color "red"
                                               #:border-width 3
                                               #:padding-x 1 #:padding-y 1))
       camera))
    (define border-bitmap (pict->bitmap border-pict))
    (define width (send border-bitmap get-width))
    (define pixels (bitmap-bytes border-bitmap))
    (define (red-row? y)
      (define offset (* 4 (+ (quotient width 2) (* y width))))
      (and (> (bytes-ref pixels (add1 offset)) 150)
           (< (bytes-ref pixels (+ offset 2)) 100)
           (< (bytes-ref pixels (+ offset 3)) 100)))
    (let loop ([row 0])
      (if (red-row? row) (add1 (loop (add1 row))) 0)))
  (check-= (red-border-thickness 1) (red-border-thickness 2) 1)
  ;; A custom semantic Pict renderer declares one asymmetric 47-by-19 logical
  ;; box. Treatment uses its centre as the paint anchor, never reuses the
  ;; lowered text's left/baseline settings, and still adds its one-pixel-style
  ;; outline after scale. Blank content leaves the background directly visible.
  (define custom-transparent-text-pict (blank 47 19))
  (struct custom-transparent-text-renderer ()
    #:transparent
    #:methods gen:pict-renderer
    [(define (pict-renderer-supports? _renderer visual) (text-visual? visual))
     (define (pict-renderer-render _renderer _visual _camera)
       custom-transparent-text-pict)])
  (define custom-treatment
    (text-treatment
     #:background
     (linear-gradient (vec2 0 1) (vec2 0 -1)
                      (list (paint-stop 0 "red") (paint-stop 1 "blue")))
     #:border-color "red" #:border-width 3 #:padding-x 1 #:padding-y 1))
  (define (custom-treated-pict scale #:rotation [rotation 0])
    (visual->pict
     (body-text "custom" #:id (gensym 'custom-treated)
                #:horizontal-alignment 'left #:vertical-alignment 'baseline
                #:scale scale #:rotation rotation #:treatment custom-treatment)
     camera
     #:renderers
     (cons (custom-transparent-text-renderer) default-pict-renderers)))
  (define custom-gradient-bitmap (pict->bitmap (custom-treated-pict 1)))
  (define custom-gradient-width (send custom-gradient-bitmap get-width))
  (define custom-gradient-height (send custom-gradient-bitmap get-height))
  (define custom-gradient-pixels (bitmap-bytes custom-gradient-bitmap))
  (define (custom-gradient-rgb y)
    (define offset (* 4 (+ (quotient custom-gradient-width 2)
                           (* y custom-gradient-width))))
    (values (bytes-ref custom-gradient-pixels (add1 offset))
            (bytes-ref custom-gradient-pixels (+ offset 2))
            (bytes-ref custom-gradient-pixels (+ offset 3))))
  (define-values (custom-top-red _custom-top-green custom-top-blue)
    (custom-gradient-rgb 4))
  (define-values (custom-bottom-red _custom-bottom-green custom-bottom-blue)
    (custom-gradient-rgb (- custom-gradient-height 5)))
  (check-true (> custom-top-red custom-top-blue))
  (check-true (> custom-bottom-blue custom-bottom-red))
  (define custom-border-treatment
    (text-treatment #:background "white" #:border-color "red" #:border-width 3
                    #:padding-x 1 #:padding-y 1))
  (define (custom-border-pict scale)
    (visual->pict
     (body-text "custom" #:id (gensym 'custom-border)
                #:horizontal-alignment 'left #:vertical-alignment 'baseline
                #:scale scale #:treatment custom-border-treatment)
     camera
     #:renderers
     (cons (custom-transparent-text-renderer) default-pict-renderers)))
  (define (custom-red-border-thickness scale)
    (define bitmap (pict->bitmap (custom-border-pict scale)))
    (define width (send bitmap get-width))
    (define pixels (bitmap-bytes bitmap))
    (define (red-row? y)
      (define offset (* 4 (+ (quotient width 2) (* y width))))
      (and (> (bytes-ref pixels (add1 offset)) 150)
           (< (bytes-ref pixels (+ offset 2)) 100)
           (< (bytes-ref pixels (+ offset 3)) 100)))
    (let loop ([row 0])
      (if (red-row? row) (add1 (loop (add1 row))) 0)))
  (check-= (custom-red-border-thickness 1)
            (custom-red-border-thickness 2) 1)
  (check-not-exn
   (lambda ()
     (custom-treated-pict (vec2 1/2 2) #:rotation 1/10)))
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
  (check-equal? (text-treatment-border-color border-color-value)
                (color-spec->rgba-color "blue"))
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
  ;; The project plan records the semantic renderer revision separately from
  ;; the unchanged theme fingerprint, so resolver-2 cached frames cannot be
  ;; accepted after the treatment rendering change.
  (check-equal? (hash-ref recorded-typography 'resolver-version) 3)
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
  ;; process-local gensym. Instantiate the equivalent fixture in two fresh
  ;; namespaces: two calls inside one module would not reproduce the old
  ;; module-instantiation bug.
  (define (fresh-semantic-section-key)
    (parameterize ([current-namespace (make-base-namespace)])
      ((dynamic-require semantic-section-key-fixture 'semantic-section-key))))
  (check-equal? (fresh-semantic-section-key)
                (fresh-semantic-section-key))
  (define preview-document
    (make-preview-document (scene-wait (scene-add (make-scene) heading) 1)))
  (define preview-sample (frame-sample 0 1))
  (define preview-render-identity
    (preview-render-spec-id
     (make-preview-render-spec #:fps 1 #:typography enlarged-theme)))
  ;; This position is the typography resolver slot in the documented private
  ;; appearance grammar. It intentionally differs from the old resolver-2
  ;; namespace while its adjacent theme fingerprint remains unchanged.
  (check-equal? (list-ref preview-render-identity 9) 3)
  (check-not-equal?
   (make-preview-frame-key preview-document 0 preview-sample
                           (make-preview-render-spec #:fps 1
                                                     #:typography animate-typography-theme))
   (make-preview-frame-key preview-document 0 preview-sample
                           (make-preview-render-spec #:fps 1
                                                     #:typography enlarged-theme)))
  (check-equal?
   (make-preview-frame-key preview-document 0 preview-sample
                           (make-preview-render-spec #:fps 1
                                                     #:typography enlarged-theme))
   (make-preview-frame-key preview-document 0 preview-sample
                           (make-preview-render-spec #:fps 1
                                                     #:typography enlarged-metadata-theme)))
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

  ;; An equal-appearance switch while the initial frame is in flight keeps the
  ;; same frame key. It must neither start a replacement producer nor discard
  ;; the completed frame merely because its selected typography metadata
  ;; changed.
  (define equal-starts (make-async-channel))
  (define equal-releases (make-async-channel))
  (define equal-events (make-async-channel))
  (define equal-appearance-session
    (open-preview-controller
     (scene-wait (scene-add (make-scene) heading) 1)
     #:typography enlarged-theme #:prefetch 0 #:render-workers 1
     #:producer
     (lambda (_document _sample spec _token)
       (async-channel-put equal-starts
                          (typography-theme-id (preview-render-spec-typography spec)))
       (async-channel-get equal-releases)
       'equal-appearance-frame)
     #:byte-size (lambda (_value) 1)
     #:on-event (lambda (event) (async-channel-put equal-events event))))
  (dynamic-wind
   void
   (lambda ()
     (check-eq? (or (sync/timeout 2 equal-starts)
                    (error 'semantic-typography-test "timed out waiting for preview work"))
                'enlarged)
     (void (preview-set-typography-theme! equal-appearance-session
                                           enlarged-metadata-theme))
     (check-false (sync/timeout 1/10 equal-starts))
     (async-channel-put equal-releases 'render)
     (define equal-frame-event
       (let wait ()
         (define event
           (or (sync/timeout 2 equal-events)
               (error 'semantic-typography-test "timed out waiting for equal-appearance frame")))
         (if (eq? (preview-event-kind event) 'frame-ready) event (wait))))
     (check-eq? (preview-event-bitmap equal-frame-event) 'equal-appearance-frame)
     (check-eq? (preview-current-bitmap equal-appearance-session)
                'equal-appearance-frame))
   (lambda ()
     (async-channel-put equal-releases 'close)
     (preview-close! equal-appearance-session)))

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
  ;; The semantic reveal path prepares an unanchored content Pict. Its
  ;; left-aligned code role used to clamp every intermediate cluster to zero
  ;; width; each interior sample must now add real glyph ink while preserving
  ;; the complete treatment box.
  (for ([alignment (in-list '(left center right))])
    (define id (string->symbol (format "typed-~a" alignment)))
    (define aligned-code
      (code-text "abc" #:id id #:horizontal-alignment alignment))
    (define aligned-scene
      (scene-play (make-scene) (typewrite aligned-code #:unit 'grapheme)
                  #:duration 3))
    (define start-pict
      (visual->pict (scene-visual-at aligned-scene id 0) camera))
    (define first-pict
      (visual->pict (scene-visual-at aligned-scene id 1) camera))
    (define second-pict
      (visual->pict (scene-visual-at aligned-scene id 2) camera))
    (define final-pict
      (visual->pict (scene-visual-at aligned-scene id 3) camera))
    (check-= (pict-width start-pict) (pict-width final-pict) 1e-9)
    (check-= (pict-height start-pict) (pict-height final-pict) 1e-9)
    (check-not-equal? (bitmap-bytes (pict->bitmap start-pict))
                      (bitmap-bytes (pict->bitmap first-pict)))
    (check-not-equal? (bitmap-bytes (pict->bitmap first-pict))
                      (bitmap-bytes (pict->bitmap second-pict)))
    (check-equal? (bitmap-bytes (pict->bitmap final-pict))
                  (bitmap-bytes (pict->bitmap (visual->pict aligned-code camera)))))
  (define cursor-code (code-text "abc" #:id 'typed-code-cursor))
  (define cursor-scene
    (scene-play (make-scene) (typewrite cursor-code #:unit 'grapheme
                                          #:cursor? #t #:cursor-style "tomato")
                #:duration 3))
  (define cursor-first
    (visual->pict (scene-visual-at cursor-scene 'typed-code-cursor 1) camera))
  (define cursor-second
    (visual->pict (scene-visual-at cursor-scene 'typed-code-cursor 2) camera))
  (check-= (pict-width cursor-first) (pict-width cursor-second) 1e-9)
  (check-= (pict-height cursor-first) (pict-height cursor-second) 1e-9)
  (check-not-equal? (bitmap-bytes (pict->bitmap cursor-first))
                    (bitmap-bytes (pict->bitmap cursor-second)))

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
