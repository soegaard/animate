#lang racket/base

;; First-class semantic text Scene values.  They retain a style key and
;; authored overrides; concrete text Visuals are made only at render time.

(require racket/list
         "affine-transform.rkt"
         "color-style.rkt"
         "paint.rkt"
         "geometry.rkt"
         "render-typography-context.rkt"
         "text-properties.rkt"
         "text-style.rkt"
         "text-visual.rkt"
         "typography-theme.rkt"
         "visual-model.rkt")

(provide title-text
         subtitle-text
         section-heading-text
         body-text
         caption-text
         label-text
         quotation-text
         code-text
         annotation-text
         styled-text
         styled-rich-text
         semantic-text-visual?
         semantic-text-style-key
         semantic-text-content
         semantic-text-spans
         semantic-text-overrides
         semantic-text-overrides?
         semantic-text-overrides-font-face
         semantic-text-overrides-font-family
         semantic-text-overrides-font-size
         semantic-text-overrides-font-style
         semantic-text-overrides-font-weight
         semantic-text-overrides-color
         semantic-text-overrides-line-spacing
         semantic-text-overrides-line-alignment
         semantic-text-overrides-horizontal-alignment
         semantic-text-overrides-vertical-alignment
         semantic-text-overrides-treatment
         semantic-text-overrides-background
         semantic-text-overrides-border-color
         semantic-text-overrides-border-width
         semantic-text-overrides-padding-x
         semantic-text-overrides-padding-y
         semantic-text-override-inherited?
         semantic-text-visual-width
         semantic-text->text-visual
         resolve-semantic-text-style
         textual-visual?)

;; This marker is stored in immutable Scene data. A prefab value gives it a
;; stable reader representation, unlike a gensym, while keeping inherited
;; distinct from an explicit #f.
(struct semantic-text-inherited () #:prefab)
(define unspecified (semantic-text-inherited))

(struct semantic-text-overrides-value
  (font-face font-family font-size font-style font-weight color line-spacing
             line-alignment horizontal-alignment vertical-alignment treatment
             background border-color border-width padding-x padding-y)
  #:transparent)

(define semantic-text-overrides? semantic-text-overrides-value?)
(define semantic-text-overrides-font-face semantic-text-overrides-value-font-face)
(define semantic-text-overrides-font-family semantic-text-overrides-value-font-family)
(define semantic-text-overrides-font-size semantic-text-overrides-value-font-size)
(define semantic-text-overrides-font-style semantic-text-overrides-value-font-style)
(define semantic-text-overrides-font-weight semantic-text-overrides-value-font-weight)
(define semantic-text-overrides-color semantic-text-overrides-value-color)
(define semantic-text-overrides-line-spacing semantic-text-overrides-value-line-spacing)
(define semantic-text-overrides-line-alignment semantic-text-overrides-value-line-alignment)
(define semantic-text-overrides-horizontal-alignment semantic-text-overrides-value-horizontal-alignment)
(define semantic-text-overrides-vertical-alignment semantic-text-overrides-value-vertical-alignment)
(define semantic-text-overrides-treatment semantic-text-overrides-value-treatment)
(define semantic-text-overrides-background semantic-text-overrides-value-background)
(define semantic-text-overrides-border-color semantic-text-overrides-value-border-color)
(define semantic-text-overrides-border-width semantic-text-overrides-value-border-width)
(define semantic-text-overrides-padding-x semantic-text-overrides-value-padding-x)
(define semantic-text-overrides-padding-y semantic-text-overrides-value-padding-y)

;; The implementation uses a private sentinel rather than #f so callers can
;; explicitly request #f for optional fields such as a treatment.  Inspection
;; clients need only this predicate, never the sentinel itself.
(define (semantic-text-override-inherited? value)
  (semantic-text-inherited? value))

(struct semantic-text-visual
  (id transform opacity style-key content spans overrides width)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual) (semantic-text-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation (semantic-text-visual-transform visual)))
   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy semantic-text-visual visual
                  [transform (affine-transform-with-translation
                              (semantic-text-visual-transform visual) position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual) (semantic-text-visual-transform visual))
   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error 'visual-with-transform "affine-transform?" transform))
     (struct-copy semantic-text-visual visual [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual) (semantic-text-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error 'visual-with-opacity "finite real in [0, 1]" opacity))
     (struct-copy semantic-text-visual visual [opacity opacity]))])

