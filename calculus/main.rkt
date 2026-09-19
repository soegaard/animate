#lang racket/base

;;;
;;; Calculus Declarations and Headless Inspection
;;;

;; Defines the public headless calculus API.  Contextual mathematical syntax is
;; introduced only inside model and lesson declarations; native output lives in
;; animate/calculus/render.


;;;
;;; Imports and Exports
;;;

;; Imports
(require "private/core.rkt"
         (for-syntax racket/base
                     racket/list))

;; Exports
(provide
 ;; Declarations.
 define-calculus-lesson
 define-calculus-model
 define-calculus-component

 ;; Inspection and compilation.
 calculus-lesson? calculus-model? calculus-component? calculus-plan?
 calculus-snapshot? calculus-result? calculus-moment?
 calculus-lesson-model calculus-model-at compile-calculus-lesson
 calculus-plan-duration calculus-plan-diagnostics calculus-plan-sample
 calculus-step-start calculus-step-end calculus-checkpoint
 calculus-snapshot-ref calculus-snapshot-visible? calculus-snapshot-diagnostics
 calculus-result-status calculus-result-method calculus-result-approximate?
 calculus-result-value calculus-result-message calculus-result->datum

 ;; Presentation and computation policies.
 calculus-profile calculus-profile? calculus-theme calculus-theme? calculus-style calculus-style?
 calculus-layout calculus-layout? calculus-motion calculus-motion? calculus-timing calculus-timing?
 calculus-computation calculus-computation? calculus-px calculus-rel calculus-em calculus-length?
 classroom-light-profile classroom-dark-profile textbook-profile default-calculus-profile
 light-calculus-theme dark-calculus-theme default-calculus-computation

 )


;;;
;;; Contextual Syntax Expansion
;;;

