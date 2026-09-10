#lang racket/base

(require "color-token.rkt"
         "text-style.rkt"
         "typography-theme.rkt")

(provide animate-typography-theme)

(define (style #:family family #:size size #:weight [weight 'normal]
               #:style [font-style 'normal] #:color color #:spacing spacing
               #:line [line 'left] #:horizontal [horizontal 'left]
               #:vertical [vertical 'top] #:treatment [treatment #f])
  (text-style #:font-family family #:font-size size #:font-style font-style
              #:font-weight weight #:color color #:line-spacing spacing
              #:line-alignment line #:horizontal-alignment horizontal
              #:vertical-alignment vertical #:treatment treatment))

;; One typography table serves light and dark color themes.  It retains role
;; colors, which are resolved only during rendering.
(define animate-typography-theme
  (typography-theme
   #:id 'animate
   #:display-name "Animate"
   #:provenance 'animate-typography-v1
   #:styles
   (hash
    'title (style #:family 'swiss #:size 3/4 #:weight 'bold #:color theme-foreground
                  #:spacing 21/20 #:line 'center #:horizontal 'center #:vertical 'center)
    'subtitle (style #:family 'swiss #:size 1/2 #:color theme-muted
                     #:spacing 11/10 #:line 'center #:horizontal 'center #:vertical 'center)
    'section-heading (style #:family 'swiss #:size 3/5 #:weight 'bold #:color theme-accent
                           #:spacing 11/10)
    ;; A body paragraph is normally left-aligned within its own width, but its
    ;; box is centered on the constructor's #:center point.  This keeps a
    ;; short explanation positioned where an author places it without making
    ;; a multi-line paragraph needlessly centered.
    'body (style #:family 'swiss #:size 2/5 #:color theme-foreground #:spacing 6/5
                 #:line 'left #:horizontal 'center)
    'caption (style #:family 'swiss #:size 3/10 #:color theme-muted #:spacing 11/10)
    'label (style #:family 'swiss #:size 7/20 #:color theme-foreground
                  #:spacing 1 #:line 'center #:horizontal 'center #:vertical 'center)
    'quotation (style #:family 'roman #:size 2/5 #:style 'italic #:color theme-foreground #:spacing 5/4)
    'code (style #:family 'modern #:size 7/20 #:color theme-foreground #:spacing 6/5
                 #:treatment (text-treatment #:background theme-surface
                                             #:border-color theme-surface-edge
                                             #:border-width 1 #:padding-x 2/5 #:padding-y 3/10))
    'annotation (style #:family 'swiss #:size 1/4 #:color theme-muted #:spacing 11/10))))
