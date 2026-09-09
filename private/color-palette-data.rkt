#lang racket/base

;;;
;;; Animate Palette Data
;;;

;; Defines the reviewed, literal Animate swatch table and its ordered catalog
;; metadata. This module contains data only: no theme state, renderer, or
;; palette-resolution algorithm.


;;;
;;; Imports and Exports
;;;

;; Exports
(provide animate-palette-version
         animate-palette-colors
         animate-palette-groups
         standard-palette-keys
         reserved-literal-palette-keys)


;;;
;;; Palette Schema and Catalog
;;;

;; animate-palette-version : exact-positive-integer?
;;   Identifies the frozen numerical Animate palette table below.
(define animate-palette-version 1)

;; animate-palette-colors : (listof (cons/c symbol? string?))
;;   Stores proposed literal sRGB swatches in canonical catalog order. The
;;   values are source data for review, not a raster-image approximation.
(define animate-palette-colors
  (list
   (cons 'blue-a "#DCEBFF") (cons 'blue-b "#A8C7FA")
   (cons 'blue-c "#4C87D9") (cons 'blue-d "#2A5DAB")
   (cons 'blue-e "#16355F")
   (cons 'aqua-a "#C9F5F5") (cons 'aqua-b "#8DE3E5")
   (cons 'aqua-c "#19C5CE") (cons 'aqua-d "#0E8D9A")
   (cons 'aqua-e "#07515A")
   (cons 'green-a "#D5F4DB") (cons 'green-b "#9ADDAD")
   (cons 'green-c "#4CBF72") (cons 'green-d "#278B4C")
   (cons 'green-e "#15522C")
   (cons 'yellow-a "#FFF5B5") (cons 'yellow-b "#FFE47A")
   (cons 'yellow-c "#F6C644") (cons 'yellow-d "#B98512")
   (cons 'yellow-e "#6C4A08")
   (cons 'gold-a "#FFE4B0") (cons 'gold-b "#F7C56B")
   (cons 'gold-c "#E8A52B") (cons 'gold-d "#A86D0D")
   (cons 'gold-e "#5B3908")
   (cons 'red-a "#FFD7D7") (cons 'red-b "#F5A3A3")
   (cons 'red-c "#E05252") (cons 'red-d "#AD2929")
   (cons 'red-e "#621414")
   (cons 'maroon-a "#F1D3DF") (cons 'maroon-b "#D99AB3")
   (cons 'maroon-c "#A64B73") (cons 'maroon-d "#742B4A")
   (cons 'maroon-e "#421628")
   (cons 'purple-a "#EADDFB") (cons 'purple-b "#CBB2EF")
   (cons 'purple-c "#8B63C7") (cons 'purple-d "#5E3B97")
   (cons 'purple-e "#321F58")
   (cons 'gray-a "#F4F6F8") (cons 'gray-b "#D8DEE6")
   (cons 'gray-c "#9AA6B2") (cons 'gray-d "#59636F")
   (cons 'gray-e "#252B33")
   (cons 'pink "#F48FB1") (cons 'light-pink "#F8C5D4")
   (cons 'orange "#F28C28") (cons 'light-brown "#C18B5A")
   (cons 'dark-brown "#67412A") (cons 'gray-brown "#786D65")
   (cons 'blush "#F6CDD1") (cons 'peach "#F4B183")
   (cons 'apricot "#F7C77A") (cons 'tan "#D2A679")
   (cons 'cocoa "#805A46") (cons 'taupe "#99867A")))

;; animate-palette-groups : (listof (list/c symbol? (listof symbol?)))
;;   Lists named ramps and auxiliary groups in reproducible display order.
(define animate-palette-groups
  (list
   (list 'blue '(blue-a blue-b blue-c blue-d blue-e))
   (list 'aqua '(aqua-a aqua-b aqua-c aqua-d aqua-e))
   (list 'green '(green-a green-b green-c green-d green-e))
   (list 'yellow '(yellow-a yellow-b yellow-c yellow-d yellow-e))
   (list 'gold '(gold-a gold-b gold-c gold-d gold-e))
   (list 'red '(red-a red-b red-c red-d red-e))
   (list 'maroon '(maroon-a maroon-b maroon-c maroon-d maroon-e))
   (list 'purple '(purple-a purple-b purple-c purple-d purple-e))
   (list 'gray '(gray-a gray-b gray-c gray-d gray-e))
   (list 'auxiliary '(pink light-pink orange light-brown dark-brown gray-brown))
   (list 'warm-naturals '(blush peach apricot tan cocoa taupe))))

;; standard-palette-keys : (listof symbol?)
;;   Gives every built-in overridable palette key in deterministic order.
(define standard-palette-keys
  (apply append (map cadr animate-palette-groups)))

;; reserved-literal-palette-keys : (listof symbol?)
;;   Names that remain exact literals and cannot be made palette entries.
(define reserved-literal-palette-keys
  '(black white pure-red pure-green pure-blue pure-cyan pure-magenta pure-yellow))