(begin-for-syntax
  ;; split-calculus-arguments : (listof syntax?) -> (values (listof syntax?) (listof (cons/c symbol? syntax?)))
  ;;   Separates ordinary operands from keyword/value pairs while preserving order.
  (define (split-calculus-arguments forms who)
    (let loop ([remaining forms] [positionals '()] [options '()])
      (cond
        [(null? remaining) (values (reverse positionals) (reverse options))]
        [(keyword? (syntax-e (car remaining)))
         (when (null? (cdr remaining))
           (raise-syntax-error who "keyword is missing its value" (car remaining)))
         (loop (cddr remaining)
               positionals
               (cons (cons (string->symbol (keyword->string (syntax-e (car remaining))))
                           (cadr remaining))
                     options))]
        [else (loop (cdr remaining) (cons (car remaining) positionals) options)])))

  ;; option-value : symbol? list? syntax? -> syntax?
  ;;   Selects one option or its default source expression.
  (define (option-value options name default)
    (define entry (assq name options))
    (if entry (cdr entry) default))

  ;; declaration-head : syntax? -> (or/c symbol? #f)
  ;;   Returns a list form's leading contextual spelling when available.
  (define (declaration-head form)
    (define pieces (syntax->list form))
    (and (pair? pieces) (identifier? (car pieces)) (syntax-e (car pieces))))

  ;; model-binding-expression : syntax? -> syntax?
  ;;   Expands one ordered [name expression] declaration into an immutable node.
  (define (model-binding-expression binding)
    (define pieces (syntax->list binding))
    (unless (and pieces (= (length pieces) 2) (identifier? (first pieces)))
      (raise-syntax-error 'model "expected [identifier expression]" binding))
    (define name (first pieces))
    (define expression (second pieces))
    #`[#,(datum->syntax name (syntax-e name))
       (bind-model-value '#,(syntax-e name) #,(lower-calculus-expression expression) #f)])

  ;; model-pairs-expression : (listof syntax?) -> (listof syntax?)
  ;;   Produces the stable public-name to node pairs retained by a model.
  (define (model-pairs-expression bindings)
    (for/list ([binding (in-list bindings)])
      (define pieces (syntax->list binding))
      (define name (first pieces))
      #`(cons '#,(syntax-e name) #,name)))

  ;; find-single-clause : symbol? (listof syntax?) -> (or/c syntax? #f)
  ;;   Finds a unique structural clause and reports duplicate declarations early.
  (define (find-single-clause name forms who)
    (define found (filter (lambda (form) (eq? (declaration-head form) name)) forms))
    (when (> (length found) 1)
      (raise-syntax-error who (format "duplicate ~a clause" name) (second found)))
    (and (pair? found) (first found)))

  ;; make-generic-expansion : syntax? symbol? -> syntax?
  ;;   Lowers a contextual constructor to one immutable generic descriptor.
  (define (make-generic-expansion stx name)
    (define forms (syntax->list stx))
    (unless forms (raise-syntax-error name "expected a proper application" stx))
    (define-values (positionals options) (split-calculus-arguments (cdr forms) name))
    (define option-forms
      (apply append
             (for/list ([option (in-list options)])
               (list #`'#,(car option) (cdr option)))))
    #`(make-generic '#,name (list #,@positionals) (hash #,@option-forms)))

  ;; make-view-expansion : syntax? symbol? -> syntax?
  ;;   Converts the documented #:objects parenthesized vocabulary into a list.
  (define (make-view-expansion stx name)
    (define forms (syntax->list stx))
    (define-values (positionals options) (split-calculus-arguments (cdr forms) name))
    (define option-forms
      (apply append
             (for/list ([option (in-list options)])
               (define value
                 (if (eq? (car option) 'objects)
                     (let ([objects (syntax->list (cdr option))])
                       (unless objects
                         (raise-syntax-error name "#:objects expects a parenthesized list" (cdr option)))
                       #`(list #,@objects))
                     (cdr option)))
               (list #`'#,(car option) value))))
    #`(make-generic '#,name (list #,@positionals) (hash #,@option-forms)))

  ;; calculus-contextual-name? : symbol? -> boolean?
  ;;   Recognizes only documented forms that are meaningful inside declarations.
  (define (calculus-contextual-name? name)
    (memq name
          '(+ - * / expt sqrt abs exp log sin cos tan asin acos atan = < <= > >= and or not if list
              parameter real-line empty-domain closed open closed-open open-closed singleton domain-union
              domain-intersection domain-except in-domain? integers procedure-function restrict-function
              compose-functions difference-function derivative-function antiderivative-function value-at
              declared-domain-of graph graph-restriction point point-on axis-point projection x-coordinate
              y-coordinate segment line-through ray-through horizontal-line vertical-line trace-of input-reading
              output-reading reading-branch coordinate-reading point-label graph-label quantity-label value-readout
              interval-marker endpoint-marker approach-marker chord secant increment difference-quotient slope
              slope-triangle tangent vertical-tangent normal point-on-line linearization approximation-error
              error-segment taylor-polynomial neighborhood punctured-neighborhood input-band output-band
              limit-statement epsilon-delta-condition continuity-condition asymptote-line definite-integral
              accumulation-function integral-region region-under region-between area-of partition uniform-partition
              tag-partition partition-marks riemann-sum riemann-rectangles trapezoidal-sum trapezoidal-regions
              sum-value refinement level-set solution-inputs root-point intersection-point sign-claim
              monotonicity-claim concavity-claim sign-chart feature-point sequence sequence-value partial-sum
              sequence-points iteration-map newton-iteration iterate-value newton-diagram snapshot-of formula
              formula-of ref value formula-occurrence quantity-correspondence graph-view formula-view number-line-view
              use-component
              part in-view show hide show-label hide-label deemphasize normalize highlight highlight-quantity read
              vary set-parameter approach trace refine limit-transition focus restore-view together compare pause
              checkpoint explain)))

  ;; lower-calculus-expression : syntax? (listof symbol?) (listof symbol?) -> syntax?
  ;;   Recursively lowers contextual source syntax before ordinary Racket expansion.
  (define (lower-calculus-expression expression [bound-variables '()] [view-names '()])
    (cond
      [(identifier? expression)
       (define name (syntax-e expression))
       (cond [(member name bound-variables) #`(c-expression 'var (list '#,name))]
             [(eq? name 'real-line) #'calculus-real-line]
             [(eq? name 'pi) #'calculus-pi]
             [(eq? name 'e) #'calculus-e]
             [else expression])]
      [else
       (define forms (syntax->list expression))
       (cond
         [(not forms) expression]
         [(null? forms) expression]
         [(and (identifier? (car forms)) (memq (syntax-e (car forms)) '(quote quasiquote))) expression]
         [(and (identifier? (car forms)) (eq? (syntax-e (car forms)) 'external))
          (unless (= (length forms) 2)
            (raise-syntax-error 'external "expects exactly one ordinary Racket expression" expression))
          (second forms)]
         [(and (identifier? (car forms)) (eq? (syntax-e (car forms)) 'function))
          (lower-function-expression expression bound-variables)]
         [(and (identifier? (car forms)) (eq? (syntax-e (car forms)) 'piecewise-function))
          (lower-piecewise-expression expression bound-variables)]
         [(and (identifier? (car forms)) (eq? (syntax-e (car forms)) 'sequence))
          (lower-sequence-expression expression bound-variables)]
         [(and (identifier? (car forms)) (eq? (syntax-e (car forms)) 'iteration-map))
          (lower-iteration-map-expression expression bound-variables)]
         [(and (identifier? (car forms)) (eq? (syntax-e (car forms)) 'step))
          (lower-step-expression expression bound-variables view-names)]
         [(and (identifier? (car forms)) (calculus-contextual-name? (syntax-e (car forms))))
          (lower-generic-expression expression bound-variables view-names)]
         [else #`(#,(lower-calculus-expression (car forms) bound-variables view-names)
                 #,@(map (lambda (form) (lower-calculus-expression form bound-variables view-names)) (cdr forms)))])]))

  ;; lower-generic-expression : syntax? (listof symbol?) -> syntax?
  ;;   Builds a generic descriptor while recursively lowering operands and options.
  ;; lower-snapshot-values : syntax? (listof symbol?) -> syntax?
  ;;   Preserves the documented #:values ([parameter constant] ...) syntax.
  (define (lower-snapshot-values expression bound-variables)
    (define bindings (syntax->list expression))
    (unless bindings
      (raise-syntax-error 'snapshot-of "#:values expects a parenthesized binding list" expression))
    #`(list
       #,@(for/list ([binding (in-list bindings)])
            (define pieces (syntax->list binding))
            (unless (and pieces (= (length pieces) 2) (identifier? (first pieces)))
              (raise-syntax-error 'snapshot-of "#:values expects [parameter constant]" binding))
            #`(cons #,(lower-calculus-expression (first pieces) bound-variables)
                    #,(lower-calculus-expression (second pieces) bound-variables)))))

  (define (lower-generic-expression expression bound-variables [view-names '()])
    (define forms (syntax->list expression))
    (define name (syntax-e (car forms)))
    (define-values (positionals options) (split-calculus-arguments (cdr forms) name))
    (define lowered-positionals
      (map (lambda (form)
             (if (and (memq name '(focus restore-view))
                      (identifier? form)
                      (member (syntax-e form) view-names))
                 #`(make-view-reference '#,(syntax-e form))
                 (lower-calculus-expression form bound-variables view-names)))
           positionals))
    (define option-forms
      (apply append
             (for/list ([option (in-list options)])
               (define lowered-value
                 (cond
                   [(and (eq? (car option) 'objects)
                         (memq name '(graph-view formula-view number-line-view)))
                   (define objects (syntax->list (cdr option)))
                   (unless objects
                     (raise-syntax-error name "#:objects expects a parenthesized list" (cdr option)))
                   #`(list #,@(map (lambda (item) (lower-calculus-expression item bound-variables view-names)) objects))]
                   [(and (eq? name 'snapshot-of) (eq? (car option) 'values))
                    (lower-snapshot-values (cdr option) bound-variables)]
                   [else (lower-calculus-expression (cdr option) bound-variables view-names)]))
               (list #`'#,(car option) lowered-value))))
    #`(make-generic '#,name (list #,@lowered-positionals) (hash #,@option-forms)))

  ;; lower-function-expression : syntax? (listof symbol?) -> syntax?
  ;;   Builds a held function with explicit lexical mathematical-variable substitution.
  (define (lower-function-expression expression bound-variables)
    (define forms (syntax->list expression))
    (unless (>= (length forms) 3)
      (raise-syntax-error 'function "expected a bound variable and body" expression))
    (define binder (syntax->list (second forms)))
    (unless (and binder (= (length binder) 1) (identifier? (first binder)))
      (raise-syntax-error 'function "expected one bound mathematical variable" (second forms)))
    (define variable (syntax-e (first binder)))
    (define-values (positionals options) (split-calculus-arguments (drop forms 3) 'function))
    (unless (null? positionals)
      (raise-syntax-error 'function "unexpected positional argument" (first positionals)))
    (define body (lower-calculus-expression (third forms) (cons variable bound-variables)))
    (define domain (lower-calculus-expression (option-value options 'domain #'calculus-real-line) bound-variables))
    (define label (lower-calculus-expression (option-value options 'label #'#f) bound-variables))
    #`(make-held-function '#,variable #,body #:domain #,domain #:label #,label))

  ;; lower-piecewise-expression : syntax? (listof symbol?) -> syntax?
  ;;   Preserves source branch order and lowers each condition under the bound variable.
  (define (lower-piecewise-expression expression bound-variables)
    (define forms (syntax->list expression))
    (define binder (and (>= (length forms) 2) (syntax->list (second forms))))
    (unless (and binder (= (length binder) 1) (identifier? (first binder)))
      (raise-syntax-error 'piecewise-function "expected one bound mathematical variable" expression))
    (define variable (syntax-e (first binder)))
    (define-values (raw-branches options) (split-calculus-arguments (drop forms 2) 'piecewise-function))
    (define else-expression #'#f)
    (define branches
      (for/fold ([result '()]) ([branch (in-list raw-branches)])
        (define pieces (syntax->list branch))
        (unless (and pieces (= (length pieces) 2))
          (raise-syntax-error 'piecewise-function "expected [condition expression]" branch))
        (if (and (identifier? (first pieces)) (eq? (syntax-e (first pieces)) 'else))
            (begin (set! else-expression (lower-calculus-expression (second pieces) (cons variable bound-variables))) result)
            (append result
                    (list #`(cons #,(lower-calculus-expression (first pieces) (cons variable bound-variables))
                                  #,(lower-calculus-expression (second pieces) (cons variable bound-variables))))))))
    (define domain (lower-calculus-expression (option-value options 'domain #'calculus-real-line) bound-variables))
    (define label (lower-calculus-expression (option-value options 'label #'#f) bound-variables))
    #`(make-piecewise-function '#,variable (list #,@branches) #,else-expression #:domain #,domain #:label #,label))

  ;; lower-sequence-expression : syntax? (listof symbol?) -> syntax?
  ;;   Holds the integer index as a lexical mathematical variable.
  (define (lower-sequence-expression expression bound-variables)
    (define forms (syntax->list expression))
    (unless (>= (length forms) 3)
      (raise-syntax-error 'sequence "expected an index binder and expression" expression))
    (define binder (syntax->list (second forms)))
    (unless (and binder (= (length binder) 1) (identifier? (first binder)))
      (raise-syntax-error 'sequence "expected one bound integer index" (second forms)))
    (define variable (syntax-e (first binder)))
    (define-values (positionals options) (split-calculus-arguments (drop forms 3) 'sequence))
    (unless (null? positionals)
      (raise-syntax-error 'sequence "unexpected positional argument" (first positionals)))
    #`(make-generic 'sequence
                    (list '#,variable
                          #,(lower-calculus-expression (third forms)
                                                       (cons variable bound-variables)))
                    (hash 'from
                          #,(lower-calculus-expression (option-value options 'from #'0)
                                                       bound-variables))))

  ;; lower-iteration-map-expression : syntax? (listof symbol?) -> syntax?
  ;;   Holds an iteration variable while retaining the finite update policy.
  (define (lower-iteration-map-expression expression bound-variables)
    (define forms (syntax->list expression))
    (unless (>= (length forms) 3)
      (raise-syntax-error 'iteration-map "expected a state binder and expression" expression))
    (define binder (syntax->list (second forms)))
    (unless (and binder (= (length binder) 1) (identifier? (first binder)))
      (raise-syntax-error 'iteration-map "expected one bound state variable" (second forms)))
    (define variable (syntax-e (first binder)))
    (define-values (positionals options) (split-calculus-arguments (drop forms 3) 'iteration-map))
    (unless (null? positionals)
      (raise-syntax-error 'iteration-map "unexpected positional argument" (first positionals)))
    #`(make-generic 'iteration-map
                    (list '#,variable
                          #,(lower-calculus-expression (third forms)
                                                       (cons variable bound-variables)))
                    (hash 'start
                          #,(lower-calculus-expression (option-value options 'start #'#f)
                                                       bound-variables)
                          'steps
                          #,(lower-calculus-expression (option-value options 'steps #'#f)
                                                       bound-variables))))

  ;; lower-step-expression : syntax? (listof symbol?) -> syntax?
  ;;   Turns a source step identifier into data and recursively lowers action commands.
  (define (lower-step-expression expression bound-variables [view-names '()])
    (define forms (syntax->list expression))
    (unless (and (>= (length forms) 2) (identifier? (second forms)))
      (raise-syntax-error 'step "expected a step identifier" expression))
    (define-values (commands options) (split-calculus-arguments (drop forms 2) 'step))
    (define id (syntax-e (second forms)))
    (define (option name) (lower-calculus-expression (option-value options name #'#f) bound-variables))
    #`(make-step '#,id #:say #,(option 'say) #:read-delay #,(option 'read-delay)
                 #:duration #,(option 'duration) #:pause #,(option 'pause)
                 #,@(map (lambda (command) (lower-calculus-expression command bound-variables view-names)) commands)))

  ;; lower-views-clause : syntax? (listof symbol?) -> syntax?
  ;;   Assigns declared view names to their independently lowered view descriptors.
  (define (lower-views-clause clause bound-variables)
    (define bindings (cdr (syntax->list clause)))
    (when (null? bindings) (raise-syntax-error 'views "requires at least one view" clause))
    #`(list
       #,@(for/list ([binding (in-list bindings)])
            (define pieces (syntax->list binding))
            (unless (and pieces (= (length pieces) 2) (identifier? (first pieces)))
              (raise-syntax-error 'views "expected [identifier view-expression]" binding))
            (define name (syntax-e (first pieces)))
            #`(cons '#,name (with-view-name #,(lower-calculus-expression (second pieces) bound-variables) '#,name)))))

  ;; lower-roles-clause : syntax? (listof symbol?) -> syntax?
  ;;   Preserves the role declaration's source ordering.
  (define (lower-roles-clause clause bound-variables)
    (if (not clause)
        #'null
        #`(list
           #,@(for/list ([assignment (in-list (cdr (syntax->list clause)))])
                (define pieces (syntax->list assignment))
                (unless (and pieces (= (length pieces) 2))
                  (raise-syntax-error 'roles "expected [target role-symbol]" assignment))
                #`(cons #,(lower-calculus-expression (first pieces) bound-variables)
                        #,(lower-calculus-expression (second pieces) bound-variables))))))

  ;; lower-command-clause : syntax? (listof symbol?) -> syntax?
  ;;   Lowers an initially clause's ordered persistent commands.
  (define (lower-command-clause clause bound-variables)
    (if clause
        #`(list #,@(map (lambda (command) (lower-calculus-expression command bound-variables))
                         (cdr (syntax->list clause))))
        #'null))

  ;; lower-timing-clause : syntax? (listof symbol?) -> syntax?
  ;;   Converts timing fields to constructor keywords while preserving expressions.
  (define (lower-timing-clause clause bound-variables)
    (if (not clause)
        #'#f
        (let ([arguments
               (apply append
                      (for/list ([field (in-list (cdr (syntax->list clause)))])
                        (define pieces (syntax->list field))
                        (unless (and pieces (= (length pieces) 2) (identifier? (first pieces)))
                          (raise-syntax-error 'timing "expected [timing-field seconds]" field))
                        (list (datum->syntax (first pieces)
                                             (string->keyword (symbol->string (syntax-e (first pieces)))))
                              (lower-calculus-expression (second pieces) bound-variables))))])
          #`(calculus-timing #,@arguments))))
  )

;; calculus-generic : contextual application -> immutable descriptor/expression
;;   Uses the call site's spelling as the semantic constructor name.
(define-syntax (calculus-generic stx)
  (define forms (syntax->list stx))
  (unless (and forms (identifier? (car forms)))
    (raise-syntax-error 'calculus "expected a contextual application" stx))
  (make-generic-expansion stx (syntax-e (car forms))))

;; calculus-graph-view : graph-view syntax -> c-view?
;;   Preserves the documented #:objects shorthand without making it a Racket call.
(define-syntax (calculus-graph-view stx) (make-view-expansion stx 'graph-view))

;; calculus-formula-view : formula-view syntax -> c-view?
;;   Preserves the documented #:objects shorthand without making it a Racket call.
(define-syntax (calculus-formula-view stx) (make-view-expansion stx 'formula-view))

;; calculus-number-line-view : number-line-view syntax -> c-view?
;;   Preserves the documented #:objects shorthand without making it a Racket call.
(define-syntax (calculus-number-line-view stx) (make-view-expansion stx 'number-line-view))

;; calculus-function : function declaration syntax -> held function descriptor
;;   Binds its one mathematical variable only inside the held expression.
(define-syntax (calculus-function stx)
  (define forms (syntax->list stx))
  (unless (and forms (>= (length forms) 3))
    (raise-syntax-error 'function "expected (function (variable) expression ...)" stx))
  (define binder (syntax->list (second forms)))
  (unless (and binder (= (length binder) 1) (identifier? (first binder)))
    (raise-syntax-error 'function "expected one bound mathematical variable" (second forms)))
  (define variable (first binder))
  (define body (third forms))
  (define-values (positionals options) (split-calculus-arguments (drop forms 3) 'function))
  (unless (null? positionals)
    (raise-syntax-error 'function "unexpected positional argument" (first positionals)))
  (define domain (option-value options 'domain #'calculus-real-line))
  (define label (option-value options 'label #'#f))
  #`(let ([#,variable (c-expression 'var (list '#,(syntax-e variable)))])
      (make-held-function '#,(syntax-e variable) #,body #:domain #,domain #:label #,label)))

;; calculus-piecewise-function : piecewise-function syntax -> held function descriptor
;;   Retains source-order branches and binds the variable only in branch syntax.
(define-syntax (calculus-piecewise-function stx)
  (define forms (syntax->list stx))
  (unless (and forms (>= (length forms) 2))
    (raise-syntax-error 'piecewise-function "expected a bound variable and branches" stx))
  (define binder (syntax->list (second forms)))
  (unless (and binder (= (length binder) 1) (identifier? (first binder)))
    (raise-syntax-error 'piecewise-function "expected one bound mathematical variable" (second forms)))
  (define variable (first binder))
  (define-values (raw-branches options) (split-calculus-arguments (drop forms 2) 'piecewise-function))
  (define else-expression #'#f)
  (define branch-expressions
    (for/list ([branch (in-list raw-branches)] #:unless #f)
      (define pieces (syntax->list branch))
      (unless (and pieces (= (length pieces) 2))
        (raise-syntax-error 'piecewise-function "expected [condition expression]" branch))
      (if (and (identifier? (first pieces)) (eq? (syntax-e (first pieces)) 'else))
          (begin (set! else-expression (second pieces)) #f)
          #`(cons #,(first pieces) #,(second pieces)))))
  (define branches (filter values branch-expressions))
  (define domain (option-value options 'domain #'calculus-real-line))
  (define label (option-value options 'label #'#f))
  #`(let ([#,variable (c-expression 'var (list '#,(syntax-e variable)))])
      (make-piecewise-function '#,(syntax-e variable) (list #,@branches) #,else-expression
                               #:domain #,domain #:label #,label)))

;; calculus-step : step syntax -> immutable action step
;;   Captures the step identifier as data rather than resolving it as a Racket value.
(define-syntax (calculus-step stx)
  (define forms (syntax->list stx))
  (unless (and forms (>= (length forms) 2) (identifier? (second forms)))
    (raise-syntax-error 'step "expected a step identifier" stx))
  (define id (second forms))
  (define-values (commands options) (split-calculus-arguments (drop forms 2) 'step))
  (define say (option-value options 'say #'#f))
  (define read-delay (option-value options 'read-delay #'#f))
  (define duration (option-value options 'duration #'#f))
  (define pause (option-value options 'pause #'#f))
  #`(make-step '#,(syntax-e id)
               #:say #,say #:read-delay #,read-delay #:duration #,duration #:pause #,pause
               #,@commands))

;; calculus-views : views clause -> ordered (symbol . c-view?) pairs
;;   Assigns the declaration names after the view expressions have been built.
(define-syntax (calculus-views stx)
  (define forms (syntax->list stx))
  (define bindings (cdr forms))
  (when (null? bindings) (raise-syntax-error 'views "requires at least one view" stx))
  (define pairs
    (for/list ([binding (in-list bindings)])
      (define pieces (syntax->list binding))
      (unless (and pieces (= (length pieces) 2) (identifier? (first pieces)))
        (raise-syntax-error 'views "expected [identifier view-expression]" binding))
      (define name (first pieces))
      #`(cons '#,(syntax-e name) (with-view-name #,(second pieces) '#,(syntax-e name)))))
  #`(list #,@pairs))

;; calculus-roles : roles clause -> immutable role assignments
;;   Preserves source order for deterministic style precedence diagnostics.
(define-syntax (calculus-roles stx)
  (define forms (syntax->list stx))
  (define assignments
    (for/list ([assignment (in-list (cdr forms))])
      (define pieces (syntax->list assignment))
      (unless (and pieces (= (length pieces) 2))
        (raise-syntax-error 'roles "expected [target role-symbol]" assignment))
      #`(cons #,(first pieces) #,(second pieces))))
  #`(list #,@assignments))

;; calculus-initially : initially clause -> list of persistent action descriptors
;;   Leaves command legality to the pure compiler, which can report all context.
(define-syntax (calculus-initially stx)
  (define forms (syntax->list stx))
  #`(list #,@(cdr forms)))

;; calculus-constraints : constraints clause -> list of held Boolean expressions
;;   Keeps declaration ordering for deterministic diagnostics.
(define-syntax (calculus-constraints stx)
  (define forms (syntax->list stx))
  #`(list #,@(cdr forms)))

;; calculus-timing-clause : timing clause -> calculus-timing?
;;   Converts [field value] declarations to the ordinary timing constructor.
(define-syntax (calculus-timing-clause stx)
  (define forms (syntax->list stx))
  (define arguments
    (apply append
           (for/list ([field (in-list (cdr forms))])
             (define pieces (syntax->list field))
             (unless (and pieces (= (length pieces) 2) (identifier? (first pieces)))
               (raise-syntax-error 'timing "expected [timing-field seconds]" field))
             (list (datum->syntax (first pieces)
                                  (string->keyword (symbol->string (syntax-e (first pieces)))))
                   (second pieces)))))
  #`(calculus-timing #,@arguments))

;; with-calculus-context : form ... -> any/c
;;   Installs all contextual DSL spellings only around one generated declaration body.
(begin-for-syntax
  ;; These values let the generated let-syntax form reuse definition-site
  ;; transformers without requiring client modules to import internal helpers.
  (define calculus-generic (syntax-local-value #'calculus-generic))
  (define calculus-graph-view (syntax-local-value #'calculus-graph-view))
  (define calculus-formula-view (syntax-local-value #'calculus-formula-view))
  (define calculus-number-line-view (syntax-local-value #'calculus-number-line-view))
  (define calculus-function (syntax-local-value #'calculus-function))
  (define calculus-piecewise-function (syntax-local-value #'calculus-piecewise-function))
  (define calculus-step (syntax-local-value #'calculus-step))
  (define calculus-views (syntax-local-value #'calculus-views))
  (define calculus-roles (syntax-local-value #'calculus-roles))
  (define calculus-initially (syntax-local-value #'calculus-initially))
  (define calculus-constraints (syntax-local-value #'calculus-constraints))
  (define calculus-timing-clause (syntax-local-value #'calculus-timing-clause)))

(define-syntax-rule (with-calculus-context body ...)
  (let-syntax ([+ calculus-generic] [- calculus-generic] [* calculus-generic] [/ calculus-generic]
               [expt calculus-generic] [sqrt calculus-generic] [abs calculus-generic]
               [exp calculus-generic] [log calculus-generic] [sin calculus-generic] [cos calculus-generic]
               [tan calculus-generic] [asin calculus-generic] [acos calculus-generic] [atan calculus-generic]
               [= calculus-generic] [< calculus-generic] [<= calculus-generic] [> calculus-generic] [>= calculus-generic]
               [and calculus-generic] [or calculus-generic] [not calculus-generic] [if calculus-generic] [list calculus-generic]
               [parameter calculus-generic] [real-line (make-rename-transformer #'calculus-real-line)]
               [empty-domain calculus-generic] [closed calculus-generic] [open calculus-generic]
               [closed-open calculus-generic] [open-closed calculus-generic] [singleton calculus-generic]
               [domain-union calculus-generic] [domain-intersection calculus-generic] [domain-except calculus-generic]
               [in-domain? calculus-generic] [integers calculus-generic]
               [function calculus-function] [piecewise-function calculus-piecewise-function]
               [procedure-function calculus-generic] [restrict-function calculus-generic] [compose-functions calculus-generic]
               [difference-function calculus-generic] [derivative-function calculus-generic] [antiderivative-function calculus-generic]
               [value-at calculus-generic] [declared-domain-of calculus-generic]
               [graph calculus-generic] [graph-restriction calculus-generic] [point calculus-generic] [point-on calculus-generic]
               [axis-point calculus-generic] [projection calculus-generic] [x-coordinate calculus-generic] [y-coordinate calculus-generic]
               [segment calculus-generic] [line-through calculus-generic] [ray-through calculus-generic]
               [horizontal-line calculus-generic] [vertical-line calculus-generic] [trace-of calculus-generic]
               [input-reading calculus-generic] [output-reading calculus-generic] [reading-branch calculus-generic]
               [coordinate-reading calculus-generic] [point-label calculus-generic] [graph-label calculus-generic]
               [quantity-label calculus-generic] [value-readout calculus-generic] [interval-marker calculus-generic]
               [endpoint-marker calculus-generic] [approach-marker calculus-generic]
               [chord calculus-generic] [secant calculus-generic] [increment calculus-generic]
               [difference-quotient calculus-generic] [slope calculus-generic] [slope-triangle calculus-generic]
               [tangent calculus-generic] [vertical-tangent calculus-generic] [normal calculus-generic]
               [point-on-line calculus-generic] [linearization calculus-generic] [approximation-error calculus-generic]
               [error-segment calculus-generic] [taylor-polynomial calculus-generic]
               [neighborhood calculus-generic] [punctured-neighborhood calculus-generic] [input-band calculus-generic]
               [output-band calculus-generic] [limit-statement calculus-generic] [epsilon-delta-condition calculus-generic]
               [continuity-condition calculus-generic] [asymptote-line calculus-generic]
               [definite-integral calculus-generic] [accumulation-function calculus-generic] [integral-region calculus-generic]
               [region-under calculus-generic] [region-between calculus-generic] [area-of calculus-generic]
               [partition calculus-generic] [uniform-partition calculus-generic] [tag-partition calculus-generic]
               [partition-marks calculus-generic] [riemann-sum calculus-generic] [riemann-rectangles calculus-generic]
               [trapezoidal-sum calculus-generic] [trapezoidal-regions calculus-generic] [sum-value calculus-generic]
               [refinement calculus-generic] [level-set calculus-generic] [solution-inputs calculus-generic]
               [root-point calculus-generic] [intersection-point calculus-generic] [sign-claim calculus-generic]
               [monotonicity-claim calculus-generic] [concavity-claim calculus-generic] [sign-chart calculus-generic]
               [feature-point calculus-generic] [sequence calculus-generic] [sequence-value calculus-generic]
               [partial-sum calculus-generic] [sequence-points calculus-generic] [iteration-map calculus-generic]
               [newton-iteration calculus-generic] [iterate-value calculus-generic] [newton-diagram calculus-generic]
               [snapshot-of calculus-generic] [formula calculus-generic] [formula-of calculus-generic]
               [ref calculus-generic] [value calculus-generic] [formula-occurrence calculus-generic]
               [quantity-correspondence calculus-generic]
               [graph-view calculus-graph-view] [formula-view calculus-formula-view] [number-line-view calculus-number-line-view]
               [part calculus-generic] [in-view calculus-generic]
               [show calculus-generic] [hide calculus-generic] [show-label calculus-generic] [hide-label calculus-generic]
               [deemphasize calculus-generic] [normalize calculus-generic] [highlight calculus-generic]
               [highlight-quantity calculus-generic] [read calculus-generic] [vary calculus-generic]
               [set-parameter calculus-generic] [approach calculus-generic] [trace calculus-generic]
               [refine calculus-generic] [limit-transition calculus-generic] [focus calculus-generic]
               [restore-view calculus-generic] [together calculus-generic] [compare calculus-generic]
               [pause calculus-generic] [checkpoint calculus-generic] [explain calculus-generic]
               [views calculus-views] [roles calculus-roles] [initially calculus-initially]
               [constraints calculus-constraints] [timing calculus-timing-clause]
               [step calculus-step] [pi (make-rename-transformer #'calculus-pi)]
               [e (make-rename-transformer #'calculus-e)])
    body ...))


;;;
;;; Public Declaration Forms
;;;

;; define-calculus-model : identifier model-clause [constraints-clause] -> definition
;;   Defines one immutable mathematical dependency model without views or actions.
(define-syntax (define-calculus-model stx)
  (define forms (syntax->list stx))
  (unless (and forms (>= (length forms) 3) (identifier? (second forms)))
    (raise-syntax-error 'define-calculus-model "expected a model identifier and (model ...) clause" stx))
  (define id (second forms))
  (define clauses (drop forms 2))
  (define model-clause (find-single-clause 'model clauses 'define-calculus-model))
  (unless model-clause (raise-syntax-error 'define-calculus-model "requires one (model ...) clause" stx))
  (define constraints-clause (find-single-clause 'constraints clauses 'define-calculus-model))
  (define bindings (cdr (syntax->list model-clause)))
  (define constraints
    (if constraints-clause
        (map lower-calculus-expression (cdr (syntax->list constraints-clause)))
        '()))
  (define bound-bindings (map model-binding-expression bindings))
  (define pairs (model-pairs-expression bindings))
  #`(define #,id
      (let* (#,@bound-bindings)
        (make-model (list #,@pairs) (list #,@constraints)))))

;; define-calculus-lesson : identifier model/views clauses and steps -> definition
;;   Defines one immutable lesson; it does not prepare fonts, Picts, scenes, or files.
(define-syntax (define-calculus-lesson stx)
  (define forms (syntax->list stx))
  (unless (and forms (>= (length forms) 4) (identifier? (second forms)))
    (raise-syntax-error 'define-calculus-lesson "expected a lesson identifier and declaration clauses" stx))
  (define id (second forms))
  (define clauses (drop forms 2))
  (define model-clause (find-single-clause 'model clauses 'define-calculus-lesson))
  (define views-clause (find-single-clause 'views clauses 'define-calculus-lesson))
  (unless model-clause (raise-syntax-error 'define-calculus-lesson "requires one (model ...) clause" stx))
  (unless views-clause (raise-syntax-error 'define-calculus-lesson "requires one (views ...) clause" stx))
  (define roles-clause (find-single-clause 'roles clauses 'define-calculus-lesson))
  (define initially-clause (find-single-clause 'initially clauses 'define-calculus-lesson))
  (define constraints-clause (find-single-clause 'constraints clauses 'define-calculus-lesson))
  (define timing-clause (find-single-clause 'timing clauses 'define-calculus-lesson))
  (define steps (filter (lambda (form) (eq? (declaration-head form) 'step)) clauses))
  (when (null? steps) (raise-syntax-error 'define-calculus-lesson "requires at least one (step ...) clause" stx))
  (define bindings (cdr (syntax->list model-clause)))
  (define bound-bindings (map model-binding-expression bindings))
  (define pairs (model-pairs-expression bindings))
  (define constraints
    (if constraints-clause
        (map lower-calculus-expression (cdr (syntax->list constraints-clause)))
        '()))
  (define roles (lower-roles-clause roles-clause '()))
  (define initially (lower-command-clause initially-clause '()))
  (define timing (lower-timing-clause timing-clause '()))
  (define lowered-views (lower-views-clause views-clause '()))
  (define view-names
    (for/list ([binding (in-list (cdr (syntax->list views-clause)))])
      (syntax-e (first (syntax->list binding)))))
  (define lowered-steps
    (map (lambda (form) (lower-step-expression form '() view-names)) steps))
  #`(define #,id
      (let* (#,@bound-bindings)
        (define lesson-model (make-model (list #,@pairs) (list #,@constraints)))
        (make-lesson lesson-model
                     #,lowered-views
                     #,roles
                     #,initially
                     #,timing
                     (list #,@lowered-steps))))
  )

;; define-calculus-component : identifier component descriptor -> definition
;;   Records a reusable component declaration; invocation support is completed by the model stage.
(define-syntax (define-calculus-component stx)
  (define forms (syntax->list stx))
  (unless (and forms (>= (length forms) 2) (identifier? (second forms)))
    (raise-syntax-error 'define-calculus-component "expected a component identifier" stx))
  (define id (second forms))
  (define clauses (drop forms 2))
  (define inputs-clause (find-single-clause 'inputs clauses 'define-calculus-component))
  (define model-clause (find-single-clause 'model clauses 'define-calculus-component))
  (define exports-clause (find-single-clause 'exports clauses 'define-calculus-component))
  (unless (and inputs-clause model-clause exports-clause)
    (raise-syntax-error 'define-calculus-component "requires inputs, model, and exports clauses" stx))
  (define constraints-clause (find-single-clause 'constraints clauses 'define-calculus-component))
  (define exposition-clause (find-single-clause 'exposition clauses 'define-calculus-component))
  #`(define #,id
      (make-component '#,(syntax-e id)
                      '#,(cdr (syntax->list inputs-clause))
                      '#,(cdr (syntax->list model-clause))
                      '#,(cdr (syntax->list exports-clause))
                      '#,(if constraints-clause (cdr (syntax->list constraints-clause)) '())
                      '#,(if exposition-clause (cdr (syntax->list exposition-clause)) '()))))
