#lang racket/base

;;;
;;; SVG Semantic Import
;;;

;; Imports a deliberately useful SVG subset into existing immutable semantic
;; Visuals. Every graphical element becomes a built-in affine Visual, while
;; nested SVG groups become ordinary Visual groups with stable identities.

(require racket/list
         racket/match
         racket/string
         xml
         "affine-transform.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "path-geometry.rkt"
         "visual-model.rkt")

(provide svg->visual
         ;; Internal adapter support: dvisvgm's path data is parsed through the
         ;; same SVG coordinate conversion as ordinary semantic SVG imports.
         svg-path-geometry)

(struct svg-style (fill stroke stroke-width opacity)
  #:transparent)

(define default-svg-style
  (svg-style "black" #f 1 1))

; svg->visual : path-string? #:id symbol?
;               [#:center vec2?] [#:rotation finite-real?]
;               [#:scale scale-factor?] [#:opacity opacity?]
;               -> group-visual?
;; Imports one SVG file as a nested group of ordinary semantic Visuals.
(define (svg->visual source
                     #:id id
                     #:center [center origin]
                     #:rotation [rotation 0]
                     #:scale [scale 1]
                     #:opacity [opacity 1])
  (unless (path-string? source)
    (raise-argument-error 'svg->visual "path-string?" source))
  (unless (symbol? id)
    (raise-argument-error 'svg->visual "symbol?" id))
  (unless (vec2? center)
    (raise-argument-error 'svg->visual "vec2?" center))
  (unless (finite-real? rotation)
    (raise-argument-error 'svg->visual "finite real?" rotation))
  (unless (scale-factor? scale)
    (raise-argument-error
     'svg->visual
     "positive finite real or vec2 with positive components"
     scale))
  (unless (opacity? opacity)
    (raise-argument-error 'svg->visual "finite real in [0, 1]" opacity))
  (define document
    (read-svg-document source))
  (unless (eq? (svg-element-tag document) 'svg)
    (raise-arguments-error
     'svg->visual
     "the document root must be an SVG element"
     "source" source
     "root" (and (pair? document) (car document))))
  (define root-translation
    (svg-transform-translation (svg-element-attributes document)))
  (define children
    (svg-children->visuals
     (svg-element-children document)
     id
     (svg-style-with-attributes default-svg-style
                                (svg-element-attributes document))))
  (group children
         #:id id
         #:center (vec2+ center root-translation)
         #:rotation rotation
         #:scale scale
         #:opacity opacity))

; read-svg-document : path-string? -> xexpr?
(define (read-svg-document source)
  (with-handlers
      ([exn:fail?
        (lambda (exception)
          (raise-arguments-error
           'svg->visual
           "could not read an XML SVG document"
           "source" source
           "exception message" (exn-message exception)))])
    (call-with-input-file
     source
     (lambda (input)
       (xml->xexpr (document-element (read-xml input)))))))


;;;
;;; SVG Tree Conversion
;;;

; svg-children->visuals : list? symbol? svg-style? -> (listof visual?)
(define (svg-children->visuals children parent-id inherited-style)
  (for/list ([child (in-list (svg-element-children-only children))]
             [index (in-naturals)]
             #:do [(define attributes (svg-element-attributes child))]
             #:do [(define child-id
                     (svg-element-id attributes parent-id index))]
             #:do [(define style
                     (svg-style-with-attributes inherited-style attributes))]
             #:when (svg-supported-element? child))
    (svg-element->visual child child-id style)))

; svg-element->visual : xexpr? symbol? svg-style? -> visual?
(define (svg-element->visual element id style)
  (define tag (svg-element-tag element))
  (define attributes (svg-element-attributes element))
  (define raw
    (case tag
      [(g)
       (group
        (svg-children->visuals (svg-element-children element) id style)
        #:id id)]
      [(path)
       (make-path-visual
        (svg-path-geometry (svg-required-attribute attributes 'd))
        #:id id
        #:center origin
        #:opacity (svg-style-opacity style)
        #:fill (svg-style-fill style)
        #:stroke (svg-style-stroke style)
        #:stroke-width (svg-style-stroke-width style))]
      [(line)
       (svg-path-visual
        id style
        (path-geometry
         (list
          (path-subpath
           (svg-point (svg-attribute-number attributes 'x1 0)
                      (svg-attribute-number attributes 'y1 0))
           (list
            (line-path-segment
             (svg-point (svg-attribute-number attributes 'x2 0)
                        (svg-attribute-number attributes 'y2 0))))
           #f))))]
      [(polyline)
       (svg-poly-points-visual id style attributes #f)]
      [(polygon)
       (svg-poly-points-visual id style attributes #t)]
      [(rect)
       (svg-rectangle-visual id style attributes)]
      [(circle)
       (circle #:id id
               #:center
               (svg-point (svg-attribute-number attributes 'cx 0)
                          (svg-attribute-number attributes 'cy 0))
               #:radius (svg-required-positive-number attributes 'r)
               #:opacity (svg-style-opacity style)
               #:fill (svg-style-fill style)
               #:stroke (svg-style-stroke style)
               #:stroke-width (svg-style-stroke-width style))]
      [(ellipse)
       (svg-ellipse-visual id style attributes)]
      [else
       (raise-arguments-error
        'svg->visual
        "unsupported SVG graphical element"
        "tag" tag)]))
  (visual-with-position
   raw
   (vec2+ (visual-position raw)
          (svg-transform-translation attributes))))

; svg-supported-element? : any/c -> boolean?
;; Groups and common geometric SVG leaves are retained; metadata is ignored.
(define (svg-supported-element? element)
  (memq (svg-element-tag element)
        '(g path line polyline polygon rect circle ellipse)))

; svg-element-children-only : list? -> (listof xexpr?)
(define (svg-element-children-only values)
  (filter pair? values))

; svg-element-tag : xexpr? -> symbol?
(define (svg-element-tag element)
  (if (and (pair? element)
           (symbol? (car element)))
      (car element)
      (raise-arguments-error
       'svg->visual
       "an SVG element expression"
       "element" element)))

; svg-element-attributes : xexpr? -> (listof list?)
(define (svg-element-attributes element)
  (define rest (cdr element))
  (if (and (pair? rest)
           (list? (car rest))
           (andmap svg-attribute-entry? (car rest)))
      (car rest)
      '()))

; svg-element-children : xexpr? -> list?
(define (svg-element-children element)
  (define rest (cdr element))
  (if (and (pair? rest)
           (list? (car rest))
           (andmap svg-attribute-entry? (car rest)))
      (cdr rest)
      rest))

; svg-attribute-entry? : any/c -> boolean?
(define (svg-attribute-entry? value)
  (and (pair? value)
       (symbol? (car value))
       (pair? (cdr value))
       (null? (cddr value))))

; svg-element-id : (listof list?) symbol? exact-nonnegative-integer? -> symbol?
(define (svg-element-id attributes parent-id index)
  (define supplied (svg-attribute attributes 'id #f))
  (cond [(and supplied (string? supplied) (not (string=? supplied "")))
         (string->symbol supplied)]
        [else
         (string->symbol
          (format "~a-part-~a" parent-id index))]))


;;;
;;; SVG Style
;;;

; svg-style-with-attributes : svg-style? (listof list?) -> svg-style?
(define (svg-style-with-attributes inherited attributes)
  (define style-attributes
    (svg-inline-style-attributes (svg-attribute attributes 'style #f)))
  (define (property name default)
    (or (svg-attribute attributes name #f)
        (svg-attribute style-attributes name #f)
        default))
  (define fill
    (svg-color-value (property 'fill (svg-style-fill inherited))))
  (define stroke
    (svg-color-value (property 'stroke (svg-style-stroke inherited))))
  (define stroke-width
    (svg-style-number
     'stroke-width
     (property 'stroke-width (svg-style-stroke-width inherited))
     (svg-style-stroke-width inherited)))
  (define local-opacity
    (svg-style-number 'opacity (property 'opacity #f) 1))
  (define combined-opacity
    (* (svg-style-opacity inherited) local-opacity))
  (unless (opacity? combined-opacity)
    (raise-arguments-error 'svg->visual "an SVG opacity in [0, 1]"
                           "opacity" combined-opacity))
  (unless (and (finite-real? stroke-width)
               (not (negative? stroke-width)))
    (raise-arguments-error 'svg->visual "a nonnegative SVG stroke-width"
                           "stroke-width" stroke-width))
  (svg-style fill stroke stroke-width combined-opacity))

; svg-inline-style-attributes : any/c -> (listof list?)
(define (svg-inline-style-attributes value)
  (cond [(not value) '()]
        [(not (string? value))
         (raise-argument-error 'svg->visual "string? style attribute" value)]
        [else
         (for/list ([entry (in-list (string-split value ";"))]
                    #:when (not (string=? (string-trim entry) "")))
           (define pieces (string-split entry ":" #:trim? #t))
           (unless (= (length pieces) 2)
             (raise-arguments-error
              'svg->visual
              "a CSS style declaration of the form name:value"
              "style entry" entry))
           (list (string->symbol (car pieces)) (cadr pieces)))]))

; svg-color-value : any/c -> any/c
(define (svg-color-value value)
  (cond [(or (not value)
             (and (string? value) (string-ci=? value "none"))) #f]
        [else value]))

; svg-style-number : symbol? any/c finite-real? -> finite-real?
(define (svg-style-number name value default)
  (if (not value)
      default
      (svg-number value name)))


;;;
;;; Common Shapes
;;;

; svg-rectangle-visual : symbol? svg-style? (listof list?) -> rectangle-visual?
(define (svg-rectangle-visual id style attributes)
  (define x (svg-attribute-number attributes 'x 0))
  (define y (svg-attribute-number attributes 'y 0))
  (define width (svg-required-positive-number attributes 'width))
  (define height (svg-required-positive-number attributes 'height))
  (rectangle #:id id
             #:center (svg-point (+ x (/ width 2))
                                 (+ y (/ height 2)))
             #:width width
             #:height height
             #:opacity (svg-style-opacity style)
             #:fill (svg-style-fill style)
             #:stroke (svg-style-stroke style)
             #:stroke-width (svg-style-stroke-width style)))

; svg-ellipse-visual : symbol? svg-style? (listof list?) -> path-visual?
(define (svg-ellipse-visual id style attributes)
  (define center
    (svg-point (svg-attribute-number attributes 'cx 0)
               (svg-attribute-number attributes 'cy 0)))
  (define radius-x (svg-required-positive-number attributes 'rx))
  (define radius-y (svg-required-positive-number attributes 'ry))
  ;; Standard cubic circle approximation, expressed after SVG's y inversion.
  (define k 0.5522847498307936)
  (define (point x y) (vec2 (+ (vec2-x center) x) (+ (vec2-y center) y)))
  (svg-path-visual
   id style
   (path-geometry
    (list
     (path-subpath
      (point radius-x 0)
      (list (cubic-bezier-path-segment (point radius-x (* -1 k radius-y))
                                        (point (* k radius-x) (* -1 radius-y))
                                        (point 0 (- radius-y)))
            (cubic-bezier-path-segment (point (* -1 k radius-x) (* -1 radius-y))
                                        (point (- radius-x) (* -1 k radius-y))
                                        (point (- radius-x) 0))
            (cubic-bezier-path-segment (point (- radius-x) (* k radius-y))
                                        (point (* -1 k radius-x) radius-y)
                                        (point 0 radius-y))
            (cubic-bezier-path-segment (point (* k radius-x) radius-y)
                                        (point radius-x (* k radius-y))
                                        (point radius-x 0)))
      #t)))))

; svg-poly-points-visual : symbol? svg-style? (listof list?) boolean? -> path-visual?
(define (svg-poly-points-visual id style attributes closed?)
  (define points
    (svg-point-list (svg-required-attribute attributes 'points)))
  (when (< (length points) (if closed? 3 2))
    (raise-arguments-error
     'svg->visual
     "a polyline needs at least two points and a polygon at least three"
     "points" points))
  (svg-path-visual
   id style
   (path-geometry
    (list
     (path-subpath (car points)
                   (for/list ([point (in-list (cdr points))])
                     (line-path-segment point))
                   closed?)))))

; svg-path-visual : symbol? svg-style? path-geometry? -> path-visual?
(define (svg-path-visual id style geometry)
  (make-path-visual geometry
                    #:id id
                    #:center origin
                    #:opacity (svg-style-opacity style)
                    #:fill (svg-style-fill style)
                    #:stroke (svg-style-stroke style)
                    #:stroke-width (svg-style-stroke-width style)))


;;;
;;; SVG Path Data
;;;

; svg-path-geometry : string? -> path-geometry?
;; Parses M/L/H/V/C/S/Q/Z commands (absolute and relative) into local geometry.
(define (svg-path-geometry source)
  (unless (string? source)
    (raise-argument-error 'svg->visual "string? SVG path data" source))
  (define tokens
    (list->vector
     (regexp-match*
      #px"[A-Za-z]|[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?"
      source)))
  (define token-count (vector-length tokens))
  (define index 0)
  (define command #f)
  (define current origin)
  (define start #f)
  ;; SVG S/s reflects the previous cubic's second control point.  This state is
  ;; deliberately tracked in SVG command terms, rather than after quadratic
  ;; conversion, because a preceding Q/q must not enable a smooth cubic.
  (define previous-cubic-control #f)
  (define reversed-segments '())
  (define reversed-subpaths '())
  (define (at-end?) (>= index token-count))
  (define (command-token? token)
    (and (= (string-length token) 1)
         (char-alphabetic? (string-ref token 0))))
  (define (next-token)
    (if (at-end?)
        (raise-arguments-error 'svg->visual "complete SVG path command data"
                               "path data" source)
        (let ([result (vector-ref tokens index)])
          (set! index (add1 index))
          result)))
  (define (next-number)
    (svg-number (next-token) 'path-data))
  (define (finish-subpath! closed?)
    (when start
      (set! reversed-subpaths
            (cons (path-subpath start (reverse reversed-segments) closed?)
                  reversed-subpaths))
      (set! start #f)
      (set! reversed-segments '())))
  (define (start-subpath! point)
    (finish-subpath! #f)
    (set! start point)
    (set! current point)
    (set! previous-cubic-control #f))
  (define (line-to! point)
    (unless start
      (raise-arguments-error 'svg->visual "a move command before a line command"
                             "path data" source))
    (set! reversed-segments (cons (line-path-segment point) reversed-segments))
    (set! current point)
    (set! previous-cubic-control #f))
  (define (cubic-to! control1 control2 endpoint)
    (unless start
      (raise-arguments-error 'svg->visual "a move command before a curve command"
                             "path data" source))
    (set! reversed-segments
          (cons (cubic-bezier-path-segment control1 control2 endpoint)
                reversed-segments))
    (set! current endpoint)
    (set! previous-cubic-control control2))
  (let loop ()
    (cond
      [(at-end?)
       (finish-subpath! #f)
       (path-geometry (reverse reversed-subpaths))]
      [else
       (define token (vector-ref tokens index))
       (when (command-token? token)
         (set! command (string->symbol token))
         (set! index (add1 index)))
       (unless command
         (raise-arguments-error 'svg->visual "an SVG path command"
                                "path data" source))
       (case command
         [(M m)
          (define x (next-number))
          (define y (next-number))
          (define point
            (if (eq? command 'M)
                (svg-point x y)
                (vec2+ current (svg-displacement x y))))
          (start-subpath! point)
          ;; SVG permits later coordinate pairs after M/m as implicit L/l.
          (set! command (if (eq? command 'M) 'L 'l))]
         [(L l)
          (define x (next-number))
          (define y (next-number))
          (line-to!
           (if (eq? command 'L)
               (svg-point x y)
               (vec2+ current (svg-displacement x y))))]
         [(H h)
          (define x (next-number))
          (line-to!
           (if (eq? command 'H)
               (vec2 x (vec2-y current))
               (vec2 (+ (vec2-x current) x) (vec2-y current))))]
         [(V v)
          (define y (next-number))
          (line-to!
           (if (eq? command 'V)
               (vec2 (vec2-x current) (- y))
               (vec2 (vec2-x current) (- (vec2-y current) y))))]
         [(C c)
          (define x1 (next-number)) (define y1 (next-number))
          (define x2 (next-number)) (define y2 (next-number))
          (define x (next-number)) (define y (next-number))
         (if (eq? command 'C)
              (cubic-to! (svg-point x1 y1) (svg-point x2 y2) (svg-point x y))
              (cubic-to! (vec2+ current (svg-displacement x1 y1))
                         (vec2+ current (svg-displacement x2 y2))
                         (vec2+ current (svg-displacement x y))))]
         [(S s)
          (define x2 (next-number)) (define y2 (next-number))
          (define x (next-number)) (define y (next-number))
          (define control1
            (if previous-cubic-control
                (vec2- (vec2-scale 2 current) previous-cubic-control)
                current))
          (define control2
            (if (eq? command 'S)
                (svg-point x2 y2)
                (vec2+ current (svg-displacement x2 y2))))
          (define endpoint
            (if (eq? command 'S)
                (svg-point x y)
                (vec2+ current (svg-displacement x y))))
          (cubic-to! control1 control2 endpoint)]
         [(Q q)
          (define x1 (next-number)) (define y1 (next-number))
          (define x (next-number)) (define y (next-number))
          (define control
            (if (eq? command 'Q)
                (svg-point x1 y1)
                (vec2+ current (svg-displacement x1 y1))))
          (define endpoint
            (if (eq? command 'Q)
                (svg-point x y)
                (vec2+ current (svg-displacement x y))))
          ;; Exact quadratic-to-cubic conversion in the imported coordinate system.
          (cubic-to! (vec2+ current (vec2-scale 2/3 (vec2- control current)))
                     (vec2+ endpoint (vec2-scale 2/3 (vec2- control endpoint)))
                     endpoint)
          (set! previous-cubic-control #f)]
         [(Z z)
          (unless start
            (raise-arguments-error 'svg->visual "a move command before closepath"
                                   "path data" source))
          (define closing-start start)
          (finish-subpath! #t)
          (set! command #f)
          (set! current closing-start)
          (set! previous-cubic-control #f)]
         [else
          (raise-arguments-error
           'svg->visual
           "SVG path commands M, L, H, V, C, S, Q, and Z"
           "unsupported command" command)])
       (loop)])))


;;;
;;; Attribute and Numeric Helpers
;;;

; svg-attribute : (listof list?) symbol? any/c -> any/c
(define (svg-attribute attributes name default)
  (cond [(assq name attributes) => cadr]
        [else default]))

; svg-required-attribute : (listof list?) symbol? -> string?
(define (svg-required-attribute attributes name)
  (define value (svg-attribute attributes name #f))
  (unless (string? value)
    (raise-arguments-error 'svg->visual "a required string SVG attribute"
                           "attribute" name
                           "value" value))
  value)

; svg-attribute-number : (listof list?) symbol? finite-real? -> finite-real?
(define (svg-attribute-number attributes name default)
  (define value (svg-attribute attributes name #f))
  (if value (svg-number value name) default))

; svg-required-positive-number : (listof list?) symbol? -> positive-real?
(define (svg-required-positive-number attributes name)
  (define value (svg-attribute-number attributes name #f))
  (unless (and (finite-real? value) (positive? value))
    (raise-arguments-error 'svg->visual "a positive finite SVG numeric attribute"
                           "attribute" name
                           "value" value))
  value)

; svg-number : any/c any/c -> finite-real?
(define (svg-number value label)
  (define parsed
    (cond [(finite-real? value) value]
          [(string? value) (string->number value)]
          [else #f]))
  (unless (finite-real? parsed)
    (raise-arguments-error 'svg->visual "a finite unitless SVG number"
                           "attribute or command" label
                           "value" value))
  parsed)

; svg-point-list : string? -> (listof vec2?)
(define (svg-point-list source)
  (define values
    (for/list ([token (in-list (regexp-match*
                                 #px"[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?"
                                 source))])
      (svg-number token 'points)))
  (unless (even? (length values))
    (raise-arguments-error 'svg->visual "an even count of SVG point coordinates"
                           "points" source))
  (let loop ([remaining values] [reversed-points '()])
    (cond [(null? remaining) (reverse reversed-points)]
          [else
           (loop (cddr remaining)
                 (cons (svg-point (car remaining) (cadr remaining))
                       reversed-points))])))

; svg-point : finite-real? finite-real? -> vec2?
;; SVG y coordinates point down; semantic geometry uses y up.
(define (svg-point x y)
  (vec2 x (- y)))

; svg-displacement : finite-real? finite-real? -> vec2?
(define (svg-displacement x y)
  (vec2 x (- y)))

; svg-transform-translation : (listof list?) -> vec2?
;; Supports SVG's common translation transform. More complex transforms must be
;; flattened by an SVG editor before import, preserving explicit semantics.
(define (svg-transform-translation attributes)
  (define transform (svg-attribute attributes 'transform #f))
  (cond [(not transform) origin]
        [(not (string? transform))
         (raise-argument-error 'svg->visual "string? transform attribute" transform)]
        [else
         (define match
           (regexp-match
            #px"^\\s*translate\\s*\\(\\s*([-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?)(?:[ ,]+([-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?))?\\s*\\)\\s*$"
            transform))
         (unless match
           (raise-arguments-error
            'svg->visual
            "a unitless SVG translate(x[, y]) transform; flatten other transforms first"
            "transform" transform))
         (svg-displacement
          (svg-number (cadr match) 'transform)
          (if (caddr match)
              (svg-number (caddr match) 'transform)
              0))]))
