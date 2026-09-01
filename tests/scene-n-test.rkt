#lang racket/base

;;;
;;; SCENE-N Model Tests
;;;

;; Tests named formula parts, formula assemblies, ordinary Visual behavior, and
;; explicit one-to-one correspondence validation.


;;;
;;; Imports
;;;

(require rackunit
         (only-in "../private/group-visual.rkt"
                  group-visual-resolved-children)
         "../main.rkt")


(module+ test
  ; make-part : symbol? string? real? -> formula-part?
  ;;   Creates one small centered formula part at local x.
  (define (make-part name source x)
    (latex-formula-part source
                        #:name name
                        #:center (vec2 x 0)
                        #:font-size 1/2))

  ; part-a : formula-part?
  ;;   Gives one valid named formula part.
  (define part-a
    (make-part 'a "a" -2))

  (check-true (formula-part? part-a))
  (check-eq? (formula-part-name part-a) 'a)
  (check-true (formula-visual? (formula-part-formula part-a)))
  (check-eq? (visual-id (formula-part-formula part-a)) 'a)
  (check-equal? (visual-position (formula-part-formula part-a))
                (vec2 -2 0))

  ;; Public structure guards reject malformed names, values, and mismatched
  ;; formula identities.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-part 1
                   (latex-formula "a" #:id 'a))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-part 'a "a")))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-part 'a
                   (latex-formula "b" #:id 'b))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (latex-formula-part "a" #:name 1)))

  ;; Formula-part construction keeps the formula model's immutable-string rule.
  ; mutable-source : string?
  ;;   Gives mutable input that must not remain shared with the model.
  (define mutable-source
    (string-copy "x+1"))

  ; copied-part : formula-part?
  ;;   Gives a part constructed from mutable source.
  (define copied-part
    (latex-formula-part mutable-source #:name 'copied))

  (string-set! mutable-source 0 #\y)
  (check-equal?
   (formula-visual-source (formula-part-formula copied-part))
   "x+1")
  (check-true
   (immutable?
    (formula-visual-source (formula-part-formula copied-part))))

  ; source-parts : (listof formula-part?)
  ;;   Gives source parts in significant back-to-front order.
  (define source-parts
    (list part-a
          (make-part 'plus "+" -1)
          (make-part 'b "b" 0)
          (make-part 'equals "=" 1)
          (make-part 'c "c" 2)))

  ; source-assembly : formula-assembly-visual?
  ;;   Gives one assembled source equation.
  (define source-assembly
    (formula-assembly source-parts
                      #:id 'source-equation
                      #:center (vec2 -3 1)
                      #:rotation 1/10
                      #:scale 3/2
                      #:opacity 4/5))

  (check-true (formula-assembly-visual? source-assembly))
  (check-true (visual? source-assembly))
  (check-true (affine-visual? source-assembly))
  (check-true (opacity-visual? source-assembly))
  (check-eq? (visual-id source-assembly) 'source-equation)
  (check-equal? (visual-position source-assembly) (vec2 -3 1))
  (check-equal? (visual-rotation source-assembly) 1/10)
  (check-equal? (visual-scale source-assembly) (vec2 3/2 3/2))
  (check-equal? (visual-opacity source-assembly) 4/5)
  (check-equal? (formula-assembly-visual-parts source-assembly)
                source-parts)
  (check-equal? (formula-assembly-visual-part-names source-assembly)
                '(a plus b equals c))
  (check-true (formula-assembly-visual-has-part? source-assembly 'b))
  (check-false (formula-assembly-visual-has-part? source-assembly 'missing))
  (check-eq? (formula-assembly-visual-ref source-assembly 'plus)
             (cadr source-parts))

  ; assembly-scene : scene?
  ;;   Gives a scene where only the complete assembly is a top-level target.
  (define assembly-scene
    (scene-add (make-scene) source-assembly))

  (check-true
   (scene-state-has? (scene-current-state assembly-scene)
                     'source-equation))
  (check-false
   (scene-state-has? (scene-current-state assembly-scene)
                     'a))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (scene-play assembly-scene
                 (move-to 'a origin)
                 #:duration 1)))

  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-assembly-visual-ref source-assembly 'missing)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-assembly-visual-has-part? source-assembly "a")))

  ;; Empty assemblies are valid deterministic composite Visuals.
  ; empty-assembly : formula-assembly-visual?
  ;;   Gives an assembly with no formula parts.
  (define empty-assembly
    (formula-assembly '() #:id 'empty-equation))

  (check-equal? (formula-assembly-visual-parts empty-assembly) '())
  (check-equal? (formula-assembly-visual-part-names empty-assembly) '())

  ;; Names are unique within an assembly, and the assembly identity differs from
  ;; every local part name because each part name is also its formula Visual id.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-assembly
      (list (make-part 'same "a" 0)
            (make-part 'same "b" 1))
      #:id 'duplicates)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-assembly (list part-a) #:id 'a)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-assembly source-parts
                       #:id 'nonuniform
                       #:scale (vec2 2 1))))

  ;; Immutable part replacement preserves assembly identity, transform, and
  ;; opacity while installing the new significant order.
  ; reversed-assembly : formula-assembly-visual?
  ;;   Gives source-assembly with the part order reversed.
  (define reversed-assembly
    (formula-assembly-visual-with-parts
     source-assembly
     (reverse source-parts)))

  (check-eq? (visual-id reversed-assembly)
             (visual-id source-assembly))
  (check-equal? (visual-transform reversed-assembly)
                (visual-transform source-assembly))
  (check-equal? (visual-opacity reversed-assembly)
                (visual-opacity source-assembly))
  (check-equal? (formula-assembly-visual-part-names reversed-assembly)
                '(c equals b plus a))

  ;; Existing affine and opacity requests animate the whole assembly.
  ; animated-assembly : scene?
  ;;   Moves, rotates, scales, and fades one assembly for two seconds.
  (define animated-assembly
    (scene-play
     (scene-add (make-scene)
                (formula-assembly source-parts
                                  #:id 'animated-equation))
     (move-to 'animated-equation (vec2 4 2))
     (rotate-to 'animated-equation 1)
     (scale-to 'animated-equation 2)
     (fade-to 'animated-equation 1/2)
     #:duration 2))

  ; midpoint-assembly : formula-assembly-visual?
  ;;   Gives the assembly sampled halfway through all four components.
  (define midpoint-assembly
    (scene-state-ref (scene-sample animated-assembly 1)
                     'animated-equation))

  (check-equal? (visual-position midpoint-assembly) (vec2 2 1))
  (check-equal? (visual-rotation midpoint-assembly) 1/2)
  (check-equal? (visual-scale midpoint-assembly) (vec2 3/2 3/2))
  (check-equal? (visual-opacity midpoint-assembly) 3/4)
  (check-equal? (formula-assembly-visual-part-names midpoint-assembly)
                '(a plus b equals c))

  ;; Formula assemblies can be affine children of ordinary groups.
  ; local-assembly : formula-assembly-visual?
  ;;   Gives one local child for inherited-transform testing.
  (define local-assembly
    (formula-assembly (list (make-part 'local-x "x" 1))
                      #:id 'local-equation
                      #:center origin
                      #:rotation 1/5))

  ; parent-group : group-visual?
  ;;   Gives a parent with uniform scale and rotation.
  (define parent-group
    (group (list local-assembly)
           #:id 'formula-parent
           #:rotation 3/10
           #:scale 2))

  ; resolved-assembly : formula-assembly-visual?
  ;;   Gives local-assembly after inheriting its parent transform.
  (define resolved-assembly
    (car (group-visual-resolved-children parent-group)))

  (check-true (formula-assembly-visual? resolved-assembly))
  (check-equal? (visual-position resolved-assembly) origin)
  (check-equal? (visual-rotation resolved-assembly) 1/2)
  (check-equal? (visual-scale resolved-assembly) (vec2 2 2))

  ;; Manual correspondence is explicit, ordered, and one-to-one.
  ; destination-parts : (listof formula-part?)
  ;;   Gives destination parts in a different significant order.
  (define destination-parts
    (list (make-part 'c "c" -2)
          (make-part 'minus "-" -1)
          (make-part 'a "a" 0)
          (make-part 'equals "=" 1)
          (make-part 'b "b" 2)))

  ; destination-assembly : formula-assembly-visual?
  ;;   Gives the destination equation used for correspondence validation.
  (define destination-assembly
    (formula-assembly destination-parts
                      #:id 'destination-equation))

  ;; Equal local part names remain valid across distinct assemblies, even when
  ;; those assemblies share one containing group.
  ; paired-equations : group-visual?
  ;;   Gives one group containing both local formula namespaces.
  (define paired-equations
    (group (list source-assembly destination-assembly)
           #:id 'paired-equations))

  (check-equal? (map visual-id (group-visual-children paired-equations))
                '(source-equation destination-equation))

  ; matches : (listof formula-part-match?)
  ;;   Gives an explicit match order independent of either part order.
  (define matches
    (list (formula-part-match 'a 'a)
          (formula-part-match 'b 'b)
          (formula-part-match 'c 'c)
          (formula-part-match 'equals 'equals)))

  ; correspondence : formula-correspondence?
  ;;   Gives a checked one-to-one source-to-destination mapping.
  (define correspondence
    (formula-correspondence source-assembly
                            destination-assembly
                            matches))

  (check-eq? (formula-correspondence-source correspondence)
             source-assembly)
  (check-eq? (formula-correspondence-destination correspondence)
             destination-assembly)
  (check-equal? (formula-correspondence-matches correspondence)
                matches)
  (check-equal?
   (formula-correspondence-unmatched-source-names correspondence)
   '(plus))
  (check-equal?
   (formula-correspondence-unmatched-destination-names correspondence)
   '(minus))

  ;; No same-name inference occurs when the caller supplies no matches.
  ; empty-correspondence : formula-correspondence?
  ;;   Gives an explicit correspondence containing no matches.
  (define empty-correspondence
    (formula-correspondence source-assembly
                            destination-assembly
                            '()))

  (check-equal?
   (formula-correspondence-unmatched-source-names empty-correspondence)
   '(a plus b equals c))
  (check-equal?
   (formula-correspondence-unmatched-destination-names empty-correspondence)
   '(c minus a equals b))

  ;; Match structure guards require symbols.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-part-match "a" 'a)))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-part-match 'a "a")))

  ;; Correspondence validation rejects missing names and reuse on either side.
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-correspondence
      source-assembly
      destination-assembly
      (list (formula-part-match 'missing 'a)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-correspondence
      source-assembly
      destination-assembly
      (list (formula-part-match 'a 'missing)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-correspondence
      source-assembly
      destination-assembly
      (list (formula-part-match 'a 'a)
            (formula-part-match 'a 'b)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-correspondence
      source-assembly
      destination-assembly
      (list (formula-part-match 'a 'a)
            (formula-part-match 'b 'a)))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-correspondence source-assembly
                             destination-assembly
                             (list 'not-a-match))))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-correspondence part-a destination-assembly '())))
  (check-exn
   exn:fail:contract?
   (lambda ()
     (formula-correspondence source-assembly part-a '()))))
