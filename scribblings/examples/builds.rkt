#lang racket/base
(require animate/slides)
(provide card clip film)

;; doc: content begin
(define card
  (slide #:id 'layout-title+body #:layout 'title+body
    [title "Explain one idea"]
    [body
     (bullets
      [structure "Choose a layout."]
      [identity "Name what matters."]
      [timing "Reveal it at the right moment."])]))
;; doc: content end

;; doc: beats begin
(define clip
  (build-slide card #:initial 'hidden
    (beat 'heading #:duration 0.7
      (reveal-slot 'title))
    (beat 'structure #:duration 0.9
      (reveal-slot '(body structure)))
    (beat 'identity #:duration 0.9
      (reveal-slot '(body identity)))
    (beat 'timing #:duration 0.9
      (reveal-slot '(body timing)))
    (beat 'read #:duration 1.6)))
;; doc: beats end

(define film
  (storyboard #:id 'manual-builds #:theme lecture-light
    (storyboard-shot 'builds clip)))
