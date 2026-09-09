#lang racket/base

;;;
;;; Color Token Tests
;;;

;; Exercises the pure palette and role token vocabulary without selecting a
;; theme or importing a drawing backend.

(require rackunit
         "../colors.rkt")

(module+ test
  ;; Every hue ramp is exported in canonical light-to-dark order.
  (check-equal?
   (map color-token-key
        (list blue-a blue-b blue-c blue-d blue-e
              aqua-a aqua-b aqua-c aqua-d aqua-e
              green-a green-b green-c green-d green-e
              yellow-a yellow-b yellow-c yellow-d yellow-e
              gold-a gold-b gold-c gold-d gold-e
              red-a red-b red-c red-d red-e
              maroon-a maroon-b maroon-c maroon-d maroon-e
              purple-a purple-b purple-c purple-d purple-e))
   '(blue-a blue-b blue-c blue-d blue-e
     aqua-a aqua-b aqua-c aqua-d aqua-e
     green-a green-b green-c green-d green-e
     yellow-a yellow-b yellow-c yellow-d yellow-e
     gold-a gold-b gold-c gold-d gold-e
     red-a red-b red-c red-d red-e
     maroon-a maroon-b maroon-c maroon-d maroon-e
     purple-a purple-b purple-c purple-d purple-e))
  (for ([token (in-list (list blue-a aqua-c purple-e))])
    (check-true (color-token? token))
    (check-eq? (color-token-kind token) 'palette))

  ;; Family and neutral aliases are the exact canonical catalog values.
  (check-eq? blue blue-c)
  (check-eq? aqua aqua-c)
  (check-eq? green green-c)
  (check-eq? yellow yellow-c)
  (check-eq? gold gold-c)
  (check-eq? red red-c)
  (check-eq? maroon maroon-c)
  (check-eq? purple purple-c)
  (check-eq? lighter-gray gray-a)
  (check-eq? light-gray gray-b)
  (check-eq? gray gray-c)
  (check-eq? dark-gray gray-d)
  (check-eq? darker-gray gray-e)
  (check-equal? (map color-token-key
                     (list pink light-pink orange light-brown dark-brown gray-brown
                           blush peach apricot tan cocoa taupe))
                '(pink light-pink orange light-brown dark-brown gray-brown
                  blush peach apricot tan cocoa taupe))

  ;; Explicit constructors may represent custom entries, but not a noncanonical
  ;; spelling. Theme membership is intentionally a later resolution concern.
  (check-equal? (color-token-key (palette-color 'custom-accent)) 'custom-accent)
  (check-equal? (palette-color 'aqua) aqua-c)
  (check-equal? (palette-color 'gray) gray-c)
  (for ([bad-key (in-list (list 'Aqua-c 'aqua_c 'aqua--c '7-a
                                  (string->symbol "")))])
    (check-exn exn:fail:contract? (lambda () (palette-color bad-key))))

  ;; Role keys use explicit constructors and cannot arrive as bare symbols.
  (check-equal? (role-color 'accent) theme-accent)
  (check-eq? (color-token-kind theme-background) 'role)
  (check-equal? (color-token-key theme-background) 'background)
  (check-exn exn:fail:contract? (lambda () (role-color (string->symbol ""))))
  (check-false (color-spec? 'aqua-c))
  (check-false (color-spec? "aqua-c"))
  ;; Existing strings remain literal names; `teal` is never a palette token.
  (check-true (literal-color-spec? "teal"))
  (check-false (color-token? "teal")))
