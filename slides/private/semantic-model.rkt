#lang racket/base

;; Named component trees and witnessed domain snapshots. These are pure source
;; declarations: no Scene, Pict, renderer, file, or native typesetter is loaded.
(require racket/list "data.rkt" "check.rkt")
(provide semantic-group semantic-group? semantic-part semantic-part?
         content-state content-state? semantic-source-at-path)

;; A part's coordinates are local to its containing group's fixed viewport.
;; Sibling names are identities, never inferred from visible strings or order.
(define (semantic-part id content #:x [x 0] #:y [y 0]
                       #:width width #:height height
                       #:align [align 'center] #:valign [valign 'center]
                       #:fit [fit 'contain])
  (check-id 'semantic-part id)
  (unless (and (finite-number? x) (finite-number? y))
    (raise-argument-error 'semantic-part "finite local x and y" (list x y)))
  (check-number 'semantic-part width #t)
  (check-number 'semantic-part height #t)
  (check-enum 'semantic-part align '(left center right))
  (check-enum 'semantic-part valign '(top center bottom))
  (check-enum 'semantic-part fit '(contain natural))
  (semantic-part-value id (immutable-copy content)
                       (box-value x y width height) align valign fit))
(define semantic-part? semantic-part-value?)

(define (semantic-group #:width width #:height height . parts)
  (check-number 'semantic-group width #t)
  (check-number 'semantic-group height #t)
  (unless (and (pair? parts) (andmap semantic-part? parts))
    (raise-argument-error 'semantic-group "nonempty list of semantic parts" parts))
  (unique! 'semantic-parts (map semantic-part-value-id parts))
  (for ([part (in-list parts)])
    (define b (semantic-part-value-box part))
    (unless (and (>= (box-value-x b) 0) (>= (box-value-y b) 0)
                 (<= (+ (box-value-x b) (box-value-width b)) (+ width 1e-8))
                 (<= (+ (box-value-y b) (box-value-height b)) (+ height 1e-8)))
      (slides-error 'semantic-bounds (list (semantic-part-value-id part))
                    "semantic part lies outside its group's declared viewport")))
  (content-value 'semantic-group parts (hash 'width width 'height height 'fit 'contain)))
(define (semantic-group? v)
  (and (content-value? v) (eq? (content-value-kind v) 'semantic-group)))

;; A snapshot owns a point on an existing domain timeline. `poster` only picks
;; a preview of a playing asset; content-state freezes the content in every shot.
;; A common canonical viewport keeps domain layout independent of slide layout.
(define (content-state content #:at at #:viewport [viewport '(16 9)])
  (unless (and (content-value? content)
               (memq (content-value-kind content) '(math geometry scene)))
    (raise-argument-error 'content-state "math-content, geometry-content, or scene-content" content))
  (unless (or (memq at '(start end)) (nonnegative-number? at)
              (symbol? at) (and (list? at) (pair? at)))
    (raise-argument-error 'content-state "nonnegative time or named domain cue" at))
  (unless (and (list? viewport) (= (length viewport) 2)
               (andmap positive-number? viewport))
    (raise-argument-error 'content-state "two positive finite viewport dimensions" viewport))
  (when (eq? (hash-ref (content-value-options content) 'media #f) 'import)
    (slides-error 'semantic-media '()
                  "content-state is visual-only; use #:media 'visual-only and author narration outside the bridge"))
  (content-value 'state content
                 (hash 'at (immutable-copy at) 'viewport (immutable-copy viewport) 'fit 'contain)))
(define (content-state? v)
  (and (content-value? v) (eq? (content-value-kind v) 'state)))

;; Resolve a prepared leaf back into its source tree during worker decoding.
;; Plain bullet children are recorded pictures and need no domain reconstruction.
(define (semantic-source-at-path content relative-path)
  (cond
    [(semantic-group? content)
     (when (null? relative-path)
       (slides-error 'source-mismatch '() "semantic leaf path ends at a group"))
     (define part
       (findf (lambda (p) (eq? (semantic-part-value-id p) (car relative-path)))
              (content-value-payload content)))
     (unless part
       (slides-error 'source-mismatch relative-path "prepared semantic child no longer exists"))
     (semantic-source-at-path (semantic-part-value-content part) (cdr relative-path))]
    [else content]))
