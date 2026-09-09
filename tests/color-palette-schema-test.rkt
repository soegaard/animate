#lang racket/base

;;;
;;; Color Palette Schema Tests
;;;

;; Verifies the authoritative literal swatch table and palette construction
;; boundary independently from roles and rendering.

(require rackunit
         "../colors.rkt")

(module+ test
  (check-equal? (length (palette-keys animate-palette)) 57)
  (check-equal? (palette-keys animate-palette)
                (apply append (map cadr (palette-groups animate-palette))))
  (check-equal? (palette-ref animate-palette 'aqua)
                (rgb-color #x19 #xC5 #xCE))
  (check-equal? (palette-ref animate-palette 'light-gray)
                (palette-ref animate-palette 'gray-b))
  (check-true (bytes? animate-palette-checksum))
  (check-equal? (bytes-length animate-palette-checksum) 20)

  ;; Root palettes are complete literal tables. Theme references cannot enter a
  ;; palette, and fixed physical literal names cannot be overridden.
  (check-exn exn:fail:contract?
             (lambda ()
               (color-palette #:id 'incomplete #:colors (hash 'aqua-c "#19C5CE"))))
  (check-exn exn:fail:contract?
             (lambda ()
               (color-palette #:id 'token-value
                              #:colors (hash 'aqua-c aqua-c))))
  (check-exn exn:fail:contract?
             (lambda ()
               (color-palette #:id 'reserved
                              #:extends animate-palette
                              #:colors (hash 'white "#000000"))))

  ;; Palette serialization has one complete canonical form.
  (check-equal? (datum->palette (palette->datum animate-palette)) animate-palette)
  (check-exn exn:fail:contract?
             (lambda () (datum->palette '(animate-color-palette 2)))) )
