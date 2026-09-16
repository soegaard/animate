#lang racket/base
(require racket/class racket/list racket/match racket/runtime-path
         (only-in racket/draw read-bitmap)
         (prefix-in p: pict)
         file/sha1
         "data.rkt" "check.rkt" "appearance.rkt" "text.rkt" "media.rkt")
(provide prepare-content intrinsic-content content-fit asset-cue-time native-operation)
(define-runtime-path native-module "native.rkt")
(define (native-operation name) (dynamic-require native-module name))
(define (content-fit content)
  (cond [(string? content) 'natural]
        [(content-value? content)
         (hash-ref (content-value-options content) 'fit
                   (if (memq (content-value-kind content) '(text bullets)) 'natural 'contain))]
        [else 'contain]))
(define (asset-cue-time a cue)
  (cond [(eq? cue 'end) (asset-duration a)]
        [(eq? cue 'start) 0]
        [(nonnegative-number? cue)
         (if (<= cue (asset-duration a)) cue
             (slides-error 'content-time (list cue) "content time is outside its duration"))]
        [(hash-ref (asset-cues a) cue #f) => values]
        [else (slides-error 'unknown-content-cue (list cue) "embedded content has no such cue")]))
(define (text-source c default-role)
  (cond [(string? c) (values c default-role #f)]
        [(and (content-value? c) (eq? (content-value-kind c) 'text))
         (values (content-value-payload c)
                 (or (hash-ref (content-value-options c) 'role #f) default-role)
                 (hash-ref (content-value-options c) 'align #f))]
        [else (slides-error 'bullet-content '() "bullet items must be strings or paragraph-content values")]))
(define (single-asset content role rectangle ctx #:align [alignment #f])
  (define width (box-value-width rectangle))
  (define theme (content-context-value-theme ctx))
  (cond
    [(or (string? content) (and (content-value? content) (eq? (content-value-kind content) 'text)))
     (define-values (text selected-role align) (text-source content role))
     (text-asset text selected-role width theme #:align (or align alignment))]
    [(p:pict? content) (pict-asset content #f)]
    [(and (content-value? content) (eq? (content-value-kind content) 'pict))
     (define value (content-value-payload content))
     (define picture (if (procedure? value) (value ctx) value))
     (pict-asset picture #f)]
    [(and (content-value? content) (eq? (content-value-kind content) 'image))
     (unless (content-context-value-effects? ctx)
       (slides-error 'preparation-required '(image) "image files require prepare-slide! or prepare-storyboard!"))
     (define path (resolve-asset-path (content-value-payload content)
                                      (hash-ref (content-value-options content) 'asset-base #f)
                                      (content-context-value-asset-base ctx)))
     (unless (file-exists? path) (slides-error 'missing-asset (list (path->string path)) "image file does not exist"))
     (define bitmap (read-bitmap path))
     (unless (send bitmap ok?) (slides-error 'image-decode (list (path->string path)) "cannot decode image"))
     (struct-copy asset (pict-asset (p:bitmap bitmap) (list 'image (call-with-input-file path sha1)))
                  [metadata (hash 'source (path->string path))])]
    [else ((native-operation 'prepare-native-content) content role rectangle ctx)]))
(define (place-asset a rectangle path key align valign fit)
  (define w (asset-width a)) (define h (asset-height a))
  (define aw (box-value-width rectangle)) (define ah (box-value-height rectangle))
  (define factor
    (case fit
      [(contain) (if (or (= w 0) (= h 0)) 1 (min (/ aw w) (/ ah h)))]
      [(cover) (if (or (= w 0) (= h 0)) 1 (max (/ aw w) (/ ah h)))]
      [else 1]))
  (define fw (* w factor)) (define fh (* h factor))
  (when (and (not (eq? fit 'cover)) (or (> fw (+ aw 1e-6)) (> fh (+ ah 1e-6))))
    (slides-error 'content-overflow path "content exceeds its available region; edit content or explicitly select a fitting policy"
                  (hash 'measured-width fw 'measured-height fh 'available-width aw 'available-height ah)))
  (define x (+ (box-value-x rectangle) (case align [(center) (/ (- aw fw) 2)] [(right) (- aw fw)] [else 0])))
  (define y (+ (box-value-y rectangle) (case valign [(center) (/ (- ah fh) 2)] [(bottom) (- ah fh)] [else 0])))
  (prepared-leaf path (box-value x y fw fh) a key (and (eq? fit 'cover) rectangle)))
(define (bullet-assets content role width theme)
  (define ordered? (hash-ref (content-value-options content) 'ordered? #f))
  (define indent 0.48)
  (for/list ([entry (in-list (content-value-payload content))] [i (in-naturals 1)])
    (define-values (text selected-role align) (text-source (cdr entry) role))
    (define body (text-asset text selected-role (max 0 (- width indent)) theme #:align align))
    (define marker (text-asset (if ordered? (format "~a." i) "•") selected-role indent theme))
    (define y (- (asset-baseline body) (asset-baseline marker)))
    (define hh (max (asset-height body) (+ y (asset-height marker))))
    (define ww (+ indent (asset-width body)))
    (define picture
      (p:pin-over
       (p:pin-over (p:blank (* measure-scale ww) (* measure-scale hh))
                   0 (* measure-scale y) (asset-value marker))
       (* measure-scale indent) 0 (asset-value body)))
    (cons (car entry)
          (asset 'pict picture ww hh (asset-baseline body) 0 'end (hash)
                 (list 'bullet (and ordered? i) ordered? (asset-identity body)) (asset-metadata body)))))
(define (prepare-content content role rectangle ctx path key align valign fit)
  (define theme (content-context-value-theme ctx))
  (cond
    [(and (content-value? content) (eq? (content-value-kind content) 'bullets))
     (when (not (eq? fit 'natural))
       (slides-error 'text-fitting path "bullet lists use natural typography; edit the font size instead of scaling the list"))
     (define entries (bullet-assets content role (box-value-width rectangle) theme))
     (define gap (theme-spacing theme 'bullet-gap))
     (define total (+ (apply + (map (lambda (e) (asset-height (cdr e))) entries))
                      (* gap (max 0 (sub1 (length entries))))))
     (when (> total (+ (box-value-height rectangle) 1e-6))
       (slides-error 'content-overflow path "bullet list exceeds available height"
                     (hash 'measured-height total 'available-height (box-value-height rectangle))))
     (define top (+ (box-value-y rectangle)
                    (case valign [(center) (/ (- (box-value-height rectangle) total) 2)]
                          [(bottom) (- (box-value-height rectangle) total)] [else 0])))
     (define-values (leaves ignored)
       (for/fold ([leaves '()] [y top]) ([e (in-list entries)])
         (define a (cdr e))
         (values (cons (place-asset a (box-value (box-value-x rectangle) y (box-value-width rectangle) (asset-height a))
                                    (append path (list (car e))) key align 'top 'natural) leaves)
                 (+ y (asset-height a) gap))))
     (reverse leaves)]
    [else
     (define a (single-asset content role rectangle ctx #:align align))
     (list (place-asset a rectangle path key align valign fit))]))
(define (intrinsic-content content role width ctx)
  (cond [(and (content-value? content) (eq? (content-value-kind content) 'bullets))
         (define entries (bullet-assets content role width (content-context-value-theme ctx)))
         (values (apply max 0 (map (lambda (e) (asset-width (cdr e))) entries))
                 (+ (apply + (map (lambda (e) (asset-height (cdr e))) entries))
                    (* (theme-spacing (content-context-value-theme ctx) 'bullet-gap) (max 0 (sub1 (length entries))))))]
        [else
         (define a (single-asset content role (box-value 0 0 width 1000000) ctx))
         (values (asset-width a) (asset-height a))]))
