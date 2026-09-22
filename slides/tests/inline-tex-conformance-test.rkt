#lang racket/base

;;;
;;; Inline TeX Conformance Matrix
;;;

;; Real backend integration coverage complementing the pure parser tests.  It
;; derives built-in surface cases from the layout catalogue rather than keeping
;; an error-prone title/body whitelist.

(require rackunit
         racket/list
         racket/class
         (only-in racket/draw color% make-font)
         (only-in pict pict? pict-ascent pict-descent pict-height)
         "../../text-content.rkt"
         "../../private/inline-tex-pict.rkt"
         "../main.rkt"
         "../render.rkt"
         "../pict.rkt"
         "../private/data.rkt"
         "../private/sample.rkt")

(provide tests)

(define sample-source
  "Æøå: $x_0$.")

(define (all-text-slots layout-name alignment)
  (for/hash ([spec (in-list (layout-slots (layout-ref layout-name)))])
    (values (slot-spec-name spec)
            (slot-content sample-source #:align alignment))))

(define (frame-has-inline-tex? prepared)
  (for/or ([leaf (in-list (frame-value-leaves (sample-slide prepared 0)))])
    (hash-ref (asset-metadata (frame-leaf-asset leaf)) 'inline-tex? #f)))

(define tests
  (test-suite
   "inline TeX conformance matrix"
   (test-case "every built-in text surface is derived from layout specifications"
     (for* ([theme (in-list (list lecture-light lecture-dark))]
            [slide-format (in-list (list widescreen portrait))]
            [alignment (in-list '(left center right))]
            [layout-name (in-list (layout-names))])
       (define source
         (make-slide #:id layout-name #:layout layout-name
                     #:slots
                     (hash-set (all-text-slots layout-name alignment)
                               'footer
                               (slot-content "f: $x$."
                                             #:align alignment))))
       (define prepared (prepare-slide! source #:theme theme #:format slide-format))
       (check-true (frame-has-inline-tex? prepared)
                   (format "~a/~a/~a/~a"
                           (slide-theme-id theme) (slide-format-id slide-format)
                           alignment layout-name))
       (check-true (pict? (slide->pict prepared)))))
   (test-case "explicit, literal, display, bullets, and semantic children share the path"
     (define content
       (inline-text "At " (tex-span "x_0" #:plain "x zero")
                    ", the price $5 is literal."))
     (check-equal? (text-content->plain content) "At x zero, the price $5 is literal.")
     (define source
       (make-slide #:layout 'title+body
                   #:slots
                   (hash
                    'title (slot-content content #:align 'center)
                    'body
                    (semantic-group #:width 8 #:height 4
                      (semantic-part 'paragraph
                                     (paragraph-content "Before $$\\sum_{i=1}^n i$$ after")
                                     #:x 0 #:y 0 #:width 8 #:height 2 #:fit 'natural)
                      (semantic-part 'list
                                     (bullets
                                      [one (literal-text "Show $x_0$ literally")]
                                      [two "Then use $x_0$."])
                                     #:x 0 #:y 2 #:width 8 #:height 2 #:fit 'natural))
                    'footer "Footer $h\\to0$.")))
     (define prepared (prepare-slide! source #:theme lecture-dark #:format portrait))
     (check-true (pict? (slide->pict prepared)))
     (check-true
      (for/or ([leaf (in-list (frame-value-leaves (sample-slide prepared 0)))])
        (define path (frame-leaf-path leaf))
        (and (>= (length path) 2)
             (equal? (take path 2) '(body paragraph))))))
   (test-case "measured display blocks and tall inline TeX retain Pict baseline metrics"
     (define font (make-font #:size 24 #:size-in-pixels? #t))
     (define color (make-object color% 240 240 240))
     (define prepared
       (prepare-inline-text
        (parse-inline-text "$$\\frac{1}{2}$$")
        font color 24 480 6/5 'left))
     (define picture (prepared-inline-text-pict prepared))
     (check-equal? (prepared-inline-text-line-count prepared) 1)
     (check-true (> (prepared-inline-text-descent prepared) 0))
     (check-= (+ (pict-ascent picture) (pict-descent picture))
              (pict-height picture) 1e-6)
     (check-exn exn:fail?
                (lambda ()
                  (prepare-inline-text
                   (parse-inline-text "$\\sum_{i=1}^{100000000} i$")
                   font color 24 1 6/5 'left))))))

(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests tests))
    (error 'inline-tex-conformance-test "failed")))
