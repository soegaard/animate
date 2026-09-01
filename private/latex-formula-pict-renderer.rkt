#lang racket/base

;;;
;;; LaTeX Formula Pict Renderer
;;;

;; Adapts semantic formula Visuals to Picts through the latex-pict package.
;; Loading and external TeX execution remain outside the semantic model.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in pict
                  blank
                  pict?
                  scale)
         "anchored-pict.rkt"
         "camera.rkt"
         "formula-visual.rkt"
         "pict-renderer.rkt"
         "renderer-resources.rkt"
         "visual-model.rkt")

;; Exports
(provide (struct-out latex-formula-pict-renderer)
         default-latex-formula-pict-renderer)


;;;
;;; Renderer Data
;;;

(struct latex-formula-pict-renderer (appearance-cache)
  #:transparent
  #:methods gen:pict-renderer
  [(define (pict-renderer-supports? _renderer visual)
     (formula-visual? visual))
   (define (pict-renderer-render renderer visual camera)
     (formula-visual->pict visual
                            camera
                            (latex-formula-pict-renderer-appearance-cache renderer)))])

;; latex-formula-pict-renderer typesets semantic formula Visuals through
;; latex-pict and returns centered local Pict geometry.

; default-latex-formula-pict-renderer : pict-renderer?
;;   Gives the built-in LaTeX formula renderer.
(define default-latex-formula-pict-renderer
  (latex-formula-pict-renderer
   (make-renderer-resource-cache #:max-entries 128)))


;;;
;;; Formula Conversion
;;;

; formula-visual->pict : formula-visual? camera? renderer-resource-cache? -> pict?
;;   Typesets one formula and applies its semantic size, anchor, and transform.
(define (formula-visual->pict visual camera appearance-cache)
  (formula-visual->pict/cached-using visual
                                     camera
                                     appearance-cache
                                     typeset-formula))

; formula-visual->pict/cached-using : formula-visual? camera?
;                                      renderer-resource-cache?
;                                      (-> formula-visual? pict?) -> pict?
;; Caches the complete local appearance. Position and opacity are intentionally
;; absent from the key because scene placement and cellophane occur later.
(define (formula-visual->pict/cached-using visual camera appearance-cache typesetter)
  (unless (renderer-resource-cache? appearance-cache)
    (raise-argument-error
     'formula-visual->pict/cached-using
     "renderer-resource-cache?"
     appearance-cache))
  (renderer-resource-cache-ref!
   appearance-cache
   (list 'latex-formula (formula-appearance-cache-key visual camera))
   (lambda ()
     ;; Formula Picts can be vector-backed; an entry-count bound avoids forcing
     ;; an additional rasterization solely to estimate bytes.
     (values (formula-visual->pict/using visual camera typesetter) 0))))

; formula-appearance-cache-key : formula-visual? camera? -> list?
(define (formula-appearance-cache-key visual camera)
  (list (formula-visual-source visual)
        (formula-visual-mode visual)
        (formula-visual-font-size visual)
        (formula-visual-preamble visual)
        (formula-visual-document-class-options visual)
        (formula-visual-preview-options visual)
        (formula-visual-horizontal-alignment visual)
        (formula-visual-vertical-alignment visual)
        (visual-scale visual)
        (visual-rotation visual)
        (camera-scale camera)))

; formula-visual->pict/using : formula-visual? camera?
;                              (-> formula-visual? pict?)
;                              -> pict?
;;   Converts one formula with an explicitly supplied typesetting procedure.
(define (formula-visual->pict/using visual camera typesetter)
  (unless (formula-visual? visual)
    (raise-argument-error
     'formula-visual->pict/using
     "formula-visual?"
     visual))
  (unless (camera? camera)
    (raise-argument-error
     'formula-visual->pict/using
     "camera?"
     camera))
  (unless (and (procedure? typesetter)
               (procedure-arity-includes? typesetter 1))
    (raise-argument-error
     'formula-visual->pict/using
     "procedure accepting one argument"
     typesetter))
  (if (string=? (formula-visual-source visual) "")
      (blank 1 1)
      (let* ([base-pict (typesetter visual)]
             [checked-pict
              (check-typesetter-result visual base-pict)]
             [sized-pict
              (scale-formula-to-font-size checked-pict visual camera)]
             [anchored-pict
              (anchor-pict
               sized-pict
               (formula-visual-horizontal-alignment visual)
               (formula-visual-vertical-alignment visual))]
             [scaled-pict
              (scale-pict-if-needed anchored-pict
                                    (visual-scale visual))])
        (rotate-pict-if-needed scaled-pict
                               (visual-rotation visual)))))

; check-typesetter-result : formula-visual? any/c -> pict?
;;   Raises an error unless a formula typesetter returns a Pict.
(define (check-typesetter-result visual result)
  (unless (pict? result)
    (raise-arguments-error
     'formula-visual->pict
     "a formula typesetter must return a pict"
     "visual" visual
     "result" result))
  result)

; scale-formula-to-font-size : pict? formula-visual? camera? -> pict?
;;   Maps the selected TeX base font size to semantic local world units.
(define (scale-formula-to-font-size source visual camera)
  (define factor
    (formula-font-scale visual camera))
  (if (= factor 1)
      source
      (scale source factor)))

; formula-font-scale : formula-visual? camera? -> positive-real?
;;   Returns the Pict scale needed for the formula's semantic font size.
(define (formula-font-scale visual camera)
  (/ (camera-length->pixels camera
                            (formula-visual-font-size visual))
     (formula-document-font-points visual)))

; formula-document-font-points : formula-visual? -> (or/c 10 11 12)
;;   Returns the standard base font size selected by document-class options.
(define (formula-document-font-points visual)
  (formula-visual-document-font-points visual))


;;;
;;; latex-pict Adapter
;;;

; typeset-formula : formula-visual? -> pict?
;;   Typesets one formula through the mode-specific latex-pict procedure.
(define (typeset-formula visual)
  (typeset-formula/using visual load-latex-typesetter))

; typeset-formula/using : formula-visual? (symbol? -> procedure?) -> pict?
;;   Typesets one formula with an explicitly supplied binding loader.
(define (typeset-formula/using visual load-typesetter)
  (unless (formula-visual? visual)
    (raise-argument-error
     'typeset-formula/using
     "formula-visual?"
     visual))
  (unless (and (procedure? load-typesetter)
               (procedure-arity-includes? load-typesetter 1))
    (raise-argument-error
     'typeset-formula/using
     "procedure accepting one argument"
     load-typesetter))
  (define binding
    (formula-mode->latex-binding
     (formula-visual-mode visual)))
  (define typesetter
    (load-typesetter binding))
  (unless (procedure? typesetter)
    (raise-arguments-error
     'typeset-formula/using
     "a typesetter loader must return a procedure"
     "binding" binding
     "result" typesetter))
  (with-handlers
      ([exn:fail?
        (lambda (exception)
          (error
           'formula-visual->pict
           (string-append
            "LaTeX formula typesetting failed\n"
            "  visual-id: ~a\n"
            "  mode: ~a\n"
            "  original error: ~a")
           (visual-id visual)
           (formula-visual-mode visual)
           (exn-message exception)))])
    (typesetter
     (formula-visual-source visual)
     #:document-class-options
     (formula-visual-document-class-options visual)
     #:preview-options
     (formula-visual-preview-options visual)
     #:preamble
     (formula-visual-preamble visual)
     #:scale 1)))

; formula-mode->latex-binding : formula-mode? -> symbol?
;;   Maps a semantic formula mode to its latex-pict procedure name.
(define (formula-mode->latex-binding mode)
  (case mode
    [(inline) 'tex-math]
    [(display) 'tex-display-math]
    [(display-environment) 'tex-real-display-math]
    [else
     (raise-argument-error
      'formula-mode->latex-binding
      "formula-mode?"
      mode)]))

; load-latex-typesetter : symbol? -> procedure?
;;   Loads one latex-pict typesetting procedure with a focused diagnostic.
(define (load-latex-typesetter binding)
  (define result
    (with-handlers
        ([exn:fail?
          (lambda (exception)
            (error
             'formula-visual->pict
             (string-append
              "LaTeX formula rendering is unavailable; install or link "
              "latex-pict with this Racket installation, or add its checkout "
              "root to PLTCOLLECTS; ensure Poppler is available\n"
              "  requested binding: ~a\n"
              "  original error: ~a")
             binding
             (exn-message exception)))])
      (dynamic-require 'latex-pict binding)))
  (unless (procedure? result)
    (raise-arguments-error
     'formula-visual->pict
     "a latex-pict typesetting binding must contain a procedure"
     "binding" binding
     "value" result))
  result)


;;;
;;; Test Support
;;;

(module+ test-support
  (provide formula-visual->pict/using
           formula-visual->pict/cached-using
           typeset-formula/using
           formula-mode->latex-binding
           formula-document-font-points
           formula-font-scale))
