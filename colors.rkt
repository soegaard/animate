#lang racket/base

;;;
;;; Animate Colors
;;;

;; Provides literal colors and pure themeable color specifications. Palette and
;; role tokens are unresolved immutable values; selecting or resolving a theme
;; is deliberately introduced in a later module slice.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "private/color-style.rkt"
         "private/color-token.rkt"
         "private/color-palette.rkt"
         "private/color-theme.rkt"
         "private/color-resolve.rkt"
         "private/color-theme-data.rkt"
         "private/color-scale.rkt"
         "private/color-inspection.rkt"
         "private/color-diagnostics.rkt"
         (only-in "private/paint.rkt"
                  paint-stop
                  paint-stop?
                  paint-stop-offset
                  paint-stop-color))

;; Exports
(provide (except-out (all-from-out "private/color-style.rkt")
                     normalize-color-spec
                     rgba-color-mix
                     color-spec->datum/budget)
         (except-out (all-from-out "private/color-token.rkt")
                     palette-token?
                     palette-token-key
                     role-token?
                     role-token-key)
         (except-out (all-from-out "private/color-palette.rkt")
                     palette->datum/budget)
         ;; `color-theme-resolved-roles` is an adapter snapshot used only to
         ;; construct a render-color-context.  The public API exposes authored
         ;; role specifications through `theme-ref`, not this implementation
         ;; table.
         (except-out (all-from-out "private/color-theme.rkt")
                     color-theme-resolved-roles)
         (all-from-out "private/color-resolve.rkt")
         (all-from-out "private/color-theme-data.rkt")
         (all-from-out "private/color-scale.rkt")
         (all-from-out "private/color-inspection.rkt")
         (all-from-out "private/color-diagnostics.rkt")
         paint-stop
         paint-stop?
         paint-stop-offset
         paint-stop-color
         black
         white
         pure-red
         pure-green
         pure-blue
         pure-cyan
         pure-magenta
         pure-yellow)


;;;
;;; Reserved Literal Colors
;;;

;; These physical endpoints are fixed literal RGBA values rather than palette
;; tokens, so a future theme cannot make `white` or a calibration primary mean
;; something else.

;; black : rgba-color?
;;   The exact opaque sRGB black endpoint.
(define black (rgb-color #x00 #x00 #x00))

;; white : rgba-color?
;;   The exact opaque sRGB white endpoint.
(define white (rgb-color #xFF #xFF #xFF))

;; pure-red : rgba-color?
;;   The exact opaque sRGB red primary.
(define pure-red (rgb-color #xFF #x00 #x00))

;; pure-green : rgba-color?
;;   The exact opaque sRGB green primary.
(define pure-green (rgb-color #x00 #xFF #x00))

;; pure-blue : rgba-color?
;;   The exact opaque sRGB blue primary.
(define pure-blue (rgb-color #x00 #x00 #xFF))

;; pure-cyan : rgba-color?
;;   The exact opaque sRGB cyan secondary.
(define pure-cyan (rgb-color #x00 #xFF #xFF))

;; pure-magenta : rgba-color?
;;   The exact opaque sRGB magenta secondary.
(define pure-magenta (rgb-color #xFF #x00 #xFF))

;; pure-yellow : rgba-color?
;;   The exact opaque sRGB yellow secondary.
(define pure-yellow (rgb-color #xFF #xFF #x00))
