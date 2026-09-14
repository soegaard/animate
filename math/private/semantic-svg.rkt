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
  annotate-math-source (struct-out semantic-marker) svg-marker-ids isolate-svg-marker
  recolor-svg svg-view-box crop-svg svg->xexpr xexpr->svg)

;;;
;;; Data Representation
;;;
(struct semantic-marker (name span)
  #:transparent)
;; semantic-marker is an immutable record. Its fields have the following roles.
;;  - name  string?  deterministic SVG marker identity
;;  - span  math-source-span?  owned source interval

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
