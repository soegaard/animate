#lang racket/base
;; Shared presentation of stored manual frames. No Animate renderer is loaded.
(require racket/list racket/path racket/runtime-path
         (only-in scribble/base image)
         (only-in scribble/core make-style make-element make-multiarg-element
                  make-paragraph make-nested-flow)
         (only-in scribble/html-properties css-addition attributes alt-tag)
         (only-in scribble/latex-properties tex-addition))
(provide (struct-out manual-frame) manual-frame-strip)

;; Width/height are the original image dimensions, not a request to resample it.
(struct manual-frame (path width height caption) #:transparent)
(define-runtime-path css-file "frame-style.css")
(define-runtime-path tex-file "frame-style.tex")
(define additions (list (css-addition css-file) (tex-addition tex-file)))
(define (style name [properties '()])
  (make-style name (append additions properties)))

(define picture-style (style "AnimFramePicture"))
(define caption-style (style "AnimFrameCaption"))
(define card-style (style "AnimFrameCard"))
(define gap (make-element (style "AnimFrameGap") '()))
(define row-names '#("" "One" "Two" "Three" "Four" "Five"))

(define (chunks xs count)
  (if (null? xs) '()
      (let ([n (min count (length xs))])
        (cons (take xs n) (chunks (drop xs n) count)))))

(define (check-frame frame)
  (unless (manual-frame? frame)
    (raise-argument-error 'manual-frame-strip "manual-frame?" frame))
  (unless (and (path-string? (manual-frame-path frame))
               (file-exists? (manual-frame-path frame)))
    (raise-arguments-error 'manual-frame-strip "expected an existing captured image"
                           "path" (manual-frame-path frame)))
  (for ([size (in-list (list (manual-frame-width frame) (manual-frame-height frame)))])
    (unless (and (real? size) (< 0 size +inf.0))
      (raise-argument-error 'manual-frame-strip "positive finite image dimension" size)))
  (unless (string? (manual-frame-caption frame))
    (raise-argument-error 'manual-frame-strip "string? caption" (manual-frame-caption frame))))

;; Default: all three or five frames in one preferred row. CSS wraps only when
;; that row cannot fit at a useful minimum width. #:columns is an explicit
;; readability override; old catalogue 'columns metadata is not an override.
(define (manual-frame-strip frames #:columns [columns #f]
                            #:note [note #f] #:label [label "Sampled frames"])
  (unless (and (list? frames) (pair? frames))
    (raise-argument-error 'manual-frame-strip "nonempty list of manual-frame values" frames))
  (for-each check-frame frames)
  (unless (or (not columns) (and (exact-integer? columns) (<= 1 columns 5)))
    (raise-argument-error 'manual-frame-strip "#f or an integer from 1 to 5" columns))
  (unless (or (not note) (string? note))
    (raise-argument-error 'manual-frame-strip "#f or string? note" note))
  (unless (string? label)
    (raise-argument-error 'manual-frame-strip "string? label" label))
  (define count (min (or columns 5) (length frames)))
  (define row-style
    (style (string-append "AnimFrameRow" (vector-ref row-names count))))
  (define cards
    (for/list ([frame (in-list frames)])
      ;; Intrinsic size is retained. CSS/TeX scale only the displayed image;
      ;; neither the capture bytes nor their checksum manifests change.
      (define caption (manual-frame-caption frame))
      (define picture
        (image
         (path->complete-path (manual-frame-path frame))
         #:style
         (make-style
          #f
          (list (attributes
                 (list (cons 'style
                             (format "aspect-ratio: auto ~a / ~a;"
                                     (exact->inexact (manual-frame-width frame))
                                     (exact->inexact (manual-frame-height frame))))))))
         caption))
      (make-multiarg-element
       card-style
       (list (make-element picture-style (list picture))
             (make-element caption-style (list caption))))))
  (make-nested-flow
   (style "AnimFrameStrip"
          (list (alt-tag "div")
                (attributes (list (cons 'role "group") (cons 'aria-label label)))))
   (append
    (for/list ([row (in-list (chunks cards count))])
      (make-paragraph row-style (add-between row gap)))
    (if note (list (make-paragraph (style "AnimFrameNote") (list note))) '()))))
