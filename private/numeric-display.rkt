#lang racket/base

;;;
;;; Numeric Displays
;;;

;; Creates immutable text Visuals for formatted numeric values and derived
;; parameter displays. A display is recomputed from sampled parameter state;
;; it never mutates a previous string or stores a renderer-specific tracker.


;;;
;;; Imports and Exports

(require racket/string
         "derived-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "parameter.rkt"
         "text-visual.rkt")

(provide numeric-display-anchor?
         format-integer
         format-decimal
         integer
         decimal-number
         numeric-label
         parameter-display)


;;;
;;; Formatting

(define (numeric-display-anchor? value)
  (and (memq value '(left center right decimal sign)) #t))

;; format-integer : exact-integer? ... -> string?
(define (format-integer value
                        #:grouping? [grouping? #f]
                        #:show-sign? [show-sign? #f]
                        #:unit [unit ""])
  (unless (exact-integer? value)
    (raise-argument-error 'format-integer "exact-integer?" value))
  (check-boolean 'format-integer "grouping?" grouping?)
  (check-boolean 'format-integer "show-sign?" show-sign?)
  (check-string 'format-integer "unit" unit)
  (string-append
   (sign-prefix value show-sign?)
   (group-digits (number->string (abs value)) grouping?)
   unit))

;; format-decimal : finite-real? ... -> string?
;; Uses a fixed number of fractional places, including trailing zeroes.
(define (format-decimal value
                        #:decimal-places [decimal-places 2]
                        #:grouping? [grouping? #f]
                        #:show-sign? [show-sign? #f]
                        #:unit [unit ""])
  (unless (finite-real? value)
    (raise-argument-error 'format-decimal "finite-real?" value))
  (check-decimal-places 'format-decimal decimal-places)
  (check-boolean 'format-decimal "grouping?" grouping?)
  (check-boolean 'format-decimal "show-sign?" show-sign?)
  (check-string 'format-decimal "unit" unit)
  (define factor (expt 10 decimal-places))
  (define scaled (* (abs value) factor))
  (unless (finite-real? scaled)
    (raise-arguments-error
     'format-decimal
     "the value and decimal precision must have a finite scaled representation"
     "value" value
     "decimal-places" decimal-places))
  (define rounded (inexact->exact (round scaled)))
  (define-values (whole fractional)
    (quotient/remainder rounded factor))
  (string-append
   (sign-prefix value show-sign?)
   (group-digits (number->string whole) grouping?)
   (if (zero? decimal-places)
       ""
       (string-append "."
                      (left-zero-pad (number->string fractional)
                                     decimal-places)))
   unit))


;;;
;;; Static Displays

;; integer : exact-integer? #:id symbol? ... -> text-visual?
(define (integer value
                 #:id id
                 #:center [center origin]
                 #:font-size [font-size 1/2]
                 #:font-family [font-family 'default]
                 #:font-style [font-style 'normal]
                 #:font-weight [font-weight 'normal]
                 #:color [color "black"]
                 #:horizontal-alignment [horizontal-alignment 'center]
                 #:vertical-alignment [vertical-alignment 'center]
                 #:grouping? [grouping? #f]
                 #:show-sign? [show-sign? #f]
                 #:unit [unit ""])
  (numeric-text
   (format-integer value
                   #:grouping? grouping?
                   #:show-sign? show-sign?
                   #:unit unit)
   id center font-size font-family font-style font-weight color
   horizontal-alignment vertical-alignment))

;; decimal-number : finite-real? #:id symbol? ... -> text-visual?
(define (decimal-number value
                        #:id id
                        #:center [center origin]
                        #:font-size [font-size 1/2]
                        #:font-family [font-family 'default]
                        #:font-style [font-style 'normal]
                        #:font-weight [font-weight 'normal]
                        #:color [color "black"]
                        #:horizontal-alignment [horizontal-alignment 'center]
                        #:vertical-alignment [vertical-alignment 'center]
                        #:decimal-places [decimal-places 2]
                        #:grouping? [grouping? #f]
                        #:show-sign? [show-sign? #f]
                        #:unit [unit ""])
  (numeric-text
   (format-decimal value
                   #:decimal-places decimal-places
                   #:grouping? grouping?
                   #:show-sign? show-sign?
                   #:unit unit)
   id center font-size font-family font-style font-weight color
   horizontal-alignment vertical-alignment))

;; numeric-label : finite-real? #:id symbol? ... -> text-visual?
;; A small convenience that chooses an integer rendering for exact integers.
(define (numeric-label value
                       #:id id
                       #:center [center origin]
                       #:decimal-places [decimal-places 2]
                       #:grouping? [grouping? #f]
                       #:show-sign? [show-sign? #f]
                       #:unit [unit ""]
                       #:font-size [font-size 1/2]
                       #:font-family [font-family 'default]
                       #:font-style [font-style 'normal]
                       #:font-weight [font-weight 'normal]
                       #:color [color "black"]
                       #:horizontal-alignment [horizontal-alignment 'center]
                       #:vertical-alignment [vertical-alignment 'center])
  (if (exact-integer? value)
      (integer value #:id id #:center center
               #:font-size font-size #:font-family font-family
               #:font-style font-style #:font-weight font-weight #:color color
               #:horizontal-alignment horizontal-alignment
               #:vertical-alignment vertical-alignment
               #:grouping? grouping? #:show-sign? show-sign? #:unit unit)
      (decimal-number value #:id id #:center center
                      #:font-size font-size #:font-family font-family
                      #:font-style font-style #:font-weight font-weight #:color color
                      #:horizontal-alignment horizontal-alignment
                      #:vertical-alignment vertical-alignment
                      #:decimal-places decimal-places
                      #:grouping? grouping? #:show-sign? show-sign? #:unit unit)))


;;;
;;; Parameter Display

;; parameter-display : parameter #:id symbol? ... -> derived-visual?
;; The anchor controls the stable side of the changing text. `decimal` builds
;; two aligned pieces around a fixed decimal point; `sign` always emits a sign
;; and fixes its left edge.
(define (parameter-display source
                           #:id id
                           #:center [center origin]
                           #:kind [kind 'decimal]
                           #:decimal-places [decimal-places 2]
                           #:grouping? [grouping? #f]
                           #:show-sign? [show-sign? #f]
                           #:unit [unit ""]
                           #:anchor [anchor 'right]
                           #:font-size [font-size 1/2]
                           #:font-family [font-family 'default]
                           #:font-style [font-style 'normal]
                           #:font-weight [font-weight 'normal]
                           #:color [color "black"]
                           #:vertical-alignment [vertical-alignment 'center])
  (define source-id (parameter-target-id source 'parameter-display))
  (unless (symbol? id)
    (raise-argument-error 'parameter-display "symbol?" id))
  (unless (memq kind '(integer decimal))
    (raise-argument-error 'parameter-display "'integer or 'decimal" kind))
  (check-decimal-places 'parameter-display decimal-places)
  (check-boolean 'parameter-display "grouping?" grouping?)
  (check-boolean 'parameter-display "show-sign?" show-sign?)
  (check-string 'parameter-display "unit" unit)
  (unless (numeric-display-anchor? anchor)
    (raise-argument-error 'parameter-display "numeric-display-anchor?" anchor))
  (define effective-show-sign? (or show-sign? (eq? anchor 'sign)))
  (define (format-value value)
    (case kind
      [(integer)
       (unless (finite-real? value)
         (raise-arguments-error
          'parameter-display
          "an integer display requires its parameter to hold a finite real"
          "parameter-id" source-id
          "value" value))
       (format-integer (inexact->exact (round value)) #:grouping? grouping?
                       #:show-sign? effective-show-sign? #:unit unit)]
      [(decimal)
       (unless (finite-real? value)
         (raise-arguments-error
          'parameter-display
          "a decimal display requires its parameter to hold a finite real"
          "parameter-id" source-id
          "value" value))
       (format-decimal value #:decimal-places decimal-places
                       #:grouping? grouping?
                       #:show-sign? effective-show-sign? #:unit unit)]))
  (define (make-display value)
    (if (eq? anchor 'decimal)
        (make-decimal-anchored-display
         (format-value value) id center font-size font-family font-style
         font-weight color vertical-alignment)
        (numeric-text
         (format-value value) id center font-size font-family font-style
         font-weight color
         (case anchor
           [(left sign) 'left]
           [(center) 'center]
           [(right) 'right])
         vertical-alignment)))
  (derived-visual
   (make-display (if (eq? kind 'integer) 0 0.0))
   (lambda (context _template)
     (make-display (derived-context-value-ref context source-id)))))


;;;
;;; Internal Text Construction

(define (numeric-text content id center font-size font-family font-style
                      font-weight color horizontal-alignment vertical-alignment)
  (plain-text content #:id id #:center center #:font-size font-size
              #:font-family font-family #:font-style font-style
              #:font-weight font-weight #:color color
              #:horizontal-alignment horizontal-alignment
              #:vertical-alignment vertical-alignment))

;; Places the leading integer immediately to the left of `center` and the
;; decimal point, fractional digits, and unit immediately to its right. This
;; makes the decimal glyph's origin fixed even when the whole part grows.
(define (make-decimal-anchored-display content id center font-size font-family
                                       font-style font-weight color
                                       vertical-alignment)
  (define decimal-index
    (or (string-character-index content #\.) (string-length content)))
  (define whole (substring content 0 decimal-index))
  (define fractional (substring content decimal-index))
  (cond
    [(= decimal-index (string-length content))
     (numeric-text content id center font-size font-family font-style
                   font-weight color 'right vertical-alignment)]
    [else
     (group
     (list
       (numeric-text whole (numeric-child-id id 'whole) origin font-size
                     font-family font-style font-weight color 'right
                     vertical-alignment)
       (numeric-text fractional (numeric-child-id id 'fraction) origin font-size
                     font-family font-style font-weight color 'left
                     vertical-alignment))
      #:id id #:center center)]))

(define (numeric-child-id id suffix)
  ;; These are nested below the display group, so stable generic names are
  ;; clearer than repeating the parent identity in every path.
  suffix)

(define (string-character-index text character)
  (for/first ([index (in-range (string-length text))]
              #:when (char=? (string-ref text index) character))
    index))

(define (sign-prefix value show-sign?)
  (cond [(negative? value) "-"]
        [show-sign? "+"]
        [else ""]))

(define (group-digits digits grouping?)
  (if (not grouping?)
      digits
      (let loop ([remaining digits] [groups '()])
        (if (<= (string-length remaining) 3)
            (string-join (cons remaining groups) ",")
            (let ([split (- (string-length remaining) 3)])
              (loop (substring remaining 0 split)
                    (cons (substring remaining split) groups)))))))

(define (left-zero-pad value width)
  (string-append (make-string (max 0 (- width (string-length value))) #\0)
                 value))

(define (check-decimal-places who value)
  (unless (and (exact-integer? value) (not (negative? value)))
    (raise-argument-error who "exact-nonnegative-integer?" value)))

(define (check-boolean who name value)
  (unless (boolean? value)
    (raise-arguments-error who "a boolean value" name value)))

(define (check-string who name value)
  (unless (string? value)
    (raise-arguments-error who "a string value" name value)))
