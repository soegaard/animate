#lang racket/base

;; Every direct color literal in a shipped source example must be accepted by
;; Animate's deterministic color vocabulary. This scans source text rather than
;; a platform drawing API, so a missing name fails before a GUI backend happens
;; to interpret it differently on another machine.

(require rackunit
         racket/file
         racket/path
         racket/runtime-path
         racket/string
         "../private/color-style.rkt")

(define-runtime-path examples-directory "../examples")

;; This is the complete literal-only color keyword vocabulary used by shipped
;; examples. Keep color values that are expressions out of this source scanner;
;; their constructors validate them normally. The two syntax patterns below
;; deliberately cover both supported example languages.
(define color-keyword-names
  '("fill"
    "stroke"
    "color"
    "background"
    "border-color"
    "cursor-style"
    "axes-stroke"
    "connector-stroke"
    "edge-stroke"
    "emission"
    "grid-stroke"
    "guide-stroke"
    "secant-stroke"
    "specular-color"
    "vertex-fill"
    "vertex-stroke"
    "wireframe-color"))

(define color-keyword-alternation (string-join color-keyword-names "|"))

(define racket-color-keyword-literal-rx
  (pregexp
   (string-append
    "#:(?:" color-keyword-alternation ")\\s*\\\"([^\\\"]*)\\\"")))

(define rhombus-color-keyword-literal-rx
  (pregexp
   (string-append
    "~#\\{(?:" color-keyword-alternation ")\\}\\s*:\\s*\\\"([^\\\"]*)\\\"")))

(define (example-source-paths)
  (sort
   (for/list ([path (in-list (find-files file-exists? examples-directory))]
              #:when (member (path-get-extension path) '(#".rkt" #".rhm")))
     path)
   path<?))

(define (source-color-literals extension source)
  (define pattern
    (cond [(equal? extension #".rkt") racket-color-keyword-literal-rx]
          [(equal? extension #".rhm") rhombus-color-keyword-literal-rx]
          [else
           (raise-argument-error
            'source-color-literals
            "#\".rkt\" or #\".rhm\" source extension"
            extension)]))
  (regexp-match* pattern source #:match-select cadr))

(define (check-source-color-literals! extension source source-name)
  (for ([literal (in-list (source-color-literals extension source))])
    (color-spec->rgba-color literal)))

(module+ test
  ;; Tiny syntax fixtures prove the language-specific scanners find the same
  ;; public color argument vocabulary, including cursor-style. A made-up name
  ;; must fail in either syntax before this test ever reaches rendering.
  (check-equal?
   (source-color-literals
    #".rkt"
    "(circle #:fill \"crimson\" #:stroke \"indigo\")\n(typewrite t #:cursor-style \"tomato\")")
   '("crimson" "indigo" "tomato"))
  (check-equal?
   (source-color-literals
    #".rhm"
    "circle(~#{fill}: \"crimson\", ~#{stroke}: \"indigo\")\ntypewrite(t, ~#{cursor-style}: \"tomato\")")
   '("crimson" "indigo" "tomato"))
  (for ([fixture (in-list
                 (list (cons #".rkt" "(circle #:fill \"not-an-animate-color\")")
                       (cons #".rhm" "circle(~#{stroke}: \"not-an-animate-color\")")))])
    (check-exn
     exn:fail?
     (lambda ()
       (check-source-color-literals! (car fixture) (cdr fixture) 'fixture))))

  (define paths (example-source-paths))
  (check-true (pair? paths))
  (check-true (ormap (lambda (path) (equal? (path-get-extension path) #".rkt")) paths))
  (check-true (ormap (lambda (path) (equal? (path-get-extension path) #".rhm")) paths))
  (for ([path (in-list paths)])
    (check-not-exn
     (lambda ()
       (check-source-color-literals!
        (path-get-extension path) (file->string path) path))
     (format "~a uses an unsupported literal color" path))))
