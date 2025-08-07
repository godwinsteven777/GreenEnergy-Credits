;; Carbon Credit Verification System
;; Enables third-party verification of carbon credits with reputation tracking

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-unauthorized (err u201))
(define-constant err-verifier-not-found (err u202))
(define-constant err-verifier-not-active (err u203))
(define-constant err-request-not-found (err u204))
(define-constant err-already-verified (err u205))
(define-constant err-invalid-amount (err u206))
(define-constant err-invalid-rating (err u207))
(define-constant err-verifier-exists (err u208))
(define-constant err-request-exists (err u209))

;; verification standards
(define-constant standard-vcs u1)  ;; Verified Carbon Standard
(define-constant standard-cdm u2)  ;; Clean Development Mechanism
(define-constant standard-gold u3) ;; Gold Standard
(define-constant standard-car u4)  ;; Climate Action Reserve

;; data variables
(define-data-var verifier-counter uint u0)
(define-data-var request-counter uint u0)
(define-data-var total-verified-credits uint u0)

;; data maps
(define-map verifiers
    principal
    {
        verifier-id: uint,
        name: (string-ascii 50),
        certification: (string-ascii 100),
        active: bool,
        total-verifications: uint,
        reputation-score: uint,
        registration-time: uint
    }
)

(define-map verification-requests
    uint
    {
        requester: principal,
        credit-amount: uint,
        project-id: (string-ascii 50),
        verification-standard: uint,
        metadata: (string-ascii 200),
        verifier: (optional principal),
        status: uint, ;; 0=pending, 1=approved, 2=rejected
        request-time: uint,
        completion-time: (optional uint)
    }
)

(define-map verified-credits
    {holder: principal, batch-id: uint}
    {
        amount: uint,
        verifier: principal,
        verification-standard: uint,
        verification-time: uint,
        project-metadata: (string-ascii 200),
        validity-period: uint
    }
)

(define-map verifier-ratings
    {verifier: principal, rater: principal}
    {rating: uint, timestamp: uint}
)

(define-map user-verification-history
    principal
    (list 50 uint)
)

(define-map batch-counter principal uint)

;; public functions

;; Register a new verifier (owner only)
(define-public (register-verifier 
    (verifier principal) 
    (name (string-ascii 50)) 
    (certification (string-ascii 100))
)
    (let ((verifier-id (+ (var-get verifier-counter) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? verifiers verifier)) err-verifier-exists)
        (map-set verifiers verifier {
            verifier-id: verifier-id,
            name: name,
            certification: certification,
            active: true,
            total-verifications: u0,
            reputation-score: u50, ;; start with neutral score
            registration-time: stacks-block-height
        })
        (var-set verifier-counter verifier-id)
        (ok verifier-id)
    )
)

