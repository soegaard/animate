#lang racket/base

;;;
;;; Immutable Waveform Peaks
;;;

(require racket/file
         racket/list
         racket/path
         (only-in "geometry.rkt" finite-real?))

(provide (struct-out waveform-level)
         (struct-out waveform)
         waveform-from-samples
         waveform-level-for-width
         waveform->datum
         waveform-from-datum
         waveform-from-wav-file
         write-waveform-file
         read-waveform-file)

(struct waveform-level (samples-per-bucket minima maxima) #:transparent)
(struct waveform (sample-rate channels levels) #:transparent)

;; `samples` is a finite sequence of normalized mono samples.  A proxy reader
;; can down-mix PCM before calling here; keeping that effect out makes waveform
;; resolution fully deterministic and readily testable.
(define (waveform-from-samples samples
                               #:sample-rate [sample-rate 48000]
                               #:channels [channels 2]
                               #:bucket-sizes [bucket-sizes '(256 1024 4096 16384)])
  (unless (and (sequence? samples)
               (for/and ([sample samples]) (finite-real? sample)))
    (raise-argument-error 'waveform-from-samples "finite real sample sequence" samples))
  (unless (exact-positive-integer? sample-rate)
    (raise-argument-error 'waveform-from-samples "exact-positive-integer?" sample-rate))
  (unless (exact-positive-integer? channels)
    (raise-argument-error 'waveform-from-samples "exact-positive-integer?" channels))
  (unless (and (list? bucket-sizes) (pair? bucket-sizes)
               (andmap exact-positive-integer? bucket-sizes))
    (raise-argument-error 'waveform-from-samples "nonempty list of positive exact integers" bucket-sizes))
  (define data (list->vector (for/list ([sample samples]) sample)))
  (waveform sample-rate channels
            (for/list ([size (in-list (sort (remove-duplicates bucket-sizes) <))])
              (make-level data size))))

(define (make-level data size)
  (define count (vector-length data))
  (define buckets (if (zero? count) 0 (inexact->exact (ceiling (/ count size)))))
  (define minima (make-vector buckets))
  (define maxima (make-vector buckets))
  (for ([bucket (in-range buckets)])
    (define start (* bucket size))
    (define end (min count (+ start size)))
    (define first (vector-ref data start))
    (define-values (low high)
      (for/fold ([low first] [high first]) ([index (in-range (add1 start) end)])
        (define value (vector-ref data index))
        (values (min low value) (max high value))))
    (vector-set! minima bucket low)
    (vector-set! maxima bucket high))
  (waveform-level size (vector->immutable-vector minima) (vector->immutable-vector maxima)))

;; Selects the coarsest level that still yields at least one peak column for
;; each requested pixel.  Callers may use a finer fallback when the waveform
;; is shorter than the viewport.
(define (waveform-level-for-width wave width)
  (unless (waveform? wave)
    (raise-argument-error 'waveform-level-for-width "waveform?" wave))
  (unless (exact-positive-integer? width)
    (raise-argument-error 'waveform-level-for-width "exact-positive-integer?" width))
  (or (for/first ([level (in-list (reverse (waveform-levels wave)))]
                  #:when (>= (vector-length (waveform-level-minima level)) width))
        level)
      (car (waveform-levels wave))))


;;;
;;; Persistent PCM-WAV Waveforms
;;;

;; Preview proxies are deliberately emitted as 16-bit PCM WAV files. Reading
;; exactly that small, documented interchange format keeps the waveform cache
;; independent of an audio decoder, FFmpeg process, or GUI toolkit. The
;; parser accepts arbitrary chunk order and skips unknown RIFF chunks, but
;; rejects compressed or differently-sized samples with an explanatory error.

(define (waveform-from-wav-file path
                                #:bucket-sizes
                                [bucket-sizes '(256 1024 4096 16384)])
  (unless (path-string? path)
    (raise-argument-error 'waveform-from-wav-file "path-string?" path))
  (unless (file-exists? path)
    (raise-arguments-error 'waveform-from-wav-file
                           "an existing PCM WAV file" "path" path))
  (define data (file->bytes path))
  (unless (and (>= (bytes-length data) 12)
               (bytes=? (subbytes data 0 4) #"RIFF")
               (bytes=? (subbytes data 8 12) #"WAVE"))
    (raise-arguments-error 'waveform-from-wav-file
                           "a RIFF/WAVE file" "path" path))
  (define fmt #f)
  (define audio-data #f)
  (let loop ([offset 12])
    (when (<= (+ offset 8) (bytes-length data))
      (define chunk-id (subbytes data offset (+ offset 4)))
      (define chunk-size (little-u32 data (+ offset 4)))
      (define start (+ offset 8))
      (define end (+ start chunk-size))
      (unless (<= end (bytes-length data))
        (raise-arguments-error 'waveform-from-wav-file
                               "a complete RIFF chunk" "path" path))
      (cond
        [(bytes=? chunk-id #"fmt ") (set! fmt (subbytes data start end))]
        [(bytes=? chunk-id #"data") (set! audio-data (subbytes data start end))]
        [else (void)])
      ;; RIFF chunks are padded to an even byte boundary.
      (loop (+ end (modulo chunk-size 2)))))
  (unless (and fmt audio-data (>= (bytes-length fmt) 16))
    (raise-arguments-error 'waveform-from-wav-file
                           "a WAV file with fmt and data chunks" "path" path))
  (define encoding (little-u16 fmt 0))
  (define channels (little-u16 fmt 2))
  (define sample-rate (little-u32 fmt 4))
  (define bits-per-sample (little-u16 fmt 14))
  (unless (= encoding 1)
    (raise-arguments-error 'waveform-from-wav-file
                           "uncompressed PCM audio" "encoding" encoding))
  (unless (positive? channels)
    (raise-arguments-error 'waveform-from-wav-file
                           "a positive channel count" "channels" channels))
  (unless (= bits-per-sample 16)
    (raise-arguments-error 'waveform-from-wav-file
                           "16-bit PCM audio" "bits-per-sample" bits-per-sample))
  (define bytes-per-frame (* channels 2))
  (unless (zero? (modulo (bytes-length audio-data) bytes-per-frame))
    (raise-arguments-error 'waveform-from-wav-file
                           "complete interleaved PCM frames" "path" path))
  (define mono-samples
    (for/list ([offset (in-range 0 (bytes-length audio-data) bytes-per-frame)])
      (/ (for/sum ([channel (in-range channels)])
           (/ (little-s16 audio-data (+ offset (* channel 2))) 32768.0))
         channels)))
  (waveform-from-samples mono-samples
                         #:sample-rate sample-rate
                         #:channels channels
                         #:bucket-sizes bucket-sizes))

;; waveform->datum is intentionally a plain Racket datum so a proxy cache is
;; readable by the preview, a later thumbnail generator, or bug-report tools
;; without decoding audio again.
(define (waveform->datum wave)
  (unless (waveform? wave)
    (raise-argument-error 'waveform->datum "waveform?" wave))
  (hasheq 'schema 'animate-waveform-v2
          'sample-rate (waveform-sample-rate wave)
          'channels (waveform-channels wave)
          'levels
          (for/list ([level (in-list (waveform-levels wave))])
            (hasheq 'samples-per-bucket (waveform-level-samples-per-bucket level)
                    'minima (vector->list (waveform-level-minima level))
                    'maxima (vector->list (waveform-level-maxima level))))))

(define (waveform-from-datum datum)
  (unless (and (hash? datum)
               (eq? (hash-ref datum 'schema #f) 'animate-waveform-v2))
    (raise-argument-error 'waveform-from-datum
                          "an animate-waveform-v2 datum" datum))
  (define sample-rate (hash-ref datum 'sample-rate #f))
  (define channels (hash-ref datum 'channels #f))
  (define levels
    (for/list ([entry (in-list (hash-ref datum 'levels '()))])
      (unless (hash? entry)
        (raise-arguments-error 'waveform-from-datum
                               "waveform level data" "level" entry))
      (define size (hash-ref entry 'samples-per-bucket #f))
      (define minima (hash-ref entry 'minima #f))
      (define maxima (hash-ref entry 'maxima #f))
      (unless (and (exact-positive-integer? size)
                   (list? minima) (list? maxima)
                   (= (length minima) (length maxima))
                   (andmap finite-real? minima)
                   (andmap finite-real? maxima))
        (raise-arguments-error 'waveform-from-datum
                               "well-formed waveform level" "level" entry))
      (waveform-level size
                      (vector->immutable-vector (list->vector minima))
                      (vector->immutable-vector (list->vector maxima)))))
  (unless (and (exact-positive-integer? sample-rate)
               (exact-positive-integer? channels)
               (pair? levels))
    (raise-arguments-error 'waveform-from-datum
                           "a nonempty waveform with positive format values"
                           "datum" datum))
  (waveform sample-rate channels levels))

(define (write-waveform-file wave path)
  (unless (path-string? path)
    (raise-argument-error 'write-waveform-file "path-string?" path))
  (define parent (path-only (if (path? path) path (string->path path))))
  (when parent (make-directory* parent))
  (call-with-output-file path
    (lambda (out)
      (write (waveform->datum wave) out)
      (newline out))
    #:exists 'truncate/replace)
  path)

(define (read-waveform-file path)
  (unless (path-string? path)
    (raise-argument-error 'read-waveform-file "path-string?" path))
  (waveform-from-datum (call-with-input-file path read)))

(define (little-u16 bytes offset)
  (+ (bytes-ref bytes offset)
     (arithmetic-shift (bytes-ref bytes (+ offset 1)) 8)))

(define (little-u32 bytes offset)
  (+ (little-u16 bytes offset)
     (arithmetic-shift (little-u16 bytes (+ offset 2)) 16)))

(define (little-s16 bytes offset)
  (define unsigned (little-u16 bytes offset))
  (if (>= unsigned #x8000) (- unsigned #x10000) unsigned))
