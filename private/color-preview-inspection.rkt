#lang racket/base

;;;
;;; Preview Color Inspector Sections
;;;

;; This adapter turns pure color inspection reports into the existing immutable
;; inspector-document vocabulary.  It deliberately contains no GUI controls:
;; the preview window remains the only clipboard/eventspace owner.


;;;
;;; Imports and Exports
;;;

(require racket/list
         racket/match
         "color-diagnostics.rkt"
         "color-inspection.rkt"
         "color-palette.rkt"
         "color-style.rkt"
         "color-theme.rkt"
         "color-token.rkt"
         "inspector-document.rkt")

(provide color-theme-inspector-section
         color-inspection-rows)


;;;
;;; Shared Color Rows
;;;

;; color-inspection-rows : string? color-spec? color-theme?
;;                         [#:owner-path (or/c #f (listof symbol?))]
;;                         [#:style-field (or/c #f symbol?)]
;;                         -> (listof inspector-row?)
;; Makes rows that identify one field without making the field itself mutable.
(define (color-inspection-rows label color theme
                               #:owner-path [owner-path #f]
                               #:style-field [style-field #f])
  (define report
    (inspect-color color theme #:owner-path owner-path #:style-field style-field))
  (define token (hash-ref report 'canonical-token))
  (define token-action
    (and token
         (inspector-action
          'copy-color-token "Copy token expression"
          `(copy-text ,(token-expression token)) #t)))
  (define literal-action
    (inspector-action
     'copy-color-literal "Copy literal hex (non-themeable)"
     `(copy-text ,(hash-ref report 'resolved-hex)) #t))
  (append
   (list
    (inspector-row (format "~a authored specification" label)
                   (hash-ref report 'authored) 'info
                   (filter values (list token-action literal-action)))
    (inspector-row (format "~a kind" label) (hash-ref report 'kind) 'info '())
    (inspector-row (format "~a canonical token" label) token 'info '())
    (inspector-row (format "~a role-resolution chain" label)
                   (hash-ref report 'role-resolution-chain) 'info '())
    (inspector-row (format "~a resolved hex / RGBA" label)
                   (vector (hash-ref report 'resolved-hex)
                           (hash-ref report 'resolved-rgba))
                   'info '())
    (inspector-row (format "~a effective alpha" label)
                   (hash-ref report 'effective-alpha) 'info '())
    (inspector-row (format "~a interpolation" label)
                   (vector (hash-ref report 'interpolation-space)
                           (hash-ref report 'alpha-mode))
                   'info '()))
   (if owner-path
       (list (inspector-row (format "~a owning path / field" label)
                            (vector owner-path style-field) 'info '()))
       '())))


;;;
;;; Whole Theme Browser
;;;

;; color-theme-inspector-section : color-theme? -> inspector-section?
;; Includes all palette groups, fixed endpoints, semantic roles, and resolved
;; categorical series. The `content` field preserves grid metadata so a future
;; richer GUI can lay out the eight hue columns and five shade rows without
;; reverse-engineering labels from rows.
(define (color-theme-inspector-section theme)
  (unless (color-theme? theme)
    (raise-argument-error 'color-theme-inspector-section "color-theme?" theme))
  (define palette (color-theme-palette theme))
  (define palette-rows
    (append*
     (for/list ([group (in-list (palette-groups palette))])
       (append
        (list (inspector-row (format "palette group ~a" (car group))
                             (cadr group) 'info '()))
        (append*
         (for/list ([key (in-list (cadr group))])
           (short-color-rows (symbol->string key) (palette-color key) theme)))))))
  (define fixed-rows
    (append*
     (for/list ([entry (in-list fixed-endpoints)])
       (short-color-rows (symbol->string (car entry)) (cdr entry) theme))))
  (define role-rows
    (append*
     (for/list ([key (in-list (theme-role-keys theme))])
       (short-color-rows (format "role ~a" key) (role-color key) theme))))
  (define series-rows
    (append*
     (for/list ([index (in-range (length (theme-series theme)))])
       (short-color-rows (format "series ~a" index) (series-color index) theme))))
  (define diagnostic-rows
    (for/list ([diagnostic (in-list (color-theme-diagnostics theme))])
      (inspector-row
       (format "color diagnostic ~a" (hash-ref diagnostic 'kind))
       (hash-ref diagnostic 'message)
       (hash-ref diagnostic 'severity)
       '())))
  (inspector-section
   'colors-and-theme "Colors and theme"
   (append
    (list (inspector-row "theme ID" (color-theme-id theme) 'info '())
          (inspector-row "theme appearance fingerprint"
                         (bytes->hex (color-theme-fingerprint theme)) 'info '())
          (inspector-row "palette ID / version"
                         (vector (color-palette-id palette) (color-palette-version palette))
                         'info '())
          (inspector-row "copying a literal" "A copied literal hex is non-themeable."
                         'info '()))
    palette-rows fixed-rows role-rows series-rows diagnostic-rows)
   (hasheq 'hue-columns '(blue aqua green yellow gold red maroon purple)
           'shade-rows '(a b c d e)
           'palette-groups (palette-groups palette)
           'fixed-endpoints (map car fixed-endpoints)
           'theme-id (color-theme-id theme))))

(define (short-color-rows label color theme)
  (define report (inspect-color color theme))
  (define token (hash-ref report 'canonical-token))
  (list
   (inspector-row label
                  (vector (hash-ref report 'resolved-hex)
                          (hash-ref report 'authored))
                  'info
                  (append
                   (if token
                       (list (inspector-action
                              'copy-color-token "Copy token expression"
                              `(copy-text ,(token-expression token)) #t))
                       '())
                   (list (inspector-action
                          'copy-color-literal "Copy literal hex (non-themeable)"
                          `(copy-text ,(hash-ref report 'resolved-hex)) #t))))))

(define (token-expression token)
  (match token
    [`(palette ,key) (format "(palette-color '~a)" key)]
    [`(role ,key) (format "(role-color '~a)" key)]
    [`(series ,index ,_canonical-index) (format "(series-color ~a)" index)]
    [_ (error 'token-expression "unexpected canonical token: ~e" token)]))

(define fixed-endpoints
  (list (cons 'black (rgb-color 0 0 0))
        (cons 'white (rgb-color 255 255 255))
        (cons 'pure-red (rgb-color 255 0 0))
        (cons 'pure-green (rgb-color 0 255 0))
        (cons 'pure-blue (rgb-color 0 0 255))
        (cons 'pure-cyan (rgb-color 0 255 255))
        (cons 'pure-magenta (rgb-color 255 0 255))
        (cons 'pure-yellow (rgb-color 255 255 0))))

(define (bytes->hex value)
  (apply string-append
         (for/list ([byte (in-bytes value)])
           (define digits (string-upcase (number->string byte 16)))
           (if (= (string-length digits) 1) (string-append "0" digits) digits))))
