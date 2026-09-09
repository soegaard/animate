#lang racket/base

;;;
;;; Pure Color and Theme Diagnostics
;;;

;; Diagnostics report review facts.  They never repair authored colors or
;; mutate a theme, so rendering remains an explicit author decision.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "geometry.rkt"
         "color-inspection.rkt"
         "color-palette.rkt"
         "color-style.rkt"
         "color-theme.rkt")

(provide color-contrast-ratio
         color-theme-diagnostics
         color-theme-datum-diagnostics
         color-resolution-diagnostics)


;;;
;;; Contrast
;;;

;; color-contrast-ratio : rgba-color? rgba-color? -> real?
;; Computes WCAG relative-luminance contrast after compositing the foreground
;; over an opaque background. A translucent background has no unique
;; luminance without an additional canvas, so this small API rejects it rather
;; than silently treating its stored RGB components as already composited.
(define (color-contrast-ratio foreground background)
  (unless (rgba-color? foreground)
    (raise-argument-error 'color-contrast-ratio "rgba-color?" foreground))
  (unless (rgba-color? background)
    (raise-argument-error 'color-contrast-ratio "rgba-color?" background))
  (unless (= (rgba-color-alpha background) 1)
    (raise-arguments-error
     'color-contrast-ratio
     "an opaque background; composite a translucent background over an explicit canvas first"
     "background" background))
  (define blended (composite-over foreground background))
  (define first (relative-luminance blended))
  (define second (relative-luminance background))
  (/ (+ (max first second) 1/20)
     (+ (min first second) 1/20)))


;;;
;;; Theme Reports
;;;

;; color-theme-diagnostics : color-theme?
;;                           [#:ordinary-text-pairs (listof (cons/c symbol? symbol?))]
;;                           [#:graphic-pairs (listof (cons/c symbol? symbol?))]
;;                           [#:minimum-series-contrast positive-real?]
;;                           [#:canvas (or/c #f rgba-color?)]
;;                           -> (listof immutable-hash?)
;; Returns deterministic, immutable reports for role contrast, categorical
;; distinguishability, empty series, and monotonic reviewed shade ramps.  The
;; constructors themselves reject missing palette entries, invalid aliases,
;; cyclic roles, and failed expression resolution; callers receive those as
;; precise construction errors before a valid color-theme value exists.
(define (color-theme-diagnostics
         theme
         #:ordinary-text-pairs [ordinary-text-pairs '((foreground . background))]
         #:graphic-pairs [graphic-pairs '((axis . background) (accent . background))]
         #:minimum-series-contrast [minimum-series-contrast 3]
         #:canvas [canvas #f])
  (unless (color-theme? theme)
    (raise-argument-error 'color-theme-diagnostics "color-theme?" theme))
  (unless (and (finite-real? minimum-series-contrast) (positive? minimum-series-contrast))
    (raise-argument-error 'color-theme-diagnostics "positive finite real? as #:minimum-series-contrast"
                          minimum-series-contrast))
  (when (and canvas (not (rgba-color? canvas)))
    (raise-argument-error 'color-theme-diagnostics "#f or rgba-color? as #:canvas" canvas))
  (when (and canvas (not (= (rgba-color-alpha canvas) 1)))
    (raise-arguments-error 'color-theme-diagnostics
                           "an opaque #:canvas when supplied"
                           "canvas" canvas))
  (check-role-pairs 'color-theme-diagnostics ordinary-text-pairs)
  (check-role-pairs 'color-theme-diagnostics graphic-pairs)
  (define default-canvas (diagnostic-background theme canvas))
  (append (contrast-reports theme ordinary-text-pairs 9/2 'ordinary-text canvas)
          (contrast-reports theme graphic-pairs 3 'meaningful-graphic canvas)
          (ramp-reports theme)
          (series-reports theme minimum-series-contrast default-canvas)))

;; color-theme-datum-diagnostics : any/c -> (listof immutable-hash?)
;; Reads an untrusted complete theme datum without evaluating it and translates
;; construction failures into one pure review report.  A valid datum returns
;; the same review rows as color-theme-diagnostics.  This makes missing
;; entries, invalid key spelling, and cyclic role declarations inspectable by
;; a file-import UI without weakening the constructor's strict validation.
(define (color-theme-datum-diagnostics datum)
  ;; Limit classification to decoding/construction. A later implementation
  ;; defect in report generation must remain visible as such instead of being
  ;; mislabeled as malformed caller input.
  (define decoded-or-report
    (with-handlers ([exn:fail?
                     (lambda (error)
                       (list
                        (report (theme-error-kind (exn-message error))
                                'error
                                (exn-message error)
                                (hasheq 'datum-summary
                                        (bounded-datum-summary datum)))))] )
      (datum->theme datum)))
  (if (color-theme? decoded-or-report)
      (color-theme-diagnostics decoded-or-report)
      decoded-or-report))

;; color-resolution-diagnostics : color-spec? color-theme?
;;                                 -> (listof immutable-hash?)
;; Resolves one arbitrary authored field without drawing it. It turns an
;; unresolved expression failure (for example, a series token under an empty
;; series) into data suitable for an inspector or import report.
(define (color-resolution-diagnostics color theme)
  (unless (color-spec? color)
    (raise-argument-error 'color-resolution-diagnostics "color-spec?" color))
  (unless (color-theme? theme)
    (raise-argument-error 'color-resolution-diagnostics "color-theme?" theme))
  (with-handlers ([exn:fail?
                   (lambda (error)
                     (list
                      (report 'expression-resolution-failure 'error
                              (exn-message error)
                              (hasheq 'authored (color-spec->datum color)
                                      'theme-id (color-theme-id theme)))) )])
    (define inspection (inspect-color color theme))
    (list (report 'resolution 'info
                  (format "resolves to ~a" (hash-ref inspection 'resolved-hex))
                  (hasheq 'authored (hash-ref inspection 'authored)
                          'resolved-hex (hash-ref inspection 'resolved-hex))))))

(define (contrast-reports theme pairs threshold use canvas)
  (for/list ([pair (in-list pairs)])
    (define foreground-key (car pair))
    (define background-key (cdr pair))
    (define foreground (resolve-color-in-theme (theme-ref theme foreground-key) theme))
    (define background (resolve-color-in-theme (theme-ref theme background-key) theme))
    (define selected-background (opaque-background background canvas))
    (if selected-background
        (let ([ratio (color-contrast-ratio foreground selected-background)])
          (report 'contrast
                  (if (>= ratio threshold) 'info 'warning)
                  (format "~a against ~a has contrast ~a:1"
                          foreground-key background-key (rounded ratio))
                  (hasheq 'foreground foreground-key
                          'background background-key
                          'ratio ratio
                          'target threshold
                          'use use
                          'canvas-policy (if (= (rgba-color-alpha background) 1)
                                             'opaque-background
                                             'composited-over-canvas))))
        (undetermined-contrast-report foreground-key background-key use))))

;; Only the built-in named hue/gray ramps declare a light-to-dark semantic
;; ordering. A custom five-item group is categorical until its API grows an
;; explicit ramp declaration; list length alone is not a luminance promise.
(define (ramp-reports theme)
  (for/list ([group (in-list (palette-groups (color-theme-palette theme)))]
             #:when (declared-ramp-group? group))
    (define keys (cadr group))
    (define luminances
      (for/list ([key (in-list keys)])
        (relative-luminance (palette-ref (color-theme-palette theme) key))))
    (define monotonic?
      (for/and ([left (in-list luminances)] [right (in-list (cdr luminances))])
        (>= left right)))
    (report 'shade-ramp
            (if monotonic? 'info 'warning)
            (if monotonic?
                (format "~a is light-to-dark by relative luminance" (car group))
                (format "~a is not monotonic by relative luminance" (car group)))
            (hasheq 'group (car group) 'keys keys 'luminances luminances))))

(define (declared-ramp-group? group)
  (and (member (car group)
               '(blue aqua green yellow gold red maroon purple gray))
       (= (length (cadr group)) 5)))

(define (series-reports theme minimum-contrast canvas)
  (define series (theme-series theme))
  (cond
    [(null? series)
     (list (report 'categorical-series 'warning
                   "theme has no categorical series; series-color cannot resolve"
                   #hasheq()))]
    [(not canvas)
     (list (report 'contrast-undetermined 'warning
                   "categorical-series contrast requires an opaque theme background or #:canvas"
                   (hasheq 'use 'categorical-series
                           'canvas-policy 'required)))]
    [else
     (for*/list ([left-index (in-range (length series))]
                 [right-index (in-range (add1 left-index) (length series))]
                 #:do [(define ratio
                         (color-contrast-ratio
                          (composite-over (list-ref series left-index) canvas)
                          (composite-over (list-ref series right-index) canvas)))]
                 #:when (< ratio minimum-contrast))
       (report 'categorical-pair 'warning
               (format "series entries ~a and ~a have contrast ~a:1"
                       left-index right-index (rounded ratio))
               (hasheq 'first-index left-index
                       'second-index right-index
                       'ratio ratio
                       'target minimum-contrast)))]))

(define (diagnostic-background theme canvas)
  (opaque-background
   (resolve-color-in-theme (theme-ref theme 'background) theme)
   canvas))

(define (opaque-background background canvas)
  (cond [(= (rgba-color-alpha background) 1) background]
        [canvas (composite-over background canvas)]
        [else #f]))

(define (undetermined-contrast-report foreground background use)
  (report 'contrast-undetermined 'warning
          (format "~a against ~a requires an opaque background or #:canvas"
                  foreground background)
          (hasheq 'foreground foreground
                  'background background
                  'use use
                  'canvas-policy 'required)))

(define (report kind severity message details)
  (make-immutable-hash
   (list (cons 'kind kind)
         (cons 'severity severity)
         (cons 'message (string->immutable-string message))
         (cons 'details details))))

(define (theme-error-kind message)
  (cond [(regexp-match? #rx"missing (role|key)" message) 'missing-entry]
        [(regexp-match? #rx"cycle" message) 'cyclic-role]
        [(regexp-match? #rx"palette key|canonical" message) 'invalid-alias]
        [else 'configuration-error]))

;; bounded-datum-summary : any/c -> immutable-hash?
;; Describes untrusted invalid input without retaining caller-owned mutable data.
(define (bounded-datum-summary datum)
  (define maximum-depth 8)
  (define maximum-nodes 128)
  (define seen (make-hasheq))
  (define nodes 0)
  (define (visit value depth)
    (set! nodes (add1 nodes))
    (cond [(> nodes maximum-nodes) (hasheq 'kind 'truncated 'reason 'node-budget)]
          [(> depth maximum-depth) (hasheq 'kind 'truncated 'reason 'depth-budget)]
          [(hash-ref seen value #f) (hasheq 'kind 'shared-or-cyclic)]
          [(pair? value)
           (hash-set! seen value #t)
           (hasheq 'kind 'pair
                   'car (visit (car value) (add1 depth))
                   'cdr (visit (cdr value) (add1 depth)))]
          [(vector? value)
           (hash-set! seen value #t)
           (hasheq 'kind 'vector 'length (vector-length value))]
          [(hash? value)
           (hash-set! seen value #t)
           (hasheq 'kind 'hash 'count (hash-count value))]
          [(string? value)
           (hasheq 'kind 'string
                   'length (string-length value)
                   'prefix (string->immutable-string
                            (substring value 0 (min 96 (string-length value)))))]
          [(bytes? value) (hasheq 'kind 'bytes 'length (bytes-length value))]
          [(or (symbol? value) (number? value) (boolean? value) (null? value))
           (hasheq 'kind 'atom 'value value)]
          [else (hasheq 'kind 'other)]))
  (visit datum 0))

(define (check-role-pairs who pairs)
  (unless (and (list? pairs)
               (andmap (lambda (pair)
                         (and (pair? pair) (symbol? (car pair)) (symbol? (cdr pair))))
                       pairs))
    (raise-argument-error who "list of (cons/c symbol? symbol?)" pairs)))

(define (composite-over foreground background)
  (define alpha (rgba-color-alpha foreground))
  (rgba-color (+ (* alpha (rgba-color-red foreground))
                 (* (- 1 alpha) (rgba-color-red background)))
              (+ (* alpha (rgba-color-green foreground))
                 (* (- 1 alpha) (rgba-color-green background)))
              (+ (* alpha (rgba-color-blue foreground))
                 (* (- 1 alpha) (rgba-color-blue background)))
              1))

(define (relative-luminance color)
  (+ (* 0.2126 (srgb-channel->linear (rgba-color-red color)))
     (* 0.7152 (srgb-channel->linear (rgba-color-green color)))
     (* 0.0722 (srgb-channel->linear (rgba-color-blue color)))))

(define (srgb-channel->linear component)
  (define encoded (/ component 255.0))
  (if (<= encoded 0.04045)
      (/ encoded 12.92)
      (expt (/ (+ encoded 0.055) 1.055) 2.4)))

(define (rounded value)
  (/ (round (* value 100)) 100.0))
