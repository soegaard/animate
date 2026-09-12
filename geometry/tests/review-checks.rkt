#lang racket/base

;; Base-only semantic and filesystem/ZIP checks. The bundle tests deliberately
;; use a tiny PNG fixture, NOT native geometry rendering; review-render-test.rkt
;; covers that separate integration boundary in a complete Animate checkout.
(require racket/list racket/file racket/path racket/port racket/runtime-path
         racket/string json file/unzip
         "../core.rkt" "../review-plan.rkt" "../private/reveal.rkt" "../private/review-bundle.rkt"
         "../private/compiler.rkt" "../examples/private/review-example-names.rkt")
(provide review-check-groups run-review-checks)
(define-runtime-path examples "../examples")
(define counter (make-parameter #f))
(define current-group (make-parameter "review"))
(define (ensure ok message . args)
  (when (counter) (set-box! (counter) (add1 (unbox (counter)))))
  (unless ok (error 'review-check "~a: ~a ~e" (current-group) message args)))
(define (near a b) (ensure (< (abs (- a b)) 1e-8) "times differ" a b))
(define (expect-error thunk [pattern #rx"."])
  (define failure (with-handlers ([exn:fail? values]) (thunk) #f))
  (ensure (and failure (regexp-match? pattern (exn-message failure)))
          "expected diagnostic" pattern (and failure (exn-message failure))))
(define (compile clauses)
  (make-construction-program 'review-test clauses (hash) "review-checks"))
(define givens '((given [A (point 0 0)] [B (point 2 0)] [C (point 0 2)])))
(define timing '(timing [opening-pause 1/5] [read-delay 2/5] [action-duration 1] [step-pause 3/5]))
(define (timeline . steps) (construction->timeline (compile (append givens (list timing) steps))))
(define (triplet t) (geometry-review-step-samples (car (make-geometry-review-plan t))))
(define (app s id) (hash-ref (geometry-frame-appearances (geometry-review-sample-frame s)) id))
(define (text s) (geometry-frame-narration (geometry-review-sample-frame s)))
(define (state->simple frame)
  (sort (hash->list (geometry-frame-appearances frame)) symbol<? #:key car))

(define-construction inner
  (given [A : Point] [B : Point] [C : Point])
  (results Segment)
  (initially (hide-label AB))
  (step "First join." [AB (segment A B)])
  (step "Second join." [BC (segment B C)])
  (result BC))
(define-construction outer
  (given [A : Point] [B : Point] [C : Point])
  (results Segment)
  (step "Both joins." (expand [BC (inner A B C)] #:auxiliaries 'hide))
  (result BC))
(construction nested
  (given [A (point 0 0)] [B (point 2 0)] [C (point 0 2)])
  (step "The whole construction." (expand [answer (outer A B C)] #:auxiliaries 'hide))
  (step "The answer." (highlight answer)))

(define (with-temporary proc)
  (define root (make-temporary-file "geometry-review-test-~a" 'directory))
  (dynamic-wind void (lambda () (proc root)) (lambda () (delete-directory/files root))))
;; Replaced below with a complete, valid 2x2 PNG. No native graphics dependency.
(define tiny-png (bytes 137 80 78 71 13 10 26 10 0 0 0 13 73 72 68 82 0 0 0 2 0 0 0 2 8 6 0 0 0 114 182 13 36 0 0 0 20 73 68 65 84 120 156 99 12 168 216 242 159 129 129 129 129 137 1 10 0 37 132 2 127 113 230 58 95 0 0 0 0 73 69 78 68 174 66 96 130))
(define (fixture-render! sample path)
  (call-with-output-file path (lambda (out) (write-bytes tiny-png out)) #:exists 'error))
(define (bundle t plan dir #:zip [archive #f] #:renderer [renderer fixture-render!] #:sheets [sheets #f])
  (write-geometry-review-bundle! t plan dir #:name "test-example" #:theme "dark"
                                #:width 2 #:height 2 #:zip archive #:render-sample! renderer
                                #:contact-sheets! sheets))
(define (png-files dir)
  (filter (lambda (p) (regexp-match? #rx"^step-.*\\.png$" (path->string p))) (directory-list dir)))
(define (file-snapshot dir)
  (for/hash ([p (in-list (directory-list dir))]) (values (path->string p) (file->bytes (build-path dir p)))))

(define basic-groups
  (list
   (cons "compiled step boundaries follow opening/read/action/hold timing"
     (lambda ()
       (define t (timeline '(step "Join AB." [AB (segment A B)])))
       (define span (car (geometry-timeline-steps t)))
       (near (geometry-step-span-start span) 1/5)
       (near (geometry-step-span-action-start span) 3/5)
       (near (geometry-step-span-action-end span) 8/5)
       (near (geometry-step-span-end span) 11/5)
       (near (geometry-timeline-duration t) 11/5)))
   (cons "three named samples show unchanged, partial, completed geometry"
     (lambda ()
       (define t (timeline '(step "Join AB." [AB (segment A B)])))
       (define s (triplet t))
       (ensure (equal? (map geometry-review-sample-phase s) '(read during settled)) "phase order")
       (ensure (equal? (map geometry-review-sample-filename s)
                       '("step-001-read.png" "step-001-during.png" "step-001-settled.png")) "filenames")
       (near (geometry-appearance-opacity (app (car s) 'AB)) 0)
       (near (geometry-appearance-reveal (app (cadr s) 'AB)) 0.5)
       (near (geometry-appearance-reveal (app (caddr s) 'AB)) 1)
       (for ([x (in-list s)]) (ensure (equal? (text x) "Join AB.") "caption"))))
   (cons "two sequential actions never sample their shared boundary"
     (lambda ()
       (define s (triplet (timeline '(step "Join both." [AB (segment A B)] [AC (segment A C)]))))
       (near (geometry-appearance-reveal (app (cadr s) 'AB)) 1)
       (near (geometry-appearance-reveal (app (cadr s) 'AC)) 0.5)))
   (cons "together actions share one mid-reveal sample"
     (lambda ()
       (define s (triplet (timeline '(step "Join both." (together [AB (segment A B)] [AC (segment A C)])))))
       (near (geometry-appearance-reveal (app (cadr s) 'AB)) 0.5)
       (near (geometry-appearance-reveal (app (cadr s) 'AC)) 0.5)))
   (cons "per-step overrides affect review times exactly"
     (lambda ()
       (define t (timeline '(step #:read-delay 1/10 #:duration 1/2 #:pause 1/5 "Join." [AB (segment A B)])))
       (define s (triplet t))
       (near (geometry-review-sample-time (car s)) 1/4)
       (near (geometry-review-sample-time (cadr s)) 11/20)
       (near (geometry-review-sample-time (caddr s)) 9/10)))
   (cons "zero ending pause does not leak the next caption or next object"
     (lambda ()
       (define t (timeline '(step #:pause 0 "First." [AB (segment A B)])
                           '(step #:read-delay 0 "Second." [AC (segment A C)])))
       (define settled (caddr (triplet t)))
       (ensure (equal? (text settled) "First.") "boundary caption")
       (near (geometry-appearance-opacity (app settled 'AC)) 0)
       (near (geometry-appearance-opacity (app settled 'AB)) 1)))
   (cons "zero reading delay has an explicit pre-action snapshot"
     (lambda ()
       (define s (triplet (timeline '(step #:read-delay 0 "First." [AB (segment A B)]))))
       (near (geometry-review-sample-time (car s)) 1/5)
       (near (geometry-appearance-opacity (app (car s) 'AB)) 0)))
   (cons "silent steps are included without an invented reading delay"
     (lambda ()
       (define t (timeline '(step [AB (segment A B)])))
       (define row (car (make-geometry-review-plan t)))
       (ensure (not (geometry-review-step-caption row)) "silent caption")
       (near (geometry-step-span-start (geometry-review-step-span row))
             (geometry-step-span-action-start (geometry-review-step-span row)))
       (ensure (= (length (geometry-review-step-samples row)) 3) "silent samples")))
   (cons "silent cleanup and no-op rows are omitted by default but can be requested"
     (lambda ()
       (define t (timeline '(step "Join." [AB (segment A B)])
                           '(step #:pause 0 (hide AB))
                           '(step #:read-delay 0 #:pause 0 (show A))))
       (define default-plan (make-geometry-review-plan t))
       (define complete-plan (make-geometry-review-plan t #:include-cleanup? #t))
       (ensure (= (length default-plan) 1) "cleanup/no-op rows were not omitted")
       (ensure (= (length complete-plan) 3) "include-cleanup did not restore all authored rows")
       (ensure (equal? (geometry-review-step-caption (car default-plan)) "Join.") "wrong surviving row")))
   (cons "narration-only and no-op steps preserve repeated images"
     (lambda ()
       (define t (timeline '(step "Observe A." (show A))))
       (define s (triplet t))
       (ensure (null? (geometry-step-span-events (car (geometry-timeline-steps t)))) "no-op event")
       (ensure (andmap (lambda (x) (equal? (state->simple (geometry-review-sample-frame x))
                                          (state->simple (geometry-review-sample-frame (car s))))) s)
               "unchanged samples")))
   (cons "instantaneous authored steps keep their own caption with a note"
     (lambda ()
       (define t (timeline '(step #:read-delay 0 #:pause 0 "Instantaneous.")
                           '(step "Next." [AB (segment A B)])))
       (define row (car (make-geometry-review-plan t)))
       (ensure (pair? (geometry-review-step-notes row)) "instantaneous note")
       (for ([s (in-list (geometry-review-step-samples row))])
         (ensure (equal? (text s) "Instantaneous.") "instantaneous caption")
         (near (geometry-appearance-opacity (app s 'AB)) 0))))
   (cons "a step-free construction produces an initial-diagram triplet"
     (lambda ()
       (define plan (make-geometry-review-plan (timeline)))
       (ensure (= (length plan) 1) "initial row")
       (ensure (zero? (geometry-step-span-id (geometry-review-step-span (car plan)))) "initial id")
       (ensure (= (length (geometry-review-samples plan)) 3) "initial images")))
   (cons "identical captions do not merge different authored steps"
     (lambda ()
       (define plan (make-geometry-review-plan (timeline '(step "Join." [AB (segment A B)])
                                                       '(step "Join." [AC (segment A C)]))))
       (ensure (= (length plan) 2) "repeated captions")
       (ensure (= (length (remove-duplicates (map geometry-review-sample-filename (geometry-review-samples plan)))) 6)
               "unique repeated-caption names")))
   (cons "highlight and visibility effects have a meaningful during image"
     (lambda ()
       (define plan (make-geometry-review-plan
                    (timeline '(step "A." (highlight A)) '(step "B." (hide B)))))
       (define a (geometry-review-step-samples (car plan)))
       (define b (geometry-review-step-samples (cadr plan)))
       (ensure (> (geometry-appearance-highlight (app (cadr a) 'A)) 0.9) "highlight during")
       (near (geometry-appearance-highlight (app (caddr a) 'A)) 0)
       (near (geometry-appearance-opacity (app (cadr b) 'B)) 0.5)
       (near (geometry-appearance-opacity (app (caddr b) 'B)) 0)))
   (cons "very short actions are sampled without movie-FPS rounding"
     (lambda ()
       (define s (triplet (timeline '(step #:read-delay 0 #:duration 1/1000000 #:pause 0 "Tiny." [AB (segment A B)]))))
       (near (geometry-appearance-reveal (app (cadr s) 'AB)) 0.5)))
   (cons "nested expansions include authored rows but omit generated cleanup rows"
     (lambda ()
       (define t (construction->timeline nested))
       (define spans (geometry-timeline-steps t))
       (define plan (make-geometry-review-plan t))
       (ensure (ormap geometry-step-span-generated? spans) "generated steps tagged")
       (ensure (andmap (lambda (r) (not (geometry-step-span-generated? (geometry-review-step-span r)))) plan)
               "generated rows filtered")
       (ensure (= (length plan) 5) "outer, inner overview, two joins, answer" (length plan))
       (ensure (ormap (lambda (r) (> (length (geometry-step-span-path (geometry-review-step-span r))) 3)) plan)
               "nested path")
       (define settled (last (geometry-review-step-samples (car plan))))
       (near (geometry-appearance-opacity (app settled 'answer)) 1)
       (for ([(id p) (in-hash (geometry-frame-appearances (geometry-review-sample-frame settled)))]
             #:when (string-prefix? (symbol->string id) "$"))
         (near (geometry-appearance-opacity p) 0))))
   (cons "top-level-only keeps parent overviews and hides substep rows"
     (lambda ()
       (define plan (make-geometry-review-plan (construction->timeline nested) #:expanded? #f))
       (ensure (= (length plan) 2) "outer step count")
       (ensure (andmap (lambda (r) (= (length (geometry-step-span-path (geometry-review-step-span r))) 1)) plan)
               "outer paths")))
   (cons "planning is deterministic, read-only, and independent of seeking"
     (lambda ()
       (define t (construction->timeline nested))
       (define plan (make-geometry-review-plan t))
       (define before (format "~s" t))
       (for ([s (in-list (reverse (geometry-review-samples plan)))])
         (sample-geometry-timeline t (geometry-review-sample-time s)))
       (ensure (equal? plan (make-geometry-review-plan t)) "determinism")
       (ensure (equal? before (format "~s" t)) "timeline mutation")))
   (cons "selection registry includes all 19 movies and excludes helper modules"
     (lambda ()
       (ensure (= (length (select-review-examples 'all)) 19) "all count")
       (ensure (= (length (select-review-examples 'library)) 13) "library count")
       (ensure (equal? (select-review-examples "incircle") '("incircle")) "single selection")
       (ensure (member "gallery" (select-review-examples 'all)) "gallery")
       (for ([name (in-list '("helpers" "../incircle" "incircle.rkt" "not-an-example"))])
         (expect-error (lambda () (select-review-examples name))))))
   (cons "bundle writes all images, captions, offline index, and relative ZIP entries"
     (lambda () (with-temporary
       (lambda (root)
         (define t (timeline '(step "Text <x> & \"quotes\"." [AB (segment A B)])))
         (define plan (make-geometry-review-plan t))
         (define dir (build-path root "directory with spaces"))
         (define zip-path (build-path root "archive with spaces.zip"))
         (define result (bundle t plan dir #:zip zip-path))
         (ensure (= (geometry-review-result-image-count result) 3) "image count")
         (ensure (= (length (png-files dir)) 3) "PNG files")
         (define m (call-with-input-file (build-path dir "manifest.json") read-json))
         (ensure (equal? (hash-ref m 'format) review-manifest-format) "manifest format")
         (ensure (= (hash-ref m 'image_count) 3) "manifest image count")
         (ensure (string-contains? (file->string (build-path dir "steps.txt")) "Text <x>") "caption text")
         (ensure (string-contains? (file->string (build-path dir "index.html")) "Text &lt;x&gt; &amp; &quot;quotes&quot;")
                 "HTML escaping")
         (define entries (zip-directory-entries (read-zip-directory zip-path)))
         (ensure (member #"test-example/step-001-during.png" entries) "relative root in ZIP" entries)
         (ensure (andmap (lambda (x) (bytes-prefix? x #"test-example/")) entries) "archive path hygiene")
         (ensure (= (length (filter (lambda (x) (regexp-match? #rx#"step-.*\\.png$" x)) entries)) 3)
                 "no archive image loss")))))
   (cons "replacing a managed review removes stale frames and is deterministic"
     (lambda () (with-temporary
       (lambda (root)
         (define many (timeline '(step "One." [AB (segment A B)]) '(step "Two." [AC (segment A C)])))
         (define one (timeline '(step "One." [AB (segment A B)])))
         (define dir (build-path root "review")) (define archive (build-path root "review.zip"))
         (bundle many (make-geometry-review-plan many) dir #:zip archive)
         (ensure (= (length (png-files dir)) 6) "initial six images")
         (bundle one (make-geometry-review-plan one) dir #:zip archive)
         (ensure (= (length (png-files dir)) 3) "stale images removed")
         (define saved (file->bytes archive))
         (bundle one (make-geometry-review-plan one) dir #:zip archive)
         (ensure (bytes=? saved (file->bytes archive)) "deterministic ZIP content")))))
   (cons "a failed render leaves the last successful review and ZIP untouched"
     (lambda () (with-temporary
       (lambda (root)
         (define t (timeline '(step "One." [AB (segment A B)])))
         (define plan (make-geometry-review-plan t))
         (define dir (build-path root "review")) (define archive (build-path root "review.zip"))
         (bundle t plan dir #:zip archive)
         (define saved (file-snapshot dir)) (define saved-zip (file->bytes archive))
         (define calls 0)
         (expect-error
          (lambda () (bundle t plan dir #:zip archive
            #:renderer (lambda (s p) (set! calls (add1 calls))
                         (when (= calls 2) (error 'fixture "deliberate failure")) (fixture-render! s p))))
          #rx"deliberate failure")
         (ensure (equal? saved (file-snapshot dir)) "previous review changed")
         (ensure (bytes=? saved-zip (file->bytes archive)) "previous ZIP changed")
         (ensure (= (length (directory-list root)) 2) "temporary render directories leaked")))))
   (cons "bad or missing PNG output prevents publication"
     (lambda () (with-temporary
       (lambda (root)
         (define t (timeline '(step "One." [AB (segment A B)])))
         (define dir (build-path root "review"))
         (expect-error (lambda () (bundle t (make-geometry-review-plan t) dir #:renderer (lambda (_s _p) (void))))
                       #rx"did not create")
         (ensure (not (directory-exists? dir)) "incomplete review published")
         (expect-error (lambda () (bundle t (make-geometry-review-plan t) dir
                                         #:renderer (lambda (_s p) (display-to-file "not an image" p)))) #rx"invalid PNG")
         (ensure (null? (directory-list root)) "staging garbage")))))
   (cons "unrelated files and hand-added review notes are never deleted"
     (lambda () (with-temporary
       (lambda (root)
         (define t (timeline '(step "One." [AB (segment A B)])))
         (define plan (make-geometry-review-plan t)) (define dir (build-path root "review"))
         (make-directory dir) (display-to-file "keep" (build-path dir "my-video.txt"))
         (expect-error (lambda () (bundle t plan dir)) #rx"refusing to replace")
         (ensure (equal? (file->string (build-path dir "my-video.txt")) "keep") "unrelated content lost")
         (delete-file (build-path dir "my-video.txt"))
         (bundle t plan dir)
         (display-to-file "notes" (build-path dir "notes.txt"))
         (expect-error (lambda () (bundle t plan dir)) #rx"refusing to replace")
         (ensure (equal? (file->string (build-path dir "notes.txt")) "notes") "review notes lost")))))
   (cons "archive cannot be nested inside its own review directory"
     (lambda () (with-temporary
       (lambda (root)
         (define t (timeline '(step "One." [AB (segment A B)])))
         (define dir (build-path root "review"))
         (expect-error (lambda () (bundle t (make-geometry-review-plan t) dir #:zip (build-path dir "nested.zip")))
                       #rx"outside the review directory")
         (ensure (not (directory-exists? dir)) "invalid archive path wrote output")))))
   (cons "duplicate or unsafe image names fail before rendering"
     (lambda () (with-temporary
       (lambda (root)
         (define t (timeline '(step "One." [AB (segment A B)])))
         (define plan (make-geometry-review-plan t)) (define row (car plan))
         (define s (car (geometry-review-step-samples row)))
         (define duplicate (list (struct-copy geometry-review-step row [samples (list s s s)])))
         (expect-error (lambda () (bundle t duplicate (build-path root "review"))) #rx"unique safe filenames")
         (define bad (struct-copy geometry-review-sample s [filename "../escape.png"]))
         (define unsafe (list (struct-copy geometry-review-step row
                               [samples (cons bad (cdr (geometry-review-step-samples row)))])))
         (expect-error (lambda () (bundle t unsafe (build-path root "review"))) #rx"unique safe filenames")))))
   (cons "contact sheets are included in the archive but not counted as step frames"
     (lambda () (with-temporary
       (lambda (root)
         (define t (timeline '(step "One." [AB (segment A B)])))
         (define dir (build-path root "review")) (define archive (build-path root "review.zip"))
         (define result
           (bundle t (make-geometry-review-plan t) dir #:zip archive
                   #:sheets (lambda (_plan stage)
                              (fixture-render! #f (build-path stage "contact-sheet.png"))
                              '("contact-sheet.png"))))
         (ensure (= (geometry-review-result-image-count result) 3) "frame count excludes sheet")
         (ensure (= (length (geometry-review-result-contact-sheets result)) 1) "sheet count")
         (ensure (member #"test-example/contact-sheet.png" (zip-directory-entries (read-zip-directory archive)))
                 "missing archived contact sheet")))))))

(define (bytes-prefix? s prefix)
  (and (>= (bytes-length s) (bytes-length prefix))
       (bytes=? (subbytes s 0 (bytes-length prefix)) prefix)))

(define (check-example name mode)
  (define factory (dynamic-require (build-path examples (string-append name ".rkt")) 'make-demo-timeline))
  (define t (factory #:theme-mode mode))
  (define plan (make-geometry-review-plan t))
  (define spans (geometry-timeline-steps t))
  (define expected
    (filter (lambda (s) (and (not (geometry-step-span-generated? s))
                             (geometry-review-span-reviewable? s spans)))
            spans))
  (ensure (= (length plan) (length expected)) "review-worthy authored/expanded step count differs" name)
  (ensure (andmap (lambda (row) (member (length (geometry-review-step-samples row)) '(3 7))) plan) "unexpected per-step image count")
  (define ids (sort (hash-keys (geometry-timeline-initial t)) symbol<?))
  (for ([row (in-list plan)])
    (define span (geometry-review-step-span row))
    (define samples (geometry-review-step-samples row))
    (define events (filter (lambda (e) (< (geometry-event-start e) (geometry-event-end e)))
                           (geometry-step-span-events span)))
    (ensure (<= (geometry-step-span-start span) (geometry-step-span-action-start span)
                (geometry-step-span-action-end span) (geometry-step-span-end span)) "bad boundaries")
    (for ([s (in-list samples)])
      (ensure (<= (geometry-step-span-start span) (geometry-review-sample-time s) (geometry-step-span-end span))
              "time outside step" name (geometry-review-step-number row))
      (ensure (equal? ids (sort (hash-keys (geometry-frame-appearances (geometry-review-sample-frame s))) symbol<?))
              "sample object ids differ"))
    (for ([sample (in-list samples)] #:when (memq (geometry-review-sample-phase sample) '(during pickup source-attention transport target-attention sweep)))
      (define time (geometry-review-sample-time sample))
      (ensure (ormap (lambda (e) (< (geometry-event-start e) time (geometry-event-end e))) events)
              "action sample fell in a pause or at an action boundary" name time (geometry-review-sample-phase sample)))
    (for ([s (in-list (list (car samples) (last samples)))]
          [state (in-list (list (geometry-step-span-before span) (geometry-step-span-after span)))])
      (for ([(id p) (in-hash state)])
        (define a (app s id))
        (ensure (= (geometry-appearance-opacity a) (if (presentation-shown? p) 1 0)) "boundary opacity")
        (ensure (= (geometry-appearance-highlight a) 0) "boundary has transient highlight"))))
  (ensure (equal? plan (make-geometry-review-plan t)) "nondeterministic plan"))

(define extra-review-groups
  (list
   (cons "compass circle rows receive seven choreography samples"
     (lambda ()
       (define program
         (compile
          (append givens
                  (list timing
                        '(step "Set the radius." [AB (segment A B)])
                        '(step "Draw the transferred circle." [k (circle C #:radius (length AB))])))))
       (define plan (make-geometry-review-plan (construction->timeline program)))
       (define row (cadr plan))
       (define samples (geometry-review-step-samples row))
       (define phases (map geometry-review-sample-phase samples))
       (ensure (equal? phases '(read pickup source-attention transport target-attention sweep settled))
               "compass phase order")
       (ensure (equal? (map geometry-review-sample-filename samples)
                       '("step-002-read.png"
                         "step-002-pickup.png"
                         "step-002-source-attention.png"
                         "step-002-transport.png"
                         "step-002-target-attention.png"
                         "step-002-sweep.png"
                         "step-002-settled.png"))
               "compass filenames")
       ;; Review timestamps target semantic reveal progress, not raw event
       ;; progress. The timeline applies smoothstep, so the planner must invert
       ;; that easing before selecting times.
       (define (phase-sample phase)
         (findf (lambda (sample) (eq? (geometry-review-sample-phase sample) phase)) samples))
       (near (geometry-appearance-reveal (app (phase-sample 'pickup) 'k))
             compass-review-pickup-progress)
       (near (geometry-appearance-reveal (app (phase-sample 'source-attention) 'k))
             compass-review-source-attention-progress)
       (near (geometry-appearance-reveal (app (phase-sample 'transport) 'k))
             compass-review-transport-progress)
       (near (geometry-appearance-reveal (app (phase-sample 'target-attention) 'k))
             compass-review-target-attention-progress)
       (near (geometry-appearance-reveal (app (phase-sample 'sweep) 'k))
             compass-review-sweep-progress)
       (ensure (member "Compass circle reveal: this row includes dedicated pickup, source-attention, transport, target-attention, and sweep samples."
                       (geometry-review-step-notes row))
               "missing compass note")))))

(define review-check-groups
  (append basic-groups extra-review-groups
          (for*/list ([name (in-list review-example-names)] [mode (in-list '(light dark))])
            (cons (format "all steps and samples: ~a / ~a" name mode)
                  (lambda () (check-example name mode))))))
(define (run-review-checks)
  (define checks (box 0))
  (parameterize ([counter checks])
    (for ([group (in-list review-check-groups)])
      (parameterize ([current-group (car group)])
        (printf "~a ... " (car group)) (flush-output)
        ((cdr group)) (displayln "ok"))))
  (printf "~a review groups, ~a checks passed.\n" (length review-check-groups) (unbox checks)))
(module+ main (run-review-checks))