;; Activate or deactivate a verifier (owner only)
(define-public (set-verifier-status (verifier principal) (active bool))
    (let ((verifier-info (unwrap! (map-get? verifiers verifier) err-verifier-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set verifiers verifier (merge verifier-info {active: active}))
        (ok true)
    )
)

;; Submit verification request
(define-public (submit-verification-request
    (credit-amount uint)
    (project-id (string-ascii 50))
    (verification-standard uint)
    (metadata (string-ascii 200))
)
    (let ((request-id (+ (var-get request-counter) u1)))
        (asserts! (> credit-amount u0) err-invalid-amount)
        (asserts! (<= verification-standard standard-car) err-invalid-rating)
        (map-set verification-requests request-id {
            requester: tx-sender,
            credit-amount: credit-amount,
            project-id: project-id,
            verification-standard: verification-standard,
            metadata: metadata,
            verifier: none,
            status: u0,
            request-time: stacks-block-height,
            completion-time: none
        })
        (var-set request-counter request-id)
        (ok request-id)
    )
)

;; Assign verifier to request (owner only)
(define-public (assign-verifier (request-id uint) (verifier principal))
    (let (
        (request (unwrap! (map-get? verification-requests request-id) err-request-not-found))
        (verifier-info (unwrap! (map-get? verifiers verifier) err-verifier-not-found))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (get active verifier-info) err-verifier-not-active)
        (asserts! (is-eq (get status request) u0) err-already-verified)
        (map-set verification-requests request-id 
            (merge request {verifier: (some verifier)}))
        (ok true)
    )
)

;; Complete verification (verifier only)
(define-public (complete-verification 
    (request-id uint) 
    (approved bool) 
    (validity-period uint)
)
    (let (
        (request (unwrap! (map-get? verification-requests request-id) err-request-not-found))
        (verifier-info (unwrap! (map-get? verifiers tx-sender) err-verifier-not-found))
        (requester (get requester request))
        (batch-id (+ (default-to u0 (map-get? batch-counter requester)) u1))
        (status (if approved u1 u2))
    )
        (asserts! (get active verifier-info) err-verifier-not-active)
        (asserts! (is-eq (some tx-sender) (get verifier request)) err-unauthorized)
        (asserts! (is-eq (get status request) u0) err-already-verified)
        
        ;; Update request status
        (map-set verification-requests request-id 
            (merge request {
                status: status,
                completion-time: (some stacks-block-height)
            }))
        
        ;; If approved, create verified credit entry
        (if approved
            (begin
                (map-set verified-credits {holder: requester, batch-id: batch-id} {
                    amount: (get credit-amount request),
                    verifier: tx-sender,
                    verification-standard: (get verification-standard request),
                    verification-time: stacks-block-height,
                    project-metadata: (get metadata request),
                    validity-period: validity-period
                })
                (map-set batch-counter requester batch-id)
                (var-set total-verified-credits 
                    (+ (var-get total-verified-credits) (get credit-amount request)))
                
                ;; Update verifier stats
                (map-set verifiers tx-sender 
                    (merge verifier-info {
                        total-verifications: (+ (get total-verifications verifier-info) u1)
                    }))
                
                ;; Update user history
                (let ((current-history (default-to (list) (map-get? user-verification-history requester))))
                    (map-set user-verification-history requester 
                        (unwrap-panic (as-max-len? (append current-history request-id) u50)))
                )
            )
            true
        )
        (ok approved)
    )
)

;; Rate a verifier (after successful verification)
(define-public (rate-verifier (verifier principal) (rating uint))
    (let (
        (verifier-info (unwrap! (map-get? verifiers verifier) err-verifier-not-found))
        (current-score (get reputation-score verifier-info))
        (total-verifications (get total-verifications verifier-info))
        (new-score (if (> total-verifications u0)
            (/ (+ (* current-score total-verifications) rating) (+ total-verifications u1))
            rating))
    )
        (asserts! (<= rating u100) err-invalid-rating)
        (asserts! (> rating u0) err-invalid-rating)
        
        ;; Store individual rating
        (map-set verifier-ratings {verifier: verifier, rater: tx-sender} {
            rating: rating,
            timestamp: stacks-block-height
        })
        
        ;; Update verifier reputation score
        (map-set verifiers verifier 
            (merge verifier-info {reputation-score: new-score}))
        (ok true)
    )
)

;; Transfer verified credits
(define-public (transfer-verified-credits 
    (batch-id uint) 
    (amount uint) 
    (recipient principal)
)
    (let (
        (credit-info (unwrap! (map-get? verified-credits {holder: tx-sender, batch-id: batch-id}) err-request-not-found))
        (current-amount (get amount credit-info))
        (new-recipient-batch (+ (default-to u0 (map-get? batch-counter recipient)) u1))
    )
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (>= current-amount amount) err-invalid-amount)
        
        ;; Update sender's batch
        (if (is-eq current-amount amount)
            (map-delete verified-credits {holder: tx-sender, batch-id: batch-id})
            (map-set verified-credits {holder: tx-sender, batch-id: batch-id}
                (merge credit-info {amount: (- current-amount amount)}))
        )
        
        ;; Create new batch for recipient
        (map-set verified-credits {holder: recipient, batch-id: new-recipient-batch}
            (merge credit-info {amount: amount}))
        (map-set batch-counter recipient new-recipient-batch)
        (ok true)
    )
)

;; read-only functions

;; Get verifier information
(define-read-only (get-verifier (verifier principal))
    (map-get? verifiers verifier)
)

;; Get verification request details
(define-read-only (get-verification-request (request-id uint))
    (map-get? verification-requests request-id)
)

;; Get verified credit batch
(define-read-only (get-verified-credits (holder principal) (batch-id uint))
    (map-get? verified-credits {holder: holder, batch-id: batch-id})
)

;; Get user's verification history
(define-read-only (get-user-verification-history (user principal))
    (default-to (list) (map-get? user-verification-history user))
)

;; Get verifier rating from specific rater
(define-read-only (get-verifier-rating (verifier principal) (rater principal))
    (map-get? verifier-ratings {verifier: verifier, rater: rater})
)

;; Get verification statistics
(define-read-only (get-verification-stats)
    {
        total-verifiers: (var-get verifier-counter),
        total-requests: (var-get request-counter),
        total-verified-credits: (var-get total-verified-credits)
    }
)

;; Check if credits are still valid
(define-read-only (is-verification-valid (holder principal) (batch-id uint))
    (match (map-get? verified-credits {holder: holder, batch-id: batch-id})
        credit-info (let (
            (verification-time (get verification-time credit-info))
            (validity-period (get validity-period credit-info))
            (expiry-time (+ verification-time validity-period))
        )
            (some (>= expiry-time stacks-block-height)))
        none
    )
)

;; Get user's current batch counter
(define-read-only (get-user-batch-counter (user principal))
    (default-to u0 (map-get? batch-counter user))
)

;; Get verification standards info
(define-read-only (get-verification-standards)
    {
        vcs: standard-vcs,
        cdm: standard-cdm,
        gold: standard-gold,
        car: standard-car
    }
)
