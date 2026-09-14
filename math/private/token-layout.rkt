#lang racket/base

;;;
;;; Prepared Token Correspondence
;;;
;; Maps mathematical lineage to prepared token placement while preserving source order.
;; These geometry calculations perform no I/O.
;;;
;;; Imports and Exports
;;;
;; Imports
(require
  (only-in racket/list append* remove-duplicates)
  "typeset-model.rkt"
  "model.rkt"
  "datum.rkt")

;; Exports
(provide owner-id matching-token-index clone-view translate)

;;;
;;; Construction and Operations
;;;
; owner-id : math? prepared-token? -> symbol?
;;   Looks up the stable occurrence owning a prepared token.
(define (owner-id state token)
  (occurrence-id (math-occurrence-at state (prepared-token-path token))))

; matching-token-index : any/c any/c any/c prepared-token? any/c -> (or/c
;   exact-nonnegative-integer? #f)
;;   Matches typed lineage and owned notation, never crop dimensions or anonymous repeated strings.
(define (matching-token-index before-state after-state old-tokens token trace)
  ;; Same semantic owner/role/content. Crop dimensions do not determine identity. No string-only
  ;; search across repeated x's, and no digit matching between different numbers.
  (define target-id (owner-id after-state token))
  (define source-ids
    (remove-duplicates
      (cons target-id
        (append*
          (for/list ([r (in-list trace)]
                      #:when
                      (and
                        (memq (trace-relation-kind r) '(preserve container copy reorder))
                        (member target-id (trace-relation-targets r))))
            (trace-relation-sources r))))))
  (define candidates
    (for/list ([old (in-list old-tokens)]
                [i (in-naturals)]
                #:when
                (and
                  (member (owner-id before-state old) source-ids)
                  (eq? (prepared-token-role old) (prepared-token-role token))
                  (string=? (prepared-token-text old) (prepared-token-text token))
))
      i))
  (and (= (length candidates) 1) (car candidates)))

; clone-view : (listof prepared-token?) symbol? any/c -> (listof prepared-token?)
;;   Allocates deterministic view identities independently of mathematical occurrence
;;   identity.
(define (clone-view tokens id view)
  (for/list ([t (in-list tokens)] [i (in-naturals)])
    (token-with-id t (string->symbol (format "~a.view~a.part~a" id view i)))))

; translate : (listof prepared-token?) any/c any/c -> (listof prepared-token?)
;;   Translates prepared token positions without changing their order or owners.
(define (translate tokens dx dy)
  (map
    (lambda (t)
      (token-with-position t (+ (prepared-token-x t) dx) (+ (prepared-token-y t) dy)))
    tokens))
