#lang racket/base

;; Each example holds the outgoing state, performs one real bridge, then holds
;; the destination. Contrasting backdrops make viewport/mask behavior visible.
(require racket/list racket/string
         "../../main.rkt" "../../../colors.rkt")
(provide gallery-entry-shots transition-example)
(define (tag id part) (string->symbol (format "~a/~a" id part)))
(define (tinted-theme theme amount)
  (define colors (slide-theme-colors theme))
  (slide-theme #:id (string->symbol (format "gallery-tint-~a" amount)) #:extends theme
    #:colors (color-theme #:id 'gallery-tint #:extends colors
              #:roles (hash 'background
                         (color-mix (resolve-color theme-background colors)
                                    (resolve-color theme-accent colors) amount)))
    #:decorations (hash 'title-rule? #t)))
(define (transition-example id)
  (define parts (string-split (symbol->string id) "-"))
  (cond
    [(eq? id 'cut) (storyboard-cut)]
    [(eq? id 'zoom) (slide-transition #:effect 'zoom #:scale 0.82 #:duration 1 #:easing 'smooth)]
    [(eq? id 'fade-through) (slide-transition #:effect 'fade-through #:color "#101820" #:duration 1)]
    [(eq? id 'match) (slide-transition #:effect 'match #:keys '(topic) #:duration 1 #:easing 'smooth)]
    [(eq? id 'crossfade) (slide-transition #:duration 1 #:easing 'smooth)]
    [else (slide-transition #:effect (string->symbol (car parts))
                            #:direction (string->symbol (cadr parts))
                            #:duration 1 #:easing 'smooth)]))
(define (pair-shots id theme label transition)
  (list
   (storyboard-shot (tag id 'source)
     (hold-slide (slide #:id (tag id 'source-card) #:layout 'title #:theme (tinted-theme theme 0.06)
                   [title label] [subtitle "A — outgoing composition"])
                 #:duration 1.2))
   transition
   (storyboard-shot (tag id 'destination)
     (hold-slide (slide #:id (tag id 'destination-card) #:layout 'title+body #:theme (tinted-theme theme 0.20)
                   [title label]
                   [body (bullets [incoming "B — incoming composition"]
                                  [time "Content clocks pause during the bridge."]
                                  [style "Backgrounds and decorations participate."])])
                 #:duration 1.8))))
(define (gallery-entry-shots id theme fmt)
  (cond
    [(eq? id 'match)
     ;; Identical text, role, line layout, and theme give a genuine asset match.
     ;; Text alignment is explicitly left on both sides; slot placement differs.
     (define title (paragraph-content "Keep the idea" #:align 'left))
     (list
      (storyboard-shot (tag id 'source)
        (hold-slide (slide #:layout 'title
                      [title #:key 'topic #:align 'center title]
                      [subtitle "A centered introduction"])
                    #:duration 1.2))
      (transition-example 'match)
      (storyboard-shot (tag id 'destination)
        (hold-slide (slide #:layout 'title+body [title #:key 'topic title]
                      [body "The same prepared title moves to its new position.\nOnly the supporting content changes."])
                    #:duration 1.8)))]
    [(eq? id 'easing)
     (append-map
      (lambda (easing)
        (pair-shots (tag id easing) theme (format "Push / ~a" easing)
                    (slide-transition #:effect 'push #:direction 'left #:duration 1.2 #:easing easing)))
      '(linear smooth ease-in ease-out ease-in-out))]
    [else (pair-shots id theme (string-replace (symbol->string id) "-" " / ")
                      (transition-example id))]))
