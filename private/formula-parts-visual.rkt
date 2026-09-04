#lang racket/base

;;;
;;; Formula Parts Visual Model
;;;

;; Defines immutable formula assemblies with explicit named LaTeX parts and
;; validated one-to-one correspondence data.
;;
;; This module contains no Pict, drawing-context, bitmap, filesystem, process,
;; browser, or JavaScript dependencies.


;;;
;;; Imports and Exports
;;;

;; Imports
(require (only-in racket/generic define/generic)
         "formula-visual.rkt"
         "geometry.rkt"
         "group-visual.rkt"
         "visual-model.rkt")

;; Exports
(provide (struct-out formula-part)
         latex-formula-part
         formula-assembly
         formula-assembly-visual?
         formula-assembly-visual-parts
         formula-assembly-visual-with-parts
         formula-assembly-visual-part-names
         formula-assembly-visual-has-part?
         formula-assembly-visual-ref
         (struct-out formula-part-match)
         (struct-out formula-correspondence)
         formula-correspondence-auto
         formula-correspondence-unmatched-source-names
         formula-correspondence-unmatched-destination-names

         ;; Adapter support
         formula-assembly-visual-group)


;;;
;;; Named Formula Parts
;;;

(struct formula-part (name formula)
  #:transparent
  #:guard
  (lambda (name formula type-name)
    (unless (symbol? name)
      (raise-argument-error type-name "symbol?" name))
    (unless (formula-visual? formula)
      (raise-argument-error type-name "formula-visual?" formula))
    (unless (eq? name (visual-id formula))
      (raise-arguments-error
       type-name
       "a formula part name must equal its formula Visual identity"
       "part-name" name
       "formula-id" (visual-id formula)))
    (values name formula)))

;; formula-part represents one explicitly named formula fragment.
;;  - name     symbol?          name local to one formula assembly.
;;  - formula  formula-visual?  independently typeset local formula Visual.
;;
;; The formula Visual identity equals name. A formula part's transform and
;; opacity are local to its containing formula assembly.

