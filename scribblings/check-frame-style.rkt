#lang racket/base
;; Documentation-only tests. No Animate/TeX/FFmpeg runtime is required.
(require rackunit rackunit/text-ui racket/file racket/list racket/runtime-path
         (only-in scribble/base title)
         (only-in scribble/core nested-flow-blocks paragraph? paragraph-style
                  paragraph-content style-name multiarg-element? multiarg-element-contents
                  element-content)
         (only-in scribble/decode decode)
         (only-in scribble/render render)
         (prefix-in latex: scribble/latex-render)
         "private/frame-style.rkt")
(define-runtime-path fixture "tests/frame-style-fixture.png")
(define (frames n)
  (for/list ([i (in-range n)])
    (manual-frame fixture 64 36 (format "~a s" i))))
(define (rows strip) (filter paragraph? (nested-flow-blocks strip)))
(define (cards row) (filter multiarg-element? (paragraph-content row)))
(define (row-name row) (style-name (paragraph-style row)))
(define suite
  (test-suite
   "Manual frame presentation"
   (test-case "three frames prefer a single row"
     (define rs (rows (manual-frame-strip (frames 3))))
     (check-equal? (length rs) 1)
     (check-equal? (row-name (car rs)) "AnimFrameRowThree")
     (check-equal? (length (cards (car rs))) 3))
   (test-case "five frames prefer a single row"
     (define rs (rows (manual-frame-strip (frames 5))))
     (check-equal? (length rs) 1)
     (check-equal? (row-name (car rs)) "AnimFrameRowFive")
     (check-equal? (length (cards (car rs))) 5))
   (test-case "each caption remains in the same card as its picture"
     (define cs (cards (car (rows (manual-frame-strip (frames 5))))))
     (check-equal? (map (lambda (c) (length (multiarg-element-contents c))) cs)
                   '(2 2 2 2 2))
     (check-equal?
      (map (lambda (c) (element-content (cadr (multiarg-element-contents c)))) cs)
      '(("0 s") ("1 s") ("2 s") ("3 s") ("4 s"))))
   (test-case "explicit columns preserve equal widths on an incomplete row"
     (define rs (rows (manual-frame-strip (frames 5) #:columns 2)))
     (check-equal? (map row-name rs) '("AnimFrameRowTwo" "AnimFrameRowTwo" "AnimFrameRowTwo"))
     (check-equal? (map (lambda (r) (length (cards r))) rs) '(2 2 1)))
   (test-case "one still and longer collections are supported"
     (check-equal? (row-name (car (rows (manual-frame-strip (frames 1))))) "AnimFrameRowOne")
     (check-equal? (map (lambda (r) (length (cards r)))
                       (rows (manual-frame-strip (frames 7)))) '(5 2)))
   (test-case "bad arguments are rejected"
     (check-exn exn:fail:contract? (lambda () (manual-frame-strip '())))
     (check-exn exn:fail:contract? (lambda () (manual-frame-strip (frames 3) #:columns 0)))
     (check-exn exn:fail:contract? (lambda () (manual-frame-strip (frames 3) #:columns 6)))
     (check-exn exn:fail:contract?
                (lambda () (manual-frame-strip (list (manual-frame fixture +nan.0 36 "bad"))))))
   (test-case "HTML includes images, captions, CSS and SVG-compatible classes"
     (define tmp (make-temporary-file "frame-style-html-~a" 'directory))
     (define before (file->bytes fixture))
     (dynamic-wind
       void
       (lambda ()
         (define doc (decode (list (title #:tag "frame-style-test" "Frame test")
                                   (manual-frame-strip (frames 5) #:note "Compare these frames."))))
         (render (list doc) (list "frames") #:dest-dir tmp)
         (define html (file->string (build-path tmp "frames.html")))
         (check-true (regexp-match? #rx"AnimFrameRowFive" html))
         (check-equal? (length (regexp-match* #rx"class=\"AnimFrameCard\"" html)) 5)
         (check-true (regexp-match? #rx"frame-style[.]css" html))
         (check-true (regexp-match? #rx"Compare these frames[.]" html))
         (check-equal? (file->bytes fixture) before))
       (lambda () (delete-directory/files tmp))))
   (test-case "LaTeX includes the width-aware row and one-pixel-equivalent rule"
     (define tmp (make-temporary-file "frame-style-tex-~a" 'directory))
     (dynamic-wind
       void
       (lambda ()
         (define doc (decode (list (title #:tag "frame-style-tex" "Frame test")
                                   (manual-frame-strip (frames 3)))))
         (render (list doc) (list "frames") #:dest-dir tmp #:render-mixin latex:render-mixin)
         (define tex (file->string (build-path tmp "frames.tex")))
         (check-true (regexp-match? #rx"AnimFrameRowThree" tex))
         (define addition (build-path tmp "frame-style.tex"))
         (check-true
          (or (regexp-match? #rx"0[.]75bp" tex)
              (and (regexp-match? #rx"frame-style[.]tex" tex)
                   (file-exists? addition)
                   (regexp-match? #rx"0[.]75bp" (file->string addition))))))
       (lambda () (delete-directory/files tmp))))))
(define (main) (unless (zero? (run-tests suite)) (exit 1)))
(module+ main (main))
(module+ test (main))
