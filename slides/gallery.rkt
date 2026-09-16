#lang racket/base

;; A data-only catalogue. Listing/selecting entries does not initialize native
;; rendering, TeX, geometry realization, audio probing, or a window.
(require racket/list racket/runtime-path
         "main.rkt")
(provide slide-gallery-entries slide-gallery-categories select-slide-gallery-entries
         slide-gallery-entry? slide-gallery-entry-id slide-gallery-entry-category
         slide-gallery-entry-title slide-gallery-entry-description
         slide-gallery-entry-requirements slide-gallery-entry-example
         slide-gallery-entry-source make-slide-gallery)

(struct slide-gallery-entry-value (id category title description requirements example source) #:transparent)
(define slide-gallery-entry? slide-gallery-entry-value?)
(define slide-gallery-entry-id slide-gallery-entry-value-id)
(define slide-gallery-entry-category slide-gallery-entry-value-category)
(define slide-gallery-entry-title slide-gallery-entry-value-title)
(define slide-gallery-entry-description slide-gallery-entry-value-description)
(define slide-gallery-entry-requirements slide-gallery-entry-value-requirements)
(define slide-gallery-entry-example slide-gallery-entry-value-example)
(define slide-gallery-entry-source slide-gallery-entry-value-source)
(define (entry-record id category title description requirements example source)
  (slide-gallery-entry-value id category (string->immutable-string title)
                             (string->immutable-string description) requirements
                             (string->immutable-string example) (string->immutable-string source)))
(define slide-gallery-categories '(layouts transitions integration))
(define (layout-entry id title description example)
  (entry-record id 'layouts title description '() example "examples/gallery/layouts.rkt"))
(define (transition-entry id title description example)
  (entry-record id 'transitions title description '() example "examples/gallery/transitions.rkt"))
(define slide-gallery-entries
  (append
   (list
    (layout-entry 'layout-title "Title" "A centered opening title and subtitle."
                  "(slide #:layout 'title [title \"A mathematical story\"] [subtitle \"One idea at a time\"])")
    (layout-entry 'layout-section "Section" "A section divider using the section-heading typography role."
                  "(slide #:layout 'section [title \"Geometry\"] [subtitle \"Reasoning with constructions\"])")
    (layout-entry 'layout-title+body "Title and body" "Keyed bullets appear in order while their space stays reserved."
                  "(reveal-slot '(body identity) #:duration 0.4)")
    (layout-entry 'layout-title+two-column "Two columns" "Related content side by side; compact stacking in portrait."
                  "(slide #:layout 'title+two-column [title \"Compare\"] [left \"Before\"] [right \"After\"])")
    (layout-entry 'layout-title+figure "Text and figure" "A stable diagram region beside explanatory text."
                  "(slide #:layout 'title+figure [title \"Observe\"] [body \"Compare the sides.\"] [figure diagram])")
    (layout-entry 'layout-figure+caption "Figure and caption" "A figure with a caption attached to its own reserved band."
                  "(slide #:layout 'figure+caption [figure diagram] [caption \"A triangle and its circle.\"])")
    (layout-entry 'layout-figure-full "Full figure" "A figure occupies the canvas without a title region."
                  "(slide #:layout 'figure-full [figure diagram])")
    (layout-entry 'layout-equation-focus "Equation focus" "The equation and its question form one centered unit."
                  "(slide #:layout 'equation-focus [equation \"3x + 5 = 17\"] [annotation \"What value makes this true?\"])")
    (layout-entry 'layout-equation+explanation "Equation and explanation" "Keep the expression visible while explaining its meaning."
                  "(slide #:layout 'equation+explanation [equation \"a² + b² = c²\"] [body \"The sides of a right triangle.\"])")
    (layout-entry 'layout-theorem "Theorem" "Statement, heading, and explanation have distinct text roles."
                  "(slide #:layout 'theorem [title \"A useful fact\"] [statement \"Equal radii have equal length.\"] [body \"Use the circles as evidence.\"])")
    (layout-entry 'layout-quote "Quotation" "A quotation with a separate attribution role."
                  "(slide #:layout 'quote [quote \"Show what changes. Keep what matters.\"] [attribution \"An authoring principle\"])")
    (layout-entry 'layout-blank "Blank canvas" "A safe region for an arbitrary Pict or a custom composition."
                  "(slide #:layout 'blank [content diagram])"))
   (list
    (transition-entry 'cut "Cut" "An exact, zero-duration switch between shots." "(storyboard-cut)")
    (transition-entry 'crossfade "Crossfade" "Fade between frozen endpoints without moving their local clocks."
                      "(slide-transition #:effect 'crossfade #:duration 1 #:easing 'smooth)")
    (transition-entry 'match "Matched title" "Keep one prepared title and move it into a different layout."
                      "(slide-transition #:effect 'match #:keys '(topic) #:duration 1 #:easing 'smooth)"))
   (for*/list ([effect (in-list '(push wipe cover uncover))]
               [direction (in-list '(left right up down))])
     (transition-entry
      (string->symbol (format "~a-~a" effect direction))
      (format "~a / ~a" effect direction)
      (case effect
        [(push) "Both panels travel together. Their backgrounds and decorations move too."]
        [(wipe) "A moving boundary reveals the stationary destination."]
        [(cover) "The incoming panel travels over the stationary outgoing panel."]
        [(uncover) "The outgoing panel moves away to reveal a stationary destination."])
      (format "(slide-transition #:effect '~a #:direction '~a #:duration 1 #:easing 'smooth)" effect direction)))
   (list
    (transition-entry 'zoom "Zoom crossfade" "Scale around the canvas center while fading between compositions."
                      "(slide-transition #:effect 'zoom #:scale 0.82 #:duration 1 #:easing 'smooth)")
    (transition-entry 'fade-through "Fade through a color" "Two halves meet at an exact solid-color midpoint."
                      "(slide-transition #:effect 'fade-through #:color \"#101820\" #:duration 1)")
    (transition-entry 'easing "Easing comparison" "The same push with linear, smooth, ease-in, ease-out, and ease-in-out timing."
                      "(slide-transition #:effect 'push #:direction 'left #:easing 'ease-in-out #:duration 1)"))
   (list
    (entry-record 'semantic-parts 'transitions "Recursive named parts"
           "A panel moves between layouts while named children rearrange; a removed question fades and a conclusion appears."
           '() "(slide-transition #:effect 'match #:keys '(ideas) #:depth 'semantic #:duration 2.5)"
           "examples/gallery/semantic-parts.rkt")
    (entry-record 'semantic-math 'integration "Semantic mathematical continuity"
           "Move an equation between layouts while replaying the existing subtraction, cancellation, and evaluation choreography."
           '(math) "(content-state (math-content plan) #:at '(subtract-five start) #:viewport '(12 7))"
           "examples/gallery/semantic-domains.rkt")
    (entry-record 'semantic-geometry 'integration "Semantic construction continuity"
           "Move a fixed construction viewport while replaying the same geometry timeline, without independent point/label tweening."
           '(geometry) "(content-state (geometry-content construction) #:at 'end #:viewport '(12 7))"
           "examples/gallery/semantic-domains.rkt")
    (entry-record 'semantic-math-geometry 'integration "Recursive math and geometry"
           "Two named native children change places while their independently witnessed domain plans advance during one bridge."
           '(math geometry) "(semantic-group #:width 16 #:height 8 equation-part construction-part caption-part)"
           "examples/gallery/semantic-domains.rkt")
    (entry-record 'native-scene 'integration "Native Scene" "A moving native Visual plays inside an independently timed slide."
           '() "(play-content 'figure)" "examples/gallery/native.rkt")
    (entry-record 'math-derivation 'integration "Mathematical derivation" "Real TeX-backed algebra with named subtraction and cancellation cues."
           '(math) "(play-content 'figure #:to '(cancel-five end))" "examples/gallery/math.rkt")
    (entry-record 'geometry-construction 'integration "Geometry construction" "A native equilateral-triangle construction with a persistent slide heading."
           '(geometry) "(geometry-content equilateral-triangle)" "examples/gallery/geometry.rkt")
    (entry-record 'math-and-geometry 'integration "Geometry and algebra" "Two native local clocks: construct an equilateral triangle and solve its perimeter equation."
           '(math geometry) "(beat 'explain #:narration draft (play-content 'left) (play-content 'right))"
           "examples/gallery/math-geometry.rkt"))))

(define (select-slide-gallery-entries #:entries [ids #f] #:category [category #f])
  (when category
    (unless (memq category slide-gallery-categories)
      (raise-argument-error 'select-slide-gallery-entries "'layouts, 'transitions, or 'integration" category)))
  (when ids
    (unless (and (list? ids) (pair? ids) (andmap symbol? ids))
      (raise-argument-error 'select-slide-gallery-entries "nonempty list of entry symbols" ids))
    (unless (= (length ids) (length (remove-duplicates ids)))
      (raise-arguments-error 'select-slide-gallery-entries "entry IDs must be unique" "entries" ids)))
  (define selected
    (if ids
        (for/list ([id (in-list ids)])
          (or (findf (lambda (e) (eq? id (slide-gallery-entry-value-id e))) slide-gallery-entries)
              (raise-arguments-error 'select-slide-gallery-entries "unknown gallery entry" "entry" id)))
        slide-gallery-entries))
  (when (and ids category (ormap (lambda (e) (not (eq? category (slide-gallery-entry-value-category e)))) selected))
    (raise-arguments-error 'select-slide-gallery-entries "selected entries must belong to the requested category"
                           "category" category "entries" ids))
  (if category (filter (lambda (e) (eq? category (slide-gallery-entry-value-category e))) selected) selected))

(define-runtime-path layouts-module "examples/gallery/layouts.rkt")
(define-runtime-path transitions-module "examples/gallery/transitions.rkt")
(define-runtime-path native-module "examples/gallery/native.rkt")
(define-runtime-path math-module "examples/gallery/math.rkt")
(define-runtime-path geometry-module "examples/gallery/geometry.rkt")
(define-runtime-path combined-module "examples/gallery/math-geometry.rkt")
(define-runtime-path semantic-parts-module "examples/gallery/semantic-parts.rkt")
(define-runtime-path semantic-domains-module "examples/gallery/semantic-domains.rkt")
(define (make-slide-gallery #:entries [ids #f] #:category [category #f]
                            #:theme [theme lecture-light] #:format [fmt widescreen]
                            #:motion [motion 'normal])
  (unless (slide-theme? theme) (raise-argument-error 'make-slide-gallery "slide-theme?" theme))
  (unless (slide-format? fmt) (raise-argument-error 'make-slide-gallery "slide-format?" fmt))
  (unless (memq motion '(normal reduced))
    (raise-argument-error 'make-slide-gallery "'normal or 'reduced as #:motion" motion))
  (define selected (select-slide-gallery-entries #:entries ids #:category category))
  (define entries
    (append-map
     (lambda (e)
       (define module
         (cond
           [(eq? (slide-gallery-entry-value-id e) 'semantic-parts) semantic-parts-module]
           [(memq (slide-gallery-entry-value-id e) '(semantic-math semantic-geometry semantic-math-geometry))
            semantic-domains-module]
           [else
         (case (slide-gallery-entry-value-category e)
           [(layouts) layouts-module]
           [(transitions) transitions-module]
           [else (case (slide-gallery-entry-value-id e)
                   [(native-scene) native-module]
                   [(math-derivation) math-module]
                   [(geometry-construction) geometry-module]
                   [(math-and-geometry) combined-module])])]))
       ;; Every builder constructs descriptions only. External resources are
       ;; prepared by the existing explicit slides/render boundary later.
       ((dynamic-require module 'gallery-entry-shots) (slide-gallery-entry-value-id e) theme fmt))
     selected))
  (apply storyboard #:id 'slide-gallery #:theme theme #:format fmt #:motion motion entries))