; latex-formula-part : string?
;                      #:name symbol?
;                      [#:center vec2?]
;                      [#:rotation finite-real?]
;                      [#:scale scale-factor?]
;                      [#:opacity opacity?]
;                      [#:mode formula-mode?]
;                      [#:font-size positive-real?]
;                      [#:preamble string?]
;                      [#:document-class-options (listof latex-option?)]
;                      [#:preview-options (listof latex-option?)]
;                      [#:horizontal-alignment text-horizontal-alignment?]
;                      [#:vertical-alignment text-vertical-alignment?]
;                      -> formula-part?
;;   Creates a named formula part whose formula Visual uses the same identity.
(define (latex-formula-part source
                            #:name name
                            #:center [center origin]
                            #:rotation [rotation 0]
                            #:scale [scale 1]
                            #:opacity [opacity 1]
                            #:mode [mode 'display]
                            #:font-size [font-size 1]
                            #:preamble [preamble ""]
                            #:document-class-options
                            [document-class-options '()]
                            #:preview-options [preview-options '()]
                            #:horizontal-alignment
                            [horizontal-alignment 'center]
                            #:vertical-alignment
                            [vertical-alignment 'center])
  (unless (symbol? name)
    (raise-argument-error 'latex-formula-part "symbol?" name))
  (formula-part
   name
   (latex-formula
    source
    #:id name
    #:center center
    #:rotation rotation
    #:scale scale
    #:opacity opacity
    #:mode mode
    #:font-size font-size
    #:preamble preamble
    #:document-class-options document-class-options
    #:preview-options preview-options
    #:horizontal-alignment horizontal-alignment
    #:vertical-alignment vertical-alignment)))


;;;
;;; Formula Assemblies
;;;

(struct formula-assembly-visual (group parts)
  #:transparent
  #:methods gen:visual
  [(define/generic generic-visual-id visual-id)
   (define/generic generic-visual-position visual-position)
   (define/generic generic-visual-with-position visual-with-position)
   (define (visual-id assembly)
     (generic-visual-id
      (formula-assembly-visual-group assembly)))
   (define (visual-position assembly)
     (generic-visual-position
      (formula-assembly-visual-group assembly)))
   (define (visual-with-position assembly position)
     (struct-copy
      formula-assembly-visual
      assembly
      [group
       (generic-visual-with-position
        (formula-assembly-visual-group assembly)
        position)]))]
  #:methods gen:affine-visual
  [(define/generic generic-visual-transform visual-transform)
   (define/generic generic-visual-with-transform visual-with-transform)
   (define (visual-transform assembly)
     (generic-visual-transform
      (formula-assembly-visual-group assembly)))
   (define (visual-with-transform assembly transform)
     (struct-copy
      formula-assembly-visual
      assembly
      [group
       (generic-visual-with-transform
        (formula-assembly-visual-group assembly)
        transform)]))]
  #:methods gen:opacity-visual
  [(define/generic generic-visual-opacity visual-opacity)
   (define/generic generic-visual-with-opacity visual-with-opacity)
   (define (visual-opacity assembly)
     (generic-visual-opacity
      (formula-assembly-visual-group assembly)))
   (define (visual-with-opacity assembly opacity)
     (struct-copy
      formula-assembly-visual
      assembly
      [group
       (generic-visual-with-opacity
       (formula-assembly-visual-group assembly)
        opacity)]))]
  #:methods gen:visual-container
  [(define (visual-child-entries assembly)
     (for/list ([part (in-list (formula-assembly-visual-parts assembly))])
       (visual-child (formula-part-name part) (formula-part-formula part))))])

;; formula-assembly-visual represents one composite formula with named parts.
;;  - group  group-visual?          validated composite identity and transform.
;;  - parts  (listof formula-part?) named parts in back-to-front drawing order.
;;                                  Ordering is significant.
;;
;; Part names form a local namespace. They are addressable with nested Visual
;; paths through their assembly, while a formula correspondence animates the
;; complete assembly collectively. Ordinary parts are typeset independently at
;; their local positions; specialised formula Visuals may supply a full-layout
;; renderer instead.

; formula-assembly : (listof formula-part?)
;                    #:id symbol?
;                    [#:center vec2?]
;                    [#:rotation finite-real?]
;                    [#:scale scale-factor?]
;                    [#:opacity opacity?]
;                    -> formula-assembly-visual?
;;   Creates a semantic formula assembly from explicitly positioned parts.
(define (formula-assembly parts
                          #:id id
                          #:center [center origin]
                          #:rotation [rotation 0]
                          #:scale [scale 1]
                          #:opacity [opacity 1])
  (define checked-parts
    (check-formula-parts 'formula-assembly parts))
  (formula-assembly-visual
   (group (formula-parts->visuals checked-parts)
          #:id id
          #:center center
          #:rotation rotation
          #:scale scale
          #:opacity opacity)
   checked-parts))

; formula-assembly-visual-with-parts : formula-assembly-visual?
;                                      (listof formula-part?)
;                                      -> formula-assembly-visual?
;;   Returns assembly with its significant ordered part list replaced.
(define (formula-assembly-visual-with-parts assembly parts)
  (unless (formula-assembly-visual? assembly)
    (raise-argument-error
     'formula-assembly-visual-with-parts
     "formula-assembly-visual?"
     assembly))
  (define checked-parts
    (check-formula-parts
     'formula-assembly-visual-with-parts
     parts))
  (formula-assembly-visual
   (group-visual-with-children
    (formula-assembly-visual-group assembly)
    (formula-parts->visuals checked-parts))
   checked-parts))

; formula-assembly-visual-part-names : formula-assembly-visual?
;                                      -> (listof symbol?)
;;   Returns local part names in significant back-to-front order.
(define (formula-assembly-visual-part-names assembly)
  (check-formula-assembly
   'formula-assembly-visual-part-names
   assembly)
  (for/list ([part
              (in-list
               (formula-assembly-visual-parts assembly))])
    (formula-part-name part)))

; formula-assembly-visual-has-part? : formula-assembly-visual? symbol?
;                                     -> boolean?
;;   Reports whether assembly contains a part with name.
(define (formula-assembly-visual-has-part? assembly name)
  (check-formula-assembly
   'formula-assembly-visual-has-part?
   assembly)
  (unless (symbol? name)
    (raise-argument-error
     'formula-assembly-visual-has-part?
     "symbol?"
     name))
  (and (member name
               (formula-assembly-visual-part-names assembly))
       #t))

; formula-assembly-visual-ref : formula-assembly-visual? symbol?
;                               -> formula-part?
;;   Returns the named part or raises when the local name is absent.
(define (formula-assembly-visual-ref assembly name)
  (check-formula-assembly 'formula-assembly-visual-ref assembly)
  (unless (symbol? name)
    (raise-argument-error
     'formula-assembly-visual-ref
     "symbol?"
     name))
  (or (for/first ([part
                   (in-list
                    (formula-assembly-visual-parts assembly))]
                  #:when (eq? name (formula-part-name part)))
        part)
      (raise-arguments-error
       'formula-assembly-visual-ref
       "the formula assembly has no part with this name"
       "assembly-id" (visual-id assembly)
       "part-name" name)))


;;;
;;; Manual Correspondence
;;;

(struct formula-part-match (source-name destination-name)
  #:transparent
  #:guard
  (lambda (source-name destination-name type-name)
    (unless (symbol? source-name)
      (raise-argument-error type-name "symbol?" source-name))
    (unless (symbol? destination-name)
      (raise-argument-error type-name "symbol?" destination-name))
    (values source-name destination-name)))

;; formula-part-match represents one manually chosen part correspondence.
;;  - source-name       symbol?  name in the source formula assembly.
;;  - destination-name  symbol?  name in the destination formula assembly.

(struct formula-correspondence (source destination matches)
  #:transparent
  #:guard
  (lambda (source destination matches type-name)
    (unless (formula-assembly-visual? source)
      (raise-argument-error
       type-name
       "formula-assembly-visual?"
       source))
    (unless (formula-assembly-visual? destination)
      (raise-argument-error
       type-name
       "formula-assembly-visual?"
       destination))
    (values
     source
     destination
     (check-formula-part-matches
      type-name
      source
      destination
      matches))))

;; formula-correspondence records an explicit one-to-one part mapping.
;;  - source       formula-assembly-visual?  source assembly value.
;;  - destination  formula-assembly-visual?  destination assembly value.
;;  - matches      (listof formula-part-match?) matches in significant order.
;;
;; A source or destination part may be omitted. Formula-part transformations
;; fade omitted source parts out and omitted destination parts in. No match is
;; inferred automatically from equal names.

; formula-correspondence-auto : formula-assembly-visual?
;                               formula-assembly-visual?
;                               -> formula-correspondence?
;; Builds deterministic one-to-one matches for unchanged formula parts. Source
;; order is significant; repeated equivalent fragments consume destination
;; parts from their destination order.
(define (formula-correspondence-auto source destination)
  (check-formula-assembly 'formula-correspondence-auto source)
  (check-formula-assembly 'formula-correspondence-auto destination)
  (define-values (reversed-matches ignored-used)
    (for/fold ([matches '()]
               [used (hash)])
              ([source-part
                (in-list (formula-assembly-visual-parts source))])
      (define destination-part
        (for/first ([candidate
                     (in-list (formula-assembly-visual-parts destination))]
                    #:unless (hash-has-key? used (formula-part-name candidate))
                    #:when (formula-parts-rendering-equivalent?
                            source-part candidate))
          candidate))
      (if destination-part
          (values
           (cons
            (formula-part-match
             (formula-part-name source-part)
             (formula-part-name destination-part))
            matches)
           (hash-set used (formula-part-name destination-part) #t))
          (values matches used))))
  (formula-correspondence source destination (reverse reversed-matches)))

; formula-parts-rendering-equivalent? : formula-part? formula-part? -> boolean?
;; Reports whether parts carry the exact same typeset semantic appearance.
(define (formula-parts-rendering-equivalent? source destination)
  (define source-formula (formula-part-formula source))
  (define destination-formula (formula-part-formula destination))
  (equal? (formula-visual-rendering-key source-formula)
          (formula-visual-rendering-key destination-formula)))

; formula-correspondence-unmatched-source-names : formula-correspondence?
;                                                 -> (listof symbol?)
;;   Returns unmatched source names in source part order.
(define (formula-correspondence-unmatched-source-names correspondence)
  (unless (formula-correspondence? correspondence)
    (raise-argument-error
     'formula-correspondence-unmatched-source-names
     "formula-correspondence?"
     correspondence))
  (define matched-names
    (for/list ([match
                (in-list
                 (formula-correspondence-matches correspondence))])
      (formula-part-match-source-name match)))
  (filter-unmatched-names
   (formula-assembly-visual-part-names
    (formula-correspondence-source correspondence))
   matched-names))

; formula-correspondence-unmatched-destination-names : formula-correspondence?
;                                                      -> (listof symbol?)
;;   Returns unmatched destination names in destination part order.
(define (formula-correspondence-unmatched-destination-names correspondence)
  (unless (formula-correspondence? correspondence)
    (raise-argument-error
     'formula-correspondence-unmatched-destination-names
     "formula-correspondence?"
     correspondence))
  (define matched-names
    (for/list ([match
                (in-list
                 (formula-correspondence-matches correspondence))])
      (formula-part-match-destination-name match)))
  (filter-unmatched-names
   (formula-assembly-visual-part-names
    (formula-correspondence-destination correspondence))
   matched-names))


;;;
;;; Validation
;;;

; check-formula-parts : symbol? any/c -> (listof formula-part?)
;;   Validates and copies one significant ordered formula-part list.
(define (check-formula-parts who parts)
  (unless (and (list? parts)
               (andmap formula-part? parts))
    (raise-argument-error
     who
     "(listof formula-part?)"
     parts))
  (define checked-parts
    (for/list ([part (in-list parts)])
      part))
  (define duplicate-name
    (find-duplicate-symbol
     (for/list ([part (in-list checked-parts)])
       (formula-part-name part))))
  (when duplicate-name
    (raise-arguments-error
     who
     "formula part names must be unique within one assembly"
     "duplicate part-name" duplicate-name))
  checked-parts)

; formula-parts->visuals : (listof formula-part?) -> (listof formula-visual?)
;;   Extracts formula Visuals without changing significant part order.
(define (formula-parts->visuals parts)
  (for/list ([part (in-list parts)])
    (formula-part-formula part)))

; check-formula-assembly : symbol? any/c -> void?
;;   Raises an argument error unless assembly is a formula assembly Visual.
(define (check-formula-assembly who assembly)
  (unless (formula-assembly-visual? assembly)
    (raise-argument-error
     who
     "formula-assembly-visual?"
     assembly)))

; check-formula-part-matches : symbol?
;                              formula-assembly-visual?
;                              formula-assembly-visual?
;                              any/c
;                              -> (listof formula-part-match?)
;;   Validates and copies a significant one-to-one match list.
(define (check-formula-part-matches who source destination matches)
  (unless (and (list? matches)
               (andmap formula-part-match? matches))
    (raise-argument-error
     who
     "(listof formula-part-match?)"
     matches))
  (define checked-matches
    (for/list ([match (in-list matches)])
      (check-match-name-exists who source destination match)
      match))
  (check-unique-match-side
   who
   "source"
   (for/list ([match (in-list checked-matches)])
     (formula-part-match-source-name match)))
  (check-unique-match-side
   who
   "destination"
   (for/list ([match (in-list checked-matches)])
     (formula-part-match-destination-name match)))
  checked-matches)

; check-match-name-exists : symbol?
;                           formula-assembly-visual?
;                           formula-assembly-visual?
;                           formula-part-match?
;                           -> void?
;;   Checks that one match names existing source and destination parts.
(define (check-match-name-exists who source destination match)
  (define source-name
    (formula-part-match-source-name match))
  (define destination-name
    (formula-part-match-destination-name match))
  (unless (formula-assembly-visual-has-part? source source-name)
    (raise-arguments-error
     who
     "a correspondence names a missing source part"
     "source assembly-id" (visual-id source)
     "source part-name" source-name))
  (unless (formula-assembly-visual-has-part?
           destination
           destination-name)
    (raise-arguments-error
     who
     "a correspondence names a missing destination part"
     "destination assembly-id" (visual-id destination)
     "destination part-name" destination-name))
  (void))

; check-unique-match-side : symbol? string? (listof symbol?) -> void?
;;   Rejects reuse of a part name on one side of a correspondence.
(define (check-unique-match-side who side names)
  (define duplicate-name
    (find-duplicate-symbol names))
  (when duplicate-name
    (raise-arguments-error
     who
     "formula correspondences must be one-to-one"
     "reused side" side
     "reused part-name" duplicate-name)))

; find-duplicate-symbol : (listof symbol?) -> (or/c symbol? false/c)
;;   Returns the first repeated symbol or false when all names are unique.
(define (find-duplicate-symbol names)
  (let loop ([remaining names]
             [seen (hash)])
    (cond
      [(null? remaining)
       #f]
      [(hash-has-key? seen (car remaining))
       (car remaining)]
      [else
       (loop (cdr remaining)
             (hash-set seen (car remaining) #t))])))

; filter-unmatched-names : (listof symbol?) (listof symbol?) -> (listof symbol?)
;;   Preserves names not present in matched-names.
(define (filter-unmatched-names names matched-names)
  (for/list ([name (in-list names)]
             #:unless (member name matched-names))
    name))
