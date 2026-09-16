#lang racket/base
(require racket/list racket/match
         "data.rkt" "check.rkt" "model.rkt" "appearance.rkt" "layout.rkt"
         "content.rkt" "arrange.rkt" "schedule.rkt" "media.rkt" "sample.rkt"
         "preparation-session.rkt")
(provide resolve-slide resolve-storyboard prepared-slide? prepared-slide-clip? prepared-storyboard?
         prepared-duration)
(define prepared-slide? prepared-slide-value?)
(define prepared-slide-clip? prepared-clip-value?)
(define prepared-storyboard? prepared-storyboard-value?)
(define (prepared-duration v)
  (cond [(prepared-slide-value? v) 0] [(prepared-clip-value? v) (prepared-clip-value-duration v)]
        [(prepared-storyboard-value? v) (prepared-storyboard-value-duration v)]
        [else (raise-argument-error 'prepared-duration "prepared slide, clip, or storyboard" v)]))
(define (resolve-slide input #:theme [theme #f] #:format [fmt #f]
                       #:effects? [effects? #f] #:asset-base [base #f])
  (call-with-preparation-session
   (lambda () (resolve-slide/session input #:theme theme #:format fmt
                                     #:effects? effects? #:asset-base base))))
(define (resolve-slide/session input #:theme [requested-theme #f] #:format [requested-format #f]
                       #:effects? [effects? #f] #:asset-base [asset-base #f])
  (define context (and (contextual-value? input) input))
  (define source (if context (contextual-value-source context) input))
  (cond
    [(or (prepared-slide-value? source) (prepared-clip-value? source))
     (define p (if (prepared-clip-value? source) (prepared-clip-value-slide source) source))
     (when (or (and requested-theme (not (equal? requested-theme (prepared-slide-value-theme p))))
               (and requested-format (not (equal? requested-format (prepared-slide-value-format p)))))
       (slides-error 'frozen-context '() "prepared content has a different appearance/format; prepare the source again"))
     source]
    [else
     (define s (if (clip-value? source) (clip-value-slide source) source))
     (unless (slide-value? s) (raise-argument-error 'resolve-slide "slide, clip, or prepared value" input))
     (define theme (or (slide-value-theme s) requested-theme (and context (contextual-value-theme context)) lecture-light))
     (define format (or requested-format (and context (contextual-value-format context)) widescreen))
     (unless (theme-value? theme) (raise-argument-error 'resolve-slide "slide-theme?" theme))
     (unless (format-value? format) (raise-argument-error 'resolve-slide "slide-format?" format))
     (define reserve (if context (contextual-value-subtitle-height context) 0))
     (define motion (or (and (clip-value? source) (clip-value-motion source))
                        (and context (contextual-value-motion context)) 'normal))
     (define entries (slide-value-slots s))
     (define specs (append (layout-value-slots (slide-value-layout s)) (list (slot-spec 'footer #:role 'caption))))
     (define (role name) (slot-spec-role (findf (lambda (s) (eq? name (slot-spec-name s))) specs)))
     (define alternatives
       (for/hash ([(name slot) (in-hash entries)])
         (values name
                 (remove-duplicates
                  (cons (slot-value-content slot)
                        (if (clip-value? source)
                            (for*/list ([b (in-list (clip-value-beats source))]
                                        [a (in-list (beat-value-actions b))]
                                        #:when (and (eq? (action-value-kind a) 'replace)
                                                    (equal? (action-value-target a) (list name))))
                              (action-value-payload a)) '())) equal?))))
     (define metrics (make-hash))
     (define (measure name width)
       (define dims
         (hash-ref! metrics (list name width)
                    (lambda ()
                      (define all
                        (for/list ([c (in-list (hash-ref alternatives name))])
                          (define ctx (content-context-value theme format (box-value 0 0 width 1000000) asset-base effects?))
                          (call-with-values (lambda () (intrinsic-content c (role name) width ctx)) cons)))
                      (cons (apply max 0 (map car all)) (apply max 0 (map cdr all))))))
       (values (car dims) (cdr dims)))
     (define-values (placements safe) (arrange-slide s format theme reserve measure))
     (define slots
       (for/list ([spec (in-list specs)] #:when (hash-has-key? entries (slot-spec-name spec)))
         (define name (slot-spec-name spec))
         (define authored (hash-ref entries name))
         (define place (hash-ref placements name))
         (define rectangle (placement-box place))
         (define ctx (content-context-value theme format rectangle asset-base effects?))
         (define variants
           (for/list ([c (in-list (hash-ref alternatives name))])
             (prepare-content c (slot-spec-role spec) rectangle ctx (list name) (slot-value-key authored)
                              (or (slot-value-align authored) (placement-align place))
                              (or (slot-value-valign authored) (placement-valign place))
                              (or (slot-value-fit authored) (content-fit c)))))
         (prepared-slot name rectangle variants (slot-value-key authored) (hash-ref alternatives name))))
     (define diagnostics
       (for*/list ([slot (in-list slots)] [variant (in-list (prepared-slot-variants slot))]
                   [leaf (in-list variant)] #:when (prepared-leaf-clip leaf))
         (diagnostic 'info 'explicit-crop (prepared-leaf-path leaf) "Content explicitly uses cover/cropping." (hash))))
     (define prepared (prepared-slide-value s theme format reserve slots diagnostics motion))
     (if (clip-value? source)
         (compile-slide-clip prepared source (lambda (n) (prepare-narration n effects? asset-base)))
         prepared)]))
(define (resolve-storyboard input #:effects? [effects? #f] #:asset-base [base #f])
  (call-with-preparation-session
   (lambda () (resolve-storyboard/session input #:effects? effects? #:asset-base base))))
(define (resolve-storyboard/session input #:effects? [effects? #f] #:asset-base [asset-base #f])
  (cond [(prepared-storyboard-value? input) input]
        [(storyboard-value? input)
         (define shots '()) (define bridges '()) (define cursor 0) (define pending #f) (define previous #f)
         (for ([entry (in-list (storyboard-value-entries input))])
           (cond [(transition-value? entry) (set! pending entry)]
                 [else
                  (define clip (resolve-slide (bound-source input (shot-value-clip entry)) #:effects? effects? #:asset-base asset-base))
                  (when (and previous pending (> (transition-value-duration pending) 0))
                    (set! bridges (append bridges (list (prepared-bridge previous (shot-value-id entry) pending cursor #f))))
                    (set! cursor (+ cursor (transition-value-duration pending))))
                  (set! shots (append shots (list (prepared-shot (shot-value-id entry) clip cursor))))
                  (set! previous (shot-value-id entry))
                  (set! cursor (+ cursor (prepared-clip-value-duration clip)))
                  (set! pending #f)]))
         (validate-bridges (prepared-storyboard-value input shots bridges cursor
                                    (append-map (lambda (s) (prepared-slide-value-diagnostics (prepared-clip-value-slide (prepared-shot-clip s)))) shots)))]
        [else (raise-argument-error 'resolve-storyboard "storyboard or prepared storyboard" input)]))
