#lang racket/base

;;;
;;; Native Mathematical Gallery Assembly
;;;
;; Prepares each view independently and appends ordinary mathematical clips to one
;; native Animate scene. Inspectors are compiled once, never updated from prior frames.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/list append-map take remove-duplicates index-of)
         (only-in racket/match match-define)
         (only-in racket/math nan? infinite?)
         (only-in racket/string string-join)
         "../../main.rkt" "../../private/native.rkt"
         "../../private/prepare.rkt" "../../private/typeset-model.rkt"
         "../../private/prepared-plan-codec.rkt"
         "../../private/prepared-plan-model.rkt"
         "../../private/presentation.rkt"
         "../../private/transition-plan.rkt"
         "../../../private/layout-box.rkt"
         (only-in "../../private/animate-adapter.rkt"
                  append-prepared-math-plan! presentation-header-lines)
         "model.rkt")
(provide prepare-gallery-views! prepare-gallery-view! build-gallery-scene!
         make-gallery-camera! gallery-view-key
         gallery-preparation-payload-schema
         prepared-gallery-view->portable-payload portable-payload->prepared-gallery-view
         (struct-out prepared-gallery-view) (struct-out gallery-layout) (struct-out gallery-text))

; gallery-preparation-payload-schema : symbol?
;;   Names the versioned parent-owned gallery view wrapper carried to fresh workers.
(define gallery-preparation-payload-schema 'animate-math-gallery-view-v2)

;;;
;;; Prepared Gallery View Data
;;;

(struct gallery-text (segment suffix text x y size) #:transparent)
;; gallery-text is one frozen native text placement.
;;  - segment  (or/c exact-nonnegative-integer? #f)  owning mathematical segment, or false.
;;  - suffix  symbol?  stable role within the gallery view.
;;  - text  immutable-string?  parent-prepared display content.
;;  - x  finite-real?  native world-coordinate horizontal placement.
;;  - y  finite-real?  native world-coordinate vertical placement.
;;  - size  positive-real?  measured font request; workers must not refit it.

(struct gallery-layout
  (body row-origin caption api annotation-y annotation-caption-y
        inspector-left inspector-width inspector-top inspector-row-gap inspector-font-size
        verdict-x verdict-y overlay-y recipe-y headings diagnostics)
  #:transparent)
;; gallery-layout is immutable parent-measured presentation geometry.
;;  - body  (list/c left bottom right top)  reserved working rectangle in y-up world coordinates.
;;  - row-origin  finite-real?  first working-row baseline derived from all token extents.
;;  - caption  (or/c gallery-text? #f)  frozen lower-band caption.
;;  - api  (or/c gallery-text? #f)  frozen optional API label.
;;  - annotation-y  finite-real?  explanatory-inset formula allocation.
;;  - annotation-caption-y  finite-real?  explanatory-inset caption allocation.
;;  - inspector-left  finite-real?  fixed tree marker-column anchor.
;;  - inspector-width  finite-real?  reserved inspector-column width.
;;  - inspector-top  finite-real?  first tree-row vertical anchor.
;;  - inspector-row-gap  positive-real?  frozen tree-row separation.
;;  - inspector-font-size  positive-real?  uniform measured tree-label request.
;;  - verdict-x  finite-real?  nearby candidate-evidence horizontal placement.
;;  - verdict-y  finite-real?  nearby candidate-evidence vertical placement.
;;  - overlay-y  (or/c finite-real? #f)  gallery-only copy-witness allocation.
;;  - recipe-y  (or/c finite-real? #f)  gallery-only recipe-label allocation.
;;  - headings  (listof gallery-text?)  all segment header lines measured by the parent.
;;  - diagnostics  (listof immutable-string?)  deterministic fit observations.

(struct prepared-gallery-view (math layout show-api?) #:transparent)
;; prepared-gallery-view pairs one existing prepared mathematical plan with immutable
;; gallery-only placement decisions. Workers consume this record without typesetting or refitting.
;;  - math  prepared-math-plan?  frozen formula layouts, schedule, and token assets.
;;  - layout  gallery-layout?  frozen header/body/inspector/annotation geometry.
;;  - show-api?  boolean?  visual option included in preparation identity.

; gallery-view-key : gallery-entry? -> (listof symbol?)
;;   Identifies a replay independently of the selected subset and worker assignment.
(define (gallery-view-key entry)
  (list (gallery-plate-id (gallery-entry-plate entry))
        (gallery-view-id (gallery-entry-view entry))))

; make-gallery-camera! : exact-positive-integer? exact-positive-integer? symbol? -> camera?
;;   Constructs the one static native camera used for preparation and output.
(define (make-gallery-camera! width height theme)
  (define-values (_foreground background) (theme-colors theme))
  ((native 'animate 'make-camera) #:width width #:height height #:background background))

; finite-real? : any/c -> boolean?
;;   Recognizes finite real world-coordinate values in portable gallery records.
(define (finite-real? value)
  (and (real? value) (not (nan? value)) (not (infinite? value))))

; camera-world-height : camera? -> positive-real?
;;   Converts the frozen camera aspect ratio into y-up world height.
(define (camera-world-height camera)
  (* ((native 'animate 'camera-world-width) camera)
     (/ ((native 'animate 'camera-height) camera) ((native 'animate 'camera-width) camera))))

; text-box : camera? string? symbol? real? real? positive-real? string?
;            [#:alignment symbol?] [#:weight symbol?] -> layout-box?
;;   Measures one actual native text visual through the same camera used for final painting.
(define (text-box camera text id x y size color #:alignment [alignment 'center]
                  #:weight [weight 'normal])
  ((native 'animate 'visual-layout-box)
   ((native 'animate 'plain-text) text #:id id #:center ((native 'animate 'vec2) x y)
    #:font-size size #:font-weight weight #:horizontal-alignment alignment #:color color)
   #:camera camera))

; fitted-gallery-text : camera? string? (or/c exact-nonnegative-integer? #f) symbol?
;                        string? real? real? positive-real? positive-real? -> gallery-text?
;;   Measures and freezes a readable single-line text size without character-count estimates.
(define (fitted-gallery-text camera color segment suffix text x y requested-width requested-size)
  (define (fits? size)
    (<= (layout-box-width (text-box camera text 'gallery.measure x y size color)) requested-width))
  (define minimum-size 1/20)
  (unless (fits? minimum-size)
    (raise-arguments-error 'prepare-gallery-view!
                           "gallery text fitting within its measured allocation"
                           "text" text "available-width" requested-width))
  (define size
    (cond
      [(fits? requested-size) requested-size]
      [else
       (for/fold ([low minimum-size] [high requested-size] [best minimum-size])
                 ([_ (in-range 12)])
         (define middle (/ (+ low high) 2))
         (if (fits? middle)
             (values middle high middle)
             (values low middle best)))]))
  (gallery-text segment suffix (string->immutable-string text) x y size))

; gallery-title : gallery-entry? -> immutable-string?
;;   Gives one replay the same title passed to the shared mathematical compiler.
(define (gallery-title entry)
  (define plate (gallery-entry-plate entry))
  (define view (gallery-entry-view entry))
  (string->immutable-string
   (if (string=? (gallery-view-title view) "")
       (gallery-plate-title plate)
       (string-append (gallery-plate-title plate) " — " (gallery-view-title view)))))

; explanation-state? : prepared-math-plan? math? -> boolean?
;;   Distinguishes separately allocated explanatory formulas from working-row formulas.
(define (explanation-state? prepared state)
  (for/or ([entry (in-list (prepared-math-plan-schedule prepared))])
    (and (eq? (scheduled-phase-kind entry) 'explain)
         (equal? state (car (presentation-phase-annotation (scheduled-phase-phase entry)))))))

; layout-token-extents : (listof prepared-layout?) -> (values real? real? real? real?)
;;   Returns the complete conservative token rectangle, including source padding.
(define (layout-token-extents layouts)
  (define tokens (append-map prepared-layout-tokens layouts))
  (values (apply min (map (lambda (t) (- (prepared-token-x t) (/ (prepared-token-width t) 2))) tokens))
          (apply max (map (lambda (t) (+ (prepared-token-x t) (/ (prepared-token-width t) 2))) tokens))
          (apply min (map (lambda (t) (- (prepared-token-y t) (/ (prepared-token-height t) 2))) tokens))
          (apply max (map (lambda (t) (+ (prepared-token-y t) (/ (prepared-token-height t) 2))) tokens))))

; tree-lines : derivation? -> (listof (cons/c list? string?))
;;   Flattens the semantic hierarchy solely for a small compile-time inspector.
;;   Indentation is handled geometrically by the renderer rather than by leading
;;   spaces, so every label can remain left-aligned and readable.
(define (tree-lines derivation)
  (define (walk node)
    (define path (derivation-node-path node))
    (cons (cons path (symbol->string (car (reverse path))))
          (append-map walk (derivation-node-children node))))
  (append-map walk (derivation-tree derivation)))

; gallery-inspector-font-size : prepared-math-plan? gallery-entry? real? real? string? -> positive-real?
;;   Measures the longest level label at its true left anchor before workers see the replay.
(define (gallery-inspector-font-size prepared entry left width color)
  (define camera (prepared-math-plan-camera prepared))
  (define rows
    (append-map (lambda (segment) (tree-lines (plan-segment-derivation segment)))
                (presentation-plan-segments (gallery-view-plan (gallery-entry-view entry)))))
  (define (fits? size)
    (for/and ([row (in-list rows)])
      (define depth (sub1 (length (car row))))
      (define label-left (+ left 3/10 (* depth 9/25)))
      (define available (max 1/2 (- width 3/10 (* depth 9/25))))
      (<= (layout-box-width
           (text-box camera (cdr row) 'gallery.tree-measure label-left 0 size color
                     #:alignment 'left #:weight 'bold))
          available)))
  (cond [(fits? 17/100) 17/100]
        [(fits? 1/20)
         (for/fold ([low 1/20] [high 17/100] [best 1/20]) ([_ (in-range 12)])
           (define middle (/ (+ low high) 2))
           (if (fits? middle) (values middle high middle) (values low middle best)))]
        [else (raise-arguments-error 'prepare-gallery-view!
                                     "hierarchy labels fitting their measured inspector column"
                                     "view" (gallery-view-key entry))]))

; fit-gallery-preparation : gallery-entry? prepared-math-plan? boolean? -> prepared-gallery-view?
;;   Reserves measured header/footer regions and derives one frozen body baseline from token extents.
(define (fit-gallery-preparation entry prepared show-api?)
  (define view (gallery-entry-view entry))
  (define camera (prepared-math-plan-camera prepared))
  (define foreground (prepared-math-plan-foreground prepared))
  (define world-width ((native 'animate 'camera-world-width) camera))
  (define world-height (camera-world-height camera))
  (define title (gallery-title entry))
  (define heading-width (- world-width 7/5))
  (define headings
    (append-map
     (lambda (segment)
       (for/list ([line (in-list (presentation-header-lines (gallery-view-plan view) segment title))])
         (match-define (list suffix text top-offset size) line)
         (fitted-gallery-text camera foreground
                              (index-of (presentation-plan-segments (gallery-view-plan view)) segment)
                              suffix text 0 (- (/ world-height 2) top-offset) heading-width size)))
     (presentation-plan-segments (gallery-view-plan view))))
  (define caption
    (fitted-gallery-text camera foreground #f 'caption (gallery-view-caption view)
                         0 (+ (- (/ world-height 2)) 8/5) heading-width 9/50))
  (define api
    (and show-api?
         (fitted-gallery-text
          camera foreground #f 'api
          (string-append "API: " (string-join (map symbol->string (gallery-view-api view)) "  "))
          0 (+ (- (/ world-height 2)) 39/20) heading-width 3/20)))
  (define heading-bottom
    (apply min
           (for/list ([line (in-list headings)])
             (layout-box-bottom
              (text-box camera (gallery-text-text line) 'gallery.header
                        (gallery-text-x line) (gallery-text-y line) (gallery-text-size line) foreground)))))
  (define footer-top
    (apply max
           (for/list ([line (in-list (filter values (list caption api)))])
             (layout-box-top
              (text-box camera (gallery-text-text line) 'gallery.footer
                        (gallery-text-x line) (gallery-text-y line) (gallery-text-size line) foreground)))))
  (define explanation?
    (for/or ([entry (in-list (prepared-math-plan-schedule prepared))])
      (eq? (scheduled-phase-kind entry) 'explain)))
  (define verdict?
    (ormap plan-segment-verdict (presentation-plan-segments (gallery-view-plan view))))
  (define provenance? (gallery-view-provenance? view))
  (define recipe? (gallery-view-recipe-call view))
  (define body-left (if (gallery-view-tree? view) (- (/ world-width 20)) (+ (- (/ world-width 2)) 7/10)))
  (define body-right (- (/ world-width 2) 7/10))
  (define body-top (- heading-bottom 1/4))
  (define body-bottom
    (+ footer-top
       (cond [explanation? 3/2]
             [provenance? 1]
             [verdict? 3/4]
             [recipe? 13/20]
             [else 1/4])))
  (unless (> body-top body-bottom)
    (raise-arguments-error 'prepare-gallery-view! "nonempty measured gallery body" "view" (gallery-view-key entry)))
  (define all-layouts (hash-values (prepared-math-plan-layouts prepared)))
  (define working-layouts
    (filter (lambda (layout) (not (explanation-state? prepared (prepared-layout-state layout)))) all-layouts))
  (define-values (xmin xmax _ymin _ymax) (layout-token-extents working-layouts))
  (define start-scale (min 1 (/ (- body-right body-left) (max 1/10 (- xmax xmin)))))
  (define style (presentation-plan-style (prepared-math-plan-plan prepared)))
  (define required-rows
    (if (eq? (presentation-style-history style) 'replace)
        1
        (presentation-style-max-visible-rows style)))
  (define (metrics scale)
    (define dx (- (/ (+ body-left body-right) 2) (* scale (/ (+ xmin xmax) 2))))
    (define fitted
      (for/hash ([(state layout) (in-hash (prepared-math-plan-layouts prepared))])
        (values state
                (struct-copy prepared-layout layout
                             [tokens (map (lambda (token) (token-scaled token scale dx))
                                          (prepared-layout-tokens layout))]))))
    (define fitting-layouts
      (filter (lambda (layout) (not (explanation-state? prepared (prepared-layout-state layout))))
              (hash-values fitted)))
    (define-values (_left _right bottom top) (layout-token-extents fitting-layouts))
    (define upward (max 0 top))
    (define downward (max 0 (- bottom)))
    (define gap (max (* scale (prepared-math-plan-row-gap prepared)) (+ upward downward 1/4)))
    (define origin (- body-top 1/5 upward))
    (define capacity
      (max 0 (add1 (inexact->exact (floor (/ (- origin downward body-bottom 1/5) gap))))))
    (values fitted dx upward downward gap origin capacity))
  (define-values (fitted dx upward downward gap origin capacity)
    (let loop ([scale start-scale])
      (define-values (next-fitted next-dx u d next-gap next-origin next-capacity) (metrics scale))
      (cond [(>= next-capacity required-rows)
             (values next-fitted next-dx u d next-gap next-origin next-capacity)]
            [(<= scale 1/2)
             (raise-arguments-error
              'prepare-gallery-view!
              "a readable measured body with its required history rows"
              "view" (gallery-view-key entry) "required-rows" required-rows
              "capacity" next-capacity "available-height" (- body-top body-bottom))]
            [else (loop (max 1/2 (* scale 9/10)))])))
  (define max-rows (min (presentation-style-max-visible-rows style) capacity))
  (when (and (not (eq? (presentation-style-history style) 'replace)) (< max-rows 2))
    (raise-arguments-error 'prepare-gallery-view! "at least two rows for retained history"
                           "view" (gallery-view-key entry) "capacity" max-rows))
  (define inspector-left (+ (- (/ world-width 2)) 2/5))
  (define inspector-width (if (gallery-view-tree? view) (- body-left inspector-left 1/5) 0))
  (define inspector-font-size
    (if (gallery-view-tree? view)
        (gallery-inspector-font-size prepared entry inspector-left inspector-width foreground)
        1/20))
  (define layout
    (gallery-layout
     (list body-left body-bottom body-right body-top) origin caption api
     (+ footer-top 17/20) (+ footer-top 7/20)
     inspector-left inspector-width (- body-top 1/5) 7/25 inspector-font-size
     (/ (+ body-left body-right) 2)
     (if verdict? (- origin downward 7/20) (+ body-bottom 9/20))
     (if provenance? (+ footer-top 3/5) #f) (if recipe? (+ footer-top 7/20) #f)
     headings
     (map string->immutable-string
          (append (list (format "body ~s; origin ~a; rows ~a; gap ~a; scale ~a; U ~a; D ~a"
                                (list body-left body-bottom body-right body-top)
                                origin max-rows (/ gap 1) start-scale upward downward))
                  (if (< start-scale 1) (list (format "Gallery formula fit scale: ~a" start-scale)) '())))))
  (prepared-gallery-view
   (struct-copy prepared-math-plan prepared [layouts fitted] [row-gap gap] [max-rows max-rows]
                [diagnostics (append (prepared-math-plan-diagnostics prepared)
                                     (gallery-layout-diagnostics layout))])
   layout
   show-api?))

; prepare-gallery-view! : gallery-entry? camera? symbol? [#:show-api? boolean?] -> prepared-gallery-view?
;;   Typesets one complete replay once; the parent then freezes its gallery geometry.
(define (prepare-gallery-view! entry camera theme #:show-api? [show-api? #f])
  (unless (boolean? show-api?)
    (raise-argument-error 'prepare-gallery-view! "boolean? as #:show-api?" show-api?))
  (fit-gallery-preparation
   entry
   (prepare-math-plan! (gallery-view-plan (gallery-entry-view entry)) #:camera camera #:theme theme)
   show-api?))

; same-family-layouts : list? -> list?
;;   Freezes one comparison-family body origin and capacity without repeating typesetting.
(define (same-family-layouts prepared-views)
  (define families
    (remove-duplicates
     (filter values
             (map (lambda (item) (gallery-view-layout-family (gallery-entry-view (car item))))
                  prepared-views))))
  (for/fold ([result prepared-views]) ([family (in-list families)])
    (define members
      (filter (lambda (item) (eq? family (gallery-view-layout-family (gallery-entry-view (car item))))) result))
    (define origins (map (lambda (item) (gallery-layout-row-origin (prepared-gallery-view-layout (cdr item)))) members))
    (define capacities (map (lambda (item) (prepared-math-plan-max-rows (prepared-gallery-view-math (cdr item)))) members))
    (define bottoms (map (lambda (item) (cadr (gallery-layout-body (prepared-gallery-view-layout (cdr item))))) members))
    (define tops (map (lambda (item) (cadddr (gallery-layout-body (prepared-gallery-view-layout (cdr item))))) members))
    (define common-origin (apply min origins))
    (define common-capacity (apply min capacities))
    (define common-bottom (apply max bottoms))
    (define common-top (apply min tops))
    (for/list ([item (in-list result)])
      (if (eq? family (gallery-view-layout-family (gallery-entry-view (car item))))
          (let* ([view (cdr item)] [old (prepared-gallery-view-layout view)]
                 [body (gallery-layout-body old)]
                 [layout (struct-copy gallery-layout old
                                      [body (list (car body) common-bottom (caddr body) common-top)]
                                      [row-origin common-origin])])
            (cons (car item)
                  (struct-copy prepared-gallery-view view
                               [math (struct-copy prepared-math-plan (prepared-gallery-view-math view)
                                                  [max-rows common-capacity])]
                               [layout layout])))
          item))))

; prepare-gallery-views! : (listof gallery-entry?) camera? symbol? [#:show-api? boolean?] -> list?
;;   Prepares selected replays in stable order and normalizes declared comparison-family geometry.
(define (prepare-gallery-views! entries camera theme #:show-api? [show-api? #f])
  (map cdr
       (same-family-layouts
        (for/list ([entry (in-list entries)])
          (cons entry (prepare-gallery-view! entry camera theme #:show-api? show-api?))))))

; text-visual! : gallery-text? symbol? string? -> visual?
;;   Reconstructs one already measured gallery text visual without fitting it again.
(define (text-visual! placement id color)
  ((native 'animate 'plain-text) (gallery-text-text placement) #:id id
   #:center ((native 'animate 'vec2) (gallery-text-x placement) (gallery-text-y placement))
   #:font-size (gallery-text-size placement) #:color color))

; tree-line-visuals! : string? symbol? symbol? gallery-layout? real? nonnegative-integer?
;   string? boolean? boolean? -> (list/c visual? visual?)
;;   Creates separate stationary marker and true-left-anchored label visuals for one inspector row.
(define (tree-line-visuals! label marker-id label-id layout y depth color active? current-leaf?)
  (define marker-left (gallery-layout-inspector-left layout))
  (define label-left (+ marker-left 3/10 (* depth 9/25)))
  (define size (gallery-layout-inspector-font-size layout))
  (list
   ((native 'animate 'plain-text) (if active? "> " "· ") #:id marker-id
    #:center ((native 'animate 'vec2) marker-left y)
    #:font-size size #:color color #:horizontal-alignment 'left)
   ((native 'animate 'plain-text) label #:id label-id
    #:center ((native 'animate 'vec2) label-left y)
    #:font-size size #:color color #:horizontal-alignment 'left
    #:font-weight (if current-leaf? 'bold 'normal) #:opacity (if active? 1 3/5))))

; active-path? : list? (or/c #f symbol? list?) -> boolean?
;;   Highlights a current leaf and its containing moves, never inferring glyph matches.
(define (active-path? path key)
  (define target (if (symbol? key) (list key) key))
  (and target (<= (length path) (length target)) (equal? path (take target (length path)))))

; frozen-heading-placements : gallery-layout? -> immutable-hash?
;;   Adapts parent-measured header lines to the private optional adapter seam.
(define (frozen-heading-placements layout)
  (for/hash ([line (in-list (gallery-layout-headings layout))])
    (values (cons (gallery-text-segment line) (gallery-text-suffix line))
            (list (gallery-text-text line) (gallery-text-x line) (gallery-text-y line)
                  (gallery-text-size line)))))

; candidate-verdict-label : verification? -> string?
;;   Keeps gallery prose truthful about a candidate check without exposing internal status jargon.
(define (candidate-verdict-label verdict)
  (case (verification-status verdict)
    [(established) "This candidate is a solution."]
    [(refuted) "This candidate is not a solution."]
    [else "This candidate has not been verified."]))

; build-gallery-scene! : (listof gallery-entry?) (listof prepared-gallery-view?)
;   camera? [#:show-api? boolean?] -> scene?
;;   Appends independent frozen replays through the ordinary native compiler and cleans ids.
(define (build-gallery-scene! entries preparations camera #:show-api? [show-api? #f])
  (unless (and (= (length entries) (length preparations)) (pair? entries))
    (raise-arguments-error 'build-gallery-scene! "one preparation per selected view"
                           "entries" (length entries) "preparations" (length preparations)))
  (define scn ((native 'animate 'make-scene) #:camera camera))
  (for ([entry (in-list entries)] [prepared-view (in-list preparations)])
    (unless (prepared-gallery-view? prepared-view)
      (raise-argument-error 'build-gallery-scene! "prepared-gallery-view?" prepared-view))
    (define view (gallery-entry-view entry))
    (define prepared (prepared-gallery-view-math prepared-view))
    (define layout (prepared-gallery-view-layout prepared-view))
    (unless (and (equal? camera (prepared-math-plan-camera prepared))
                 (equal? (gallery-view-plan view) (prepared-math-plan-plan prepared))
                 (equal? show-api? (prepared-gallery-view-show-api? prepared-view)))
      (raise-arguments-error 'build-gallery-scene!
                             "matching view, frozen camera/plan, and API mode"
                             "view" (gallery-view-key entry)))
    (define plate (gallery-entry-plate entry))
    (define id (string->symbol (format "gallery.~a.~a" (gallery-plate-id plate) (gallery-view-id view))))
    (define foreground (prepared-math-plan-foreground prepared))
    (define caption-id (string->symbol (format "~a.caption" id)))
    (define api-id (string->symbol (format "~a.api" id)))
    (define recipe-id (string->symbol (format "~a.recipe" id)))
    (define decoration-ids '())
    (define (clear-decorations scene)
      (if (null? decoration-ids) scene
          (apply (native 'animate 'scene-remove) scene decoration-ids)))
    (define on-step
      (lambda (scene segment-index key)
        (define cleared (clear-decorations scene))
        (set! decoration-ids '())
        (if (not (gallery-view-tree? view))
            cleared
            (let* ([derivation
                    (plan-segment-derivation
                     (list-ref (presentation-plan-segments (gallery-view-plan view)) segment-index))]
                   [lines (tree-lines derivation)]
                   [ids
                    (append-map
                     (lambda (i)
                       (list (string->symbol (format "~a.tree.~a.marker" id i))
                             (string->symbol (format "~a.tree.~a.label" id i))))
                     (build-list (length lines) values))])
              (set! decoration-ids ids)
              (apply
               (native 'animate 'scene-add)
               cleared
               (append-map
                (lambda (line marker-id label-id i)
                  (define path (car line))
                  (define current (if (symbol? key) (list key) key))
                  (tree-line-visuals! (cdr line) marker-id label-id layout
                                      (- (gallery-layout-inspector-top layout)
                                         (* i (gallery-layout-inspector-row-gap layout)))
                                      (sub1 (length path)) foreground
                                      (active-path? path current) (equal? path current)))
                lines (filter (lambda (item) (regexp-match? #rx"marker$" (symbol->string item))) ids)
                (filter (lambda (item) (regexp-match? #rx"label$" (symbol->string item))) ids)
                (build-list (length lines) values)))))))
    (define on-step-end
      (and (gallery-view-provenance? view)
           (lambda (scene segment-index key)
             (define derivation
               (plan-segment-derivation
                (list-ref (presentation-plan-segments (gallery-view-plan view)) segment-index)))
             (define step (and key (derivation-step derivation key)))
             (define copied?
               (and step
                    (ormap (lambda (relation)
                             (and (eq? (trace-relation-kind relation) 'copy)
                                  (= (length (trace-relation-sources relation)) 1)
                                  (= (length (trace-relation-targets relation)) 2)))
                           (rewrite-step-trace step))))
             (if (not copied?) scene
                 (let ([witness-id (string->symbol (format "~a.provenance" id))])
                   (set! decoration-ids (cons witness-id decoration-ids))
                   ((native 'animate 'scene-add) scene
                    ((native 'animate 'plain-text)
                     "Witness: one occurrence has two descendants"
                     #:id witness-id
                     #:center ((native 'animate 'vec2) 0 (gallery-layout-overlay-y layout))
                     #:font-size 7/50 #:color foreground)))))))
    (define caption (gallery-layout-caption layout))
    (set! scn ((native 'animate 'scene-add) scn (text-visual! caption caption-id foreground)))
    (when show-api?
      (set! scn ((native 'animate 'scene-add) scn
                 (text-visual! (gallery-layout-api layout) api-id foreground))))
    (when (gallery-view-recipe-call view)
      (set! scn
            ((native 'animate 'scene-add) scn
             ((native 'animate 'plain-text) (gallery-view-recipe-call view) #:id recipe-id
              #:center ((native 'animate 'vec2) 0 (gallery-layout-recipe-y layout))
              #:font-size 7/50 #:color foreground))))
    (define-values (next owned checkpoint)
      (append-prepared-math-plan!
       scn prepared #:title (gallery-title entry) #:id id
       #:top-margin (- (/ (camera-world-height camera) 2) (gallery-layout-row-origin layout))
       #:heading-placements (frozen-heading-placements layout)
       #:annotation-placement
       (list (gallery-layout-annotation-y layout) (gallery-layout-annotation-caption-y layout))
       #:candidate-verdict-position
       (list (gallery-layout-verdict-x layout) (gallery-layout-verdict-y layout))
       #:candidate-verdict-label candidate-verdict-label
       #:on-step on-step #:on-step-end on-step-end))
    (set! scn ((native 'animate 'scene-wait) next gallery-settle-time))
    (set! scn (clear-decorations scn))
    (set! decoration-ids '())
    (set! scn (apply (native 'animate 'scene-remove) scn
                     (append owned (list caption-id)
                             (if show-api? (list api-id) '())
                             (if (gallery-view-recipe-call view) (list recipe-id) '()))))
    (set! scn ((native 'animate 'scene-remove-value) scn checkpoint))
    (set! scn ((native 'animate 'scene-wait) scn gallery-gap-time)))
  scn)

;;;
;;; Portable Gallery Geometry
;;;

; gallery-payload-hash : symbol? any/c -> immutable-hash?
;;   Rejects mutable or non-record data before worker-side geometry reconstruction.
(define (gallery-payload-hash who value)
  (unless (and (hash? value) (immutable? value))
    (raise-argument-error who "immutable hash?" value))
  value)

; gallery-payload-vector : symbol? any/c -> list?
;;   Converts a bounded immutable vector while rejecting list lookalikes in payload files.
(define (gallery-payload-vector who value)
  (unless (and (vector? value) (immutable? value))
    (raise-argument-error who "immutable vector?" value))
  (vector->list value))

; gallery-required : symbol? immutable-hash? symbol? procedure? -> any/c
;;   Fetches one checked gallery payload field with a field-specific diagnostic.
(define (gallery-required who record key predicate)
  (define value (hash-ref record key #f))
  (unless (predicate value)
    (raise-arguments-error who "a well-formed gallery layout field" "field" key "value" value))
  value)

; gallery-text->datum : gallery-text? -> immutable-hash?
;;   Serializes one frozen text placement without rendering or remeasurement.
(define (gallery-text->datum placement)
  (hasheq 'segment (gallery-text-segment placement)
          'suffix (gallery-text-suffix placement)
          'text (gallery-text-text placement)
          'x (gallery-text-x placement) 'y (gallery-text-y placement)
          'size (gallery-text-size placement)))

; datum->gallery-text : any/c -> gallery-text?
;;   Restores one bounded text record after validating the worker-safe payload grammar.
(define (datum->gallery-text value)
  (define record (gallery-payload-hash 'portable-payload->prepared-gallery-view value))
  (define segment (gallery-required 'portable-payload->prepared-gallery-view record 'segment
                                    (lambda (item) (or (not item) (exact-nonnegative-integer? item)))))
  (define suffix (gallery-required 'portable-payload->prepared-gallery-view record 'suffix symbol?))
  (define text (gallery-required 'portable-payload->prepared-gallery-view record 'text string?))
  (define x (gallery-required 'portable-payload->prepared-gallery-view record 'x finite-real?))
  (define y (gallery-required 'portable-payload->prepared-gallery-view record 'y finite-real?))
  (define size (gallery-required 'portable-payload->prepared-gallery-view record 'size positive?))
  (gallery-text segment suffix (string->immutable-string text) x y size))

; gallery-layout->datum : gallery-layout? -> immutable-hash?
;;   Serializes all parent-owned body, decoration, and diagnostic layout decisions.
(define (gallery-layout->datum layout)
  (hasheq
   'body (vector->immutable-vector (list->vector (gallery-layout-body layout)))
   'row-origin (gallery-layout-row-origin layout)
   'caption (and (gallery-layout-caption layout) (gallery-text->datum (gallery-layout-caption layout)))
   'api (and (gallery-layout-api layout) (gallery-text->datum (gallery-layout-api layout)))
   'annotation-y (gallery-layout-annotation-y layout)
   'annotation-caption-y (gallery-layout-annotation-caption-y layout)
   'inspector-left (gallery-layout-inspector-left layout)
   'inspector-width (gallery-layout-inspector-width layout)
   'inspector-top (gallery-layout-inspector-top layout)
   'inspector-row-gap (gallery-layout-inspector-row-gap layout)
   'inspector-font-size (gallery-layout-inspector-font-size layout)
   'verdict-x (gallery-layout-verdict-x layout) 'verdict-y (gallery-layout-verdict-y layout)
   'overlay-y (gallery-layout-overlay-y layout) 'recipe-y (gallery-layout-recipe-y layout)
   'headings (vector->immutable-vector
              (list->vector (map gallery-text->datum (gallery-layout-headings layout))))
   'diagnostics (vector->immutable-vector (list->vector (gallery-layout-diagnostics layout)))))

; datum->gallery-layout : any/c -> gallery-layout?
;;   Reconstitutes exactly the frozen private geometry; this function never fits text or formulas.
(define (datum->gallery-layout value)
  (define record (gallery-payload-hash 'portable-payload->prepared-gallery-view value))
  (define body (gallery-payload-vector 'portable-payload->prepared-gallery-view
                                       (hash-ref record 'body #f)))
  (unless (and (= (length body) 4) (andmap finite-real? body)
               (< (car body) (caddr body)) (< (cadr body) (cadddr body)))
    (raise-arguments-error 'portable-payload->prepared-gallery-view
                           "a nonempty four-coordinate gallery body" "body" body))
  (define (real-field key) (gallery-required 'portable-payload->prepared-gallery-view record key finite-real?))
  (define (positive-field key) (gallery-required 'portable-payload->prepared-gallery-view record key positive?))
  (define (optional-text key)
    (define item (hash-ref record key #f))
    (and item (datum->gallery-text item)))
  (define (optional-real key)
    (define item (hash-ref record key #f))
    (and item (gallery-required 'portable-payload->prepared-gallery-view record key finite-real?)))
  (define headings
    (map datum->gallery-text
         (gallery-payload-vector 'portable-payload->prepared-gallery-view
                                 (hash-ref record 'headings #f))))
  (define diagnostics
    (gallery-payload-vector 'portable-payload->prepared-gallery-view
                            (hash-ref record 'diagnostics #f)))
  (unless (and (pair? headings) (ormap (lambda (item) (eq? (gallery-text-suffix item) 'title)) headings)
               (andmap string? diagnostics))
    (raise-arguments-error 'portable-payload->prepared-gallery-view
                           "gallery headings and string diagnostics" "headings" headings))
  (gallery-layout body (real-field 'row-origin) (optional-text 'caption) (optional-text 'api)
                  (real-field 'annotation-y) (real-field 'annotation-caption-y)
                  (real-field 'inspector-left) (real-field 'inspector-width)
                  (real-field 'inspector-top) (positive-field 'inspector-row-gap)
                  (positive-field 'inspector-font-size)
                  (real-field 'verdict-x) (real-field 'verdict-y)
                  (optional-real 'overlay-y) (optional-real 'recipe-y)
                  headings (map string->immutable-string diagnostics)))

; prepared-gallery-view->portable-payload : prepared-gallery-view? immutable-hash? immutable-hash?
;                                            -> immutable-hash?
;;   Wraps the established mathematical payload with every gallery-only frozen decision.
(define (prepared-gallery-view->portable-payload prepared expected-options asset-paths)
  (unless (prepared-gallery-view? prepared)
    (raise-argument-error 'prepared-gallery-view->portable-payload "prepared-gallery-view?" prepared))
  (unless (and (hash? expected-options) (immutable? expected-options))
    (raise-argument-error 'prepared-gallery-view->portable-payload "immutable hash? as options" expected-options))
  (define show-api? (hash-ref expected-options 'show-api? #f))
  (unless (and (boolean? show-api?) (equal? show-api? (prepared-gallery-view-show-api? prepared)))
    (raise-arguments-error 'prepared-gallery-view->portable-payload
                           "an API option matching frozen gallery geometry"
                           "options" expected-options))
  (hasheq 'schema gallery-preparation-payload-schema
          'options expected-options
          'show-api? show-api?
          'math (prepared-math-plan->portable-payload
                 (prepared-gallery-view-math prepared) expected-options asset-paths)
          'layout (gallery-layout->datum (prepared-gallery-view-layout prepared))))

; portable-payload->prepared-gallery-view : immutable-hash? presentation-plan? camera? immutable-hash?
;                                            -> prepared-gallery-view?
;;   Validates the new schema and restores a replay without typesetting or layout measurement.
(define (portable-payload->prepared-gallery-view payload plan camera expected-options)
  (define record (gallery-payload-hash 'portable-payload->prepared-gallery-view payload))
  (unless (eq? (hash-ref record 'schema #f) gallery-preparation-payload-schema)
    (raise-arguments-error 'portable-payload->prepared-gallery-view
                           "the current gallery preparation schema"
                           "schema" (hash-ref record 'schema #f)))
  (unless (equal? (hash-ref record 'options #f) expected-options)
    (raise-arguments-error 'portable-payload->prepared-gallery-view
                           "gallery preparation options matching this worker"
                           "payload-options" (hash-ref record 'options #f)
                           "expected-options" expected-options))
  (define show-api? (gallery-required 'portable-payload->prepared-gallery-view record 'show-api? boolean?))
  (unless (equal? show-api? (hash-ref expected-options 'show-api? #f))
    (raise-arguments-error 'portable-payload->prepared-gallery-view
                           "an API mode matching frozen gallery geometry"
                           "prepared" show-api? "requested" (hash-ref expected-options 'show-api? #f)))
  (prepared-gallery-view
   (portable-payload->prepared-math-plan (hash-ref record 'math #f) plan camera expected-options)
   (datum->gallery-layout (hash-ref record 'layout #f))
   show-api?))
