#lang racket/base

;;;
;;; SCENE-M Model Tests
;;;

;; Tests semantic LaTeX formula data, immutable string and option storage,
;; group participation, and existing affine and opacity animation behavior.


;;;
;;; Imports
;;;

(require rackunit
         (only-in "../private/group-visual.rkt"
                  group-visual-resolved-children)
         "../main.rkt")


(module+ test
  ; sampled-visual : scene? real? symbol? -> visual?
  ;;   Returns one top-level Visual from a sampled scene.
  (define (sampled-visual scene time id)
    (scene-state-ref (scene-sample scene time) id))

  ;; Formula modes and LaTeX options use the documented semantic values.

  (for ([mode
         (in-list '(inline display display-environment))])
    (check-true (formula-mode? mode)))

  (check-false (formula-mode? 'math))
  (check-true (latex-option? 'tightpage))
  (check-true (latex-option? "12pt"))
  (check-false (latex-option? 12))

  ;; The default constructor creates an affine and opacity-aware formula.

  ; pythagorean : formula-visual?
  ;;   Gives a centered display-style formula with default options.
  (define pythagorean
    (latex-formula "a^2+b^2=c^2" #:id 'pythagorean))

  (check-true (visual? pythagorean))
  (check-true (affine-visual? pythagorean))
  (check-true (opacity-visual? pythagorean))
  (check-true (formula-visual? pythagorean))
  (check-equal? (visual-id pythagorean) 'pythagorean)
  (check-equal? (visual-position pythagorean) origin)
  (check-equal? (visual-rotation pythagorean) 0)
  (check-equal? (visual-scale pythagorean) (vec2 1 1))
  (check-equal? (visual-opacity pythagorean) 1)
  (check-equal? (formula-visual-source pythagorean)
                "a^2+b^2=c^2")
  (check-true (immutable? (formula-visual-source pythagorean)))
  (check-equal? (formula-visual-mode pythagorean) 'display)
  (check-equal? (formula-visual-font-size pythagorean) 1)
  (check-equal? (formula-visual-preamble pythagorean) "")
  (check-equal? (formula-visual-document-class-options pythagorean)
                '())
  (check-equal? (formula-visual-preview-options pythagorean)
                '())
  (check-equal? (formula-visual-horizontal-alignment pythagorean)
                'center)
  (check-equal? (formula-visual-vertical-alignment pythagorean)
                'center)

  ;; Explicit source, mode, transform, opacity, options, and anchor data remain
  ;; semantic model values.

  ; integral : formula-visual?
  ;;   Gives a fully configured inline formula.
  (define integral
    (latex-formula "\\int_0^1 x^2\\,dx=\\frac{1}{3}"
                   #:id 'integral
                   #:center (vec2 3 -2)
                   #:rotation 1/4
                   #:scale (vec2 2 1/2)
                   #:opacity 3/4
                   #:mode 'inline
                   #:font-size 2/3
                   #:preamble "\\usepackage{amsmath}"
                   #:document-class-options
                   (list "12pt" 'fleqn)
                   #:preview-options
                   (list 'tightpage "lyx")
                   #:horizontal-alignment 'left
                   #:vertical-alignment 'baseline))

  (check-equal? (visual-position integral) (vec2 3 -2))
  (check-equal? (visual-rotation integral) 1/4)
  (check-equal? (visual-scale integral) (vec2 2 1/2))
  (check-equal? (visual-opacity integral) 3/4)
  (check-equal? (formula-visual-mode integral) 'inline)
  (check-equal? (formula-visual-font-size integral) 2/3)
  (check-equal? (formula-visual-preamble integral)
                "\\usepackage{amsmath}")
  (check-equal? (formula-visual-document-class-options integral)
                (list "12pt" 'fleqn))
  (check-equal? (formula-visual-preview-options integral)
                (list 'tightpage "lyx"))
  (check-equal? (formula-visual-horizontal-alignment integral) 'left)
  (check-equal? (formula-visual-vertical-alignment integral) 'baseline)
  (check-true (immutable? (formula-visual-preamble integral)))
  (check-true
   (immutable?
    (car (formula-visual-document-class-options integral))))
  (check-true
   (immutable?
    (cadr (formula-visual-preview-options integral))))

  ;; Mutable source, preamble, and option strings are copied.

  ; mutable-source : string?
  ;;   Gives mutable formula source for copy testing.
  (define mutable-source
    (string #\x #\^ #\2))

  ; mutable-preamble : string?
  ;;   Gives mutable preamble text for copy testing.
  (define mutable-preamble
    (string #\\ #\d #\e #\f))

  ; mutable-option : string?
  ;;   Gives a mutable document-class option for copy testing.
  (define mutable-option
    (string #\1 #\1 #\p #\t))

  ; mutable-preview-option : string?
  ;;   Gives a mutable Preview-package option for copy testing.
  (define mutable-preview-option
    (string #\l #\y #\x))

  ; copied-formula : formula-visual?
  ;;   Gives a formula constructed from mutable strings.
  (define copied-formula
    (latex-formula mutable-source
                   #:id 'copied-formula
                   #:preamble mutable-preamble
                   #:document-class-options
                   (list mutable-option)
                   #:preview-options
                   (list mutable-preview-option)))

  (string-set! mutable-source 0 #\y)
  (string-set! mutable-preamble 1 #\X)
  (string-set! mutable-option 0 #\9)
  (string-set! mutable-preview-option 0 #\X)
  (check-equal? (formula-visual-source copied-formula) "x^2")
  (check-equal? (formula-visual-preamble copied-formula) "\\def")
  (check-equal?
   (formula-visual-document-class-options copied-formula)
   (list "11pt"))
  (check-equal?
   (formula-visual-preview-options copied-formula)
   (list "lyx"))

  ;; Source replacement preserves every other semantic field.

  ; changed-source : formula-visual?
  ;;   Gives integral with only its LaTeX source replaced.
  (define changed-source
    (formula-visual-with-source integral "e^{i\\pi}+1=0"))

  (check-equal? (formula-visual-source changed-source)
                "e^{i\\pi}+1=0")
  (check-true (immutable? (formula-visual-source changed-source)))
  (check-equal? (visual-id changed-source) (visual-id integral))
  (check-equal? (visual-transform changed-source)
                (visual-transform integral))
  (check-equal? (visual-opacity changed-source)
                (visual-opacity integral))
  (check-equal? (formula-visual-mode changed-source)
                (formula-visual-mode integral))
  (check-equal? (formula-visual-font-size changed-source)
                (formula-visual-font-size integral))
  (check-equal? (formula-visual-preamble changed-source)
                (formula-visual-preamble integral))
  (check-equal? (formula-visual-document-class-options changed-source)
                (formula-visual-document-class-options integral))
  (check-equal? (formula-visual-preview-options changed-source)
                (formula-visual-preview-options integral))
  (check-equal? (formula-visual-horizontal-alignment changed-source)
                (formula-visual-horizontal-alignment integral))
  (check-equal? (formula-visual-vertical-alignment changed-source)
                (formula-visual-vertical-alignment integral))
  (check-equal? (formula-visual-source integral)
                "\\int_0^1 x^2\\,dx=\\frac{1}{3}")

  ; mutable-replacement : string?
  ;;   Gives mutable replacement source for immutable-update copy testing.
  (define mutable-replacement
    (string #\x #\+ #\1))

  ; copied-replacement : formula-visual?
  ;;   Gives integral with mutable replacement source copied into the result.
  (define copied-replacement
    (formula-visual-with-source integral mutable-replacement))

  (string-set! mutable-replacement 0 #\y)
  (check-equal? (formula-visual-source copied-replacement) "x+1")

  ;; Generic immutable updates preserve formula-specific data.

  ; moved-formula : formula-visual?
  ;;   Gives integral with only its position changed.
  (define moved-formula
    (visual-with-position integral (vec2 -4 1)))

  ; rotated-formula : formula-visual?
  ;;   Gives integral with only its rotation changed.
  (define rotated-formula
    (visual-with-rotation integral 3/4))

  ; scaled-formula : formula-visual?
  ;;   Gives integral with only its scale changed.
  (define scaled-formula
    (visual-with-scale integral (vec2 3 2)))

  ; faded-formula : formula-visual?
  ;;   Gives integral with only its opacity changed.
  (define faded-formula
    (visual-with-opacity integral 1/5))

  (for ([updated
         (in-list
          (list moved-formula
                rotated-formula
                scaled-formula
                faded-formula))])
    (check-true (formula-visual? updated))
    (check-equal? (visual-id updated) 'integral)
    (check-equal? (formula-visual-source updated)
                  (formula-visual-source integral))
    (check-equal? (formula-visual-mode updated)
                  (formula-visual-mode integral))
    (check-equal? (formula-visual-font-size updated)
                  (formula-visual-font-size integral))
    (check-equal? (formula-visual-preamble updated)
                  (formula-visual-preamble integral))
    (check-equal? (formula-visual-document-class-options updated)
                  (formula-visual-document-class-options integral))
    (check-equal? (formula-visual-preview-options updated)
                  (formula-visual-preview-options integral)))

  (check-equal? (visual-position moved-formula) (vec2 -4 1))
  (check-equal? (visual-rotation rotated-formula) 3/4)
  (check-equal? (visual-scale scaled-formula) (vec2 3 2))
  (check-equal? (visual-opacity faded-formula) 1/5)

  ;; Empty source is valid semantic data and does not require a TeX result.

  (check-equal?
   (formula-visual-source
    (latex-formula "" #:id 'empty-formula))
   "")

  ;; Multiline source remains intact because LaTeX source is not plain text.

  ; multiline-formula : formula-visual?
  ;;   Gives a formula containing an aligned environment on several lines.
  (define multiline-formula
    (latex-formula
     "\\begin{aligned}\nx+y&=3\\\\\nx-y&=1\n\\end{aligned}"
     #:id 'multiline-formula))

  (check-equal?
   (formula-visual-source multiline-formula)
   "\\begin{aligned}\nx+y&=3\\\\\nx-y&=1\n\\end{aligned}")

  ;; Constructor and update validation reject malformed semantic data.

  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula 42 #:id 'bad-source)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x" #:id 42)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-center
                              #:center 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-rotation
                              #:rotation +inf.0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-scale
                              #:scale 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-opacity
                              #:opacity -1)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-mode
                              #:mode 'math)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-size
                              #:font-size 0)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-preamble
                              #:preamble 42)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-options
                              #:document-class-options
                              (list "10pt" 11))))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-preview-options
                              #:preview-options
                              (list 'tightpage 11))))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'conflicting-size-options
                              #:document-class-options
                              (list "10pt" "12pt"))))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-horizontal
                              #:horizontal-alignment 'middle)))
  (check-exn exn:fail:contract?
             (lambda ()
               (latex-formula "x"
                              #:id 'bad-vertical
                              #:vertical-alignment 'middle)))
  (check-exn exn:fail:contract?
             (lambda ()
               (formula-visual-with-source integral 42)))

  ;; Formula Visuals participate in nested groups as ordinary affine children.

  ; local-formula : formula-visual?
  ;;   Gives one formula in coordinates local to a group.
  (define local-formula
    (latex-formula "x+y"
                   #:id 'local-formula
                   #:center (vec2 1 0)
                   #:rotation 1/5
                   #:scale (vec2 2 1/2)))

  ; formula-group : group-visual?
  ;;   Gives a rotated and uniformly scaled formula group.
  (define formula-group
    (group (list local-formula)
           #:id 'formula-group
           #:center (vec2 4 3)
           #:rotation 3/10
           #:scale 2))

  ; resolved-formula : formula-visual?
  ;;   Gives local-formula with inherited group rotation and scale.
  (define resolved-formula
    (car (group-visual-resolved-children formula-group)))

  (check-true (formula-visual? resolved-formula))
  (check-equal? (visual-id resolved-formula) 'local-formula)
  (check-equal? (visual-position resolved-formula)
                (affine-transform-apply-vector
                 (visual-transform formula-group)
                 (vec2 1 0)))
  (check-equal? (visual-rotation resolved-formula) 1/2)
  (check-equal? (visual-scale resolved-formula) (vec2 4 1))
  (check-equal? (formula-visual-source resolved-formula) "x+y")

  ;; Existing animation requests interpolate formula components independently.

  ; animated-formula : scene?
  ;;   Moves, rotates, scales, and fades one formula for two seconds.
  (define animated-formula
    (scene-play (scene-add (make-scene) pythagorean)
                (move-to pythagorean (vec2 4 -2))
                (rotate-to pythagorean 1)
                (scale-to pythagorean (vec2 2 1/2))
                (fade-to pythagorean 1/2)
                #:duration 2))

  ; midpoint : formula-visual?
  ;;   Gives the exact midpoint formula sample.
  (define midpoint
    (sampled-visual animated-formula 1 'pythagorean))

  (check-true (formula-visual? midpoint))
  (check-equal? (visual-position midpoint) (vec2 2 -1))
  (check-equal? (visual-rotation midpoint) 1/2)
  (check-equal? (visual-scale midpoint) (vec2 3/2 3/4))
  (check-equal? (visual-opacity midpoint) 3/4)
  (check-equal? (formula-visual-source midpoint)
                "a^2+b^2=c^2")

  ;; Fade-in introduces the complete formula at zero opacity before sampling.

  ; entering-formula : formula-visual?
  ;;   Gives a formula with a non-default final opacity.
  (define entering-formula
    (latex-formula "e^{i\\pi}+1=0"
                   #:id 'entering-formula
                   #:opacity 3/5))

  ; formula-entrance : scene?
  ;;   Fades the absent formula into the scene.
  (define formula-entrance
    (scene-play (make-scene)
                (move-to entering-formula (vec2 2 0))
                (fade-in entering-formula)
                #:duration 1))

  ; entrance-start : formula-visual?
  ;;   Gives the prepared zero-opacity start value.
  (define entrance-start
    (sampled-visual formula-entrance 0 'entering-formula))

  (check-equal? (visual-opacity entrance-start) 0)
  (check-equal? (formula-visual-source entrance-start)
                "e^{i\\pi}+1=0")
  (check-equal? (visual-position entrance-start) origin)
  (check-equal?
   (visual-opacity
    (sampled-visual formula-entrance 1 'entering-formula))
   3/5))
