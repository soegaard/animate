#lang racket/base

;;;
;;; Inline TeX Content Model
;;;

;; Defines the immutable, renderer-independent mixed prose and TeX content
;; representation shared by slide slots and calculus captions.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         racket/string)

;; Exports
(provide literal-text
         inline-text
         tex-span
         tex-span?
         tex-span-source
         tex-span-plain
         text-content?
         text-content-runs
         text-content-source
         text-content->plain
         text-run?
         text-run-kind
         text-run-content
         text-run-plain
         text-run-start
         text-run-end
         parse-inline-text
         normalize-text-content
         exn:fail:inline-tex?
         exn:fail:inline-tex-code
         exn:fail:inline-tex-start
         exn:fail:inline-tex-end)


;;;
;;; Data Representation
;;;

(struct tex-span-data (source plain)
  #:transparent)

;; tex-span-data represents one explicit delimiter-free mathematical fragment.
;;  - source  immutable-string?           TeX source without math delimiters.
;;  - plain   (or/c immutable-string? #f) optional authored text-export fallback.

(struct text-run-data (kind content plain start end)
  #:transparent)

;; text-run-data represents one normalized source interval.
;;  - kind     one of 'text, 'inline-math, 'display-math, or 'hard-break.
;;  - content  immutable-string?  prose or delimiter-free TeX source.
;;  - plain    immutable-string?  deterministic plain-text representation.
;;  - start    exact-nonnegative-integer?  inclusive runtime-string offset.
;;  - end      exact-nonnegative-integer?  exclusive runtime-string offset.

(struct text-content-data (runs source plain-override)
  #:transparent)

;; text-content-data represents one immutable ordered sequence of text runs.
;;  - runs           immutable list of text-run-data values in source order.
;;  - source         (or/c immutable-string? #f) original shorthand source.
;;  - plain-override (or/c immutable-string? #f) authored whole-content export.

(struct exn:fail:inline-tex exn:fail (code start end)
  #:transparent)

;; exn:fail:inline-tex records a source-local markup diagnostic.
;;  - code   symbol?                       stable machine-readable category.
;;  - start  exact-nonnegative-integer?    inclusive runtime-string offset.
;;  - end    exact-nonnegative-integer?    exclusive runtime-string offset.


;;;
;;; Public Construction
;;;

; tex-span : string? [#:plain (or/c string? #f)] -> tex-span?
;; Creates one explicit delimiter-free inline TeX fragment.
(define (tex-span source #:plain [plain #f])
  (define checked-source (immutable-string 'tex-span source))
  (when (blank-string? checked-source)
    (raise-arguments-error 'tex-span
                           "a nonempty TeX body"
                           "source" source))
  (tex-span-data checked-source
                 (and plain (immutable-string 'tex-span plain))))

; tex-span? : any/c -> boolean?
;; Reports whether value is an explicit TeX fragment.
(define tex-span? tex-span-data?)

; tex-span-source : tex-span? -> immutable-string?
;; Returns an explicit fragment's delimiter-free TeX source.
(define tex-span-source tex-span-data-source)

; tex-span-plain : tex-span? -> (or/c immutable-string? #f)
;; Returns an explicit fragment's optional plain-text fallback.
(define tex-span-plain tex-span-data-plain)

; literal-text : string? [#:plain (or/c string? #f)] -> text-content?
;; Creates ordinary content whose dollars and backslashes remain literal.
(define (literal-text source #:plain [plain #f])
  (define checked-source (immutable-string 'literal-text source))
  (make-text-content
   (literal-runs checked-source)
   checked-source
   (and plain (immutable-string 'literal-text plain))))

; inline-text : [#:plain (or/c string? #f)]
;               (or/c string? tex-span? text-content?) ...
;               -> text-content?
;; Joins literal prose and explicit TeX fragments without reparsing prose.
(define (inline-text #:plain [plain #f] . pieces)
  (define checked-pieces
    (for/list ([piece (in-list pieces)])
      (cond [(string? piece) (literal-text piece)]
            [(tex-span? piece) (explicit-tex-content piece)]
            [(text-content? piece) piece]
            [else
             (raise-argument-error
              'inline-text
              "(or/c string? tex-span? text-content?)"
              piece)])))
  (make-text-content
   (append-map text-content-runs checked-pieces)
   #f
   (and plain (immutable-string 'inline-text plain))))


;;;
;;; Normalization and Inspection
;;;

; text-content? : any/c -> boolean?
;; Reports whether value is immutable normalized mixed text content.
(define text-content? text-content-data?)

; text-content-runs : text-content? -> (listof text-run?)
;; Returns ordered immutable prose, math, and hard-break runs.
(define text-content-runs text-content-data-runs)

; text-content-source : text-content? -> (or/c immutable-string? #f)
;; Returns the original shorthand source when content came from one string.
(define text-content-source text-content-data-source)

; text-run? : any/c -> boolean?
;; Reports whether value is one normalized source run.
(define text-run? text-run-data?)

; text-run-kind : text-run? -> symbol?
;; Returns a run's prose, inline-math, display-math, or hard-break kind.
(define text-run-kind text-run-data-kind)

; text-run-content : text-run? -> immutable-string?
;; Returns prose or delimiter-free TeX source.
(define text-run-content text-run-data-content)

; text-run-plain : text-run? -> immutable-string?
;; Returns the run's deterministic plain-text representation.
(define text-run-plain text-run-data-plain)

; text-run-start : text-run? -> exact-nonnegative-integer?
;; Returns the inclusive source offset for this run.
(define text-run-start text-run-data-start)

; text-run-end : text-run? -> exact-nonnegative-integer?
;; Returns the exclusive source offset for this run.
(define text-run-end text-run-data-end)

; text-content->plain : text-content? -> immutable-string?
;; Returns the authored whole-content fallback or deterministic run fallback.
(define (text-content->plain value)
  (unless (text-content? value)
    (raise-argument-error 'text-content->plain "text-content?" value))
  (or (text-content-data-plain-override value)
      (string->immutable-string
       (apply string-append
              (for/list ([run (in-list (text-content-runs value))])
                (text-run-plain run))))))

; parse-inline-text : string? -> text-content?
;; Parses markup-enabled shorthand into immutable source-mapped runs.
(define (parse-inline-text source)
  (define checked-source (immutable-string 'parse-inline-text source))
  (define length (string-length checked-source))
  (define runs '())
  (define text-start #f)
  (define text-out (open-output-string))

  ; flush-text! : exact-nonnegative-integer? -> void?
  ;; Commits the current ordinary prose source interval.
  (define (flush-text! end)
    (when text-start
      (define content (get-output-string text-out))
      (unless (string=? content "")
        (set! runs
              (cons (text-run-data 'text
                                   (string->immutable-string content)
                                   (string->immutable-string content)
                                   text-start
                                   end)
                    runs)))
      (set! text-start #f)
      (set! text-out (open-output-string))))

  ; append-text! : character? exact-nonnegative-integer? -> void?
  ;; Extends the current ordinary prose run.
  (define (append-text! character source-index)
    (unless text-start
      (set! text-start source-index))
    (write-char character text-out))

  ; append-backslashes! : exact-nonnegative-integer? exact-nonnegative-integer? -> void?
  ;; Retains literal paired escaping backslashes before an active delimiter.
  (define (append-backslashes! count source-index)
    (for ([offset (in-range count)])
      (append-text! #\\ (+ source-index offset))))

  ; add-break! : exact-nonnegative-integer? exact-nonnegative-integer? -> void?
  ;; Records one author-visible line break without assigning it to prose.
  (define (add-break! start end)
    (flush-text! start)
    (set! runs
          (cons (text-run-data 'hard-break "" "\n" start end) runs)))

  ; add-math! : symbol? string? exact-nonnegative-integer? exact-nonnegative-integer? -> void?
  ;; Records one already-validated mathematical source interval.
  (define (add-math! kind body start end)
    (flush-text! start)
    (set! runs
          (cons (text-run-data kind
                               (string->immutable-string body)
                               (string->immutable-string body)
                               start
                               end)
                runs)))

  (let loop ([index 0])
    (cond
      [(= index length)
       (flush-text! length)
       (make-text-content (reverse runs) checked-source #f)]
      [else
       (define character (string-ref checked-source index))
       (cond
         [(char=? character #\newline)
          (add-break! index (add1 index))
          (loop (add1 index))]
         [(char=? character #\\)
          (define slash-end
            (let scan ([cursor index])
              (if (and (< cursor length)
                       (char=? (string-ref checked-source cursor) #\\))
                  (scan (add1 cursor))
                  cursor)))
          (define slash-count (- slash-end index))
          (define next-character
            (and (< slash-end length)
                 (string-ref checked-source slash-end)))
          (cond
            [(and next-character
                  (member next-character '(#\$ #\( #\[)))
             (define escaped-dollar?
               (and (char=? next-character #\$)
                    (odd? slash-count)))
             (append-backslashes! (quotient slash-count 2) index)
             (cond
               [escaped-dollar?
                (append-text! next-character slash-end)
                (loop (add1 slash-end))]
               [(char=? next-character #\$)
                (if (and (< (add1 slash-end) length)
                         (char=? (string-ref checked-source (add1 slash-end)) #\$))
                    (let-values ([(body end)
                                  (scan-math checked-source
                                             (+ slash-end 2)
                                             "$$"
                                             'display-math)])
                      (add-math! 'display-math body index end)
                      (loop end))
                    (let-values ([(body end)
                                  (scan-math checked-source
                                             (add1 slash-end)
                                             "$"
                                             'inline-math)])
                      (add-math! 'inline-math body index end)
                      (loop end)))]
               [(char=? next-character #\()
                (let-values ([(body end)
                              (scan-math checked-source
                                         (add1 slash-end)
                                         "\\)"
                                         'inline-math)])
                  (add-math! 'inline-math body index end)
                  (loop end))]
               [else
                (let-values ([(body end)
                              (scan-math checked-source
                                         (add1 slash-end)
                                         "\\]"
                                         'display-math)])
                  (add-math! 'display-math body index end)
                  (loop end))])]
            [else
             (append-backslashes! slash-count index)
             (loop slash-end)])]
         [(char=? character #\$)
          (if (and (< (add1 index) length)
                   (char=? (string-ref checked-source (add1 index)) #\$))
              (let-values ([(body end)
                            (scan-math checked-source (+ index 2) "$$" 'display-math)])
                (add-math! 'display-math body index end)
                (loop end))
              (let-values ([(body end)
                            (scan-math checked-source (add1 index) "$" 'inline-math)])
                (add-math! 'inline-math body index end)
                (loop end)))]
         [else
          (append-text! character index)
          (loop (add1 index))])])))

; normalize-text-content : (or/c string? text-content? tex-span?) -> text-content?
;; Converts shorthand or explicit content to the shared normal form.
(define (normalize-text-content value)
  (cond [(string? value) (parse-inline-text value)]
        [(text-content? value) value]
        [(tex-span? value) (explicit-tex-content value)]
        [else
         (raise-argument-error
          'normalize-text-content
          "(or/c string? text-content? tex-span?)"
          value)]))


;;;
;;; Scanner Helpers
;;;

; immutable-string : symbol? any/c -> immutable-string?
;; Copies one caller-owned string into immutable parser/model storage.
(define (immutable-string who value)
  (unless (string? value)
    (raise-argument-error who "string?" value))
  (string->immutable-string value))

; make-text-content : (listof text-run?) (or/c immutable-string? #f)
;                     (or/c immutable-string? #f) -> text-content?
;; Freezes one ordered normalized run sequence.
(define (make-text-content runs source plain-override)
  (text-content-data (immutable-list-copy runs) source plain-override))

; immutable-list-copy : list? -> immutable-list?
;; Copies the ordered public run spine without changing run occurrence identity.
(define (immutable-list-copy value)
  (cond [(null? value) '()]
        [else (cons (car value) (immutable-list-copy (cdr value)))]))

; literal-runs : immutable-string? -> (listof text-run?)
;; Splits literal content at authored hard line breaks without recognizing TeX.
(define (literal-runs source)
  (define length (string-length source))
  (let loop ([start 0] [index 0] [runs '()])
    (cond [(= index length)
           (reverse
            (if (< start length)
                (cons (text-run-data 'text
                                     (substring/immutable source start length)
                                     (substring/immutable source start length)
                                     start
                                     length)
                      runs)
                runs))]
          [(char=? (string-ref source index) #\newline)
           (define next-runs
             (if (< start index)
                 (cons (text-run-data 'text
                                      (substring/immutable source start index)
                                      (substring/immutable source start index)
                                      start
                                      index)
                       runs)
                 runs))
           (loop (add1 index) (add1 index)
                 (cons (text-run-data 'hard-break "" "\n" index (add1 index))
                       next-runs))]
          [else (loop start (add1 index) runs)])))

; explicit-tex-content : tex-span? -> text-content?
;; Converts one explicit mathematical fragment to ordinary normalized content.
(define (explicit-tex-content value)
  (make-text-content
   (list (text-run-data 'inline-math
                        (tex-span-source value)
                        (or (tex-span-plain value) (tex-span-source value))
                        0
                        (string-length (tex-span-source value))))
   #f
   #f))

; substring/immutable : string? exact-nonnegative-integer? exact-nonnegative-integer?
;                      -> immutable-string?
;; Copies one source substring into immutable model storage.
(define (substring/immutable source start end)
  (string->immutable-string (substring source start end)))

; blank-string? : string? -> boolean?
;; Reports whether source contains no non-whitespace character.
(define (blank-string? source)
  (for/and ([character (in-string source)])
    (char-whitespace? character)))

; scan-math : immutable-string? exact-nonnegative-integer? string? symbol?
;             -> (values immutable-string? exact-nonnegative-integer?)
;; Finds one matching delimiter while preserving TeX comments and source body.
(define (scan-math source start closing kind)
  (define length (string-length source))
  (define opening
    (case closing
      [("$") "$"]
      [("$$") "$$"]
      [("\\)") "\\("]
      [("\\]") "\\["]))
  (define closing-length (string-length closing))
  (define (finish end)
    (define body (substring/immutable source start end))
    (when (blank-string? body)
      (raise-inline-tex 'empty-math start end
                        "empty mathematical expression"))
    (values body (+ end closing-length)))
  (let loop ([index start] [comment? #f])
    (cond [(= index length)
           (raise-inline-tex
            (if (eq? kind 'inline-math) 'unclosed-inline-math 'unclosed-display-math)
            (- start (string-length opening))
            length
            (format "unclosed ~a beginning with ~s"
                    (if (eq? kind 'inline-math) "inline math" "display math")
                    opening))]
          [comment?
           (if (char=? (string-ref source index) #\newline)
               (loop (add1 index) #f)
               (loop (add1 index) #t))]
          [else
           (define character (string-ref source index))
           (cond
             [(and (char=? character #\%)
                   (not (tex-escaped? source index)))
              (loop (add1 index) #t)]
             [(string-prefix-at? source closing index)
              (finish index)]
             [(mismatched-closing? source index closing)
              (raise-inline-tex
               'mismatched-math-delimiter index (delimiter-end source index)
               (format "mismatched math delimiter inside expression opened by ~s" opening))]
             [(nested-opening? source index closing)
              (raise-inline-tex
               'nested-math-delimiter index (delimiter-end source index)
               "nested math delimiters are not supported; use tex-span for delimiter-like TeX")]
             [else (loop (add1 index) #f)])])))

; string-prefix-at? : string? string? exact-nonnegative-integer? -> boolean?
;; Tests a delimiter without allocating a substring.
(define (string-prefix-at? source prefix index)
  (define prefix-length (string-length prefix))
  (and (<= (+ index prefix-length) (string-length source))
       (for/and ([offset (in-range prefix-length)])
         (char=? (string-ref source (+ index offset))
                 (string-ref prefix offset)))))

; tex-escaped? : string? exact-nonnegative-integer? -> boolean?
;; Reports whether an odd immediately preceding backslash run escapes a token.
(define (tex-escaped? source index)
  (let loop ([cursor (sub1 index)] [count 0])
    (if (and (>= cursor 0)
             (char=? (string-ref source cursor) #\\))
        (loop (sub1 cursor) (add1 count))
        (odd? count))))

; mismatched-closing? : string? exact-nonnegative-integer? string? -> boolean?
;; Detects a different recognized closing delimiter before the expected one.
(define (mismatched-closing? source index expected)
  (and (not (tex-escaped? source index))
       (or (and (string-prefix-at? source "\\)" index)
                (not (string=? expected "\\)")))
           (and (string-prefix-at? source "\\]" index)
                (not (string=? expected "\\]")))
           (and (string-prefix-at? source "$$" index)
                (not (string=? expected "$$")))
           (and (char=? (string-ref source index) #\$)
                (not (string=? expected "$"))
                (not (string-prefix-at? source "$$" index))))))

; nested-opening? : string? exact-nonnegative-integer? string? -> boolean?
;; Rejects an active delimiter opening before the current expression closes.
(define (nested-opening? source index expected)
  (and (not (tex-escaped? source index))
       (or (and (string-prefix-at? source "\\(" index)
                (not (string=? expected "\\)")))
           (and (string-prefix-at? source "\\[" index)
                (not (string=? expected "\\]")))
           (and (string-prefix-at? source "$$" index)
                (not (string=? expected "$$"))))))

; delimiter-end : string? exact-nonnegative-integer? -> exact-nonnegative-integer?
;; Gives the source offset immediately after a recognized delimiter.
(define (delimiter-end source index)
  (cond [(or (string-prefix-at? source "\\)" index)
             (string-prefix-at? source "\\]" index)
             (string-prefix-at? source "$$" index))
         (+ index 2)]
        [else (add1 index)]))

; raise-inline-tex : symbol? exact-nonnegative-integer? exact-nonnegative-integer?
;                    string? -> none/c
;; Raises one source-local parse diagnostic without importing a rendering layer.
(define (raise-inline-tex code start end message)
  (raise
   (exn:fail:inline-tex
    (format "animate/text-content: ~a (characters ~a..~a)"
            message start end)
    (current-continuation-marks)
    code
    start
    end)))
