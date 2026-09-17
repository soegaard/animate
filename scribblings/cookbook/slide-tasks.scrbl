#lang scribble/manual
@(require scribble/example
          (for-label racket/base
                     (only-in animate
                              typography-theme
                              typography-ref
                              text-style-update)
                     animate/slides
                     animate/slides/pict
                     animate/slides/render)
          "../private/examples.rkt"
          "../private/illustrations.rkt")

@(define slide-eval (make-base-eval))
@examples[#:eval slide-eval #:hidden
  (require animate/slides animate/slides/pict animate/typography)]

@title[#:tag "cookbook-slide-tasks"]{Slide recipes}

Short slide recipes are evaluated as part of the manual build. The math and
geometry recipes remain complete source files because their domain plans and
toolchains are part of the example rather than incidental setup.

@section[#:tag "recipe-slide-picture"]{Make a title card}

@examples[#:eval slide-eval #:no-result
  (define welcome
    (slide #:id 'welcome #:layout 'title
      [title "Solving equations"]
      [subtitle "Keep both sides equal."]))
  (define welcome-picture
    (slide->pict welcome))]

@examples[#:eval slide-eval #:label #f
  (eval:check (slide? welcome) #t)]

@frame-strip["title-card"]

To give the card a duration, use @racket[(hold-slide welcome #:duration 3)].
A plain slide and its Pict do not have a movie duration. See
@secref["reference-slide-output"].

@section[#:tag "recipe-slide-builds"]{Reveal one bullet at a time}

@examples[#:eval slide-eval #:no-result
  (define build-card
    (slide #:id 'layout-title+body #:layout 'title+body
      [title "Explain one idea"]
      [body
       (bullets
        [structure "Choose a layout."]
        [identity "Name what matters."]
        [timing "Reveal it at the right moment."])]))

  (define build-clip
    (build-slide build-card #:initial 'hidden
      (beat 'heading #:duration 0.7
        (reveal-slot 'title))
      (beat 'structure #:duration 0.9
        (reveal-slot '(body structure)))
      (beat 'identity #:duration 0.9
        (reveal-slot '(body identity)))
      (beat 'timing #:duration 0.9
        (reveal-slot '(body timing)))
      (beat 'read #:duration 1.6)))]

@examples[#:eval slide-eval #:label #f
  (eval:check (slide-clip? build-clip) #t)]

@frame-strip["bullet-build"]

Select the second settled bullet state with
@racket[(slide->pict build-clip #:at '(identity end))]. To hide the complete
list later, append a beat containing
@racket[(conceal-slot 'body #:duration 0.5)]. To draw attention first, use
@racket[emphasize-slot] on a visible item. Neither operation frees layout space.
See @secref["reference-slide-actions"].

@section[#:tag "recipe-slide-theme"]{Use your own theme}

@examples[#:eval slide-eval #:no-result
  (define base-type
    (slide-theme-typography lecture-dark))
  (define course-type
    (typography-theme #:id 'course-type #:extends base-type
      #:styles
      (hash 'title
            (text-style-update (typography-ref base-type 'title)
                               #:font-family 'roman #:font-size 0.72))))
  (define course-theme
    (slide-theme #:id 'course #:extends lecture-dark
      #:typography course-type
      #:spacing (hash 'safe-x 0.8 'column-gap 0.7)
      #:decorations (hash 'title-rule? #t)))]

@examples[#:eval slide-eval #:label #f
  (eval:check (slide-theme? course-theme) #t)]

Use the theme on a storyboard or when converting an unprepared slide:

@examples[#:eval slide-eval #:no-result
  (define themed-picture
    (slide->pict welcome #:theme course-theme))]

This changes presentation settings; it does not rewrite @racket[welcome]. The
comparison below uses the built-in light and dark themes so the color change is
easy to see.

@frame-strip["lesson-themes"]

A prepared slide already has a measured layout. Change the original description
and prepare again. See @secref["reference-slide-appearance"].

@section[#:tag "recipe-slide-transition"]{Keep a title between slides}

Give corresponding contents a shared key, then match that key across a
transition.

@examples[#:eval slide-eval #:no-result
  (define shared-title
    (paragraph-content "Keep the idea" #:align 'left))
  (define title-before
    (slide #:layout 'title
      [title #:key 'topic #:align 'center shared-title]
      [subtitle "A centered introduction"]))
  (define title-after
    (slide #:layout 'title+body
      [title #:key 'topic shared-title]
      [body "The same prepared title moves to its new position."]))
  (define title-film
    (storyboard #:id 'manual-title-match #:theme lecture-dark
      (storyboard-shot 'before (hold-slide title-before #:duration 1.2))
      (slide-transition #:effect 'match #:keys '(topic)
                        #:duration 1 #:easing 'smooth)
      (storyboard-shot 'after (hold-slide title-after #:duration 1.8))))]

@examples[#:eval slide-eval #:label #f
  (eval:check (storyboard? title-film) #t)]

@frame-strip["title-match"]

The content keeps the key @racket['topic] while the layout changes. See
@secref["reference-slide-transitions"].

@section[#:tag "recipe-matched-parts"]{Move children as their panel changes layout}

Semantic part names state which children continue into the next arrangement.

@examples[#:eval slide-eval #:no-result
  (define (make-idea-panel final?)
    (define row
      (semantic-group #:width 10 #:height 3
        (semantic-part 'observe "Observe"
                       #:x (if final? 6 0) #:y 0 #:width 4 #:height 1.2)
        (semantic-part 'explain "Explain"
                       #:x (if final? 0 6) #:y 1.6 #:width 4 #:height 1.2)))
    (semantic-group #:width 12 #:height 6
      (semantic-part 'ideas row
                     #:x (if final? 0 1) #:y (if final? 1.4 0.4)
                     #:width (if final? 9 10) #:height 3)
      (semantic-part (if final? 'conclusion 'question)
                     (if final? "Connect the ideas." "What do we notice?")
                     #:x 1 #:y 4.5 #:width 10 #:height 1)))

  (define parts-before
    (slide #:layout 'title+figure
      [title "The parts keep their identities"]
      [figure #:key 'ideas (make-idea-panel #f)]))
  (define parts-after
    (slide #:layout 'title+figure
      [title "The parts keep their identities"]
      [body "The panel moves. Its named children rearrange independently."]
      [figure #:key 'ideas (make-idea-panel #t)]))
  (define parts-film
    (storyboard #:id 'manual-parts #:theme lecture-dark
      (storyboard-shot 'before (hold-slide parts-before #:duration 2))
      (slide-transition #:effect 'match #:keys '(ideas) #:depth 'semantic
                        #:duration 2.5 #:easing 'smooth)
      (storyboard-shot 'after (hold-slide parts-after #:duration 3))))]

@examples[#:eval slide-eval #:label #f
  (eval:check (storyboard? parts-film) #t)]

@frame-strip["semantic-parts"]

A part's x/y coordinates are measured from its containing group's top-left, not
its center. See @secref["reference-semantic-content"].

@section[#:tag "recipe-math-checkpoints"]{Move an equation while doing its algebra}

This example is intentionally kept as one complete program. Its derivation,
presentation plan, checkpoints, and storyboard belong together, and preparing
it uses the math typesetting toolchain.

@example-source["math-checkpoints.rkt"]
@frame-strip["semantic-math"]

Prepare with @racket[prepare-storyboard!] before sampling the result. The bridge
replays the authored derivation; it does not infer algebra from unrelated
pictures. See @secref["guide-checkpoint"] and
@secref["reference-semantic-content"].

@section[#:tag "recipe-geometry-slide"]{Reuse an animated construction}

This is also a complete-program example: the imported construction and slide
wrapper are separate reusable pieces.

@example-source["geometry-slide.rkt"]
@frame-strip["geometry-play"]

@racket[play-content] starts the local animation; revealing the slot alone does
not. Use the ordinary slide project runner for workers. See
@secref["recipe-render-workers"].

@close-eval[slide-eval]
