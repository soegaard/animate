#lang racket/base

;;;
;;; Text Types in Animate
;;;
;; This source program is both a short lesson and a working specimen.  Open it
;; in the block-aware preview and choose a block to inspect one group of text
;; constructors at a time.

(require racket/cmdline
         animate
         animate/authoring
         animate/render)

(provide text-types-tutorial
         tutorial-title
         make-demo-program
         make-demo-timeline
         make-demo-scene)

(define tutorial-title "Animate text types")

(define tutorial-camera
  (make-camera #:width 1280 #:height 720 #:world-width 16
               #:background "white"))

;; A block starts from the complete immutable Scene made by the preceding
;; block.  Removing one page before adding the next keeps this specimen easy
;; to read in both the previewer and a rendered video.
(define (clear-page scn old-ids)
  (apply scene-remove scn old-ids))

(define-scene-program text-types-tutorial
  #:initial (make-scene #:camera tutorial-camera)

  ;; Typography is data chosen at rendering time.  Semantic constructors keep
  ;; only their role in the Scene, so the same program can use another theme.
  (scene-block typography (scn)
    (define title
      (title-text "Text has a role"
                  #:id 'typography-title #:center (vec2 0 3)))
    (define subtitle
      (subtitle-text "Animate separates what text is for from how it looks."
                     #:id 'typography-subtitle #:center (vec2 0 2)))
    (define explanation
      (body-text
       "A typography theme supplies each role's font, size, weight, colour, and alignment. Choose a role such as title or caption in the source; choose the theme when you preview or render."
       #:id 'typography-body #:center (vec2 0 1/4) #:width 12))
    (define note
      (annotation-text
       "The box is centered on #:center; body lines remain left-aligned."
       #:id 'typography-note #:center (vec2 0 -2)
       #:horizontal-alignment 'center))
    (scene-wait
     (scene-play scn
                 (fade-in title) (fade-in subtitle) (fade-in explanation) (fade-in note)
                 #:duration 3/5)
     2))

  ;; These roles name presentation hierarchy. They are semantic text values,
  ;; not hand-selected fonts.
  (scene-block headings (scn)
    (define title
      (title-text "title-text"
                  #:id 'role-title #:center (vec2 0 3)))
    (define subtitle
      (subtitle-text "subtitle-text — supporting text for a title"
                     #:id 'role-subtitle #:center (vec2 0 2)))
    (define heading
      (section-heading-text "section-heading-text"
                            #:id 'role-section-heading #:center (vec2 -6 3/4)))
    (define body
      (body-text
       "Use these three roles to show the structure of a presentation. The theme decides their visual hierarchy."
       #:id 'headings-body #:center (vec2 0 -1/4) #:width 12))
    (scene-wait
     (scene-play
      (clear-page scn
                  '(typography-title typography-subtitle typography-body typography-note))
      (fade-in title) (fade-in subtitle) (fade-in heading) (fade-in body)
      #:duration 3/5)
     2))

  ;; These roles explain and label the main material of a video.
  (scene-block explanatory-text (scn)
    (define heading
      (section-heading-text "Explanatory text"
                            #:id 'explanation-heading #:center (vec2 -6 3)))
    (define body
      (body-text
       "body-text is ordinary explanatory copy. Give it a width when it should wrap into a paragraph."
       #:id 'role-body #:center (vec2 -3 9/5) #:width 6))
    (define quotation
      (quotation-text
       "“quotation-text is for a quoted voice or an important statement.”"
       #:id 'role-quotation #:center (vec2 -3 -1/10) #:width 6))
    (define caption
      (caption-text "caption-text is small supporting detail."
                    #:id 'role-caption #:center (vec2 -3 -17/10)))
    (define label
      (label-text "label-text"
                  #:id 'role-label #:center (vec2 4 9/5)))
    (define label-detail
      (body-text
       "A label names a nearby thing, control, or value."
       #:id 'label-detail #:center (vec2 4 1) #:width 4
       #:line-alignment 'center))
    (scene-wait
     (scene-play
      (clear-page scn
                  '(role-title role-subtitle role-section-heading headings-body))
      (fade-in heading) (fade-in body) (fade-in quotation) (fade-in caption)
      (fade-in label) (fade-in label-detail)
      #:duration 3/5)
     3))

  ;; Code and annotations are also semantic roles.  The built-in code role has
  ;; a theme-controlled treatment box, while annotations are quieter notes.
  (scene-block technical-text (scn)
    (define heading
      (section-heading-text "Technical text"
                            #:id 'technical-heading #:center (vec2 -6 3)))
    (define code
      (code-text "(title-text \"Hello\" #:id 'hello)"
                 #:id 'role-code #:center (vec2 0 3/2) #:width 11
                 #:horizontal-alignment 'center))
    (define annotation
      (annotation-text
       "annotation-text adds a quiet note without competing with the main explanation."
       #:id 'role-annotation #:center (vec2 0 1/4) #:width 11
       #:line-alignment 'center #:horizontal-alignment 'center))
    (define styled
      (styled-text "styled-text chooses a named style"
                   #:style 'section-heading #:id 'role-styled
                   #:center (vec2 0 -1) #:horizontal-alignment 'center))
    (define rich
      (styled-rich-text
       #:style 'body #:id 'role-styled-rich #:center (vec2 0 -2) #:width 11
       "styled-rich-text keeps "
       (text-span "inline emphasis" #:font-weight 'bold)
       " while the surrounding role still comes from the theme."
       #:line-alignment 'center))
    (scene-wait
     (scene-play
      (clear-page scn
                  '(explanation-heading role-body role-quotation role-caption role-label label-detail))
      (fade-in heading) (fade-in code) (fade-in annotation) (fade-in styled) (fade-in rich)
      #:duration 3/5)
     3))

  ;; Raw constructors are useful when the source, rather than the theme,
  ;; deliberately owns every font and colour choice.
  (scene-block raw-text (scn)
    (define heading
      (section-heading-text "Low-level text constructors"
                            #:id 'raw-heading #:center (vec2 -6 3)))
    (define plain
      (plain-text "plain-text — one line with explicit font settings"
                  #:id 'raw-plain #:center (vec2 0 3/2)
                  #:font-size 2/5 #:font-family 'swiss #:font-weight 'bold
                  #:color "navy"))
    (define raw-paragraph
      (paragraph
       "paragraph wraps ordinary text when you give it a width. Use it when the source should own the appearance instead of a typography theme."
       #:id 'raw-paragraph #:center (vec2 0 1/10) #:width 11
       #:font-size 1/3 #:font-family 'swiss #:color "darkslategray"
       #:horizontal-alignment 'center #:line-alignment 'left))
    (define rich
      (rich-text #:id 'raw-rich #:center (vec2 0 -2)
                 #:font-size 1/3 #:font-family 'swiss #:color "black"
                 "rich-text combines "
                 (text-span "styled" #:font-weight 'bold #:color "crimson")
                 " inline spans in one raw text value."))
    (scene-wait
     (scene-play
      (clear-page scn
                  '(technical-heading role-code role-annotation role-styled role-styled-rich))
      (fade-in heading) (fade-in plain) (fade-in raw-paragraph) (fade-in rich)
      #:duration 3/5)
     3))

  (scene-block recap (scn)
    (define title
      (title-text "Choose the role first"
                  #:id 'recap-title #:center (vec2 0 2)))
    (define body
      (body-text
       "Use semantic text for presentation text: title, body, caption, code, and the other named roles. Use styled-text for a named custom style. Use plain-text, paragraph, or rich-text only when the source should control the exact appearance."
       #:id 'recap-body #:center (vec2 0 0) #:width 12))
    (define note
      (annotation-text
       "Change the typography theme to change the whole video without rewriting its story."
       #:id 'recap-note #:center (vec2 0 -5/2)
       #:horizontal-alignment 'center))
    (scene-wait
     (scene-play
      (clear-page scn '(raw-heading raw-plain raw-paragraph raw-rich))
      (fade-in title) (fade-in body) (fade-in note)
      #:duration 3/5)
     2)))

(define (make-demo-program)
  text-types-tutorial)

(define (compile-demo-program)
  (compile-scene-program text-types-tutorial))

(define (make-demo-timeline)
  (define compiled (compile-demo-program))
  (make-authored-timeline
   (compiled-scene-program-scene compiled)
   #:sections
   (for/list ([run (in-list (compiled-scene-program-block-runs compiled))])
     (section (scene-block-run-id run)
              (scene-block-run-start-time run)
              (scene-block-run-end-time run)))))

(define (make-demo-scene)
  (compiled-scene-program-scene (compile-demo-program)))

(module+ main
  (define output-directory "frames")
  (define output-video #f)
  (command-line
   #:program "text-types-tutorial.rkt"
   #:args ([frames-directory "frames"] [mp4-file #f])
   (set! output-directory frames-directory)
   (set! output-video mp4-file))
  (define paths (render-frames! (make-demo-scene) output-directory #:fps 30))
  (printf "Rendered ~a frames to ~a\n" (length paths) output-directory)
  (when output-video
    (encode-mp4! output-directory output-video #:fps 30)
    (printf "Encoded ~a\n" output-video)))
