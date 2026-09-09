#lang racket/base

;;;
;;; Color Theme Resolution Tests
;;;

;; Exercises explicit resolution of literals, palette tokens, roles, and pure
;; expressions without invoking a renderer or global mutable theme.

(require rackunit
         "../colors.rkt")

(module+ test
  (check-equal? (resolve-color "#19C5CE" animate-light-theme)
                (rgb-color #x19 #xC5 #xCE))
  (check-equal? (resolve-color aqua-c animate-light-theme)
                (rgb-color #x19 #xC5 #xCE))
  (check-equal? (resolve-color theme-accent animate-light-theme)
                (palette-ref animate-palette 'aqua-d))
  (check-equal? (resolve-color theme-accent animate-dark-theme)
                (palette-ref animate-palette 'aqua-c))
  (check-equal? (resolve-color (color-with-alpha aqua-c 1/4) animate-light-theme)
                (rgba-color #x19 #xC5 #xCE 1/4))
  ;; A token/literal mix uses the selected snapshot and remains deterministic.
  (check-equal? (resolve-color (color-mix aqua-c pure-red 0) animate-dark-theme)
                (palette-ref animate-palette 'aqua-c))
  (check-exn #px"palette containing the requested key"
             (lambda () (resolve-color (palette-color 'custom-missing)
                                       animate-light-theme)))
  (check-exn #px"theme containing the requested role"
             (lambda () (resolve-color (role-color 'missing-role)
                                       animate-light-theme)))
  (check-equal? (datum->theme (theme->datum animate-dark-theme))
                animate-dark-theme))
