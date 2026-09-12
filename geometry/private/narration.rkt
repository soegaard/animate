#lang racket/base

;; Captions with named references survive hygienic helper expansion. Resolve them
;; once, in the caller, using the same display names as its diagram labels.
(require racket/list racket/string racket/match "data.rkt" "math.rkt")
(provide caption-template? map-caption finalize-program-narration)

(define (caption-template? value)
  (and (list? value) (pair? value) (eq? (car value) 'caption)))
(define (map-caption value mapping)
  (if (caption-template? value)
      (cons 'caption (map (lambda (part) (if (symbol? part) (hash-ref mapping part part) part))
                          (cdr value)))
      value))
(define (base-name id) (last (string-split (symbol->string id) "/")))
(define (subscript n)
  (list->string
   (for/list ([ch (in-string (number->string n))])
     (string-ref "₀₁₂₃₄₅₆₇₈₉" (- (char->integer ch) (char->integer #\0))))))

(define (finalize-program-narration program)
  (define nodes (geometry-program-nodes program))
  (define table (for/hash ([n (in-list nodes)]) (values (geometry-node-id n) n)))
  (define explicit-texts
    (for/fold ([h (hash)]) ([rule (in-list (geometry-program-layout program))]
                           #:when (eq? (car rule) 'label-text))
      (hash-set h (cadr rule) (caddr rule))))
  (define (text id) (hash-ref explicit-texts id (lambda () (base-name id))))
  (define active (make-hasheq))
  (define (visit-step s)
    (when (caption-template? (geometry-step-narration s))
      (for ([p (in-list (cdr (geometry-step-narration s)))] #:when (symbol? p))
        (hash-set! active p #t)))
    (for-each visit-action (geometry-step-actions s)))
  (define (visit-action a)
    (case (geometry-action-kind a)
      [(expanded) (for-each visit-step (geometry-action-payload a))]
      [(together) (for-each visit-action (geometry-action-payload a))]
      [(show reveal show-label)
       (for ([id (in-list (geometry-action-targets a))]) (hash-set! active id #t))]
      [else (void)]))
  (for-each visit-step (geometry-program-steps program))
  (for ([n (in-list nodes)] #:when (geometry-node-given? n))
    (hash-set! active (geometry-node-id n) #t))
  ;; Follow only proven aliases/projections. Do not merge numerically close
  ;; intersections or public points that happen to share coordinates.
  (define (expression id)
    (define e (geometry-node-expression (hash-ref table id)))
    (if (and (symbol? e) (hash-has-key? table e)) (expression e) e))
  (define canonical-cache (make-hasheq))
  (define (canonical id)
    (hash-ref! canonical-cache id
      (lambda ()
        (define e (geometry-node-expression (hash-ref table id)))
        (cond
          [(and (symbol? e) (hash-has-key? table e)) (canonical e)]
          [else
           (define projected
             (match e
               [(list (and op (or 'start-point 'end-point 'angle-first 'angle-vertex 'angle-last 'center))
                      (? symbol? owner))
                (define source (expression owner))
                (match source
                  [(list (or 'line 'segment 'ray) a b)
                   (case op [(start-point) a] [(end-point) b] [else #f])]
                  [(list 'angle a b c)
                   (case op [(angle-first) a] [(angle-vertex) b] [(angle-last) c] [else #f])]
                  [(list 'circle center rest ...) (and (eq? op 'center) center)]
                  [_ #f])]
               [_ #f]))
           (if (and (symbol? projected) (hash-has-key? table projected))
               (canonical projected) id)]))))
  (define preferred (make-hasheq))
  (define reserved (make-hash))
  (define names (make-hasheq))
  (for ([n (in-list nodes)] #:when (geometry-node-public? n))
    (define id (geometry-node-id n))
    (hash-set! reserved (text id) #t)
    (hash-set! names id (text id))
    (unless (hash-has-key? preferred (canonical id))
      (hash-set! preferred (canonical id) (text id))))
  (for ([n (in-list nodes)] #:unless (geometry-node-public? n))
    (define id (geometry-node-id n))
    (define public-name (hash-ref preferred (canonical id) #f))
    (define name
      (cond [public-name public-name]
            [(not (hash-has-key? active id)) (text id)]
            [else
             (let loop ([i 0])
               (define candidate (if (zero? i) (text id) (string-append (text id) (subscript i))))
               (if (hash-has-key? reserved candidate) (loop (add1 i)) candidate))]))
    (hash-set! names id name)
    (when (hash-has-key? active id) (hash-set! reserved name #t)))
  (define auto-labels
    (for/list ([n (in-list nodes)]
               #:when (and (not (geometry-node-public? n))
                           (memq (geometry-node-type n) '(Point Line Segment Ray Circle Marker))
                           (not (hash-has-key? explicit-texts (geometry-node-id n)))
                           (not (equal? (hash-ref names (geometry-node-id n)) (base-name (geometry-node-id n))))))
      (list 'label-text (geometry-node-id n) (hash-ref names (geometry-node-id n)))))
  (define (resolve-step s)
    (define value (geometry-step-narration s))
    (struct-copy geometry-step s
      [narration (if (caption-template? value)
                     (string->immutable-string
                      (apply string-append
                             (map (lambda (part) (if (symbol? part) (hash-ref names part) part)) (cdr value))))
                     value)]
      [actions (map resolve-action (geometry-step-actions s))]))
  (define (resolve-action a)
    (case (geometry-action-kind a)
      [(expanded) (struct-copy geometry-action a [payload (map resolve-step (geometry-action-payload a))])]
      [(together) (struct-copy geometry-action a [payload (map resolve-action (geometry-action-payload a))])]
      [else a]))
  (struct-copy geometry-program program
    [steps (map resolve-step (geometry-program-steps program))]
    [layout (append auto-labels (geometry-program-layout program))]))
