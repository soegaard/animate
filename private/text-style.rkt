#lang racket/base

;; Immutable, renderer-independent complete typography style values.

(require "color-style.rkt"
         "paint.rkt"
         "geometry.rkt"
         "text-properties.rkt")

(provide text-treatment
         text-treatment?
         text-treatment-background
         text-treatment-border-color
         text-treatment-border-width
         text-treatment-padding-x
         text-treatment-padding-y
         text-treatment-update
         text-style
         text-style?
         text-style-font-face
         text-style-font-family
         text-style-font-size
         text-style-font-style
         text-style-font-weight
         text-style-color
         text-style-line-spacing
         text-style-line-alignment
         text-style-horizontal-alignment
         text-style-vertical-alignment
         text-style-treatment
         text-style-update
         text-style->datum
         datum->text-style)

(define unspecified (gensym 'unspecified))

(struct text-treatment-value (background border-color border-width padding-x padding-y)
  #:transparent)

(define (text-treatment #:background [background #f]
                        #:border-color [border-color #f]
                        #:border-width [border-width 0]
                        #:padding-x [padding-x 0]
                        #:padding-y [padding-y 0])
  (unless (or (not background) (paint? background))
    (raise-argument-error 'text-treatment "(or/c #f paint?) as #:background" background))
  (unless (or (not border-color) (color-spec? border-color))
    (raise-argument-error 'text-treatment "(or/c #f color-spec?) as #:border-color" border-color))
  (for ([value (in-list (list border-width padding-x padding-y))]
        [name (in-list '(border-width padding-x padding-y))])
    (unless (and (finite-real? value) (>= value 0))
      (raise-arguments-error 'text-treatment "a nonnegative finite real value"
                             "property" name "value" value)))
  (text-treatment-value (and background (normalize-paint background 'text-treatment))
                        (and border-color (normalize-color-spec border-color 'text-treatment))
                        border-width padding-x padding-y))

(define text-treatment? text-treatment-value?)
(define text-treatment-background text-treatment-value-background)
(define text-treatment-border-color text-treatment-value-border-color)
(define text-treatment-border-width text-treatment-value-border-width)
(define text-treatment-padding-x text-treatment-value-padding-x)
(define text-treatment-padding-y text-treatment-value-padding-y)

;; text-treatment-update : text-treatment? ... -> text-treatment?
;; Returns a copy whose explicitly supplied properties replace the matching
;; value.  The private sentinel keeps an omitted keyword distinct from an
;; explicit #f for background and border color.
(define (text-treatment-update treatment
                               #:background [background unspecified]
                               #:border-color [border-color unspecified]
                               #:border-width [border-width unspecified]
                               #:padding-x [padding-x unspecified]
                               #:padding-y [padding-y unspecified])
  (unless (text-treatment? treatment)
    (raise-argument-error 'text-treatment-update "text-treatment?" treatment))
  (define (keep proposed prior)
    (if (eq? proposed unspecified) prior proposed))
  (text-treatment
   #:background (keep background (text-treatment-background treatment))
   #:border-color (keep border-color (text-treatment-border-color treatment))
   #:border-width (keep border-width (text-treatment-border-width treatment))
   #:padding-x (keep padding-x (text-treatment-padding-x treatment))
   #:padding-y (keep padding-y (text-treatment-padding-y treatment))))

(struct text-style-value
  (font-face font-family font-size font-style font-weight color line-spacing
             line-alignment horizontal-alignment vertical-alignment treatment)
  #:transparent)

(define (text-style #:font-face [font-face #f]
                    #:font-family font-family
                    #:font-size font-size
                    #:font-style font-style
                    #:font-weight font-weight
                    #:color color
                    #:line-spacing line-spacing
                    #:line-alignment line-alignment
                    #:horizontal-alignment horizontal-alignment
                    #:vertical-alignment vertical-alignment
                    #:treatment [treatment #f])
  (define checked-face (check-font-face 'text-style font-face))
  (unless (text-font-family? font-family)
    (raise-argument-error 'text-style "text-font-family? as #:font-family" font-family))
  (unless (text-font-size? font-size)
    (raise-argument-error 'text-style "positive finite real? as #:font-size" font-size))
  (unless (text-font-style? font-style)
    (raise-argument-error 'text-style "text-font-style? as #:font-style" font-style))
  (unless (text-font-weight? font-weight)
    (raise-argument-error 'text-style "text-font-weight? as #:font-weight" font-weight))
  (unless (color-spec? color)
    (raise-argument-error 'text-style "color-spec? as #:color" color))
  (unless (text-line-spacing? line-spacing)
    (raise-argument-error 'text-style "positive finite real? as #:line-spacing" line-spacing))
  (unless (text-line-alignment? line-alignment)
    (raise-argument-error 'text-style "text-line-alignment? as #:line-alignment" line-alignment))
  (unless (text-horizontal-alignment? horizontal-alignment)
    (raise-argument-error 'text-style "text-horizontal-alignment? as #:horizontal-alignment" horizontal-alignment))
  (unless (text-vertical-alignment? vertical-alignment)
    (raise-argument-error 'text-style "text-vertical-alignment? as #:vertical-alignment" vertical-alignment))
  (unless (or (not treatment) (text-treatment? treatment))
    (raise-argument-error 'text-style "(or/c #f text-treatment?) as #:treatment" treatment))
  (text-style-value checked-face font-family font-size font-style font-weight
                    (normalize-color-spec color 'text-style)
                    line-spacing line-alignment horizontal-alignment vertical-alignment treatment))

(define text-style? text-style-value?)
(define text-style-font-face text-style-value-font-face)
(define text-style-font-family text-style-value-font-family)
(define text-style-font-size text-style-value-font-size)
(define text-style-font-style text-style-value-font-style)
(define text-style-font-weight text-style-value-font-weight)
(define text-style-color text-style-value-color)
(define text-style-line-spacing text-style-value-line-spacing)
(define text-style-line-alignment text-style-value-line-alignment)
(define text-style-horizontal-alignment text-style-value-horizontal-alignment)
(define text-style-vertical-alignment text-style-value-vertical-alignment)
(define text-style-treatment text-style-value-treatment)

;; Uses a private sentinel so #:font-face #f and #:treatment #f mean exactly
;; what they say rather than being mistaken for an omitted update.
(define (text-style-update style
                           #:font-face [font-face unspecified]
                           #:font-family [font-family unspecified]
                           #:font-size [font-size unspecified]
                           #:font-style [font-style unspecified]
                           #:font-weight [font-weight unspecified]
                           #:color [color unspecified]
                           #:line-spacing [line-spacing unspecified]
                           #:line-alignment [line-alignment unspecified]
                           #:horizontal-alignment [horizontal-alignment unspecified]
                           #:vertical-alignment [vertical-alignment unspecified]
                           #:treatment [treatment unspecified])
  (unless (text-style? style)
    (raise-argument-error 'text-style-update "text-style?" style))
  (define (keep proposed prior) (if (eq? proposed unspecified) prior proposed))
  (text-style #:font-face (keep font-face (text-style-font-face style))
              #:font-family (keep font-family (text-style-font-family style))
              #:font-size (keep font-size (text-style-font-size style))
              #:font-style (keep font-style (text-style-font-style style))
              #:font-weight (keep font-weight (text-style-font-weight style))
              #:color (keep color (text-style-color style))
              #:line-spacing (keep line-spacing (text-style-line-spacing style))
              #:line-alignment (keep line-alignment (text-style-line-alignment style))
              #:horizontal-alignment (keep horizontal-alignment (text-style-horizontal-alignment style))
              #:vertical-alignment (keep vertical-alignment (text-style-vertical-alignment style))
              #:treatment (keep treatment (text-style-treatment style))))

(define (check-font-face who face)
  (cond [(not face) #f]
        [(string? face) (string->immutable-string face)]
        [else (raise-argument-error who "(or/c string? #f)" face)]))

;; Text treatment is part of a theme's immutable appearance contract, so every
;; supported paint form must cross a project plan and worker boundary.  Keep
;; this local datum grammar deliberately small and canonical rather than
;; relying on transparent-struct printing.
(define (paint->datum paint)
  (cond
    [(color-spec? paint) `(solid ,(color-spec->datum paint))]
    [(linear-gradient-paint? paint)
     `(linear-gradient
       ,(vec2->datum (linear-gradient-paint-start paint))
       ,(vec2->datum (linear-gradient-paint-end paint))
       ,(stops->datum (linear-gradient-paint-stops paint)))]
    [(radial-gradient-paint? paint)
     `(radial-gradient
       ,(vec2->datum (radial-gradient-paint-focal-center paint))
       ,(radial-gradient-paint-focal-radius paint)
       ,(vec2->datum (radial-gradient-paint-center paint))
       ,(radial-gradient-paint-radius paint)
       ,(stops->datum (radial-gradient-paint-stops paint)))]
    [(checker-pattern-paint? paint)
     `(checker-pattern
       ,(color-spec->datum (checker-pattern-paint-first paint))
       ,(color-spec->datum (checker-pattern-paint-second paint))
       ,(checker-pattern-paint-cell-size paint))]
    [else (raise-arguments-error 'text-style->datum "paint?" "background" paint)]))

(define (datum->paint datum)
  (unless (and (list? datum) (pair? datum))
    (raise-arguments-error 'datum->text-style "a treatment paint datum" "datum" datum))
  (case (car datum)
    [(solid)
     (check-datum-length 'datum->text-style datum 2)
     (datum->color-spec (cadr datum))]
    [(linear-gradient)
     (check-datum-length 'datum->text-style datum 4)
     (linear-gradient (datum->vec2 (cadr datum))
                      (datum->vec2 (caddr datum))
                      (datum->stops (list-ref datum 3)))]
    [(radial-gradient)
     (check-datum-length 'datum->text-style datum 6)
     (radial-gradient (datum->vec2 (list-ref datum 3))
                      (list-ref datum 4)
                      (datum->stops (list-ref datum 5))
                      #:focal-center (datum->vec2 (list-ref datum 1))
                      #:focal-radius (list-ref datum 2))]
    [(checker-pattern)
     (check-datum-length 'datum->text-style datum 4)
     (checker-pattern (datum->color-spec (cadr datum))
                      (datum->color-spec (caddr datum))
                      #:cell-size (list-ref datum 3))]
    [else (raise-arguments-error 'datum->text-style
                                  "a supported treatment paint datum"
                                  "datum" datum)]))

(define (vec2->datum point) (list (vec2-x point) (vec2-y point)))

(define (datum->vec2 datum)
  (unless (and (list? datum) (= (length datum) 2)
               (finite-real? (car datum)) (finite-real? (cadr datum)))
    (raise-arguments-error 'datum->text-style "a (list finite-real? finite-real?) point"
                           "datum" datum))
  (vec2 (car datum) (cadr datum)))

(define (stops->datum stops)
  (for/list ([stop (in-list stops)])
    (list (paint-stop-offset stop) (color-spec->datum (paint-stop-color stop)))))

(define (datum->stops datum)
  (unless (list? datum)
    (raise-arguments-error 'datum->text-style "a list of paint stop data" "datum" datum))
  (for/list ([entry (in-list datum)])
    (unless (and (list? entry) (= (length entry) 2))
      (raise-arguments-error 'datum->text-style "a (offset color-datum) paint stop"
                             "datum" entry))
    (paint-stop (car entry) (datum->color-spec (cadr entry)))))

(define (check-datum-length who datum expected)
  (unless (= (length datum) expected)
    (raise-arguments-error who "a treatment paint datum with the expected arity"
                           "datum" datum)))

(define (treatment->datum treatment)
  (and treatment
       `(text-treatment
         ,(and (text-treatment-background treatment)
               (paint->datum (text-treatment-background treatment)))
         ,(and (text-treatment-border-color treatment)
               (color-spec->datum (text-treatment-border-color treatment)))
         ,(text-treatment-border-width treatment)
         ,(text-treatment-padding-x treatment)
         ,(text-treatment-padding-y treatment))))

(define (datum->treatment datum)
  (cond [(not datum) #f]
        [(and (list? datum) (= (length datum) 6) (eq? (car datum) 'text-treatment))
         (text-treatment #:background (and (cadr datum) (datum->paint (cadr datum)))
                         #:border-color (and (caddr datum) (datum->color-spec (caddr datum)))
                         #:border-width (list-ref datum 3)
                         #:padding-x (list-ref datum 4)
                         #:padding-y (list-ref datum 5))]
        [else (raise-arguments-error 'datum->text-style
                                      "#f or a text-treatment datum"
                                      "datum" datum)]))

(define (text-style->datum style)
  (unless (text-style? style)
    (raise-argument-error 'text-style->datum "text-style?" style))
  `(text-style
    ,(text-style-font-face style)
    ,(text-style-font-family style)
    ,(text-style-font-size style)
    ,(text-style-font-style style)
    ,(text-style-font-weight style)
    ,(color-spec->datum (text-style-color style))
    ,(text-style-line-spacing style)
    ,(text-style-line-alignment style)
    ,(text-style-horizontal-alignment style)
    ,(text-style-vertical-alignment style)
    ,(treatment->datum (text-style-treatment style))))

(define (datum->text-style datum)
  (unless (and (list? datum) (= (length datum) 12) (eq? (car datum) 'text-style))
    (raise-arguments-error 'datum->text-style "a complete text-style datum" "datum" datum))
  (text-style #:font-face (list-ref datum 1)
              #:font-family (list-ref datum 2)
              #:font-size (list-ref datum 3)
              #:font-style (list-ref datum 4)
              #:font-weight (list-ref datum 5)
              #:color (datum->color-spec (list-ref datum 6))
              #:line-spacing (list-ref datum 7)
              #:line-alignment (list-ref datum 8)
              #:horizontal-alignment (list-ref datum 9)
              #:vertical-alignment (list-ref datum 10)
              #:treatment (datum->treatment (list-ref datum 11))))
