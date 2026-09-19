#lang scribble/manual
@(require racket/list racket/string
          "../../private/example-catalog.rkt")

@title[#:tag '("complete-example-catalog" "cookbook-canonical-examples")]{More example programs}

The preceding chapters are a selected reading path. This catalog lists the other
maintained examples as well, grouped by their main topic. Titles, source paths,
and requirements come from the existing example catalog; they are not maintained
as a second list in the manual.

Requirements describe running the full demonstration. A GUI example opens a
window; a formula example may need LaTeX and dvisvgm; movie encoding needs FFmpeg.
The source links below open the repository and can be newer than your checkout.

@(define (category entry)
   (define cs (example-entry-categories entry))
   (cond [(memq '3d cs) 'spatial]
         [(memq 'formula cs) 'formula]
         [(ormap (lambda (c) (memq c cs)) '(plotting relations ode)) 'plots]
         [(ormap (lambda (c) (memq c cs)) '(authoring preview rendering typography)) 'authoring]
         [else 'animation]))

@(define (program-list group)
   (itemlist
    (for/list ([entry (in-list canonical-example-catalog)]
               #:when (eq? group (category entry)))
      (item (bold (example-entry-title entry)) " — "
            (hyperlink
             (string-append "https://github.com/soegaard/animate/blob/main/"
                            (example-entry-source entry))
             (filepath (example-entry-source entry)))
            ". Requires "
            (string-join (map symbol->string (example-entry-requirements entry)) ", ")
            "."))))

@section[#:tag "complete-catalog-animation"]{Animation and composition}
@(program-list 'animation)

@section[#:tag "complete-catalog-plots"]{Plots, relations, and trajectories}
@(program-list 'plots)

@section[#:tag "complete-catalog-formulas"]{Formula animation}
@(program-list 'formula)

@section[#:tag "complete-catalog-authoring"]{Authoring, text, and media}
@(program-list 'authoring)

@section[#:tag "complete-catalog-spatial"]{3D examples}
@(program-list 'spatial)
