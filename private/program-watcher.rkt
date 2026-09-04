#lang racket/base

;;;
;;; Debounced, Content-Based Program Watcher
;;;

;; Native notifications are intentionally not a correctness dependency. A
;; polling watcher works reliably with atomic-save editors and synchronised
;; folders because it compares bytes, debounces bursts, and emits one callback
;; only for a genuinely changed watched-file snapshot.

(require file/sha1
         racket/async-channel
         racket/file
         racket/list
         racket/path
         "program-loader.rkt"
         "scene-program.rkt")

(provide program-watcher?
         open-program-watcher
         program-watcher-update-loader!
         program-watcher-close!)

(struct program-watcher (stop thread alive? paths)
  #:transparent)

(define (open-program-watcher loader on-change
                              #:interval [interval 1/4]
                              #:debounce [debounce 1/3])
  (unless (scene-program-loader? loader)
    (raise-argument-error 'open-program-watcher "scene-program-loader?" loader))
  (unless (procedure? on-change)
    (raise-argument-error 'open-program-watcher "procedure?" on-change))
  (check-positive-real 'open-program-watcher "interval" interval)
  (check-nonnegative-real 'open-program-watcher "debounce" debounce)
  (define stop (make-async-channel))
  (define alive? (box #t))
  (define paths (box (loader-watch-paths loader)))
  (define worker
    (thread
     (lambda ()
       (let loop ([known (paths-digest (unbox paths))])
         (define message (sync/timeout interval stop))
         (cond
           [message (set-box! alive? #f)]
           [else
            (define observed (paths-digest (unbox paths)))
            (if (equal? observed known)
                (loop known)
                ;; Wait for the final write in a save burst, then hash again.
                (let ([debounce-message (sync/timeout debounce stop)])
                  (cond
                    [debounce-message (set-box! alive? #f)]
                    [else
                     (with-handlers ([exn:fail? (lambda (_error) (void))])
                       (on-change))
                     ;; Even a syntax-error reload becomes the new observed
                     ;; content. Further callbacks wait for a further edit.
                     ;; The callback may have installed a reloaded program
                     ;; with a different declared asset set. Snapshot its new
                     ;; paths now so that declaration change itself does not
                     ;; trigger a spurious second reload.
                     (loop (paths-digest (unbox paths)))])))])))))
  (program-watcher stop worker alive? paths))

(define (program-watcher-update-loader! watcher loader)
  (unless (program-watcher? watcher)
    (raise-argument-error 'program-watcher-update-loader! "program-watcher?" watcher))
  (unless (scene-program-loader? loader)
    (raise-argument-error 'program-watcher-update-loader! "scene-program-loader?" loader))
  (set-box! (program-watcher-paths watcher) (loader-watch-paths loader))
  (void))

(define (program-watcher-close! watcher)
  (unless (program-watcher? watcher)
    (raise-argument-error 'program-watcher-close! "program-watcher?" watcher))
  (when (unbox (program-watcher-alive? watcher))
    (async-channel-put (program-watcher-stop watcher) 'stop)
    (thread-wait (program-watcher-thread watcher)))
  (void))

(define (loader-watch-paths loader)
  (define source (scene-program-loader-source-path loader))
  (define source-directory (or (path-only source) (current-directory)))
  (remove-duplicates
   (cons source
         (append*
          (for/list ([block (in-list
                              (scene-program-blocks
                               (compiled-scene-program-program
                                (scene-program-loader-compiled loader))))])
            (for/list ([asset (in-list (scene-block-spec-assets block))])
              (simplify-path (path->complete-path asset source-directory))))))))

(define (paths-digest paths)
  (for/list ([path (in-list paths)])
    (list path
          (cond
            [(file-exists? path) (sha1-bytes (file->bytes path))]
            [else 'missing]))))

(define (check-positive-real who label value)
  (unless (and (real? value) (rational? value) (positive? value))
    (raise-arguments-error who "positive finite real" label value)))

(define (check-nonnegative-real who label value)
  (unless (and (real? value) (rational? value) (>= value 0))
    (raise-arguments-error who "nonnegative finite real" label value)))
