#lang racket/base

;;;
;;; Color Theme Inheritance Tests
;;;

;; Ensures optional parent snapshots are merged once and are never retained as
;; mutable lookup chains.

(require rackunit
         "../colors.rkt")

(module+ test
  (define supplied-roles (make-hash (list (cons 'accent red-c))))
  (define child
    (color-theme #:id 'child
                 #:extends animate-light-theme
                 #:roles supplied-roles))
  (hash-set! supplied-roles 'foreground pure-red)
  (check-equal? (resolve-color theme-accent child)
                (palette-ref animate-palette 'red-c))
  (check-equal? (resolve-color theme-foreground child)
                (resolve-color theme-foreground animate-light-theme))
  (check-equal? (theme-ref animate-light-theme 'accent) aqua-d)
  (check-equal? (color-theme-palette child) animate-palette)

  ;; A derived palette copies caller-owned data and changes only the selected
  ;; swatch in the child theme.
  (define supplied-colors (make-hash (list (cons 'aqua-c "#112233"))))
  (define child-palette
    (color-palette #:id 'child-palette
                   #:extends animate-palette
                   #:colors supplied-colors))
  (hash-set! supplied-colors 'aqua-c "#FFFFFF")
  (define palette-child
    (color-theme #:id 'palette-child
                 #:extends animate-light-theme
                 #:palette child-palette
                 #:roles (hash)))
  (check-equal? (resolve-color aqua-c palette-child) (rgb-color #x11 #x22 #x33))
  (check-equal? (resolve-color aqua-c animate-light-theme) (rgb-color #x19 #xC5 #xCE)))
