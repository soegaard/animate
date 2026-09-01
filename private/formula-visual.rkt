#lang racket/base

;;;
;;; Formula Visual Model
;;;

;; Defines immutable semantic LaTeX formula Visuals and their typesetting
;; options.
;;
;; This module contains no Pict, drawing-context, bitmap, filesystem, process,
;; browser, or JavaScript dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "affine-transform.rkt"
         "geometry.rkt"
         (only-in "text-visual.rkt"
                  text-horizontal-alignment?
                  text-vertical-alignment?)
         "visual-model.rkt")

;; Exports
(provide formula-mode?
         latex-option?
         latex-formula
         formula-visual?
         formula-visual-source
         formula-visual-mode
         formula-visual-font-size
         formula-visual-preamble
         formula-visual-document-class-options
         formula-visual-preview-options
         formula-visual-horizontal-alignment
         formula-visual-vertical-alignment
         formula-visual-with-source
         formula-visual-document-font-points

         ;; Composite animation support
         formula-visual-with-id)


;;;
;;; Formula Predicates
;;;

; formula-mode? : any/c -> boolean?
;;   Reports whether value is a supported LaTeX mathematical display mode.
(define (formula-mode? value)
  (and (memq value '(inline display display-environment))
       #t))

; latex-option? : any/c -> boolean?
;;   Reports whether value is a symbol or string accepted as a LaTeX option.
(define (latex-option? value)
  (or (symbol? value)
      (string? value)))


;;;
;;; Data Representation
;;;

(struct formula-visual
  (id
   transform
   opacity
   source
   mode
   font-size
   preamble
   document-class-options
   preview-options
   horizontal-alignment
   vertical-alignment)
  #:transparent
  #:methods gen:visual
  [(define (visual-id visual)
     (formula-visual-id visual))
   (define (visual-position visual)
     (affine-transform-translation
      (formula-visual-transform visual)))
   (define (visual-with-position visual position)
     (unless (vec2? position)
       (raise-argument-error 'visual-with-position "vec2?" position))
     (struct-copy formula-visual visual
                  [transform
                   (affine-transform-with-translation
                    (formula-visual-transform visual)
                    position)]))]
  #:methods gen:affine-visual
  [(define (visual-transform visual)
     (formula-visual-transform visual))
   (define (visual-with-transform visual transform)
     (unless (affine-transform? transform)
       (raise-argument-error
        'visual-with-transform
        "affine-transform?"
        transform))
     (struct-copy formula-visual visual [transform transform]))]
  #:methods gen:opacity-visual
  [(define (visual-opacity visual)
     (formula-visual-opacity visual))
   (define (visual-with-opacity visual opacity)
     (unless (opacity? opacity)
       (raise-argument-error
        'visual-with-opacity
        "finite real in [0, 1]"
        opacity))
     (struct-copy formula-visual visual [opacity opacity]))])

;; formula-visual represents one semantic LaTeX mathematical formula.
;;  - id                      symbol?                     stable Visual identity.
;;  - transform               affine-transform?           placement and deformation.
;;  - opacity                 opacity?                    global rendering opacity.
;;  - source                  immutable-string?           LaTeX formula source.
;;  - mode                    formula-mode?               mathematical display mode.
;;  - font-size               positive finite real?       local size in world units.
;;  - preamble                immutable-string?           additional LaTeX preamble.
;;  - document-class-options  (listof latex-option?)       significant option order.
;;  - preview-options         (listof latex-option?)       significant option order.
;;  - horizontal-alignment    text-horizontal-alignment?  anchor position on x axis.
;;  - vertical-alignment      text-vertical-alignment?    anchor position on y axis.
;;
;; Option ordering is preserved because LaTeX packages can interpret option
;; order. The formula source and option strings are copied into immutable model
;; storage. The model does not contain a typeset Pict or a TeX process result.


;;;
;;; Construction and Immutable Updates
;;;

; latex-formula : string?
;                 #:id symbol?
;                 [#:center vec2?]
;                 [#:rotation finite-real?]
;                 [#:scale scale-factor?]
;                 [#:opacity opacity?]
;                 [#:mode formula-mode?]
;                 [#:font-size positive-real?]
;                 [#:preamble string?]
;                 [#:document-class-options (listof latex-option?)]
;                 [#:preview-options (listof latex-option?)]
;                 [#:horizontal-alignment text-horizontal-alignment?]
;                 [#:vertical-alignment text-vertical-alignment?]
;                 -> formula-visual?
;;   Creates one semantic LaTeX formula with an explicit local anchor.
(define (latex-formula source
                       #:id id
                       #:center [center origin]
                       #:rotation [rotation 0]
                       #:scale [scale 1]
                       #:opacity [opacity 1]
                       #:mode [mode 'display]
                       #:font-size [font-size 1]
                       #:preamble [preamble ""]
                       #:document-class-options
                       [document-class-options '()]
                       #:preview-options [preview-options '()]
                       #:horizontal-alignment
                       [horizontal-alignment 'center]
                       #:vertical-alignment
                       [vertical-alignment 'center])
  (check-formula-id 'latex-formula id)
  (unless (vec2? center)
    (raise-argument-error 'latex-formula "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'latex-formula "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error
     'latex-formula
     "positive finite real or vec2 with positive components"
     scale))
  (unless (opacity? opacity)
    (raise-argument-error
     'latex-formula
     "finite real in [0, 1]"
     opacity))
  (unless (formula-mode? mode)
    (raise-argument-error 'latex-formula "formula-mode?" mode))
  (check-formula-font-size 'latex-formula font-size)
  (unless (text-horizontal-alignment? horizontal-alignment)
    (raise-argument-error
     'latex-formula
     "text-horizontal-alignment?"
     horizontal-alignment))
  (unless (text-vertical-alignment? vertical-alignment)
    (raise-argument-error
     'latex-formula
     "text-vertical-alignment?"
     vertical-alignment))
  (define checked-document-options
    (copy-latex-options
     'latex-formula
     "document-class-options"
     document-class-options))
  (check-document-font-size-options
   'latex-formula
   checked-document-options)
  (formula-visual
   id
   (make-affine-transform #:translation center
                          #:rotation rotation
                          #:scale scale)
   opacity
   (copy-formula-string 'latex-formula "source" source)
   mode
   font-size
   (copy-formula-string 'latex-formula "preamble" preamble)
   checked-document-options
   (copy-latex-options
    'latex-formula
    "preview-options"
    preview-options)
   horizontal-alignment
   vertical-alignment))

; formula-visual-with-id : formula-visual? symbol? -> formula-visual?
;;   Returns visual with its identity replaced for internal composite animation.
(define (formula-visual-with-id visual id)
  (unless (formula-visual? visual)
    (raise-argument-error
     'formula-visual-with-id
     "formula-visual?"
     visual))
  (check-formula-id 'formula-visual-with-id id)
  (struct-copy formula-visual visual [id id]))

; formula-visual-with-source : formula-visual? string? -> formula-visual?
;;   Returns visual with its immutable LaTeX source replaced.
(define (formula-visual-with-source visual source)
  (unless (formula-visual? visual)
    (raise-argument-error
     'formula-visual-with-source
     "formula-visual?"
     visual))
  (struct-copy formula-visual visual
               [source
                (copy-formula-string
                 'formula-visual-with-source
                 "source"
                 source)]))

; formula-visual-document-font-points : formula-visual? -> (or/c 10 11 12)
;;   Returns the standard document base used to calibrate semantic font size.
(define (formula-visual-document-font-points visual)
  (unless (formula-visual? visual)
    (raise-argument-error
     'formula-visual-document-font-points
     "formula-visual?"
     visual))
  (or (for/or ([option
                (in-list
                 (formula-visual-document-class-options visual))])
        (latex-option-font-size option))
      10))


;;;
;;; Validation
;;;

; check-formula-id : symbol? any/c -> void?
;;   Raises an argument error unless id is a symbol.
(define (check-formula-id who id)
  (unless (symbol? id)
    (raise-argument-error who "symbol?" id)))

; check-formula-font-size : symbol? any/c -> void?
;;   Raises an argument error unless size is positive and finite.
(define (check-formula-font-size who size)
  (unless (and (finite-real? size)
               (positive? size))
    (raise-argument-error
     who
     "positive finite real?"
     size)))

; copy-formula-string : symbol? string? any/c -> immutable-string?
;;   Validates and copies one string into immutable formula model storage.
(define (copy-formula-string who field-name source)
  (unless (string? source)
    (raise-arguments-error
     who
     "a formula string field must contain a string"
     field-name source))
  (string->immutable-string source))

; copy-latex-options : symbol? string? any/c -> (listof latex-option?)
;;   Validates and copies a significant ordered LaTeX option list.
(define (copy-latex-options who field-name options)
  (unless (and (list? options)
               (andmap latex-option? options))
    (raise-arguments-error
     who
     "LaTeX options must be a list of symbols or strings"
     field-name options))
  (for/list ([option (in-list options)])
    (if (string? option)
        (string->immutable-string option)
        option)))

; check-document-font-size-options : symbol? (listof latex-option?) -> void?
;;   Rejects conflicting 10pt, 11pt, and 12pt document-class options.
(define (check-document-font-size-options who options)
  (define selected-sizes
    (for/fold ([sizes '()])
              ([option (in-list options)])
      (define size
        (latex-option-font-size option))
      (if (and size
               (not (member size sizes)))
          (cons size sizes)
          sizes)))
  (when (> (length selected-sizes) 1)
    (raise-arguments-error
     who
     "document class options contain conflicting font sizes"
     "document-class-options" options)))

; latex-option-font-size : latex-option? -> (or/c 10 11 12 false/c)
;;   Extracts a standard document-class font size from one option.
(define (latex-option-font-size option)
  (define option-string
    (if (symbol? option)
        (symbol->string option)
        option))
  (cond
    [(string=? option-string "10pt") 10]
    [(string=? option-string "11pt") 11]
    [(string=? option-string "12pt") 12]
    [else #f]))
