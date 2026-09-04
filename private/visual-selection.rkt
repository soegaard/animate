#lang racket/base

;;;
;;; Root-Relative Semantic Visual Selections
;;;

;; A selection names existing leaves without introducing a synthetic rendered
;; group.  The root is a semantic path; each selected path is relative to that
;; root.  Keeping the paths relative lets a formula or component be authored
;; before its eventual parent scene path is known.

(require racket/list
         "visual-model.rkt")

(provide (struct-out visual-selection)
         visual-selection-empty?
         visual-selection-count
         visual-selection-union
         visual-selection-intersection
         visual-selection-rebase
         visual-selection-absolute-paths)


;;;
;;; Data Representation
;;;

;; A relative visual path may be empty: the empty relative path selects the
;; root itself.  Ordinary formula source selections will normally name one or
;; more descendant leaves instead.
(define (relative-visual-path? value)
  (and (list? value)
       (andmap symbol? value)))

(struct visual-selection (root paths)
  #:transparent
  #:guard
  (lambda (root paths type-name)
    (unless (visual-path? root)
      (raise-argument-error type-name "visual-path?" root))
    (unless (and (list? paths)
                 (andmap relative-visual-path? paths))
      (raise-argument-error
       type-name
       "list of relative Visual paths (lists of symbols)"
       paths))
    ;; Input order is semantic drawing/source order supplied by the caller.
    ;; Removing duplicates preserves the first occurrence and never depends on
    ;; hash iteration order.
    (values root (remove-duplicates paths equal?))))

;; visual-selection represents leaves beneath one semantic root.
;;  - root   visual-path?  root identity in the component's own path space.
;;  - paths  ordered duplicate-free (listof relative-visual-path?).
;;
;; `metadata` is intentionally not a field.  A source-match report belongs in
;; a separate value, ensuring that `equal?` and hashing reflect only the
;; selected semantic leaves.


;;;
;;; Queries
;;;

(define (visual-selection-empty? selection)
  (check-selection 'visual-selection-empty? selection)
  (null? (visual-selection-paths selection)))

(define (visual-selection-count selection)
  (check-selection 'visual-selection-count selection)
  (length (visual-selection-paths selection)))

;; visual-selection-absolute-paths : visual-selection? -> (listof visual-path?)
;; Resolves relative leaf paths below the selection's current root.  No scene
;; lookup happens here; stale or missing leaves are reported by the later scene
;; resolution layer.
(define (visual-selection-absolute-paths selection)
  (check-selection 'visual-selection-absolute-paths selection)
  (for/list ([path (in-list (visual-selection-paths selection))])
    (append (visual-selection-root selection) path)))


;;;
;;; Set Operations
;;;

;; Both operations preserve the source/drawing order of their first argument.
;; A union appends only as-yet-unseen paths from subsequent arguments.
(define (visual-selection-union first . rest)
  (check-selection 'visual-selection-union first)
  (for/fold ([result first]) ([selection (in-list rest)])
    (check-compatible-selection 'visual-selection-union result selection)
    (visual-selection
     (visual-selection-root result)
     (append (visual-selection-paths result)
             (visual-selection-paths selection)))))

(define (visual-selection-intersection first . rest)
  (check-selection 'visual-selection-intersection first)
  (for/fold ([result first]) ([selection (in-list rest)])
    (check-compatible-selection 'visual-selection-intersection result selection)
    (visual-selection
     (visual-selection-root result)
     (for/list ([path (in-list (visual-selection-paths result))]
                #:when (member path (visual-selection-paths selection) equal?))
       path))))


;;;
;;; Root Rebinding
;;;

;; visual-selection-rebase : visual-selection? visual-path? -> visual-selection?
;; Rebinds a component-local selection to its actual scene location.  The
;; target path must end in the same root identity, which prevents accidentally
;; applying formula leaves to an unrelated Visual with a different ID.
(define (visual-selection-rebase selection root)
  (check-selection 'visual-selection-rebase selection)
  (unless (visual-path? root)
    (raise-argument-error 'visual-selection-rebase "visual-path?" root))
  (unless (eq? (last root) (last (visual-selection-root selection)))
    (raise-arguments-error
     'visual-selection-rebase
     "a root path ending in the selection root identity"
     "selection-root" (visual-selection-root selection)
     "new-root" root))
  (visual-selection root (visual-selection-paths selection)))


;;;
;;; Validation
;;;

(define (check-selection who value)
  (unless (visual-selection? value)
    (raise-argument-error who "visual-selection?" value)))

(define (check-compatible-selection who first second)
  (check-selection who second)
  (unless (equal? (visual-selection-root first)
                  (visual-selection-root second))
    (raise-arguments-error
     who
     "selections with the same root path"
     "first-root" (visual-selection-root first)
     "second-root" (visual-selection-root second))))
