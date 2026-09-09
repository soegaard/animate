#lang racket/base

;;;
;;; Color Theme Resolution Tests
;;;

;; Exercises explicit resolution of literals, palette tokens, roles, and pure
;; expressions without invoking a renderer or global mutable theme.

(require racket/list
         rackunit
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
  ;; A series can be consumed only after a theme has its completed categorical
  ;; vector. Definitions may not depend on that vector, including through a
  ;; nested alpha or mix expression.
  (check-exn #px"series-color dependencies"
             (lambda ()
               (color-theme #:id 'invalid-role-series
                            #:extends animate-light-theme
                            #:roles (hash 'accent
                                          (color-with-alpha (series-color 0) 1/2)))))
  (check-exn #px"series-color dependencies"
             (lambda ()
               (color-theme #:id 'invalid-series-series
                            #:extends animate-light-theme
                            #:series (list (color-mix aqua-c (series-color 1) 1/2)))))
  (define light-datum (theme->datum animate-light-theme))
  (define duplicate-role-datum
    (append (take light-datum 5)
            (list (append (list-ref light-datum 5)
                          (list (car (list-ref light-datum 5)))))
            (drop light-datum 6)))
  (check-exn #px"duplicate keys"
             (lambda () (datum->theme duplicate-role-datum)))
  (check-equal? (datum->theme (theme->datum animate-dark-theme))
                animate-dark-theme))
