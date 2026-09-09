#lang racket/base

;;;
;;; Color Tokens
;;;

;; Defines immutable references to palette entries and semantic theme roles.
;; This module contains no drawing, GUI, filesystem, process, or theme-state
;; dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/string)

;; Exports
(provide palette-color
         role-color
         series-color
         portable-color-key?
         palette-token?
         palette-token-key
         role-token?
         role-token-key
         series-color?
         series-color-index
         color-token?
         color-token-kind
         color-token-key
         blue-a blue-b blue-c blue-d blue-e
         aqua-a aqua-b aqua-c aqua-d aqua-e
         green-a green-b green-c green-d green-e
         yellow-a yellow-b yellow-c yellow-d yellow-e
         gold-a gold-b gold-c gold-d gold-e
         red-a red-b red-c red-d red-e
         maroon-a maroon-b maroon-c maroon-d maroon-e
         purple-a purple-b purple-c purple-d purple-e
         blue aqua green yellow gold red maroon purple
         gray-a gray-b gray-c gray-d gray-e
         lighter-gray light-gray gray dark-gray darker-gray
         pink light-pink orange light-brown dark-brown gray-brown
         blush peach apricot tan cocoa taupe
         theme-background theme-foreground theme-muted theme-axis theme-grid
         theme-surface theme-surface-edge theme-accent theme-highlight
         theme-selection theme-warning theme-success theme-error)


;;;
;;; Data Representation
;;;

