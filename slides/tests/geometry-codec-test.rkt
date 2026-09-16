#lang racket/base

;; Real geometry data and real native samplers; no substitute renderer.
(require rackunit racket/list racket/file racket/port
         (prefix-in g: "../../geometry/core.rkt")
         (prefix-in ga: "../../geometry/animate.rkt")
         (prefix-in a: "../../main.rkt")
         (prefix-in c: "../../colors.rkt")
         (prefix-in gp: "../../geometry/private/render-preparation.rkt")
         "../../geometry/private/render-preparation-codec.rkt"
         (only-in "../../geometry/examples/equilateral-triangle.rkt" equilateral-triangle)
         "../main.rkt" "../pict.rkt" "../scene.rkt" "../render.rkt" "../gallery.rkt"
         "../geometry.rkt" "../private/data.rkt" "../private/codec.rkt" "../private/sample.rkt"
         "helpers.rkt")
(provide tests)
(define (wire-copy p)
  (datum->prepared-geometry-render
   (call-with-input-string (format "~s" (prepared-geometry-render->datum p)) read)))
(define (timeline) (g:construction->timeline equilateral-triangle #:aspect 16/9))
(define (prepare) (ga:prepare-geometry-render! (timeline) #:width 320 #:captions? #f))
(define (with-temp thunk)
  (define temp (make-temporary-file "slides-geometry-codec-~a" 'directory))
  (dynamic-wind void (lambda () (thunk temp)) (lambda () (delete-directory/files temp))))
(define (geometry-artifacts artifacts)
  (filter (lambda (a) (eq? (hash-ref a 'role #f) 'slide-prepared-geometry)) artifacts))
(define (board-for program)
  (storyboard (storyboard-shot 'construction
    (hold-slide (slide #:layout 'figure-full [figure (geometry-content program)]) #:duration 1))))

;; Ready realization with every drawable family. Source provenance isn't needed
;; to serialize them; points remain exact and marker/label targets retain type.
(define (primitive-timeline)
  (define A (g:point -3/2 -1)) (define B (g:point 3/2 -1)) (define C (g:point 0 2))
  (define O (g:point 0 0))
  (define AB (g:segment A B))
  (define angle (g:angle-spec B A C))
  (define entries
    (list (cons 'A A) (cons 'B B) (cons 'C C)
          (cons 'segment AB) (cons 'line (g:line A B)) (cons 'ray (g:ray A C))
          (cons 'circle (g:circle A B))
          (cons 'right-angle (g:perpendicular-marker (g:line O (g:point 2 0))
                                                    (g:line O (g:point 0 2)) O))
          (cons 'parallel (g:parallel-marker (g:line A B) (g:line (g:point -1 1) (g:point 1 1))))
          (cons 'lengths (g:equal-length-marker (list AB (g:segment B A))))
          (cons 'angle (g:angle-marker angle))
          (cons 'angles (g:equal-angle-marker (list angle angle)))
          (cons 'midpoint (g:midpoint-marker (g:point 0 -1) AB))
          (cons 'point-name (g:point-label A "A*"))
          (cons 'segment-name (g:segment-label AB "base"))
          (cons 'length-name (g:length-label AB "s"))
          (cons 'angle-name (g:angle-label angle "θ"))))
  (define nodes (for/list ([entry (in-list entries)])
                  (g:geometry-node (car entry) (g:geometry-kind (cdr entry)) #f #f #t #t)))
  (define program (g:geometry-program 'primitive-fixture nodes '() '() '() '() '() '() #f '() '() #f))
  (define realization
    (g:geometry-realization program (make-immutable-hash entries) (g:geometry-view O 16 16/9 1/20) (hash) '()))
  (define initial (for/hash ([entry (in-list entries)]) (values (car entry) (g:presentation #t #f #f))))
  (g:geometry-timeline realization g:default-geometry-theme '() '() initial initial 67/10 '()))

(define tests
  (test-suite
   "portable geometry preparation"
   (test-case "all primitive, marker, label and exact-number fields round trip"
     (define p (ga:prepare-geometry-render! (primitive-timeline) #:width 320 #:captions? #f))
     (define restored (wire-copy p))
     (check-equal? restored p)
     (check-equal? (ga:prepared-geometry-render-duration restored) 67/10)
     (check-true (exact? (ga:prepared-geometry-render-duration restored)))
     (check-equal? (g:point-x (hash-ref (gp:prepared-geometry-render-environment restored) 'A)) -3/2))
   (test-case "reconstruction and reverse sampling never call preparation"
     (define t (timeline))
     (define p (ga:prepare-geometry-render! t #:width 320 #:captions? #t))
     (define camera (ga:geometry-timeline->camera t #:width 320 #:height 180))
     (define original (ga:prepared-geometry->visual-sampler p #:id 'construction))
     (parameterize ([ga:current-geometry-render-preparation-observer
                     (lambda args (error 'geometry-codec-test "worker repeated annotation preparation"))])
       (define restored (ga:prepared-geometry->visual-sampler (wire-copy p) #:id 'construction))
       (for ([time (in-list (list (g:geometry-timeline-duration t) 5 2 0 5))])
         (check-true
          (bytes=? (pixel-bytes (a:visual->pict (original time) camera))
                   (pixel-bytes (a:visual->pict (restored time) camera)))))))
   (test-case "native theme tokens and alpha remain semantic color data"
     (define p (prepare))
     (define color (c:color-mix (c:rgba-color 12 30 70 1/2) c:theme-accent 1/3))
     (define changed
       (struct-copy gp:prepared-geometry-render p
         [guide-style (hash-set (gp:prepared-geometry-render-guide-style p) 'stroke-color color)]))
     (check-equal? (hash-ref (gp:prepared-geometry-render-guide-style (wire-copy changed)) 'stroke-color) color))
   (test-case "source syntax locations do not affect the semantic fingerprint"
     (check-equal? (geometry-source-fingerprint equilateral-triangle)
                   (geometry-source-fingerprint
                    (struct-copy g:geometry-program equilateral-triangle [source 'different-location])))
     (check-not-equal? (geometry-source-fingerprint equilateral-triangle)
                       (geometry-source-fingerprint
                        (struct-copy g:geometry-program equilateral-triangle [name 'other-construction]))))
   (test-case "invalid schema records identities and executable values are rejected"
     (define p (prepare))
     (define datum (prepared-geometry-render->datum p))
     (check-exn exn:fail? (lambda () (datum->prepared-geometry-render (hash-set datum 'schema 'unknown))))
     (check-exn exn:fail? (lambda () (datum->prepared-geometry-render (hash-set datum 'data '(record arbitrary ())))))
     (check-exn exn:fail?
       (lambda () (wire-copy (struct-copy gp:prepared-geometry-render p [order '(A A)]))))
     (check-exn exn:fail?
       (lambda () (prepared-geometry-render->datum
                   (struct-copy gp:prepared-geometry-render p
                     [guide-style (hash 'procedure void)])))))
   (test-case "one geometry artifact serves two semantic checkpoints"
     (define source (make-slide-gallery #:entries '(semantic-geometry)))
     (define count 0)
     (define p
       (parameterize ([ga:current-geometry-render-preparation-observer
                       (lambda args (set! count (add1 count)))])
         (prepare-storyboard! source)))
     (check-equal? count 1)
     (with-temp
      (lambda (temp)
        (define-values (payload artifacts deps) (prepared-storyboard->payload! p temp))
        (check-equal? (length (geometry-artifacts artifacts)) 1)
        (parameterize ([ga:current-geometry-render-preparation-observer
                        (lambda args (error 'geometry-codec-test "decoder prepared geometry"))])
          (define restored (payload->prepared-storyboard payload source))
          (check-equal? (storyboard-match-report restored) (storyboard-match-report p))
          (for ([fraction (in-list '(1 3/4 1/2 1/4 0 1/2))])
            (define time (* fraction (prepared-duration p)))
            (check-equal? (sample-signature (sample-storyboard restored time))
                          (sample-signature (sample-storyboard p time))))))))
   (test-case "changed and missing geometry artifacts fail before sampling"
     (define source (board-for equilateral-triangle))
     (with-temp
      (lambda (temp)
        (define-values (payload artifacts deps) (prepared-storyboard->payload! (prepare-storyboard! source) temp))
        (define path (hash-ref (car (geometry-artifacts artifacts)) 'path))
        (display-to-file "corrupt geometry" path #:exists 'truncate/replace)
        (check-exn (code? 'artifact-integrity) (lambda () (payload->prepared-storyboard payload source)))
        (delete-file path)
        (check-exn (code? 'artifact-integrity) (lambda () (payload->prepared-storyboard payload source))))))
   (test-case "changed geometry source is rejected even with unchanged slot names"
     (define source (board-for equilateral-triangle))
     (with-temp
      (lambda (temp)
        (define-values (payload artifacts deps) (prepared-storyboard->payload! (prepare-storyboard! source) temp))
        (define changed (board-for (struct-copy g:geometry-program equilateral-triangle [name 'changed])))
        (check-exn (code? 'source-mismatch) (lambda () (payload->prepared-storyboard payload changed))))))
   (test-case "a ready timeline retains supplied realization and timing"
     (define t (timeline))
     (define source (storyboard (storyboard-shot 'ready
       (hold-slide (slide #:layout 'figure-full [figure (geometry-content t)]) #:duration 1))))
     (with-temp
      (lambda (temp)
        (define p (prepare-storyboard! source))
        (define-values (payload artifacts deps) (prepared-storyboard->payload! p temp))
        (define restored (payload->prepared-storyboard payload source))
        (check-equal? (sample-signature (sample-storyboard p 1))
                      (sample-signature (sample-storyboard restored 1))))))))
(module+ test
  (require rackunit/text-ui)
  (unless (zero? (run-tests tests)) (error 'geometry-codec-test "failed")))
