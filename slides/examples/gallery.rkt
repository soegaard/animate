#lang racket/base
(require animate/slides animate/slides/pict
         (only-in pict filled-rectangle cc-superimpose text colorize))
(provide gallery-slides gallery-film)
(define (figure label)
  (pict-content
   (lambda (ctx)
     (cc-superimpose
      (filled-rectangle 400 240 #:draw-border? #f #:color (content-color ctx 'surface-edge))
      (colorize (text label null 24) (content-color ctx 'foreground))))))
(define gallery-slides
  (list
   (slide #:id 'title #:layout 'title [title "Mathematics in motion"] [subtitle "Semantic content, consistent presentation"])
   (slide #:id 'section #:layout 'section [title "A new idea"] [subtitle "Chapter 2"])
   (slide #:id 'title+body #:layout 'title+body [title "Keep the structure"]
     [body (bullets [a "Name the important parts."] [b "Choose how they appear."] [c "Change appearance without editing content."])])
   (slide #:id 'title+two-column #:layout 'title+two-column [title "Compare two approaches"]
     [left (bullets [a "Static composition"] [b "A reusable pict"])]
     [right (bullets [a "Timed presentation"] [b "An ordinary Scene"])])
   (slide #:id 'title+figure #:layout 'title+figure [title "Explain a diagram"]
     [body "The layout reserves a stable region for the figure."] [figure (figure "DIAGRAM")])
   (slide #:id 'figure+caption #:layout 'figure+caption [figure (figure "A FIGURE")]
     [caption "A caption belongs to the figure, not to narration."])
   (slide #:id 'figure-full #:layout 'figure-full [figure (figure "FULL FIGURE")])
   (slide #:id 'equation-focus #:layout 'equation-focus [equation "3x + 5 = 17"] [annotation "Which value makes this true?"])
   (slide #:id 'equation+explanation #:layout 'equation+explanation [title "Preserve equality"]
     [equation "3x = 12"] [body "Subtract five from both sides."])
   (slide #:id 'theorem #:layout 'theorem [title "A useful observation"]
     [statement "Adding the same number to both sides preserves equality."]
     [body "The statement and its explanation occupy distinct semantic roles."])
   (slide #:id 'quote #:layout 'quote [quote "A layout says where; a theme says how."] [attribution "Themeable layouts"])
   (slide #:id 'blank #:layout 'blank [content "Start with an empty canvas."])))
(define (gallery-film [theme lecture-light] [format widescreen])
  (apply storyboard #:id 'layout-gallery #:theme theme #:format format
         (for/list ([s (in-list gallery-slides)])
           (storyboard-shot (slide-id s)
             (build-slide s #:initial 'hidden
               (apply beat 'reveal #:duration 2
                      (for/list ([name (in-list (hash-keys (slide-slots s)))])
                        (reveal-slot name #:duration 1)))
               (beat 'hold #:duration 1))))))
