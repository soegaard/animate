#lang racket/base

;;;
;;; SCENE-EK Deterministic Source-Match Planner Tests
;;;

(require rackunit
         racket/list
         "../main.rkt"
         (only-in "../private/formula-source-map.rkt"
                  make-formula-source-map)
         (only-in "../private/source-document.rkt"
                  source-document-from-strings
                  source-document-span-text)
         "../private/formula-source-normalization.rkt")

(module+ test
  ;; These formulas use the pure formula model directly.  EK planning must not
  ;; need LaTeX, dvisvgm, a renderer, or a sampled scene frame.
  (define (declared-formula id text declarations)
    ;; declarations : (listof (list symbol? exact-nonnegative-integer?
    ;;                                exact-nonnegative-integer?))
    (define document (source-document-from-strings (list text)))
    (define matches
      (for/list ([declaration (in-list declarations)])
        (define name (first declaration))
        (define span (source-span (second declaration) (third declaration)))
        (formula-source-match
         span
         (source-document-span-text document span)
         name
         (list (list name)))))
    (formula-assembly
     (for/list ([declaration (in-list declarations)])
       (define name (first declaration))
       (latex-formula-part
        (formula-source-match-text
         (for/first ([match (in-list matches)]
                     #:when (eq? name (formula-source-match-name match)))
           match))
        #:name name))
     #:id id
     #:source-map (make-formula-source-map document matches)))

  (define before
    (declared-formula
     'equation
     "x + 3 = 7"
     '((x 0 1) (plus 2 3) (three 4 5) (equals 6 7) (seven 8 9))))
  (define after
    (declared-formula
     'equation
     "x = 7 - 3"
     '((x 0 1) (equals 2 3) (seven 4 5) (minus 6 7) (three 8 9))))

  ;; The source normalizer deliberately ignores inter-token whitespace while
  ;; retaining TeX token boundaries and lexical structure.
  (check-equal?
   (normalize-formula-source "\\sin x")
   '((control-word "\\sin") (ordinary "x")))
  (check-equal?
   (map formula-source-unit-raw-key (formula-source-units before))
   '("x" "+" "3" "=" "7"))
  (check-equal?
   (drop (formula-source-units before) 3)
   (list
    (formula-source-unit
     (source-span 6 7) "=" '((ordinary "=")) '((equals)) 1)
    (formula-source-unit
     (source-span 8 9) "7" '((ordinary "7")) '((seven)) 1)))
  (check-equal?
   (take (drop (formula-source-units after) 1) 2)
   (list
    (formula-source-unit
     (source-span 2 3) "=" '((ordinary "=")) '((equals)) 1)
    (formula-source-unit
     (source-span 4 5) "7" '((ordinary "7")) '((seven)) 1)))

  ;; The largest exact source block is `= 7`; `x` and then the relocated `3`
  ;; are chosen on later passes.  Only the changed plus/minus remain unmatched.
  (define automatic (plan-matching-strings before after))
  (check-equal?
   (map planned-string-match-reason (string-match-plan-matches automatic))
   '(automatic-source-block automatic-source-block automatic-source-block))
  (check-equal?
   (map planned-string-match-source-span (string-match-plan-matches automatic))
   (list (source-span 6 9) (source-span 0 1) (source-span 4 5)))
  (check-equal?
   (map planned-string-match-destination-span (string-match-plan-matches automatic))
   (list (source-span 2 5) (source-span 0 1) (source-span 8 9)))
  (check-equal?
   (map formula-source-unit-raw-key
        (string-match-plan-unmatched-source automatic))
   '("+"))
  (check-equal?
   (map formula-source-unit-raw-key
        (string-match-plan-unmatched-destination automatic))
   '("-"))

  ;; An explicit map wins before automatic matching, including a deliberate
  ;; source spelling change.  The plan reports its changed movement policy.
  (define keyed
    (plan-matching-strings
     before after
     #:key-map (list (string-match "+" "-"))))
  (check-equal?
   (planned-string-match-reason
    (car (string-match-plan-matches keyed)))
   'explicit-key-map)
  (check-equal?
   (planned-string-match-movement-mode
    (car (string-match-plan-matches keyed)))
   'cross-fade)

  ;; A protected term is still usable by an explicit match but otherwise cannot
  ;; participate in automatic block matching.
  (define protected
    (plan-matching-strings before after #:protect-source (list "x")))
  (check-equal?
   (map formula-source-unit-raw-key
        (string-match-plan-unmatched-source protected))
   '("x" "+"))
  (check-true (pair? (string-match-plan-warnings protected)))

  ;; Explicit source spans have highest reporting priority and cannot consume
  ;; either source/destination unit twice.
  (define spans
    (plan-matching-strings
     before after
     #:matches
     (list (string-match (source-span 0 1) (source-span 0 1)))))
  (check-equal?
   (planned-string-match-reason
    (car (string-match-plan-matches spans)))
   'explicit-span)
  (check-exn
   exn:fail?
   (lambda ()
     (plan-matching-strings
      before after
      #:matches
      (list (string-match "x" "x")
            (string-match "x" "x")))))

  ;; Equal-quality but incompatible choices can be surfaced instead of hidden.
  ;; The default remains reproducible: earliest source span, then target span.
  (define reordered-before
    (declared-formula 'equation "x + y" '((x 0 1) (plus 2 3) (y 4 5))))
  (define reordered-after
    (declared-formula 'equation "y + x" '((y 0 1) (plus 2 3) (x 4 5))))
  (define left-to-right
    (plan-matching-strings reordered-before reordered-after))
  (check-equal?
   (planned-string-match-source-span
    (car (string-match-plan-matches left-to-right)))
   (source-span 0 1))
  (check-exn
   exn:fail?
   (lambda ()
     (plan-matching-strings
      reordered-before reordered-after
      #:on-ambiguity 'error)))

  (check-equal?
   (hash-ref (string-match-plan->datum automatic) 'diagnostics)
   '())

  ;; The animation adapter reuses the existing formula-part transition engine.
  ;; Its endpoint carries the destination source map, while its temporary
  ;; transition layers intentionally carry none.
  (define rewritten
    (scene-play
     (scene-add (make-scene) before)
     (transform-matching-strings
      before after
      #:key-map (list (string-match "+" "-")))
     #:duration 1))
  (define exact-source
    (scene-state-ref (scene-sample rewritten 0) 'equation))
  (define interior
    (scene-state-ref (scene-sample rewritten 1/2) 'equation))
  (define exact-destination
    (scene-state-ref (scene-current-state rewritten) 'equation))
  (check-equal? (formula-source exact-source) "x + 3 = 7")
  (check-false (formula-source-map interior))
  (check-equal? (formula-source exact-destination) "x = 7 - 3")
  (check-true (formula-source-map? (formula-source-map exact-destination)))

  ;; Anchoring resolves through source selectors and remains current-layout
  ;; relative when the scene compiler installs the rewrite.
  (define anchored
    (scene-play
     (scene-add (make-scene) before)
     (rewrite-matching-strings
      before after
      #:anchor "="
      #:stationary (list "x")
      #:key-map (list (string-match "+" "-")))
     #:duration 1))
  (check-equal?
   (formula-source
    (scene-state-ref (scene-current-state anchored) 'equation))
   "x = 7 - 3")

  ;; A copy leaves its source seven in place while introducing the otherwise
  ;; unmatched second seven in the destination formula.
  (define one-seven
    (declared-formula 'equation "x = 7" '((x 0 1) (equals 2 3) (seven 4 5))))
  (define two-sevens
    (declared-formula
     'equation
     "x = 7 + 7"
     '((x 0 1) (equals 2 3) (seven-1 4 5) (plus 6 7) (seven-2 8 9))))
  (define copied
    (scene-play
     (scene-add (make-scene) one-seven)
     (transform-matching-strings
      one-seven two-sevens
      #:copies
      (list
       (string-copy
        "7"
        (source-occurrence "7" 1)
        #:route (formula-arc #:angle 1/3))))
     #:duration 1))
  (check-equal?
   (formula-source
    (scene-state-ref (scene-current-state copied) 'equation))
   "x = 7 + 7"))