;; Keep the public observation names independent of the representation's
;; struct prefix.  These are deliberately read-only: semantic text is an
;; immutable scene value, just like the concrete text Visual it lowers to.
(define semantic-text-style-key semantic-text-visual-style-key)
(define semantic-text-content semantic-text-visual-content)
(define semantic-text-spans semantic-text-visual-spans)
(define semantic-text-overrides semantic-text-visual-overrides)

(define (portable-style-key? value)
  (and (symbol? value) (symbol-interned? value)
       (positive? (string-length (symbol->string value)))))

(define (styled-text content #:style style-key
                     #:id id #:center [center origin] #:rotation [rotation 0]
                     #:scale [scale 1] #:opacity [opacity 1]
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
                     #:treatment [treatment unspecified]
                     #:background [background unspecified]
                     #:border-color [border-color unspecified]
                     #:border-width [border-width unspecified]
                     #:padding-x [padding-x unspecified]
                     #:padding-y [padding-y unspecified]
                     #:width [width #f])
  (make-semantic-text 'styled-text content (list (text-span content)) style-key
                      #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
                      #:font-face font-face #:font-family font-family #:font-size font-size
                      #:font-style font-style #:font-weight font-weight #:color color
                      #:line-spacing line-spacing #:line-alignment line-alignment
                      #:horizontal-alignment horizontal-alignment
                      #:vertical-alignment vertical-alignment #:treatment treatment
                      #:background background #:border-color border-color
                      #:border-width border-width #:padding-x padding-x #:padding-y padding-y
                      #:width width))

(define (styled-rich-text #:style style-key #:id id
                          #:center [center origin] #:rotation [rotation 0]
                          #:scale [scale 1] #:opacity [opacity 1]
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
                          #:treatment [treatment unspecified]
                          #:background [background unspecified]
                          #:border-color [border-color unspecified]
                          #:border-width [border-width unspecified]
                          #:padding-x [padding-x unspecified]
                          #:padding-y [padding-y unspecified]
                          #:width [width #f]
                          . pieces)
  (define spans
    (for/list ([piece (in-list pieces)])
      (cond [(string? piece) (text-span piece)]
            [(text-span? piece) piece]
            [else (raise-argument-error 'styled-rich-text "string? or text-span?" piece)])))
  (make-semantic-text 'styled-rich-text
                      (apply string-append (map text-span-content spans)) spans style-key
                      #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
                      #:font-face font-face #:font-family font-family #:font-size font-size
                      #:font-style font-style #:font-weight font-weight #:color color
                      #:line-spacing line-spacing #:line-alignment line-alignment
                      #:horizontal-alignment horizontal-alignment
                      #:vertical-alignment vertical-alignment #:treatment treatment
                      #:background background #:border-color border-color
                      #:border-width border-width #:padding-x padding-x #:padding-y padding-y
                      #:width width))

(define (semantic-role-constructor style-key)
  (lambda (content #:id id #:center [center origin] #:rotation [rotation 0]
           #:scale [scale 1] #:opacity [opacity 1]
           #:font-face [font-face unspecified] #:font-family [font-family unspecified]
           #:font-size [font-size unspecified] #:font-style [font-style unspecified]
           #:font-weight [font-weight unspecified] #:color [color unspecified]
           #:line-spacing [line-spacing unspecified] #:line-alignment [line-alignment unspecified]
           #:horizontal-alignment [horizontal-alignment unspecified]
           #:vertical-alignment [vertical-alignment unspecified]
           #:treatment [treatment unspecified]
           #:background [background unspecified]
           #:border-color [border-color unspecified]
           #:border-width [border-width unspecified]
           #:padding-x [padding-x unspecified]
           #:padding-y [padding-y unspecified]
           #:width [width #f])
    (make-semantic-text style-key content (list (text-span content)) style-key
                        #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
                        #:font-face font-face #:font-family font-family #:font-size font-size
                        #:font-style font-style #:font-weight font-weight #:color color
                        #:line-spacing line-spacing #:line-alignment line-alignment
                        #:horizontal-alignment horizontal-alignment
                        #:vertical-alignment vertical-alignment #:treatment treatment
                        #:background background #:border-color border-color
                        #:border-width border-width #:padding-x padding-x #:padding-y padding-y
                        #:width width)))

(define title-text (semantic-role-constructor 'title))
(define subtitle-text (semantic-role-constructor 'subtitle))
(define section-heading-text (semantic-role-constructor 'section-heading))
(define body-text (semantic-role-constructor 'body))
(define caption-text (semantic-role-constructor 'caption))
(define label-text (semantic-role-constructor 'label))
(define quotation-text (semantic-role-constructor 'quotation))
(define code-text (semantic-role-constructor 'code))
(define annotation-text (semantic-role-constructor 'annotation))

(define (make-semantic-text who content spans style-key
                            #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
                            #:font-face font-face #:font-family font-family #:font-size font-size
                            #:font-style font-style #:font-weight font-weight #:color color
                            #:line-spacing line-spacing #:line-alignment line-alignment
                            #:horizontal-alignment horizontal-alignment
                            #:vertical-alignment vertical-alignment #:treatment treatment
                            #:background background #:border-color border-color
                            #:border-width border-width #:padding-x padding-x #:padding-y padding-y
                            #:width width)
  (unless (string? content) (raise-argument-error who "string?" content))
  (unless (symbol? id) (raise-argument-error who "symbol? as #:id" id))
  (unless (portable-style-key? style-key)
    (raise-argument-error who "nonempty interned symbol? as #:style" style-key))
  (unless (vec2? center) (raise-argument-error who "vec2? as #:center" center))
  (unless (finite-real? rotation) (raise-argument-error who "finite real? as #:rotation" rotation))
  (unless (scale-factor? scale) (raise-argument-error who "scale-factor? as #:scale" scale))
  (unless (opacity? opacity) (raise-argument-error who "opacity? as #:opacity" opacity))
  (unless (or (not width) (and (finite-real? width) (positive? width)))
    (raise-argument-error who "positive finite real? or #f as #:width" width))
  (check-overrides who font-face font-family font-size font-style font-weight color
                   line-spacing line-alignment horizontal-alignment vertical-alignment treatment
                   background border-color border-width padding-x padding-y)
  (semantic-text-visual
   id (make-affine-transform #:translation center #:rotation rotation #:scale scale) opacity style-key
   (string->immutable-string content) spans
   (semantic-text-overrides-value font-face font-family font-size font-style font-weight color
                                  line-spacing line-alignment horizontal-alignment vertical-alignment treatment
                                  background border-color border-width padding-x padding-y)
   width))

(define (check-overrides who font-face font-family font-size font-style font-weight color
                         line-spacing line-alignment horizontal vertical treatment
                         background border-color border-width padding-x padding-y)
  (when (and (not (semantic-text-override-inherited? font-face)) font-face (not (string? font-face)))
    (raise-argument-error who "string? or #f as #:font-face" font-face))
  (for ([value (in-list (list font-family font-size font-style font-weight line-spacing line-alignment horizontal vertical))]
        [predicate (in-list (list text-font-family? text-font-size? text-font-style? text-font-weight?
                                  text-line-spacing? text-line-alignment?
                                  text-horizontal-alignment? text-vertical-alignment?))]
        [name (in-list '(font-family font-size font-style font-weight line-spacing line-alignment horizontal-alignment vertical-alignment))])
    (unless (or (semantic-text-override-inherited? value) (predicate value))
      (raise-arguments-error who "a valid explicit typography override" "property" name "value" value)))
  (when (and (not (semantic-text-override-inherited? color)) (not (color-spec? color)))
    (raise-argument-error who "color-spec? as #:color" color))
  (when (and (not (semantic-text-override-inherited? treatment)) treatment (not (text-treatment? treatment)))
    (raise-argument-error who "text-treatment? or #f as #:treatment" treatment))
  (when (and (not (semantic-text-override-inherited? background))
             background
             (not (paint? background)))
    (raise-argument-error who "paint? or #f as #:background" background))
  (when (and (not (semantic-text-override-inherited? border-color))
             border-color
             (not (color-spec? border-color)))
    (raise-argument-error who "color-spec? or #f as #:border-color" border-color))
  (for ([value (in-list (list border-width padding-x padding-y))]
        [name (in-list '(border-width padding-x padding-y))])
    (unless (or (semantic-text-override-inherited? value)
                (and (finite-real? value) (>= value 0)))
      (raise-arguments-error who "a nonnegative finite real treatment override"
                             "property" name "value" value))))

(define (override-or value base)
  (if (semantic-text-override-inherited? value) base value))

(define (resolve-semantic-text-style visual theme)
  (unless (semantic-text-visual? visual)
    (raise-argument-error 'resolve-semantic-text-style "semantic-text-visual?" visual))
  (unless (typography-theme? theme)
    (raise-argument-error 'resolve-semantic-text-style "typography-theme?" theme))
  (define overrides (semantic-text-visual-overrides visual))
  (define base (typography-ref theme (semantic-text-visual-style-key visual)))
  ;; Resolve a complete replacement before its individual refinements. A
  ;; property override on #f begins with a neutral treatment.
  (define replacement-treatment
    (override-or (semantic-text-overrides-treatment overrides)
                 (text-style-treatment base)))
  (define treatment-properties
    (list (semantic-text-overrides-background overrides)
          (semantic-text-overrides-border-color overrides)
          (semantic-text-overrides-border-width overrides)
          (semantic-text-overrides-padding-x overrides)
          (semantic-text-overrides-padding-y overrides)))
  (define resolved-treatment
    (if (ormap (lambda (value) (not (semantic-text-override-inherited? value)))
               treatment-properties)
        (let ([prior (or replacement-treatment (text-treatment))])
          (text-treatment-update
           prior
           #:background
           (override-or (semantic-text-overrides-background overrides)
                        (text-treatment-background prior))
           #:border-color
           (override-or (semantic-text-overrides-border-color overrides)
                        (text-treatment-border-color prior))
           #:border-width
           (override-or (semantic-text-overrides-border-width overrides)
                        (text-treatment-border-width prior))
           #:padding-x
           (override-or (semantic-text-overrides-padding-x overrides)
                        (text-treatment-padding-x prior))
           #:padding-y
           (override-or (semantic-text-overrides-padding-y overrides)
                        (text-treatment-padding-y prior))))
        replacement-treatment))
  (text-style-update
   base
   #:font-face (override-or (semantic-text-overrides-font-face overrides) (text-style-font-face base))
   #:font-family (override-or (semantic-text-overrides-font-family overrides) (text-style-font-family base))
   #:font-size (override-or (semantic-text-overrides-font-size overrides) (text-style-font-size base))
   #:font-style (override-or (semantic-text-overrides-font-style overrides) (text-style-font-style base))
   #:font-weight (override-or (semantic-text-overrides-font-weight overrides) (text-style-font-weight base))
   #:color (override-or (semantic-text-overrides-color overrides) (text-style-color base))
   #:line-spacing (override-or (semantic-text-overrides-line-spacing overrides) (text-style-line-spacing base))
   #:line-alignment (override-or (semantic-text-overrides-line-alignment overrides) (text-style-line-alignment base))
   #:horizontal-alignment (override-or (semantic-text-overrides-horizontal-alignment overrides) (text-style-horizontal-alignment base))
   #:vertical-alignment (override-or (semantic-text-overrides-vertical-alignment overrides) (text-style-vertical-alignment base))
   #:treatment resolved-treatment))

(define (semantic-text->text-visual visual
                                     [typography-context (current-or-default-render-typography-context)])
  (unless (semantic-text-visual? visual)
    (raise-argument-error 'semantic-text->text-visual "semantic-text-visual?" visual))
  (unless (render-typography-context? typography-context)
    (raise-argument-error 'semantic-text->text-visual "render-typography-context?" typography-context))
  (define style (resolve-semantic-text-style visual (render-typography-context-theme typography-context)))
  (apply rich-text
         #:id (semantic-text-visual-id visual)
         #:center (visual-position visual)
         #:rotation (visual-rotation visual)
         #:scale (visual-scale visual)
         #:opacity (visual-opacity visual)
         #:font-size (text-style-font-size style)
         #:font-face (text-style-font-face style)
         #:font-family (text-style-font-family style)
         #:font-style (text-style-font-style style)
         #:font-weight (text-style-font-weight style)
         #:color (text-style-color style)
         #:horizontal-alignment (text-style-horizontal-alignment style)
         #:vertical-alignment (text-style-vertical-alignment style)
         #:width (semantic-text-visual-width visual)
         #:line-spacing (text-style-line-spacing style)
         #:line-alignment (text-style-line-alignment style)
         (semantic-text-visual-spans visual)))

(define (textual-visual? value)
  (or (text-visual? value) (semantic-text-visual? value)))
