#lang racket/base

;;;
;;; Numeric Displays
;;;

;; Creates immutable text Visuals for formatted numeric values and relation
;; parameter displays. A display is recomputed from sampled parameter state;
;; it never mutates a previous string or stores a renderer-specific tracker.


;;;
;;; Imports and Exports

(require racket/list
         racket/string
         "clipped-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "interpolation.rkt"
         "parameter.rkt"
         "path-geometry.rkt"
         "relation-context.rkt"
         "relation-dependency.rkt"
         "relation-spec.rkt"
         "relation-visual.rkt"
         "text-visual.rkt"
         "visual-model.rkt")

(provide numeric-display-anchor?
         numeric-unit?
         unit
         unit-product
         format-unit
         format-integer
         format-decimal
         format-scientific
         format-significant
         format-rational
         format-complex
         integer
         decimal-number
         scientific-number
         significant-number
         rational-number
         complex-number
         numeric-label
         (struct-out parameter-display-relation-spec)
         parameter-display
         rolling-number-display)


;;;
;;; Formatting

;; A numeric unit stores symbolic factors, with an integer power for each. It
;; remains data rather than a renderer-specific superscript effect; the common
;; text backend turns powers into Unicode superscripts at formatting time.
(struct unit-factor (symbol power)
  #:transparent)

(struct numeric-unit (factors)
  #:transparent)

; unit : string? [#:power nonzero-exact-integer?] -> numeric-unit?
;; Creates one upright unit factor. Negative powers give denominator factors.
(define (unit symbol #:power [power 1])
  (check-unit-symbol 'unit symbol)
  (check-unit-power 'unit power)
  (numeric-unit (list (unit-factor symbol power))))

; unit-product : numeric-unit? ... -> numeric-unit?
;; Concatenates typeset unit factors in their declared order.
(define (unit-product . units)
  (for ([value (in-list units)])
    (unless (numeric-unit? value)
      (raise-argument-error 'unit-product "numeric-unit?" value)))
  (numeric-unit (append* (map numeric-unit-factors units))))

; format-unit : (or/c string? numeric-unit?) -> string?
;; Formats a literal string unchanged, or a semantic unit with upright Unicode
;; superscripts, for example `m·s⁻²`.
(define (format-unit value)
  (cond
    [(string? value) value]
    [(numeric-unit? value)
     (string-join
      (for/list ([factor (in-list (numeric-unit-factors value))])
        (string-append (unit-factor-symbol factor)
                       (integer->superscript (unit-factor-power factor))))
      "·")]
    [else
     (raise-argument-error 'format-unit "(or/c string? numeric-unit?)" value)]))

(define (numeric-unit-spec? value)
  (or (string? value) (numeric-unit? value)))

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
  (check-unit-spec 'format-integer unit)
  (string-append
   (sign-prefix value show-sign?)
   (group-digits (number->string (abs value)) grouping?)
   (unit-suffix unit)))

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
  (check-unit-spec 'format-decimal unit)
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
   (unit-suffix unit)))

;; format-scientific : finite-real? ... -> string?
;; Formats a real as a normalized mantissa times a signed decimal exponent.
(define (format-scientific value
                           #:significant-figures [significant-figures 3]
                           #:show-sign? [show-sign? #f]
                           #:unit [unit ""])
  (check-finite-real 'format-scientific value)
  (check-significant-figures 'format-scientific significant-figures)
  (check-boolean 'format-scientific "show-sign?" show-sign?)
  (check-unit-spec 'format-scientific unit)
  (define-values (mantissa exponent)
    (scientific-components (abs value) significant-figures))
  (string-append
   (sign-prefix value show-sign?)
   mantissa
   "e"
   (if (negative? exponent) "-" "+")
   (number->string (abs exponent))
   (unit-suffix unit)))

;; format-significant : finite-real? ... -> string?
;; Keeps a requested number of significant figures, selecting scientific form
;; for very large/small magnitudes unless #:notation requests otherwise.
(define (format-significant value
                            #:significant-figures [significant-figures 3]
                            #:notation [notation 'auto]
                            #:grouping? [grouping? #f]
                            #:show-sign? [show-sign? #f]
                            #:unit [unit ""])
  (check-finite-real 'format-significant value)
  (check-significant-figures 'format-significant significant-figures)
  (unless (memq notation '(auto fixed scientific))
    (raise-argument-error 'format-significant
                          "(or/c 'auto 'fixed 'scientific)" notation))
  (check-boolean 'format-significant "grouping?" grouping?)
  (check-boolean 'format-significant "show-sign?" show-sign?)
  (check-unit-spec 'format-significant unit)
  (define exponent (decimal-exponent (abs value)))
  (define use-scientific?
    (or (eq? notation 'scientific)
        (and (eq? notation 'auto)
             (or (>= exponent significant-figures)
                 (< exponent -3)))))
  (if use-scientific?
      (format-scientific value
                         #:significant-figures significant-figures
                         #:show-sign? show-sign?
                         #:unit unit)
      (let* ([rounding-exponent (- exponent significant-figures -1)]
             [rounding-place (expt 10 rounding-exponent)]
             [rounded (* (round (/ value rounding-place)) rounding-place)]
             [decimal-places (max 0 (- significant-figures 1 exponent))])
        (format-decimal rounded
                        #:decimal-places decimal-places
                        #:grouping? grouping?
                        #:show-sign? show-sign?
                        #:unit unit))))

;; format-rational : finite-real? ... -> string?
;; Uses the closest fraction with a bounded positive denominator, which keeps
;; animated inexact samples legible instead of exposing binary float ratios.
(define (format-rational value
                         #:max-denominator [max-denominator 1000]
                         #:mixed? [mixed? #f]
                         #:show-sign? [show-sign? #f]
                         #:unit [unit ""])
  (check-finite-real 'format-rational value)
  (check-positive-exact-integer 'format-rational "max-denominator" max-denominator)
  (check-boolean 'format-rational "mixed?" mixed?)
  (check-boolean 'format-rational "show-sign?" show-sign?)
  (check-unit-spec 'format-rational unit)
  (define-values (numerator denominator)
    (closest-rational-components (abs value) max-denominator))
  (define body
    (cond
      [(= denominator 1) (number->string numerator)]
      [mixed?
       (define-values (whole remainder) (quotient/remainder numerator denominator))
       (if (zero? whole)
           (format "~a/~a" remainder denominator)
           (format "~a ~a/~a" whole remainder denominator))]
      [else (format "~a/~a" numerator denominator)]))
  (string-append (sign-prefix value show-sign?) body (unit-suffix unit)))

;; format-complex : finite-number? ... -> string?
;; Formats cartesian complex components with one explicit binary sign.
(define (format-complex value
                        #:decimal-places [decimal-places 2]
                        #:grouping? [grouping? #f]
                        #:show-sign? [show-sign? #f]
                        #:imaginary-unit [imaginary-unit "i"]
                        #:unit [unit ""])
  (check-finite-number 'format-complex value)
  (check-decimal-places 'format-complex decimal-places)
  (check-boolean 'format-complex "grouping?" grouping?)
  (check-boolean 'format-complex "show-sign?" show-sign?)
  (check-string 'format-complex "imaginary-unit" imaginary-unit)
  (check-unit-spec 'format-complex unit)
  (define real (real-part value))
  (define imaginary (imag-part value))
  (string-append
   (format-decimal real #:decimal-places decimal-places #:grouping? grouping?
                   #:show-sign? show-sign?)
   (if (negative? imaginary) " - " " + ")
   (format-decimal (abs imaginary) #:decimal-places decimal-places
                   #:grouping? grouping? #:show-sign? #f)
   imaginary-unit
   (unit-suffix unit)))


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

;; scientific-number : finite-real? #:id symbol? ... -> text-visual?
;; Creates a fixed scientific-notation numeric label.
(define (scientific-number value
                           #:id id
                           #:center [center origin]
                           #:font-size [font-size 1/2]
                           #:font-family [font-family 'default]
                           #:font-style [font-style 'normal]
                           #:font-weight [font-weight 'normal]
                           #:color [color "black"]
                           #:horizontal-alignment [horizontal-alignment 'center]
                           #:vertical-alignment [vertical-alignment 'center]
                           #:significant-figures [significant-figures 3]
                           #:show-sign? [show-sign? #f]
                           #:unit [unit ""])
  (numeric-text
   (format-scientific value #:significant-figures significant-figures
                      #:show-sign? show-sign? #:unit unit)
   id center font-size font-family font-style font-weight color
   horizontal-alignment vertical-alignment))

;; significant-number : finite-real? #:id symbol? ... -> text-visual?
;; Creates a fixed significant-figures label with explicit notation policy.
(define (significant-number value
                            #:id id
                            #:center [center origin]
                            #:font-size [font-size 1/2]
                            #:font-family [font-family 'default]
                            #:font-style [font-style 'normal]
                            #:font-weight [font-weight 'normal]
                            #:color [color "black"]
                            #:horizontal-alignment [horizontal-alignment 'center]
                            #:vertical-alignment [vertical-alignment 'center]
                            #:significant-figures [significant-figures 3]
                            #:notation [notation 'auto]
                            #:grouping? [grouping? #f]
                            #:show-sign? [show-sign? #f]
                            #:unit [unit ""])
  (numeric-text
   (format-significant value #:significant-figures significant-figures
                       #:notation notation #:grouping? grouping?
                       #:show-sign? show-sign? #:unit unit)
   id center font-size font-family font-style font-weight color
   horizontal-alignment vertical-alignment))

;; rational-number : finite-real? #:id symbol? ... -> text-visual?
;; Creates a rational approximation label with a deterministic denominator cap.
(define (rational-number value
                         #:id id
                         #:center [center origin]
                         #:font-size [font-size 1/2]
                         #:font-family [font-family 'default]
                         #:font-style [font-style 'normal]
                         #:font-weight [font-weight 'normal]
                         #:color [color "black"]
                         #:horizontal-alignment [horizontal-alignment 'center]
                         #:vertical-alignment [vertical-alignment 'center]
                         #:max-denominator [max-denominator 1000]
                         #:mixed? [mixed? #f]
                         #:show-sign? [show-sign? #f]
                         #:unit [unit ""])
  (numeric-text
   (format-rational value #:max-denominator max-denominator #:mixed? mixed?
                    #:show-sign? show-sign? #:unit unit)
   id center font-size font-family font-style font-weight color
   horizontal-alignment vertical-alignment))

;; complex-number : finite-number? #:id symbol? ... -> text-visual?
;; Creates a cartesian complex-number label.
(define (complex-number value
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
                        #:imaginary-unit [imaginary-unit "i"]
                        #:unit [unit ""])
  (numeric-text
   (format-complex value #:decimal-places decimal-places #:grouping? grouping?
                   #:show-sign? show-sign? #:imaginary-unit imaginary-unit
                   #:unit unit)
   id center font-size font-family font-style font-weight color
   horizontal-alignment vertical-alignment))

;; numeric-label : finite-number? #:id symbol? ... -> text-visual?
;; A convenience that chooses integer, decimal, or complex formatting unless
;; #:kind explicitly selects one of the richer numeric notations.
(define (numeric-label value
                       #:id id
                       #:center [center origin]
                       #:kind [kind 'auto]
                       #:decimal-places [decimal-places 2]
                       #:significant-figures [significant-figures 3]
                       #:notation [notation 'auto]
                       #:max-denominator [max-denominator 1000]
                       #:mixed? [mixed? #f]
                       #:grouping? [grouping? #f]
                       #:show-sign? [show-sign? #f]
                       #:imaginary-unit [imaginary-unit "i"]
                       #:unit [unit ""]
                       #:font-size [font-size 1/2]
                       #:font-family [font-family 'default]
                       #:font-style [font-style 'normal]
                       #:font-weight [font-weight 'normal]
                       #:color [color "black"]
                       #:horizontal-alignment [horizontal-alignment 'center]
                       #:vertical-alignment [vertical-alignment 'center])
  (unless (memq kind '(auto integer decimal scientific significant rational complex))
    (raise-argument-error
     'numeric-label
     "(or/c 'auto 'integer 'decimal 'scientific 'significant 'rational 'complex)"
     kind))
  (define text
    (case kind
      [(auto)
       (cond [(exact-integer? value)
              (format-integer value #:grouping? grouping?
                              #:show-sign? show-sign? #:unit unit)]
             [(finite-real? value)
              (format-decimal value #:decimal-places decimal-places
                              #:grouping? grouping? #:show-sign? show-sign?
                              #:unit unit)]
             [else
              (format-complex value #:decimal-places decimal-places
                              #:grouping? grouping? #:show-sign? show-sign?
                              #:imaginary-unit imaginary-unit #:unit unit)])]
      [(integer)
       (unless (finite-real? value)
         (raise-argument-error 'numeric-label "finite-real? for #:kind 'integer" value))
       (format-integer (inexact->exact (round value)) #:grouping? grouping?
                       #:show-sign? show-sign? #:unit unit)]
      [(decimal)
       (check-finite-real 'numeric-label value)
       (format-decimal value #:decimal-places decimal-places #:grouping? grouping?
                       #:show-sign? show-sign? #:unit unit)]
      [(scientific)
       (check-finite-real 'numeric-label value)
       (format-scientific value #:significant-figures significant-figures
                          #:show-sign? show-sign? #:unit unit)]
      [(significant)
       (check-finite-real 'numeric-label value)
       (format-significant value #:significant-figures significant-figures
                           #:notation notation #:grouping? grouping?
                           #:show-sign? show-sign? #:unit unit)]
      [(rational)
       (check-finite-real 'numeric-label value)
       (format-rational value #:max-denominator max-denominator #:mixed? mixed?
                        #:show-sign? show-sign? #:unit unit)]
      [(complex)
       (format-complex value #:decimal-places decimal-places #:grouping? grouping?
                       #:show-sign? show-sign? #:imaginary-unit imaginary-unit
                       #:unit unit)]))
  (numeric-text text id center font-size font-family font-style font-weight color
                horizontal-alignment vertical-alignment))


;;;
;;; Parameter Display

;; A transparent built-in relation specification replaces the former resolver
;; closure.  It records only durable formatting data, so relation inspection
;; and cache identity do not have to treat parameter displays as opaque
;; procedures.
(struct parameter-display-relation-spec
  (source-id kind decimal-places significant-figures notation max-denominator
             mixed? grouping? show-sign? imaginary-unit unit anchor font-size
             font-family font-style font-weight color vertical-alignment)
  #:transparent
  #:methods gen:relation-spec
  [(define (resolve-relation-spec spec context template)
     (parameter-display-spec-build
      spec
      (relation-context-value-ref
       context
       (parameter-display-relation-spec-source-id spec))
      (visual-id template)
      (visual-position template)))])

(define (parameter-display-spec-format-value spec value)
  (define source-id (parameter-display-relation-spec-source-id spec))
  (define kind (parameter-display-relation-spec-kind spec))
  (define decimal-places (parameter-display-relation-spec-decimal-places spec))
  (define significant-figures
    (parameter-display-relation-spec-significant-figures spec))
  (define notation (parameter-display-relation-spec-notation spec))
  (define max-denominator (parameter-display-relation-spec-max-denominator spec))
  (define mixed? (parameter-display-relation-spec-mixed? spec))
  (define grouping? (parameter-display-relation-spec-grouping? spec))
  (define show-sign? (parameter-display-relation-spec-show-sign? spec))
  (define imaginary-unit (parameter-display-relation-spec-imaginary-unit spec))
  (define unit (parameter-display-relation-spec-unit spec))
  (case kind
    [(integer)
     (check-display-real-value 'parameter-display source-id kind value)
     (format-integer (inexact->exact (round value)) #:grouping? grouping?
                     #:show-sign? show-sign? #:unit unit)]
    [(decimal)
     (check-display-real-value 'parameter-display source-id kind value)
     (format-decimal value #:decimal-places decimal-places
                     #:grouping? grouping?
                     #:show-sign? show-sign? #:unit unit)]
    [(scientific)
     (check-display-real-value 'parameter-display source-id kind value)
     (format-scientific value #:significant-figures significant-figures
                        #:show-sign? show-sign? #:unit unit)]
    [(significant)
     (check-display-real-value 'parameter-display source-id kind value)
     (format-significant value #:significant-figures significant-figures
                         #:notation notation #:grouping? grouping?
                         #:show-sign? show-sign? #:unit unit)]
    [(rational)
     (check-display-real-value 'parameter-display source-id kind value)
     (format-rational value #:max-denominator max-denominator #:mixed? mixed?
                      #:show-sign? show-sign? #:unit unit)]
    [(complex)
     (unless (finite-number? value)
       (raise-arguments-error
        'parameter-display
        "a complex display requires its parameter to hold a finite real or complex value"
        "parameter-id" source-id
        "value" value))
     (format-complex value #:decimal-places decimal-places
                     #:grouping? grouping? #:show-sign? show-sign?
                     #:imaginary-unit imaginary-unit #:unit unit)]))

(define (parameter-display-spec-build spec value id center)
  (define kind (parameter-display-relation-spec-kind spec))
  (define anchor (parameter-display-relation-spec-anchor spec))
  (define font-size (parameter-display-relation-spec-font-size spec))
  (define font-family (parameter-display-relation-spec-font-family spec))
  (define font-style (parameter-display-relation-spec-font-style spec))
  (define font-weight (parameter-display-relation-spec-font-weight spec))
  (define color (parameter-display-relation-spec-color spec))
  (define vertical-alignment
    (parameter-display-relation-spec-vertical-alignment spec))
  (define text (parameter-display-spec-format-value spec value))
  (if (and (eq? anchor 'decimal)
           (memq kind '(decimal significant scientific)))
      (make-decimal-anchored-display
       text id center font-size font-family font-style font-weight color
       vertical-alignment)
      (numeric-text
       text id center font-size font-family font-style font-weight color
       (case anchor
         [(left sign) 'left]
         [(center) 'center]
         [(right) 'right])
       vertical-alignment)))

;; parameter-display : parameter #:id symbol? ... -> relation-visual?
;; The anchor controls the stable side of the changing text. `decimal` builds
;; two aligned pieces around a fixed decimal point; `sign` always emits a sign
;; and fixes its left edge.
(define (parameter-display source
                           #:id id
                           #:center [center origin]
                           #:kind [kind 'decimal]
                           #:decimal-places [decimal-places 2]
                           #:significant-figures [significant-figures 3]
                           #:notation [notation 'auto]
                           #:max-denominator [max-denominator 1000]
                           #:mixed? [mixed? #f]
                           #:grouping? [grouping? #f]
                           #:show-sign? [show-sign? #f]
                           #:imaginary-unit [imaginary-unit "i"]
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
  (unless (memq kind '(integer decimal scientific significant rational complex))
    (raise-argument-error
     'parameter-display
     "(or/c 'integer 'decimal 'scientific 'significant 'rational 'complex)"
     kind))
  (check-decimal-places 'parameter-display decimal-places)
  (check-significant-figures 'parameter-display significant-figures)
  (unless (memq notation '(auto fixed scientific))
    (raise-argument-error 'parameter-display
                          "(or/c 'auto 'fixed 'scientific)" notation))
  (check-positive-exact-integer 'parameter-display "max-denominator" max-denominator)
  (check-boolean 'parameter-display "mixed?" mixed?)
  (check-boolean 'parameter-display "grouping?" grouping?)
  (check-boolean 'parameter-display "show-sign?" show-sign?)
  (check-string 'parameter-display "imaginary-unit" imaginary-unit)
  (check-unit-spec 'parameter-display unit)
  (unless (numeric-display-anchor? anchor)
    (raise-argument-error 'parameter-display "numeric-display-anchor?" anchor))
  (define spec
    (parameter-display-relation-spec
     source-id kind decimal-places significant-figures notation max-denominator
     mixed? grouping? (or show-sign? (eq? anchor 'sign)) imaginary-unit unit
     anchor font-size font-family font-style font-weight color
     vertical-alignment))
  ;; The initial template establishes the authored outer placement. During
  ;; relation resolution the same specification rebuilds local content at the
  ;; template's local origin, and the relation envelope reapplies this centre.
  (relation-visual
   (parameter-display-spec-build
    spec (if (eq? kind 'integer) 0 0.0) id center)
   #:depends-on (list (value-dependency source-id))
   #:structure 'fixed
   spec))


;;;
;;; Rolling Digits

;; rolling-number-display : parameter #:id symbol? ... -> relation-visual?
;; Renders fixed digit slots as clipped, vertically rolling digit wheels. The
;; display is evaluated from the scalar value at each requested scene sample;
;; it does not inspect a preceding frame.
(define (rolling-number-display source
                                #:id id
                                #:center [center origin]
                                #:integer-digits [integer-digits 3]
                                #:decimal-places [decimal-places 0]
                                #:show-sign? [show-sign? #f]
                                #:unit [unit ""]
                                #:anchor [anchor 'right]
                                #:font-size [font-size 1/2]
                                #:font-family [font-family 'modern]
                                #:font-style [font-style 'normal]
                                #:font-weight [font-weight 'normal]
                                #:color [color "black"]
                                #:vertical-alignment [vertical-alignment 'center])
  (define source-id (parameter-target-id source 'rolling-number-display))
  (unless (symbol? id)
    (raise-argument-error 'rolling-number-display "symbol?" id))
  (unless (vec2? center)
    (raise-argument-error 'rolling-number-display "vec2?" center))
  (check-positive-exact-integer 'rolling-number-display "integer-digits" integer-digits)
  (check-decimal-places 'rolling-number-display decimal-places)
  (check-boolean 'rolling-number-display "show-sign?" show-sign?)
  (check-unit-spec 'rolling-number-display unit)
  (unless (numeric-display-anchor? anchor)
    (raise-argument-error 'rolling-number-display "numeric-display-anchor?" anchor))
  (unless (and (finite-real? font-size) (positive? font-size))
    (raise-argument-error 'rolling-number-display "positive finite real?" font-size))
  (define effective-show-sign? (or show-sign? (eq? anchor 'sign)))
  ;; The medium/modern default gives digits a regular advance. It is still an
  ;; author-selected font, so the public limitation documents that this is not
  ;; renderer-measured tabular figure layout.
  (define advance (* font-size 3/5))
  (define digit-height (* font-size 6/5))
  (define unit-text (unit-suffix unit))
  (define sign-count (if effective-show-sign? 1 0))
  (define decimal-count (if (positive? decimal-places) 1 0))
  (define slot-count
    (+ sign-count integer-digits decimal-count decimal-places
       (string-length unit-text)))
  (define decimal-index (+ sign-count integer-digits))
  (define anchor-index
    (case anchor
      [(left sign) 0]
      [(center) (/ (sub1 slot-count) 2)]
      [(decimal) decimal-index]
      [(right) (sub1 slot-count)]))
  (define (slot-position index)
    (vec2 (* (- index anchor-index) advance) 0))
  (define (text-at content index suffix)
    (numeric-text content
                  (rolling-child-id id suffix)
                  (slot-position index)
                  font-size font-family font-style font-weight color
                  'center vertical-alignment))
  (define (digit-wheel index place value)
    ;; Decimal literals such as 42.7 are normally inexact.  Their quotient by
    ;; 1/10 can consequently land infinitesimally below 427 at an exact clip
    ;; endpoint, leaving a one-pixel sliver of the preceding digit.  Snap only
    ;; machine-noise-near integer phases; ordinary in-between rolling motion is
    ;; left untouched.
    (define quotient (snap-near-integer (/ value place)))
    (define whole (floor quotient))
    (define current (modulo (inexact->exact whole) 10))
    ;; An odometer wheel should be readable through most of a digit interval.
    ;; Let it turn during the last tenth before its next carry instead of
    ;; continuously through the entire interval.  Thus 42.7 displays cleanly
    ;; as 42.7, while the relevant wheel visibly rolls as a carry approaches.
    (define phase (wheel-roll-phase (- quotient whole)))
    (define next (modulo (add1 current) 10))
    (define content
      (group
       (list
        (numeric-text (number->string current)
                      'current origin font-size font-family font-style font-weight color
                      'center vertical-alignment)
        (numeric-text (number->string next)
                      'next (vec2 0 digit-height)
                      font-size font-family font-style font-weight color
                      'center vertical-alignment))
       #:id (rolling-child-id id (string->symbol (format "wheel-content-~a" index)))
       #:center (vec2 0 (* -1 phase digit-height))))
    (clip-visual
     content
     (polygon-path
      (list (vec2 (/ advance -2) (/ digit-height -2))
            (vec2 (/ advance 2) (/ digit-height -2))
            (vec2 (/ advance 2) (/ digit-height 2))
            (vec2 (/ advance -2) (/ digit-height 2))))
     #:id (rolling-child-id id (string->symbol (format "digit-~a" index)))
     #:center (slot-position index)))
  (define (make-display value)
    (unless (and (finite-real? value) (not (negative? value)))
      (raise-arguments-error
       'rolling-number-display
       "a rolling display requires a nonnegative finite real parameter value"
       "parameter-id" source-id
       "value" value))
    (define limit (expt 10 integer-digits))
    (unless (< value limit)
      (raise-arguments-error
       'rolling-number-display
       "a value that fits the declared integer digit slots"
       "parameter-id" source-id
       "value" value
       "integer-digits" integer-digits))
    (define integer-wheels
      (for/list ([offset (in-range integer-digits)])
        (define place (expt 10 (- integer-digits offset 1)))
        (digit-wheel (+ sign-count offset) place value)))
    (define fractional-wheels
      (for/list ([offset (in-range decimal-places)])
        (define place (expt 10 (- (add1 offset))))
        (digit-wheel (+ sign-count integer-digits decimal-count offset)
                     place value)))
    (define static-pieces
      (append
       (if effective-show-sign?
           (list (text-at "+" 0 'sign))
           '())
       (if (positive? decimal-places)
           (list (text-at "." decimal-index 'decimal))
           '())
       (for/list ([character (in-string unit-text)]
                  [index (in-naturals (+ sign-count integer-digits decimal-count))])
         (text-at (string character) index
                  (string->symbol (format "unit-~a" index))))))
    (group (append integer-wheels fractional-wheels static-pieces)
           #:id id #:center center))
  (relation-visual
   (make-display 0)
   #:depends-on (list (value-dependency source-id))
   #:structure 'fixed
   (lambda (context _template)
     (make-display (relation-context-value-ref context source-id)))))


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

(define (rolling-child-id id suffix)
  (string->symbol (format "~a-~a" id suffix)))

(define (string-character-index text character)
  (for/first ([index (in-range (string-length text))]
              #:when (char=? (string-ref text index) character))
    index))

(define (sign-prefix value show-sign?)
  (cond [(negative? value) "-"]
        [show-sign? "+"]
        [else ""]))

(define (unit-suffix value)
  (cond
    ;; Literal units predate semantic units and historically controlled their
    ;; own leading space, such as " m".  Preserve that exact compatibility.
    [(string? value) value]
    [else
     (define rendered (format-unit value))
     (if (string=? rendered "") "" (string-append " " rendered))]))

(define (scientific-components magnitude significant-figures)
  (cond
    [(zero? magnitude)
     (values (format-decimal 0 #:decimal-places (sub1 significant-figures)) 0)]
    [else
     (define initial-exponent (decimal-exponent magnitude))
     (define factor (expt 10 (sub1 significant-figures)))
     (define scaled
       (inexact->exact
        (round (* (/ magnitude (expt 10 initial-exponent)) factor))))
     (define rollover? (>= scaled (* 10 factor)))
     (define exponent (if rollover? (add1 initial-exponent) initial-exponent))
     (define normalized-scaled (if rollover? factor scaled))
     (values
      (format-decimal (/ normalized-scaled factor)
                      #:decimal-places (sub1 significant-figures))
      exponent)]))

(define (decimal-exponent magnitude)
  (cond
    [(zero? magnitude) 0]
    ;; Exact scene values can be much larger than an IEEE double.  Derive the
    ;; decimal order from their numerator and denominator instead of converting
    ;; them through +inf.0 merely to call log.
    [(exact? magnitude)
     (exact-decimal-exponent magnitude)]
    [else
     (inexact->exact
      (floor (/ (log magnitude) (log 10))))]))

(define (exact-decimal-exponent magnitude)
  (define numerator-value (numerator magnitude))
  (define denominator-value (denominator magnitude))
  (define estimated
    (- (sub1 (string-length (number->string numerator-value)))
       (sub1 (string-length (number->string denominator-value)))))
  (if (< magnitude (expt 10 estimated))
      (sub1 estimated)
      estimated))

(define (closest-rational-components magnitude maximum-denominator)
  (cond
    [(zero? magnitude) (values 0 1)]
    [else
     ;; Convert finite flonums to their exact represented value once.  This
     ;; keeps comparison defined even near the largest finite float and avoids
     ;; a temporary +inf.0 when testing candidate denominators.
     (define exact-magnitude
       (if (exact? magnitude) magnitude (inexact->exact magnitude)))
     (define-values (best-numerator best-denominator _best-error)
       (for/fold ([best-numerator 0]
                  [best-denominator 1]
                  [best-error +inf.0])
                 ([denominator (in-range 1 (add1 maximum-denominator))])
         (define numerator
           (round (* exact-magnitude denominator)))
         (define error
           (abs (- exact-magnitude (/ numerator denominator))))
         (if (< error best-error)
             (values numerator denominator error)
             (values best-numerator best-denominator best-error))))
     (define divisor (gcd best-numerator best-denominator))
     (values (/ best-numerator divisor) (/ best-denominator divisor))]))

(define superscript-digits
  (hash #\0 "⁰" #\1 "¹" #\2 "²" #\3 "³" #\4 "⁴"
        #\5 "⁵" #\6 "⁶" #\7 "⁷" #\8 "⁸" #\9 "⁹"))

(define (integer->superscript power)
  (cond
    [(= power 1) ""]
    [else
     (string-append
      (if (negative? power) "⁻" "")
      (apply string-append
             (for/list ([character (in-string (number->string (abs power)))])
               (hash-ref superscript-digits character))))]))

;; snap-near-integer : finite-real? -> finite-real?
;; Eliminates only the IEEE-754 residue adjacent to an intended whole wheel
;; advance.  The tolerance is relative so the rule also works for higher digit
;; slots without perceptibly quantizing a normal counter animation.
(define (snap-near-integer value)
  (define nearest (round value))
  (if (<= (abs (- value nearest))
          (* 1e-10 (max 1 (abs value))))
      nearest
      value))

;; wheel-roll-phase : finite-real? -> unit-real?
;; Maps a digit interval's fractional remainder to a short pre-carry roll.
(define (wheel-roll-phase fraction)
  (define roll-start 9/10)
  (if (<= fraction roll-start)
      0
      (min 1 (/ (- fraction roll-start) (- 1 roll-start)))))

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

(define (check-significant-figures who value)
  (check-positive-exact-integer who "significant-figures" value))

(define (check-positive-exact-integer who field value)
  (unless (and (exact-integer? value) (positive? value))
    (raise-arguments-error who "positive exact integer" field value)))

(define (check-finite-real who value)
  (unless (finite-real? value)
    (raise-argument-error who "finite-real?" value)))

(define (finite-number? value)
  (or (finite-real? value) (finite-complex? value)))

(define (check-finite-number who value)
  (unless (finite-number? value)
    (raise-argument-error who "finite real or finite complex number" value)))

(define (check-display-real-value who source-id kind value)
  (unless (finite-real? value)
    (raise-arguments-error
     who
     "the selected display kind requires its parameter to hold a finite real"
     "parameter-id" source-id
     "kind" kind
     "value" value)))

(define (check-unit-symbol who value)
  (unless (and (string? value) (not (string=? value "")))
    (raise-argument-error who "nonempty string?" value)))

(define (check-unit-power who value)
  (unless (and (exact-integer? value) (not (zero? value)))
    (raise-argument-error who "nonzero exact-integer?" value)))

(define (check-unit-spec who value)
  (unless (numeric-unit-spec? value)
    (raise-argument-error who "(or/c string? numeric-unit?)" value)))

(define (check-boolean who name value)
  (unless (boolean? value)
    (raise-arguments-error who "a boolean value" name value)))

(define (check-string who name value)
  (unless (string? value)
    (raise-arguments-error who "a string value" name value)))
