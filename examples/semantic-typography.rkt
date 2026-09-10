#lang racket/base

;;;
;;; Semantic Typography Specimen
;;;

;; This compact scene is deliberately ordinary Animate source.  The semantic
;; constructors say what each piece of text is for; the typography snapshot
;; chosen by a project supplies the concrete family, size, colour role, and
;; optional treatment.

(require animate
         animate/colors
         animate/project)

(provide make-typography-scene
         lecture-typography
         typography-light-project
         typography-dark-project)

(define lecture-typography
  (typography-theme
   #:id 'lecture
   #:display-name "Lecture notes"
   #:extends animate-typography-theme
   #:styles
   (hash
    'title
    (text-style-update
     (typography-ref animate-typography-theme 'title)
     #:font-family 'roman
     #:font-size 9/10)
    'body
    (text-style-update
     (typography-ref animate-typography-theme 'body)
     #:font-size 9/20)
    'quotation
    (text-style-update
     (typography-ref animate-typography-theme 'quotation)
     #:font-size 9/20)
    'theorem-heading
    (text-style #:font-family 'swiss #:font-size 9/20
                #:font-style 'normal #:font-weight 'bold
                #:color theme-accent #:line-spacing 11/10
                #:line-alignment 'left
                #:horizontal-alignment 'left
                #:vertical-alignment 'top))))

(define (make-typography-scene)
  (define camera
    (make-camera #:width 1280 #:height 720 #:world-width 18
                 #:background theme-background))
  (scene-wait
   (scene-add
    (make-scene #:camera camera)
    (title-text "Semantic text" #:id 'title #:center (vec2 0 4))
    (subtitle-text "One scene can use light, dark, or custom typography."
                   #:id 'subtitle #:center (vec2 0 31/10))
    (section-heading-text "The standard roles" #:id 'section
                          #:center (vec2 -7/2 23/10))
    (body-text "Body text explains an idea.\nIt wraps at a maximum width."
               #:id 'body #:center (vec2 -7/2 6/5) #:width 6)
    (quotation-text "“A style says what this text is for.”"
                    #:id 'quotation #:center (vec2 -7/2 -3/5) #:width 6)
    (caption-text "A caption is small supporting text."
                  #:id 'caption #:center (vec2 -7/2 -17/10))
    (code-text "(title-text \"Hello\" #:id 'hello)"
               #:id 'code #:center (vec2 7/2 7/5) #:width 6)
    (annotation-text "Code gets a theme-aware treatment box."
                     #:id 'annotation #:center (vec2 7/2 1/10))
    (label-text "Label" #:id 'label #:center (vec2 7/2 -9/10))
    (styled-text "Theorem — custom styles belong in a typography theme."
                 #:style 'theorem-heading #:id 'theorem
                 #:center (vec2 0 -31/10) #:width 14))
   2))

;; The source scene is independent of either project.  The colour and
;; typography snapshots are explicit rendering choices, not mutable globals.
(define typography-light-project
  (animate-project
   #:id 'semantic-typography-light
   #:source (scene-source (make-typography-scene))
   #:render (render-spec #:fps 30 #:width 1280 #:height 720
                         #:theme animate-light-theme
                         #:typography lecture-typography)
   #:preview (preview-spec #:fps 30 #:pixel-scale 1/2 #:cache-megabytes 512)
   #:output (output-spec #:root "media" #:name "semantic-typography-light")
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root ".animate-cache" #:policy 'off)))

(define typography-dark-project
  (animate-project
   #:id 'semantic-typography-dark
   #:source (scene-source (make-typography-scene))
   #:render (render-spec #:fps 30 #:width 1280 #:height 720
                         #:theme animate-dark-theme
                         #:typography lecture-typography)
   #:preview (preview-spec #:fps 30 #:pixel-scale 1/2 #:cache-megabytes 512)
   #:output (output-spec #:root "media" #:name "semantic-typography-dark")
   #:encoder (encoder-spec #:codec 'none)
   #:cache (cache-spec #:root ".animate-cache" #:policy 'off)))
