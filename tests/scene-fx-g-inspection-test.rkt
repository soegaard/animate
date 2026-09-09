#lang racket/base

;;;
;;; FX-G Generic Effects Inspector Tests
;;;

(require racket/list
         rackunit
         "../main.rkt"
         "../preview.rkt")

(module+ test
  (define caption
    (rich-text #:id 'caption #:width 3 #:font-size 1/2
               (text-span "prepared " #:color "navy")
               (text-span "layout" #:font-weight 'bold)))
  (define effects-scene
    (scene-play
     (scene-add (make-scene) caption)
     (animation-group
      (pulse 'caption #:scale-factor 6/5)
      (underline-sweep 'caption #:retain? #f)
      (highlight-sweep 'caption #:retain? #t))
     #:duration 2))
  (define document (scene-inspector-document effects-scene 1/2))
  (define effects-section
    (for/first ([section (in-list (inspector-document-sections document))]
                #:when (eq? (inspector-section-id section) 'effects))
      section))
  (check-not-false effects-section)
  (check-equal?
   (map inspector-row-label (inspector-section-rows effects-section))
   '("pulse" "underline-sweep" "highlight-sweep"))
  (for ([row (in-list (inspector-section-rows effects-section))])
    (check-true (immutable? (inspector-row-value row)))
    (check-equal? (inspector-row-actions row) '()))
  (define underline-data
    (inspector-row-value
     (second (inspector-section-rows effects-section))))
  (check-equal? (hash-ref underline-data 'layout) 'frozen-at-clip-start)

  ;; Prepared text identity appears in the same generic Effects section. It
  ;; is source data, not an adapter cache object, and remains available when a
  ;; completed clip is inspected.
  (define typed
    (scene-play (make-scene)
                (typewrite caption #:unit 'word
                           #:cursor? #t #:cursor-style "tomato")
                #:duration 1))
  (define typed-document (scene-inspector-document typed 1/2))
  (define typed-effects
    (for/first ([section (in-list (inspector-document-sections typed-document))]
                #:when (eq? (inspector-section-id section) 'effects))
      section))
  (define typewrite-data
    (inspector-row-value (car (inspector-section-rows typed-effects))))
  (check-true (vector? (hash-ref typewrite-data 'prepared-layout-key)))
  (check-equal? (hash-ref typewrite-data 'unit) 'word)
  (check-true (hash-ref typewrite-data 'cursor?))
  (check-equal? (hash-ref typewrite-data 'cursor-style) "tomato")
  (check-equal? (hash-ref typewrite-data 'cursor-lifecycle) 'open-clip-only))
