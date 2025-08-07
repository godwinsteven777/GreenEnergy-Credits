;; Carbon Credit Retirement System
;; Enables permanent retirement of credits for verified offset claims

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-invalid-amount (err u301))
(define-constant err-insufficient-balance (err u302))
(define-constant err-certificate-not-found (err u303))
(define-constant err-unauthorized (err u304))
(define-constant err-invalid-reason (err u305))
(define-constant err-retirement-disabled (err u306))

;; retirement reasons
(define-constant reason-voluntary u1)      ;; Voluntary carbon offset
(define-constant reason-compliance u2)     ;; Regulatory compliance
(define-constant reason-corporate u3)      ;; Corporate sustainability
(define-constant reason-event u4)          ;; Event carbon neutrality
(define-constant reason-product u5)        ;; Product lifecycle offset

;; data variables
(define-data-var retirement-counter uint u0)
(define-data-var total-retired-credits uint u0)
(define-data-var total-co2-offset uint u0)    ;; Total CO2 equivalent offset in tons
(define-data-var retirement-enabled bool true)

;; data maps
(define-map retirement-certificates
    uint
    {
        retiree: principal,
        beneficiary: principal,
        amount: uint,
        reason: uint,
        retirement-time: uint,
        project-info: (string-ascii 200),
        certificate-hash: (buff 32),
        co2-equivalent: uint
    }
)

(define-map user-retirement-history
    principal
    (list 100 uint)
)

(define-map retirement-by-reason
    uint
    uint
)

(define-map annual-retirement-stats
    uint
    {
        year: uint,
        total-credits: uint,
        total-co2: uint,
        certificate-count: uint
    }
)

(define-map beneficiary-retirement-totals
    principal
    {
        total-credits: uint,
        total-co2: uint,
        certificate-count: uint,
        first-retirement: uint
    }
)

(define-map project-retirement-tracking
    (string-ascii 50)
    {
        total-retired: uint,
        retirement-count: uint,
        last-retirement: uint
    }
)

;; public functions

;; Retire credits permanently
(define-public (retire-credits 
    (amount uint) 
    (reason uint) 
    (beneficiary principal) 
    (project-info (string-ascii 200))
    (co2-equivalent uint)
)
    (let (
        (retiree-balance (contract-call? .GreenEnergy get-credit-balance tx-sender))
        (certificate-id (+ (var-get retirement-counter) u1))
        (current-year (/ stacks-block-height u52560)) ;; Approximate blocks per year
        (certificate-hash (keccak256 (concat 
            (unwrap-panic (to-consensus-buff? certificate-id))
            (concat
                (unwrap-panic (to-consensus-buff? tx-sender))
                (unwrap-panic (to-consensus-buff? stacks-block-height))
            )
        )))
    )
        (asserts! (var-get retirement-enabled) err-retirement-disabled)
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (<= reason reason-product) err-invalid-reason)
        (asserts! (>= retiree-balance amount) err-insufficient-balance)
        
        ;; Transfer credits from user to contract (effectively burning them)
        (try! (contract-call? .GreenEnergy transfer-credits amount tx-sender (as-contract tx-sender)))
        
        ;; Create retirement certificate
        (map-set retirement-certificates certificate-id {
            retiree: tx-sender,
            beneficiary: beneficiary,
            amount: amount,
            reason: reason,
            retirement-time: stacks-block-height,
            project-info: project-info,
            certificate-hash: certificate-hash,
            co2-equivalent: co2-equivalent
        })
        
        ;; Update retirement counter
        (var-set retirement-counter certificate-id)
        
        ;; Update global retirement stats
        (var-set total-retired-credits (+ (var-get total-retired-credits) amount))
        (var-set total-co2-offset (+ (var-get total-co2-offset) co2-equivalent))
        
        ;; Update retirement by reason
        (map-set retirement-by-reason reason 
            (+ (default-to u0 (map-get? retirement-by-reason reason)) amount))
        
        ;; Update user retirement history
        (let ((current-history (default-to (list) (map-get? user-retirement-history tx-sender))))
            (map-set user-retirement-history tx-sender 
                (unwrap-panic (as-max-len? (append current-history certificate-id) u100)))
        )
        
        ;; Update annual stats
        (let ((annual-stats (default-to 
            {year: current-year, total-credits: u0, total-co2: u0, certificate-count: u0}
            (map-get? annual-retirement-stats current-year)
        )))
            (map-set annual-retirement-stats current-year {
                year: current-year,
                total-credits: (+ (get total-credits annual-stats) amount),
                total-co2: (+ (get total-co2 annual-stats) co2-equivalent),
                certificate-count: (+ (get certificate-count annual-stats) u1)
            })
        )
        
        ;; Update beneficiary totals
        (let ((beneficiary-stats (default-to 
            {total-credits: u0, total-co2: u0, certificate-count: u0, first-retirement: stacks-block-height}
            (map-get? beneficiary-retirement-totals beneficiary)
        )))
            (map-set beneficiary-retirement-totals beneficiary {
                total-credits: (+ (get total-credits beneficiary-stats) amount),
                total-co2: (+ (get total-co2 beneficiary-stats) co2-equivalent),
                certificate-count: (+ (get certificate-count beneficiary-stats) u1),
                first-retirement: (get first-retirement beneficiary-stats)
            })
        )
        
        (ok certificate-id)
    )
)

