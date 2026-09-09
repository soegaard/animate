#lang racket/base

;;;
;;; Built-in Animate Themes
;;;

;; Defines the complete light and dark theme snapshots from the authoritative
;; palette table. Role assignments are explicit semantic choices, not inverted
;; palette rules or mutable process-wide state.


;;;
;;; Imports and Exports
;;;

;; Imports
(require file/sha1
         (only-in racket/port call-with-output-bytes)
         "color-style.rkt"
         "color-token.rkt"
         "color-palette.rkt"
         "color-palette-data.rkt"
         "color-theme.rkt")

;; Exports
(provide animate-palette
         animate-palette-checksum
         animate-light-theme
         animate-dark-theme)


;;;
;;; Authoritative Built-in Palette
;;;

;; animate-palette : color-palette?
;;   The complete numerical palette shared by Animate's initial built-in themes.
(define animate-palette
  (color-palette
   #:id 'animate
   #:display-name "Animate"
   #:version animate-palette-version
   #:colors (make-immutable-hash animate-palette-colors)
   #:groups animate-palette-groups
   #:provenance 'animate-palette-v1))

;; animate-palette-checksum : immutable-bytes?
;;   Gives the deterministic swatch-table checksum for review and change control.
(define animate-palette-checksum
  (let ([appearance
         (list 'animate-palette-v1
               (for/list ([key (in-list (palette-keys animate-palette))])
                 (list key (palette-ref animate-palette key))))])
    (bytes->immutable-bytes
     (sha1-bytes
      (call-with-output-bytes
       (lambda (out) (write appearance out)))))))


;;;
;;; Built-in Theme Role Assignments
;;;

;; animate-light-theme : color-theme?
;;   The conservative initial theme, with an exact white semantic background.
(define animate-light-theme
  (color-theme
   #:id 'animate-light
   #:display-name "Animate light"
   #:palette animate-palette
   #:provenance 'animate-theme-v1
   #:roles
   (hash 'background (rgb-color #xFF #xFF #xFF)
         'foreground gray-e
         'muted gray-d
         'axis gray-d
         'grid (color-opacity gray-b 1/2)
         'surface (rgb-color #xFF #xFF #xFF)
         'surface-edge gray-c
         'accent aqua-d
         'highlight (color-opacity gold-b 1/4)
         'selection aqua-c
         'warning gold-d
         'success green-d
         'error red-d)
   #:series (list blue-d aqua-d green-d gold-d red-d maroon-d purple-d orange)))

;; animate-dark-theme : color-theme?
;;   The dark companion theme with explicit readable role assignments.
(define animate-dark-theme
  (color-theme
   #:id 'animate-dark
   #:display-name "Animate dark"
   #:palette animate-palette
   #:provenance 'animate-theme-v1
   #:roles
   (hash 'background (rgb-color #x12 #x17 #x1E)
         'foreground gray-a
         'muted gray-c
         'axis gray-b
         'grid (color-opacity gray-d 3/4)
         'surface gray-e
         'surface-edge gray-d
         'accent aqua-c
         'highlight (color-opacity gold-b 1/4)
         'selection aqua-b
         'warning gold-c
         'success green-c
         'error red-c)
   #:series (list blue-b aqua-b green-b gold-b red-b maroon-b purple-b peach)))
