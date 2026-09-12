#lang racket/base

;; Paginated, headless contact sheets. Never hold a whole movie in memory:
;; each page holds at most six rows, and source bitmaps are read one at a time.
(require racket/class racket/draw racket/list racket/string racket/format
         "../review-plan.rkt" "../core.rkt")
(provide write-review-contact-sheets!)

(define (write-review-contact-sheets! plan directory #:name name #:theme [theme "light"]
                                       #:thumbnail-width [thumb-width 384]
                                       #:aspect [aspect 16/9] #:rows-per-page [rows-per-page 6])
  (unless (and (pair? plan) (andmap geometry-review-step? plan)
               (exact-positive-integer? thumb-width) (positive? aspect)
               (exact-positive-integer? rows-per-page))
    (error 'geometry-review "invalid contact-sheet options"))
  (define gutter 12)
  (define thumb-height (max 1 (inexact->exact (round (/ thumb-width aspect)))))
  (define pages (quotient (+ (length plan) (sub1 rows-per-page)) rows-per-page))
  (define background (if (equal? theme "dark") (make-color 22 28 36) (make-color 246 247 249)))
  (define foreground (if (equal? theme "dark") (make-color 235 239 244) (make-color 26 35 46)))
  (define muted (if (equal? theme "dark") (make-color 180 192 208) (make-color 78 92 110)))
  (define border (if (equal? theme "dark") (make-color 76 89 108) (make-color 192 201 213)))
  (define body-font (make-font #:size 14 #:family 'swiss #:size-in-pixels? #t))
  (define title-font (make-font #:size 20 #:family 'swiss #:weight 'bold #:size-in-pixels? #t))
  (define heading-font (make-font #:size 15 #:family 'swiss #:weight 'bold #:size-in-pixels? #t))
  (define measure-bitmap (make-bitmap 1 1))
  (define measure-dc (new bitmap-dc% [bitmap measure-bitmap]))
  (send measure-dc set-font heading-font)
  (define (text-width s)
    (define-values (w _h _d _a) (send measure-dc get-text-extent s)) w)
  ;; Break long unspaced strings too, so generated helper ids cannot overflow.
  (define (wrap text max-width)
    (define lines '())
    (define line "")
    (for ([word (in-list (string-split text))])
      (define candidate (if (equal? line "") word (string-append line " " word)))
      (when (and (not (equal? line "")) (> (text-width candidate) max-width))
        (set! lines (cons line lines)) (set! line ""))
      (for ([ch (in-string (if (equal? line "") word (string-append " " word)))])
        (define next (string-append line (string ch)))
        (when (and (not (equal? line "")) (> (text-width next) max-width))
          (set! lines (cons line lines)) (set! line ""))
        (set! line (string-append line (string ch)))))
    (reverse (cons line lines)))
  (define (heading row)
    (format "Step ~a~a — ~a"
            (~r (geometry-review-step-number row) #:min-width 3 #:pad-string "0")
            (if (geometry-step-span-expanded? (geometry-review-step-span row)) " (expanded overview)" "")
            (or (geometry-review-step-caption row) "No new narration")))
  (define names
    (for/list ([page (in-range pages)])
      (define rows (take (drop plan (* page rows-per-page))
                         (min rows-per-page (- (length plan) (* page rows-per-page)))))
      (define columns (apply max (map (lambda (row) (length (geometry-review-step-samples row))) rows)))
      (define width (+ (* columns thumb-width) (* (add1 columns) gutter)))
      (define row-lines (map (lambda (row) (wrap (heading row) (- width (* 2 gutter)))) rows))
      (define row-heights (map (lambda (lines) (+ (* 20 (length lines)) thumb-height 52)) row-lines))
      (define height (+ 68 (apply + row-heights) gutter))
      (define canvas (make-bitmap width height))
      (define dc (new bitmap-dc% [bitmap canvas]))
      (define filename
        (if (= pages 1) "contact-sheet.png"
            (format "contact-sheet-~a.png" (~r (add1 page) #:min-width 3 #:pad-string "0"))))
      (dynamic-wind
       void
       (lambda ()
         (send dc set-background background) (send dc clear)
         (send dc set-smoothing 'smoothed)
         (send dc set-text-foreground foreground) (send dc set-font title-font)
         (send dc draw-text (format "~a / ~a — review ~a/~a" name theme (add1 page) pages) gutter 12)
         (send dc set-font body-font) (send dc set-text-foreground muted)
         (send dc draw-text "Rows may have either three or seven samples; each thumbnail is labeled below." gutter 42)
         ;; Do not use global phase headings: mixed three- and seven-sample rows
         ;; would place ordinary `during`/`settled` images under compass-only
         ;; `measure`/`transport` headings. Per-thumbnail labels are unambiguous.
         (define y 68)
         (for ([row (in-list rows)] [lines (in-list row-lines)] [row-height (in-list row-heights)])
           (send dc set-font heading-font) (send dc set-text-foreground foreground)
           (for ([line (in-list lines)] [line-number (in-naturals)])
             (send dc draw-text line gutter (+ y (* line-number 20))))
           (define image-y (+ y (* 20 (length lines)) 5))
           (for ([sample (in-list (geometry-review-step-samples row))] [col (in-naturals)])
             (define x (+ gutter (* col (+ thumb-width gutter))))
             (define bitmap (read-bitmap (build-path directory (geometry-review-sample-filename sample))))
             (unless (send bitmap ok?) (error 'geometry-review "cannot read review image for contact sheet"))
             (define transform (send dc get-transformation))
             (dynamic-wind
              void
              (lambda ()
                (send dc set-origin x image-y)
                (send dc set-scale (/ thumb-width (send bitmap get-width))
                                   (/ thumb-height (send bitmap get-height)))
                (unless (send dc draw-bitmap bitmap 0 0)
                  (error 'geometry-review "cannot draw contact-sheet thumbnail")))
              (lambda () (send dc set-transformation transform)))
             (send dc set-pen border 1 'solid) (send dc set-brush background 'transparent)
             (send dc draw-rectangle x image-y thumb-width thumb-height)
             (send dc set-font body-font) (send dc set-text-foreground muted)
             (send dc draw-text
                   (format "~a · ~a s" (geometry-review-sample-phase sample)
                           (~r (geometry-review-sample-time sample) #:precision '(= 3)))
                   x (+ image-y thumb-height 5)))
           (set! y (+ y row-height)))
         (unless (send canvas save-file (build-path directory filename) 'png)
           (error 'geometry-review "could not save contact sheet ~a" filename)))
       (lambda () (send dc set-bitmap #f)))
      filename))
  (send measure-dc set-bitmap #f)
  names)
