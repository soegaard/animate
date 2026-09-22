#lang racket/base

;;;
;;; Inline TeX Slide Integration Tests
;;;

;; Uses the real formula adapter to cover every slide text surface. The parser
;; itself remains covered by inline-tex-content-test without native effects.

(require rackunit
         racket/list
         "../../main.rkt"
         "../main.rkt"
         "../render.rkt"
         "../pict.rkt"
         "../scene.rkt"
         "../private/data.rkt"
         "../../private/inline-tex-pict.rkt"
         "../private/sample.rkt"
         "helpers.rkt"
         (only-in pict pict?))

(provide tests)

(define (text-slots layout-name)
  (for/hash ([spec (in-list (layout-slots (layout-ref layout-name)))])
    (values (slot-spec-name spec)
            "For $x_0$, $\\frac{1}{2}$ is a value.")))

(define tests
  (test-suite
   "real inline TeX slide preparation"
   (test-case "plain strings retain the preparation-free path"
     (define source
       (slide #:layout 'title
         [title "Plain prose"]
         [subtitle "No formula process is needed."]))
     (check-true (pict? (slide->pict source))))
   (test-case "every built-in text slot accepts inline TeX"
     (for ([layout-name (in-list (layout-names))])
       (define source
         (make-slide #:id layout-name #:layout layout-name
                     #:slots (hash-set (text-slots layout-name)
                                       'footer
                                       "$x$")))
       (define prepared (prepare-slide! source #:theme lecture-dark))
       (check-true (prepared-slide? prepared) (symbol->string layout-name))
       (check-true (pict? (slide->pict prepared))
                   (symbol->string layout-name))))
   (test-case "paragraphs, bullets, replacements, and custom roles share one path"
     (define custom
       (layout #:id 'inline-tex-custom
               #:slots (list (slot-spec 'heading #:required? #t #:role 'title)
                             (slot-spec 'proof #:required? #t #:role 'body))
               #:arrange
               (vbox (region 'heading #:basis 'content)
                     (region 'proof #:grow 1))))
     (define source
       (build-slide
        (slide #:layout custom
          [heading (inline-text "Why " (tex-span "x_0" #:plain "x zero") "?")]
          [proof
           (bullets
            [first (paragraph-content "For $h\\neq0$, $x_0+h$ is distinct.")]
            [second "Price: \\$5 and $\\sqrt{x}$ are both supported."])])
        #:initial 'hidden
        (beat 'replace #:duration 1
              (reveal-slot 'heading)
              (replace-content
               'proof
               "A replacement has $\\sum_{i=1}^n i$ before it is visible."))))
     (define prepared (prepare-slide! source))
     (define leaves (frame-value-leaves (sample-slide prepared 1/2)))
     (check-true (andmap (lambda (leaf) (asset? (frame-leaf-asset leaf))) leaves))
     (check-not-false
      (for/or ([leaf (in-list leaves)])
        (hash-ref (asset-metadata (frame-leaf-asset leaf)) 'inline-tex? #f)))
     (check-true (pict? (slide->pict prepared #:at 1/2)))
     (define scene (slide->scene prepared))
     (check-true (pict? (scene-state->pict (scene-sample scene 1/2)
                                            #:camera (scene-camera-at scene 1/2)))))
   (test-case "unprepared TeX requires the explicit effects boundary"
     (define source
       (slide #:layout 'title [title "Find $x_0$"]))
     (check-exn
      (lambda (value)
        (and (exn:fail:slides? value)
             (eq? (exn:fail:slides-code value) 'preparation-required)))
      (lambda () (slide->pict source))))
   (test-case "prepared text never typesets or reflows during frame sampling"
     (define source
       (build-slide
        (slide #:layout 'title
          [title "A fraction $\\frac{1}{2}$ has a real baseline."]
          [subtitle "The same $x_0$ survives a reveal."])
        #:initial 'hidden
        (beat 'show #:duration 1
              (reveal-slot 'title)
              (reveal-slot 'subtitle))))
     (define preparations 0)
     (define prepared
       (parameterize
           ([current-inline-tex-preparation-observer
             (lambda (_kind _value) (set! preparations (add1 preparations)))])
         (prepare-slide! source)))
     (check-true (> preparations 0))
     (parameterize
         ([current-inline-tex-preparation-observer
           (lambda (_kind _value)
             (error 'inline-tex-test "frame sampling must not prepare TeX"))])
       (check-true (pict? (slide->pict prepared #:at 1/2)))
       (define scene (slide->scene prepared))
       (check-true
        (pict? (scene-state->pict (scene-sample scene 1/2)
                                  #:camera (scene-camera-at scene 1/2))))))
   (test-case "hidden malformed replacement is diagnosed during preparation"
     (define source
       (build-slide
        (slide #:layout 'title [title "Safe"])
        #:initial 'hidden
        (beat 'bad #:duration 1
              (replace-content 'title "Broken $x_0"))))
     (check-exn
      (lambda (value)
        (and (exn:fail:slides? value)
             (eq? (exn:fail:slides-code value) 'inline-math-syntax)))
      (lambda () (prepare-slide! source))))))

(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests tests))
    (error 'inline-tex-test "failed")))
