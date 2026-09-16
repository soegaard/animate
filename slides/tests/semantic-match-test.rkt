#lang racket/base
(require (only-in rackunit test-suite test-case check-equal? check-true check-false check-exn check-=)
         racket/list racket/file
         (only-in pict pict?)
         (only-in "../../main.rkt" make-scene make-camera scene-add circle vec2
                  scene-play move-to linear scene-sample scene-camera-at scene-state->pict)
         (only-in "../../project.rkt" source-transfer-data?)
         "../main.rkt" "../pict.rkt" "../scene.rkt" "../render.rkt" "../gallery.rkt"
         "../private/data.rkt" "../private/sample.rkt" "../private/semantic-plan.rkt"
         "../private/codec.rkt" "helpers.rkt")
(provide tests)

(define motion
  (scene-play
   (scene-add (make-scene #:camera (make-camera #:width 320 #:height 180 #:world-width 8))
              (circle #:id 'disc #:center (vec2 -2 0) #:radius 0.5 #:fill "red"))
   (move-to 'disc (vec2 2 0)) #:duration 2 #:easing linear))
(define moving (scene-content motion))
(define (state t) (content-state moving #:at t))
(define (card c) (slide #:layout 'figure-full [figure #:key 'work c]))
(define (film a b #:depth [depth 'auto] #:motion [motion 'normal])
  (storyboard #:motion motion
    (storyboard-shot 'a (hold-slide (card a) #:duration 1))
    (slide-transition #:effect 'match #:keys '(work) #:depth depth #:duration 2)
    (storyboard-shot 'b (hold-slide (card b) #:duration 1))))
(define (bridge board) (car (prepared-storyboard-value-bridges board)))
(define (plan board) (car (prepared-bridge-plan (bridge board))))
(define (pairs board) (match-plan-pairs (plan board)))
(define (part id text x)
  (semantic-part id text #:x x #:y 0 #:width 2 #:height 1 #:fit 'natural))
(define (panel . parts) (apply semantic-group #:width 6 #:height 2 parts))
(define (close-box? a b)
  (andmap (lambda (f) (< (abs (- (f a) (f b))) 1e-8))
          (list box-value-x box-value-y box-value-width box-value-height)))

(define (mean-delta a b)
  (check-equal? (bytes-length a) (bytes-length b))
  (/ (for/sum ([x (in-bytes a)] [y (in-bytes b)]) (abs (- x y))) (bytes-length a)))

(define tests
  (test-suite
   "prepared semantic correspondence"
   (test-case "public descriptions reject duplicate identities and invalid geometry"
     (check-true (semantic-part? (part 'x "x" 0)))
     (check-true (semantic-group? (panel (part 'x "x" 0))))
     (check-true (content-state? (state 'end)))
     (check-exn exn:fail? (lambda () (panel (part 'x "x" 0) (part 'x "x" 3))))
     (check-exn (code? 'semantic-bounds) (lambda () (panel (part 'x "x" 5))))
     (check-exn exn:fail? (lambda () (content-state "opaque equation" #:at 'start))))
   (test-case "depth is an explicit validated transition policy"
     (check-equal? (slide-transition-depth (slide-transition #:effect 'match)) 'auto)
     (check-equal? (slide-transition-depth (slide-transition #:effect 'match #:depth 'slot)) 'slot)
     (check-exn (code? 'transition-option) (lambda () (slide-transition #:depth 'semantic)))
     (check-exn exn:fail? (lambda () (slide-transition #:effect 'match #:depth 'guess))))
   (test-case "duplicate visible strings match by child name, not order"
     (define b (prepare-storyboard!
                (film (panel (part 'first "x" 0) (part 'second "x" 3))
                      (panel (part 'second "x" 0) (part 'first "x" 3)) #:depth 'semantic)))
     (check-equal? (length (pairs b)) 2)
     (for ([p (in-list (pairs b))])
       (check-equal? (cddr (frame-leaf-path (match-pair-source p)))
                     (cddr (frame-leaf-path (match-pair-target p)))))
     (check-equal? (map match-pair-mode (pairs b)) '(preserve preserve)))
   (test-case "named appearance changes crossfade without claiming glyph morphs"
     (define b (prepare-storyboard! (film (panel (part 'message "before" 0))
                                         (panel (part 'message "after" 3)) #:depth 'semantic)))
     (check-equal? (map match-pair-mode (pairs b)) '(replace))
     (define leaves (frame-value-leaves (sample-storyboard b 2)))
     (check-equal? (length leaves) 2)
     (check-equal? (map frame-leaf-opacity leaves) '(1/2 1/2)))
   (test-case "inserted and removed children do not break surviving matches"
     (define b (prepare-storyboard!
                (film (panel (part 'keep "same" 0) (part 'remove "old" 3))
                      (panel (part 'add "new" 0) (part 'keep "same" 3)) #:depth 'semantic)))
     (check-equal? (length (pairs b)) 1)
     (check-equal? (map (lambda (l) (cddr (frame-leaf-path l))) (match-plan-outgoing (plan b))) '((remove)))
     (check-equal? (map (lambda (l) (cddr (frame-leaf-path l))) (match-plan-incoming (plan b))) '((add))))
   (test-case "nested sibling namespaces remain distinct"
     (define (nested swap?)
       (semantic-group #:width 12 #:height 3
         (semantic-part 'left (panel (part 'label "x" (if swap? 3 0)))
                        #:x 0 #:y 0 #:width 6 #:height 2)
         (semantic-part 'right (panel (part 'label "x" (if swap? 0 3)))
                        #:x 6 #:y 0 #:width 6 #:height 2)))
     (define b (prepare-storyboard! (film (nested #f) (nested #t) #:depth 'semantic)))
     (check-equal? (map (lambda (p) (cddr (frame-leaf-path (match-pair-target p)))) (pairs b))
                   '((left label) (right label))))
   (test-case "parent and local transforms compose, rather than interpolate baked positions"
     (define fake (asset 'pict #f 1 1 1 0 'end (hash) '(same) (hash)))
     (define (leaf path box chain)
       (frame-leaf path box (struct-copy asset fake [metadata (hash 'semantic-chain chain)]) 0 1 1 'work #f))
     (define a (leaf '(a figure x) (box-value 0 0 2 2)
                     (list (box-value 0 0 8 8) (box-value 0 0 1/4 1/4))))
     (define b (leaf '(b figure x) (box-value 6 0 1 1)
                     (list (box-value 4 0 4 4) (box-value 1/2 0 1/4 1/4))))
     (define p (match-pair a b 'preserve #f #f #f 'identity))
     (check-equal? (box-value-x (match-pair-box p 1/2)) 7/2)
     (check-equal? (match-pair-box p 0) (frame-leaf-box a))
     (check-equal? (match-pair-box p 1) (frame-leaf-box b)))
   (test-case "prepared nested ancestry reproduces both endpoint boxes"
     (define b (prepare-storyboard! (make-slide-gallery #:entries '(semantic-parts))))
     (for ([p (in-list (pairs b))])
       (check-true (close-box? (match-pair-box p 0) (frame-leaf-box (match-pair-source p))))
       (check-true (close-box? (match-pair-box p 1) (frame-leaf-box (match-pair-target p))))))
   (test-case "snapshots stay fixed throughout their own shot"
     (define p (prepare-slide! (hold-slide (card (state 1)) #:duration 3)))
     (check-equal? (pixel-bytes (slide->pict p #:at 0 #:size '(320 180)))
                   (pixel-bytes (slide->pict p #:at 3 #:size '(320 180)))))
   (test-case "a domain witness advances only during the matched bridge"
     (define b (prepare-storyboard! (film (state 0) (state 2) #:depth 'semantic)))
     (define p (car (pairs b)))
     (check-equal? (match-pair-mode p) 'replay)
     (check-equal? (match-pair-from-time p) 0)
     (check-equal? (match-pair-to-time p) 2)
     (define frame (sample-storyboard b 2))
     (check-equal? (length (frame-value-leaves frame)) 1)
     (check-equal? (frame-leaf-time (car (frame-value-leaves frame))) 1)
     (check-false (hash-ref (asset-metadata (frame-leaf-asset (car (frame-value-leaves frame)))) 'state-time #f)))
   (test-case "slot depth retains conservative whole-asset fallback"
     (define b (prepare-storyboard! (film (state 0) (state 2) #:depth 'slot)))
     (check-equal? (pairs b) '())
     (check-equal? (length (frame-value-leaves (sample-storyboard b 2))) 2))
   (test-case "unsupported and reverse domain transitions are explicit"
     (check-exn (code? 'semantic-match-unavailable)
                (lambda () (prepare-storyboard! (film (state 2) (state 0) #:depth 'semantic))))
     (define b (prepare-storyboard! (film (state 2) (state 0))))
     (check-equal? (match-plan-reason (plan b)) 'backward-domain-transition)
     (check-exn (code? 'semantic-match-unavailable)
       (lambda () (prepare-storyboard! (film "one" "two" #:depth 'semantic)))))
   (test-case "domain appearance and viewport differences are not hidden"
     (check-exn (code? 'semantic-match-unavailable)
       (lambda () (prepare-storyboard!
                    (film (state 0) (content-state moving #:at 2 #:viewport '(8 8)) #:depth 'semantic)))))
   (test-case "snapshots do not accidentally start a local clip clock"
     (check-exn (code? 'not-animated)
       (lambda () (prepare-slide!
                    (build-slide (card (state 0)) (beat 'play #:duration 3 (play-content 'figure)))))))
   (test-case "animated children need explicit snapshots"
     (check-exn (code? 'semantic-animated-child)
       (lambda () (prepare-slide! (card (panel (semantic-part 'moving moving #:width 4 #:height 2)))))))
   (test-case "reduced motion crossfades frozen endpoints without replay"
     (define b (prepare-storyboard! (film (state 0) (state 2) #:depth 'semantic #:motion 'reduced)))
     (define leaves (frame-value-leaves (sample-storyboard b 2)))
     (check-equal? (length leaves) 2)
     (check-equal? (map frame-leaf-time leaves) '(0 0))
     (check-equal? (map (lambda (l) (hash-ref (asset-metadata (frame-leaf-asset l)) 'state-time)) leaves) '(0 2)))
   (test-case "native and Pict semantic replay agree and seek deterministically"
     (define b (prepare-storyboard! (film (state 0) (state 2) #:depth 'semantic)))
     (define scn (storyboard->scene b #:size '(320 180)))
     (for ([t (in-list '(4 3 5/2 2 3/2 1 0 2))])
       (define direct (storyboard->pict b #:at t #:size '(320 180)))
       (define native (scene-state->pict (scene-sample scn t) #:camera (scene-camera-at scn t)))
       (check-true (<= (mean-delta (pixel-bytes direct) (pixel-bytes native)) 0.05))
       (check-equal? (pixel-bytes direct) (pixel-bytes (storyboard->pict b #:at t #:size '(320 180))))))
   (test-case "native snapshot and recursive ancestry survive portable reconstruction"
     (define (group t) (panel (semantic-part 'moving (state t) #:width 6 #:height 2)))
     (define source (film (group 0) (group 2) #:depth 'semantic))
     (define b (prepare-storyboard! source))
     (define temp (make-temporary-file "slides-semantic-codec-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (define-values (payload artifacts dependencies) (prepared-storyboard->payload! b temp))
         (check-true (source-transfer-data? payload))
         (define restored (payload->prepared-storyboard payload source))
         (check-equal? (storyboard-match-report b) (storyboard-match-report restored))
         (for ([t (in-list '(4 3 2 1 0))])
           (check-equal? (sample-signature (sample-storyboard b t))
                         (sample-signature (sample-storyboard restored t)))))
       (lambda () (delete-directory/files temp))))
   (test-case "recursive Pict child geometry survives portable reconstruction"
     (define source (make-slide-gallery #:entries '(semantic-parts)))
     (define b (prepare-storyboard! source))
     (define temp (make-temporary-file "slides-semantic-pict-codec-~a" 'directory))
     (dynamic-wind void
       (lambda ()
         (define-values (payload artifacts dependencies) (prepared-storyboard->payload! b temp))
         (check-true (source-transfer-data? payload))
         (define restored (payload->prepared-storyboard payload source))
         (check-equal? (storyboard-match-report b) (storyboard-match-report restored))
         (check-equal? (sample-signature (sample-storyboard b 3))
                       (sample-signature (sample-storyboard restored 3))))
       (lambda () (delete-directory/files temp))))
   (test-case "match reports are data, not closures or native handles"
     (define b (prepare-storyboard! (film (state 0) (state 2) #:depth 'semantic)))
     (check-true (source-transfer-data? (storyboard-match-report b))))))
(module+ test
  (require (only-in rackunit/text-ui run-tests))
  (unless (zero? (run-tests tests)) (error 'semantic-match-test "failed")))
