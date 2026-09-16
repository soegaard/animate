#lang racket/base

;; Copyable layout examples. Diagram construction is deferred until preparation;
;; text keeps semantic roles and all styling comes from the supplied theme.
(require racket/class racket/list
         (only-in racket/draw make-pen make-brush dc-path%)
         (only-in pict dc)
         "../../main.rkt" "../../pict.rkt")
(provide gallery-entry-shots make-layout-example diagram)

(define (diagram)
  (pict-content
   (lambda (ctx)
     (define ink (content-color ctx 'foreground))
     (define accent (content-color ctx 'accent))
     (define muted (content-color ctx 'muted))
     (dc
      (lambda (draw x y)
        (define old-pen (send draw get-pen))
        (define old-brush (send draw get-brush))
        (define old-smoothing (send draw get-smoothing))
        (dynamic-wind void
          (lambda ()
            (send draw set-smoothing 'smoothed)
            (send draw set-brush (make-brush #:style 'transparent))
            (send draw set-pen (make-pen #:color muted #:width 2))
            (send draw draw-ellipse (+ x 150) (+ y 30) 300 300)
            (define triangle (new dc-path%))
            (send triangle move-to (+ x 170) (+ y 255))
            (send triangle line-to (+ x 430) (+ y 255))
            (send triangle line-to (+ x 300) (+ y 30))
            (send triangle close)
            (send draw set-pen (make-pen #:color accent #:width 5 #:cap 'round #:join 'round))
            (send draw draw-path triangle)
            (send draw set-pen (make-pen #:style 'transparent))
            (send draw set-brush (make-brush #:color ink))
            (for ([point (in-list '((170 255) (430 255) (300 30)))])
              (send draw draw-ellipse (+ x (car point) -5) (+ y (cadr point) -5) 10 10)))
          (lambda ()
            (send draw set-pen old-pen) (send draw set-brush old-brush)
            (send draw set-smoothing old-smoothing)))) 600 360))))

(define (make-layout-example id)
  (define layout-id (string->symbol (substring (symbol->string id) 7)))
  (case layout-id
    [(title) (slide #:id id #:layout 'title [title "A mathematical story"] [subtitle "One idea at a time"])]
    [(section) (slide #:id id #:layout 'section [title "Geometry"] [subtitle "Reasoning with constructions"])]
    [(title+body)
     (slide #:id id #:layout 'title+body [title "Explain one idea"]
       [body (bullets [structure "Choose a layout."] [identity "Name what matters."] [timing "Reveal it at the right moment."])])]
    [(title+two-column)
     (slide #:id id #:layout 'title+two-column [title "Two viewpoints"]
       [left (bullets [before "See the construction."] [evidence "Identify the evidence."])]
       [right (bullets [after "Write the relation."] [reason "Explain why it holds."])])]
    [(title+figure)
     (slide #:id id #:layout 'title+figure [title "Look for equal lengths"]
       [body "Use a circle to carry a distance.\nThe diagram keeps its own space."] [figure (diagram)])]
    [(figure+caption)
     (slide #:id id #:layout 'figure+caption [figure (diagram)] [caption "One diagram, one supporting caption."])]
    [(figure-full) (slide #:id id #:layout 'figure-full [figure (diagram)])]
    [(equation-focus)
     (slide #:id id #:layout 'equation-focus [equation "3x + 5 = 17"] [annotation "What value makes this true?"])]
    [(equation+explanation)
     (slide #:id id #:layout 'equation+explanation [title "A right triangle"]
       [equation "a² + b² = c²"] [body "The squares on the two shorter sides add up to the square on the hypotenuse."])]
    [(theorem)
     (slide #:id id #:layout 'theorem [title "Equal radii"]
       [statement "All radii of the same circle have equal length."]
       [body "Use the construction to justify the equal-side markers."])]
    [(quote)
     (slide #:id id #:layout 'quote [quote "Show what changes.\nKeep what matters."] [attribution "An authoring principle"])]
    [(blank) (slide #:id id #:layout 'blank [content (diagram)])]
    [else (raise-arguments-error 'make-layout-example "unknown gallery layout" "entry" id)]))

(define (gallery-entry-shots id theme fmt)
  (define s (make-layout-example id))
  (define clip
    (if (eq? id 'layout-title+body)
        (build-slide s #:initial 'hidden
          (beat 'heading #:duration 0.7 (reveal-slot 'title))
          (beat 'structure #:duration 0.9 (reveal-slot '(body structure)))
          (beat 'identity #:duration 0.9 (reveal-slot '(body identity)))
          (beat 'timing #:duration 0.9 (reveal-slot '(body timing)))
          (beat 'read #:duration 1.6))
        (build-slide s #:initial 'hidden
          (apply beat 'show #:duration 0.8
                 (for/list ([name (in-list (sort (hash-keys (slide-slots s)) symbol<?))])
                   (reveal-slot name #:duration 0.5)))
          (beat 'read #:duration 2.2))))
  (list (storyboard-shot id clip)))
