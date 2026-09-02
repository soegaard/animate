#lang racket/base

;;;
;;; Text Visual Model
;;;

;; Defines immutable semantic plain-text Visuals and their font and alignment
;; data.
;;
;; This module contains no Pict, drawing-context, bitmap, filesystem, process,
;; browser, or JavaScript dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "geometry.rkt"
         "visual-model.rkt")

;; Exports
(provide text-font-family?
         text-font-style?
         text-font-weight?
         text-horizontal-alignment?
         text-vertical-alignment?
         text-span
         text-span?
         text-span-content
         text-span-font-size
         text-span-font-face
         text-span-font-family
         text-span-font-style
         text-span-font-weight
         text-span-color
         plain-text
         paragraph
         rich-text
         text-visual?
         text-visual-content
         text-visual-spans
         text-visual-font-size
         text-visual-font-face
         text-visual-font-family
         text-visual-font-style
         text-visual-font-weight
         text-visual-color
         text-visual-horizontal-alignment
         text-visual-vertical-alignment
         text-visual-width
         text-visual-line-spacing
         text-visual-line-alignment
         text-visual-with-content
         text-visual-with-spans)


;;;
;;; Font and Alignment Predicates
;;;

; text-font-family? : any/c -> boolean?
;;   Reports whether value is a supported portable font-family symbol.
(define (text-font-family? value)
  (and (memq value
             '(default decorative roman script swiss modern symbol system))
       #t))

; text-font-style? : any/c -> boolean?
;;   Reports whether value is a supported font-slant style.
(define (text-font-style? value)
  (and (memq value '(normal italic slant))
       #t))

; text-font-weight? : any/c -> boolean?
;;   Reports whether value is a supported font-weight style.
(define (text-font-weight? value)
  (and (memq value '(normal bold light))
       #t))

; text-horizontal-alignment? : any/c -> boolean?
;;   Reports whether value is a supported horizontal anchor alignment.
(define (text-horizontal-alignment? value)
  (and (memq value '(left center right))
       #t))

; text-vertical-alignment? : any/c -> boolean?
;;   Reports whether value is a supported vertical anchor alignment.
(define (text-vertical-alignment? value)
  (and (memq value '(top center baseline bottom))
       #t))


;;;
;;; Data Representation
;;;

;; text-span carries optional inline overrides. A false value means that the
;; surrounding text Visual supplies the corresponding default. Text content is
;; intentionally allowed to contain explicit line breaks; wrapping itself is a
;; renderer-time measurement because its result depends on camera scale/font
;; metrics.
(struct text-span-data
  (content font-size font-face font-family font-style font-weight color)
  #:transparent
  #:constructor-name make-text-span-data
  #:guard
  (lambda (content font-size font-face font-family font-style font-weight color who)
    (values (check-text-content who content)
            (check-optional-font-size who font-size)
            (check-optional-font-face who font-face)
            (check-optional-font-family who font-family)
            (check-optional-font-style who font-style)
            (check-optional-font-weight who font-weight)
            color)))

; text-span : string? [#:font-size (or/c false/c positive-real?)] ...
;;             -> text-span?
;; Creates one immutable rich inline run. False style values inherit the outer
;; rich-text or paragraph defaults.
(define (text-span content
                   #:font-size [font-size #f]
                   #:font-face [font-face #f]
                   #:font-family [font-family #f]
                   #:font-style [font-style #f]
                   #:font-weight [font-weight #f]
                   #:color [color #f])
  (make-text-span-data content font-size font-face font-family font-style font-weight color))

(define text-span? text-span-data?)
(define text-span-content text-span-data-content)
(define text-span-font-size text-span-data-font-size)
(define text-span-font-face text-span-data-font-face)
(define text-span-font-family text-span-data-font-family)
(define text-span-font-style text-span-data-font-style)
(define text-span-font-weight text-span-data-font-weight)
(define text-span-color text-span-data-color)

(struct text-visual
  (id
   transform
   opacity
   content
   font-size
   font-face
   font-family
   font-style
   font-weight
   color
   horizontal-alignment
   vertical-alignment
   spans
   width
   line-spacing
   line-alignment)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (text-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation
      (text-visual-transform visual)))
   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy text-visual visual
                  [transform
                   (affine-transform-with-translation
                    (text-visual-transform visual)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (text-visual-transform visual))
   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error
        'visual-with-transform
        "affine-transform?"
        transform))
     (struct-copy text-visual visual [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (text-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error
        'visual-with-opacity
        "finite real in [0, 1]"
        opacity))
     (struct-copy text-visual visual [opacity opacity]))])

;; text-visual represents one immutable text/paragraph layout request.
;;  - id                    symbol?                     stable Visual identity.
;;  - transform             affine-transform?           placement and deformation.
;;  - opacity               opacity?                    global rendering opacity.
;;  - content               immutable-string?           concatenated Unicode content.
;;  - font-size             positive finite real?       local size in world units.
;;  - font-face             (or/c immutable-string? #f) preferred platform face.
;;  - font-family           text-font-family?           portable fallback family.
;;  - font-style            text-font-style?            normal, italic, or slant.
;;  - font-weight           text-font-weight?           normal, bold, or light.
;;  - color                 any/c                       opaque adapter color style.
;;  - horizontal-alignment  text-horizontal-alignment?  anchor position on x axis.
;;  - vertical-alignment    text-vertical-alignment?    anchor position on y axis.
;;  - spans                 (listof text-span?)         ordered rich inline content.
;;  - width                 (or/c false/c positive-real?) wrapping width in local units.
;;  - line-spacing          positive-real?              line-advance multiplier.
;;  - line-alignment        text-horizontal-alignment?  alignment of each laid-out line.
;;
;; The text line is laid out in local coordinates before scale and rotation.
;; Alignment determines which point of that untransformed text box is placed at
;; the Visual's reference position.


;;;
;;; Construction and Immutable Updates
;;;

; plain-text : string? #:id symbol? ... -> text-visual?
;;   Creates one compatible one-line plain-text Visual. Use paragraph when
;;   explicit line breaks or a measured wrapping width are wanted.
(define (plain-text content
                    #:id id
                    #:center [center origin]
                    #:rotation [rotation 0]
                    #:scale [scale 1]
                    #:opacity [opacity 1]
                    #:font-size [font-size 1/2]
                    #:font-face [font-face #f]
                    #:font-family [font-family 'default]
                    #:font-style [font-style 'normal]
                    #:font-weight [font-weight 'normal]
                    #:color [color "black"]
                    #:horizontal-alignment [horizontal-alignment 'center]
                    #:vertical-alignment [vertical-alignment 'center])
  (define checked-content
    (check-single-line-text-content 'plain-text content))
  (make-textual-visual
   'plain-text
   (list (inherited-text-span checked-content))
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:font-size font-size #:font-face font-face #:font-family font-family
   #:font-style font-style #:font-weight font-weight #:color color
   #:horizontal-alignment horizontal-alignment #:vertical-alignment vertical-alignment
   #:width #f #:line-spacing 1 #:line-alignment 'left))

; paragraph : string? #:id symbol? ... -> text-visual?
;;   Creates ordinary Unicode text that may contain explicit lines and wrap at
;;   a renderer-measured local width.
(define (paragraph content
                   #:id id
                   #:center [center origin]
                   #:rotation [rotation 0]
                   #:scale [scale 1]
                   #:opacity [opacity 1]
                   #:font-size [font-size 1/2]
                   #:font-face [font-face #f]
                   #:font-family [font-family 'default]
                   #:font-style [font-style 'normal]
                   #:font-weight [font-weight 'normal]
                   #:color [color "black"]
                   #:horizontal-alignment [horizontal-alignment 'center]
                   #:vertical-alignment [vertical-alignment 'center]
                   #:width [width #f]
                   #:line-spacing [line-spacing 1]
                   #:line-alignment [line-alignment 'left])
  (make-textual-visual
   'paragraph
   (list (inherited-text-span content))
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:font-size font-size #:font-face font-face #:font-family font-family
   #:font-style font-style #:font-weight font-weight #:color color
   #:horizontal-alignment horizontal-alignment #:vertical-alignment vertical-alignment
   #:width width #:line-spacing line-spacing #:line-alignment line-alignment))

; rich-text : #:id symbol? ... (or/c string? text-span?) ... -> text-visual?
;;   Creates a text/paragraph Visual with local inline style overrides.
(define (rich-text #:id id
                   #:center [center origin]
                   #:rotation [rotation 0]
                   #:scale [scale 1]
                   #:opacity [opacity 1]
                   #:font-size [font-size 1/2]
                   #:font-face [font-face #f]
                   #:font-family [font-family 'default]
                   #:font-style [font-style 'normal]
                   #:font-weight [font-weight 'normal]
                   #:color [color "black"]
                   #:horizontal-alignment [horizontal-alignment 'center]
                   #:vertical-alignment [vertical-alignment 'center]
                   #:width [width #f]
                   #:line-spacing [line-spacing 1]
                   #:line-alignment [line-alignment 'left]
                   . pieces)
  (make-textual-visual
   'rich-text
   (for/list ([piece (in-list pieces)])
     (text-piece->span 'rich-text piece))
   #:id id #:center center #:rotation rotation #:scale scale #:opacity opacity
   #:font-size font-size #:font-face font-face #:font-family font-family
   #:font-style font-style #:font-weight font-weight #:color color
   #:horizontal-alignment horizontal-alignment #:vertical-alignment vertical-alignment
   #:width width #:line-spacing line-spacing #:line-alignment line-alignment))

;; make-textual-visual : symbol? (listof text-span?) ... -> text-visual?
;; Centralizes validation and immutable storage for one-line, paragraph, and
;; rich constructors so renderer behavior remains exactly the same Visual type.
(define (make-textual-visual who spans
                             #:id id #:center center #:rotation rotation
                             #:scale scale #:opacity opacity #:font-size font-size
                             #:font-face font-face #:font-family font-family
                             #:font-style font-style #:font-weight font-weight
                             #:color color #:horizontal-alignment horizontal-alignment
                             #:vertical-alignment vertical-alignment #:width width
                             #:line-spacing line-spacing #:line-alignment line-alignment)
  (check-text-id who id)
  (unless (vec2? center)
    (raise-argument-error who "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error who "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error
     who "positive finite real or vec2 with positive components" scale))
  (unless (opacity? opacity)
    (raise-argument-error who "finite real in [0, 1]" opacity))
  (check-font-size who font-size)
  (define checked-font-face (check-font-face who font-face))
  (unless (text-font-family? font-family)
    (raise-argument-error who "text-font-family?" font-family))
  (unless (text-font-style? font-style)
    (raise-argument-error who "text-font-style?" font-style))
  (unless (text-font-weight? font-weight)
    (raise-argument-error who "text-font-weight?" font-weight))
  (unless (text-horizontal-alignment? horizontal-alignment)
    (raise-argument-error who "text-horizontal-alignment?" horizontal-alignment))
  (unless (text-vertical-alignment? vertical-alignment)
    (raise-argument-error who "text-vertical-alignment?" vertical-alignment))
  (check-text-width who width)
  (check-line-spacing who line-spacing)
  (unless (text-horizontal-alignment? line-alignment)
    (raise-argument-error who "text-horizontal-alignment?" line-alignment))
  (define checked-spans (check-text-spans who spans))
  (text-visual
   id
   (make-affine-transform #:translation center #:rotation rotation #:scale scale)
   opacity
   (spans->content checked-spans)
   font-size checked-font-face font-family font-style font-weight color
   horizontal-alignment vertical-alignment
   checked-spans width line-spacing line-alignment))

; text-visual-with-content : text-visual? string? -> text-visual?
;; Returns visual with its immutable plain content replaced. The replacement may
;; contain explicit line breaks, which preserves the Visual's layout options.
(define (text-visual-with-content visual content)
  (unless (text-visual? visual)
    (raise-argument-error 'text-visual-with-content "text-visual?" visual))
  (define checked-content (check-text-content 'text-visual-with-content content))
  (struct-copy text-visual visual
               [content checked-content]
               [spans (list (inherited-text-span checked-content))]))

; text-visual-with-spans : text-visual? (listof text-span?) -> text-visual?
;; Returns visual with a new ordered rich inline content list. All layout and
;; outer font properties stay intact.
(define (text-visual-with-spans visual spans)
  (unless (text-visual? visual)
    (raise-argument-error 'text-visual-with-spans "text-visual?" visual))
  (define checked-spans (check-text-spans 'text-visual-with-spans spans))
  (struct-copy text-visual visual
               [content (spans->content checked-spans)]
               [spans checked-spans]))


;;;
;;; Validation
;;;

; check-text-id : symbol? any/c -> void?
;;   Raises an argument error unless id is a symbol.
(define (check-text-id who id)
  (unless (symbol? id)
    (raise-argument-error who "symbol?" id)))

; check-text-content : symbol? any/c -> immutable-string?
;;   Validates and copies text into immutable model storage. Paragraph/rich
;;   content may contain explicit line breaks.
(define (check-text-content who content)
  (unless (string? content)
    (raise-argument-error who "string?" content))
  (string->immutable-string content))

; check-single-line-text-content : symbol? any/c -> immutable-string?
;;   Retains the historic plain-text constructor contract.
(define (check-single-line-text-content who content)
  (define checked-content (check-text-content who content))
  (when (string-contains-line-break? checked-content)
    (raise-arguments-error
     who
     "plain text content must contain exactly one line"
     "content" content))
  checked-content)

; string-contains-line-break? : string? -> boolean?
;;   Reports whether content contains a carriage return or newline.
(define (string-contains-line-break? content)
  (for/or ([character (in-string content)])
    (or (char=? character #\return)
        (char=? character #\newline))))

; check-font-size : symbol? any/c -> void?
;;   Raises an argument error unless size is positive and finite.
(define (check-font-size who size)
  (unless (and (finite-real? size)
               (positive? size))
    (raise-argument-error
     who
     "positive finite real?"
     size)))

; check-optional-font-size : symbol? any/c -> (or/c false/c positive-real?)
(define (check-optional-font-size who size)
  (cond
    [(not size) #f]
    [else
     (check-font-size who size)
     size]))

; check-font-face : symbol? any/c -> (or/c immutable-string? #f)
;;   Validates and copies an optional preferred font face.
(define (check-font-face who face)
  (cond
    [(not face)
     #f]
    [(string? face)
     (string->immutable-string face)]
    [else
     (raise-argument-error
      who
      "(or/c string? #f)"
      face)]))

; check-optional-font-face : symbol? any/c -> (or/c immutable-string? false/c)
(define (check-optional-font-face who face)
  (check-font-face who face))

; check-optional-font-family : symbol? any/c -> (or/c false/c text-font-family?)
(define (check-optional-font-family who family)
  (cond
    [(not family) #f]
    [(text-font-family? family) family]
    [else (raise-argument-error who "text-font-family? or #f" family)]))

; check-optional-font-style : symbol? any/c -> (or/c false/c text-font-style?)
(define (check-optional-font-style who style)
  (cond
    [(not style) #f]
    [(text-font-style? style) style]
    [else (raise-argument-error who "text-font-style? or #f" style)]))

; check-optional-font-weight : symbol? any/c -> (or/c false/c text-font-weight?)
(define (check-optional-font-weight who weight)
  (cond
    [(not weight) #f]
    [(text-font-weight? weight) weight]
    [else (raise-argument-error who "text-font-weight? or #f" weight)]))

; check-text-width : symbol? any/c -> void?
(define (check-text-width who width)
  (unless (or (not width)
              (and (finite-real? width) (positive? width)))
    (raise-argument-error who "positive finite real? or #f" width)))

; check-line-spacing : symbol? any/c -> void?
(define (check-line-spacing who spacing)
  (unless (and (finite-real? spacing) (positive? spacing))
    (raise-argument-error who "positive finite real?" spacing)))

; inherited-text-span : string? -> text-span?
;; Constructs one unstyled run that inherits all outer text-Visual properties.
(define (inherited-text-span content)
  (make-text-span-data content #f #f #f #f #f #f))

; text-piece->span : symbol? (or/c string? text-span?) -> text-span?
(define (text-piece->span who piece)
  (cond
    [(string? piece) (inherited-text-span piece)]
    [(text-span? piece) piece]
    [else (raise-argument-error who "string? or text-span?" piece)]))

; check-text-spans : symbol? any/c -> (listof text-span?)
(define (check-text-spans who spans)
  (unless (list? spans)
    (raise-argument-error who "list?" spans))
  (for/list ([span (in-list spans)])
    (unless (text-span? span)
      (raise-argument-error who "text-span?" span))
    span))

; spans->content : (listof text-span?) -> immutable-string?
(define (spans->content spans)
  (string->immutable-string
   (apply string-append (map text-span-content spans))))
