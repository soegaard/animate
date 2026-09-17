#lang racket/base

;;;
;;; Mathematical Gallery Descriptions
;;;
;; Describes independent demonstration plates and sequential presentation variants.
;; This is catalogue data, not an algebraic case tree or a second scene evaluator.

;;;
;;; Imports and Exports
;;;
(require (only-in racket/list append-map remove-duplicates)
         "../../main.rkt")
(provide make-gallery-view gallery-view? gallery-view-id gallery-view-title
         gallery-view-caption gallery-view-api gallery-view-plan gallery-view-tree?
         gallery-view-provenance? gallery-view-recipe-call gallery-view-layout-family
         make-gallery-plate gallery-plate? gallery-plate-id gallery-plate-chapter
         gallery-plate-title gallery-plate-summary gallery-plate-views
         gallery-entry? gallery-entry-plate gallery-entry-view gallery-entry-start
         gallery-entry-end gallery-entries gallery-duration gallery-settle-time
         gallery-gap-time gallery-safe-id?)

;;;
;;; Validated Immutable Records
;;;
(struct gallery-view (id title caption api plan tree? provenance? recipe-call layout-family)
  #:transparent)
;; gallery-view is one replay of ordinary checked mathematics.
;;  - id  symbol?  plate-local, filename-safe identity; independent of worker count.
;;  - title  immutable-string?  short variant heading, or empty for a single replay.
;;  - caption  immutable-string?  mathematical explanation; not verification evidence.
;;  - api  (listof symbol?)  relevant public constructs in intentional display order.
;;  - plan  presentation-plan?  original mathematical states and deterministic phases.
;;  - tree?  boolean?  whether a compile-time hierarchy inspector is shown alongside.
;;  - provenance?  boolean?  whether one checked copy witness is shown as a gallery-only panel.
;;  - recipe-call  (or/c immutable-string? #f)  actual optional recipe invocation label.
;;  - layout-family  (or/c symbol? #f)  replays that must share one gallery body contract.
(struct gallery-plate (id chapter title summary views) #:transparent)
;; gallery-plate is a named independent demonstration, never a mathematical branch.
;;  - id  symbol?  globally unique, filename-safe plate name.
;;  - chapter  symbol?  one registry chapter identity.
;;  - title  immutable-string?  human-readable demonstration name.
;;  - summary  immutable-string?  catalogue explanation, not a proof certificate.
;;  - views  (nonempty-listof gallery-view?)  chronological replays with unique local ids.
(struct gallery-entry (plate view start end) #:transparent)
;; gallery-entry schedules one variant without evaluating or sampling mathematics.
;;  - plate  gallery-plate?  catalogue owner.
;;  - view  gallery-view?  replayed plan; each replay is fitted independently.
;;  - start  nonnegative-real?  absolute start of its ordinary math plan.
;;  - end  positive-real?  exclusive end after the final readable hold and separator.

; gallery-settle-time : exact-nonnegative-rational?
;;   Adds reading time after the native plan's own final hold.
(define gallery-settle-time 6/5)

; gallery-gap-time : exact-nonnegative-rational?
;;   Separates unrelated plates with a clean blank frame interval.
(define gallery-gap-time 2/5)

; gallery-safe-id? : any/c -> boolean?
;;   Recognizes stable symbols that also make unambiguous portable filenames.
(define (gallery-safe-id? id)
  (and (symbol? id) (and (regexp-match? #px"^[a-z][a-z0-9-]*$" (symbol->string id)) #t)))

; short-text : symbol? any/c -> immutable-string?
;;   Freezes a bounded, single-line gallery heading or caption.
(define (short-text who text)
  (unless (and (string? text) (<= (string-length text) 200)
               (not (regexp-match? #rx"[\r\n]" text)))
    (raise-argument-error who "single-line string of at most 200 characters" text))
  (string->immutable-string text))

; make-gallery-view : symbol? string? presentation-plan? #:caption string?
;   [#:api (listof symbol?)] [#:tree? boolean?] [#:provenance? boolean?]
;   [#:recipe-call (or/c string? #f)] [#:layout-family (or/c symbol? #f)] -> gallery-view?
;;   Creates one validated replay, keeping its original mathematical plan intact.
(define (make-gallery-view id title plan #:caption caption #:api [api '()] #:tree? [tree? #f]
                           #:provenance? [provenance? #f] #:recipe-call [recipe-call #f]
                           #:layout-family [layout-family #f])
  (unless (gallery-safe-id? id) (raise-argument-error 'make-gallery-view "gallery-safe-id?" id))
  (unless (presentation-plan? plan) (raise-argument-error 'make-gallery-view "presentation-plan?" plan))
  (unless (and (list? api) (andmap symbol? api))
    (raise-argument-error 'make-gallery-view "list of API symbols" api))
  (unless (boolean? tree?) (raise-argument-error 'make-gallery-view "boolean?" tree?))
  (unless (boolean? provenance?)
    (raise-argument-error 'make-gallery-view "boolean? as #:provenance?" provenance?))
  (unless (or (not recipe-call) (and (string? recipe-call) (not (regexp-match? #rx"[\r\n]" recipe-call))))
    (raise-argument-error 'make-gallery-view "#f or a single-line recipe call" recipe-call))
  (unless (or (not layout-family) (gallery-safe-id? layout-family))
    (raise-argument-error 'make-gallery-view "#f or gallery-safe-id? as #:layout-family" layout-family))
  (gallery-view id (short-text 'make-gallery-view title) (short-text 'make-gallery-view caption)
                (for/list ([name (in-list api)]) name) plan tree? provenance?
                (and recipe-call (short-text 'make-gallery-view recipe-call)) layout-family))

; make-gallery-plate : symbol? symbol? string? string? (listof gallery-view?) -> gallery-plate?
;;   Creates one independently selectable plate with uniquely named ordered variants.
(define (make-gallery-plate id chapter title summary views)
  (unless (and (gallery-safe-id? id) (gallery-safe-id? chapter))
    (raise-arguments-error 'make-gallery-plate "safe plate and chapter names" "id" id "chapter" chapter))
  (unless (and (list? views) (pair? views) (andmap gallery-view? views)
               (= (length views) (length (remove-duplicates (map gallery-view-id views)))))
    (raise-argument-error 'make-gallery-plate "nonempty list of uniquely named gallery views" views))
  (gallery-plate id chapter (short-text 'make-gallery-plate title)
                 (short-text 'make-gallery-plate summary)
                 (for/list ([view (in-list views)]) view)))

; gallery-entries : (listof gallery-plate?) -> (listof gallery-entry?)
;;   Orders views and computes exact global offsets without combining their mathematics.
(define (gallery-entries plates)
  (unless (and (list? plates) (andmap gallery-plate? plates)
               (= (length plates) (length (remove-duplicates (map gallery-plate-id plates)))))
    (raise-argument-error 'gallery-entries "ordered list of uniquely named plates" plates))
  (define-values (_end reversed)
    (for*/fold ([start 0] [entries '()]) ([plate (in-list plates)]
                                        [view (in-list (gallery-plate-views plate))])
      (define end (+ start (plan-duration (gallery-view-plan view))
                     gallery-settle-time gallery-gap-time))
      (values end (cons (gallery-entry plate view start end) entries))))
  (reverse reversed))

; gallery-duration : (listof gallery-plate?) -> nonnegative-real?
;;   Reports the duration of a selection before typesetting or scene construction.
(define (gallery-duration plates)
  (for/sum ([entry (in-list (gallery-entries plates))])
    (- (gallery-entry-end entry) (gallery-entry-start entry))))
