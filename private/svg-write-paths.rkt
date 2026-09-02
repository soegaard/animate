#lang racket/base

;;;
;;; SVG Paths for Animated Write
;;;

;; dvisvgm represents glyphs as paths in <defs>, then positions them with
;; <use>.  The general SVG renderer intentionally keeps that implementation
;; detail private.  This adapter expands the vector subset needed for an
;; animated write without asking the renderer to rasterize another frame.

(require racket/list
         racket/string
         xml
         "geometry.rkt"
         "path-geometry.rkt"
         "svg-import.rkt"
         "visual-model.rkt")

(provide svg-string->write-path-visuals)

(struct svg-write-style (fill stroke)
  #:transparent)

(struct svg-matrix (a b c d e f)
  #:transparent)

(define identity-svg-matrix
  (svg-matrix 1 0 0 1 0 0))

;; svg-string->write-path-visuals : string? symbol? positive-real? positive-real?
;;                                  -> (listof path-visual?)
;; Converts every currently visible path in a dvisvgm-style SVG into local,
;; centred world geometry.  `world-per-pict-unit` is supplied by the formula
;; model, so this module remains independent of formula Visuals.
(define (svg-string->write-path-visuals source id world-per-pict-unit)
  (unless (string? source)
    (raise-argument-error 'svg-string->write-path-visuals "string?" source))
  (unless (symbol? id)
    (raise-argument-error 'svg-string->write-path-visuals "symbol?" id))
  (unless (and (finite-real? world-per-pict-unit)
               (positive? world-per-pict-unit))
    (raise-argument-error
     'svg-string->write-path-visuals
     "positive finite real?"
     world-per-pict-unit))
  (define root
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (raise-arguments-error
             'svg-string->write-path-visuals
             "a readable SVG document"
             "exception message" (exn-message exception)))])
      (xml->xexpr
       (document-element
        (read-xml (open-input-string source))))))
  (unless (eq? (svg-tag root) 'svg)
    (raise-argument-error 'svg-string->write-path-visuals "SVG x-expression" root))
  (define root-attributes (svg-attributes root))
  (define-values (width height view-x view-y view-width view-height)
    (svg-dimensions root-attributes))
  (define path-definitions
    (svg-path-definitions root))
  ;; Tagged formulas hide every fragment in a stylesheet, then enable exactly
  ;; one.  Retaining that selection makes the adapter work with the cropped
  ;; snippets stored on tagged-formula fragments.
  (define visible-fragment-id
    (svg-visible-fragment-id source))
  ;; glyph-tex performs the same selection at the <use> leaf level.  Honouring
  ;; both selectors matters here because an outline morph must receive one
  ;; glyph contour, rather than every reusable path from the complete formula.
  (define visible-glyph-id
    (svg-visible-glyph-id source))
  (define emitted-reversed '())
  (define glyph-index 0)
  (define (emit! geometry matrix style)
    (define glyph-id
      (string->symbol (format "~a-write-glyph-~a" id glyph-index)))
    (set! glyph-index (add1 glyph-index))
    (define positioned
      (path-geometry-map-points
       geometry
       (lambda (point)
         ;; `svg-path-geometry` already flips SVG y-down coordinates into
         ;; Animate y-up coordinates.  Transform back for SVG matrix handling,
         ;; then map the SVG viewport to a centred local formula coordinate.
         (define transformed
           (svg-matrix-apply-down
            matrix
            (vec2 (vec2-x point) (- (vec2-y point)))))
         (vec2
          (* world-per-pict-unit
             (- (* (/ width view-width)
                   (- (vec2-x transformed) view-x))
                (/ width 2)))
          (* world-per-pict-unit
             (- (/ height 2)
                (* (/ height view-height)
                   (- (vec2-y transformed) view-y))))))))
    (set! emitted-reversed
          (cons
           (make-path-visual positioned
                             #:id glyph-id
                             #:center origin
                             #:fill (svg-write-style-fill style)
                             #:stroke (svg-write-style-stroke style)
                             #:stroke-width 0)
           emitted-reversed)))
  (define (walk element matrix inherited-style active?)
    (when (pair? element)
      (define tag (svg-tag element))
      (define attributes (svg-attributes element))
      (define node-id (svg-attribute attributes 'id #f))
      (define node-active?
        (and active?
             (or (not visible-fragment-id)
                 (not (and (string? node-id)
                           (string-prefix? node-id "animate-fragment-")))
                 (string=? node-id visible-fragment-id))
             (or (not visible-glyph-id)
                 (not (and (string? node-id)
                           (string-prefix? node-id "animate-glyph-")))
                 (string=? node-id visible-glyph-id))))
      (define style
        (svg-write-style-with-attributes inherited-style attributes))
      (define node-matrix
        (svg-matrix-compose
         matrix
         (svg-transform-matrix
          (svg-attribute attributes 'transform #f))))
      (when node-active?
        (case tag
          [(svg g)
           (for ([child (in-list (svg-children element))])
             (walk child node-matrix style node-active?))]
          [(path)
           (emit!
            (svg-path-geometry
             (svg-required-attribute attributes 'd))
            node-matrix
            style)]
          [(use)
           (define href
             (or (svg-attribute attributes 'href #f)
                 (svg-attribute attributes 'xlink:href #f)))
           (unless (and (string? href)
                        (string-prefix? href "#"))
             (raise-arguments-error
              'svg-string->write-path-visuals
              "a local <use> href"
              "href" href))
           (define referenced
             (hash-ref path-definitions
                       (substring href 1)
                       (lambda ()
                         (raise-arguments-error
                          'svg-string->write-path-visuals
                          "a <use> reference to a defined path"
                          "href" href))))
           (define use-matrix
             (svg-matrix-compose
              node-matrix
              (svg-translate-matrix
               (svg-number (svg-attribute attributes 'x "0") 'x)
               (svg-number (svg-attribute attributes 'y "0") 'y))))
           (emit! (svg-path-geometry
                   (svg-required-attribute
                    (svg-attributes referenced)
                    'd))
                  use-matrix
                  style)]
          [(defs style)
           (void)]
          [else
           ;; dvisvgm can include metadata nodes.  They do not contribute
           ;; paintable geometry to a write animation.
           (void)]))))
  (walk root identity-svg-matrix (svg-write-style "black" #f) #t)
  (reverse emitted-reversed))


;;; SVG Tree Helpers

(define (svg-tag element)
  (if (and (pair? element) (symbol? (car element)))
      (car element)
      (raise-argument-error 'svg-string->write-path-visuals "SVG element" element)))

(define (svg-attributes element)
  (define rest (cdr element))
  (if (and (pair? rest)
           (list? (car rest))
           (andmap svg-attribute-entry? (car rest)))
      (car rest)
      '()))

(define (svg-children element)
  (define rest (cdr element))
  (define raw
    (if (and (pair? rest)
             (list? (car rest))
             (andmap svg-attribute-entry? (car rest)))
        (cdr rest)
        rest))
  (filter pair? raw))

(define (svg-attribute-entry? value)
  (and (pair? value)
       (symbol? (car value))
       (pair? (cdr value))
       (null? (cddr value))))

(define (svg-attribute attributes name default)
  (cond [(assq name attributes) => cadr]
        [else default]))

(define (svg-required-attribute attributes name)
  (define value (svg-attribute attributes name #f))
  (unless (string? value)
    (raise-arguments-error
     'svg-string->write-path-visuals
     "a string SVG attribute"
     "attribute" name
     "value" value))
  value)

(define (svg-path-definitions root)
  (for/fold ([definitions (hash)])
            ([element (in-list (svg-descendants root))]
             #:when (and (eq? (svg-tag element) 'path)
                         (string? (svg-attribute (svg-attributes element) 'id #f))))
    (hash-set definitions
              (svg-attribute (svg-attributes element) 'id #f)
              element)))

(define (svg-descendants root)
  (cons root
        (append-map svg-descendants (svg-children root))))

(define (svg-visible-fragment-id source)
  (define match
    (regexp-match
     #px"#(animate-fragment-[[:alnum:]-]+)\\s*\\{\\s*opacity\\s*:\\s*1"
     source))
  (and match (cadr match)))

(define (svg-visible-glyph-id source)
  (define match
    (regexp-match
     #px"#(animate-glyph-[[:alnum:]-]+)\\s*\\{\\s*opacity\\s*:\\s*1"
     source))
  (and match (cadr match)))


;;; Style Helpers

(define (svg-write-style-with-attributes inherited attributes)
  (define inline
    (svg-inline-style (svg-attribute attributes 'style #f)))
  (define (property name default)
    (or (svg-attribute attributes name #f)
        (svg-attribute inline name #f)
        default))
  (svg-write-style
   (svg-paint-value (property 'fill (svg-write-style-fill inherited)))
   (svg-paint-value (property 'stroke (svg-write-style-stroke inherited)))))

(define (svg-inline-style value)
  (cond [(not value) '()]
        [(not (string? value))
         (raise-argument-error
          'svg-string->write-path-visuals
          "string? SVG style attribute"
          value)]
        [else
         (for/list ([entry (in-list (string-split value ";"))]
                    #:when (not (string=? (string-trim entry) "")))
           (define pieces (string-split entry ":" #:trim? #t))
           (if (= (length pieces) 2)
               (list (string->symbol (car pieces)) (cadr pieces))
               (raise-arguments-error
                'svg-string->write-path-visuals
                "a CSS name:value style declaration"
                "style entry" entry)))]))

(define (svg-paint-value value)
  (cond [(and (string? value) (string-ci=? value "none")) #f]
        [else value]))


;;; SVG Dimensions and Transforms

(define (svg-dimensions attributes)
  (define width (svg-number (svg-required-attribute attributes 'width) 'width))
  (define height (svg-number (svg-required-attribute attributes 'height) 'height))
  (define view-box
    (map (lambda (token) (svg-number token 'viewBox))
         (regexp-match*
          #px"[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?"
          (svg-required-attribute attributes 'viewBox))))
  (unless (= (length view-box) 4)
    (raise-arguments-error
     'svg-string->write-path-visuals
     "a four-number SVG viewBox"
     "viewBox" (svg-attribute attributes 'viewBox #f)))
  (unless (and (positive? width) (positive? height)
               (positive? (list-ref view-box 2))
               (positive? (list-ref view-box 3)))
    (raise-arguments-error
     'svg-string->write-path-visuals
     "positive SVG width, height, and viewBox extent"
     "width" width
     "height" height
     "viewBox" view-box))
  (apply values width height view-box))

(define (svg-number value name)
  (define result
    (cond [(number? value) value]
          [(string? value)
           (or (string->number value)
               (let ([match
                      (regexp-match
                       #px"^\\s*([-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?)"
                       value)])
                 (and match (string->number (cadr match)))))]
          [else #f]))
  (unless (finite-real? result)
    (raise-arguments-error
     'svg-string->write-path-visuals
     "a finite SVG number"
     "attribute" name
     "value" value))
  result)

(define (svg-transform-matrix value)
  (cond [(not value) identity-svg-matrix]
        [(not (string? value))
         (raise-argument-error
          'svg-string->write-path-visuals
          "string? SVG transform"
          value)]
        [else
         (for/fold ([result identity-svg-matrix])
                   ([matched
                     (in-list
                      (regexp-match*
                       #px"[[:alpha:]]+\\s*\\([^)]*\\)"
                       value))])
           (define parts
             (regexp-match #px"^([[:alpha:]]+)\\s*\\(([^)]*)\\)$" matched))
           (unless parts
             (raise-arguments-error
              'svg-string->write-path-visuals
              "a supported SVG transform"
              "transform" value))
           (define name (string-downcase (cadr parts)))
           (define values
             (map (lambda (token) (svg-number token 'transform))
                  (regexp-match*
                   #px"[-+]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][-+]?[0-9]+)?"
                   (caddr parts))))
           (svg-matrix-compose
            result
            (case (string->symbol name)
              [(matrix)
               (unless (= (length values) 6)
                 (raise-arguments-error
                  'svg-string->write-path-visuals
                  "matrix(a b c d e f)"
                  "transform" matched))
               (apply svg-matrix values)]
              [(translate)
               (unless (or (= (length values) 1) (= (length values) 2))
                 (raise-arguments-error
                  'svg-string->write-path-visuals
                  "translate(x [, y])"
                  "transform" matched))
               (svg-translate-matrix (car values)
                                     (if (= (length values) 2)
                                         (cadr values)
                                         0))]
              [(scale)
               (unless (or (= (length values) 1) (= (length values) 2))
                 (raise-arguments-error
                  'svg-string->write-path-visuals
                  "scale(x [, y])"
                  "transform" matched))
               (svg-matrix (car values) 0 0
                           (if (= (length values) 2) (cadr values) (car values))
                           0 0)]
              [else
               (raise-arguments-error
                'svg-string->write-path-visuals
                "SVG matrix, translate, or scale transform"
                "transform" matched)])))]))

(define (svg-translate-matrix x y)
  (svg-matrix 1 0 0 1 x y))

;; compose(outer, inner) applies inner first and outer second.
(define (svg-matrix-compose outer inner)
  (svg-matrix
   (+ (* (svg-matrix-a outer) (svg-matrix-a inner))
      (* (svg-matrix-c outer) (svg-matrix-b inner)))
   (+ (* (svg-matrix-b outer) (svg-matrix-a inner))
      (* (svg-matrix-d outer) (svg-matrix-b inner)))
   (+ (* (svg-matrix-a outer) (svg-matrix-c inner))
      (* (svg-matrix-c outer) (svg-matrix-d inner)))
   (+ (* (svg-matrix-b outer) (svg-matrix-c inner))
      (* (svg-matrix-d outer) (svg-matrix-d inner)))
   (+ (* (svg-matrix-a outer) (svg-matrix-e inner))
      (* (svg-matrix-c outer) (svg-matrix-f inner))
      (svg-matrix-e outer))
   (+ (* (svg-matrix-b outer) (svg-matrix-e inner))
      (* (svg-matrix-d outer) (svg-matrix-f inner))
      (svg-matrix-f outer))))

(define (svg-matrix-apply-down matrix point)
  (vec2
   (+ (* (svg-matrix-a matrix) (vec2-x point))
      (* (svg-matrix-c matrix) (vec2-y point))
      (svg-matrix-e matrix))
   (+ (* (svg-matrix-b matrix) (vec2-x point))
      (* (svg-matrix-d matrix) (vec2-y point))
      (svg-matrix-f matrix))))
