#lang racket/base

;;;
;;; Read-Only Color Resolution Inspection
;;;

;; This module explains one authored color specification under one explicit
;; immutable theme.  It owns no renderer, GUI state, or current-theme
;; parameter, so previews, command-line probes, and tests see the same data.


;;;
;;; Imports and Exports
;;;

(require racket/list
         "color-expression.rkt"
         "color-style.rkt"
         "color-theme.rkt"
         "color-token.rkt")

(provide color-inspection?
         inspect-color
         rgba-color->hex)


;;;
;;; Public Inspection Data
;;;

;; color-inspection? : any/c -> boolean?
;;   Recognizes the immutable hash returned by inspect-color.
(define (color-inspection? value)
  (and (hash? value)
       (immutable? value)
       (hash-has-key? value 'authored)
       (hash-has-key? value 'resolved)))

;; inspect-color : color-spec? color-theme?
;;                 [#:owner-path (or/c #f (listof symbol?))]
;;                 [#:style-field (or/c #f symbol?)]
;;                 -> immutable-hash?
;; Produces a display-neutral explanation of an authored color.  `authored`
;; stays a versioned datum, not a printed private struct, and `resolved` is a
;; renderer-independent rgba-color value.  Palette aliases are normalized by
;; palette-color at construction time, so `alias-used` is #f for every stored
;; color specification; `canonical-token` is the durable information.
(define (inspect-color color theme
                       #:owner-path [owner-path #f]
                       #:style-field [style-field #f])
  (unless (color-spec? color)
    (raise-argument-error 'inspect-color "color-spec?" color))
  (unless (color-theme? theme)
    (raise-argument-error 'inspect-color "color-theme?" theme))
  (unless (or (not owner-path) (and (list? owner-path) (andmap symbol? owner-path)))
    (raise-argument-error 'inspect-color "#f or list of symbols as #:owner-path" owner-path))
  (unless (or (not style-field) (symbol? style-field))
    (raise-argument-error 'inspect-color "#f or symbol? as #:style-field" style-field))
  (define normalized (normalize-color-spec color 'inspect-color))
  (define resolved (resolve-color-in-theme normalized theme))
  (make-immutable-hash
   (list
    (cons 'authored (color-spec->datum normalized))
    (cons 'kind (color-spec-kind normalized))
    (cons 'canonical-token (canonical-token-datum normalized theme))
    (cons 'alias-used #f)
    (cons 'role-resolution-chain (role-resolution-chain normalized theme))
    (cons 'resolved resolved)
    (cons 'resolved-hex (rgba-color->hex resolved))
    (cons 'resolved-rgba
          (vector (rgba-color-red resolved)
                  (rgba-color-green resolved)
                  (rgba-color-blue resolved)
                  (rgba-color-alpha resolved)))
    (cons 'effective-alpha (rgba-color-alpha resolved))
    (cons 'theme-id (color-theme-id theme))
    (cons 'theme-fingerprint (bytes->hex (color-theme-fingerprint theme)))
    (cons 'interpolation-space
          (and (mix-color? normalized) (mix-color-space normalized)))
    (cons 'alpha-mode
          (and (mix-color? normalized) (mix-color-alpha-mode normalized)))
    (cons 'owner-path owner-path)
    (cons 'style-field style-field))))

;; rgba-color->hex : rgba-color? -> string?
;; Formats one resolved color as #RRGGBBAA.  Including alpha makes a copied
;; literal explicit rather than silently turning a translucent color opaque.
(define (rgba-color->hex color)
  (unless (rgba-color? color)
    (raise-argument-error 'rgba-color->hex "rgba-color?" color))
  (string-append "#"
                 (channel->hex (rgba-color-red color))
                 (channel->hex (rgba-color-green color))
                 (channel->hex (rgba-color-blue color))
                 (channel->hex (* 255 (rgba-color-alpha color)))))


;;;
;;; Structural Explanation
;;;

(define (color-spec-kind color)
  (cond [(rgba-color? color) 'literal]
        [(palette-token? color) 'palette]
        [(role-token? color) 'role]
        [(series-color? color) 'series]
        [(color-expression? color) 'expression]
        [else (raise-argument-error 'color-spec-kind "color-spec?" color)]))

(define (canonical-token-datum color theme)
  (cond [(palette-token? color) `(palette ,(palette-token-key color))]
        [(role-token? color) `(role ,(role-token-key color))]
        [(series-color? color)
         (define series (theme-series theme))
         `(series ,(series-color-index color)
                  ,(and (pair? series)
                        (modulo (series-color-index color) (length series))))]
        [else #f]))

;; A role can name another role or occur inside a mix/alpha expression.  The
;; resolver has already rejected cycles at theme construction, but a `seen`
;; list keeps this display traversal bounded even when a custom theme repeats
;; a role along independent expression branches.
(define (role-resolution-chain color theme [seen '()])
  (cond
    [(role-token? color)
     (define key (role-token-key color))
     (if (member key seen)
         (list key)
         (cons key
               (role-resolution-chain (theme-ref theme key) theme (cons key seen))))]
    [(mix-color? color)
     (append (role-resolution-chain (mix-color-from color) theme seen)
             (role-resolution-chain (mix-color-to color) theme seen))]
    [(alpha-color? color)
     (role-resolution-chain (alpha-color-source color) theme seen)]
    [else '()]))

(define (channel->hex value)
  (define rounded (inexact->exact (round value)))
  (define digits (string-upcase (number->string rounded 16)))
  (if (= (string-length digits) 1)
      (string-append "0" digits)
      digits))

(define (bytes->hex value)
  (apply string-append
         (for/list ([byte (in-bytes value)])
           (channel->hex byte))))
