#lang racket/base

;;; Complete theme serialization shares one bounded output budget

(require racket/list
         rackunit
         "../colors.rkt")

(module+ test
  ;; A palette can be shallow while still producing an impractically large
  ;; readable datum. It must not bypass the same theme export allowance used
  ;; for color expressions.
  (define shallow-palette
    (color-palette
     #:id 'many-shallow-swatches
     #:extends animate-palette
     #:colors
     (for/hash ([index (in-range 8000)])
       (values (string->symbol (format "shallow-~a" index))
               (rgb-color 1 2 3)))
     #:groups '()))
  (define shallow-palette-theme
    (color-theme #:id 'many-shallow-swatches-theme
                 #:extends animate-light-theme
                 #:palette shallow-palette))
  (check-exn exn:fail:contract?
             (lambda () (theme->datum shallow-palette-theme)))

  ;; Group membership is serialized metadata too. A long group must be bounded
  ;; even though it references existing palette entries rather than new colors.
  (define long-group-palette
    (color-palette #:id 'long-group-palette
                   #:extends animate-palette
                   #:colors (hash)
                   #:groups
                   (list (list 'many-members
                               (make-list 60000 'blue-c)))))
  (define long-group-theme
    (color-theme #:id 'long-group-theme #:extends animate-light-theme
                 #:palette long-group-palette))
  (check-exn exn:fail:contract?
             (lambda () (theme->datum long-group-theme)))

  ;; Two independently acceptable sections can exceed the whole-theme budget
  ;; together; construction cannot reset the allowance between palette, roles,
  ;; and series.
  (define combined-palette
    (color-palette
     #:id 'combined-palette
     #:extends animate-palette
     #:colors
     (for/hash ([index (in-range 3500)])
       (values (string->symbol (format "combined-~a" index))
               (rgb-color 4 5 6)))
     #:groups '()))
  (define combined-roles
    (for/hash ([index (in-range 5000)])
      (values (string->symbol (format "combined-role-~a" index)) theme-accent)))
  (define combined-theme
    (color-theme #:id 'combined-budget-theme #:extends animate-light-theme
                 #:palette combined-palette #:roles combined-roles))
  (check-exn exn:fail:contract?
             (lambda () (theme->datum combined-theme)))

  ;; Atom bytes have their own bound so one long display string cannot hide in
  ;; a single node.
  (define oversized-name-theme
    (color-theme #:id 'oversized-name-theme #:extends animate-light-theme
                 #:display-name (make-string 65537 #\x)))
  (check-exn exn:fail:contract?
             (lambda () (theme->datum oversized-name-theme)))

  ;; Ordinary catalog data remains serializable and round-trips normally.
  (check-equal? (datum->theme (theme->datum animate-light-theme))
                animate-light-theme))
