#lang racket/base

;; Geometry theme data. Color families stay symbolic until the animate adapter
;; turns them into animate/colors palette tokens. Widths are cosmetic; radius,
;; font-size and offset are local world lengths.
(require racket/list racket/match racket/string "private/math.rkt"
         (for-syntax racket/base))
(provide geometry-theme geometry-theme? make-geometry-theme
         default-geometry-theme default-light-geometry-theme default-dark-geometry-theme
         geometry-theme-rules geometry-theme-set resolve-geometry-style
         validate-object-style)

(struct geometry-theme-value (rules) #:transparent)
(define geometry-theme? geometry-theme-value?)
(define geometry-theme-rules geometry-theme-value-rules)
(define selectors '(stroke fill label point line segment ray circle marker normal deemphasized highlighted))
(define states '(normal deemphasized highlighted))
(define (selector-path? path)
  (define kinds '(point line segment ray circle marker))
  (define channels '(stroke fill label))
  (match path
    [(list x) (memq x selectors)]
    [(list x y) (or (and (memq x kinds) (memq y (append channels states)))
                    (and (memq x states) (memq y channels)))]
    [(list x y z) (and (memq x kinds) (memq y states) (memq z channels))]
    [_ #f]))
(define properties '(width radius size spacing font-size font-family font-face font-style font-weight offset
                          color-family color-variant color opacity dash))
(define (property-valid? key value)
  (case key
    [(width offset spacing) (and (finite-real? value) (>= value 0))]
    [(radius size font-size) (and (finite-real? value) (> value 0))]
    [(opacity) (and (finite-real? value) (<= 0 value 1))]
    [(color-family) (and (symbol? value) (regexp-match? #px"^[a-z][a-z0-9-]*$" (symbol->string value)))]
    [(color-variant) (memq value '(a b c d e))]
    ;; Opaque native color values are also accepted by the procedural setter;
    ;; the animate adapter performs the authoritative color-spec validation.
    [(color) (not (procedure? value))]
    [(font-family) (memq value '(default decorative roman script swiss modern symbol system))]
    [(font-face) (or (not value) (string? value))]
    [(font-style) (memq value '(normal italic slant))]
    [(font-weight) (memq value '(normal bold light))]
    [(dash) (or (eq? value 'solid)
                (and (list? value) (pair? value) (even? (length value))
                     (andmap (lambda (n) (and (finite-real? n) (> n 0))) value)))]
    [else #f]))
(define (check-property key value channel)
  (unless (and (memq key properties) (property-valid? key value))
    (geometry-error 'geometry-theme "invalid property ~a = ~e" key value))
  (when (and (eq? key 'width) (not (eq? channel 'stroke)))
    (geometry-error 'geometry-theme "width belongs in a stroke rule"))
  (when (and (eq? key 'dash) (not (eq? channel 'stroke)))
    (geometry-error 'geometry-theme "dash belongs in a stroke rule")))
(define (compile-rules rules initial)
  (define table initial)
  (define (walk rule path)
    (unless (and (list? rule) (pair? rule) (memq (car rule) selectors))
      (geometry-error 'geometry-theme "unknown selector/rule ~e" rule))
    (define key (append path (list (car rule))))
    (unless (selector-path? key)
      (geometry-error 'geometry-theme "unsupported selector combination ~e" key))
    (for ([entry (in-list (cdr rule))])
      (unless (and (list? entry) (pair? entry)) (geometry-error 'geometry-theme "invalid style entry ~e" entry))
      (if (memq (car entry) selectors)
          (walk entry key)
          (begin
            (unless (= (length entry) 2) (geometry-error 'geometry-theme "expected [property value]: ~e" entry))
            (check-property (car entry) (cadr entry) (last key))
            (set! table (hash-set table key (hash-set (hash-ref table key (hash)) (car entry) (if (string? (cadr entry))
                                                                                       (string->immutable-string (cadr entry))
                                                                                       (cadr entry)))))))))
  (for-each (lambda (r) (walk r '())) rules)
  table)
(define default-light-geometry-theme
  (geometry-theme-value
   (compile-rules
    '((stroke (width 2))
      (point (radius 0.055) (highlighted (radius 0.08)))
      (label (font-size 0.30) (font-family roman) (font-style italic)
             (offset 0.16) (color foreground))
      (circle (color-family aqua))
      (marker (size 0.18) (spacing 0.08) (radius 0.28)
              (normal (color foreground))
              (deemphasized (color muted) (opacity 0.75))
              (highlighted (color highlight) (opacity 1) (stroke (width 4))))
      (normal (color-variant d))
      (deemphasized (color-variant c) (opacity 0.75))
      (highlighted (color-variant e) (opacity 1) (stroke (width 4))))
    (hash))))
(define default-dark-geometry-theme
  (geometry-theme-value
   (compile-rules
    '((stroke (width 2))
      (point (radius 0.055) (highlighted (radius 0.08)))
      (label (font-size 0.30) (font-family roman) (font-style italic)
             (offset 0.16) (color foreground))
      (circle (color-family aqua))
      (marker (size 0.18) (spacing 0.08) (radius 0.28)
              (normal (color foreground))
              (deemphasized (color muted) (opacity 0.70))
              (highlighted (color highlight) (opacity 1) (stroke (width 4))))
      (normal (color-variant b))
      (deemphasized (color-variant c) (opacity 0.70))
      (highlighted (color-variant a) (opacity 1) (stroke (width 4))))
    (hash))))
(define default-geometry-theme default-light-geometry-theme)
(define (make-geometry-theme rules #:extends [parent default-geometry-theme])
  (unless (geometry-theme? parent) (geometry-error 'make-geometry-theme "expected a parent geometry theme"))
  (geometry-theme-value (compile-rules rules (geometry-theme-rules parent))))
(define-syntax (geometry-theme stx)
  (syntax-case stx ()
    [(_ #:extends parent rule ...) #'(make-geometry-theme '(rule ...) #:extends parent)]
    [(_ rule ...) #'(make-geometry-theme '(rule ...))]))
(define (geometry-theme-set theme selector entries)
  (define path (if (symbol? selector) (list selector) selector))
  (unless (and (list? path) (pair? path)) (geometry-error 'geometry-theme-set "expected a selector path"))
  (define nested (foldr (lambda (key content) (list (cons key content))) entries path))
  (make-geometry-theme nested #:extends theme))

(define (validate-object-style entries)
  (define (walk entries channel)
    (for ([entry (in-list entries)])
      (unless (and (list? entry) (pair? entry)) (geometry-error 'style "invalid style entry ~e" entry))
      (if (memq (car entry) '(stroke fill label))
          (walk (cdr entry) (car entry))
          (begin
            (unless (= (length entry) 2) (geometry-error 'style "expected [property value]"))
            (check-property (car entry) (cadr entry) channel)))))
  (walk entries 'main)
  entries)

(define initial-style
  (hash 'radius 0.055 'size 0.18 'spacing 0.08 'font-size 0.30 'font-family 'roman 'font-face #f
        'font-style 'italic 'font-weight 'normal 'offset 0.16
        'opacity 1 'stroke-opacity 1 'fill-opacity 1 'label-opacity 1
        'stroke-width 2 'dash 'solid
        'stroke-family 'blue 'stroke-variant 'a 'stroke-color 'inherit
        'fill-family 'blue 'fill-variant 'a 'fill-color 'inherit
        'label-family 'blue 'label-variant 'a 'label-color 'inherit))
(define (channel-key channel suffix)
  (string->symbol (format "~a-~a" channel suffix)))
(define (apply-property style key value channel)
  (case key
    [(color-family color-variant color)
     (define suffix (case key [(color-family) 'family] [(color-variant) 'variant] [else 'color]))
     (for/fold ([s style]) ([ch (in-list (if (eq? channel 'main) '(stroke fill label) (list channel)))])
       (hash-set s (channel-key ch suffix) value))]
    [(width) (hash-set style 'stroke-width value)]
    [(opacity) (hash-set style (if (eq? channel 'main) 'opacity (channel-key channel 'opacity)) value)]
    [else (hash-set style key value)]))
(define (apply-entries style entries channel)
  (for/fold ([s style]) ([entry (in-list entries)])
    (if (memq (car entry) '(stroke fill label))
        (apply-entries s (cdr entry) (car entry))
        (apply-property s (car entry) (cadr entry) channel))))
(define (resolve-geometry-style theme kind state [overrides '()] #:highlight? [highlight? #f])
  (unless (geometry-theme? theme) (geometry-error 'resolve-geometry-style "expected a geometry theme"))
  (unless (memq state '(normal deemphasized)) (geometry-error 'resolve-geometry-style "invalid persistent state"))
  (validate-object-style overrides)
  (define type (string->symbol (string-downcase (symbol->string kind))))
  (define rules (geometry-theme-rules theme))
  (define (rule s path [channel 'main])
    (for/fold ([s s]) ([(key value) (in-hash (hash-ref rules path (hash)))])
      (apply-property s key value channel)))
  (define (scope s path)
    (for/fold ([s (rule s path)]) ([ch (in-list '(stroke fill label))])
      (rule s (append path (list ch)) ch)))
  (define s0 (for/fold ([s initial-style]) ([ch (in-list '(stroke fill))]) (rule s (list ch) ch)))
  (define s1 (scope s0 (list type)))
  (define s2 (rule (rule s1 '(label) 'label) (list type 'label) 'label))
  (define s3 (scope (scope s2 '(normal)) (list type 'normal)))
  (define s4 (if (eq? state 'normal) s3 (scope (scope s3 (list state)) (list type state))))
  (define s5 (if highlight? (scope (scope s4 '(highlighted)) (list type 'highlighted)) s4))
  ;; Family-only overrides retain the variant supplied by the current state.
  ;; Exact colors remain exact, but opacity/width/highlight can still animate.
  (apply-entries s5 overrides 'main))
