#lang racket/base

;;;
;;; Color Inspection and Diagnostics Tests
;;;

(require rackunit
         "../colors.rkt"
         "../private/color-preview-inspection.rkt"
         "../private/inspector-document.rkt")

(module+ test
  (define mixed
    (color-mix theme-accent (color-opacity gold-b 1/2) 1/4 #:space 'oklab))
  (define report
    (inspect-color mixed animate-light-theme
                   #:owner-path '(world card)
                   #:style-field 'fill))
  (check-true (color-inspection? report))
  (check-equal? (hash-ref report 'kind) 'expression)
  (check-equal? (hash-ref report 'interpolation-space) 'oklab)
  (check-equal? (hash-ref report 'owner-path) '(world card))
  (check-equal? (hash-ref report 'style-field) 'fill)
  (check-true (pair? (hash-ref report 'role-resolution-chain)))
  (check-regexp-match #px"^#[0-9A-F]{8}$" (hash-ref report 'resolved-hex))
  (check-equal? (rgba-color->hex (resolve-color pure-blue animate-light-theme))
                "#0000FFFF")
  (define diagnostics (color-theme-diagnostics animate-light-theme))
  (check-true (pair? diagnostics))
  (check-true
   (for/or ([diagnostic (in-list diagnostics)])
     (eq? (hash-ref diagnostic 'kind) 'contrast)))
  (define invalid-theme-datum
    `(animate-color-theme 1 incomplete "Incomplete"
                          ,(palette->datum animate-palette)
                          () () #f))
  (check-eq? (hash-ref (car (color-theme-datum-diagnostics invalid-theme-datum)) 'kind)
             'missing-entry)
  (define no-series-theme
    (color-theme #:id 'no-series #:extends animate-light-theme #:series '()))
  (check-eq?
   (hash-ref (car (color-resolution-diagnostics (series-color 0) no-series-theme)) 'kind)
   'expression-resolution-failure)
  (define section (color-theme-inspector-section animate-dark-theme))
  (check-equal? (inspector-section-id section) 'colors-and-theme)
  (check-true (pair? (inspector-section-rows section)))
  (check-equal? (hash-ref (inspector-section-content section) 'hue-columns)
                '(blue aqua green yellow gold red maroon purple))
  (define material-rows
    (color-inspection-rows "surface" theme-surface animate-dark-theme
                           #:owner-path '(world orb) #:style-field 'material-color))
  (check-true (pair? material-rows))
  (check-true
   (for/or ([action (in-list (inspector-row-actions (car material-rows)))])
     (eq? (inspector-action-id action) 'copy-color-token))))
