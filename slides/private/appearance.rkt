#lang racket/base
(require "data.rkt" "check.rkt"
         "../../colors.rkt" "../../typography.rkt")
(provide slide-format slide-format? slide-format-id slide-format-width slide-format-height
         widescreen standard portrait square-format
         slide-theme slide-theme? slide-theme-id slide-theme-colors slide-theme-typography
         slide-theme-spacing slide-theme-decorations lecture-light lecture-dark
         theme-spacing role-style)

(define slide-format? format-value?)
(define slide-format-id format-value-id)
(define slide-format-width format-value-width)
(define slide-format-height format-value-height)
(define (slide-format #:id id #:width width #:height height)
  (check-id 'slide-format id)
  (check-number 'slide-format width #t) (check-number 'slide-format height #t)
  (format-value id width height))
(define widescreen (slide-format #:id 'widescreen #:width 16 #:height 9))
(define standard (slide-format #:id 'standard #:width 12 #:height 9))
(define portrait (slide-format #:id 'portrait #:width 9 #:height 16))
(define square-format (slide-format #:id 'square #:width 12 #:height 12))

(define default-spacing
  (hash 'safe-x 0.65 'safe-y 0.50 'section-gap 0.35 'column-gap 0.60
        'bullet-gap 0.23 'paragraph-gap 0.25 'footer-height 0.35
        'subtitle-height 0.85 'math-minimum-scale 0.7 'title-band 1.2 'caption-band 0.85))
(define lecture-typography
  (typography-theme
   #:id 'slides-lecture #:extends animate-typography-theme
   #:styles
   (for/hash ([entry (in-list '((title . 0.67) (subtitle . 0.36)
                               (section-heading . 0.62) (body . 0.36)
                               (caption . 0.27) (annotation . 0.29)
                               (quotation . 0.50) (label . 0.27)))])
     (values (car entry)
             (text-style-update (typography-ref animate-typography-theme (car entry))
                                #:font-size (cdr entry))))))
(define (merge base overrides)
  (for/fold ([h base]) ([(k v) (in-hash overrides)]) (hash-set h k (immutable-copy v))))
(define (slide-theme #:id id #:extends [parent #f] #:colors [colors #f]
                     #:typography [typography #f] #:spacing [spacing (hash)]
                     #:decorations [decorations (hash)])
  (check-id 'slide-theme id)
  (unless (or (not parent) (theme-value? parent))
    (raise-argument-error 'slide-theme "slide-theme? as #:extends" parent))
  (define c (or colors (and parent (theme-value-colors parent)) animate-light-theme))
  (define t (or typography (and parent (theme-value-typography parent)) lecture-typography))
  (unless (color-theme? c) (raise-argument-error 'slide-theme "color-theme?" c))
  (unless (typography-theme? t) (raise-argument-error 'slide-theme "typography-theme?" t))
  (unless (and (hash? spacing) (hash? decorations))
    (raise-argument-error 'slide-theme "hashes for spacing and decorations" (list spacing decorations)))
  (for ([(k v) (in-hash spacing)])
    (check-id 'slide-theme k) (check-number 'slide-theme v)
    (when (and (eq? k 'math-minimum-scale) (> v 1))
      (raise-argument-error 'slide-theme "math-minimum-scale in [0,1]" v)))
  (for ([(k v) (in-hash decorations)])
    (check-enum 'slide-theme k '(title-rule? footer-rule?))
    (unless (boolean? v) (raise-argument-error 'slide-theme "boolean decoration" v)))
  (theme-value id c t
               (merge (if parent (theme-value-spacing parent) default-spacing) spacing)
               (merge (if parent (theme-value-decorations parent)
                          (hash 'title-rule? #f 'footer-rule? #f)) decorations)))
(define slide-theme? theme-value?)
(define slide-theme-id theme-value-id)
(define slide-theme-colors theme-value-colors)
(define slide-theme-typography theme-value-typography)
(define slide-theme-spacing theme-value-spacing)
(define slide-theme-decorations theme-value-decorations)
(define lecture-light (slide-theme #:id 'lecture-light #:colors animate-light-theme))
(define lecture-dark (slide-theme #:id 'lecture-dark #:colors animate-dark-theme))
(define (theme-spacing theme key)
  (if (number? key) (check-number 'theme-spacing key)
      (hash-ref (theme-value-spacing theme) key
                (lambda () (slides-error 'unknown-spacing (list key) "unknown spacing token")))))
(define (role-style theme role)
  (typography-ref (theme-value-typography theme) role))
