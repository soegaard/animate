#lang racket/base

;;;
;;; Semantic TeX and SVG Ownership
;;;
;; Emits semantic marker source and extracts ordered ownership from supplied SVG text.
;; Parsing operates on supplied data without invoking TeX.

;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list append-map)
  racket/match
  (only-in racket/string string-join string-prefix? string-trim)
  xml
  "format.rkt")

;; Exports
(provide
  annotate-math-source (struct-out semantic-marker) (struct-out svg-rule-bounds)
  svg-marker-ids isolate-svg-marker
  recolor-svg canonicalize-svg-definitions svg-view-box fraction-rule-bounds crop-svg
  svg->xexpr xexpr->svg)

;;;
;;; Data Representation
;;;
(struct semantic-marker (name span)
  #:transparent)
;; semantic-marker is an immutable record. Its fields have the following roles.
;;  - name  string?  deterministic SVG marker identity
;;  - span  math-source-span?  owned source interval

(struct svg-rule-bounds (x y width height)
  #:transparent)
;; svg-rule-bounds is an immutable SVG-coordinate record. Its fields identify
;; the direct rectangular rule geometry emitted for one prepared TeX fraction.
;;  - x  real?  left edge in the cropped SVG view-box coordinate system
;;  - y  real?  top edge in the cropped SVG view-box coordinate system
;;  - width  positive-real?  horizontal painted-rule extent in SVG units
;;  - height  positive-real?  vertical painted-rule extent in SVG units

; annotate-math-source : any/c -> (values string? list?)
;;   Marks nested semantic ranges before one complete TeX layout pass.
(define (annotate-math-source source)
  (define text (math-source-text source))
  (define indexed
    (for/list ([span (in-list (math-source-spans source))] [i (in-naturals)])
      (semantic-marker (format "animate-math-~a" i) span)))
  (define (start m) (math-source-span-start (semantic-marker-span m)))
  (define (end m) (math-source-span-end (semantic-marker-span m)))
  ;; Equal ranges: the expression is the outer container, its atom is inner.
  (define ordered
    (sort indexed
      (lambda (a b)
        (cond
          [(< (start a) (start b)) #t]
          [(> (start a) (start b)) #f]
          [(> (end a) (end b)) #t]
          [(< (end a) (end b)) #f]
          [else
           (and
             (eq? (math-source-span-role (semantic-marker-span a)) 'expression)
             (not (eq? (math-source-span-role (semantic-marker-span b)) 'expression)))]))))
  (define output (open-output-string))
  (define stack '())
  (for ([i (in-range (+ 1 (string-length text)))])
    (let close ()
      (when (and (pair? stack) (= i (end (car stack))))
        (display "\\special{dvisvgm:raw </g>}" output)
        (set! stack (cdr stack))
        (close)))
    (for ([m (in-list ordered)] #:when (= i (start m)))
      (when (and (pair? stack) (> (end m) (end (car stack))))
        (error 'annotate-math-source "overlapping non-nested mathematical source ranges"))
      (fprintf output "\\special{dvisvgm:raw <g id='~a'>}" (semantic-marker-name m))
      (set! stack (cons m stack)))
    (when (< i (string-length text)) (write-char (string-ref text i) output)))
  (unless (null? stack) (error 'annotate-math-source "unclosed source marker"))
  (values (get-output-string output) indexed))

; svg->xexpr : any/c -> list?
;;   Parses an SVG string into an XML expression at the adapter boundary.
(define (svg->xexpr source)
  (xml->xexpr (document-element (read-xml (open-input-string source)))))

; xexpr->svg : any/c -> string?
;;   Serializes an XML expression as SVG source.
(define (xexpr->svg x)
  (xexpr->string x))

; element? : any/c -> boolean?
;;   Recognizes an XML element or an owned semantic marker.
(define (element? x)
  (and (list? x) (pair? x) (symbol? (car x)) (pair? (cdr x)) (list? (cadr x))))

; attr : any/c any/c [any/c] -> any/c
;;   Looks up one XML attribute with an explicit fallback.
(define (attr x key [fallback #f])
  (define entry (and (element? x) (assq key (cadr x))))
  (if entry (cadr entry) fallback))

; glyph-definition? : any/c -> boolean?
;;   Recognizes a named direct path definition emitted by dvisvgm for a glyph.
(define (glyph-definition? value)
  (and (element? value)
       (eq? (car value) 'path)
       (string? (attr value 'id))))

; sort-glyph-definition-runs : list? -> list?
;;   Stabilizes direct glyph definitions while retaining every non-glyph definition
;;   element and whitespace position. SVG definition order does not affect references.
(define (sort-glyph-definition-runs entries)
  (define (insert-glyph glyph ordered)
    (cond
      [(null? ordered) (list glyph)]
      [(string<? (attr glyph 'id) (attr (car ordered) 'id))
       (cons glyph ordered)]
      [else (cons (car ordered) (insert-glyph glyph (cdr ordered)))]))
  (define (sort-glyphs glyphs)
    (let loop ([remaining glyphs] [ordered '()])
      (if (null? remaining)
        ordered
        (loop (cdr remaining) (insert-glyph (car remaining) ordered)))))
  (define ordered-glyphs
    (sort-glyphs (filter glyph-definition? entries)))
  (let loop ([remaining entries] [remaining-glyphs ordered-glyphs])
    (cond
      [(null? remaining) '()]
      [(glyph-definition? (car remaining))
       (cons (car remaining-glyphs)
             (loop (cdr remaining) (cdr remaining-glyphs)))]
      [else (cons (car remaining) (loop (cdr remaining) remaining-glyphs))])))

; canonicalize-svg-definitions : string? -> string?
;;   Makes dvisvgm's otherwise nondeterministic glyph-definition order stable before
;;   content-addressing a prepared SVG. It leaves drawable order and all non-glyph
;;   definition elements alone.
(define (canonicalize-svg-definitions source)
  (unless (string? source)
    (raise-argument-error 'canonicalize-svg-definitions "string?" source))
  (define (walk value)
    (if (element? value)
      (let ([children (map walk (cddr value))])
        (cons (car value)
              (cons (cadr value)
                    (if (eq? (car value) 'defs)
                      (sort-glyph-definition-runs children)
                      children))))
      value))
  (xexpr->svg (walk (svg->xexpr source))))

; marker? : any/c -> boolean?
;;   Recognizes an XML element or an owned semantic marker.
(define (marker? x)
  (define id (attr x 'id))
  (and id (string-prefix? id "animate-math-")))

; svg-marker-ids : any/c -> (listof string?)
;;   Lists semantic marker names in source traversal order.
(define (svg-marker-ids source)
  (define (walk x)
    (if (element? x)
      (append (if (marker? x) (list (attr x 'id)) '()) (append-map walk (cddr x)))
      '()))
  (walk (if (string? source) (svg->xexpr source) source)))

; isolate-svg-marker : any/c any/c -> string?
;;   Isolates one owned marker while retaining shared definitions and ancestor
;;   transforms.
(define (isolate-svg-marker source wanted)
  (define root (if (string? source) (svg->xexpr source) source))
  (define (walk x active?)
    (cond
      [(not (element? x)) (and active? x)]
      [(eq? (car x) 'defs) x]
      [(and (marker? x) active? (not (equal? (attr x 'id) wanted))) #f]
      [else
       (define now? (or active? (equal? (attr x 'id) wanted)))
       (define children (filter values (map (lambda (v) (walk v now?)) (cddr x))))
       (define container? (memq (car x) '(svg g a)))
       (cond [(or now? container?) (cons (car x) (cons (cadr x) children))] [else #f])]))
  (xexpr->svg (walk root #f)))

; recolor-svg : any/c any/c -> string?
;;   Recolors prepared mathematical ink without altering absent paint.
(define (recolor-svg source color)
  (unless (and (string? color) (regexp-match? #px"^(#[0-9A-Fa-f]{3,8}|[A-Za-z]+)$" color))
    (raise-argument-error 'recolor-svg "CSS named or hexadecimal solid color" color))
  (define (walk x)
    (if (element? x)
      (let* ([attributes
              (for/list ([a (in-list (cadr x))])
                (if (and
                      (memq (car a) '(fill stroke color))
                      (not (member (cadr a) '("none" "transparent"))))
                  (list (car a) color)
                  a))]
              [attrs
               (if (eq? (car x) 'svg)
                 (cons
                   (list 'fill color)
                   (filter (lambda (a) (not (eq? (car a) 'fill))) attributes))
                 attributes)])
        (cons (car x) (cons attrs (map walk (cddr x)))))
      x))
  (xexpr->svg (walk (svg->xexpr source))))

; svg-view-box : any/c -> list?
;;   Reads and validates the SVG view box used for coordinate conversion.
(define (svg-view-box source)
  (define x (if (string? source) (svg->xexpr source) source))
  (define text (attr x 'viewBox))
  (unless text (error 'svg-view-box "SVG has no viewBox"))
  (define values (map string->number (regexp-split #px"[ ,]+" (string-trim text))))
  (unless (and
            (= (length values) 4)
            (andmap real? values)
            (> (list-ref values 2) 0)
            (> (list-ref values 3) 0))
    (error 'svg-view-box "invalid viewBox: ~s" text))
  values)

; fraction-rule-bounds : any/c -> (or/c svg-rule-bounds? #f)
;;   Returns the widest positive direct SVG rectangle, which is the fraction rule
;;   in a division marker. Definitions are ignored because they are never painted.
(define (fraction-rule-bounds source)
  (define root (if (string? source) (svg->xexpr source) source))
  (define (number-attribute element key [fallback #f])
    (define value (attr element key fallback))
    (and (string? value) (string->number value)))
  (define (rect-bounds element)
    (and (element? element)
         (eq? (car element) 'rect)
         (let ([x (number-attribute element 'x "0")]
               [y (number-attribute element 'y "0")]
               [width (number-attribute element 'width)]
               [height (number-attribute element 'height)])
           (and (real? x) (real? y) (real? width) (real? height)
                (positive? width) (positive? height)
                (svg-rule-bounds x y width height)))))
  (define (painted-rectangles element)
    (cond
      [(not (element? element)) '()]
      [(eq? (car element) 'defs) '()]
      [else
       (append (if (rect-bounds element) (list (rect-bounds element)) '())
               (append-map painted-rectangles (cddr element)))]))
  (define rectangles (painted-rectangles root))
  (and (pair? rectangles)
       (car (sort rectangles > #:key svg-rule-bounds-width))))

; crop-svg : any/c any/c any/c any/c -> string?
;;   Changes the SVG viewport without discarding its frozen glyph geometry.
(define (crop-svg source box width height)
  (define root (svg->xexpr source))
  (define attrs
    (filter (lambda (a) (not (memq (car a) '(viewBox width height)))) (cadr root)))
  (xexpr->svg
    (cons 'svg
      (cons
        (append
          (list
            (list 'viewBox (string-join (map number->string box) " "))
            (list 'width (number->string width))
            (list 'height (number->string height)))
          attrs)
        (cddr root)))))
