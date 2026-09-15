#lang racket/base

;;;
;;; Preparation Artifact Leases
;;;

;; Keeps active preparation artifacts pinned by explicit session leases.  The
;; manager is an effectful execution resource, not a process-global scene or
;; cache registry; callers own and release the manager with their session.


;;;
;;; Imports and Exports
;;;

;; Imports
(require racket/list
         "render-preparation-manifest.rkt")

;; Exports
(provide preparation-lease-manager?
         make-preparation-lease-manager
         preparation-lease?
         acquire-preparation-lease!
         release-preparation-lease!
         preparation-artifact-pinned?
         preparation-lease-manager-pinned-identities)


;;;
;;; Mutable Session Resource
;;;

(struct preparation-lease-manager (counts lock)
  #:transparent)

;; preparation-lease-manager owns reference counts for content-addressed
;; preparation artifacts.
;;  - counts  mutable-hash?  maps artifact identities to positive lease counts.
;;  - lock    semaphore?     serializes overlapping acquire/release operations.

(struct preparation-lease (owner identities released?)
  #:mutable
  #:transparent)

;; preparation-lease represents one active render session's artifact pins.
;;  - owner       preparation-lease-manager?  owns shared reference counts.
;;  - identities  immutable-list?              distinct artifact digest identities.
;;  - released?   box?                         prevents double release.

; make-preparation-lease-manager : -> preparation-lease-manager?
;;   Allocates an explicit empty manager for one cache/session coordinator.
(define (make-preparation-lease-manager)
  (preparation-lease-manager (make-hash) (make-semaphore 1)))

; acquire-preparation-lease! : preparation-lease-manager?
;                              (or/c render-preparation-manifest? false/c)
;                              -> preparation-lease?
;;   Pins every path-bearing artifact in one verified preparation manifest.
(define (acquire-preparation-lease! manager manifest)
  (unless (preparation-lease-manager? manager)
    (raise-argument-error
     'acquire-preparation-lease! "preparation-lease-manager?" manager))
  (unless (or (not manifest) (render-preparation-manifest? manifest))
    (raise-argument-error
     'acquire-preparation-lease!
     "(or/c render-preparation-manifest? false/c)"
     manifest))
  (define identities
    (if manifest
        (remove-duplicates
         (for/list ([artifact (in-list (hash-ref manifest 'artifacts))]
                    #:unless (eq? (hash-ref artifact 'kind 'file) 'metadata))
           (hash-ref artifact 'sha1)))
        '()))
  (call-with-semaphore
   (preparation-lease-manager-lock manager)
   (lambda ()
     (for ([identity (in-list identities)])
       (hash-update! (preparation-lease-manager-counts manager) identity add1 0))))
  (preparation-lease manager identities (box #f)))

; release-preparation-lease! : preparation-lease? -> void?
;;   Releases one session's pins without affecting another active session's lease.
(define (release-preparation-lease! lease)
  (unless (preparation-lease? lease)
    (raise-argument-error 'release-preparation-lease! "preparation-lease?" lease))
  (unless (unbox (preparation-lease-released? lease))
    (call-with-semaphore
     (preparation-lease-manager-lock (preparation-lease-owner lease))
     (lambda ()
       (for ([identity (in-list (preparation-lease-identities lease))])
         (define count
           (hash-ref (preparation-lease-manager-counts
                      (preparation-lease-owner lease)) identity 0))
         (cond
           [(<= count 1)
            (hash-remove! (preparation-lease-manager-counts
                           (preparation-lease-owner lease)) identity)]
           [else
            (hash-set! (preparation-lease-manager-counts
                        (preparation-lease-owner lease)) identity (sub1 count))]))))
    (set-box! (preparation-lease-released? lease) #t))
  (void))

; preparation-artifact-pinned? : preparation-lease-manager? string? -> boolean?
;;   Reports whether an artifact identity remains protected from eviction.
(define (preparation-artifact-pinned? manager identity)
  (unless (preparation-lease-manager? manager)
    (raise-argument-error
     'preparation-artifact-pinned? "preparation-lease-manager?" manager))
  (unless (string? identity)
    (raise-argument-error 'preparation-artifact-pinned? "string?" identity))
  (call-with-semaphore
   (preparation-lease-manager-lock manager)
   (lambda ()
     (positive? (hash-ref (preparation-lease-manager-counts manager) identity 0)))))

; preparation-lease-manager-pinned-identities : preparation-lease-manager?
;                                                -> immutable-list?
;;   Returns sorted pinned artifact identities for deterministic diagnostics/tests.
(define (preparation-lease-manager-pinned-identities manager)
  (unless (preparation-lease-manager? manager)
    (raise-argument-error
     'preparation-lease-manager-pinned-identities "preparation-lease-manager?" manager))
  (call-with-semaphore
   (preparation-lease-manager-lock manager)
   (lambda ()
     (sort (hash-keys (preparation-lease-manager-counts manager)) string<?))))
