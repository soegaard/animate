#lang racket/base

;; Elaboration and geometry-type checking. No eval, namespace mutation or GUI.
;; Builder mutation is local to elaboration; the returned graph is immutable.
(require racket/list racket/match racket/string
         "math.rkt" "data.rkt" "vocabulary.rkt" "reveal.rkt" "narration.rkt")
(provide make-construction-program make-construction-helper
         infer-expression-type expression-references substitute-expression)

(define curve-types '(Line Segment Ray Circle))
(define linear-types '(Line Segment Ray))
(define relation-types '(Relation Angle))
(define (lookup-type env id who)
  (hash-ref env id (lambda () (geometry-error who "unknown or forward geometry reference ~a" id))))
(define (expect-type actual expected who expression)
  (unless (equal? actual expected)
    (geometry-error who "expected ~a, received ~a in ~e" expected actual expression)))
(define (expect-count xs n who expression)
  (unless (= (length xs) n)
    (geometry-error who "expected ~a arguments in ~e" n expression)))

(define default-program-timing (geometry-timing 0.6 1.0 0.9 0.5))
(define (nonnegative-real! who label value)
  (unless (and (finite-real? value) (>= value 0))
    (geometry-error who "~a must be a nonnegative real, received ~e" label value))
  value)
(define (positive-real! who label value)
  (unless (and (finite-real? value) (> value 0))
    (geometry-error who "~a must be a positive real, received ~e" label value))
  value)
(define (parse-timing-clause who clause)
  (define seen '())
  (define table (make-hash))
  (for ([entry (in-list (cdr clause))])
    (unless (and (list? entry) (= (length entry) 2) (symbol? (car entry)))
      (geometry-error who "timing expects [name value] entries, received ~e" entry))
    (define key (car entry))
    (define value (cadr entry))
    (when (memq key seen) (geometry-error who "duplicate timing setting ~a" key))
    (case key
      [(opening-pause read-delay step-pause) (nonnegative-real! who key value)]
      [(action-duration) (positive-real! who key value)]
      [else (geometry-error who "unknown timing setting ~a" key)])
    (set! seen (cons key seen))
    (hash-set! table key value))
  (geometry-timing (hash-ref table 'opening-pause (geometry-timing-opening-pause default-program-timing))
                   (hash-ref table 'read-delay (geometry-timing-read-delay default-program-timing))
                   (hash-ref table 'action-duration (geometry-timing-action-duration default-program-timing))
                   (hash-ref table 'step-pause (geometry-timing-step-pause default-program-timing))))
(define (parse-step-timing-overrides who items)
  (let loop ([rest items] [seen '()] [acc (hash)])
    (cond
      [(and (pair? rest) (keyword? (car rest)))
       (unless (pair? (cdr rest)) (geometry-error who "step timing keyword ~a needs a value" (car rest)))
       (define key (car rest))
       (define value (cadr rest))
       (when (memq key seen) (geometry-error who "duplicate step timing keyword ~a" key))
       (case key
         [(#:read-delay) (nonnegative-real! who key value) (loop (cddr rest) (cons key seen) (hash-set acc 'read-delay value))]
         [(#:duration) (positive-real! who key value) (loop (cddr rest) (cons key seen) (hash-set acc 'duration value))]
         [(#:pause) (nonnegative-real! who key value) (loop (cddr rest) (cons key seen) (hash-set acc 'pause value))]
         [else (geometry-error who "unknown step timing keyword ~a" key)])]
      [else (values acc rest)])))

;; infer-expression-type : expression-datum type-table provenance -> type-symbol
;; Helpers have already been inlined when this is called on stored graph nodes.
(define (infer-expression-type e env who)
  (define (infer x) (infer-expression-type x env who))
  (define (all-of xs type)
    (for ([x (in-list xs)]) (expect-type (infer x) type who x)))
  (define (relation-expression-type x)
    (unless (and (list? x) (pair? x)) (geometry-error who "invalid relation expression ~e" x))
    (case (car x)
      [(angle)
       (expect-count (cdr x) 3 who x)
       (all-of (cdr x) 'Point)
       'Angle]
      [(perpendicular)
       (unless (or (= (length (cdr x)) 2) (= (length (cdr x)) 4))
         (geometry-error who "perpendicular expects two linear objects and optional #:at point"))
       (for ([arg (in-list (take (cdr x) 2))])
         (unless (memq (infer arg) linear-types)
           (geometry-error who "perpendicular expects line, segment or ray arguments")))
       (when (= (length (cdr x)) 4)
         ;; x = (perpendicular first second #:at point)
         (unless (eq? (cadddr x) '#:at) (geometry-error who "expected #:at in ~e" x))
         (expect-type (infer (list-ref x 4)) 'Point who x))
       'Relation]
      [(parallel)
       (expect-count (cdr x) 2 who x)
       (for ([arg (in-list (cdr x))])
         (unless (memq (infer arg) linear-types)
           (geometry-error who "parallel expects line, segment or ray arguments")))
       'Relation]
      [(equal-length)
       (unless (>= (length (cdr x)) 2) (geometry-error who "equal-length expects at least two segments"))
       (all-of (cdr x) 'Segment)
       'Relation]
      [(equal-angle)
       (unless (>= (length (cdr x)) 2) (geometry-error who "equal-angle expects at least two angles"))
       (for ([arg (in-list (cdr x))])
         (expect-type (infer arg) 'Angle who arg))
       'Relation]
      [(collinear)
       (unless (>= (length (cdr x)) 3) (geometry-error who "collinear expects at least three points"))
       (all-of (cdr x) 'Point)
       'Relation]
      [(midpoint-of)
       (expect-count (cdr x) 2 who x)
       (expect-type (infer (cadr x)) 'Point who x)
       (expect-type (infer (caddr x)) 'Segment who x)
       'Relation]
      [else (geometry-error who "unsupported relation expression ~a" (car x))]))
  (cond
    [(finite-real? e) 'Number]
    [(boolean? e) 'Boolean]
    [(string? e) 'Text]
    [(symbol? e) (lookup-type env e who)]
    [(not (and (list? e) (pair? e))) (geometry-error who "invalid geometry expression ~e" e)]
    [else
     (define op (car e))
     (define args (cdr e))
     (case op
       [(quote)
        (unless (and (= (length args) 1) (symbol? (car args)))
          (geometry-error who "only quoted selector symbols are allowed here: ~e" e))
        (if (memq (car args) '(left right)) 'Side 'Selector)]
       [(vector)
        (expect-count args 2 who e) (all-of args 'Number) 'Vector]
       [(vector-between)
        (expect-count args 2 who e) (all-of args 'Point) 'Vector]
       [(vector-x vector-y)
        (expect-count args 1 who e) (all-of args 'Vector) 'Number]
       [(degrees)
        (expect-count args 1 who e) (all-of args 'Number) 'Number]
       [(identity-transform)
        (expect-count args 0 who e) 'Transform]
       [(translation)
        (expect-count args 1 who e) (all-of args 'Vector) 'Transform]
       [(rotation dilation)
        (expect-count args 2 who e)
        (expect-type (infer (car args)) 'Point who e)
        (expect-type (infer (cadr args)) 'Number who e)
        (when (and (eq? op 'dilation) (number? (cadr args)) (zero? (cadr args)))
          (geometry-error who "dilation scale must be nonzero"))
        'Transform]
       [(reflection)
        (expect-count args 1 who e) (all-of args 'Line) 'Transform]
       [(compose-transform)
        (all-of args 'Transform) 'Transform]
       [(inverse-transform transformation-scale transformation-orientation)
        (expect-count args 1 who e) (all-of args 'Transform)
        (if (eq? op 'inverse-transform) 'Transform 'Number)]
       [(transform translate rotate reflect dilate)
        (expect-count args (if (memq op '(rotate dilate)) 3 2) who e)
        (define object (if (eq? op 'transform) (cadr args) (car args)))
        (define type (infer object))
        (unless (memq type '(Point Line Segment Ray Circle Angle Relation Marker))
          (geometry-error who "~a cannot transform ~a; recreate labels on transformed geometry" op type))
        (case op
          [(transform) (expect-type (infer (car args)) 'Transform who e)]
          [(translate) (expect-type (infer (cadr args)) 'Vector who e)]
          [(reflect) (expect-type (infer (cadr args)) 'Line who e)]
          [else
           (expect-type (infer (cadr args)) 'Point who e)
           (expect-type (infer (caddr args)) 'Number who e)
           (when (and (eq? op 'dilate) (number? (caddr args)) (zero? (caddr args)))
             (geometry-error who "dilation scale must be nonzero"))])
        type]
       [(point-label segment-label length-label angle-label)
        (unless (pair? args) (geometry-error who "~a needs a target" op))
        (expect-type (infer (car args))
                     (case op [(point-label) 'Point] [(angle-label) 'Angle] [else 'Segment]) who e)
        (define rest (cdr args))
        (define has-text? (and (pair? rest) (not (keyword? (car rest)))))
        (when has-text?
          (expect-type (infer (car rest)) 'Text who e)
          (when (and (string? (car rest))
                     (or (string=? (string-trim (car rest)) "")
                         (regexp-match? #rx"[\r\n\t]" (car rest))))
            (geometry-error who "label text must be a nonempty single line without tabs"))
          (set! rest (cdr rest)))
        (when (and (memq op '(point-label segment-label)) (not has-text?))
          (geometry-error who "~a requires text" op))
        (let loop ([remaining rest] [seen '()])
          (unless (null? remaining)
            (unless (and (pair? (cdr remaining)) (keyword? (car remaining)))
              (geometry-error who "expected label keyword/value pairs in ~e" e))
            (define key (car remaining)) (define value (cadr remaining))
            (when (memq key seen) (geometry-error who "duplicate label option ~a" key))
            (case key
              [(#:precision)
               (unless (memq op '(length-label angle-label)) (geometry-error who "~a does not accept #:precision" op))
               (expect-type (infer value) 'Number who e)
               (when (and (number? value) (not (and (exact-integer? value) (<= 0 value 12))))
                 (geometry-error who "label precision must be an integer from 0 to 12"))]
              [(#:unit)
               (unless (and (eq? op 'length-label) (not has-text?))
                 (geometry-error who "#:unit is for measured length labels only"))
               (expect-type (infer value) 'Text who e)]
              [(#:arc?)
               (unless (eq? op 'angle-label) (geometry-error who "#:arc? belongs to angle-label"))
               (expect-type (infer value) 'Boolean who e)]
              [else (geometry-error who "unknown label option ~a" key)])
            (loop (cddr remaining) (cons key seen))))
        'Label]
       [(point)
        (unless (or (null? args) (= (length args) 2))
          (geometry-error who "point expects zero (free given) or two arguments"))
        (all-of args 'Number) 'Point]
       [(line segment ray)
        (expect-count args 2 who e) (all-of args 'Point)
        (case op [(line) 'Line] [(segment) 'Segment] [else 'Ray])]
       [(circle)
        (cond [(= (length args) 2) (all-of args 'Point)]
              [(and (= (length args) 3) (eq? (cadr args) '#:radius))
               (expect-type (infer (car args)) 'Point who e)
               (expect-type (infer (caddr args)) 'Number who e)]
              [else (geometry-error who "circle expects centre/through points or centre #:radius length")])
        'Circle]
       [(start-point end-point)
        (expect-count args 1 who e)
        (unless (memq (infer (car args)) linear-types)
          (geometry-error who "~a expects a line, segment or ray" op))
        'Point]
       [(angle-first angle-vertex angle-last)
        (expect-count args 1 who e) (all-of args 'Angle) 'Point]
       [(side-of?)
        (expect-count args 3 who e)
        (expect-type (infer (car args)) 'Point who e)
        (unless (memq (infer (cadr args)) linear-types)
          (geometry-error who "side-of? expects a directed line, segment or ray"))
        (expect-type (infer (caddr args)) 'Side who e) 'Boolean]
       [(midpoint distance)
        (expect-count args 2 who e) (all-of args 'Point)
        (if (eq? op 'midpoint) 'Point 'Number)]
       [(center)
        (expect-count args 1 who e) (all-of args 'Circle) 'Point]
       [(length)
        (expect-count args 1 who e) (all-of args 'Segment) 'Number]
       [(marker)
        (expect-count args 1 who e)
        (when (and (pair? (car args)) (eq? (caar args) 'collinear))
          (geometry-error who "collinear is assertable but has no built-in marker"))
        (unless (memq (infer (car args)) relation-types)
          (geometry-error who "marker expects a drawable relation or angle"))
        'Marker]
       [(angle perpendicular parallel equal-length equal-angle collinear midpoint-of) (relation-expression-type e)]
       [(intersection intersections)
        (unless (>= (length args) 2) (geometry-error who "two curves are required in ~e" e))
        (for ([x (in-list (take args 2))])
          (unless (memq (infer x) curve-types) (geometry-error who "expected a curve in ~e" e)))
        (if (eq? op 'intersections)
            (begin (expect-count args 2 who e) 'PointList)
            (begin
              (let loop ([rest (drop args 2)] [seen '()])
                (unless (null? rest)
                  (define key (car rest))
                  (when (memq key seen) (geometry-error who "repeated intersection selector ~a" key))
                  (case key
                    [(#:side-of)
                     (unless (>= (length rest) 3) (geometry-error who "#:side-of needs a directed object and side"))
                     (unless (memq (infer (cadr rest)) '(Line Segment Ray))
                       (geometry-error who "#:side-of requires a directed line, segment or ray"))
                     (expect-type (infer (caddr rest)) 'Side who e)
                     (loop (cdddr rest) (cons key seen))]
                    [(#:other-than #:near #:far-from)
                     (unless (>= (length rest) 2) (geometry-error who "missing point for ~a" key))
                     (expect-type (infer (cadr rest)) 'Point who (cadr rest))
                     (when (and (memq key '(#:near #:far-from))
                                (ormap (lambda (k) (memq k '(#:near #:far-from))) seen))
                       (geometry-error who "use #:near or #:far-from, not both"))
                     (loop (cddr rest) (cons key seen))]
                    [else (geometry-error who "unknown intersection selector ~e" key)])))
              'Point))]
       [(choose)
        (expect-count args 1 who e)
        (expect-type (infer (car args)) 'PointDomain who e) 'Point]
       [(point-on)
        (unless (or (= (length args) 1) (= (length args) 3))
          (geometry-error who "point-on expects a curve and optional #:except point"))
        (unless (memq (infer (car args)) curve-types) (geometry-error who "point-on expects a curve"))
        (when (= (length args) 3)
          (unless (eq? (cadr args) '#:except) (geometry-error who "expected #:except in ~e" e))
          (expect-type (infer (caddr args)) 'Point who e))
        'PointDomain]
       [(distinct?) (expect-count args 2 who e) (all-of args 'Point) 'Boolean]
       [(noncollinear?) (expect-count args 3 who e) (all-of args 'Point) 'Boolean]
       [(on)
        (expect-count args 2 who e) (expect-type (infer (car args)) 'Point who e)
        (unless (memq (infer (cadr args)) curve-types) (geometry-error who "on expects a curve"))
        'Boolean]
       [(and or not)
        (when (eq? op 'not) (expect-count args 1 who e))
        (for ([x (in-list args)])
          (unless (memq (infer x) '(Boolean Relation))
            (geometry-error who "~a needs Boolean or relation operands" op)))
        'Boolean]
       [(+ * - /)
        (when (and (memq op '(- /)) (null? args)) (geometry-error who "~a needs an argument" op))
        (all-of args 'Number) 'Number]
       [(= < > <= >=)
        (unless (>= (length args) 2) (geometry-error who "comparison needs at least two numbers"))
        (all-of args 'Number) 'Boolean]
       [(expect-points)
        (expect-count args 2 who e)
        (unless (exact-positive-integer? (car args)) (geometry-error who "invalid result count"))
        (expect-type (infer (cadr args)) 'PointList who e) 'PointList]
       [(select-point)
        (expect-count args 2 who e)
        (expect-type (infer (car args)) 'PointList who e)
        (unless (exact-nonnegative-integer? (cadr args)) (geometry-error who "invalid result index"))
        'Point]
       [else (geometry-error who "unsupported expression/operator ~a" op)])]))

(define (expression-references e)
  (cond [(symbol? e) (list e)]
        [(and (list? e) (pair? e) (not (eq? (car e) 'quote)))
         (remove-duplicates (append-map expression-references (cdr e)))]
        [else '()]))
(define (substitute-expression e substitutions)
  (cond [(symbol? e) (hash-ref substitutions e e)]
        [(and (list? e) (pair? e) (not (eq? (car e) 'quote)))
         (cons (car e) (map (lambda (a) (substitute-expression a substitutions)) (cdr e)))]
        [else e]))

(define (make-construction-program name clauses helpers source)
  (finalize-program-narration (compile-program name clauses helpers source #f)))
(define (make-construction-helper name clauses helpers source)
  (define givens (filter (lambda (c) (and (pair? c) (eq? (car c) 'given))) clauses))
  (define result-clauses (filter (lambda (c) (and (pair? c) (eq? (car c) 'results))) clauses))
  (unless (= (length givens) 1) (geometry-error name "helper needs one typed given clause"))
  (unless (= (length result-clauses) 1) (geometry-error name "helper needs one results signature"))
  (define parameters
    (for/list ([b (in-list (cdar givens))])
      (match b
        [(list (? symbol? id) ': type)
         (unless (memq type geometry-types) (geometry-error name "unknown input type ~a" type))
         (cons id type)]
        [_ (geometry-error name "input types are mandatory; expected [name : Type], received ~e" b)])))
  (define result-types (cdar result-clauses))
  (unless (and (pair? result-types) (andmap (lambda (t) (memq t geometry-types)) result-types))
    (geometry-error name "results must declare one or more supported types"))
  (define program (compile-program name clauses helpers source parameters))
  (define types (for/hash ([n (in-list (geometry-program-nodes program))])
                  (values (geometry-node-id n) (geometry-node-type n))))
  (expect-count (geometry-program-results program) (length result-types) name '(result ...))
  (for ([id (in-list (geometry-program-results program))] [type (in-list result-types)])
    (expect-type (lookup-type types id name) type name id))
  (construction-helper name parameters result-types program))

(define (compile-program name clauses helpers source parameters)
  (unless (and (symbol? name) (list? clauses) (hash? helpers))
    (geometry-error 'construction "invalid compiler input"))
  (define nodes '())
  (define types (make-hash))
  (define steps '())
  (define initial '())
  (define checks '())
  (define assertions '())
  (define layouts '())
  (define styles '())
  (define reveal-rules '())
  (define timing default-program-timing)
  (define outputs '())
  (define serial 0)
  (define (fresh tag)
    (set! serial (add1 serial))
    (string->symbol (format "$~a/~a" tag serial)))
  (define (origin id) (format "~a / ~a (~a)" name id source))
  (define (add! id type e given? public?)
    (unless (symbol? id) (geometry-error name "binding name is not an identifier: ~e" id))
    (when (and public? (regexp-match? #rx"^\\$" (symbol->string id)))
      (geometry-error name "names beginning with $ are reserved for helper internals: ~a" id))
    (when (hash-has-key? types id) (geometry-error name "duplicate geometry binding ~a" id))
    (hash-set! types id type)
    (set! nodes (append nodes (list (geometry-node id type e (origin id) given? public?)))))
  (define (known! id)
    (lookup-type types id name) id)
  (define (drawable! id)
    (unless (memq (lookup-type types id name) '(Point Line Segment Ray Circle Marker Label))
      (geometry-error name "presentation and visual layout need a drawable object or marker, not ~a" id))
    id)
  (define (helper-call? e)
    (and (pair? e) (symbol? (car e)) (hash-has-key? helpers (car e))))
  (define (check-free-placement! e [root? #f] [given? #f])
    (when (and (list? e) (pair? e) (not (eq? (car e) 'quote)))
      (when (and (equal? e '(point)) (not (and root? given?)))
        (geometry-error name "a free (point) must be a named given, not nested geometry"))
      (when (and (eq? (car e) 'choose) (not (and root? (not given?))))
        (geometry-error name "choose must be a named step binding, not a given or nested expression"))
      (for-each (lambda (x) (check-free-placement! x)) (cdr e))))
  (define (lower-expression e)
    (cond
      [(helper-call? e)
       (define h (hash-ref helpers (car e)))
       (unless (construction-helper? h) (geometry-error name "~a is not a construction helper" (car e)))
       (unless (= (length (construction-helper-result-types h)) 1)
         (geometry-error name "a nested helper expression must have one result"))
       (define id (fresh 'value))
       (instantiate! (list id) e #f)
       id]
      [(and (pair? e) (list? e) (not (eq? (car e) 'quote)))
       (cons (car e) (map lower-expression (cdr e)))]
      [else e]))
  (define (action-map action mapping)
    (geometry-action
     (geometry-action-kind action)
     (map (lambda (id) (hash-ref mapping id id)) (geometry-action-targets action))
     (case (geometry-action-kind action)
       [(together) (map (lambda (a) (action-map a mapping)) (geometry-action-payload action))]
       [(expanded) (map (lambda (s) (step-map s mapping)) (geometry-action-payload action))]
       [else (geometry-action-payload action)])))
  (define (step-map step mapping)
    (geometry-step (map-caption (geometry-step-narration step) mapping)
                   (map (lambda (a) (action-map a mapping)) (geometry-step-actions step))
                   (geometry-step-timing step)))
  ;; Inlines a checked helper graph into the caller. Result aliases provide
  ;; caller-visible identity without duplicating internal result visuals.
  (define (instantiate! ids expression public?)
    (define h (hash-ref helpers (car expression)))
    (unless (construction-helper? h) (geometry-error name "~a is not a construction helper" (car expression)))
    (define params (construction-helper-parameters h))
    (expect-count (cdr expression) (length params) name expression)
    (expect-count ids (length (construction-helper-result-types h)) name expression)
    (define prefix (fresh (car ids)))
    (define args
      (for/list ([e (in-list (cdr expression))] [param (in-list params)] [i (in-naturals)])
        (check-free-placement! e)
        (define x (lower-expression e))
        (define type (infer-expression-type x types name))
        (expect-type type (cdr param) name e)
        (if (symbol? x) x
            (let ([id (string->symbol (format "~a/argument-~a" prefix i))])
              (add! id type x #f #f) id))))
    (define body (construction-helper-program h))
    (define substitutions (make-hash))
    (for ([param (in-list params)] [arg (in-list args)])
      (hash-set! substitutions (car param) arg))
    (for ([n (in-list (geometry-program-nodes body))] #:unless (geometry-node-given? n))
      (hash-set! substitutions (geometry-node-id n)
                 (string->symbol (format "~a/~a" prefix (geometry-node-id n)))))
    (for ([n (in-list (geometry-program-nodes body))] #:unless (geometry-node-given? n))
      (add! (hash-ref substitutions (geometry-node-id n)) (geometry-node-type n)
            (substitute-expression (geometry-node-expression n) substitutions) #f #f))
    (for ([id (in-list ids)] [result (in-list (geometry-program-results body))]
          [type (in-list (construction-helper-result-types h))])
      (add! id type (hash-ref substitutions result) #f public?))
    (set! checks
          (append checks
                  (for/list ([c (in-list (geometry-program-checks body))])
                    (geometry-check (substitute-expression (geometry-check-expression c) substitutions)
                                    (format "~a / helper ~a: ~a" name (car expression) (geometry-check-origin c))))))
    (set! assertions
          (append assertions
                  (for/list ([c (in-list (geometry-program-assertions body))])
                    (geometry-check (substitute-expression (geometry-check-expression c) substitutions)
                                    (format "~a / helper ~a: ~a" name (car expression) (geometry-check-origin c))))))
    (define action-substitutions (hash-copy substitutions))
    (for ([id (in-list ids)] [result (in-list (geometry-program-results body))])
      (hash-set! action-substitutions result id))
    ;; Annotation hints follow visible result aliases just like styles and
    ;; reveals. Geometric constraints keep referencing the internal graph.
    ;; Caller hints are collected later and override the helper's defaults.
    (set! layouts
          (append layouts
                  (for/list ([l (in-list (geometry-program-layout body))])
                    (define annotation?
                      (memq (car l) '(label-side label-at label-offset label-position label-outside-of label-text
                                                marker-quadrant marker-position marker-radius)))
                    (define transformed
                      (substitute-expression l (if annotation? action-substitutions substitutions)))
                    (if (eq? (car transformed) 'prefer)
                        (append (take transformed 3) (list (* 1/4 (if (= (length transformed) 4) (cadddr transformed) 1))))
                        transformed))))
    ;; Helper styling follows result aliases, but never restyles caller inputs.
    (set! styles
          (append styles
                  (for/list ([s (in-list (geometry-program-styles body))]
                             #:unless (assoc (car s) params))
                    (cons (hash-ref action-substitutions (car s)) (cdr s)))))
    ;; Caller reveal rules, collected later, override helper-local defaults.
    (set! reveal-rules
          (append reveal-rules
                  (for/list ([r (in-list (geometry-program-reveals body))])
                    (list (hash-ref action-substitutions (car r)) (cadr r)))))
    (define mapped-initial
      (for/list ([a (in-list (geometry-program-initial body))]
                 #:when (ormap (lambda (id) (not (assoc id params))) (geometry-action-targets a)))
        (action-map (struct-copy geometry-action a
                                 [targets (filter (lambda (id) (not (assoc id params)))
                                                  (geometry-action-targets a))])
                    action-substitutions)))
    (define exposed-steps
      (append (if (null? mapped-initial) '() (list (geometry-step #f mapped-initial (hash 'read-delay 0 'pause 0 'generated? #t))))
              (map (lambda (s) (step-map s action-substitutions)) (geometry-program-steps body))))
    (define (reveals a)
      (case (geometry-action-kind a)
        [(reveal show) (geometry-action-targets a)]
        [(together) (append-map reveals (geometry-action-payload a))]
        [(expanded) (append-map (lambda (s) (append-map reveals (geometry-step-actions s)))
                                (geometry-action-payload a))]
        [else '()]))
    (define shown-outputs
      (append-map (lambda (s) (append-map reveals (geometry-step-actions s))) exposed-steps))
    (define missing (filter (lambda (id) (not (memq id shown-outputs))) ids))
    ;; Also handles a helper returning an input unchanged, with no internal steps.
    (append exposed-steps
            (if (null? missing) '()
                (list (geometry-step #f (list (geometry-action 'reveal missing #f)) (hash 'read-delay 0 'pause 0 'generated? #t))))))

  (define (parse-binding b [given? #f] [expanded? #f] [auxiliaries 'keep])
    (unless (and (list? b) (= (length b) 2)) (geometry-error name "expected [name expression], received ~e" b))
    (define lhs (car b))
    (define ids (if (symbol? lhs) (list lhs) lhs))
    (unless (and (list? ids) (pair? ids) (andmap symbol? ids)
                 (= (length ids) (length (remove-duplicates ids))))
      (geometry-error name "expected one identifier or distinct result identifiers: ~e" lhs))
    (define e (cadr b))
    (check-free-placement! e #t given?)
    (cond
      [(helper-call? e)
       (when given? (geometry-error name "a given cannot run a construction helper; use a step"))
       (define old-count (length nodes))
       (define child-steps (instantiate! ids e #t))
       (define private-drawables
         (for/list ([n (in-list (drop nodes old-count))]
                    #:when (and (not (memq (geometry-node-id n) ids))
                                (memq (geometry-node-type n) '(Point Line Segment Ray Circle Marker Label))))
           (geometry-node-id n)))
       (define completed-steps
         (if (or (eq? auxiliaries 'keep) (null? private-drawables)) child-steps
             (append child-steps
                     (list (geometry-step #f
                            (list (geometry-action
                                   (if (eq? auxiliaries 'hide) 'hide 'deemphasize)
                                   private-drawables #f))
                            (hash 'read-delay 0 'pause 0 'generated? #t))))))
       (if expanded? (geometry-action 'expanded ids completed-steps)
           (geometry-action 'reveal
                            (filter (lambda (id) (memq (lookup-type types id name)
                                                       '(Point Line Segment Ray Circle Marker Label))) ids) #f))]
      [else
       (when expanded? (geometry-error name "expand expects a construction-helper binding"))
       (define expression (lower-expression e))
       (define type (infer-expression-type expression types name))
       (when (and (equal? expression '(point)) (not given?))
         (geometry-error name "(point) is a free given; use choose for construction choices"))
       (when (and given? (pair? expression) (eq? (car expression) 'choose))
         (geometry-error name "choose belongs in a step, not given"))
       (cond
         [(eq? type 'PointList)
          (define tmp (fresh 'intersections))
          (add! tmp 'PointList `(expect-points ,(length ids) ,expression) #f #f)
          (for ([id (in-list ids)] [i (in-naturals)])
            (add! id 'Point `(select-point ,tmp ,i) given? #t))]
         [else
          (expect-count ids 1 name b)
          (unless (memq type geometry-types) (geometry-error name "cannot bind a ~a as geometry" type))
          (add! (car ids) type expression given? #t)])
       (geometry-action 'reveal
                        (if (memq type '(Point PointList Line Segment Ray Circle Marker Label)) ids '()) #f)]))
  (define (parse-action a [initial? #f])
    (unless (and (list? a) (pair? a)) (geometry-error name "invalid action ~e" a))
    (case (car a)
      [(show hide show-label hide-label deemphasize normalize highlight)
       (when (null? (cdr a)) (geometry-error name "~a needs a target" (car a)))
       (unless (andmap symbol? (cdr a)) (geometry-error name "actions target named objects: ~e" a))
       (unless initial? (for-each drawable! (cdr a)))
       (when (and initial? (eq? (car a) 'highlight))
         (geometry-error name "initially sets persistent state; highlight belongs in a step"))
       (geometry-action (car a) (remove-duplicates (cdr a)) #f)]
      [(together)
       (when initial? (geometry-error name "initially does not need together"))
       (define children (map parse-action (cdr a)))
       (when (null? children) (geometry-error name "empty together group"))
       (when (ormap (lambda (a) (memq (geometry-action-kind a) '(expanded together))) children)
         (geometry-error name "v0.1 together accepts leaf actions/bindings, not expand or nested together"))
       (define targets (append-map geometry-action-targets children))
       (unless (= (length targets) (length (remove-duplicates targets)))
         (geometry-error name "together actions must have disjoint targets"))
       (geometry-action 'together targets children)]
      [(expand)
       (when initial? (geometry-error name "expand belongs in a step"))
       (define auxiliaries
         (match a
           [(list 'expand binding) 'keep]
           [(list 'expand binding '#:auxiliaries (list 'quote mode))
            (unless (memq mode '(keep hide deemphasize))
              (geometry-error name "auxiliaries must be 'keep, 'hide or 'deemphasize"))
            mode]
           [_ (geometry-error name "expand expects a helper binding and optional #:auxiliaries mode")]))
       (parse-binding (cadr a) #f #t auxiliaries)]
      [(assert)
       (when initial? (geometry-error name "assert belongs at top level or in a step"))
       (when (null? (cdr a)) (geometry-error name "assert needs an expression"))
       (for ([e (in-list (cdr a))])
         (unless (memq (infer-expression-type e types name) '(Boolean Relation))
           (geometry-error name "assert expects a Boolean or relation: ~e" e))
         (set! assertions (append assertions (list (geometry-check e (format "~a step assertion" name))))))
       (geometry-action 'reveal '() #f)]
      [else
       (when initial? (geometry-error name "initially accepts presentation commands only"))
       (parse-binding a)]))
  (define (parse-step c)
    (define-values (timing-overrides body0) (parse-step-timing-overrides name (cdr c)))
    (define narration (if (and (pair? body0) (or (string? (car body0)) (caption-template? (car body0)))) (car body0) #f))
    (define body (if narration (cdr body0) body0))
    (define actions (map parse-action body))
    (when (caption-template? narration)
      (unless (pair? (cdr narration)) (geometry-error name "caption needs text or a named reference"))
      (for ([part (in-list (cdr narration))])
        (cond [(string? part) (void)]
              [(symbol? part) (drawable! part)]
              [else (geometry-error name "caption parts must be strings or drawable identifiers: ~e" part)])))
    (geometry-step narration actions timing-overrides))

  ;; Given declarations are collected before exposition. Layout/style/initial
  ;; clauses are checked after the graph exists, so they can refer forward.
  (define given-clauses (filter (lambda (c) (and (pair? c) (eq? (car c) 'given))) clauses))
  (unless (= (length given-clauses) 1) (geometry-error name "expected exactly one given clause"))
  (if parameters
      (for ([param (in-list parameters)]) (add! (car param) (cdr param) '(input) #t #t))
      (for ([b (in-list (cdar given-clauses))]) (parse-binding b #t)))
  (define deferred-checks '())
  (define deferred-assertions '())
  (define outer-layout '())
  (define outer-style '())
  (define outer-reveals '())
  (define seen-timing? #f)
  (define seen-result? #f)
  (for ([c (in-list clauses)])
    (unless (and (pair? c) (list? c) (symbol? (car c))) (geometry-error name "invalid construction clause ~e" c))
    (case (car c)
      [(given) (void)]
      [(results) (unless parameters (geometry-error name "results signatures belong in define-construction"))]
      [(result)
       (when seen-result? (geometry-error name "duplicate result clause"))
       (set! seen-result? #t)
       (set! outputs (cdr c))]
      [(require) (set! deferred-checks (append deferred-checks (cdr c)))]
      [(assert) (set! deferred-assertions (append deferred-assertions (cdr c)))]
      [(layout) (set! outer-layout (append outer-layout (cdr c)))]
      [(style) (set! outer-style (append outer-style (cdr c)))]
      [(reveal) (set! outer-reveals (append outer-reveals (cdr c))) ]
      [(timing) (when seen-timing? (geometry-error name "duplicate timing clause"))
                (set! seen-timing? #t)
                (set! timing (parse-timing-clause name c))]
      [(initially) (set! initial (append initial (map (lambda (a) (parse-action a #t)) (cdr c))))]
      [(step) (set! steps (append steps (list (parse-step c))))]
      [else (geometry-error name "unknown construction clause ~a" (car c))]))
  (when (and parameters (not seen-result?)) (geometry-error name "helper needs a result clause"))
  (unless (= (length outputs) (length (remove-duplicates outputs))) (geometry-error name "results must be distinct names"))
  (for-each known! outputs)
  (for ([a (in-list initial)]) (for-each drawable! (geometry-action-targets a)))
  (for ([e (in-list deferred-checks)])
    (unless (memq (infer-expression-type e types name) '(Boolean Relation))
      (geometry-error name "require expects a Boolean or relation: ~e" e))
    (set! checks (append checks (list (geometry-check e (format "~a precondition" name))))))
  (for ([e (in-list deferred-assertions)])
    (unless (memq (infer-expression-type e types name) '(Boolean Relation))
      (geometry-error name "assert expects a Boolean or relation: ~e" e))
    (set! assertions (append assertions (list (geometry-check e (format "~a assertion" name))))))
  (set! layouts (append layouts outer-layout))
  (for ([l (in-list layouts)])
    (match l
      [(list 'focus ids ...) (for-each drawable! ids)]
      [(list 'keep-visible ids ...) (for-each drawable! ids)]
      [(list 'fit-circle ids ...)
       (when (null? ids) (geometry-error name "fit-circle needs at least one circle"))
       (for ([id (in-list ids)]) (expect-type (lookup-type types id name) 'Circle name l))]
      [(list 'label-side id (list 'quote side))
       (drawable! id)
       (unless (memq side '(auto above below left right above-left above-right below-left below-right))
         (geometry-error name "unknown label side ~e" side))]
      [(list 'label-at id (list 'point (? finite-real? x) (? finite-real? y))) (drawable! id)]
      [(list 'label-offset id (list 'point (? finite-real? dx) (? finite-real? dy)))
       (unless (memq (lookup-type types id name) '(Point Label))
         (geometry-error name "label-offset expects a Point or semantic Label"))]
      [(list 'label-position id t)
       (expect-type (lookup-type types id name) 'Label name id)
       (unless (and (finite-real? t) (< 0 t 1))
         (geometry-error name "label position must be between 0 and 1"))]
      [(list 'label-outside-of id reference)
       (expect-type (lookup-type types id name) 'Label name id)
       (expect-type (lookup-type types reference name) 'Point name reference)]
      [(list 'label-text id (? string? text))
       (drawable! id)
       (when (or (string-contains? text "\n") (string-contains? text "\r") (zero? (string-length text)))
         (geometry-error name "label-text needs a nonempty, single-line string"))]
      [(list 'marker-quadrant id quadrant)
       (expect-type (lookup-type types id name) 'Marker name id)
       (unless (memq quadrant '(1 2 3 4)) (geometry-error name "marker quadrant must be 1, 2, 3 or 4"))]
      [(list 'marker-position id t)
       (expect-type (lookup-type types id name) 'Marker name id)
       (unless (and (finite-real? t) (< 0 t 1)) (geometry-error name "marker position must be between 0 and 1"))]
      [(list 'marker-radius id r)
       (unless (memq (lookup-type types id name) '(Marker Label))
         (geometry-error name "marker-radius expects a Marker or angle Label"))
       (unless (and (finite-real? r) (> r 0)) (geometry-error name "marker radius must be positive"))]
      [(list 'prefer e target extra ...)
       (unless (<= (length extra) 1) (geometry-error name "prefer accepts expression, target and optional weight"))
       (expect-type (infer-expression-type e types name) 'Number name e)
       (expect-type (infer-expression-type target types name) 'Number name target)
       (when (and (pair? extra) (not (and (finite-real? (car extra)) (positive? (car extra)))))
         (geometry-error name "preference weight must be positive"))]
      [(list 'constrain e) (expect-type (infer-expression-type e types name) 'Boolean name e)]
      [(list 'pin id (list 'point (? finite-real? x) (? finite-real? y)))
       (expect-type (lookup-type types id name) 'Point name id)
       (define n (findf (lambda (n) (eq? (geometry-node-id n) id)) nodes))
       (unless (or (equal? (geometry-node-expression n) '(point))
                   (and (pair? (geometry-node-expression n)) (eq? (car (geometry-node-expression n)) 'choose)))
         (geometry-error name "pin may realize a free point/choose, not alter derived geometry: ~a" id))]
      [_ (geometry-error name "unsupported layout hint ~e" l)]))
  (set! styles (append styles outer-style))
  (for ([s (in-list styles)])
    (unless (and (list? s) (pair? s) (symbol? (car s))) (geometry-error name "invalid object style ~e" s))
    (drawable! (car s)))
  (set! reveal-rules (append reveal-rules outer-reveals))
  (for ([r (in-list reveal-rules)])
    (match r
      [(list (? symbol? id) (? symbol? mode))
       (drawable! id)
       (unless (reveal-mode-valid? (lookup-type types id name) mode)
         (geometry-error name "unsupported reveal ~a for ~a (~a)" mode id (lookup-type types id name)))]
      [_ (geometry-error name "reveal expects [object mode], received ~e" r)]))
  (geometry-program name nodes steps initial checks assertions layouts styles timing reveal-rules outputs source))
