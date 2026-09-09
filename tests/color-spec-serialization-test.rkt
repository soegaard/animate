#lang racket/base

;;;
;;; Color Specification Serialization Tests
;;;

;; Ensures the versioned datum reader accepts only bounded declarative color
;; values and never evaluates external input.

(require rackunit
         racket/mpair
         "../colors.rkt")

(module+ test
  (define source
    (color-opacity
     (color-mix aqua-c
                (color-with-alpha (rgb-color 25 197 206) 3/4)
                1/2)
     1/4))
  (define encoded (color-spec->datum source))
  (check-equal? encoded
                '(animate-color-spec 1
                                     (alpha multiply 1/4
                                            (mix srgb-linear premultiplied 1/2
                                                 (palette aqua-c)
                                                 (rgba 25 197 206 3/4)))))
  (check-equal? (datum->color-spec encoded) source)
  ;; Alias input is normalized while reading, so a datum has one stable form.
  (check-equal? (datum->color-spec '(animate-color-spec 1 (palette aqua))) aqua-c)

  ;; There is no evaluator in the reader: arbitrary application-like data is
  ;; rejected as a tag, rather than executed.
  (for ([bad (in-list
              (list '(palette aqua-c)
                    '(animate-color-spec 2 (palette aqua-c))
                    '(animate-color-spec 1 (unknown aqua-c))
                    '(animate-color-spec 1 (rgba 0 0 0))
                    '(animate-color-spec 1 (mix srgb-linear premultiplied 2
                                               (palette aqua-c) (palette red-c)))
                    '(animate-color-spec 1 (alpha source-over 1/2 (palette aqua-c)))
                    '(animate-color-spec 1 (application erase-everything))))])
    (check-exn exn:fail:contract? (lambda () (datum->color-spec bad))))

  ;; Improper and mutable cyclic input cannot enter the immutable value model.
  (define cyclic (mcons 'animate-color-spec null))
  (set-mcdr! cyclic cyclic)
  (check-exn exn:fail:contract? (lambda () (datum->color-spec cyclic)))
  (check-exn exn:fail:contract?
             (lambda () (datum->color-spec encoded #:maximum-depth 0)))
  (check-exn exn:fail:contract?
             (lambda () (datum->color-spec encoded #:maximum-depth -1))))
