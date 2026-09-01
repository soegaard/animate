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
         plain-text
         text-visual?
         text-visual-content
         text-visual-font-size
         text-visual-font-face
         text-visual-font-family
         text-visual-font-style
         text-visual-font-weight
         text-visual-color
         text-visual-horizontal-alignment
         text-visual-vertical-alignment
         text-visual-with-content)


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
   vertical-alignment)
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

;; text-visual represents one line of styled semantic text.
;;  - id                    symbol?                     stable Visual identity.
;;  - transform             affine-transform?           placement and deformation.
;;  - opacity               opacity?                    global rendering opacity.
;;  - content               immutable-string?           one line of Unicode text.
;;  - font-size             positive finite real?       local size in world units.
;;  - font-face             (or/c immutable-string? #f) preferred platform face.
;;  - font-family           text-font-family?           portable fallback family.
;;  - font-style            text-font-style?            normal, italic, or slant.
;;  - font-weight           text-font-weight?           normal, bold, or light.
;;  - color                 any/c                       opaque adapter color style.
;;  - horizontal-alignment  text-horizontal-alignment?  anchor position on x axis.
;;  - vertical-alignment    text-vertical-alignment?    anchor position on y axis.
;;
;; The text line is laid out in local coordinates before scale and rotation.
;; Alignment determines which point of that untransformed text box is placed at
;; the Visual's reference position.


;;;
;;; Construction and Immutable Updates
;;;

; plain-text : string?
;              #:id symbol?
;              [#:center vec2?]
;              [#:rotation finite-real?]
;              [#:scale scale-factor?]
;              [#:opacity opacity?]
;              [#:font-size positive-real?]
;              [#:font-face (or/c string? #f)]
;              [#:font-family text-font-family?]
;              [#:font-style text-font-style?]
;              [#:font-weight text-font-weight?]
;              [#:color any/c]
;              [#:horizontal-alignment text-horizontal-alignment?]
;              [#:vertical-alignment text-vertical-alignment?]
;              -> text-visual?
;;   Creates one semantic line of plain text with an explicit local anchor.
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
                    #:horizontal-alignment
                    [horizontal-alignment 'center]
                    #:vertical-alignment
                    [vertical-alignment 'center])
  (check-text-id 'plain-text id)
  (unless (vec2? center)
    (raise-argument-error 'plain-text "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'plain-text "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error
     'plain-text
     "positive finite real or vec2 with positive components"
     scale))
  (unless (opacity? opacity)
    (raise-argument-error
     'plain-text
     "finite real in [0, 1]"
     opacity))
  (define checked-content
    (check-text-content 'plain-text content))
  (check-font-size 'plain-text font-size)
  (define checked-font-face
    (check-font-face 'plain-text font-face))
  (unless (text-font-family? font-family)
    (raise-argument-error
     'plain-text
     "text-font-family?"
     font-family))
  (unless (text-font-style? font-style)
    (raise-argument-error
     'plain-text
     "text-font-style?"
     font-style))
  (unless (text-font-weight? font-weight)
    (raise-argument-error
     'plain-text
     "text-font-weight?"
     font-weight))
  (unless (text-horizontal-alignment? horizontal-alignment)
    (raise-argument-error
     'plain-text
     "text-horizontal-alignment?"
     horizontal-alignment))
  (unless (text-vertical-alignment? vertical-alignment)
    (raise-argument-error
     'plain-text
     "text-vertical-alignment?"
     vertical-alignment))
  (text-visual
   id
   (make-affine-transform #:translation center
                          #:rotation rotation
                          #:scale scale)
   opacity
   checked-content
   font-size
   checked-font-face
   font-family
   font-style
   font-weight
   color
   horizontal-alignment
   vertical-alignment))

; text-visual-with-content : text-visual? string? -> text-visual?
;;   Returns visual with its immutable single-line content replaced.
(define (text-visual-with-content visual content)
  (unless (text-visual? visual)
    (raise-argument-error
     'text-visual-with-content
     "text-visual?"
     visual))
  (struct-copy text-visual visual
               [content
                (check-text-content
                 'text-visual-with-content
                 content)]))


;;;
;;; Validation
;;;

; check-text-id : symbol? any/c -> void?
;;   Raises an argument error unless id is a symbol.
(define (check-text-id who id)
  (unless (symbol? id)
    (raise-argument-error who "symbol?" id)))

; check-text-content : symbol? any/c -> immutable-string?
;;   Validates and copies one line of text into immutable model storage.
(define (check-text-content who content)
  (unless (string? content)
    (raise-argument-error who "string?" content))
  (when (string-contains-line-break? content)
    (raise-arguments-error
     who
     "plain text content must contain exactly one line"
     "content" content))
  (string->immutable-string content))

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
