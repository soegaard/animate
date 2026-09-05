#lang racket/base

;;;
;;; SCENE-CR Formula Selection and Styling Tests
;;;

(require racket/class
         rackunit
         (only-in pict filled-rectangle pict? pict->bitmap)
         (only-in "../private/latex-formula-pict-renderer.rkt"
                  formula-visual-base-pict->pict)
         "../main.rkt")

(define (assembly-at x-position)
  (formula-assembly
   (list
    (latex-formula-part "x" #:name 'x #:center (vec2 x-position 0))
    (latex-formula-part " = " #:name 'equals #:center (vec2 (+ x-position 1) 0))
    (latex-formula-part "y" #:name 'y #:center (vec2 (+ x-position 2) 0)))
   #:id 'equation))

(define (part-formula formula name)
  (formula-part-formula (formula-assembly-visual-ref formula name)))

;; bitmap-has-rgb? : bitmap% byte? byte? byte? -> boolean?
;; Formula glyph interiors include fully opaque pixels, so one exact colour
;; sample proves that the SVG renderer honoured the semantic paint rather than
;; merely retaining it in the Formula Visual model.
(define (bitmap-has-rgb? bitmap red green blue)
  (define width (send bitmap get-width))
  (define height (send bitmap get-height))
  (define pixels (make-bytes (* width height 4)))
  (send bitmap get-argb-pixels 0 0 width height pixels)
  (for/or ([index (in-range 0 (bytes-length pixels) 4)])
    (and (= (bytes-ref pixels index) 255)
         (= (bytes-ref pixels (+ index 1)) red)
         (= (bytes-ref pixels (+ index 2)) green)
         (= (bytes-ref pixels (+ index 3)) blue))))

(module+ test
  (define base (assembly-at -1))

  ;; Selection returns the ordinary nested Visual path that attention and
  ;; existing style requests already understand.
  (check-equal? (formula-select base 'x) '(equation x))
  (check-true (visual-path? (formula-select base 'equals)))

  ;; Functional styling preserves the assembly identity, untouched parts, and
  ;; each selected formula's exact TeX source while adding a colour capability.
  (define highlighted
    (formula-color base 'x "gold"))
  (check-equal? (visual-id highlighted) 'equation)
  (check-true (fill-color-visual? (part-formula highlighted 'x)))
  (check-equal? (visual-fill-color (part-formula highlighted 'x)) "gold")
  (check-false (fill-color-visual? (part-formula highlighted 'equals)))
  (check-equal? (formula-visual-source (part-formula highlighted 'x)) "x")
  ;; Ordinary LaTeX Picts and tagged SVG fragments each have a distinct
  ;; rendering path. Exercise the former with a supplied Pict so the test does
  ;; not require the optional latex-pict/Poppler installation.
  (check-true
   (bitmap-has-rgb?
    (pict->bitmap
     (formula-visual-base-pict->pict
      (part-formula highlighted 'x)
      (make-camera)
      (filled-rectangle 40 40 #:draw-border? #f))
     'aligned)
    255 215 0))

  ;; A multi-part style and a construction-style map both use the existing
  ;; semantic part names. Opacity remains an ordinary per-part visual property.
  (define emphasized
    (formula-style highlighted '(x y) #:color "firebrick" #:opacity 3/4))
  (check-equal? (visual-fill-color (part-formula emphasized 'x)) "firebrick")
  (check-equal? (visual-fill-color (part-formula emphasized 'y)) "firebrick")
  (check-equal? (visual-opacity (part-formula emphasized 'x)) 3/4)
  (define mapped
    (formula-color-map base (hash 'x "red" 'y "blue")))
  (check-equal? (visual-fill-color (part-formula mapped 'x)) "red")
  (check-equal? (visual-fill-color (part-formula mapped 'y)) "blue")

  ;; Styled fragments participate in the established nested style animation.
  ;; Its interior samples use semantic RGBA interpolation and the exact target
  ;; spelling is retained at the endpoint.
  (define recoloured
    (scene-play
     (scene-add (make-scene) highlighted)
     (fill-color-to '(equation x) "blue")
     #:duration 2))
  (check-equal?
   (visual-fill-color (part-formula (scene-visual-at recoloured 'equation 1) 'x))
   (rgba-color 255/2 215/2 255/2 1))
  (check-equal?
   (visual-fill-color (part-formula (scene-visual-at recoloured 'equation 2) 'x))
   "blue")

  ;; Equal semantic paint remains attached to a matching fragment as it moves;
  ;; the formula transition compiler uses one stable styled layer. A changed
  ;; colour keeps the established cross-fade fallback and installs the exact
  ;; destination style at the endpoint.
  (define moving-source (formula-color (assembly-at -1) 'x "red"))
  (define moving-destination (formula-color (assembly-at 1) 'x "red"))
  (define moved
    (scene-play
     (scene-add (make-scene) moving-source)
     (transform-matching-parts moving-source moving-destination)
     #:duration 2))
  (define interior
    (part-formula
     (scene-visual-at moved 'equation 1)
     '__formula-transition-0))
  (check-equal? (visual-fill-color interior) "red")
  (check-equal?
   (visual-fill-color (part-formula (scene-visual-at moved 'equation 2) 'x))
   "red")

  ;; #:color-map applies after tagged TeX has created its stable fragment
  ;; namespace and does not invalidate its SVG renderer path.
  (define tagged
    (tagged-formula
     #:id 'tagged-equation #:color-map (hash 'x "purple")
     (formula-fragment 'x "x")
     (formula-fragment 'equals " = ")
     (formula-fragment 'y "y")))
  (check-equal? (visual-fill-color (part-formula tagged 'x)) "purple")
  (define tagged-pict (scene->pict (scene-add (make-scene) tagged) 0))
  (check-true (pict? tagged-pict))
  ;; dvisvgm SVG normally paints its paths black. This pixel-level assertion
  ;; protects the renderer-specific CSS override used by styled fragments.
  (check-true (bitmap-has-rgb? (pict->bitmap tagged-pict 'aligned)
                               160 32 240))

  (check-exn exn:fail:contract?
             (lambda () (formula-select base 'missing)))
  (check-exn exn:fail:contract?
             (lambda () (formula-style base 'x)))
  (check-exn exn:fail:contract?
             (lambda () (formula-color-map base (hash 'missing "red")))))