;; Retire credits on behalf of another party
(define-public (retire-on-behalf 
    (amount uint) 
    (reason uint) 
    (beneficiary principal) 
    (project-info (string-ascii 200))
    (co2-equivalent uint)
    (payer principal)
)
    (let (
        (payer-balance (contract-call? .GreenEnergy get-credit-balance payer))
        (certificate-id (+ (var-get retirement-counter) u1))
    )
        (asserts! (var-get retirement-enabled) err-retirement-disabled)
        (asserts! (> amount u0) err-invalid-amount)
        (asserts! (<= reason reason-product) err-invalid-reason)
        (asserts! (>= payer-balance amount) err-insufficient-balance)
        (asserts! (is-eq tx-sender payer) err-unauthorized)
        
        ;; Call main retirement function with payer as retiree
        (retire-credits amount reason beneficiary project-info co2-equivalent)
    )
)

;; Bulk retire multiple credit amounts with different reasons
(define-public (bulk-retire-credits 
    (retirement-list (list 10 {amount: uint, reason: uint, beneficiary: principal, co2-equivalent: uint}))
    (project-info (string-ascii 200))
)
    (let (
        (total-amount (fold + (map get-amount retirement-list) u0))
        (retiree-balance (contract-call? .GreenEnergy get-credit-balance tx-sender))
    )
        (asserts! (var-get retirement-enabled) err-retirement-disabled)
        (asserts! (>= retiree-balance total-amount) err-insufficient-balance)
        
        ;; Process each retirement in the list
        (ok (map process-single-retirement retirement-list))
    )
)

;; Helper function for bulk retirement
(define-private (process-single-retirement 
    (retirement-data {amount: uint, reason: uint, beneficiary: principal, co2-equivalent: uint})
)
    (retire-credits 
        (get amount retirement-data)
        (get reason retirement-data)
        (get beneficiary retirement-data)
        ""
        (get co2-equivalent retirement-data)
    )
)

;; Helper function to get amount from retirement data
(define-private (get-amount (retirement-data {amount: uint, reason: uint, beneficiary: principal, co2-equivalent: uint}))
    (get amount retirement-data)
)

;; Update project retirement tracking
(define-public (update-project-tracking (project-id (string-ascii 50)) (retired-amount uint))
    (let (
        (project-stats (default-to 
            {total-retired: u0, retirement-count: u0, last-retirement: u0}
            (map-get? project-retirement-tracking project-id)
        ))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set project-retirement-tracking project-id {
            total-retired: (+ (get total-retired project-stats) retired-amount),
            retirement-count: (+ (get retirement-count project-stats) u1),
            last-retirement: stacks-block-height
        })
        (ok true)
    )
)

;; Toggle retirement system on/off (emergency function)
(define-public (set-retirement-status (enabled bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set retirement-enabled enabled)
        (ok true)
    )
)

;; read-only functions

;; Get retirement certificate details
(define-read-only (get-retirement-certificate (certificate-id uint))
    (map-get? retirement-certificates certificate-id)
)

;; Get user's retirement history
(define-read-only (get-user-retirement-history (user principal))
    (default-to (list) (map-get? user-retirement-history user))
)

;; Get total retirements by reason
(define-read-only (get-retirement-by-reason (reason uint))
    (default-to u0 (map-get? retirement-by-reason reason))
)

;; Get annual retirement statistics
(define-read-only (get-annual-retirement-stats (year uint))
    (map-get? annual-retirement-stats year)
)

;; Get beneficiary retirement totals
(define-read-only (get-beneficiary-totals (beneficiary principal))
    (map-get? beneficiary-retirement-totals beneficiary)
)

;; Get project retirement tracking
(define-read-only (get-project-retirement-stats (project-id (string-ascii 50)))
    (map-get? project-retirement-tracking project-id)
)

;; Get global retirement statistics
(define-read-only (get-global-retirement-stats)
    {
        total-certificates: (var-get retirement-counter),
        total-retired-credits: (var-get total-retired-credits),
        total-co2-offset: (var-get total-co2-offset),
        retirement-enabled: (var-get retirement-enabled)
    }
)

;; Get retirement reasons reference
(define-read-only (get-retirement-reasons)
    {
        voluntary: reason-voluntary,
        compliance: reason-compliance,
        corporate: reason-corporate,
        event: reason-event,
        product: reason-product
    }
)

;; Verify certificate authenticity by hash
(define-read-only (verify-certificate (certificate-id uint) (provided-hash (buff 32)))
    (match (map-get? retirement-certificates certificate-id)
        certificate (is-eq (get certificate-hash certificate) provided-hash)
        false
    )
)

;; Calculate environmental impact for a user
(define-read-only (get-user-environmental-impact (user principal))
    (let (
        (retirement-history (get-user-retirement-history user))
        (total-impact (fold calculate-certificate-impact retirement-history u0))
    )
        total-impact
    )
)

;; Helper function to calculate impact from certificate IDs
(define-private (calculate-certificate-impact (certificate-id uint) (accumulator uint))
    (match (map-get? retirement-certificates certificate-id)
        certificate (+ accumulator (get co2-equivalent certificate))
        accumulator
    )
)

;; Get retirement system status
(define-read-only (is-retirement-enabled)
    (var-get retirement-enabled)
)
