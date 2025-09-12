;; Credit Escrow Service
;; Enables secure carbon credit transactions with time-locked releases and dispute resolution

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u400))
(define-constant err-invalid-amount (err u401))
(define-constant err-insufficient-balance (err u402))
(define-constant err-escrow-not-found (err u403))
(define-constant err-unauthorized (err u404))
(define-constant err-invalid-state (err u405))
(define-constant err-escrow-expired (err u406))
(define-constant err-escrow-not-expired (err u407))
(define-constant err-cannot-escrow-self (err u408))

;; escrow states
(define-constant state-pending u0)    ;; Waiting for seller acceptance
(define-constant state-active u1)     ;; Accepted, awaiting completion
(define-constant state-completed u2)  ;; Credits released to buyer
(define-constant state-disputed u3)   ;; Under dispute resolution
(define-constant state-cancelled u4)  ;; Cancelled or refunded

;; timing constants
(define-constant default-timeout u1008) ;; ~7 days in blocks
(define-constant dispute-period u432)   ;; ~3 days for dispute resolution

;; data variables
(define-data-var escrow-counter uint u0)
(define-data-var total-escrowed-credits uint u0)
(define-data-var dispute-resolution-fee uint u5) ;; 5% fee for dispute resolution

;; data maps
(define-map escrow-agreements
    uint
    {
        buyer: principal,
        seller: principal,
        credit-amount: uint,
        stx-amount: uint,
        state: uint,
        creation-time: uint,
        acceptance-time: (optional uint),
        completion-deadline: uint,
        terms: (string-ascii 200),
        dispute-reason: (optional (string-ascii 100))
    }
)

(define-map user-escrows
    principal
    (list 20 uint)
)

(define-map escrow-disputes
    uint
    {
        disputed-by: principal,
        dispute-time: uint,
        resolution: (optional bool), ;; true=buyer wins, false=seller wins
        resolved-by: (optional principal),
        resolution-time: (optional uint)
    }
)

;; public functions

;; Create new escrow agreement
(define-public (create-escrow 
    (seller principal) 
    (credit-amount uint) 
    (stx-amount uint) 
    (terms (string-ascii 200))
)
    (let (
        (buyer-balance (contract-call? .GreenEnergy get-credit-balance tx-sender))
        (escrow-id (+ (var-get escrow-counter) u1))
        (completion-deadline (+ stacks-block-height default-timeout))
        (current-escrows (default-to (list) (map-get? user-escrows tx-sender)))
    )
        (asserts! (> credit-amount u0) err-invalid-amount)
        (asserts! (> stx-amount u0) err-invalid-amount)
        (asserts! (not (is-eq tx-sender seller)) err-cannot-escrow-self)
        (asserts! (>= buyer-balance credit-amount) err-insufficient-balance)
        
        ;; Lock buyer's credits in escrow
        (try! (contract-call? .GreenEnergy transfer-credits 
            credit-amount tx-sender (as-contract tx-sender)))
        
        ;; Create escrow record
        (map-set escrow-agreements escrow-id {
            buyer: tx-sender,
            seller: seller,
            credit-amount: credit-amount,
            stx-amount: stx-amount,
            state: state-pending,
            creation-time: stacks-block-height,
            acceptance-time: none,
            completion-deadline: completion-deadline,
            terms: terms,
            dispute-reason: none
        })
        
        ;; Update counters and user tracking
        (var-set escrow-counter escrow-id)
        (var-set total-escrowed-credits (+ (var-get total-escrowed-credits) credit-amount))
        (map-set user-escrows tx-sender 
            (unwrap-panic (as-max-len? (append current-escrows escrow-id) u20)))
        
        (ok escrow-id)
    )
)

;; Seller accepts escrow terms
(define-public (accept-escrow (escrow-id uint))
    (let (
        (escrow (unwrap! (map-get? escrow-agreements escrow-id) err-escrow-not-found))
        (current-time stacks-block-height)
    )
        (asserts! (is-eq tx-sender (get seller escrow)) err-unauthorized)
        (asserts! (is-eq (get state escrow) state-pending) err-invalid-state)
        (asserts! (<= current-time (get completion-deadline escrow)) err-escrow-expired)
        
        ;; Update escrow to active state
        (map-set escrow-agreements escrow-id
            (merge escrow {
                state: state-active,
                acceptance-time: (some current-time)
            }))
        (ok true)
    )
)

;; Release credits to buyer (called by seller after service delivery)
(define-public (release-credits (escrow-id uint))
    (let (
        (escrow (unwrap! (map-get? escrow-agreements escrow-id) err-escrow-not-found))
        (buyer (get buyer escrow))
        (credit-amount (get credit-amount escrow))
        (stx-amount (get stx-amount escrow))
    )
        (asserts! (is-eq tx-sender (get seller escrow)) err-unauthorized)
        (asserts! (is-eq (get state escrow) state-active) err-invalid-state)
        
        ;; Transfer credits to buyer and STX to seller
        (try! (as-contract (contract-call? .GreenEnergy transfer-credits 
            credit-amount tx-sender buyer)))
        (try! (stx-transfer? stx-amount buyer tx-sender))
        
        ;; Mark escrow as completed
        (map-set escrow-agreements escrow-id
            (merge escrow {state: state-completed}))
        (var-set total-escrowed-credits (- (var-get total-escrowed-credits) credit-amount))
        (ok true)
    )
)