;; A palette-token names an overridable entry in a future immutable palette.
;; A role-token names an overridable semantic role in a future immutable theme.
;; A series-token names a stable zero-based categorical index. Its final
;; canonical index is chosen by the selected immutable theme's ordered series.
(struct palette-token (key) #:transparent)
(struct role-token (key) #:transparent)
(struct series-token (index) #:transparent)


;;;
;;; Validation and Constructors
;;;

;; palette-color : symbol? -> palette-token?
;;   Constructs an immutable palette reference, normalizing documented aliases.
(define (palette-color key)
  (palette-token (canonical-palette-key key 'palette-color)))

;; role-color : symbol? -> role-token?
;;   Constructs an immutable semantic-role reference.
(define (role-color key)
  (unless (portable-color-key? key)
    (raise-argument-error 'role-color "nonempty interned symbol?" key))
  (role-token key))

;; portable-color-key? : any/c -> boolean?
;; Identifies a symbol whose identity and spelling survive a `write`/`read`
;; boundary. Non-interned and unreadable symbols are process-local identities;
;; accepting either in a portable theme/palette key could change or merge a
;; declaration after it is stored or sent to a worker.
(define (portable-color-key? value)
  (and (symbol? value)
       (symbol-interned? value)
       (positive? (string-length (symbol->string value)))))

;; series-color : exact-nonnegative-integer? -> series-color?
;; Constructs a themeable categorical color reference without consulting a
;; mutable "next color" counter. Resolution wraps the index explicitly by the
;; selected theme's nonempty categorical series.
(define (series-color index)
  (unless (exact-nonnegative-integer? index)
    (raise-argument-error 'series-color "exact-nonnegative-integer?" index))
  (series-token index))

;; color-token? : any/c -> boolean?
;;   Reports whether value is a palette or semantic-role reference.
(define (color-token? value)
  (or (palette-token? value) (role-token? value) (series-token? value)))

;; color-token-kind : color-token? -> (or/c 'palette 'role 'series)
;;   Returns the namespace of a color token.
(define (color-token-kind token)
  (cond
    [(palette-token? token) 'palette]
    [(role-token? token) 'role]
    [(series-token? token) 'series]
    [else (raise-argument-error 'color-token-kind "color-token?" token)]))

;; color-token-key : (or/c palette-token? role-token?) -> symbol?
;;   Returns the normalized palette key or exact semantic-role key. Series
;;   tokens use series-color-index instead because their key is numeric.
(define (color-token-key token)
  (cond
    [(palette-token? token) (palette-token-key token)]
    [(role-token? token) (role-token-key token)]
    [else (raise-argument-error 'color-token-key
                                "(or/c palette-token? role-token?)"
                                token)]))

;; series-color? : any/c -> boolean?
;; Reports whether a token names a stable categorical series index.
(define (series-color? value) (series-token? value))

;; series-color-index : series-color? -> exact-nonnegative-integer?
;; Returns the original author-supplied index before theme-specific wraparound.
(define (series-color-index token)
  (unless (series-token? token)
    (raise-argument-error 'series-color-index "series-color?" token))
  (series-token-index token))

;; canonical-palette-key : any/c symbol? -> symbol?
;;   Validates canonical hyphenated palette spelling and normalizes aliases.
(define (canonical-palette-key key who)
  (unless (portable-color-key? key)
    (raise-argument-error who "nonempty interned canonical hyphenated symbol?" key))
  (define spelling (symbol->string key))
  (unless (regexp-match? #px"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$" spelling)
    (raise-arguments-error
     who
     "palette key must be a lowercase canonical hyphenated symbol"
     "key" key))
  (hash-ref palette-key-aliases key key))

;; palette-key-aliases : immutable-hashof symbol? symbol?
;;   Maps documented short and neutral aliases to their canonical palette keys.
(define palette-key-aliases
  (hash 'blue 'blue-c
        'aqua 'aqua-c
        'green 'green-c
        'yellow 'yellow-c
        'gold 'gold-c
        'red 'red-c
        'maroon 'maroon-c
        'purple 'purple-c
        'lighter-gray 'gray-a
        'light-gray 'gray-b
        'gray 'gray-c
        'dark-gray 'gray-d
        'darker-gray 'gray-e))


;;;
;;; Public Palette Catalog
;;;

;; The catalog contains token references only. Numeric swatches are intentionally
;; introduced with immutable palettes in COLOR-B, not in this value-language slice.
(define blue-a (palette-color 'blue-a))
(define blue-b (palette-color 'blue-b))
(define blue-c (palette-color 'blue-c))
(define blue-d (palette-color 'blue-d))
(define blue-e (palette-color 'blue-e))
(define aqua-a (palette-color 'aqua-a))
(define aqua-b (palette-color 'aqua-b))
(define aqua-c (palette-color 'aqua-c))
(define aqua-d (palette-color 'aqua-d))
(define aqua-e (palette-color 'aqua-e))
(define green-a (palette-color 'green-a))
(define green-b (palette-color 'green-b))
(define green-c (palette-color 'green-c))
(define green-d (palette-color 'green-d))
(define green-e (palette-color 'green-e))
(define yellow-a (palette-color 'yellow-a))
(define yellow-b (palette-color 'yellow-b))
(define yellow-c (palette-color 'yellow-c))
(define yellow-d (palette-color 'yellow-d))
(define yellow-e (palette-color 'yellow-e))
(define gold-a (palette-color 'gold-a))
(define gold-b (palette-color 'gold-b))
(define gold-c (palette-color 'gold-c))
(define gold-d (palette-color 'gold-d))
(define gold-e (palette-color 'gold-e))
(define red-a (palette-color 'red-a))
(define red-b (palette-color 'red-b))
(define red-c (palette-color 'red-c))
(define red-d (palette-color 'red-d))
(define red-e (palette-color 'red-e))
(define maroon-a (palette-color 'maroon-a))
(define maroon-b (palette-color 'maroon-b))
(define maroon-c (palette-color 'maroon-c))
(define maroon-d (palette-color 'maroon-d))
(define maroon-e (palette-color 'maroon-e))
(define purple-a (palette-color 'purple-a))
(define purple-b (palette-color 'purple-b))
(define purple-c (palette-color 'purple-c))
(define purple-d (palette-color 'purple-d))
(define purple-e (palette-color 'purple-e))

(define blue blue-c)
(define aqua aqua-c)
(define green green-c)
(define yellow yellow-c)
(define gold gold-c)
(define red red-c)
(define maroon maroon-c)
(define purple purple-c)

(define gray-a (palette-color 'gray-a))
(define gray-b (palette-color 'gray-b))
(define gray-c (palette-color 'gray-c))
(define gray-d (palette-color 'gray-d))
(define gray-e (palette-color 'gray-e))
(define lighter-gray gray-a)
(define light-gray gray-b)
(define gray gray-c)
(define dark-gray gray-d)
(define darker-gray gray-e)

(define pink (palette-color 'pink))
(define light-pink (palette-color 'light-pink))
(define orange (palette-color 'orange))
(define light-brown (palette-color 'light-brown))
(define dark-brown (palette-color 'dark-brown))
(define gray-brown (palette-color 'gray-brown))
(define blush (palette-color 'blush))
(define peach (palette-color 'peach))
(define apricot (palette-color 'apricot))
(define tan (palette-color 'tan))
(define cocoa (palette-color 'cocoa))
(define taupe (palette-color 'taupe))


;;;
;;; Public Semantic Roles
;;;

(define theme-background (role-color 'background))
(define theme-foreground (role-color 'foreground))
(define theme-muted (role-color 'muted))
(define theme-axis (role-color 'axis))
(define theme-grid (role-color 'grid))
(define theme-surface (role-color 'surface))
(define theme-surface-edge (role-color 'surface-edge))
(define theme-accent (role-color 'accent))
(define theme-highlight (role-color 'highlight))
(define theme-selection (role-color 'selection))
(define theme-warning (role-color 'warning))
(define theme-success (role-color 'success))
(define theme-error (role-color 'error))
