#lang racket/base

;;;
;;; SCENE-EJ Canonical Source and Selector Tests
;;;

(require rackunit
         (only-in "../main.rkt"
                  source-span
                  source-span?
                  source-occurrence
                  source-part
                  source-selector?)
         (only-in "../private/source-document.rkt"
                  source-document-from-strings
                  source-document-text
                  source-document-argument-spans
                  source-document-separator
                  source-document-span-text)
         (only-in "../private/source-selector.rkt"
                  resolve-source-selector))

(module+ test
  ;; Multiple source arguments have one canonical character-index coordinate
  ;; system.  Their joining spaces are deliberate source characters.
  (define document
    (source-document-from-strings '("α + β" "=" "α")))
  (check-equal? (source-document-text document) "α + β = α")
  (check-equal? (source-document-separator document) " ")
  (check-equal?
   (source-document-argument-spans document)
   (list (source-span 0 5)
         (source-span 6 7)
         (source-span 8 9)))
  (check-equal?
   (source-document-span-text document (source-span 6 7))
   "=")

  ;; Literal strings resolve in source order, and all indices are Racket
  ;; string-character indices rather than UTF-8 byte offsets.
  (check-equal?
   (resolve-source-selector document "α")
   (list (source-span 0 1) (source-span 8 9)))
  (check-equal?
   (resolve-source-selector document #px"[αβ]")
   (list (source-span 0 1) (source-span 4 5) (source-span 8 9)))

  ;; Repeated literal matches use the documented left-to-right,
  ;; non-overlapping rule.  A later occurrence can be requested explicitly.
  (define repeated (source-document-from-strings '("xxx") #:separator ""))
  (check-equal?
   (resolve-source-selector repeated "xx")
   (list (source-span 0 2)))
  (check-equal?
   (resolve-source-selector document (source-occurrence "α" 1))
   (list (source-span 8 9)))

  ;; Named parts are selectors with stable author names.  EJ-1 records no
  ;; rendering identity yet; that arrives when declared formula maps are built.
  (define equals-part (source-part 'equals (source-span 6 7)))
  (check-true (source-selector? equals-part))
  (check-equal?
   (resolve-source-selector document equals-part)
   (list (source-span 6 7)))

  ;; Protected ranges suppress automatic string/regexp matches before indexed
  ;; occurrence selection, but an explicit span remains authoritative.
  (define first-term (source-span 0 5))
  (check-equal?
   (resolve-source-selector document "α" #:protected (list first-term))
   (list (source-span 8 9)))
  (check-equal?
   (resolve-source-selector document
                            (source-occurrence "α" 0)
                            #:protected (list first-term))
   (list (source-span 8 9)))
  (check-equal?
   (resolve-source-selector document
                            (source-span 0 1)
                            #:protected (list first-term))
   (list (source-span 0 1)))

  ;; Invalid source addressing fails early and descriptively rather than being
  ;; silently clipped or interpreted as a zero-width rendered selection.
  (check-exn exn:fail:contract?
             (lambda () (source-span 3 2)))
  (check-exn exn:fail?
             (lambda ()
               (resolve-source-selector document (source-span 0 10))))
  (check-exn exn:fail?
             (lambda ()
               (resolve-source-selector document (source-span 2 2))))
  (check-exn exn:fail?
             (lambda ()
               (resolve-source-selector document "")))
  (check-exn exn:fail?
             (lambda ()
               (resolve-source-selector document #px"a*")))
  (check-exn exn:fail?
             (lambda ()
               (resolve-source-selector document (source-occurrence "α" 2))))
  (check-exn exn:fail:contract?
             (lambda ()
               (source-occurrence (source-occurrence "α" 0) 0)))

  ;; The public span value remains an ordinary immutable, transparent datum.
  (check-true (source-span? (source-span 0 1))))