;; Initiate dispute (can be called by buyer or seller)
(define-public (dispute-escrow (escrow-id uint) (reason (string-ascii 100)))
    (let (
        (escrow (unwrap! (map-get? escrow-agreements escrow-id) err-escrow-not-found))
        (buyer (get buyer escrow))
        (seller (get seller escrow))
    )
        (asserts! (or (is-eq tx-sender buyer) (is-eq tx-sender seller)) err-unauthorized)
        (asserts! (is-eq (get state escrow) state-active) err-invalid-state)
        
        ;; Create dispute record
        (map-set escrow-disputes escrow-id {
            disputed-by: tx-sender,
            dispute-time: stacks-block-height,
            resolution: none,
            resolved-by: none,
            resolution-time: none
        })
        
        ;; Update escrow state
        (map-set escrow-agreements escrow-id
            (merge escrow {
                state: state-disputed,
                dispute-reason: (some reason)
            }))
        (ok true)
    )
)

;; Resolve dispute (owner only)
(define-public (resolve-dispute (escrow-id uint) (buyer-wins bool))
    (let (
        (escrow (unwrap! (map-get? escrow-agreements escrow-id) err-escrow-not-found))
        (dispute (unwrap! (map-get? escrow-disputes escrow-id) err-escrow-not-found))
        (buyer (get buyer escrow))
        (seller (get seller escrow))
        (credit-amount (get credit-amount escrow))
        (stx-amount (get stx-amount escrow))
        (resolution-fee (/ (* stx-amount (var-get dispute-resolution-fee)) u100))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-eq (get state escrow) state-disputed) err-invalid-state)
        
        ;; Distribute credits and STX based on resolution
        (if buyer-wins
            (begin
                ;; Buyer gets credits back, seller pays resolution fee
                (try! (as-contract (contract-call? .GreenEnergy transfer-credits 
                    credit-amount tx-sender buyer)))
                (try! (stx-transfer? resolution-fee seller contract-owner))
            )
            (begin
                ;; Seller gets credits and payment, buyer pays resolution fee
                (try! (as-contract (contract-call? .GreenEnergy transfer-credits 
                    credit-amount tx-sender seller)))
                (try! (stx-transfer? stx-amount buyer seller))
                (try! (stx-transfer? resolution-fee buyer contract-owner))
            )
        )
        
        ;; Update records
        (map-set escrow-disputes escrow-id
            (merge dispute {
                resolution: (some buyer-wins),
                resolved-by: (some tx-sender),
                resolution-time: (some stacks-block-height)
            }))
        (map-set escrow-agreements escrow-id
            (merge escrow {state: state-completed}))
        (var-set total-escrowed-credits (- (var-get total-escrowed-credits) credit-amount))
        (ok true)
    )
)

;; Cancel expired escrow (refund to buyer)
(define-public (cancel-expired-escrow (escrow-id uint))
    (let (
        (escrow (unwrap! (map-get? escrow-agreements escrow-id) err-escrow-not-found))
        (buyer (get buyer escrow))
        (credit-amount (get credit-amount escrow))
    )
        (asserts! (>= stacks-block-height (get completion-deadline escrow)) err-escrow-not-expired)
        (asserts! (is-eq (get state escrow) state-pending) err-invalid-state)
        
        ;; Refund credits to buyer
        (try! (as-contract (contract-call? .GreenEnergy transfer-credits 
            credit-amount tx-sender buyer)))
        
        ;; Mark as cancelled
        (map-set escrow-agreements escrow-id
            (merge escrow {state: state-cancelled}))
        (var-set total-escrowed-credits (- (var-get total-escrowed-credits) credit-amount))
        (ok true)
    )
)

;; read-only functions

;; Get escrow details
(define-read-only (get-escrow (escrow-id uint))
    (map-get? escrow-agreements escrow-id)
)

;; Get user's escrow list
(define-read-only (get-user-escrows (user principal))
    (default-to (list) (map-get? user-escrows user))
)

;; Get dispute details
(define-read-only (get-dispute (escrow-id uint))
    (map-get? escrow-disputes escrow-id)
)

;; Get escrow statistics
(define-read-only (get-escrow-stats)
    {
        total-escrows: (var-get escrow-counter),
        total-escrowed-credits: (var-get total-escrowed-credits),
        dispute-fee-rate: (var-get dispute-resolution-fee)
    }
)

;; Check if escrow is expired
(define-read-only (is-escrow-expired (escrow-id uint))
    (match (map-get? escrow-agreements escrow-id)
        escrow (>= stacks-block-height (get completion-deadline escrow))
        false
    )
)
